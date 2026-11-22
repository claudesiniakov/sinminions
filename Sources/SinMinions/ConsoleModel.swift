import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

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
            ChatEntry(kind: .assistant, text: "всё под контролем, периметр чист. текст можно выделить мышью и скопировать по ⌘C.", speaker: "GIGACHAT"),
            ChatEntry(kind: .user, text: "а если без шуток?"),
            ChatEntry(kind: .error, text: "Сервис GigaChat недоступен (503)"),
        ]
    }
}

@MainActor
@Observable
final class ConsoleModel {
    enum Screen { case menu, chat, shell }

    var screen = Screen.menu {
        didSet { if screen != oldValue { onScreenChange() } }
    }
    /// Экран сменился: строка ввода новая, фокус надо поставить заново.
    @ObservationIgnored var onScreenChange: () -> Void = {}
    let chat = ChatSession()
    /// Обычный терминал (zsh).
    let shell = ShellSession()
    /// Терминал открывается в режиме zsh; запоминается между запусками.
    private(set) var shellMode = UserDefaults.standard.bool(forKey: "terminalShellMode")
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

    enum SlashOutput { case shell, chat, zsh }

    init() {
        chat.onSlash = { [weak self] text in self?.runSlash(text, output: .chat) }
        shell.onSlash = { [weak self] text in self?.runSlash(text, output: .zsh) }
        shell.onExit = { [weak self] in self?.setShellMode(false) }
    }

    /// Переключатель «терминал компаньона / обычный терминал».
    func setShellMode(_ on: Bool) {
        shellMode = on
        UserDefaults.standard.set(on, forKey: "terminalShellMode")
        screen = on ? .shell : .menu
        focusTick += 1
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
            case .zsh: lines.forEach { shell.addInfo($0) }
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
                if output == .zsh {
                    shell.clear()
                } else {
                    chat.reset()
                    say(["ИСТОРИЯ ЧАТА ОЧИЩЕНА"])
                }
            case .shell:
                setShellMode(!shellMode)
                if shellMode {
                    shell.addInfo("ОБЫЧНЫЙ ТЕРМИНАЛ ZSH. EXIT ИЛИ /SHELL — НАЗАД.")
                } else if output == .chat {
                    say(["ТЕРМИНАЛ КОМПАНЬОНА"])
                }
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
