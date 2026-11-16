import AppKit
import ApplicationServices
import SinMinionsCore

/// Открывает Spotlight, воспроизводя системное сочетание клавиш: публичного API для этого нет.
@MainActor
enum SpotlightLauncher {
    enum Outcome: Equatable {
        case sent
        /// Нет разрешения «Универсальный доступ».
        case needAccess
        /// Сочетание Spotlight выключено в настройках системы.
        case disabled
    }

    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Системный запрос разрешения с кнопкой перехода в настройки.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Удаляет запись приложения из списка «Универсальный доступ» и запрашивает разрешение заново.
    /// Нужно после обновления: подпись без сертификата у каждой сборки своя, и система продолжает
    /// показывать включённый переключатель, который относится к прежней сборке.
    @discardableResult
    static func resetAccess() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", "Accessibility", bundleID]
        tccutil.standardOutput = FileHandle.nullDevice
        tccutil.standardError = FileHandle.nullDevice
        do {
            try tccutil.run()
            tccutil.waitUntilExit()
        } catch {
            return false
        }
        requestAccess()
        return tccutil.terminationStatus == 0
    }

    static func openAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func currentHotkey() -> SpotlightHotkey.Resolution {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let table = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return SpotlightHotkey.resolve(symbolicHotKeys: table)
    }

    static func open() -> Outcome {
        guard case let .hotkey(hotkey) = currentHotkey() else { return .disabled }
        guard hasAccess else {
            requestAccess()
            return .needAccess
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: hotkey.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: hotkey.keyCode, keyDown: false)
        else { return .needAccess }
        let flags = CGEventFlags(rawValue: hotkey.flags)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .sent
    }
}
