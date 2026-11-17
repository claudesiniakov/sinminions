import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

/// Команды терминала среднего режима.
enum ConsoleCommand: Int, CaseIterable, Identifiable {
    case spotlight, chat, nap, hide, corner, settings
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .spotlight: return "ПОИСК SPOTLIGHT"
        case .chat: return "ЧАТ С GIGACHAT"
        case .nap: return "УСЫПИТЬ НА 1 ЧАС"
        case .hide: return "СКРЫТЬ"
        case .corner: return "ВЕРНУТЬ В УГОЛ"
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
    var llmCanStepUp = false
    var llmCanStepDown = false
    @ObservationIgnored var switchModel: (Int) -> Void = { _ in }
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Term.small)
                .tracking(1)
                .foregroundStyle(Term.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
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
        .overlay(Rectangle().strokeBorder(Term.dim, lineWidth: 1))
        .shadow(color: Term.green.opacity(0.35), radius: 8)
        .padding(10)
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
        TerminalFrame(title: "MOTH-OS // ТЕРМИНАЛ") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ConsoleCommand.allCases) { command in
                    let active = model.selected == command.rawValue
                    HStack(spacing: 8) {
                        Text(active ? ">" : " ")
                        Text(command.title)
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
                Text("↑↓ ВЫБОР · ENTER · +/− LLM · ⌥↑↓ МОДЕЛЬ · ESC")
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
        TerminalFrame(title: "MOTH-OS // " + ([model.llmName, model.llmModelName].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "НЕЙРОСЕТЬ").uppercased()) {
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
                Text("ENTER ОТПРАВИТЬ · ⌥↑↓ МОДЕЛЬ · ESC НАЗАД")
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

    /// Призрак вместо человечка Pip-Boy и переключатель «интеллекта»: «−» и «+» меняют подключение,
    /// «▼» и «▲» — модель внутри него (по списку от простых к мощным).
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
                    if !model.llmPosition.isEmpty {
                        Text(model.llmPosition).foregroundStyle(Term.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                stepButton("+", enabled: model.llmCount > 1) { model.switchConnection(1) }
            }
            if let modelName = model.llmModelName {
                HStack(spacing: 10) {
                    stepButton("▼", enabled: model.llmCanStepDown) { model.switchModel(-1) }
                    Text(modelName.uppercased())
                        .foregroundStyle(Term.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                    stepButton("▲", enabled: model.llmCanStepUp) { model.switchModel(1) }
                }
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

    /// Остаток токенов или средств по каждому подключению; выбранное подсвечено. Длинный список прокручивается.
    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ЛИМИТЫ").foregroundStyle(Term.dim)
            if model.llmConnections.isEmpty {
                Text("ПОДКЛЮЧЕНИЙ НЕТ").foregroundStyle(Term.dim)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(model.llmConnections) { item in limitRow(item) }
                    }
                }
                .frame(height: min(CGFloat(model.llmConnections.count) * 16, 80))
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
        return HStack(spacing: 6) {
            Text((item.isActive ? "▸ " : "  ") + item.connection.name.uppercased())
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(text.uppercased())
                .foregroundStyle(warning ? Term.amber : (item.isActive ? Term.green : Term.dim))
                .lineLimit(1)
                .layoutPriority(1)
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
        TerminalFrame(title: "СИСТЕМА // МОНИТОР") {
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

// MARK: - Окна

/// Окно терминала: принимает клавиатуру, не активируя приложение.
final class ConsolePanel: NSPanel {
    var onKey: (UInt16) -> Bool = { _ in false }
    /// Что скопировать по ⌘C, если ничего не выделено.
    var copyFallback: () -> String? = { nil }

    /// Куда вставить текст, если строка ввода не в фокусе.
    var pasteFallback: (String) -> Void = { _ in }
    /// ⌥↑ и ⌥↓: модель выше и ниже.
    var onModelStep: (Int) -> Void = { _ in }

    /// У приложения без значка в Dock нет меню «Правка», поэтому сочетания ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z
    /// обрабатываем сами, отправляя действие тому, кто сейчас в фокусе.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .option {
            switch event.keyCode {
            case 126: onModelStep(1); return true
            case 125: onModelStep(-1); return true
            default: break
            }
        }
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
    /// Размеры окон вместе с полями под свечение (10 pt с каждой стороны).
    static let terminalSize = CGSize(width: 460, height: 380)
    static let monitorWidth: CGFloat = 300
    static let monitorMinHeight: CGFloat = 610

    let model = ConsoleModel()
    private let terminal: ConsolePanel
    private let monitor: NSPanel
    private let sampler = SystemMonitor()
    private var timer: Timer?
    private(set) var isOpen = false

    var onCommand: (ConsoleCommand) -> Void = { _ in }
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
        terminal.onModelStep = { [weak self] delta in self?.model.switchModel(delta) }
        terminal.pasteFallback = { [weak self] text in
            guard let self, self.model.screen == .chat else { return }
            // Строка ввода однострочная: переводы строк заменяем пробелами.
            self.model.chat.input += text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            self.model.chat.focusTick += 1
        }
        model.run = { [weak self] command in self?.onCommand(command) }
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        terminal.collectionBehavior = behavior
        monitor.collectionBehavior = behavior
    }

    func open(terminalFrame: CGRect, monitorFrame: CGRect) {
        isOpen = true
        model.screen = .menu
        model.selected = 0
        sampler.reset()
        model.snapshot = sampler.sample()
        terminal.setFrame(terminalFrame, display: true)
        monitor.setFrame(monitorFrame, display: true)
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
