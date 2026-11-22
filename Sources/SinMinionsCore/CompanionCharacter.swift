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
        case .ab: return tr("КОГИТАТОР")
        }
    }

    public var monitorName: String {
        switch self {
        case .f: return tr("СИСТЕМА")
        case .ab: return tr("АУСПЕКС")
        }
    }
}

/// Одежда золотого стража: доспех днём, полосатая пижама с колпаком ночью.
public enum Outfit: String, Sendable {
    case armor, pajamas
}

public enum Wardrobe {
    /// Входит ли час в промежуток «с — до». Промежуток может переходить через полночь (с 23 до 7);
    /// если «с» равно «до», пижама весь день.
    public static func isWithin(hour: Int, from: Int, to: Int) -> Bool {
        if from == to { return true }
        return from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }

    /// Во что одет страж: пижама, если он «спит» (уровень 0 выносливости) или включена смена по времени и сейчас ночь.
    public static func outfit(alwaysAsleep: Bool, auto: Bool, from: Int, to: Int, hour: Int) -> Outfit {
        if alwaysAsleep { return .pajamas }
        if auto, isWithin(hour: hour, from: from, to: to) { return .pajamas }
        return .armor
    }
}
