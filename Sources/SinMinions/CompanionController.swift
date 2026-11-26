import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import SinMinionsCore

/// Связывает автомат поведения с окном персонажа, пузырём, таймерами и событиями системы.
@MainActor
final class CompanionController: NSObject {
    let prefs: Prefs
    var engine: BehaviorEngine
    private var book = PhraseBook()
    private var bookCharacter = CompanionCharacter.f
    private let panel: NSPanel
    private(set) var view: CompanionView
    private let bubble = BubblePanel()
    private let findPanel = FindPanel()
    private var tvPanel: TVPanel?
    private var tvScale: Double = 0
    private var collectionBehavior: NSWindow.CollectionBehavior = []
    private var playTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    let console = ConsoleController()
    let analytics = AnalyticsWindow()
    private var usage: UsageStore?
    private let portalA = PortalWindow(color: PortalWindow.blue)
    private let portalB = PortalWindow(color: PortalWindow.orange)
    private var teleportTask: Task<Void, Never>?
    /// Меняется при каждом начале и прерывании телепорта: устаревшие шаги не выполняются.
    private var teleportToken = 0
    /// Номер подсказки: новая подсказка или реплика отменяет таймер скрытия прежней.
    private var hintToken = 0
    /// Демо-режим для снимка в CI: порталы остаются открытыми подольше.
    private let demo = ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil
    /// Где призрак был до открытия терминала; nil — терминал закрыт.
    private var consoleHome: CGPoint?

    private var timer: Timer?
    /// Когда в последний раз шагал автомат и проверялись питание и одежда.
    private var lastEngineTick: Double = 0
    private var lastSlowCheck: Double = 0
    /// Курсор не двигается: таймер редкий, пока монитор событий не разбудит.
    private var calmTimer = false
    private var lastMoveAt: Double = 0
    private var mouseMonitors: [Any] = []
    private var nextBlinkAt: Double = 0
    private var lastMouse: CGPoint?
    private var lastMouseTime: Double?
    private var flight: Flight?
    private var flightTimer: Timer?
    /// Сторож выхода из полноэкранного режима: основной таймер в это время выключен.
    private var fullScreenWatch: Timer?
    private var power: PowerState?
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Скрыт пунктом меню.
    private(set) var hiddenByUser = false
    /// Скрыт системой: экран заблокирован или погашен.
    private var suspendedBySystem = false
    /// Скрыт, потому что активное приложение занимает экран целиком.
    private var hiddenForFullScreen = false

    /// Меняется то, что показывает меню (скрыт, спит).
    var onStateChange: () -> Void = {}
    /// Открыть настройки; `nil` — на той вкладке, что открыта.
    var onOpenSettings: (SettingsTab?) -> Void = { _ in }

    private struct Flight {
        let from: CGPoint
        let to: CGPoint
        let start: Double
        let duration: Double
        /// Обычный перелёт (в отличие от перемещения к терминалу и обратно).
        let wander: Bool
        /// Перелёт к курсору: на месте призрак говорит реплику.
        var chase = false
        /// Отгон: на месте призрак говорит реплику.
        var shoo = false
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
    private var isVisible: Bool { !hiddenByUser && !suspendedBySystem && !hiddenForFullScreen }
    var now: Double { Date().timeIntervalSinceReferenceDate }

    init(prefs: Prefs) {
        self.prefs = prefs
        engine = BehaviorEngine(
            config: prefs.behaviorConfig(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
            now: Date().timeIntervalSinceReferenceDate
        )
        let view = CompanionView(scale: prefs.scale, style: prefs.ghostStyle, coffee: prefs.coffee, character: prefs.character, outfit: prefs.outfit)
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
        console.model.switchConnection = { [weak self] delta in self?.switchConnection(delta) }
        console.onSlash = { [weak self] command in self?.perform(command) }
        console.onAdjustSpecial = { [weak self] stat, delta in self?.adjustSpecial(stat, delta) }
        power = Self.readPower()
        applyCharacter()

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
        // Полноэкранный режим: сменилось активное приложение или пространство — проверяем,
        // не занят ли экран целиком, и скрываемся, если так.
        workspace.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        workspace.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )

        panel.orderFrontRegardless()
        startTimer()
        updateFullScreenHide()
        installMouseMonitors()
        // «Помнить кофе»: режим, включённый до перезапуска, снова не даёт ноутбуку уснуть.
        updateCaffeine()
    }

    /// Движение мыши будит редкий таймер сразу, без ожидания следующего тика.
    /// Глобальный монитор движений мыши не требует «Универсального доступа».
    private func installMouseMonitors() {
        let wake: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastMoveAt = self.now
                if self.calmTimer { self.startTimer() }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { _ in wake() }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in wake(); return event }) {
            mouseMonitors.append(local)
        }
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
        let corner = prefs.character == .v && prefs.vikchaRoute == .screenBottom
            ? Layout.walkPoint(figure: view.mothFrame, in: area, fraction: 1)
            : Layout.corner(size: panel.frame.size, in: area, margin: 8)
        panel.setFrameOrigin(corner)
        apply(engine.handle(.dragEnded, now: now))
        savePosition()
    }

    /// Чат по горячей клавише и из меню: открыть, а если уже открыт — закрыть.
    func toggleConsole() {
        if engine.mode == .console {
            apply(engine.handle(.closeConsole, now: now))
        } else {
            // Отдельного события «открыть чат» нет: открытие — это двойной щелчок по персонажу.
            apply(engine.handle(.doubleClick, now: now))
        }
    }

    /// Неназойливая подсказка в пузыре: приветствие при первом запуске, весть об обновлении.
    /// Живёт `seconds` секунд, но любая реплика персонажа её сменяет.
    func showHint(_ text: String, seconds: Double = 6) {
        guard isVisible else { return }
        hintToken += 1
        let token = hintToken
        bubble.show(text, over: liftedMoth, in: area)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.hintToken == token else { return }
            self.bubble.hide()
        }
    }

    /// Первый запуск: как открыть чат.
    func showIntroHint() {
        showHint(tr("Двойной щелчок по мне — чат. Меню — у значка в строке меню."), seconds: 9)
    }

    /// Вышла новая версия: говорим об этом в пузыре, установка — из меню.
    /// Если в заметках к релизу есть первая фраза — показываем и её, чтобы было видно,
    /// что именно изменилось, не открывая меню.
    func announceUpdate(version: String, notes: String = "") {
        if let first = firstSentence(of: notes) {
            showHint(trf("Вышла версия %@. Что нового: %@. Обновить можно из меню", version, first), seconds: 12)
        } else {
            showHint(trf("Вышла версия %@ — обновить можно из меню", version), seconds: 10)
        }
    }

    /// Первая фраза заметок: до точки, восклицательного или вопросительного знака,
    /// не длиннее 120 знаков — пузырь не должен превращаться в стену текста.
    private func firstSentence(of notes: String) -> String? {
        let flat = notes
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        let end = flat.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) ?? flat.endIndex
        let sentence = String(flat[flat.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        guard !sentence.isEmpty else { return nil }
        return sentence.count > 120 ? String(sentence.prefix(120)) + "…" : sentence
    }

    /// Реплика по системному поводу; обычные поводы молчат, если реплики выключены или компаньон спит.
    func announce(_ kind: PhraseKind, force: Bool = false) {
        guard isVisible else { return }
        if !force, !prefs.talkEnabled || engine.mode == .sleeping || engine.mode == .dragged { return }
        apply(engine.handle(.announce(kind), now: now))
    }

    /// Выбранное подключение к нейросети — в модель терминала и монитора.
    private func refreshLLM() {
        let list = prefs.connections
        console.model.chatStaysOpen = prefs.chatStaysOpen
        console.model.chatFont = prefs.chatFont
        console.model.llmName = list.active?.name
        console.model.llmModelName = list.active?.model
        console.model.llmConnections = list.items.filter(\.showLimits)
            .map { LLMConnectionRow(connection: $0, isActive: $0.id == list.active?.id) }
        // Блок «Лимиты» скрыт, только если подключения есть, но ни у одного лимиты не включены.
        console.model.showLimits = list.items.isEmpty || list.items.contains(where: \.showLimits)
        console.model.llmCount = list.chatItems.count
        console.model.llmPosition = list.activePosition.map { "\($0)/\(list.chatItems.count)" } ?? ""
    }

    /// Значения для экрана S.P.E.C.I.A.L. из настроек.
    private func refreshSpecial() {
        let scales = Prefs.scales
        let scaleText = prefs.scale == 1.5 ? "1,5×" : "\(Int(prefs.scale))×"
        console.model.ghostStyle = prefs.ghostStyle
        console.model.coffee = prefs.coffee
        console.model.outfit = prefs.outfit
        console.model.special = SpecialState(
            scaleLevel: scales.firstIndex(of: prefs.scale) ?? 1,
            scaleLabel: tr("РАЗМЕР ") + scaleText,
            perceptionLevel: prefs.ghostStyle.rawValue,
            perceptionLabel: tr("ОБЛИК: ") + prefs.ghostStyle.title,
            agilityLevel: prefs.agility,
            agilityLabel: tr("СКОРОСТЬ ПОЛЁТА: ") + Agility.title(level: prefs.agility),
            enduranceLevel: prefs.endurance,
            enduranceLabel: prefs.character == .ab && prefs.endurance == 0
                ? tr("СПИТ В ПИЖАМЕ")
                : Endurance.title(level: prefs.endurance, sleepMinutes: prefs.sleepMinutes),
            charismaLevel: prefs.charisma,
            charismaLabel: tr("РЕПЛИКИ: ") + Charisma.title(level: prefs.charisma),
            intelligenceLabel: prefs.connections.active.map { tr("ПОДКЛЮЧЕНИЕ: ") + $0.name.uppercased() } ?? tr("НЕТ ПОДКЛЮЧЕНИЙ"),
            intelligenceCount: prefs.connections.chatItems.count
        )
    }

    /// «+» и «−» у характеристики: S — размер, P — облик, C — реплики, E — сон, I — подключение к нейросети, A — скорость полёта.
    private func adjustSpecial(_ stat: SpecialStat, _ delta: Int) {
        switch stat {
        case .strength:
            let scales = Prefs.scales
            let index = scales.firstIndex(of: prefs.scale) ?? 1
            prefs.scale = scales[min(max(index + delta, 0), scales.count - 1)]
        case .agility:
            prefs.agility = Agility.clamp(prefs.agility + delta)
        case .perception:
            prefs.ghostStyleLevel = GhostStyle.clamp(prefs.ghostStyleLevel + delta).rawValue
        case .charisma:
            prefs.charisma = Charisma.clamp(prefs.charisma + delta)
        case .endurance:
            prefs.endurance = Endurance.clamp(prefs.endurance + delta)
            // Из сна «пока не потревожат» выходим сразу, как только он отменён.
            if prefs.endurance != 0, isSleeping, !engine.isNapping {
                apply(engine.handle(.wake, now: now))
            }
        case .intelligence:
            switchConnection(delta, announce: false)
        case .luck:
            break
        }
        refreshSpecial()
    }

    private var caffeineAssertions: [IOPMAssertionID] = []

    /// Режим «кофе»: пока он включён, система и экран не засыпают от бездействия.
    private func updateCaffeine() {
        if prefs.coffee, caffeineAssertions.isEmpty {
            for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep] {
                var id = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                         tr("SinMinions: кофе") as CFString, &id)
                if result == kIOReturnSuccess { caffeineAssertions.append(id) }
            }
        } else if !prefs.coffee, !caffeineAssertions.isEmpty {
            caffeineAssertions.forEach { IOPMAssertionRelease($0) }
            caffeineAssertions = []
        }
    }

    private func refreshLimits() {
        console.model.limits.refresh(prefs.connections.items.filter(\.showLimits))
    }

    /// Как узнавать лимит подключения (остаток токенов или средств) — для блока на мониторе.
    func attachLimits(fetch: @escaping @MainActor (LLMConnection, String) async throws -> String?) {
        console.model.limits.fetch = fetch
    }

    /// Журнал расхода токенов для окна «/аналитика».
    func attachAnalytics(usage: UsageStore) {
        self.usage = usage
    }

    func showAnalytics() {
        guard let usage else { return }
        analytics.show(store: usage, limits: console.model.limits, connections: prefs.connections.items,
                       character: prefs.character, near: console.terminalFrame)
    }

    /// «+» и «−» на мониторе: следующее или предыдущее подключение по кругу.
    private func switchConnection(_ delta: Int, announce: Bool = true) {
        var list = prefs.connections
        guard let active = list.cycle(by: delta) else { return }
        prefs.connections = list
        refreshLLM()
        if announce, !console.model.chat.entries.isEmpty {
            console.model.chat.addInfo(tr("ПОДКЛЮЧЕНИЕ: ") + active.name.uppercased())
        }
    }

    /// Настройки изменились. Пачку изменений подряд (переключатели, степперы) применяем один раз,
    /// через 0,15 с после последнего: перестройка автомата и проверка рисунка — не на каждое касание.
    func prefsChanged() {
        // Подписи на мониторе обновляем сразу — это дёшево, и отклик на «+»/«−» мгновенный.
        console.model.language = L10n.current
        refreshLLM()
        refreshSpecial()
        prefsTask?.cancel()
        prefsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.prefsTask = nil
            self.applyPrefs()
        }
    }

    private var prefsTask: Task<Void, Never>?

    func applyPrefs() {
        prefsTask?.cancel()
        prefsTask = nil
        refreshLLM()
        refreshSpecial()
        if console.isOpen { refreshLimits() }
        updateCaffeine()
        applyCharacter()
        if view.scale != CGFloat(prefs.scale) || view.style != prefs.ghostStyle || view.coffee != prefs.coffee || view.character != prefs.character || view.outfit != prefs.outfit { rebuildView() }
        applyCollectionBehavior()
        updateFullScreenHide()
        engine.reconfigure(prefs.behaviorConfig(lowPower: lowPower), now: now)
    }

    /// Выход из приложения: команда обычного терминала не остаётся работать без окна.
    func prepareForQuit() {
        console.model.shell.terminateRunning()
    }

    func savePosition() {
        // В демонстрации профиль пользователя не трогаем.
        guard !demo else { return }
        // Пока открыт терминал, призрак временно в центре — запоминаем его обычное место.
        let origin = consoleHome ?? panel.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: Keys.x)
        UserDefaults.standard.set(Double(origin.y), forKey: Keys.y)
    }

    /// Подключает чат терминала к клиенту нейросети.
    func attachChat(
        send: @escaping @MainActor ([ChatMessage]) async throws -> String,
        hasCredentials: @escaping () -> Bool,
        speaker: @escaping () -> String
    ) {
        let chat = console.model.chat
        chat.send = send
        chat.hasCredentials = hasCredentials
        chat.speaker = speaker
        chat.needCredentials = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.closeConsole, now: self.now))
            self.onOpenSettings(.llm)
        }
    }

    // MARK: - Телепорт

    private func pause(_ seconds: Double, token: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && token == teleportToken
    }

    /// Синий портал открывается рядом с призраком (сбоку, а если там нет места — под ним), призрак втягивается
    /// в него и выходит из оранжевого, тоже стоящего рядом с новым местом. Порталы не рисуются на самом призраке.
    private func startTeleport() {
        teleportToken += 1
        let token = teleportToken
        let moth = view.mothFrame
        let area = area
        let from = panel.frame.origin
        let target: CGPoint
        if prefs.character == .v, prefs.vikchaRoute == .screenBottom {
            // По низу экрана портал выносит её в другую точку той же линии, без смены высоты.
            target = Self.bottomLineTarget(figure: moth, in: area, from: from)
        } else {
            target = Layout.randomTarget(size: panel.frame.size, in: area, from: from, minDistance: 240)
        }

        // В демо-режиме для снимка в CI порталы рисуются всегда: на раннере «Уменьшение движения» включено.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !demo {
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
        let direction: CGFloat = target.x >= from.x ? 1 : -1
        // Портал А — рядом с призраком, со стороны, куда он полетит. Портал Б — рядом с новым местом, с противоположной
        // стороны: призрак выходит из него и отлетает вперёд.
        let centerA = Layout.portalCenter(beside: moth.offsetBy(dx: from.x, dy: from.y), portal: portalSize, preferring: direction, in: area)
        let centerB = Layout.portalCenter(beside: moth.offsetBy(dx: target.x, dy: target.y), portal: portalSize, preferring: -direction, in: area)
        func origin(forGhostCenter center: CGPoint) -> CGPoint {
            CGPoint(x: center.x - moth.midX, y: center.y - moth.midY)
        }
        let hold = demo ? 4.0 : 0.0
        teleportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.bubble.hide()
            self.portalA.open(center: centerA, size: portalSize, duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            // Призрак втягивается в портал А: летит к нему, сжимаясь и кружась.
            self.view.vanish(duration: 0.35)
            self.glide(to: origin(forGhostCenter: centerA), duration: 0.35)
            guard await self.pause(0.4, token: token) else { return }
            if !self.demo { self.portalA.close(duration: 0.25) }
            self.panel.alphaValue = 0
            self.panel.setFrameOrigin(origin(forGhostCenter: centerB))
            self.portalB.open(center: centerB, size: portalSize, duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            // Выходит из портала Б и отлетает на своё новое место рядом с ним.
            self.panel.alphaValue = 1
            self.view.appear(duration: 0.4)
            self.glide(to: target, duration: 0.45)
            guard await self.pause(0.5 + (self.demo ? 1.0 : 0.0), token: token) else { return }
            if self.demo { self.captureDemoShot() }
            guard await self.pause(hold, token: token) else { return }
            self.portalA.close(duration: 0.25)
            self.portalB.close(duration: 0.3)
            guard await self.pause(0.3, token: token) else { return }
            self.finishTeleport()
        }
    }

    /// Для CI: метка «оба портала открыты, призрак вышел из второго» — по ней оболочка делает снимок.
    private func captureDemoShot() {
        guard let dir = ProcessInfo.processInfo.environment["SINMINIONS_SHOT_DIR"] else { return }
        FileManager.default.createFile(atPath: dir + "/teleport.ready", contents: Data())
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
        stopFlight(snap: false)
        portalA.hide()
        portalB.hide()
        view.clearPortalEffect()
        if isVisible { panel.alphaValue = 1 }
        savePosition()
    }

    // MARK: - Средний режим

    private func openConsole() {
        applyCharacter()
        refreshLLM()
        refreshSpecial()
        refreshLimits()
        let mothSize = view.mothFrame.size
        let area = area
        let place = Layout.console(
            moth: mothSize, terminal: ConsoleController.terminalSize, monitor: ConsoleController.monitorSize, in: area
        )
        // Место призрака с запасом на парение и свечение: окна на него не наезжают.
        let ghost = CGRect(origin: place.moth, size: mothSize).insetBy(dx: -10, dy: -12)
        // Раскладка, заданная пользователем, действует, пока подходит к экрану; иначе — выровненная по умолчанию.
        var terminalRect = place.terminal
        var monitorRect = place.monitor
        if let saved = ConsoleLayoutStore.load(),
           Layout.isValidConsoleLayout(terminal: saved.terminal, monitor: saved.monitor, ghost: ghost, in: area) {
            terminalRect = saved.terminal
            monitorRect = saved.monitor
        }
        console.areaProvider = { [weak self] in self?.area ?? .zero }
        console.ghostRect = ghost
        console.defaultRects = (place.terminal, place.monitor)
        consoleHome = panel.frame.origin
        bubble.hide(animated: false)
        glide(to: CGPoint(x: place.moth.x - view.mothFrame.minX, y: place.moth.y - view.mothFrame.minY))
        console.open(terminalRect: terminalRect, monitorRect: monitorRect)
        // В меню есть строка ввода: клавиатуре нужно ключевое окно.
        console.activateForTyping()
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

    /// Команды со «/» из терминала и чата. Возвращает строку-подтверждение для журнала.
    private func perform(_ command: SlashCommand) -> String? {
        switch command {
        case .nap:
            nap(seconds: 3600)
            return tr("ПРИЗРАК УСНУЛ НА 1 ЧАС")
        case .coffee:
            prefs.coffee.toggle()
            return prefs.coffee ? tr("КОФЕ: НОУТБУК НЕ ЗАСНЁТ, ПОКА ВКЛЮЧЕНО") : tr("КОФЕ ДОПИТ: НОУТБУК СНОВА МОЖЕТ ЗАСНУТЬ")
        case .sing:
            guard prefs.character == .ab else { return tr("ПОЁТ ТОЛЬКО СТРАЖ: ПЕРЕКЛЮЧИТЕ ПЕРСОНАЖА НА ab В НАСТРОЙКАХ") }
            apply(engine.handle(.closeConsole, now: now))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { return }
                self.apply(self.engine.handle(.singCommand, now: self.now))
            }
            return nil
        case .analytics:
            showAnalytics()
            return tr("АНАЛИТИКА ТОКЕНОВ ОТКРЫТА В ОТДЕЛЬНОМ ОКНЕ")
        case .hide:
            setHidden(true)
            return nil
        case .corner:
            if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
                consoleHome = Layout.corner(size: panel.frame.size, in: visible, margin: 8)
            }
            apply(engine.handle(.closeConsole, now: now))
            return nil
        case .unlock:
            console.setUnlocked(true)
            return tr("ОКНА РАЗБЛОКИРОВАНЫ: ДВИГАЙТЕ ЗА ЗАГОЛОВОК, РАЗМЕР — ЗА УГОЛОК ◢")
        case .lock:
            console.setUnlocked(false)
            return tr("ОКНА ЗАБЛОКИРОВАНЫ")
        case .resetLayout:
            console.resetLayout()
            return tr("РАСКЛАДКА ОКОН СБРОШЕНА")
        case .settings:
            apply(engine.handle(.closeConsole, now: now))
            onOpenSettings(nil)
            return nil
        case .next, .previous:
            switchConnection(command == .next ? 1 : -1, announce: false)
            guard let active = prefs.connections.active else { return tr("ПОДКЛЮЧЕНИЙ НЕТ") }
            return tr("ПОДКЛЮЧЕНИЕ: ") + active.name.uppercased() + " · " + active.model.uppercased()
        case .help, .clear, .shell:
            return nil
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
        view.onShoo = { [weak self] in
            guard let self else { return }
            self.apply(self.engine.handle(.shoo, now: self.now))
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

    /// Смена персонажа: реплики и стиль терминала с монитором переключаются на его набор.
    private func applyCharacter() {
        if bookCharacter != prefs.character {
            bookCharacter = prefs.character
            book = PhraseBook(character: prefs.character)
        }
        console.model.character = prefs.character
        bubble.character = prefs.character
        console.model.language = L10n.current
    }


    /// Смена одежды по времени: раз в полминуты проверяем, не пора ли надеть пижаму или доспех.
    private func checkOutfit() {
        guard view.outfit != prefs.outfit else { return }
        applyPrefs()
    }

    private func rebuildView() {
        let wasSleeping = isSleeping
        let old = panel.frame
        view = CompanionView(scale: prefs.scale, style: prefs.ghostStyle, coffee: prefs.coffee, character: prefs.character, outfit: prefs.outfit)
        wire(view)
        // Низ и середина по горизонтали остаются на месте.
        let size = view.frame.size
        let origin = CGPoint(x: old.midX - size.width / 2, y: old.minY)
        panel.setFrame(CGRect(origin: clamped(origin, size: size), size: size), display: false)
        panel.contentView = view
        view.setSleeping(wasSleeping)
        bubble.hide(animated: false)
        savePosition()
        // Призрак другого размера занимает другое место: окна не должны наезжать на него.
        if console.isOpen {
            console.ghostRect = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY).insetBy(dx: -10, dy: -12)
        }
    }

    private func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Без этого флага окно не показывается поверх полноэкранных приложений.
        if !prefs.hideInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
        bubble.setCollectionBehavior(behavior)
        findPanel.setCollectionBehavior(behavior)
        collectionBehavior = behavior
        tvPanel?.setCollectionBehavior(behavior)
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
            view.setPaused(false)
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
            view.setPaused(true)
        }
        onStateChange()
    }

    // MARK: - Таймер

    /// Один таймер на всё: 10 раз в секунду — мышь и глаза (во сне 5), раз в секунду — автомат.
    /// Если курсор стоит больше 3 секунд, таймер редкий (2 раза в секунду, во сне раз в секунду),
    /// а первое же движение мыши возвращает частый.
    private func startTimer(calm: Bool = false) {
        timer?.invalidate()
        timer = nil
        calmTimer = calm
        guard isVisible else { return }
        let interval = calm ? (isSleeping ? 1.0 : 0.5) : (isSleeping ? 0.2 : 0.1)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fastTick() }
        }
        timer.tolerance = interval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var windowPosition: CGFloat = 0.75
    private var nextWindowCheck: Double = 0
    /// WindowServer перечисляет окна спереди назад в координатах с началом вверху основного экрана.
    private func windowWalkTarget(at fraction: CGFloat) -> CGPoint? {
        guard prefs.character == .v, prefs.vikchaRoute == .windowEdge,
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let screen = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let figure = view.mothFrame
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? Int32 == application.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let rect = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = rect["X"], let y = rect["Y"], let w = rect["Width"], let h = rect["Height"],
                  w >= figure.width, h >= figure.height else { continue }
            let frame = CGRect(x: x, y: screen.frame.maxY - y - h, width: w, height: h)
            let visible = NSScreen.screens.map { $0.visibleFrame.intersection(frame) }
                .filter { !$0.isNull && $0.width >= figure.width && $0.height >= figure.height }
                .max { $0.width * $0.height < $1.width * $1.height }
            guard let visible else { continue }
            return clamped(CGPoint(x: visible.minX + fraction * (visible.width - figure.width) - figure.minX,
                                   y: visible.minY - figure.minY), size: panel.frame.size)
        }
        return nil
    }

    /// Телепорт в плоскости линии низа: та же высота, но далеко по горизонтали.
    private static func bottomLineTarget(figure: CGRect, in area: CGRect, from origin: CGPoint) -> CGPoint {
        var best = origin
        for _ in 0..<8 {
            let candidate = Layout.walkPoint(figure: figure, in: area, fraction: .random(in: 0...1))
            if abs(candidate.x - origin.x) >= 240 { return candidate }
            if abs(candidate.x - origin.x) > abs(best.x - origin.x) { best = candidate }
        }
        return best
    }

    private func fastTick() {
        if prefs.character == .v, prefs.vikchaRoute == .windowEdge, flight == nil, !view.isDragging,
           engine.mode == .idle, now >= nextWindowCheck {
            nextWindowCheck = now + 0.45
            if let target = windowWalkTarget(at: windowPosition), target != panel.frame.origin {
                panel.setFrameOrigin(target)
                followBubble()
            }
        }
        // Только когда она «живёт» на экране: в терминале её держит раскладка, при перетаскивании — курсор.
        if prefs.character == .v, prefs.vikchaRoute == .screenBottom, flight == nil, !view.isDragging,
           engine.mode == .idle || engine.mode == .wandering {
            // Ноги держим на линии низа: после смены размера, экрана или возврата из терминала.
            if let area = (panel.screen ?? NSScreen.main)?.visibleFrame {
                let line = Layout.walkPoint(figure: view.mothFrame, in: area, fraction: 0)
                if abs(panel.frame.origin.y - line.y) > 0.5 {
                    panel.setFrameOrigin(CGPoint(x: panel.frame.origin.x, y: line.y))
                    followBubble()
                }
            }
        }
        let mouse = NSEvent.mouseLocation
        if !view.isDragging {
            let inside = view.silhouetteContains(screenPoint: mouse)
            if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        }
        let time = now
        // Испуг: курсор быстро пронёсся рядом с призраком.
        if let last = lastMouse, let lastTime = lastMouseTime, !isSleeping, !view.isDragging,
           engine.mode == .idle || engine.mode == .wandering {
            let dt = time - lastTime
            if dt > 0.02, dt < 0.5 {
                let speed = hypot(mouse.x - last.x, mouse.y - last.y) / dt
                let near = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY).insetBy(dx: -140, dy: -140)
                if speed > 1500, near.contains(mouse) { apply(engine.handle(.scare, now: time)) }
            }
        }
        // Прятки: курсор подошёл к почти невидимому призраку — он выскакивает.
        if engine.mode == .hiding, !view.isDragging {
            let near = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY).insetBy(dx: -90, dy: -90)
            if near.contains(mouse) { apply(engine.handle(.reveal, now: time)) }
        }
        // Запасной путь: движение над своими окнами монитор событий может не увидеть.
        if let last = lastMouse, last != mouse {
            lastMoveAt = time
            if calmTimer { startTimer() }
        }
        lastMouse = mouse
        lastMouseTime = time
        if !isSleeping {
            view.look(at: mouse)
            if time >= nextBlinkAt {
                if nextBlinkAt > 0 { view.blink() }
                nextBlinkAt = time + Double.random(in: 3...7)
            }
        }
        // Курсор стоит, ничего не летит и не тащится — переходим на редкий таймер.
        if lastMoveAt == 0 { lastMoveAt = time }
        if !calmTimer, time - lastMoveAt > 3, flight == nil, !view.isDragging, engine.mode != .hiding {
            startTimer(calm: true)
        }
        guard time - lastEngineTick >= 0.95 else { return }
        lastEngineTick = time
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        apply(engine.tick(now: time, idleSeconds: idle))
        if time - lastSlowCheck >= 30 {
            lastSlowCheck = time
            checkPower()
            checkOutfit()
        }
    }

    // MARK: - Эффекты автомата

    func apply(_ effects: [Effect]) {
        guard !effects.isEmpty else { return }
        let sleptBefore = isSleepingShown
        for effect in effects {
            switch effect {
            case .startWander: startFlight()
            case .stopWander: stopFlight()
            case let .say(kind): say(kind)
            case .hideBubble:
                bubble.hide()
                findPanel.hide()
            case .startSearch: startSearch()
            case .stopSearch: stopSearch()
            case .showFind:
                showFind()
                view.bow()
            case .startPlay: startPlay()
            case .stopPlay: stopPlay()
            case .startSing: startSing()
            case .stopSing: stopSing()
            case .fallAsleep:
                bubble.hide()
                view.setSleeping(true)
            case .wakeUp: view.setSleeping(false)
            case .hop: view.hop()
            case .openConsole: openConsole()
            case .closeConsole: closeConsole(returnHome: !view.isDragging)
            case .startTeleport: startTeleport()
            case .shake: view.shake()
            case .spin:
                if view.isGolden { view.cheer() } else { view.spin() }
            case .fadeOut:
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.6
                panel.animator().alphaValue = 0.1
                NSAnimationContext.endGrouping()
            case .fadeIn:
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                panel.animator().alphaValue = 1
                NSAnimationContext.endGrouping()
            case .startChase: startChase()
            case .startShoo: startShoo()
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

    // MARK: - Поиск

    /// Призрак ищет: каждые пару секунд перелетает в соседнюю точку и приговаривает.
    private func startSearch() {
        searchTask?.cancel()
        findPanel.hide()
        searchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.engine.mode == .searching else { return }
                self.say(.searching)
                let from = self.panel.frame.origin
                let step = CGPoint(x: from.x + CGFloat.random(in: -140...140), y: from.y + CGFloat.random(in: -50...50))
                self.glide(to: self.clamped(step, size: self.panel.frame.size), duration: 1.1)
                try? await Task.sleep(for: .seconds(2.4))
            }
        }
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        stopFlight()
    }

    /// Находка: предмет появляется рядом с призраком, он радуется и говорит про запас.
    private func showFind() {
        let find = SearchFind.pick(for: prefs.character)
        let moth = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        findPanel.show(find, beside: moth, in: area)
        let text = find.phrases.randomElement() ?? find.title
        let lifted = CGRect(x: moth.minX, y: moth.minY, width: moth.width, height: moth.height + 11 * view.scale)
        bubble.show(text, over: lifted, in: area)
    }

    // MARK: - Игра на приставке

    /// Страж садится на пол с геймпадом, рядом появляется телевизор; время от времени он радуется вслух.
    private func startPlay() {
        view.setPlaying(true)
        if tvPanel == nil || tvScale != prefs.scale {
            tvPanel = TVPanel(scale: CGFloat(prefs.scale))
            tvPanel?.setCollectionBehavior(collectionBehavior)
            tvScale = prefs.scale
        }
        let moth = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        tvPanel?.show(beside: moth, in: area)
        playTask?.cancel()
        playTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self, self.engine.mode == .playing else { return }
                self.view.hop()
                self.say(.playing)
            }
        }
    }

    // MARK: - Песня

    private var singTask: Task<Void, Never>?

    /// Страж поёт гимн: строка за строкой в облачке, рот открыт, над головой ноты; на последней строке кричит «В бой!».
    private func startSing() {
        view.setSinging(true)
        singTask?.cancel()
        singTask = Task { @MainActor [weak self] in
            for (index, line) in Anthem.lines.enumerated() {
                guard !Task.isCancelled, let self, self.engine.mode == .singing else { return }
                let moth = self.view.mothFrame.offsetBy(dx: self.panel.frame.minX, dy: self.panel.frame.minY)
                let lifted = CGRect(x: moth.minX, y: moth.minY, width: moth.width, height: moth.height + 11 * self.view.scale)
                self.bubble.show(line, over: lifted, in: self.area)
                if index == Anthem.lines.count - 1 { self.view.cheer() }
                try? await Task.sleep(for: .seconds(Anthem.secondsPerLine))
            }
        }
    }

    private func stopSing() {
        singTask?.cancel()
        singTask = nil
        view.setSinging(false)
        bubble.hide()
    }

    private func stopPlay() {
        playTask?.cancel()
        playTask = nil
        view.setPlaying(false)
        tvPanel?.hide()
        bubble.hide()
    }

    private func say(_ kind: PhraseKind) {
        hintToken += 1
        let hour = Calendar.current.component(.hour, from: Date())
        let text = book.next(kind, hour: hour)
        bubble.show(text, over: liftedMoth, in: area)
    }

    /// Персонаж в координатах экрана с запасом над головой под парение.
    private var liftedMoth: CGRect {
        let moth = view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        return CGRect(x: moth.minX, y: moth.minY, width: moth.width, height: moth.height + 11 * view.scale)
    }

    /// Реплика идёт за персонажем: он шагает по окну или летит, а пузырь остаётся у головы.
    private func followBubble() {
        bubble.follow(over: liftedMoth, in: area)
    }

    // MARK: - Перелёт

    private func startFlight(to explicit: CGPoint? = nil, chase: Bool = false) {
        let from = panel.frame.origin
        let to: CGPoint
        if let explicit {
            to = explicit
        } else if prefs.character == .v && prefs.vikchaRoute == .windowEdge {
            windowPosition = windowPosition > 0.5 ? .random(in: 0.05...0.40) : .random(in: 0.60...0.95)
            to = windowWalkTarget(at: windowPosition) ?? Layout.randomTarget(size: panel.frame.size, in: area, from: from)
        } else if prefs.character == .v && prefs.vikchaRoute == .screenBottom {
            windowPosition = windowPosition > 0.5 ? .random(in: 0.05...0.35) : .random(in: 0.65...0.95)
            to = Layout.walkPoint(figure: view.mothFrame, in: area, fraction: windowPosition)
        } else {
            to = Layout.randomTarget(size: panel.frame.size, in: area, from: from)
        }
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
        // По низу экрана она идёт пешком — но только когда это прогулка по маршруту:
        // погоня за курсором и выход из терминала остаются полётом в любую точку.
        let walking = prefs.character == .v && prefs.vikchaRoute == .screenBottom && explicit == nil && !chase
        let speed = walking ? Agility.walkSpeed(level: prefs.agility) : Double.random(in: prefs.flightSpeedRange)
        let distance = Double(hypot(to.x - from.x, to.y - from.y))
        flight = Flight(from: from, to: to, start: now, duration: max(distance / speed, walking ? 0.6 : 0.5), wander: true, chase: chase)
        startFlightTimer()
    }

    /// Быстрое перемещение к терминалу и обратно.
    private func glide(to target: CGPoint, duration: Double = 0.45) {
        stopFlight(snap: false)
        flight = Flight(from: panel.frame.origin, to: target, start: now, duration: duration, wander: false)
        startFlightTimer()
    }

    private func startFlightTimer() {
        view.setWalking(true)
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
        followBubble()
        if progress >= 1 { finishFlight() }
    }

    /// Подлёт к курсору: призрак встаёт рядом с ним, со стороны центра экрана, и говорит реплику.
    private func startChase() {
        let mouse = NSEvent.mouseLocation
        let moth = view.mothFrame
        let side: CGFloat = mouse.x > area.midX ? -1 : 1
        let center = CGPoint(x: mouse.x + side * 110, y: mouse.y - 20)
        let origin = CGPoint(x: center.x - moth.midX, y: center.y - moth.midY)
        startFlight(to: clamped(origin, size: panel.frame.size), chase: true)
    }

    /// Отгон: быстрый отлёт к краю экрана, который дальше от курсора.
    private func startShoo() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        let from = panel.frame.origin
        let awayRight = mouse.x < area.midX
        let margin: CGFloat = 8
        let x = awayRight ? area.maxX - size.width - margin : area.minX + margin
        let target = clamped(CGPoint(x: x, y: from.y), size: size)
        let distance = Double(hypot(target.x - from.x, target.y - from.y))
        flight = Flight(from: from, to: target, start: now, duration: max(distance / 900, 0.25), wander: true, shoo: true)
        startFlightTimer()
    }

    private func finishFlight() {
        let finished = flight
        stopFlight()
        guard finished?.wander ?? true else { return }
        apply(engine.handle(.arrived, now: now))
        if finished?.chase == true { announce(.curious) }
        if finished?.shoo == true { announce(.shooed) }
    }

    /// `snap` — прерванное перемещение к терминалу или обратно сразу довести до цели
    /// (обычный перелёт просто останавливается там, где его прервали).
    private func stopFlight(snap: Bool = true) {
        view.setWalking(false)
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
            // Радуется, если танец включён; иначе просто говорит.
            let effects = engine.handle(.celebrate(.charging), now: now)
            if effects.isEmpty { announce(.charging) } else { apply(effects) }
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
        if console.isOpen {
            console.keepOnScreen(in: area, ghost: view.mothFrame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY))
        }
        updateFullScreenHide()
    }

    /// Это уведомление система может прислать не из главного потока (как и смену режима питания).
    @objc private nonisolated func frontmostAppChanged() {
        Task { @MainActor in self.updateFullScreenHide() }
    }

    /// Свайп на другое пространство. Персонаж виден везде, а окна терминала остаются на прежнем
    /// пространстве — и двойной щелчок считал, что чат открыт, и закрывал его вместо открытия.
    /// Поэтому при смене пространства чат закрывается: следующий двойной щелчок открывает его заново.
    @objc private nonisolated func spaceChanged() {
        Task { @MainActor in
            if self.engine.mode == .console {
                self.apply(self.engine.handle(.closeConsole, now: self.now))
            }
            self.updateFullScreenHide()
        }
    }

    /// Скрывается ли компаньон, потому что активное приложение занимает экран целиком.
    /// Настройка «Скрывать в полноэкранных приложениях» по умолчанию включена.
    private func updateFullScreenHide() {
        var shouldHide = false
        if prefs.hideInFullScreen,
           let front = NSWorkspace.shared.frontmostApplication,
           let screen = (panel.screen ?? NSScreen.main)?.frame {
            shouldHide = FullScreenCover.covers(
                screen: screen,
                windows: Self.windowInfos(),
                frontmostPID: front.processIdentifier,
                ownPID: ProcessInfo.processInfo.processIdentifier
            )
        }
        guard shouldHide != hiddenForFullScreen else { return }
        hiddenForFullScreen = shouldHide
        // Пока скрыты из-за полноэкранного режима, основной таймер выключен: следим отдельным,
        // иначе выход из полноэкранного режима без смены приложения оставил бы компаньона скрытым.
        if shouldHide { startFullScreenWatch() } else { stopFullScreenWatch() }
        updateVisibility()
    }

    private func startFullScreenWatch() {
        guard fullScreenWatch == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreenHide() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        fullScreenWatch = timer
    }

    private func stopFullScreenWatch() {
        fullScreenWatch?.invalidate()
        fullScreenWatch = nil
    }

    /// Окна WindowServer в координатах AppKit: он отдаёт их от верхнего левого угла основного экрана.
    private static func windowInfos() -> [FullScreenCover.Window] {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let rect = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = rect["X"], let y = rect["Y"],
                  let w = rect["Width"], let h = rect["Height"] else { return nil }
            return FullScreenCover.Window(
                ownerPID: pid,
                layer: layer,
                bounds: CGRect(x: x, y: mainHeight - y - h, width: w, height: h),
                isOnScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
            )
        }
    }
}
