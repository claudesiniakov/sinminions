import AppKit
import SwiftUI
import Observation
import SinMinionsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs()
    private let updater = Updater()
    private let llm = LLMService()
    private let usage = UsageStore()
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
        controller.attachLimits { [weak self] connection, key in
            guard let self else { return nil }
            return try await self.llm.limits(connection: connection, key: key)
        }
        controller.attachAnalytics(usage: usage)
        controller.attachChat(
            send: { [weak self] messages in
                guard let self, let connection = self.prefs.connections.active,
                      let key = Keychain.read(connection.keyAccount) else { throw LLMError.noCredentials }
                let reply = try await self.llm.send(messages, connection: connection, key: key)
                self.usage.record(provider: connection.provider, model: connection.model, usage: reply.usage)
                return reply.text
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
            controller.showHelpForDemo()
            await wait(1.5)
            demoMark("console")
            await wait(4)
            controller.showChatDemo()
            await wait(1.5)
            demoMark("chat")
            await wait(4)
            // Ввод в чат: набираем текст настоящими событиями клавиатуры и смотрим, что попало в строку.
            await controller.typeInConsoleForDemo("привет")
            await wait(1)
            fputs("DEMO input after system typing: [\(controller.consoleInputForDemo)] \(controller.debugConsoleForDemo())\n", stderr)
            controller.sendKeysForDemo("ab")
            await wait(0.5)
            fputs("DEMO input after window typing: [\(controller.consoleInputForDemo)] \(controller.debugConsoleForDemo())\n", stderr)
            demoMark("typing")
            await wait(4)
            controller.unlockConsoleForDemo()
            await wait(1.5)
            demoMark("unlock")
            await wait(4)
            // Все облики призрака: снимок на каждый (окна терминала и монитора остаются открытыми).
            for level in 1...4 {
                controller.setGhostStyleForDemo(level)
                await wait(2.5)
                demoMark("style\(level)")
                await wait(3)
            }
            controller.setGhostStyleForDemo(0)
            // Окно «/аналитика»: расход токенов по моделям.
            controller.showAnalytics()
            await wait(2.5)
            demoMark("analytics")
            await wait(3)
            controller.hideAnalyticsForDemo()
            // Режим «кофе» (E, уровень 3): чашка у призрака.
            controller.setCoffeeForDemo(true)
            await wait(2.5)
            demoMark("coffee")
            await wait(3)
            controller.setCoffeeForDemo(false)
            // Второй персонаж: золотой страж и стиль терминала с монитором в духе Вархаммера.
            controller.setCharacterForDemo(.ab)
            await wait(3)
            demoMark("ab")
            await wait(3)
            // Чашка кофе, клич «В бой!» и посадка у золотого стража.
            controller.setCoffeeForDemo(true)
            await wait(2.5)
            demoMark("ab_cup")
            await wait(2.5)
            controller.setCoffeeForDemo(false)
            await wait(1.5)
            controller.cheerForDemo()
            await wait(0.4)
            demoMark("ab_cheer")
            await wait(3)
            controller.sitForDemo(true)
            await wait(2.5)
            demoMark("ab_sit")
            await wait(3)
            controller.sitForDemo(false)
            await wait(1)
            // Пижама и колпак по расписанию.
            controller.setPajamasForDemo(true)
            await wait(2.5)
            demoMark("ab_pajama")
            await wait(3)
            controller.setPajamasForDemo(false)
            await wait(1.5)
            // Песня стража: терминал закрыт, поёт гимн.
            controller.closeConsoleForDemo()
            await wait(1)
            controller.singForDemo()
            await wait(5.5)
            demoMark("ab_sing")
            await wait(3)
            controller.stopSingForDemo()
            await wait(5)
            // Поиск реликвий Империума.
            controller.searchForDemo()
            await wait(14)
            demoMark("ab_find")
            await wait(9)
            // Игра на приставке: рядом появляется телевизор.
            controller.playForDemo()
            await wait(3)
            demoMark("ab_play")
            await wait(3)
            controller.stopPlayForDemo()
            await wait(1)
            controller.setCharacterForDemo(.f)
            await wait(1)
            controller.closeConsoleForDemo()
            await wait(1)
            // Поиск и находка (водяной чип и т. п.).
            controller.searchForDemo()
            await wait(3)
            demoMark("search")
            await wait(3)
            await wait(10)
            demoMark("find")
            await wait(3)
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
