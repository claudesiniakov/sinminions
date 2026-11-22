import AppKit
import SinMinionsCore

/// Хуки для демонстрации в CI (SINMINIONS_DEMO=1): сцены и снимки экрана. В обычной работе не вызываются.
extension CompanionController {
    /// Для снимка в CI: открывает терминал и монитор независимо от выбранного режима.
    func openConsoleForDemo() {
        var config = prefs.behaviorConfig(lowPower: lowPower)
        config.consoleEnabled = true
        engine.reconfigure(config, now: now)
        apply(engine.handle(.doubleClick, now: now))
    }

    func showChatDemo() {
        console.model.chat.loadDemo()
        console.model.screen = .chat
        console.activateForTyping()
    }

    func hideAnalyticsForDemo() { analytics.hide() }

    /// Обычный терминал (zsh) с парой настоящих команд.
    func shellForDemo(_ on: Bool) { console.shellForDemo(on) }

    func closeConsoleForDemo() {
        apply(engine.handle(.closeConsole, now: now))
    }

    func teleportForDemo() {
        apply(engine.handle(.teleportNow, now: now))
    }

    /// Для CI: набирает текст настоящими событиями клавиатуры, как пользователь (в CI «Универсальный доступ» выдан).
    /// Проверяет, что ввод в строку чата доходит до окна, которое не забирает фокус у других приложений.
    func typeInConsoleForDemo(_ text: String) async {
        for scalar in text.unicodeScalars {
            var utf16 = Array(String(scalar).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                event.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    func debugConsoleForDemo() -> String { console.debugState() }

    func sendKeysForDemo(_ text: String) { console.sendKeysForDemo(text) }

    /// Что сейчас в строке ввода чата (для проверки в CI).
    var consoleInputForDemo: String { console.model.chat.input }

    /// Для снимка в CI: в меню выполнена команда /help.
    func showHelpForDemo() {
        console.model.shellLog.append("> /help")
        console.model.runSlash("/help", output: .shell)
    }

    /// Для демо: режим «кофе» (уровень 3 выносливости) или обычный.
    func setCoffeeForDemo(_ on: Bool) {
        prefs.endurance = on ? Endurance.coffeeLevel : 2
        applyPrefs()
    }

    /// Для демо: переключает персонажа (как вкладка «F» и «ab» в настройках).
    func setCharacterForDemo(_ character: CompanionCharacter) {
        prefs.character = character
    }

    /// Для снимков в CI: смена облика призрака.
    func setGhostStyleForDemo(_ level: Int) {
        prefs.ghostStyleLevel = GhostStyle.clamp(level).rawValue
        applyPrefs()
    }

    /// Для снимка в CI: окна разблокированы.
    func unlockConsoleForDemo() {
        console.setUnlocked(true)
    }

    func singForDemo() { apply(engine.handle(.singNow, now: now)) }

    func stopSingForDemo() { apply(engine.handle(.click, now: now)) }

    func playForDemo() { apply(engine.handle(.playNow, now: now)) }

    func stopPlayForDemo() { apply(engine.handle(.click, now: now)) }

    /// Для демо: пижама и колпак у стража (расписание «весь день»), затем обратно.
    func setPajamasForDemo(_ on: Bool) {
        prefs.pajamaFrom = 0
        prefs.pajamaTo = 0
        prefs.pajamaAuto = on
    }

    func cheerForDemo() { view.cheer() }

    func sitForDemo(_ on: Bool) { view.setSleeping(on) }

    func searchForDemo() {
        apply(engine.handle(.searchNow, now: now))
    }
}
