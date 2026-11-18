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
    var connections: LLMConnections { didSet { store(connections.json() ?? Data(), "llmConnections") } }
    var scale: Double { didSet { store(scale, "scale") } }
    var wanderEnabled: Bool { didSet { store(wanderEnabled, "wanderEnabled") } }
    var teleportEnabled: Bool { didSet { store(teleportEnabled, "teleportEnabled") } }
    var scareEnabled: Bool { didSet { store(scareEnabled, "scareEnabled") } }
    var chaseEnabled: Bool { didSet { store(chaseEnabled, "chaseEnabled") } }
    var agility: Int { didSet { store(agility, "agility") } }
    var alwaysAsleep: Bool { didSet { store(alwaysAsleep, "alwaysAsleep") } }
    var hideSeekEnabled: Bool { didSet { store(hideSeekEnabled, "hideSeekEnabled") } }
    var celebrateEnabled: Bool { didSet { store(celebrateEnabled, "celebrateEnabled") } }
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
        connections = LLMConnections.decode(d.data(forKey: "llmConnections")) ?? Self.legacyConnections(d)
        let savedScale = d.object(forKey: "scale") as? Double ?? 1.5
        scale = Self.scales.contains(savedScale) ? savedScale : 1.5
        wanderEnabled = d.object(forKey: "wanderEnabled") as? Bool ?? true
        teleportEnabled = d.object(forKey: "teleportEnabled") as? Bool ?? true
        scareEnabled = d.object(forKey: "scareEnabled") as? Bool ?? true
        chaseEnabled = d.object(forKey: "chaseEnabled") as? Bool ?? true
        hideSeekEnabled = d.object(forKey: "hideSeekEnabled") as? Bool ?? true
        agility = Agility.clamp(d.object(forKey: "agility") as? Int ?? Agility.defaultLevel)
        alwaysAsleep = d.object(forKey: "alwaysAsleep") as? Bool ?? false
        celebrateEnabled = d.object(forKey: "celebrateEnabled") as? Bool ?? true
        wanderFrequency = Frequency(rawValue: d.string(forKey: "wanderFrequency") ?? "") ?? .normal
        talkEnabled = d.object(forKey: "talkEnabled") as? Bool ?? true
        talkFrequency = Frequency(rawValue: d.string(forKey: "talkFrequency") ?? "") ?? .normal
        let savedSleep = d.object(forKey: "sleepMinutes") as? Int ?? 5
        sleepMinutes = Self.sleepOptions.contains(savedSleep) ? savedSleep : 5
        spotlightEnabled = d.object(forKey: "spotlightEnabled") as? Bool ?? true
        hideInFullScreen = d.object(forKey: "hideInFullScreen") as? Bool ?? true
    }

    /// До v0.1.8 было одно подключение GigaChat: ключ лежал в Связке ключей под прежним именем,
    /// область доступа и модель — в отдельных настройках. Переносим его в список.
    private static func legacyConnections(_ d: UserDefaults) -> LLMConnections {
        guard Keychain.exists(GigaChatAccount.key) else { return LLMConnections() }
        let scope = d.string(forKey: "llmScope") ?? ""
        let model = d.string(forKey: "llmModel") ?? ""
        let connection = LLMConnection(
            name: "GigaChat",
            scope: GigaChatAPI.scopes.contains(scope) ? scope : GigaChatAPI.scopes[0],
            model: GigaChatAPI.models.contains(model) ? model : GigaChatAPI.models[0],
            keyAccount: GigaChatAccount.key
        )
        var list = LLMConnections()
        list.add(connection)
        return list
    }

    /// Выносливость (E в S.P.E.C.I.A.L.): 0 — спит, 1 — засыпает через 5 минут, 2 — не засыпает.
    var endurance: Int {
        get { Endurance.level(alwaysAsleep: alwaysAsleep, sleepMinutes: sleepMinutes) }
        set {
            let applied = Endurance.apply(level: newValue, sleepMinutes: sleepMinutes)
            alwaysAsleep = applied.alwaysAsleep
            sleepMinutes = applied.sleepMinutes
        }
    }

    /// Ловкость (A): скорость случайных перелётов.
    var flightSpeedRange: ClosedRange<Double> { Agility.speedRange(level: agility) }

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
        config.scareEnabled = scareEnabled
        config.chaseEnabled = chaseEnabled
        config.hideSeekEnabled = hideSeekEnabled
        config.celebrateEnabled = celebrateEnabled
        config.talkEnabled = talkEnabled
        config.talkInterval = talkFrequency.talkInterval
        config.sleepAfter = sleepMinutes > 0 ? Double(sleepMinutes) * 60 : nil
        config.sleepsAlways = alwaysAsleep
        config.spotlightEnabled = spotlightEnabled
        config.consoleEnabled = mode == .medium
        return config
    }
}
