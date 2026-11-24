import AppKit
import Observation
import SinMinionsCore

/// Значок Moth в строке меню и меню управления.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let controller: CompanionController
    private let updater: Updater
    private let prefs: Prefs
    private let modeItem = NSMenuItem(title: tr("Режим"), action: nil, keyEquivalent: "")
    private var modeItems: [(CompanionMode, NSMenuItem)] = []
    private let openSettings: () -> Void

    private let hideItem = NSMenuItem(title: tr("Скрыть"), action: #selector(StatusMenu.toggleHidden), keyEquivalent: "")
    private let napItem = NSMenuItem(title: tr("Усыпить на 1 час"), action: #selector(StatusMenu.toggleNap), keyEquivalent: "")
    private let cornerItem = NSMenuItem(title: tr("Вернуть в угол"), action: #selector(StatusMenu.returnToCorner), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(StatusMenu.updateAction), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: tr("Настройки…"), action: #selector(StatusMenu.showSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: tr("Завершить SinMinions"), action: #selector(StatusMenu.quit), keyEquivalent: "q")

    init(controller: CompanionController, updater: Updater, prefs: Prefs, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.updater = updater
        self.prefs = prefs
        self.openSettings = openSettings
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        versionItem.isEnabled = false
        let modes = NSMenu()
        for mode in CompanionMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(StatusMenu.selectMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            modes.addItem(entry)
            modeItems.append((mode, entry))
        }
        modeItem.submenu = modes
        for entry in [hideItem, napItem, cornerItem, .separator(), modeItem, .separator(), versionItem, updateItem, .separator(), settingsItem, quitItem] {
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        item.button?.toolTip = "SinMinions"
        refresh()
        observeUpdater()
        observeCharacter()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    /// Заголовки пунктов и значок по текущему состоянию.
    func refresh() {
        // Подписи на текущем языке (язык меняется в настройках на ходу).
        modeItem.title = tr("Режим")
        cornerItem.title = tr("Вернуть в угол")
        settingsItem.title = tr("Настройки…")
        quitItem.title = tr("Завершить SinMinions")
        for (mode, entry) in modeItems { entry.title = mode.title }
        hideItem.title = controller.hiddenByUser ? tr("Показать") : tr("Скрыть")
        napItem.title = controller.isSleeping ? tr("Разбудить") : tr("Усыпить на 1 час")
        napItem.isEnabled = !controller.hiddenByUser
        cornerItem.isEnabled = !controller.hiddenByUser

        for (mode, entry) in modeItems { entry.state = prefs.mode == mode ? .on : .off }

        versionItem.title = updater.statusLine
        switch updater.state {
        case .idle, .upToDate:
            updateItem.title = tr("Проверить обновления…")
            updateItem.isEnabled = true
        case let .available(release):
            updateItem.title = trf("Обновить до %@", "\(release.version)")
            updateItem.isEnabled = true
        case .failed:
            updateItem.title = tr("Повторить")
            updateItem.isEnabled = true
        case .checking, .downloading, .installing:
            updateItem.title = tr("Обновление…")
            updateItem.isEnabled = false
        }
        item.button?.image = Self.icon(dot: updater.needsAttention, character: prefs.character)
    }

    /// Перерисовываем меню при каждом изменении состояния обновления (в том числе пока оно открыто).
    private func observeUpdater() {
        withObservationTracking {
            _ = updater.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeUpdater()
            }
        }
    }

    /// Значок в строке меню следует за активным персонажем.
    private func observeCharacter() {
        withObservationTracking {
            _ = prefs.character
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeCharacter()
            }
        }
    }

    // MARK: - Действия

    @objc private func toggleHidden() {
        controller.setHidden(!controller.hiddenByUser)
    }

    @objc private func toggleNap() {
        if controller.isSleeping {
            controller.wake()
        } else {
            controller.nap(seconds: 3600)
        }
    }

    @objc private func returnToCorner() {
        controller.returnToCorner()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CompanionMode(rawValue: raw) else { return }
        prefs.mode = mode
        refresh()
    }

    @objc private func updateAction() {
        updater.primaryAction()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        controller.savePosition()
        NSApp.terminate(nil)
    }

    // MARK: - Значок

    /// Силуэт Moth как шаблонное изображение 18×18; точка в углу — есть обновление.
    static func icon(dot: Bool, character: CompanionCharacter = .f) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path: NSBezierPath
            switch character {
            case .f: path = mothPath()
            case .ab: path = guardPath()
            case .v:
                path = NSBezierPath()
                path.move(to: NSPoint(x: 2, y: 3))
                path.line(to: NSPoint(x: 5, y: 3))
                path.line(to: NSPoint(x: 9, y: 11))
                path.line(to: NSPoint(x: 13, y: 3))
                path.line(to: NSPoint(x: 16, y: 3))
                path.line(to: NSPoint(x: 9, y: 16))
                path.close()
            }
            NSColor.black.setFill()
            path.fill()

            if dot, let context = NSGraphicsContext.current {
                let center = NSPoint(x: 14.5, y: 3.5)
                context.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)).fill()
                context.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Силуэт стража: шлем с гребнем и двумя прорезями для глаз, под ним отдельно — раздвоенная борода.
    private static func guardPath() -> NSBezierPath {
        let path = NSBezierPath()
        // Шлем с гребнем.
        path.move(to: NSPoint(x: 3, y: 8.2))
        path.curve(to: NSPoint(x: 9, y: 2.6), controlPoint1: NSPoint(x: 3, y: 4.8), controlPoint2: NSPoint(x: 5.6, y: 2.6))
        path.curve(to: NSPoint(x: 15, y: 8.2), controlPoint1: NSPoint(x: 12.4, y: 2.6), controlPoint2: NSPoint(x: 15, y: 4.8))
        path.close()
        path.appendRect(NSRect(x: 8.1, y: 0.5, width: 1.8, height: 2.3))
        // Прорези для глаз.
        path.append(NSBezierPath(roundedRect: NSRect(x: 5.1, y: 5.2, width: 3, height: 1.6), xRadius: 0.8, yRadius: 0.8))
        path.append(NSBezierPath(roundedRect: NSRect(x: 9.9, y: 5.2, width: 3, height: 1.6), xRadius: 0.8, yRadius: 0.8))
        path.windingRule = .evenOdd
        // Борода: широкая, с вырезом посередине.
        let beard = NSBezierPath()
        beard.move(to: NSPoint(x: 2.6, y: 9.6))
        beard.line(to: NSPoint(x: 15.4, y: 9.6))
        beard.curve(to: NSPoint(x: 12.4, y: 17.6), controlPoint1: NSPoint(x: 15.4, y: 13.6), controlPoint2: NSPoint(x: 14, y: 16.4))
        beard.line(to: NSPoint(x: 9, y: 14.2))
        beard.line(to: NSPoint(x: 5.6, y: 17.6))
        beard.curve(to: NSPoint(x: 2.6, y: 9.6), controlPoint1: NSPoint(x: 4, y: 16.4), controlPoint2: NSPoint(x: 2.6, y: 13.6))
        beard.close()
        path.append(beard)
        return path
    }

    private static func mothPath() -> NSBezierPath {
            let k: CGFloat = 16.0 / 56.0
            let dx = (18 - 48 * k) / 2, dy: CGFloat = 1
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: dx + x * k, y: dy + y * k) }

            let path = NSBezierPath()
            path.move(to: p(4, 24))
            path.curve(to: p(24, 4), controlPoint1: p(4, 12.954), controlPoint2: p(13.163, 4))
            path.curve(to: p(44, 24), controlPoint1: p(34.837, 4), controlPoint2: p(44, 12.954))
            path.line(to: p(44, 44))
            path.curve(to: p(36, 44), controlPoint1: p(44, 44), controlPoint2: p(40, 40))
            path.curve(to: p(24, 44), controlPoint1: p(32, 48), controlPoint2: p(28, 44))
            path.curve(to: p(12, 44), controlPoint1: p(20, 44), controlPoint2: p(16, 48))
            path.curve(to: p(4, 44), controlPoint1: p(8, 40), controlPoint2: p(4, 44))
            path.close()
            // Глаза — прорези в силуэте.
            for center in MothShape.eyeCenters {
                let c = p(center.x, center.y)
                path.appendOval(in: NSRect(x: c.x - 3.4 * k, y: c.y - 4 * k, width: 6.8 * k, height: 8 * k))
            }
            path.windingRule = .evenOdd
            return path
    }
}
