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
    private let openSettings: () -> Void

    private let hideItem = NSMenuItem(title: "Скрыть", action: #selector(StatusMenu.toggleHidden), keyEquivalent: "")
    private let napItem = NSMenuItem(title: "Усыпить на 1 час", action: #selector(StatusMenu.toggleNap), keyEquivalent: "")
    private let cornerItem = NSMenuItem(title: "Вернуть в угол", action: #selector(StatusMenu.returnToCorner), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(StatusMenu.updateAction), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(StatusMenu.showSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Завершить SinMinions", action: #selector(StatusMenu.quit), keyEquivalent: "q")

    init(controller: CompanionController, updater: Updater, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.updater = updater
        self.openSettings = openSettings
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        versionItem.isEnabled = false
        for entry in [hideItem, napItem, cornerItem, .separator(), versionItem, updateItem, .separator(), settingsItem, quitItem] {
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        item.button?.toolTip = "SinMinions"
        refresh()
        observeUpdater()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    /// Заголовки пунктов и значок по текущему состоянию.
    func refresh() {
        hideItem.title = controller.hiddenByUser ? "Показать" : "Скрыть"
        napItem.title = controller.isSleeping ? "Разбудить" : "Усыпить на 1 час"
        napItem.isEnabled = !controller.hiddenByUser
        cornerItem.isEnabled = !controller.hiddenByUser

        versionItem.title = updater.statusLine
        switch updater.state {
        case .idle, .upToDate:
            updateItem.title = "Проверить обновления…"
            updateItem.isEnabled = true
        case let .available(release):
            updateItem.title = "Обновить до \(release.version)"
            updateItem.isEnabled = true
        case .failed:
            updateItem.title = "Повторить"
            updateItem.isEnabled = true
        case .checking, .downloading, .installing:
            updateItem.title = "Обновление…"
            updateItem.isEnabled = false
        }
        item.button?.image = Self.icon(dot: updater.needsAttention)
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
    static func icon(dot: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
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
}
