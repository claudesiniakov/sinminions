import AppKit
import SwiftUI
import Observation
import SinMinionsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs()
    private let updater = Updater()
    private var controller: CompanionController?
    private var statusMenu: StatusMenu?
    private var settingsWindow: NSWindow?
    private var checkTimer: Timer?
    /// Версия, о которой компаньон уже сказал репликой.
    private var announcedVersion: AppVersion?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.repairIfMoved()
        let controller = CompanionController(prefs: prefs)
        self.controller = controller
        prefs.onChange = { [weak controller] in controller?.prefsChanged() }
        updater.beforeRestart = { [weak controller] in controller?.savePosition() }

        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        let statusMenu = StatusMenu(controller: controller, updater: updater, prefs: prefs) { [weak self] in
            self?.showSettings()
        }
        self.statusMenu = statusMenu
        controller.onStateChange = { [weak statusMenu] in statusMenu?.refresh() }

        observeUpdater()
        Task { await updater.checkIfDue() }
        // Автопроверка не чаще раза в сутки; таймер лишь даёт ей шанс у долго работающего приложения.
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.updater.checkIfDue() }
            }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer

        if ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                controller.announce(.ambient, force: true)
                // Для снимка в CI: через несколько секунд открываются настройки.
                try? await Task.sleep(for: .seconds(5))
                self.showSettings()
                // …а затем — терминал и монитор среднего режима.
                try? await Task.sleep(for: .seconds(6))
                self.settingsWindow?.close()
                controller.openConsoleForDemo()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.savePosition()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Компаньон один раз говорит о каждой найденной версии.
    private func observeUpdater() {
        withObservationTracking {
            _ = updater.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if case let .available(release) = self.updater.state, self.announcedVersion != release.version {
                    self.announcedVersion = release.version
                    self.controller?.announce(.updateAvailable)
                }
                self.observeUpdater()
            }
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(prefs: prefs, updater: updater))
            // Размер окна не диктуется содержимым: иначе на небольшом экране низ уходит под Dock.
            hosting.sizingOptions = []
            let ideal = hosting.sizeThatFits(in: CGSize(width: 460, height: 10_000))
            let window = NSWindow(contentViewController: hosting)
            window.title = "SinMinions"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Зелёная кнопка разворачивает окно на весь экран (без отдельного полноэкранного пространства).
            window.collectionBehavior = [.fullScreenNone]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 420, height: 280)
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
            let titleBar = window.frame.height - window.contentLayoutRect.height
            let height = min(max(ideal.height, 280), visible.height - titleBar - 16)
            window.setContentSize(NSSize(width: 460, height: height))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow {
            // Окно, оставшееся за краем экрана (сменили монитор), возвращаем в видимую область.
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, !visible.contains(window.frame) {
                var frame = window.frame
                frame.size.height = min(frame.height, visible.height)
                frame.size.width = min(frame.width, visible.width)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                window.setFrame(frame, display: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
enum SinMinionsMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
