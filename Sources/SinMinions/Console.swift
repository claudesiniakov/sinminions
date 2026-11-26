import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

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
    /// Где окно терминала на экране (nil — закрыто): рядом с ним ставим окно аналитики.
    var terminalFrame: CGRect? { isOpen && terminal.isVisible ? terminal.frame : nil }

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
            case .shell: self.model.shell.input += line
            }
            self.model.focusTick += 1
            self.focusInput()
        }
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
    func shellForDemo(_ on: Bool) {
        model.setShellMode(on)
        if on { model.shell.runDemo() }
    }

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
        model.setShellMode(false)
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
        guard isOpen, code == 53 else { return false }
        onDismiss()
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        // По умолчанию чат закрывается, как только фокус ушёл; в настройках это можно выключить,
        // чтобы держать диалог открытым рядом с работой в другом приложении.
        if isOpen, !model.chatStaysOpen { onDismiss() }
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
