import AppKit
import Observation
import SwiftUI
import SinMinionsCore

/// Обычный терминал: каждая строка выполняется в zsh (`zsh -l -c`) в текущей папке, вывод — в журнал.
/// Это не полноценный эмулятор: полноэкранные программы (vim, top, less) не работают, ввод для запущенной
/// команды передаётся строкой по Enter, Ctrl+C прерывает, Ctrl+D закрывает ввод.
@MainActor
@Observable
final class ShellSession {
    enum Kind { case command, output, info }

    struct Line: Identifiable {
        let id: Int
        let kind: Kind
        var text: String
    }

    private(set) var lines: [Line] = []
    var input = ""
    private(set) var cwd: String
    private(set) var isRunning = false

    /// Команда со «/», известная приложению (например «/shell»): выполняет модель консоли.
    @ObservationIgnored var onSlash: (String) -> Void = { _ in }
    /// «exit»: вернуться к терминалу компаньона.
    @ObservationIgnored var onExit: () -> Void = {}

    @ObservationIgnored private let home = NSHomeDirectory()
    @ObservationIgnored private let user = NSUserName()
    @ObservationIgnored private let host: String = {
        let name = ProcessInfo.processInfo.hostName
        return name.split(separator: ".").first.map(String.init) ?? name
    }()
    @ObservationIgnored private var previousDir: String?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdin: Pipe?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var openOutput = false
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var historyIndex: Int?

    static let maxLines = 1500

    init() {
        cwd = NSHomeDirectory()
    }

    var prompt: String { ShellText.prompt(user: user, host: host, cwd: cwd, home: home) }

    func submit() {
        let text = input
        input = ""
        historyIndex = nil
        // Команда уже идёт: строка уходит ей на вход (например, ответ «y» на вопрос).
        if isRunning {
            add(.command, text)
            openOutput = false
            stdin?.fileHandleForWriting.write(Data((text + "\n").utf8))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        add(.command, prompt + " " + text)
        guard !trimmed.isEmpty else { return }
        if history.last != trimmed { history.append(trimmed) }
        if history.count > 200 { history.removeFirst(history.count - 200) }

        if trimmed.hasPrefix("/"), case .command = SlashParser.parse(trimmed) {
            onSlash(trimmed)
            return
        }
        switch trimmed {
        case "clear":
            clear()
            return
        case "exit", "logout":
            onExit()
            return
        default:
            break
        }
        if let argument = ShellText.cdArgument(trimmed) {
            changeDirectory(argument)
            return
        }
        run(trimmed)
    }

    func addInfo(_ text: String) {
        add(.info, text)
    }

    func clear() {
        lines = []
        openOutput = false
    }

    /// Ctrl+C: прервать запущенную команду.
    func interrupt() {
        guard let process, process.isRunning else {
            add(.command, prompt + " " + input + "^C")
            input = ""
            return
        }
        process.interrupt()
        // Не послушалась — через секунду завершаем.
        let pid = process.processIdentifier
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let current = self.process, current.processIdentifier == pid, current.isRunning else { return }
            current.terminate()
        }
    }

    /// Ctrl+D: конец ввода для запущенной команды.
    func endInput() {
        guard isRunning else { return }
        try? stdin?.fileHandleForWriting.close()
        stdin = nil
    }

    /// Стрелки ↑↓: история команд.
    func browseHistory(_ delta: Int) {
        guard !history.isEmpty, !isRunning else { return }
        let index = min(max((historyIndex ?? history.count) + delta, 0), history.count)
        historyIndex = index
        input = index < history.count ? history[index] : ""
    }

    // MARK: - Выполнение

    private func changeDirectory(_ argument: String) {
        let target = ShellText.resolve(argument, cwd: cwd, home: home, previous: previousDir)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory) else {
            add(.output, "cd: no such file or directory: \(argument)")
            return
        }
        guard isDirectory.boolValue else {
            add(.output, "cd: not a directory: \(argument)")
            return
        }
        previousDir = cwd
        cwd = target
    }

    private func run(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -l: как в обычном Терминале подтягиваются PATH и настройки из ~/.zprofile.
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        environment["CLICOLOR"] = "0"
        environment["NO_COLOR"] = "1"
        environment["PWD"] = cwd
        process.environment = environment

        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.appendOutput(text) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            let pid = finished.processIdentifier
            Task { @MainActor in
                // Даём дочитать остаток вывода.
                try? await Task.sleep(for: .milliseconds(80))
                self?.finish(status: status, reason: reason, pid: pid)
            }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            add(.output, "zsh: не удалось запустить: \(error.localizedDescription)")
            return
        }
        self.process = process
        self.stdin = input
        isRunning = true
        openOutput = false
    }

    private func finish(status: Int32, reason: Process.TerminationReason, pid: Int32) {
        guard let process, process.processIdentifier == pid else { return }
        self.process = nil
        try? stdin?.fileHandleForWriting.close()
        stdin = nil
        isRunning = false
        if openOutput, let last = lines.last, last.kind == .output, last.text.isEmpty { lines.removeLast() }
        openOutput = false
        if reason == .uncaughtSignal { add(.info, "^C") }
        _ = status
    }

    private func appendOutput(_ chunk: String) {
        var parts = ShellText.stripANSI(chunk).components(separatedBy: "\n")
        if openOutput, let last = lines.indices.last, lines[last].kind == .output {
            lines[last].text += parts.removeFirst()
        }
        for part in parts { add(.output, part) }
        openOutput = true
    }

    private func add(_ kind: Kind, _ text: String) {
        lines.append(Line(id: nextID, kind: kind, text: text))
        nextID += 1
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    /// Для снимка в CI: пара настоящих команд.
    func runDemo() {
        input = "echo привет из zsh && sw_vers"
        submit()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.input = "ls /"
            self?.submit()
        }
    }
}

/// Цвета обычного терминала: как профиль «Базовый» в тёмной теме Терминала macOS.
enum PlainTerm {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let text = Color(red: 0.9, green: 0.9, blue: 0.9)
    static let dim = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let line = Color(red: 0.3, green: 0.3, blue: 0.32)
    static let font = Font.system(size: 12, design: .monospaced)
}

/// Экран обычного терминала: журнал команд и вывода, строка ввода с приглашением.
struct PlainShellScreen: View {
    var model: ConsoleModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var shell = model.shell
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if shell.lines.isEmpty {
                            Text("Обычный терминал (zsh). exit или /shell — назад к \(model.character.terminalName).")
                                .foregroundStyle(PlainTerm.dim)
                        } else {
                            Text(transcript(shell))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: shell.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: shell.lines.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !shell.isRunning {
                    Text(shell.prompt).lineLimit(1).truncationMode(.head).layoutPriority(0)
                }
                TextField("", text: $shell.input)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .layoutPriority(1)
                    .onSubmit { shell.submit() }
                    .onKeyPress(.upArrow) { shell.browseHistory(-1); return .handled }
                    .onKeyPress(.downArrow) { shell.browseHistory(1); return .handled }
                    .onKeyPress { press in
                        guard press.modifiers.contains(.control) else { return .ignored }
                        switch press.key.character {
                        case "c", "\u{03}": shell.interrupt(); return .handled
                        case "d", "\u{04}": shell.endInput(); return .handled
                        case "l", "\u{0C}": shell.clear(); return .handled
                        default: return .ignored
                        }
                    }
            }
            Text(shell.isRunning ? "ВЫПОЛНЯЕТСЯ… CTRL+C ПРЕРВАТЬ · CTRL+D КОНЕЦ ВВОДА" : "↑↓ ИСТОРИЯ · CTRL+L ОЧИСТИТЬ · EXIT НАЗАД · ESC ЗАКРЫТЬ")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(PlainTerm.dim)
        }
        .font(PlainTerm.font)
        .foregroundStyle(PlainTerm.text)
        .tint(PlainTerm.text)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
    }

    private func transcript(_ shell: ShellSession) -> AttributedString {
        var result = AttributedString()
        for (index, line) in shell.lines.enumerated() {
            var part = AttributedString(line.text)
            switch line.kind {
            case .command: part.font = .system(size: 12, weight: .semibold, design: .monospaced)
            case .output: break
            case .info: part.foregroundColor = PlainTerm.dim
            }
            result += part
            if index < shell.lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

/// Переключатель в заголовке терминала: терминал компаньона или обычный (zsh).
struct TerminalModeSwitch: View {
    var model: ConsoleModel
    var plain: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(model.character == .ab ? "КОГИТАТОР" : "MOTH", active: !model.shellMode) { model.setShellMode(false) }
            segment("ZSH", active: model.shellMode) { model.setShellMode(true) }
        }
        .font(.system(size: 10, design: .monospaced))
        .overlay(Rectangle().strokeBorder(plain ? PlainTerm.line : Term.dark, lineWidth: 1))
        .help("Обычный терминал (zsh) или терминал компаньона. Команда: /shell")
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        let fg = plain ? PlainTerm.text : Term.green
        let bg = plain ? PlainTerm.background : Term.background
        return Text(title)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(active ? bg : (plain ? PlainTerm.dim : Term.dim))
            .background(active ? fg : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
