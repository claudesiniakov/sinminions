import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

// MARK: - Оформление терминала

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Палитра терминала и монитора. У первого персонажа зелёный терминал из Fallout, у второго золото и багрянец в духе Вархаммера.
enum Term {
    nonisolated(unsafe) static var theme: CompanionCharacter = .f
    private static var gothic: Bool { theme == .ab }

    static var body: Color { Color(nsColor: CompanionView.Palette.body) }
    static var bodyStroke: Color { Color(nsColor: CompanionView.Palette.bodyStroke) }
    static var pupil: Color { Color(nsColor: CompanionView.Palette.pupil) }
    /// Предупреждения и ошибки: янтарь у Moth, багрянец у стража.
    static var amber: Color { gothic ? Color(nsColor: CompanionView.Palette.rgb(0xff6b57)) : Color(red: 1, green: 0.69, blue: 0.2) }
    // У стража: тёплый пергамент для текста и рамок, кровавый багрянец для линий и разделителей, чёрно-красный фон.
    static var green: Color { theme == .v ? Color(nsColor: CompanionView.Palette.vikchaText) : gothic ? Color(nsColor: CompanionView.Palette.rgb(0xf0d58c)) : Color(nsColor: CompanionView.Palette.green) }
    static var dim: Color { theme == .v ? Color(nsColor: CompanionView.Palette.rgb(0xbf8dbd)) : gothic ? Color(nsColor: CompanionView.Palette.rgb(0xb59a62)) : Color(nsColor: CompanionView.Palette.greenDim) }
    static var dark: Color { theme == .v ? Color(nsColor: CompanionView.Palette.rgb(0x614363)) : gothic ? Color(nsColor: CompanionView.Palette.rgb(0x7a2222)) : Color(nsColor: CompanionView.Palette.greenDark) }
    static var background: Color { theme == .v ? Color(nsColor: CompanionView.Palette.vikchaPanel) : gothic ? Color(nsColor: CompanionView.Palette.rgb(0x0e0808)) : Color(nsColor: CompanionView.Palette.rgb(0x0b0f0a)) }
    static var font: Font { Font.system(size: 13, design: .monospaced) }
    static var small: Font { Font.system(size: 11, design: .monospaced) }
    /// Заголовки окон: у стража — готический засечный шрифт.
    static var title: Font { gothic ? Font.system(size: 11, weight: .bold, design: .serif) : small }
}

/// Рамка окна терминала: тёмный фон, зелёная рамка, строки развёртки, заголовок.
struct TerminalFrame<Content: View>: View {
    let title: String
    let window: ConsoleWindow
    var model: ConsoleModel
    @ViewBuilder var content: Content

    private var lockAccessibilityLabel: String {
        model.unlocked ? tr("Заблокировать окна") : tr("Разблокировать окна")
    }

    private var pinAccessibilityLabel: String {
        model.chatPinned ? tr("Открепить чат") : tr("Приколоть чат: не закроется при потере фокуса")
    }

    private var fg: Color { Term.green }
    private var dimColor: Color { Term.dim }
    private var lineColor: Color { Term.dark }
    private var back: Color { Term.background }

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
                    .foregroundStyle(dimColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if window == .terminal {
                    TerminalModeSwitch(model: model)
                }
                Text(model.unlocked ? tr("[ЗАМОК ВЫКЛ]") : tr("[ЗАМОК ВКЛ]"))
                    .font(Term.small)
                    .foregroundStyle(model.unlocked ? fg : dimColor)
                    .contentShape(Rectangle())
                    .onTapGesture { model.layoutEvent(window, .toggleLock) }
                    .help(model.unlocked ? tr("Заблокировать окна") : tr("Разблокировать: окна можно двигать и менять их размер"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(lockAccessibilityLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            // Двигать окно можно только разблокированным и только за заголовок.
            .gesture(moveGesture, including: model.unlocked ? .all : .subviews)
            Rectangle().fill(lineColor).frame(height: 1)
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(back.opacity(0.96))
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
            scanlines
        }
        .overlay(
            // Разблокированное окно обведено пунктиром.
            Rectangle().strokeBorder(
                model.unlocked ? fg : dimColor,
                style: StrokeStyle(lineWidth: 1, dash: model.unlocked ? [5, 3] : [])
            )
            .allowsHitTesting(false)
        )
        .overlay(alignment: .bottomTrailing) {
            if model.unlocked { resizeHandle }
        }
        .shadow(color: Term.green.opacity(0.35), radius: 8)
        .padding(10)
        .id(model.character.rawValue + model.language.rawValue)
    }

    /// Строки развёртки старого монитора.
    private var scanlines: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }

    /// Ручка изменения размера в правом нижнем углу разблокированного окна.
    private var resizeHandle: some View {
        Text("◢")
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(fg)
            .padding(4)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .help(tr("Потяните, чтобы изменить размер"))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(tr("Изменить размер")))
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
        Group {
            switch model.screen {
            case .chat: ChatScreen(model: model)
            case .shell:
                TerminalFrame(title: model.character.terminalName + " // ZSH " + ShellText.abbreviate(model.shell.cwd, home: NSHomeDirectory()), window: .terminal, model: model) {
                    PlainShellScreen(model: model)
                }
            }
        }
        // Смена языка пересоздаёт экраны целиком: подписи берутся заново.
        .id(model.language)
    }

}

/// Экран чата: журнал, строка ввода, подсказка.
struct ChatScreen: View {
    var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var chat = model.chat
        TerminalFrame(title: model.character.terminalName + " // " + ([model.llmName, model.llmModelName].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? tr("НЕЙРОСЕТЬ")).uppercased(), window: .terminal, model: model) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if chat.entries.isEmpty {
                                Text(tr("ВВЕДИТЕ СООБЩЕНИЕ. /clear — ОЧИСТИТЬ ИСТОРИЮ."))
                                    .foregroundStyle(Term.dim)
                            }
                            if !chat.entries.isEmpty {
                                // Весь журнал — один текст: выделять можно мышью через несколько реплик, ⌘C копирует.
                                Text(chat.cachedLog(key: "\(chat.revision)|\(model.language)|\(model.character)") { log(chat) })
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if chat.isSending {
                                Text(tr("ОЖИДАНИЕ ОТВЕТА…")).foregroundStyle(Term.dim)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .font(.system(size: model.chatFont.pointSize, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: chat.revision) { scroll(proxy, chat) }
                    .onChange(of: chat.isSending) { scroll(proxy, chat) }
                }
                Rectangle().fill(Term.dark).frame(height: 1)
                // Подсказки команд: у каждой задан свой цвет (иначе в светлой теме системный
                // чёрный терялся на тёмной панели), одна строка и не больше четырёх —
                // иначе список сжимал журнал и обрезался сам.
                let hints = SlashParser.hints(for: chat.input)
                if !hints.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(hints.prefix(4), id: \.name) { hint in
                            Button {
                                chat.input = hint.name
                                focused = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(hint.name)
                                        .foregroundStyle(Term.green)
                                        .lineLimit(1)
                                    Text(hint.summary)
                                        .foregroundStyle(Term.dim)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(hint.summary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    Text(">")
                    TextField("", text: $chat.input)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { chat.submit() }
                        .onKeyPress(.upArrow) { chat.historyUp(); return .handled }
                        .onKeyPress(.downArrow) { chat.historyDown(); return .handled }
                        .onKeyPress(.tab) {
                            guard let name = SlashParser.completion(for: chat.input) else { return .ignored }
                            chat.input = name
                            return .handled
                        }
                }
                .font(.system(size: model.chatFont.pointSize, design: .monospaced))
                .foregroundStyle(Term.green)
                Text(tr("ENTER ОТПРАВИТЬ · /HELP · ESC ЗАКРЫТЬ"))
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
                line = AttributedString(tr("ОШИБКА: ") + entry.text)
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
