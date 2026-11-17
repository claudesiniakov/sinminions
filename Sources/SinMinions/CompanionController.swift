import AppKit
import IOKit.ps
import SinMinionsCore

/// Связывает автомат поведения с окном персонажа, пузырём, таймерами и событиями системы.
@MainActor
final class CompanionController: NSObject {
    private let prefs: Prefs
    private var engine: BehaviorEngine
    private var book = PhraseBook()
    private let panel: NSPanel
    private var view: CompanionView
    private let bubble = BubblePanel()
    private let console = ConsoleController()
    private let portalA = PortalWindow(color: PortalWindow.blue)
    private let portalB = PortalWindow(color: PortalWindow.orange)
    private var teleportTask: Task<Void, Never>?
    /// Меняется при каждом начале и прерывании телепорта: устаревшие шаги не выполняются.
    private var teleportToken = 0
    /// Демо-режим для снимка в CI: порталы остаются открытыми подольше.
    private let demo = ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil
    /// Где призрак был до открытия терминала; nil — терминал закрыт.
    private var consoleHome: CGPoint?

    private var timer: Timer?
    private var ticks = 0
    private var nextBlinkAt: Double = 0
    private var flight: Flight?
    private var flightTimer: Timer?
    private var power: PowerState?
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Скрыт пунктом меню.
    private(set) var hiddenByUser = false
    /// Скрыт системой: экран заблокирован или погашен.
    private var suspendedBySystem = false

    /// Меняется то, что показывает меню (скрыт, спит).
    var onStateChange: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private struct Flight {
        let from: CGPoint
        let to: CGPoint
        let start: Double
        let duration: Double
        /// Обычный перелёт (в отличие от перемещения к терминалу и обратно).
        let wander: Bool
    }

    private struct PowerState: Equatable {
        let onAC: Bool
        let percent: Int
    }

    private enum Keys {
        static let x = "positionX"
        static let y = "positionY"
    }

    var isSleeping: Bool { engine.mode == .sleeping }
    private var isVisible: Bool { !hiddenByUser && !suspendedBySystem }
    private var now: Double { Date().timeIntervalSinceReferenceDate }

    init(prefs: Prefs) {
        self.prefs = prefs
        engine = BehaviorEngine(
            config: prefs.behaviorConfig(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
            now: Date().timeIntervalSinceReferenceDate
        )
        let view = CompanionView(scale: prefs.scale)
        self.view = view
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: view.frame.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = view
        wire(view)
        applyCollectionBehavior()
        restorePosition()
        console.onDismiss = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.closeConsole, now: self.now))
        }
        console.onCommand = { [weak self] command in self?.run(command) }
        power = Self.readPower()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenWentAway), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenCameBack), name: NSWorkspace.screensDidWakeNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenWentAway), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenCameBack), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerModeChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil
        )

        panel.orderFrontRegardless()
        startTimer()
    }

    // MARK: - Команды меню и настроек

    func setHidden(_ hidden: Bool) {
        guard hidden != hiddenByUser else { return }
        hiddenByUser = hidden
        updateVisibility()
    }

    func nap(seconds: Double) {
        apply(engine.handle(.nap(seconds), now: now))
    }

    func wake() {
        apply(engine.handle(.wake, now: now))
    }

    func returnToCorner() {
        guard let area = NSScreen.main?.visibleFrame else { return }
        apply(engine.handle(.dragBegan, now: now))
        panel.setFrameOrigin(Layout.corner(size: panel.frame.size, in: area, margin: 8))
        apply(engine.handle(.dragEnded, now: now))
        savePosition()
    }

    /// Реплика по системному поводу; обычные поводы молчат, если реплики выключены или компаньон спит.
    func announce(_ kind: PhraseKind, force: Bool = false) {
        guard isVisible else { return }
        if !force, !prefs.talkEnabled || engine.mode == .sleeping || engine.mode == .dragged { return }
        apply(engine.handle(.announce(kind), now: now))
    }

    func prefsChanged() {
        if view.scale != CGFloat(prefs.scale) { rebuildView() }
        applyCollectionBehavior()
        engine.reconfigure(prefs.behaviorConfig(lowPower: lowPower), now: now)
    }

    func savePosition() {
        // Пока открыт терминал, призрак временно в центре — запоминаем его обычное место.
        let origin = consoleHome ?? panel.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: Keys.x)
        UserDefaults.standard.set(Double(origin.y), forKey: Keys.y)
    }

    /// Для снимка в CI: открывает терминал и монитор независимо от выбранного режима.
    func openConsoleForDemo() {
        var config = prefs.behaviorConfig(lowPower: lowPower)
        config.consoleEnabled = true
        engine.reconfigure(config, now: now)
        apply(engine.handle(.doubleClick, now: now))
    }

    func closeConsoleForDemo() {
        apply(engine.handle(.closeConsole, now: now))
    }

    func teleportForDemo() {
        apply(engine.handle(.teleportNow, now: now))
    }

    // MARK: - Телепорт

    private func pause(_ seconds: Double, token: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && token == teleportToken
    }

    /// Синий портал открывается под призраком, он втягивается и выходит из оранжевого в другой точке.
    private func startTeleport() {
        teleportToken += 1
        let token = teleportToken
        let moth = view.mothFrame
        let from = panel.frame.origin
        let target = Layout.randomTarget(size: panel.frame.size, in: area, from: from, minDistance: 240)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // «Уменьшение движения»: без порталов — плавное исчезновение и появление на новом месте.
            teleportTask = Task { @MainActor [weak self] in
                guard let self else { return }
                self.bubble.hide()
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                self.panel.animator().alphaValue = 0
                NSAnimationContext.endGrouping()
                guard await self.pause(0.35, token: token) else { return }
                self.panel.setFrameOrigin(target)
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                self.panel.animator().alphaValue = 1
                NSAnimationContext.endGrouping()
                guard await self.pause(0.35, token: token) else { return }
                self.finishTeleport()
            }
            return
        }

        let portalSize = CGSize(width: moth.width * 0.75, height: moth.height * 1.25)
        let source = CGPoint(x: from.x + moth.midX, y: from.y + moth.midY)
        let destination = CGPoint(x: target.x + moth.midX, y: target.y + moth.midY)
        let hold = demo ? 3.0 : 0.0
        teleportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.bubble.hide()
            self.portalA.open(center: source, size: portalSize, duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            self.view.vanish(duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            self.panel.alphaValue = 0
            self.panel.setFrameOrigin(target)
            self.portalB.open(center: destination, size: portalSize, duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            self.panel.alphaValue = 1
            self.view.appear(duration: 0.3)
            guard await self.pause(0.3 + hold, token: token) else { return }
            self.portalA.close(duration: 0.3)
            self.portalB.close(duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            self.finishTeleport()
        }
    }

    private func finishTeleport() {
        teleportTask = nil
        savePosition()
        apply(engine.handle(.teleportDone, now: now))
        // Иногда — реплика о том, что произошло.
        if Int.random(in: 0..<3) == 0 { announce(.teleport) }
    }

    /// Прерванный телепорт (перетаскивание, щелчок, скрытие): порталы исчезают сразу, призрак виден.
    private func stopTeleport() {
        teleportToken += 1
        teleportTask?.cancel()
        teleportTask = nil
        portalA.hide()
        portalB.hide()
        view.clearPortalEffect()
        if isVisible { panel.alphaValue = 1 }
        savePosition()
    }

    // MARK: - Средний режим

    private func openConsole() {
        let mothSize = view.mothFrame.size
        let terminalSize = ConsoleController.terminalSize
        let monitorSize = CGSize(
            width: ConsoleController.monitorWidth,
            height: max(mothSize.height + 16 + terminalSize.height, ConsoleController.monitorMinHeight)
        )
        let place = Layout.console(moth: mothSize, terminal: terminalSize, monitor: monitorSize, in: area)
        consoleHome = panel.frame.origin
        bubble.hide(animated: false)
        glide(to: CGPoint(x: place.moth.x - view.mothFrame.minX, y: place.moth.y - view.mothFrame.minY))
        console.open(
            terminalFrame: CGRect(origin: place.terminal, size: terminalSize),
            monitorFrame: CGRect(origin: place.monitor, size: monitorSize)
        )
        onStateChange()
    }

    private func closeConsole(returnHome: Bool) {
        console.close()
        let home = consoleHome
        consoleHome = nil
        if returnHome, let home {
            glide(to: clamped(home, size: panel.frame.size))
        } else {
            stopFlight(snap: false)
        }
        onStateChange()
    }

    private func run(_ command: ConsoleCommand) {
        switch command {
        case .spotlight:
            apply(engine.handle(.closeConsole, now: now))
            // Даём терминалу отдать клавиатуру, затем нажимаем сочетание Spotlight.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.openSpotlight()
            }
        case .nap:
            nap(seconds: 3600)
        case .hide:
            setHidden(true)
        case .corner:
            if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                consoleHome = Layout.corner(size: panel.frame.size, in: visible, margin: 8)
            }
            apply(engine.handle(.closeConsole, now: now))
        case .settings:
            apply(engine.handle(.closeConsole, now: now))
            onOpenSettings()
        }
    }

    // MARK: - Окно

    private func wire(_ view: CompanionView) {
        view.onClick = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.click, now: self.now))
        }
        view.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.doubleClick, now: self.now))
        }
        view.onDragBegan = { [weak self] in
            guard let self else { return }
            self.stopFlight(snap: false)
            self.apply(self.engine.handle(.dragBegan, now: self.now))
        }
        view.onDragMoved = { [weak self] origin in
            guard let self else { return }
            // Перетаскивать можно на любой экран: ограничиваем экраном под курсором.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? self.panel.screen ?? NSScreen.main
            let area = screen?.visibleFrame ?? self.panel.frame
            self.panel.setFrameOrigin(Layout.clamp(origin: origin, size: self.panel.frame.size, in: area))
        }
        view.onDragEnded = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.dragEnded, now: self.now))
            self.savePosition()
        }
    }

    private func rebuildView() {
        let wasSleeping = isSleeping
        let old = panel.frame
        view = CompanionView(scale: prefs.scale)
        wire(view)
        // Низ и середина по горизонтали остаются на месте.
        let size = view.frame.size
        let origin = CGPoint(x: old.midX - size.width / 2, y: old.minY)
        panel.setFrame(CGRect(origin: clamped(origin, size: size), size: size), display: false)
        panel.contentView = view
        view.setSleeping(wasSleeping)
        bubble.hide(animated: false)
        savePosition()
    }

    private func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Без этого флага окно не показывается поверх полноэкранных приложений.
        if !prefs.hideInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
        bubble.setCollectionBehavior(behavior)
        console.setCollectionBehavior(behavior)
        portalA.setCollectionBehavior(behavior)
        portalB.setCollectionBehavior(behavior)
    }

    private var area: CGRect {
        (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
    }

    private func clamped(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return Layout.clamp(origin: origin, size: size, in: visible)
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        let size = panel.frame.size
        if let x = defaults.object(forKey: Keys.x) as? Double, let y = defaults.object(forKey: Keys.y) as? Double {
            panel.setFrameOrigin(clamped(CGPoint(x: x, y: y), size: size))
        } else if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(Layout.corner(size: size, in: visible, margin: 8))
        }
    }

    private func updateVisibility() {
        if isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            view.startFloating()
            apply(engine.handle(.resumed, now: now))
            startTimer()
        } else {
            apply(engine.handle(.suspended, now: now))
            stopFlight()
            bubble.hide(animated: false)
            timer?.invalidate()
            timer = nil
            panel.orderOut(nil)
        }
        onStateChange()
    }

    // MARK: - Таймер

    /// Один таймер на всё: 10 раз в секунду — мышь и глаза, раз в секунду — автомат (во сне вдвое реже).
    private func startTimer() {
        timer?.invalidate()
        guard isVisible else { return }
        let interval = isSleeping ? 0.2 : 0.1
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fastTick() }
        }
        timer.tolerance = interval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        ticks = 0
    }

    private func fastTick() {
        let mouse = NSEvent.mouseLocation
        if !view.isDragging {
            let inside = view.silhouetteContains(screenPoint: mouse)
            if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        }
        let time = now
        if !isSleeping {
            view.look(at: mouse)
            if time >= nextBlinkAt {
                if nextBlinkAt > 0 { view.blink() }
                nextBlinkAt = time + Double.random(in: 3...7)
            }
        }
        ticks += 1
        let perSecond = isSleeping ? 5 : 10
        guard ticks % perSecond == 0 else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        apply(engine.tick(now: time, idleSeconds: idle))
        if ticks % (perSecond * 30) == 0 { checkPower() }
    }

    // MARK: - Эффекты автомата

    private func apply(_ effects: [Effect]) {
        guard !effects.isEmpty else { return }
        let sleptBefore = isSleepingShown
        for effect in effects {
            switch effect {
            case .startWander: startFlight()
            case .stopWander: stopFlight()
            case let .say(kind): say(kind)
            case .hideBubble: bubble.hide()
            case .fallAsleep:
                bubble.hide()
                view.setSleeping(true)
            case .wakeUp: view.setSleeping(false)
            case .hop: view.hop()
            case .openSpotlight: openSpotlight()
            case .openConsole: openConsole()
            case .closeConsole: closeConsole(returnHome: !view.isDragging)
            case .startTeleport: startTeleport()
            case .stopTeleport: stopTeleport()
            }
        }
        if sleptBefore != isSleeping {
            isSleepingShown = isSleeping
            startTimer()
            onStateChange()
        }
    }

    private var isSleepingShown = false

    private func say(_ kind: PhraseKind) {
        let hour = Calendar.current.component(.hour, from: Date())
        let text = book.next(kind, hour: hour)
        let moth = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        // Над головой оставляем место под парение.
        let lifted = CGRect(x: moth.minX, y: moth.minY, width: moth.width, height: moth.height + 11 * view.scale)
        bubble.show(text, over: lifted, in: area)
    }

    private func openSpotlight() {
        switch SpotlightLauncher.open() {
        case .sent: break
        case .needAccess: announce(.needAccess, force: true)
        case .disabled: announce(.spotlightOff, force: true)
        }
    }

    // MARK: - Перелёт

    private func startFlight() {
        let from = panel.frame.origin
        let to = Layout.randomTarget(size: panel.frame.size, in: area, from: from)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // «Уменьшение движения»: вместо перелёта — плавное появление в новой точке.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.engine.mode == .wandering else { return }
                    self.panel.setFrameOrigin(to)
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        self.panel.animator().alphaValue = 1
                    }
                    self.finishFlight()
                }
            })
            return
        }
        let speed = Double.random(in: 40...80)
        let distance = Double(hypot(to.x - from.x, to.y - from.y))
        flight = Flight(from: from, to: to, start: now, duration: max(distance / speed, 0.5), wander: true)
        startFlightTimer()
    }

    /// Быстрое перемещение к терминалу и обратно.
    private func glide(to target: CGPoint, duration: Double = 0.45) {
        stopFlight(snap: false)
        flight = Flight(from: panel.frame.origin, to: target, start: now, duration: duration, wander: false)
        startFlightTimer()
    }

    private func startFlightTimer() {
        flightTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flightStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flightTimer = timer
    }

    private func flightStep() {
        guard let flight else { return }
        let progress = (now - flight.start) / flight.duration
        let k = CGFloat(Layout.ease(progress))
        panel.setFrameOrigin(CGPoint(
            x: flight.from.x + (flight.to.x - flight.from.x) * k,
            y: flight.from.y + (flight.to.y - flight.from.y) * k
        ))
        if progress >= 1 { finishFlight() }
    }

    private func finishFlight() {
        let wasWander = flight?.wander ?? true
        stopFlight()
        if wasWander { apply(engine.handle(.arrived, now: now)) }
    }

    /// `snap` — прерванное перемещение к терминалу или обратно сразу довести до цели
    /// (обычный перелёт просто останавливается там, где его прервали).
    private func stopFlight(snap: Bool = true) {
        flightTimer?.invalidate()
        flightTimer = nil
        if let interrupted = flight {
            flight = nil
            if snap, !interrupted.wander { panel.setFrameOrigin(interrupted.to) }
            savePosition()
        }
        if isVisible { panel.alphaValue = 1 }
    }

    // MARK: - Система

    private static func readPower() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            let onAC = description["Power Source State"] as? String == "AC Power"
            return PowerState(onAC: onAC, percent: maximum > 0 ? current * 100 / maximum : current)
        }
        return nil
    }

    private func checkPower() {
        let fresh = Self.readPower()
        defer { power = fresh }
        guard let old = power, let fresh else { return }
        if fresh.onAC, !old.onAC {
            announce(.charging)
        } else if !fresh.onAC, fresh.percent < 20, old.percent >= 20 {
            announce(.lowBattery)
        }
    }

    /// Это уведомление система может прислать не из главного потока.
    @objc private nonisolated func powerModeChanged() {
        Task { @MainActor in
            self.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.engine.reconfigure(self.prefs.behaviorConfig(lowPower: self.lowPower), now: self.now)
        }
    }

    @objc private func systemDidWake() {
        announce(.wake)
    }

    @objc private func screenWentAway() {
        guard !suspendedBySystem else { return }
        suspendedBySystem = true
        if !hiddenByUser { updateVisibility() }
    }

    @objc private func screenCameBack() {
        guard suspendedBySystem else { return }
        suspendedBySystem = false
        if !hiddenByUser { updateVisibility() }
    }

    @objc private func screensChanged() {
        panel.setFrameOrigin(clamped(panel.frame.origin, size: panel.frame.size))
    }
}
