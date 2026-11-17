import Foundation
import Observation
import SinMinionsCore

enum Frequency: String, CaseIterable, Identifiable {
    case rare, normal, often
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rare: return "Редко"
        case .normal: return "Обычно"
        case .often: return "Часто"
        }
    }

    var wanderInterval: ClosedRange<Double> {
        switch self {
        case .rare: return 180...360
        case .normal: return 60...180
        case .often: return 20...60
        }
    }

    var talkInterval: ClosedRange<Double> {
        switch self {
        case .rare: return 300...900
        case .normal: return 120...300
        case .often: return 8...14
        }
    }
}

/// Режим компаньона: что происходит по двойному щелчку.
enum CompanionMode: String, CaseIterable, Identifiable {
    /// Двойной щелчок открывает Spotlight.
    case minimal
    /// Двойной щелчок: призрак в центре экрана, под ним терминал, справа монитор.
    case medium
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Минимальный — Spotlight по двойному щелчку"
        case .medium: return "Средний — терминал и монитор по двойному щелчку"
        }
    }
}

/// Настройки пользователя; хранятся в UserDefaults.
@MainActor
@Observable
final class Prefs {
    static let scales: [Double] = [1, 1.5, 2, 3]
    /// Минуты до сна; 0 — никогда.
    static let sleepOptions: [Int] = [1, 5, 15, 0]

    var mode: CompanionMode { didSet { store(mode.rawValue, "mode") } }
    var scale: Double { didSet { store(scale, "scale") } }
    var wanderEnabled: Bool { didSet { store(wanderEnabled, "wanderEnabled") } }
    var teleportEnabled: Bool { didSet { store(teleportEnabled, "teleportEnabled") } }
    var wanderFrequency: Frequency { didSet { store(wanderFrequency.rawValue, "wanderFrequency") } }
    var talkEnabled: Bool { didSet { store(talkEnabled, "talkEnabled") } }
    var talkFrequency: Frequency { didSet { store(talkFrequency.rawValue, "talkFrequency") } }
    var sleepMinutes: Int { didSet { store(sleepMinutes, "sleepMinutes") } }
    var spotlightEnabled: Bool { didSet { store(spotlightEnabled, "spotlightEnabled") } }
    var hideInFullScreen: Bool { didSet { store(hideInFullScreen, "hideInFullScreen") } }

    /// Вызывается после любого изменения.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        mode = CompanionMode(rawValue: d.string(forKey: "mode") ?? "") ?? .minimal
        let savedScale = d.object(forKey: "scale") as? Double ?? 1.5
        scale = Self.scales.contains(savedScale) ? savedScale : 1.5
        wanderEnabled = d.object(forKey: "wanderEnabled") as? Bool ?? true
        teleportEnabled = d.object(forKey: "teleportEnabled") as? Bool ?? true
        wanderFrequency = Frequency(rawValue: d.string(forKey: "wanderFrequency") ?? "") ?? .normal
        talkEnabled = d.object(forKey: "talkEnabled") as? Bool ?? true
        talkFrequency = Frequency(rawValue: d.string(forKey: "talkFrequency") ?? "") ?? .normal
        let savedSleep = d.object(forKey: "sleepMinutes") as? Int ?? 5
        sleepMinutes = Self.sleepOptions.contains(savedSleep) ? savedSleep : 5
        spotlightEnabled = d.object(forKey: "spotlightEnabled") as? Bool ?? true
        hideInFullScreen = d.object(forKey: "hideInFullScreen") as? Bool ?? true
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange()
    }

    /// Настройки поведения; в режиме энергосбережения перелёты отключаются.
    func behaviorConfig(lowPower: Bool) -> BehaviorConfig {
        var config = BehaviorConfig()
        config.wanderEnabled = wanderEnabled && !lowPower
        config.wanderInterval = wanderFrequency.wanderInterval
        config.teleportEnabled = teleportEnabled
        config.teleportInterval = wanderFrequency.wanderInterval
        config.talkEnabled = talkEnabled
        config.talkInterval = talkFrequency.talkInterval
        config.sleepAfter = sleepMinutes > 0 ? Double(sleepMinutes) * 60 : nil
        config.spotlightEnabled = spotlightEnabled
        config.consoleEnabled = mode == .medium
        return config
    }
}
