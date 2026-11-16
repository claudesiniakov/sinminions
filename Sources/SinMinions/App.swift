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

        let statusMenu = StatusMenu(controller: controller, updater: updater) { [weak self] in
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
            let window = NSWindow(contentViewController: hosting)
            window.title = "SinMinions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
