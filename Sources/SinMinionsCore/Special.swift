import Foundation

/// Ловкость (A в S.P.E.C.I.A.L.): скорость полёта призрака.
public enum Agility {
    public static let levels = 4
    /// Обычная скорость — та, что была до появления этой настройки.
    public static let defaultLevel = 1

    public static func clamp(_ level: Int) -> Int { min(max(level, 0), levels - 1) }

    /// Скорость случайного перелёта, pt/с.
    public static func speedRange(level: Int) -> ClosedRange<Double> {
        switch clamp(level) {
        case 0: return 20...35
        case 1: return 40...80
        case 2: return 100...160
        default: return 240...360
        }
    }

    public static func title(level: Int) -> String {
        ["МЕДЛЕННО", "ОБЫЧНО", "БЫСТРО", "МОЛНИЕНОСНО"][clamp(level)]
    }
}

/// Выносливость (E): 0 — призрак спит, 1 — засыпает при бездействии, 2 — не засыпает.
public enum Endurance {
    public static let levels = 3
    /// На уровне 1 призрак засыпает через столько минут.
    public static let defaultMinutes = 5

    public static func clamp(_ level: Int) -> Int { min(max(level, 0), levels - 1) }

    public static func level(alwaysAsleep: Bool, sleepMinutes: Int) -> Int {
        alwaysAsleep ? 0 : (sleepMinutes <= 0 ? 2 : 1)
    }

    /// Какие настройки соответствуют уровню. На уровне 0 время засыпания не меняется.
    public static func apply(level: Int, sleepMinutes: Int) -> (alwaysAsleep: Bool, sleepMinutes: Int) {
        switch clamp(level) {
        case 0: return (true, sleepMinutes)
        case 1: return (false, defaultMinutes)
        default: return (false, 0)
        }
    }

    public static func title(level: Int, sleepMinutes: Int) -> String {
        switch clamp(level) {
        case 0: return "СПИТ"
        case 1: return "ЗАСЫПАЕТ ЧЕРЕЗ \(sleepMinutes > 0 ? sleepMinutes : defaultMinutes) МИН"
        default: return "НЕ ЗАСЫПАЕТ"
        }
    }
}

/// Харизма (C): частота реплик. 0 — молчит, дальше от редких к частым.
public enum Charisma {
    public static let levels = 4
    public static let defaultLevel = 2

    public static func clamp(_ level: Int) -> Int { min(max(level, 0), levels - 1) }

    public static func title(level: Int) -> String {
        ["МОЛЧИТ", "РЕДКО (5–15 МИН)", "ОБЫЧНО (2–5 МИН)", "ЧАСТО (8–14 С)"][clamp(level)]
    }
}

/// Облик призрака (P в S.P.E.C.I.A.L.): пять стилей отрисовки одного и того же силуэта.
public enum GhostStyle: Int, CaseIterable, Sendable {
    case classic, detailed, warden, terminal, radiation

    public static let levels = allCases.count
    public static let defaultStyle = GhostStyle.classic

    public static func clamp(_ level: Int) -> GhostStyle {
        GhostStyle(rawValue: min(max(level, 0), levels - 1)) ?? defaultStyle
    }

    public var title: String {
        switch self {
        case .classic: return "КЛАССИЧЕСКИЙ"
        case .detailed: return "ДЕТАЛЬНЫЙ"
        case .warden: return "СМОТРИТЕЛЬ"
        case .terminal: return "ТЕРМИНАЛ"
        case .radiation: return "РАДИАЦИЯ"
        }
    }

    /// Во сколько раз свечение сильнее или слабее, чем у классического призрака.
    public var glowScale: Double {
        switch self {
        case .classic, .warden: return 1
        case .detailed: return 1.1
        case .terminal: return 0.8
        case .radiation: return 1.7
        }
    }
}
