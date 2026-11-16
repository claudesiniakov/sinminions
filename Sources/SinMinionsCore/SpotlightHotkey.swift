import Foundation

/// Сочетание клавиш: виртуальный код клавиши и флаги модификаторов (в раскладке CGEventFlags).
public struct Hotkey: Equatable, Sendable {
    public let keyCode: UInt16
    public let flags: UInt64

    public init(keyCode: UInt16, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// Системное сочетание «Показать поиск Spotlight» из настроек пользователя
/// (`com.apple.symbolichotkeys`, ключ `AppleSymbolicHotKeys`, запись 64).
public enum SpotlightHotkey {
    public static let shift: UInt64 = 0x20000
    public static let control: UInt64 = 0x40000
    public static let option: UInt64 = 0x80000
    public static let command: UInt64 = 0x100000
    static let modifierMask = shift | control | option | command

    /// ⌘Пробел — значение системы, пока пользователь ничего не менял.
    public static let standard = Hotkey(keyCode: 49, flags: command)

    public enum Resolution: Equatable, Sendable {
        case hotkey(Hotkey)
        case disabled
    }

    public static func resolve(symbolicHotKeys: [String: Any]?) -> Resolution {
        guard let entry = symbolicHotKeys?["64"] as? [String: Any] else { return .hotkey(standard) }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return .disabled }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let key = (parameters[1] as? NSNumber)?.intValue,
              let modifiers = (parameters[2] as? NSNumber)?.uint64Value,
              key >= 0, key < 0xFFFF
        else { return .hotkey(standard) }
        return .hotkey(Hotkey(keyCode: UInt16(key), flags: modifiers & modifierMask))
    }
}
