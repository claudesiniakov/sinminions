import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

/// Команды терминала среднего режима.
enum ConsoleCommand: Int, CaseIterable, Identifiable {
    case spotlight, chat, nap, hide, corner, unlock, resetLayout, settings
    var id: Int { rawValue }

    func title(unlocked: Bool) -> String {
        switch self {
        case .spotlight: return "ПОИСК SPOTLIGHT"
        case .chat: return "ЧАТ С GIGACHAT"
        case .nap: return "УСЫПИТЬ НА 1 ЧАС"
        case .hide: return "СКРЫТЬ"
        case .corner: return "ВЕРНУТЬ В УГОЛ"
        case .unlock: return unlocked ? "ЗАБЛОКИРОВАТЬ ОКНА" : "РАЗБЛОКИРОВАТЬ ОКНА"
        case .resetLayout: return "СБРОСИТЬ РАСКЛАДКУ"
        case .settings: return "НАСТРОЙКИ"
        }
    }
}

/// Замер состояния Mac для окна мониторинга.
struct SystemSnapshot: Equatable {
    var cpu: Double?
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var battery: Int?
    var onAC = false
    var netDown: Double = 0
    var netUp: Double = 0
    var uptime: Double = 0
    var thermal: ProcessInfo.ThermalState = .nominal
}

/// Читает простые метрики системы; скорости считаются между соседними замерами.
@MainActor
final class SystemMonitor {
    private var lastTicks: CPUTicks?
    private var lastNet: InterfaceCounters?
    private var lastTime: Double?

    func reset() {
        lastTicks = nil
        lastNet = nil
        lastTime = nil
    }

    func sample() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        let time = ProcessInfo.processInfo.systemUptime

        let ticks = Self.cpuTicks()
        if let old = lastTicks, let ticks { snapshot.cpu = CPUTicks.usage(from: old, to: ticks) }
        lastTicks = ticks

        let net = NetworkCounters.physicalTotal(NetworkCounters.counters())
        if let old = lastNet, let before = lastTime {
            let rate = NetworkCounters.rate(from: old, to: net, seconds: time - before)
            snapshot.netDown = rate.rx
            snapshot.netUp = rate.tx
        }
        lastNet = net
        lastTime = time

        snapshot.memoryTotal = ProcessInfo.processInfo.physicalMemory
        snapshot.memoryUsed = Self.memoryUsed() ?? 0

        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage {
            snapshot.diskTotal = UInt64(max(total, 0))
            snapshot.diskUsed = UInt64(max(Int64(total) - free, 0))
        }

        if let power = Self.battery() {
            snapshot.battery = power.percent
            snapshot.onAC = power.onAC
        }
        snapshot.uptime = time
        snapshot.thermal = ProcessInfo.processInfo.thermalState
        return snapshot
    }

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Порядок состояний: user, system, idle, nice.
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// Занятая память: активные, закреплённые и сжатые страницы.
    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(max(sysconf(_SC_PAGESIZE), 0))
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * page
    }

    private static func battery() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            let onAC = description["Power Source State"] as? String == "AC Power"
            return (maximum > 0 ? current * 100 / maximum : current, onAC)
        }
        return nil
    }
}

/// Строка списка подключений для блока лимитов.
struct LLMConnectionRow: Identifiable, Equatable {
    let connection: LLMConnection
    let isActive: Bool
    var id: UUID { connection.id }
}

/// Окна среднего режима.
enum ConsoleWindow { case terminal, monitor }

enum GesturePhase { case began, changed, ended }

/// Что пользователь делает с окном: замок, перемещение за заголовок, изменение размера за уголок.
enum LayoutEvent {
    case toggleLock
    case move(GesturePhase)
    case resize(GesturePhase)
}

enum ChatEntryKind { case user, assistant, error, info }

struct ChatEntry: Identifiable, Equatable {
    let id = UUID()
    let kind: ChatEntryKind
    let text: String
    /// Кто ответил (для реплик модели): название провайдера на момент ответа.
    var speaker: String? = nil
}

/// Переписка в терминале: журнал на экране и история для модели.
@MainActor
@Observable
final class ChatSession {
    static let systemPrompt = "Ты — Moth, призрак-компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в духе терминала Fallout, без эмодзи."

    var entries: [ChatEntry] = []
    var input = ""
    /// Растёт, когда нужно вернуть фокус в строку ввода.
    var focusTick = 0
    private(set) var isSending = false

    @ObservationIgnored var send: @MainActor ([ChatMessage]) async throws -> String = { _ in throw LLMError.noCredentials }
    @ObservationIgnored var hasCredentials: () -> Bool = { false }
    @ObservationIgnored var needCredentials: () -> Void = {}
    @ObservationIgnored var speaker: () -> String = { "LLM" }
    @ObservationIgnored private var history = [ChatMessage(.system, ChatSession.systemPrompt)]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Меняется при сбросе и отмене: ответ на устаревший запрос не попадает в журнал.
    @ObservationIgnored private var generation = 0

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        if text == "/clear" || text == "/очистить" {
            reset()
            entries = [ChatEntry(kind: .info, text: "ИСТОРИЯ ОЧИЩЕНА")]
            return
        }
        guard hasCredentials() else {
            entries.append(ChatEntry(kind: .info, text: "НЕТ ПОДКЛЮЧЕНИЯ С КЛЮЧОМ — ОТКРЫВАЮ НАСТРОЙКИ"))
            needCredentials()
            return
        }
        entries.append(ChatEntry(kind: .user, text: text))
        history.append(ChatMessage(.user, text))
        isSending = true
        let snapshot = history
        let mine = generation
        let who = speaker()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await self.send(snapshot)
                guard mine == self.generation else { return }
                self.history.append(ChatMessage(.assistant, answer))
                self.entries.append(ChatEntry(kind: .assistant, text: answer, speaker: who))
            } catch {
                guard mine == self.generation else { return }
                // Неудавшийся вопрос из истории убираем, чтобы его можно было задать заново.
                self.history.removeLast()
                if !(error is CancellationError) {
                    self.entries.append(ChatEntry(kind: .error, text: error.localizedDescription))
                }
            }
            self.isSending = false
        }
    }

    func addInfo(_ text: String) {
        entries.append(ChatEntry(kind: .info, text: text))
    }

    /// Терминал закрыт во время запроса: ответ уже не нужен.
    func cancel() {
        guard isSending else { return }
        generation += 1
        task?.cancel()
        task = nil
        history.removeLast()
        isSending = false
        entries.append(ChatEntry(kind: .info, text: "ЗАПРОС ПРЕРВАН"))
    }

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        isSending = false
        history = [ChatMessage(.system, Self.systemPrompt)]
        entries = []
    }

    /// Для снимка в CI: готовая переписка без обращения к сети.
    func loadDemo() {
        entries = [
            ChatEntry(kind: .user, text: "привет, как дела?"),
            ChatEntry(kind: .assistant, text: "всё под контролем, смотритель. радиация в норме, периметр чист. текст можно выделить мышью и скопировать по ⌘C.", speaker: "GIGACHAT"),
            ChatEntry(kind: .user, text: "а если без шуток?"),
            ChatEntry(kind: .error, text: "Сервис GigaChat недоступен (503)"),
        ]
    }
}

@MainActor
@Observable
final class ConsoleModel {
    enum Screen { case menu, chat }

    var screen = Screen.menu
    let chat = ChatSession()
    var selected = 0
    /// Выбранное подключение к нейросети («интеллект») — для монитора и заголовка чата.
    var llmName: String?
    var llmModelName: String?
    var llmPosition = ""
    var llmCount = 0
    var llmConnections: [LLMConnectionRow] = []
    let limits = LimitsStore()
    /// Окна разблокированы: их можно двигать и менять их размер.
    var unlocked = false
    @ObservationIgnored var layoutEvent: (ConsoleWindow, LayoutEvent) -> Void = { _, _ in }
    @ObservationIgnored var switchConnection: (Int) -> Void = { _ in }
    var snapshot = SystemSnapshot()
    @ObservationIgnored var run: (ConsoleCommand) -> Void = { _ in }

    func move(_ delta: Int) {
        let count = ConsoleCommand.allCases.count
        selected = (selected + delta + count) % count
    }

    func runSelected() {
        if let command = ConsoleCommand(rawValue: selected) { run(command) }
    }
}

// MARK: - Оформление терминала

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum Term {
    static let body = Color(nsColor: CompanionView.Palette.body)
    static let bodyStroke = Color(nsColor: CompanionView.Palette.bodyStroke)
    static let pupil = Color(nsColor: CompanionView.Palette.pupil)
    static let amber = Color(red: 1, green: 0.69, blue: 0.2)
    static let green = Color(nsColor: CompanionView.Palette.green)
    static let dim = Color(nsColor: CompanionView.Palette.greenDim)
    static let dark = Color(nsColor: CompanionView.Palette.greenDark)
    static let background = Color(nsColor: CompanionView.Palette.rgb(0x0b0f0a))
    static let font = Font.system(size: 13, design: .monospaced)
    static let small = Font.system(size: 11, design: .monospaced)
}

/// Рамка окна терминала: тёмный фон, зелёная рамка, строки развёртки, заголовок.
private struct TerminalFrame<Content: View>: View {
    let title: String
    let window: ConsoleWindow
    var model: ConsoleModel
    @ViewBuilder var content: Content

    @State private var moving = false
    @State private var resizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Term.small)
                    .tracking(1)
                    .foregroundStyle(Term.dim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(model.unlocked ? "[ЗАМОК ВЫКЛ]" : "[ЗАМОК ВКЛ]")
                    .font(Term.small)
                    .foregroundStyle(model.unlocked ? Term.green : Term.dim)
                    .contentShape(Rectangle())
                    .onTapGesture { model.layoutEvent(window, .toggleLock) }
                    .help(model.unlocked ? "Заблокировать окна" : "Разблокировать: окна можно двигать и менять их размер")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            // Двигать окно можно только разблокированным и только за заголовок.
            .gesture(moveGesture, including: model.unlocked ? .all : .subviews)
            Rectangle().fill(Term.dark).frame(height: 1)
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Term.background.opacity(0.96))
        .overlay {
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                    y += 3
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(
            // Разблокированное окно обведено пунктиром.
            Rectangle().strokeBorder(
                model.unlocked ? Term.green : Term.dim,
                style: StrokeStyle(lineWidth: 1, dash: model.unlocked ? [5, 3] : [])
            )
            .allowsHitTesting(false)
        )
        .overlay(alignment: .bottomTrailing) {
            if model.unlocked {
                Text("◢")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Term.green)
                    .padding(4)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture)
                    .help("Потяните, чтобы изменить размер")
            }
        }
        .shadow(color: Term.green.opacity(0.35), radius: 8)
        .padding(10)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                model.layoutEvent(window, .move(moving ? .changed : .began))
                moving = true
            }
            .onEnded { _ in
                model.layoutEvent(window, .move(.ended))
                moving = false
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                model.layoutEvent(window, .resize(resizing ? .changed : .began))
                resizing = true
            }
            .onEnded { _ in
                model.layoutEvent(window, .resize(.ended))
                resizing = false
            }
    }
}

struct TerminalView: View {
    var model: ConsoleModel

    var body: some View {
        switch model.screen {
        case .menu: menu
        case .chat: ChatScreen(model: model)
        }
    }

    private var menu: some View {
        TerminalFrame(title: "MOTH-OS // ТЕРМИНАЛ", window: .terminal, model: model) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ConsoleCommand.allCases) { command in
                    let active = model.selected == command.rawValue
                    HStack(spacing: 8) {
                        Text(active ? ">" : " ")
                        Text(command.title(unlocked: model.unlocked))
                        Spacer(minLength: 0)
                    }
                    .font(Term.font)
                    .foregroundStyle(active ? Term.background : Term.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(active ? Term.green : Color.clear)
                    .shadow(color: active ? .clear : Term.green.opacity(0.5), radius: 3)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { model.selected = command.rawValue }
                    }
                    .onTapGesture {
                        model.selected = command.rawValue
                        model.runSelected()
                    }
                }
                Spacer(minLength: 6)
                Text("↑↓ ВЫБОР · ENTER · +/− LLM · ESC ВЫХОД")
                    .font(Term.small)
                    .foregroundStyle(Term.dim)
            }
        }
    }
}

/// Экран чата: журнал, строка ввода, подсказка.
private struct ChatScreen: View {
    var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var chat = model.chat
        TerminalFrame(title: "MOTH-OS // " + ([model.llmName, model.llmModelName].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "НЕЙРОСЕТЬ").uppercased(), window: .terminal, model: model) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if chat.entries.isEmpty {
                                Text("ВВЕДИТЕ СООБЩЕНИЕ. /clear — ОЧИСТИТЬ ИСТОРИЮ.")
                                    .foregroundStyle(Term.dim)
                            }
                            if !chat.entries.isEmpty {
                                // Весь журнал — один текст: выделять можно мышью через несколько реплик, ⌘C копирует.
                                Text(log(chat))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if chat.isSending {
                                Text("ОЖИДАНИЕ ОТВЕТА…").foregroundStyle(Term.dim)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: chat.entries.count) { scroll(proxy, chat) }
                    .onChange(of: chat.isSending) { scroll(proxy, chat) }
                }
                Rectangle().fill(Term.dark).frame(height: 1)
                HStack(spacing: 6) {
                    Text(">")
                    TextField("", text: $chat.input)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { chat.submit() }
                }
                .foregroundStyle(Term.green)
                Text("ENTER ОТПРАВИТЬ · ESC НАЗАД")
                    .foregroundStyle(Term.dim)
            }
            .font(Term.small)
            .tint(Term.green)
        }
        .onAppear { focused = true }
        .onChange(of: chat.focusTick) { focused = true }
    }

    /// Журнал одной строкой с цветом по видам реплик.
    private func log(_ chat: ChatSession) -> AttributedString {
        var result = AttributedString()
        for (index, entry) in chat.entries.enumerated() {
            var line: AttributedString
            switch entry.kind {
            case .user:
                line = AttributedString("> " + entry.text)
                line.foregroundColor = Term.green
            case .assistant:
                line = AttributedString((entry.speaker ?? "LLM") + ": " + entry.text)
                line.foregroundColor = Term.green
            case .error:
                line = AttributedString("ОШИБКА: " + entry.text)
                line.foregroundColor = Term.amber
            case .info:
                line = AttributedString(entry.text)
                line.foregroundColor = Term.dim
            }
            result += line
            if index < chat.entries.count - 1 { result += AttributedString("\n\n") }
        }
        return result
    }

    private func scroll(_ proxy: ScrollViewProxy, _ chat: ChatSession) {
        proxy.scrollTo("end", anchor: .bottom)
    }
}

/// Призрак Moth для монитора: тот же контур, что и у персонажа на экране.
private struct GhostFigure: View {
    var body: some View {
        Canvas { context, size in
            let k = size.width / MothShape.size.width
            let transform = CGAffineTransform(scaleX: k, y: k)
            let body = Path(MothShape.body(transform))
            context.fill(body, with: .color(Term.body))
            context.stroke(body, with: .color(Term.bodyStroke), lineWidth: 1.5 * k)
            for center in MothShape.eyeCenters {
                context.fill(Path(MothShape.ellipse(center: center, radii: MothShape.eyeRadii, transform)), with: .color(Term.green))
            }
            for center in MothShape.shineCenters {
                context.fill(Path(MothShape.ellipse(center: center, radii: CGSize(width: 1, height: 1), transform)), with: .color(Term.pupil))
            }
        }
        .aspectRatio(MothShape.size.width / MothShape.size.height, contentMode: .fit)
        .shadow(color: Term.green.opacity(0.6), radius: 8)
    }
}

struct MonitorView: View {
    var model: ConsoleModel

    private func fraction(_ part: UInt64, _ whole: UInt64) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }

    private var thermal: String {
        switch model.snapshot.thermal {
        case .nominal: return "НОРМА"
        case .fair: return "ПОВЫШЕН"
        case .serious: return "ВЫСОКИЙ"
        case .critical: return "КРИТИЧЕСКИЙ"
        @unknown default: return "—"
        }
    }

    /// Призрак вместо человечка Pip-Boy и переключатель «интеллекта»: «−» и «+» меняют подключение.
    /// Порядок подключений и модель задаются в настройках.
    private var intelligence: some View {
        VStack(spacing: 6) {
            GhostFigure()
                .frame(width: 72, height: 84)
            Text("ИНТЕЛЛЕКТ")
                .foregroundStyle(Term.dim)
            HStack(spacing: 10) {
                stepButton("−", enabled: model.llmCount > 1) { model.switchConnection(-1) }
                VStack(spacing: 1) {
                    Text((model.llmName ?? "НЕТ ПОДКЛЮЧЕНИЙ").uppercased())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let modelName = model.llmModelName {
                        Text(modelName.uppercased())
                            .foregroundStyle(Term.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if !model.llmPosition.isEmpty {
                        Text(model.llmPosition).foregroundStyle(Term.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                stepButton("+", enabled: model.llmCount > 1) { model.switchConnection(1) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Text(symbol)
            .frame(width: 26, height: 26)
            .overlay(Rectangle().strokeBorder(enabled ? Term.green : Term.dark, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }

    /// Остаток токенов или средств по каждому подключению: название и остаток, под ними модель.
    /// Выбранное подключение подсвечено; длинный список прокручивается.
    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ЛИМИТЫ").foregroundStyle(Term.dim)
            if model.llmConnections.isEmpty {
                Text("ПОДКЛЮЧЕНИЙ НЕТ").foregroundStyle(Term.dim)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.llmConnections) { item in limitRow(item) }
                    }
                }
                .frame(height: min(CGFloat(model.llmConnections.count) * 31, 96))
            }
        }
    }

    private func limitRow(_ item: LLMConnectionRow) -> some View {
        let state = model.limits.state(for: item.connection) ?? .loading
        let text: String
        var warning = false
        switch state {
        case .loading: text = "…"
        case let .value(value): text = value
        case let .failed(reason): text = reason; warning = true
        case .noKey: text = "нет ключа"; warning = true
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Название имеет приоритет: сжимается значение справа, а не оно.
                Text((item.isActive ? "▸ " : "  ") + item.connection.name.uppercased())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(text.uppercased())
                    .foregroundStyle(warning ? Term.amber : (item.isActive ? Term.green : Term.dim))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text("  " + item.connection.model.uppercased())
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(item.isActive ? Term.green : Term.dim)
    }

    private func gauge(_ label: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer(minLength: 4)
                Text(value)
            }
            Text(Gauge.bar(fraction, width: 30))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 4)
            Text(value)
        }
    }

    var body: some View {
        let s = model.snapshot
        TerminalFrame(title: "СИСТЕМА // МОНИТОР", window: .monitor, model: model) {
            // Если окно сделали ниже содержимого, оно прокручивается.
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                intelligence
                Rectangle().fill(Term.dark).frame(height: 1)
                gauge("ЦП", s.cpu.map { Gauge.percent($0) } ?? "…", s.cpu ?? 0)
                gauge("ПАМЯТЬ", "\(MetricFormat.bytes(s.memoryUsed)) / \(MetricFormat.bytes(s.memoryTotal))",
                      fraction(s.memoryUsed, s.memoryTotal))
                gauge("ДИСК", "\(MetricFormat.bytes(s.diskUsed)) / \(MetricFormat.bytes(s.diskTotal))",
                      fraction(s.diskUsed, s.diskTotal))
                if let battery = s.battery {
                    gauge(s.onAC ? "БАТАРЕЯ ⚡" : "БАТАРЕЯ", "\(battery)%", Double(battery) / 100)
                }
                Rectangle().fill(Term.dark).frame(height: 1)
                line("СЕТЬ ↓", MetricFormat.rate(s.netDown))
                line("СЕТЬ ↑", MetricFormat.rate(s.netUp))
                line("НАГРЕВ", thermal)
                line("В РАБОТЕ", MetricFormat.uptime(s.uptime))
                Rectangle().fill(Term.dark).frame(height: 1)
                limitsBlock
            }
            .font(Term.small)
            .foregroundStyle(Term.green)
            .shadow(color: Term.green.opacity(0.45), radius: 3)
            }
        }
    }
}

// MARK: - Окна

/// Окно терминала: принимает клавиатуру, не активируя приложение.
final class ConsolePanel: NSPanel {
    var onKey: (UInt16) -> Bool = { _ in false }
    /// Что скопировать по ⌘C, если ничего не выделено.
    var copyFallback: () -> String? = { nil }

    /// Куда вставить текст, если строка ввода не в фокусе.
    var pasteFallback: (String) -> Void = { _ in }

    /// У приложения без значка в Dock нет меню «Правка», поэтому сочетания ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z
    /// обрабатываем сами, отправляя действие тому, кто сейчас в фокусе.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if flags == [.command, .shift] {
            if key == "z", NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c":
            let board = NSPasteboard.general
            let before = board.changeCount
            _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            // Выделения нет — копируем последний ответ модели.
            if board.changeCount == before, let text = copyFallback() {
                board.clearContents()
                board.setString(text, forType: .string)
            }
            return true
        case "x":
            if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
        case "v":
            if let editor = firstResponder as? NSTextView, editor.isEditable,
               NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            // Строка ввода не в фокусе (например, выделяли текст журнала): вставляем в неё напрямую.
            if let text = NSPasteboard.general.string(forType: .string) { pasteFallback(text) }
            return true
        case "a":
            if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
        case "z":
            if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !onKey(event.keyCode) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKey(53)
    }
}

/// Терминал и монитор среднего режима.
@MainActor
final class ConsoleController: NSObject, NSWindowDelegate {
    /// Поля вокруг видимой части окна под свечение (10 pt с каждой стороны). Размеры и положения
    /// ниже и в раскладке — видимой части; окну ОС добавляются поля.
    static let padding: CGFloat = 10
    static let terminalSize = CGSize(width: 440, height: 580)
    static let monitorSize = CGSize(width: 280, height: 580)
    static let terminalMinSize = CGSize(width: 340, height: 240)
    static let monitorMinSize = CGSize(width: 240, height: 300)

    let model = ConsoleModel()
    private let terminal: ConsolePanel
    private let monitor: NSPanel
    private let sampler = SystemMonitor()
    private var timer: Timer?
    private(set) var isOpen = false

    var onCommand: (ConsoleCommand) -> Void = { _ in }
    /// Область экрана, в которой можно двигать окна.
    var areaProvider: () -> CGRect = { .zero }
    /// Занятое призраком место (с запасом на парение и свечение): окна на него не наезжают.
    var ghostRect: CGRect = .zero
    /// Раскладка по умолчанию — к ней возвращает «Сбросить раскладку».
    var defaultRects: (terminal: CGRect, monitor: CGRect) = (.zero, .zero)

    private struct DragSession {
        let window: ConsoleWindow
        let resize: Bool
        let startMouse: CGPoint
        let startRect: CGRect
    }
    private var session: DragSession?
    /// Esc или щелчок мимо терминала.
    var onDismiss: () -> Void = {}

    override init() {
        terminal = ConsolePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        monitor = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        for panel in [terminal, monitor] {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.alphaValue = 0
        }
        // Окно мониторинга принимает щелчки по «+» и «−», но не забирает фокус у терминала.
        monitor.ignoresMouseEvents = false
        terminal.contentView = NSHostingView(rootView: TerminalView(model: model))
        monitor.contentView = NSHostingView(rootView: MonitorView(model: model))
        terminal.delegate = self
        terminal.onKey = { [weak self] code in self?.handleKey(code) ?? false }
        terminal.copyFallback = { [weak self] in
            self?.model.chat.entries.last(where: { $0.kind == .assistant })?.text
        }
        terminal.pasteFallback = { [weak self] text in
            guard let self, self.model.screen == .chat else { return }
            // Строка ввода однострочная: переводы строк заменяем пробелами.
            self.model.chat.input += text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            self.model.chat.focusTick += 1
        }
        model.run = { [weak self] command in self?.onCommand(command) }
        model.layoutEvent = { [weak self] window, event in self?.handleLayout(window, event) }
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        terminal.collectionBehavior = behavior
        monitor.collectionBehavior = behavior
    }

    /// Видимая часть окна (без полей под свечение).
    private func visual(_ panel: NSPanel) -> CGRect {
        panel.frame.insetBy(dx: Self.padding, dy: Self.padding)
    }

    private func panel(for window: ConsoleWindow) -> NSPanel {
        window == .terminal ? terminal : monitor
    }

    private func setVisual(_ rect: CGRect, of panel: NSPanel, animated: Bool = false) {
        let frame = rect.insetBy(dx: -Self.padding, dy: -Self.padding)
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// Приложение, которое было активным до чата: ему возвращается фокус, когда терминал закрывают.
    private var previousApp: NSRunningApplication?

    /// Окно терминала не активирует приложение, а клавиатура идёт в активное — поэтому в нём нельзя печатать.
    /// Входя в чат, делаем приложение активным и возвращаем фокус в строку ввода.
    func activateForTyping() {
        guard isOpen, !NSApp.isActive else {
            model.chat.focusTick += 1
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        terminal.makeKeyAndOrderFront(nil)
        model.chat.focusTick += 1
    }

    /// Для CI: состояние фокуса окна терминала.
    func debugState() -> String {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let responder = terminal.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        return "active=\(NSApp.isActive) key=\(terminal.isKeyWindow) fr=\(responder) front=\(front)"
    }

    /// Для CI: нажатия клавиш, отправленные прямо в окно терминала (мимо системы).
    func sendKeysForDemo(_ text: String) {
        for character in text {
            let string = String(character)
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: terminal.windowNumber, context: nil, characters: string,
                charactersIgnoringModifiers: string, isARepeat: false, keyCode: 0
            ) else { continue }
            terminal.sendEvent(event)
        }
    }

    /// Терминал закрыт: фокус возвращается приложению, из которого его открыли.
    private func restorePreviousApp() {
        guard let previous = previousApp else { return }
        previousApp = nil
        if NSApp.isActive { previous.activate() }
    }

    func setUnlocked(_ value: Bool) {
        guard model.unlocked != value else { return }
        model.unlocked = value
        session = nil
    }

    func resetLayout() {
        ConsoleLayoutStore.clear()
        setVisual(defaultRects.terminal, of: terminal, animated: true)
        setVisual(defaultRects.monitor, of: monitor, animated: true)
    }

    private func saveLayout() {
        ConsoleLayoutStore.save(terminal: visual(terminal), monitor: visual(monitor))
    }

    private func handleLayout(_ window: ConsoleWindow, _ event: LayoutEvent) {
        switch event {
        case .toggleLock: setUnlocked(!model.unlocked)
        case let .move(phase): drag(window, resize: false, phase)
        case let .resize(phase): drag(window, resize: true, phase)
        }
    }

    /// Перемещение и изменение размера: положение мыши берётся с экрана, а не из жеста, потому что
    /// окно двигается вместе с курсором. Окна не наезжают друг на друга и на призрака.
    private func drag(_ window: ConsoleWindow, resize: Bool, _ phase: GesturePhase) {
        guard model.unlocked else { return }
        let target = panel(for: window)
        switch phase {
        case .began:
            session = DragSession(window: window, resize: resize, startMouse: NSEvent.mouseLocation, startRect: visual(target))
        case .changed:
            guard let current = session, current.window == window else { return }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - current.startMouse.x
            let dy = mouse.y - current.startMouse.y
            let other = visual(panel(for: window == .terminal ? .monitor : .terminal))
            let obstacles = [other, ghostRect]
            let result: CGRect?
            if current.resize {
                result = Layout.resizedWindow(
                    from: current.startRect,
                    to: CGSize(width: current.startRect.width + dx, height: current.startRect.height - dy),
                    avoiding: obstacles, in: areaProvider(),
                    minSize: window == .terminal ? Self.terminalMinSize : Self.monitorMinSize
                )
            } else {
                result = Layout.placeWindow(current.startRect.offsetBy(dx: dx, dy: dy), avoiding: obstacles, in: areaProvider())
            }
            // Нет подходящего места — окно остаётся там, где было.
            if let result, result != visual(target) { setVisual(result, of: target) }
        case .ended:
            session = nil
            saveLayout()
        }
    }

    func open(terminalRect: CGRect, monitorRect: CGRect) {
        isOpen = true
        model.screen = .menu
        model.selected = 0
        model.unlocked = false
        session = nil
        sampler.reset()
        model.snapshot = sampler.sample()
        setVisual(terminalRect, of: terminal)
        setVisual(monitorRect, of: monitor)
        monitor.orderFrontRegardless()
        terminal.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            terminal.animator().alphaValue = 1
            monitor.animator().alphaValue = 1
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                self.model.snapshot = self.sampler.sample()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        model.chat.cancel()
        restorePreviousApp()
        timer?.invalidate()
        timer = nil
        terminal.alphaValue = 0
        monitor.alphaValue = 0
        terminal.orderOut(nil)
        monitor.orderOut(nil)
    }

    private func handleKey(_ code: UInt16) -> Bool {
        guard isOpen else { return false }
        // В чате клавиатуру получает строка ввода; Esc возвращает в меню.
        if model.screen == .chat {
            guard code == 53 else { return false }
            model.screen = .menu
            return true
        }
        switch code {
        case 126: model.move(-1)
        case 125: model.move(1)
        case 36, 76: model.runSelected()
        case 24, 69: model.switchConnection(1)
        case 27, 78: model.switchConnection(-1)
        case 53: onDismiss()
        default: return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if isOpen { onDismiss() }
    }
}

/// Раскладка окон терминала и монитора, которую пользователь задал сам (видимые части, координаты экрана).
enum ConsoleLayoutStore {
    struct Saved: Codable {
        var terminal: CGRect
        var monitor: CGRect
    }

    private static let key = "consoleLayout"

    static func load() -> Saved? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(terminal: CGRect, monitor: CGRect) {
        guard let data = try? JSONEncoder().encode(Saved(terminal: terminal, monitor: monitor)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
