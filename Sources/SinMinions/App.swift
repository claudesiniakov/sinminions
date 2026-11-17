import AppKit
import SwiftUI
import Observation
import SinMinionsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs()
    private let updater = Updater()
    private let llm = LLMService()
    private let settingsRouter = SettingsRouter()
    private var controller: CompanionController?
    private var statusMenu: StatusMenu?
    private var settingsWindow: NSWindow?
    private var checkTimer: Timer?
    /// Версия, о которой компаньон уже сказал репликой.
    private var announcedVersion: AppVersion?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        LoginItem.repairIfMoved()
        let controller = CompanionController(prefs: prefs)
        self.controller = controller
        prefs.onChange = { [weak controller] in controller?.prefsChanged() }
        updater.beforeRestart = { [weak controller] in controller?.savePosition() }

        controller.onOpenSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        let statusMenu = StatusMenu(controller: controller, updater: updater, prefs: prefs) { [weak self] in
            self?.showSettings()
        }
        self.statusMenu = statusMenu
        controller.onStateChange = { [weak statusMenu] in statusMenu?.refresh() }
        controller.attachChat(
            send: { [weak self] messages in
                guard let self, let connection = self.prefs.connections.active,
                      let key = Keychain.read(connection.keyAccount) else { throw LLMError.noCredentials }
                return try await self.llm.send(messages, connection: connection, key: key)
            },
            hasCredentials: { [weak self] in
                guard let connection = self?.prefs.connections.active else { return false }
                return Keychain.exists(connection.keyAccount)
            },
            speaker: { [weak self] in
                self?.prefs.connections.active?.provider.title.uppercased() ?? "LLM"
            }
        )

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

        if ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil { runDemo(controller) }
    }

    /// Для CI: сцены демонстрации. Перед каждой приложение ставит файл-метку `<имя>.ready`,
    /// по которой оболочка делает снимок экрана (снимать экран само приложение не может).
    private func demoMark(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SINMINIONS_SHOT_DIR"] else { return }
        FileManager.default.createFile(atPath: dir + "/" + name + ".ready", contents: Data())
    }

    private func runDemo(_ controller: CompanionController) {
        Task { @MainActor in
            func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            // Для снимков: три подключения вместо пустого списка.
            if prefs.connections.items.isEmpty {
                let samples: [(String, LLMProvider, String)] = [
                    ("GigaChat", .gigachat, "GigaChat"), ("GigaChat Pro", .gigachat, "GigaChat-2-Pro"),
                    ("DeepSeek", .deepseek, "deepseek-flash"),
                ]
                for (name, provider, model) in samples {
                    prefs.connections.add(LLMConnection(name: name, provider: provider, model: model))
                }
                prefs.connections.setActive(prefs.connections.items[1].id)
            }
            await wait(2)
            controller.announce(.ambient, force: true)
            await wait(1)
            demoMark("screen")
            await wait(3)
            showSettings()
            await wait(1.5)
            demoMark("settings")
            await wait(4)
            settingsRouter.tab = .llm
            await wait(1.5)
            demoMark("llm")
            await wait(4)
            settingsWindow?.close()
            controller.openConsoleForDemo()
            await wait(1.5)
            demoMark("console")
            await wait(4)
            controller.showChatDemo()
            await wait(1.5)
            demoMark("chat")
            await wait(4)
            controller.closeConsoleForDemo()
            await wait(1)
            controller.teleportForDemo()
        }
    }

    /// У приложения без значка в Dock нет меню, а без него не работают ⌘C, ⌘V, ⌘X, ⌘A и ⌘Z в полях ввода
    /// окна настроек. Меню в строке меню не показывается, но сочетания клавиш в нём действуют.
    private func installMainMenu() {
        let main = NSMenu()
        main.addItem(NSMenuItem())
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Окно")
        window.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
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

    private func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsRouter.tab = tab }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                prefs: prefs, updater: updater, router: settingsRouter, llm: llm
            ))
            // Размер окна не диктуется содержимым: иначе на небольшом экране низ уходит под Dock.
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "SinMinions"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Зелёная кнопка разворачивает окно на весь экран (без отдельного полноэкранного пространства).
            window.collectionBehavior = [.fullScreenNone]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 460, height: 320)
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
            let titleBar = window.frame.height - window.contentLayoutRect.height
            let height = min(620, visible.height - titleBar - 16)
            window.setContentSize(NSSize(width: 500, height: max(height, 320)))
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
