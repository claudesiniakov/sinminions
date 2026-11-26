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
            return tr("Ты — Moth, призрак-компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в духе терминала Fallout, без эмодзи.")
        case .v:
            return tr("Ты — vikcha piccha, энергичная аниме-девочка-маркетолог и компаньон на рабочем столе Mac. Отвечай по-русски, кратко и дружелюбно. В вопросах маркетинга учитывай аудиторию, цель и измеримый результат. Подхватывай конкретную деталь из последних слов собеседника. В обычной беседе дай место шутке, сочувствию или короткой истории. Если просят идею, предложи живой пример; если делятся переживанием, сначала откликнись на него. Задавай вопрос, только когда он помогает продолжить разговор. О том, что происходит на экране пользователя, суди только по его словам.")
        case .ab:
            return tr("Ты — золотой страж, коренастый воин в золочёном доспехе, компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в суровом готическом тоне торжественного караульного. Без отсылок к Fallout и без эмодзи.")
        }
    }
    static var systemPrompt: String { systemPrompt(for: .f) }
    private(set) var character: CompanionCharacter = .f

    /// Смена персонажа меняет тон ответов: обновляем системное сообщение, историю беседы оставляем.
    /// Сменился язык: модель отвечает на новом языке, история беседы остаётся.
    func refreshPrompt() {
        if let first = history.first, first.role == .system {
            history[0] = ChatMessage(.system, Self.systemPrompt(for: character))
        }
    }

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
        guard !text.isEmpty else { return }
        if text.hasPrefix("/") {
            input = ""
            append(ChatEntry(kind: .user, text: text))
            onSlash(text)
            return
        }
        guard !isSending else { return }
        guard hasCredentials() else {
            append(ChatEntry(kind: .info, text: tr("НЕТ ПОДКЛЮЧЕНИЯ С КЛЮЧОМ — ОТКРЫВАЮ НАСТРОЙКИ")))
            needCredentials()
            return
        }
        append(ChatEntry(kind: .user, text: text))
        input = ""
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
                self.append(ChatEntry(kind: .assistant, text: answer, speaker: who))
                self.history = ChatHistory.trimmed(self.history)
            } catch {
                guard mine == self.generation else { return }
                // Неудавшийся вопрос из истории убираем, чтобы его можно было задать заново.
                self.history.removeLast()
                if !(error is CancellationError) {
                    self.append(ChatEntry(kind: .error, text: error.localizedDescription))
                }
            }
            self.isSending = false
        }
    }

    func addInfo(_ text: String) {
        append(ChatEntry(kind: .info, text: text))
    }

    /// Журнал на экране не растёт бесконечно: при долгой переписке память и отрисовка
    /// оставались пропорциональны числу реплик. Храним последние двести сорок.
    static let entriesLimit = 240

    private func append(_ entry: ChatEntry) {
        entries.append(entry)
        if entries.count > Self.entriesLimit {
            entries.removeFirst(entries.count - Self.entriesLimit)
        }
    }

    /// Терминал закрыт во время запроса: ответ уже не нужен.
    func cancel() {
        guard isSending else { return }
        generation += 1
        task?.cancel()
        task = nil
        history.removeLast()
        isSending = false
        append(ChatEntry(kind: .info, text: tr("ЗАПРОС ПРЕРВАН")))
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
            ChatEntry(kind: .user, text: tr("привет, как дела?")),
            ChatEntry(kind: .assistant, text: tr("всё под контролем, периметр чист. текст можно выделить мышью и скопировать по ⌘C."), speaker: "GIGACHAT"),
            ChatEntry(kind: .user, text: tr("а если без шуток?")),
            ChatEntry(kind: .error, text: tr("Сервис GigaChat недоступен (503)")),
        ]
    }
}

@MainActor
@Observable
final class ConsoleModel {
    enum Screen { case chat, shell }

    var screen = Screen.chat {
        didSet { if screen != oldValue { onScreenChange() } }
    }
    /// Экран сменился: строка ввода новая, фокус надо поставить заново.
    @ObservationIgnored var onScreenChange: () -> Void = {}
    let chat = ChatSession()
    /// Обычный терминал (zsh).
    let shell = ShellSession()
    var shellMode: Bool { screen == .shell }
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
    /// Чат не закрывать при потере фокуса (настройка).
    var chatStaysOpen = false

    var character: CompanionCharacter = .f {
        didSet {
            Term.theme = character
            chat.setCharacter(character)
            // У другого персонажа набор кнопок свой: выбранная буква могла исчезнуть.
            if !isActive(selectedStat) { selectedStat = .intelligence }
        }
    }

    /// Доступна ли буква: у золотого стража один облик, поэтому «P» неактивна.
    func isActive(_ stat: SpecialStat) -> Bool {
        stat.isActive(for: character)
    }
    var coffee = false
    var outfit: Outfit = .armor
    /// Язык интерфейса: при смене окна терминала и монитора перерисовываются целиком.
    var language: AppLanguage = .ru {
        didSet { if language != oldValue { chat.refreshPrompt() } }
    }
    /// Выбранная буква S.P.E.C.I.A.L. в мониторе: её уровень меняют большие «−» и «+».
    var selectedStat: SpecialStat = .intelligence
    var llmConnections: [LLMConnectionRow] = []
    let limits = LimitsStore()
    /// Окна разблокированы: их можно двигать и менять их размер.
    var unlocked = false
    @ObservationIgnored var layoutEvent: (ConsoleWindow, LayoutEvent) -> Void = { _, _ in }
    @ObservationIgnored var switchConnection: (Int) -> Void = { _ in }
    var snapshot = SystemSnapshot()
    /// Выполняет команду со «/», которой нужны окна и призрак; возвращает строку-подтверждение.
    @ObservationIgnored var slashAction: (SlashCommand) -> String? = { _ in nil }

    enum SlashOutput { case chat, zsh }

    init() {
        chat.onSlash = { [weak self] text in self?.runSlash(text, output: .chat) }
        shell.onSlash = { [weak self] text in self?.runSlash(text, output: .zsh) }
        shell.onExit = { [weak self] in self?.setShellMode(false) }
    }

    /// Переключатель «терминал компаньона / обычный терминал».
    func setShellMode(_ on: Bool) {
        screen = on ? .shell : .chat
        focusTick += 1
    }

    /// Команда со «/» из меню или чата; ответ выводится туда же, откуда команда пришла.
    func runSlash(_ text: String, output: SlashOutput) {
        func say(_ lines: [String]) {
            switch output {
            case .chat: lines.forEach { chat.addInfo($0) }
            case .zsh: lines.forEach { shell.addInfo($0) }
            }
        }
        switch SlashParser.parse(text) {
        case .notACommand:
            return
        case let .unknown(name):
            say([trf("НЕИЗВЕСТНАЯ КОМАНДА %@ — /HELP ПОКАЖЕТ СПИСОК", "\(name.uppercased())")])
        case let .command(command):
            switch command {
            case .help:
                say(SlashParser.helpLines)
            case .clear:
                if output == .zsh {
                    shell.clear()
                } else {
                    chat.reset()
                    say([tr("ИСТОРИЯ ЧАТА ОЧИЩЕНА")])
                }
            case .shell:
                setShellMode(!shellMode)
                if shellMode {
                    shell.addInfo(tr("ОБЫЧНЫЙ ТЕРМИНАЛ ZSH. EXIT ИЛИ /SHELL — НАЗАД."))
                } else if output == .chat {
                    say([tr("ТЕРМИНАЛ КОМПАНЬОНА")])
                }
            default:
                if let reply = slashAction(command) { say([reply]) }
            }
        }
    }

}
