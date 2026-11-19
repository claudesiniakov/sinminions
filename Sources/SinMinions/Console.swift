import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

/// Пункты меню терминала. Остальные команды вводятся со «/» (см. `SlashCommand`, «/help»).
enum ConsoleCommand: Int, CaseIterable, Identifiable {
    case spotlight, chat
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .spotlight: return "ПОИСК SPOTLIGHT"
        case .chat: return "ЧАТ С ИИ"
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

/// Характеристики призрака, как в Fallout. Работают S (размер), P (облик), C (частота реплик), E (сон),
/// I (подключение к нейросети) и A (скорость полёта); L пока без назначения.
enum SpecialStat: Int, CaseIterable, Identifiable {
    case strength, perception, endurance, charisma, intelligence, agility, luck
    var id: Int { rawValue }
    var letter: String { ["S", "P", "E", "C", "I", "A", "L"][rawValue] }
    var title: String {
        ["СИЛА", "ВОСПРИЯТИЕ", "ВЫНОСЛИВОСТЬ", "ХАРИЗМА", "ИНТЕЛЛЕКТ", "ЛОВКОСТЬ", "УДАЧА"][rawValue]
    }
    var isActive: Bool { self == .strength || self == .perception || self == .endurance || self == .intelligence || self == .agility || self == .charisma }
}

/// Значения характеристик для экрана S.P.E.C.I.A.L.
struct SpecialState: Equatable {
    var scaleLevel = 1
    var scaleLabel = "РАЗМЕР 1,5×"
    var perceptionLevel = 0
    var perceptionLabel = "ОБЛИК: КЛАССИЧЕСКИЙ"
    var agilityLevel = Agility.defaultLevel
    var agilityLabel = "ОБЫЧНО"
    var enduranceLevel = 1
    var enduranceLabel = "ЗАСЫПАЕТ ЧЕРЕЗ 5 МИН"
    var charismaLevel = Charisma.defaultLevel
    var charismaLabel = "ОБЫЧНО (2–5 МИН)"
    var intelligenceLabel = "—"
    var intelligenceCount = 0
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
    static func systemPrompt(for character: CompanionCharacter) -> String {
        switch character {
        case .f:
            return "Ты — Moth, призрак-компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в духе терминала Fallout, без эмодзи."
        case .ab:
            return "Ты — золотой страж, коренастый воин в золочёном доспехе, компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в суровом готическом тоне торжественного караульного. Без отсылок к Fallout и без эмодзи."
        }
    }
    static var systemPrompt: String { systemPrompt(for: .f) }
    private(set) var character: CompanionCharacter = .f

    /// Смена персонажа меняет тон ответов: обновляем системное сообщение, историю беседы оставляем.
    func setCharacter(_ new: CompanionCharacter) {
        guard new != character else { return }
        character = new
        if let first = history.first, first.role == .system {
            history[0] = ChatMessage(.system, Self.systemPrompt(for: new))
        }
    }

    var entries: [ChatEntry] = []
    var input = ""
    private(set) var isSending = false

    @ObservationIgnored var send: @MainActor ([ChatMessage]) async throws -> String = { _ in throw LLMError.noCredentials }
    @ObservationIgnored var hasCredentials: () -> Bool = { false }
    @ObservationIgnored var needCredentials: () -> Void = {}
    /// Команда со «/», набранная в чате: выполняет модель консоли.
    @ObservationIgnored var onSlash: (String) -> Void = { _ in }
    @ObservationIgnored var speaker: () -> String = { "LLM" }
    @ObservationIgnored private var history = [ChatMessage(.system, ChatSession.systemPrompt)]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Меняется при сбросе и отмене: ответ на устаревший запрос не попадает в журнал.
    @ObservationIgnored private var generation = 0

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        if text.hasPrefix("/") {
            entries.append(ChatEntry(kind: .user, text: text))
            onSlash(text)
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
        history = [ChatMessage(.system, Self.systemPrompt(for: character))]
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

    var screen = Screen.menu {
        didSet { if screen != oldValue { onScreenChange() } }
    }
    /// Экран сменился: строка ввода новая, фокус надо поставить заново.
    @ObservationIgnored var onScreenChange: () -> Void = {}
    let chat = ChatSession()
    var selected = 0
    /// Строка ввода меню (команды со «/») и журнал ответов.
    var shellInput = ""
    var shellLog: [String] = []
    /// Экран S.P.E.C.I.A.L.: значения и выбранная строка.
    var special = SpecialState()
    @ObservationIgnored var adjustSpecial: (SpecialStat, Int) -> Void = { _, _ in }

    /// Растёт, когда нужно вернуть фокус в строку ввода.
    var focusTick = 0
    /// Выбранное подключение к нейросети («интеллект») — для монитора и заголовка чата.
    var llmName: String?
    var llmModelName: String?
    var llmPosition = ""
    var llmCount = 0
    /// Настройка «Запрашивать и показывать лимиты».
    var showLimits = true
    /// Облик призрака в мониторе.
    var ghostStyle: GhostStyle = .classic
    /// Активный персонаж: меняет рисунок в мониторе, стиль окон и названия.
    var character: CompanionCharacter = .f {
        didSet {
            Term.theme = character
            chat.setCharacter(character)
            if character == .ab, selectedStat == .perception { selectedStat = .intelligence }
        }
    }

    /// Доступна ли буква: у золотого стража один облик, поэтому «P» неактивна.
    func isActive(_ stat: SpecialStat) -> Bool {
        stat.isActive && !(character == .ab && stat == .perception)
    }
    var coffee = false
    var outfit: Outfit = .armor
    /// Выбранная буква S.P.E.C.I.A.L. в мониторе: её уровень меняют большие «−» и «+».
    var selectedStat: SpecialStat = .intelligence
    var llmConnections: [LLMConnectionRow] = []
    let limits = LimitsStore()
    /// Окна разблокированы: их можно двигать и менять их размер.
    var unlocked = false
    @ObservationIgnored var layoutEvent: (ConsoleWindow, LayoutEvent) -> Void = { _, _ in }
    @ObservationIgnored var switchConnection: (Int) -> Void = { _ in }
    var snapshot = SystemSnapshot()
    @ObservationIgnored var run: (ConsoleCommand) -> Void = { _ in }
    /// Выполняет команду со «/», которой нужны окна и призрак; возвращает строку-подтверждение.
    @ObservationIgnored var slashAction: (SlashCommand) -> String? = { _ in nil }

    enum SlashOutput { case shell, chat }

    init() {
        chat.onSlash = { [weak self] text in self?.runSlash(text, output: .chat) }
    }

    /// Enter в строке меню: пусто — выбранный пункт, «/…» — команда.
    func submitShell() {
        let text = shellInput.trimmingCharacters(in: .whitespacesAndNewlines)
        shellInput = ""
        if text.isEmpty {
            runSelected()
            return
        }
        shellLog.append("> " + text)
        if text.hasPrefix("/") {
            runSlash(text, output: .shell)
        } else {
            shellLog.append("КОМАНДЫ НАЧИНАЮТСЯ СО «/». /HELP — СПИСОК.")
        }
        trimLog()
    }

    private func trimLog() {
        if shellLog.count > 80 { shellLog.removeFirst(shellLog.count - 80) }
    }

    /// Команда со «/» из меню или чата; ответ выводится туда же, откуда команда пришла.
    func runSlash(_ text: String, output: SlashOutput) {
        func say(_ lines: [String]) {
            switch output {
            case .shell: shellLog.append(contentsOf: lines)
            case .chat: lines.forEach { chat.addInfo($0) }
            }
            trimLog()
        }
        switch SlashParser.parse(text) {
        case .notACommand:
            return
        case let .unknown(name):
            say(["НЕИЗВЕСТНАЯ КОМАНДА \(name.uppercased()) — /HELP ПОКАЖЕТ СПИСОК"])
        case let .command(command):
            switch command {
            case .help:
                say(SlashParser.helpLines)
            case .clear:
                chat.reset()
                say(["ИСТОРИЯ ЧАТА ОЧИЩЕНА"])
            default:
                if let reply = slashAction(command) { say([reply]) }
            }
        }
    }

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

/// Палитра терминала и монитора. У первого персонажа зелёный терминал из Fallout, у второго золото и багрянец в духе Вархаммера.
private enum Term {
    nonisolated(unsafe) static var theme: CompanionCharacter = .f
    private static var gothic: Bool { theme == .ab }

    static var body: Color { Color(nsColor: CompanionView.Palette.body) }
    static var bodyStroke: Color { Color(nsColor: CompanionView.Palette.bodyStroke) }
    static var pupil: Color { Color(nsColor: CompanionView.Palette.pupil) }
    /// Предупреждения и ошибки: янтарь у Moth, багрянец у стража.
    static var amber: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0xff6b57)) : Color(red: 1, green: 0.69, blue: 0.2) }
    // У стража: тёплый пергамент для текста и рамок, кровавый багрянец для линий и разделителей, чёрно-красный фон.
    static var green: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0xf0d58c)) : Color(nsColor: CompanionView.Palette.green) }
    static var dim: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0xb59a62)) : Color(nsColor: CompanionView.Palette.greenDim) }
    static var dark: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0x7a2222)) : Color(nsColor: CompanionView.Palette.greenDark) }
    static var background: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0x0e0808)) : Color(nsColor: CompanionView.Palette.rgb(0x0b0f0a)) }
    static var font: Font { Font.system(size: 13, design: .monospaced) }
    static var small: Font { Font.system(size: 11, design: .monospaced) }
    /// Заголовки окон: у стража — готический засечный шрифт.
    static var title: Font { gothic ? Font.system(size: 12, weight: .bold, design: .serif) : small }
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
                if model.character == .ab {
                    Text("✠").font(Term.title).foregroundStyle(Term.green)
                }
                Text(title)
                    .font(Term.title)
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
            if model.character == .ab {
                // Двойная рамка с угловыми знаками, как на готической табличке.
                ZStack {
                    Rectangle().strokeBorder(Term.dark, lineWidth: 1).padding(4)
                    VStack {
                        HStack { Text("✠"); Spacer(); Text("✠") }
                        Spacer()
                        HStack { Text("✠"); Spacer(); Text("✠") }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Term.dim)
                    .padding(6)
                }
                .allowsHitTesting(false)
            }
        }
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
        .id(model.character)
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
        TerminalFrame(title: "\(model.character.terminalName) // ТЕРМИНАЛ", window: .terminal, model: model) {
            ShellScreen(model: model)
        }
    }
}

/// Экран меню: два пункта, журнал ответов на команды и строка ввода («/help» — список команд).
private struct ShellScreen: View {
    var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
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
            Rectangle().fill(Term.dark).frame(height: 1).padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if model.shellLog.isEmpty {
                            Text("КОМАНДЫ НАЧИНАЮТСЯ СО «/». ВВЕДИТЕ /HELP — СПИСОК.")
                                .foregroundStyle(Term.dim)
                        }
                        ForEach(Array(model.shellLog.enumerated()), id: \.offset) { _, line in
                            Text(line).foregroundStyle(line.hasPrefix(">") ? Term.green : Term.dim)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .font(Term.small)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.shellLog.count) { proxy.scrollTo("end", anchor: .bottom) }
            }
            Rectangle().fill(Term.dark).frame(height: 1)
            // Подсказки команд по вводу: Tab дописывает, щелчок подставляет.
            let hints = SlashParser.hints(for: model.shellInput)
            if !hints.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(hints.prefix(6), id: \.name) { hint in
                        HStack(spacing: 8) {
                            Text(hint.name)
                            Text(hint.summary).foregroundStyle(Term.dim)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.shellInput = hint.name; model.focusTick += 1 }
                    }
                }
                .font(Term.small)
                .foregroundStyle(Term.green)
            }
            HStack(spacing: 6) {
                Text(">")
                TextField("", text: $model.shellInput)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { model.submitShell() }
                    // Стрелки выбирают пункт меню, а не двигают курсор в строке.
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.tab) {
                        guard let done = SlashParser.completion(for: model.shellInput) else { return .handled }
                        model.shellInput = done
                        return .handled
                    }
                    // «+» и «−» в пустой строке переключают подключение к нейросети.
                    .onKeyPress(characters: CharacterSet(charactersIn: "+-=")) { press in
                        guard model.shellInput.isEmpty else { return .ignored }
                        model.switchConnection(press.characters == "-" ? -1 : 1)
                        return .handled
                    }
            }
            .font(Term.small)
            .foregroundStyle(Term.green)
            Text("↑↓ ВЫБОР · TAB ДОПИСАТЬ · /HELP · ESC ВЫХОД")
                .font(Term.small)
                .foregroundStyle(Term.dim)
        }
        .tint(Term.green)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
    }
}

/// Экран чата: журнал, строка ввода, подсказка.
private struct ChatScreen: View {
    var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var chat = model.chat
        TerminalFrame(title: model.character.terminalName + " // " + ([model.llmName, model.llmModelName].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "НЕЙРОСЕТЬ").uppercased(), window: .terminal, model: model) {
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
                Text("ENTER ОТПРАВИТЬ · /HELP · ESC НАЗАД")
                    .foregroundStyle(Term.dim)
            }
            .font(Term.small)
            .tint(Term.green)
        }
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
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
private struct GhostFigure: NSViewRepresentable {
    let style: GhostStyle
    let coffee: Bool
    let character: CompanionCharacter
    let outfit: Outfit

    func makeNSView(context: Context) -> GhostFigureHost { GhostFigureHost(style: style, coffee: coffee, character: character, outfit: outfit) }

    func updateNSView(_ view: GhostFigureHost, context: Context) { view.show(style, coffee: coffee, character: character, outfit: outfit) }
}

/// Призрак для монитора: те же слои, что у призрака на экране, размером 72×84.
final class GhostFigureHost: NSView {
    private var style: GhostStyle
    private var coffee: Bool
    private var character: CompanionCharacter
    private var outfit: Outfit

    init(style: GhostStyle, coffee: Bool, character: CompanionCharacter, outfit: Outfit) {
        self.style = style
        self.coffee = coffee
        self.character = character
        self.outfit = outfit
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 84))
        wantsLayer = true
        layer?.masksToBounds = false
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override var intrinsicContentSize: NSSize { NSSize(width: 72, height: 84) }

    func show(_ style: GhostStyle, coffee: Bool, character: CompanionCharacter, outfit: Outfit) {
        guard style != self.style || coffee != self.coffee || character != self.character || outfit != self.outfit else { return }
        self.style = style
        self.coffee = coffee
        self.character = character
        self.outfit = outfit
        rebuild()
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        let art: any CompanionArt = character == .ab ? GoldenArt(scale: 1.5, coffee: coffee, outfit: outfit) : GhostArt(style: style, scale: 1.5, coffee: coffee)
        art.root.frame = CGRect(x: 0, y: 0, width: 72, height: 84)
        art.body.shadowRadius = 6 * art.glowScale
        art.body.shadowOpacity = 0.6
        layer?.addSublayer(art.root)
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

    /// Значение, уровень и число уровней по буквам; nil — характеристика пока без назначения.
    private func specialInfo(_ stat: SpecialStat) -> (value: String, level: Int, levels: Int, label: String)? {
        let state = model.special
        switch stat {
        case .strength: return ("\(state.scaleLevel)", state.scaleLevel, Prefs.scales.count, state.scaleLabel)
        case .perception: return ("\(state.perceptionLevel)", state.perceptionLevel, GhostStyle.levels, state.perceptionLabel)
        case .endurance: return ("\(state.enduranceLevel)", state.enduranceLevel, Endurance.levels, state.enduranceLabel)
        case .charisma: return ("\(state.charismaLevel)", state.charismaLevel, Charisma.levels, state.charismaLabel)
        case .agility: return ("\(state.agilityLevel)", state.agilityLevel, Agility.levels, state.agilityLabel)
        case .intelligence:
            return (model.llmPosition.split(separator: "/").first.map(String.init) ?? "–", 0, 0, "")
        default: return nil
        }
    }

    /// S.P.E.C.I.A.L. над призраком, как в Fallout: буквы с точками в квадратиках. Выбранная буква
    /// светится ярче остальных (рамка и заливка у всех одинаковые). Щелчок выбирает характеристику, и большие
    /// «−» и «+» под призраком меняют её уровень (у I — подключение к нейросети).
    private var specialStrip: some View {
        HStack(spacing: 4) {
            ForEach(SpecialStat.allCases) { stat in
                let selected = model.selectedStat == stat
                let strength: Double = selected ? 1 : (model.isActive(stat) ? 0.5 : 0.28)
                // Буква и точка внутри одного квадрата: «S.», «P.», …
                Text(stat.letter + ".")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(maxWidth: 34)
                    .frame(height: 30)
                    .overlay(Rectangle().strokeBorder(Term.green, lineWidth: 1))
                    .foregroundStyle(Term.green)
                    .opacity(strength)
                    .shadow(color: Term.green.opacity(selected ? 0.9 : 0), radius: selected ? 5 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { if model.isActive(stat) { model.selectedStat = stat } }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Подпись и «−» с «+» под призраком: для I — подключение, для остальных букв — уровень выбранной характеристики.
    private var intelligence: some View {
        let stat = model.selectedStat
        let info = specialInfo(stat)
        let isIntelligence = stat == .intelligence
        let level = info?.level ?? 0
        let levels = info?.levels ?? 0
        return VStack(spacing: 6) {
            specialStrip
            GhostFigure(style: model.ghostStyle, coffee: model.coffee, character: model.character, outfit: model.outfit)
                .frame(width: 72, height: 84)
            Text(stat.title)
                .foregroundStyle(Term.dim)
            HStack(spacing: 10) {
                stepButton("−", enabled: isIntelligence ? model.llmCount > 1 : level > 0) {
                    if isIntelligence { model.switchConnection(-1) } else { model.adjustSpecial(stat, -1) }
                }
                VStack(spacing: 1) {
                    if isIntelligence {
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
                    } else {
                        Text(info?.label ?? "")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("УРОВЕНЬ \(level) ИЗ \(max(levels - 1, 0))").foregroundStyle(Term.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                stepButton("+", enabled: isIntelligence ? model.llmCount > 1 : level < levels - 1) {
                    if isIntelligence { model.switchConnection(1) } else { model.adjustSpecial(stat, 1) }
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

    /// Остаток токенов или средств по каждому подключению: название и остаток, под ними модель.
    /// Выбранное подключение подсвечено; длинный список прокручивается.
    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ЛИМИТЫ").foregroundStyle(Term.green).bold()
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
        case .unsupported: text = "—"
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
        TerminalFrame(title: "\(model.character.monitorName) // МОНИТОР", window: .monitor, model: model) {
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
                if model.showLimits {
                    Rectangle().fill(Term.dark).frame(height: 1)
                    limitsBlock
                }
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

    /// Без этого окно без рамки не может стать ключевым и клавиатура в него не попадает.
    override var canBecomeKey: Bool { true }
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
    /// Команды со «/»: возвращает подтверждение для журнала.
    var onSlash: (SlashCommand) -> String? = { _ in nil }
    /// «+» и «−» на экране S.P.E.C.I.A.L.
    var onAdjustSpecial: (SpecialStat, Int) -> Void = { _, _ in }
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
            guard let self else { return }
            // Строка ввода однострочная: переводы строк заменяем пробелами.
            let line = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            switch self.model.screen {
            case .chat: self.model.chat.input += line
            case .menu: self.model.shellInput += line
            }
            self.model.focusTick += 1
            self.focusInput()
        }
        model.run = { [weak self] command in self?.onCommand(command) }
        model.slashAction = { [weak self] command in self?.onSlash(command) }
        model.layoutEvent = { [weak self] window, event in self?.handleLayout(window, event) }
        model.adjustSpecial = { [weak self] stat, delta in self?.onAdjustSpecial(stat, delta) }
        model.onScreenChange = { [weak self] in self?.scheduleFocus() }
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
        guard isOpen else { return }
        if !NSApp.isActive {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            NSApp.activate(ignoringOtherApps: true)
        }
        // Приложение могло быть уже активным (например, после окна настроек), но ключевым окном — другое:
        // клавиатура идёт только в ключевое окно.
        terminal.makeKeyAndOrderFront(nil)
        model.focusTick += 1
        scheduleFocus()
    }

    /// Первая редактируемая строка ввода в окне терминала.
    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }

    /// Ставит курсор в строку ввода средствами AppKit: фокус SwiftUI в окне без рамки ненадёжен —
    /// окно оказывалось ключевым, а печатать было некуда.
    func focusInput() {
        guard isOpen, let content = terminal.contentView,
              let field = Self.firstTextField(in: content) else { return }
        terminal.makeFirstResponder(field)
    }

    /// SwiftUI строит экран не мгновенно, поэтому фокус ставим дважды: сразу после и чуть позже.
    private func scheduleFocus() {
        for delay in [0.05, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.focusInput() }
            }
        }
    }

    /// Для CI: состояние фокуса окна терминала.
    func debugState() -> String {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let responder = terminal.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let keyWindow = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil"
        return "active=\(NSApp.isActive) key=\(terminal.isKeyWindow) keyWindow=\(keyWindow) canKey=\(terminal.canBecomeKey) visible=\(terminal.isVisible) fr=\(responder) front=\(front)"
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
        model.shellInput = ""
        model.shellLog = []
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
