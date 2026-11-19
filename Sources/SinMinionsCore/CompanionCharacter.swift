import Foundation

/// Персонаж-компаньон. У каждого свои настройки поведения, облик и стиль терминала с монитором.
public enum CompanionCharacter: String, CaseIterable, Sendable, Identifiable {
    /// Первый персонаж: призрак Moth, стиль терминала из Fallout.
    case f
    /// Второй персонаж: золотой страж, стиль терминала в духе Вархаммера.
    case ab

    public var id: String { rawValue }

    /// Название вкладки в настройках.
    public var tabTitle: String {
        switch self {
        case .f: return "F"
        case .ab: return "ab"
        }
    }

    /// Префикс ключей настроек в UserDefaults: у первого персонажа пустой, чтобы сохранились прежние настройки.
    public var keyPrefix: String {
        switch self {
        case .f: return ""
        case .ab: return "ab."
        }
    }

    /// Обороты в заголовках терминала и монитора.
    public var terminalName: String {
        switch self {
        case .f: return "MOTH-OS"
        case .ab: return "КОГИТАТОР"
        }
    }

    public var monitorName: String {
        switch self {
        case .f: return "СИСТЕМА"
        case .ab: return "АУСПЕКС"
        }
    }
}
