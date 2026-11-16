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
