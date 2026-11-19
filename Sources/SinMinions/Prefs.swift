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

    var mode: CompanionMode { didSet { storeGlobal(mode.rawValue, "mode") } }
    var connections: LLMConnections { didSet { storeGlobal(connections.json() ?? Data(), "llmConnections") } }
    /// Активный персонаж: на экране показан он, а настройки поведения ниже относятся к нему.
    var character: CompanionCharacter {
        didSet {
            guard character != oldValue else { return }
            storeGlobal(character.rawValue, "character")
            applyCharacterSettings()
        }
    }
    var scale: Double { didSet { store(scale, "scale") } }
    var wanderEnabled: Bool { didSet { store(wanderEnabled, "wanderEnabled") } }
    var teleportEnabled: Bool { didSet { store(teleportEnabled, "teleportEnabled") } }
    var scareEnabled: Bool { didSet { store(scareEnabled, "scareEnabled") } }
    var chaseEnabled: Bool { didSet { store(chaseEnabled, "chaseEnabled") } }
    var agility: Int { didSet { store(agility, "agility") } }
    /// Облик призрака (P в S.P.E.C.I.A.L.): номер стиля отрисовки.
    var ghostStyleLevel: Int { didSet { store(ghostStyleLevel, "ghostStyle") } }
    var ghostStyle: GhostStyle { GhostStyle.clamp(ghostStyleLevel) }
    /// Режим «кофе» (уровень 3 буквы E или команда /coffee): ноутбук не засыпает. После перезапуска выключен, чтобы не разряжать батарею втихую.
    var coffee = false { didSet { if !applying { onChange() } } }
    var alwaysAsleep: Bool { didSet { store(alwaysAsleep, "alwaysAsleep") } }
    var hideSeekEnabled: Bool { didSet { store(hideSeekEnabled, "hideSeekEnabled") } }
    var searchEnabled: Bool { didSet { store(searchEnabled, "searchEnabled") } }
    /// Игра на приставке рядом с телевизором: есть только у золотого стража.
    var playEnabled: Bool { didSet { store(playEnabled, "playEnabled") } }
    /// Песня: страж иногда поёт гимн (только у него).
    var singEnabled: Bool { didSet { store(singEnabled, "singEnabled") } }
    /// Смена одежды стража по времени: ночью пижама и колпак, днём доспех.
    var pajamaAuto: Bool { didSet { store(pajamaAuto, "pajamaAuto") } }
    var pajamaFrom: Int { didSet { store(pajamaFrom, "pajamaFrom") } }
    var pajamaTo: Int { didSet { store(pajamaTo, "pajamaTo") } }
    var shooEnabled: Bool { didSet { store(shooEnabled, "shooEnabled") } }
    var celebrateEnabled: Bool { didSet { store(celebrateEnabled, "celebrateEnabled") } }
    var wanderFrequency: Frequency { didSet { store(wanderFrequency.rawValue, "wanderFrequency") } }
    var talkEnabled: Bool { didSet { store(talkEnabled, "talkEnabled") } }
    var talkFrequency: Frequency { didSet { store(talkFrequency.rawValue, "talkFrequency") } }
    var sleepMinutes: Int { didSet { store(sleepMinutes, "sleepMinutes") } }
    var hideInFullScreen: Bool { didSet { storeGlobal(hideInFullScreen, "hideInFullScreen") } }

    /// Вызывается после любого изменения.
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var applying = false

    init() {
        let d = UserDefaults.standard
        mode = CompanionMode(rawValue: d.string(forKey: "mode") ?? "") ?? .medium
        connections = LLMConnections.decode(d.data(forKey: "llmConnections")) ?? Self.legacyConnections(d)
        let active = CompanionCharacter(rawValue: d.string(forKey: "character") ?? "") ?? .f
        character = active
        let c = CharacterSettings.read(d, active)
        scale = c.scale
        wanderEnabled = c.wander
        teleportEnabled = c.teleport
        scareEnabled = c.scare
        chaseEnabled = c.chase
        hideSeekEnabled = c.hideSeek
        shooEnabled = c.shoo
        searchEnabled = c.search
        playEnabled = c.play
        singEnabled = c.sing
        pajamaAuto = c.pajamaAuto
        pajamaFrom = c.pajamaFrom
        pajamaTo = c.pajamaTo
        ghostStyleLevel = c.ghostStyle
        agility = c.agility
        alwaysAsleep = c.alwaysAsleep
        celebrateEnabled = c.celebrate
        wanderFrequency = c.wanderFrequency
        talkEnabled = c.talkEnabled
        talkFrequency = c.talkFrequency
        sleepMinutes = c.sleepMinutes
        hideInFullScreen = d.object(forKey: "hideInFullScreen") as? Bool ?? true
    }

    /// Загружает настройки активного персонажа в свойства (при переключении вкладки F и ab).
    private func applyCharacterSettings() {
        let c = CharacterSettings.read(defaults, character)
        applying = true
        scale = c.scale
        wanderEnabled = c.wander
        teleportEnabled = c.teleport
        scareEnabled = c.scare
        chaseEnabled = c.chase
        hideSeekEnabled = c.hideSeek
        shooEnabled = c.shoo
        searchEnabled = c.search
        playEnabled = c.play
        singEnabled = c.sing
        pajamaAuto = c.pajamaAuto
        pajamaFrom = c.pajamaFrom
        pajamaTo = c.pajamaTo
        ghostStyleLevel = c.ghostStyle
        agility = c.agility
        alwaysAsleep = c.alwaysAsleep
        celebrateEnabled = c.celebrate
        wanderFrequency = c.wanderFrequency
        talkEnabled = c.talkEnabled
        talkFrequency = c.talkFrequency
        sleepMinutes = c.sleepMinutes
        coffee = false
        applying = false
        onChange()
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

    /// Одежда персонажа сейчас: у золотого стража пижама во сне и по расписанию, иначе доспех.
    var outfit: Outfit {
        guard character == .ab else { return .armor }
        let hour = Calendar.current.component(.hour, from: Date())
        return Wardrobe.outfit(alwaysAsleep: alwaysAsleep, auto: pajamaAuto, from: pajamaFrom, to: pajamaTo, hour: hour)
    }

    /// Выносливость (E в S.P.E.C.I.A.L.): 0 — спит, 1 — засыпает через 5 минут, 2 — не засыпает.
    var endurance: Int {
        get { Endurance.level(alwaysAsleep: alwaysAsleep, sleepMinutes: sleepMinutes, coffee: coffee) }
        set {
            let applied = Endurance.apply(level: newValue, sleepMinutes: sleepMinutes)
            alwaysAsleep = applied.alwaysAsleep
            sleepMinutes = applied.sleepMinutes
            coffee = Endurance.clamp(newValue) == Endurance.coffeeLevel
        }
    }

    /// Харизма (C): 0 — молчит, 1 — редко, 2 — обычно, 3 — часто.
    var charisma: Int {
        get {
            guard talkEnabled else { return 0 }
            switch talkFrequency {
            case .rare: return 1
            case .normal: return 2
            case .often: return 3
            }
        }
        set {
            let level = Charisma.clamp(newValue)
            talkEnabled = level > 0
            switch level {
            case 1: talkFrequency = .rare
            case 2: talkFrequency = .normal
            case 3: talkFrequency = .often
            default: break
            }
        }
    }

    /// Ловкость (A): скорость случайных перелётов.
    var flightSpeedRange: ClosedRange<Double> { Agility.speedRange(level: agility) }

    /// Настройка активного персонажа: ключ получает его префикс.
    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: character.keyPrefix + key)
        if !applying { onChange() }
    }

    /// Общая настройка, не зависящая от персонажа.
    private func storeGlobal(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        if !applying { onChange() }
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
        config.shooEnabled = shooEnabled
        config.searchEnabled = searchEnabled
        config.playEnabled = playEnabled && character == .ab
        config.singEnabled = singEnabled && character == .ab
        config.singDuration = Anthem.duration
        config.celebrateEnabled = celebrateEnabled
        config.talkEnabled = talkEnabled
        config.talkInterval = talkFrequency.talkInterval
        config.sleepAfter = sleepMinutes > 0 && !coffee ? Double(sleepMinutes) * 60 : nil
        config.sleepsAlways = alwaysAsleep
        config.consoleEnabled = mode == .medium
        return config
    }
}

/// Настройки поведения одного персонажа, прочитанные из UserDefaults. Значения по умолчанию у персонажей разные:
/// золотой страж тяжёлый и медленный, не прячется и не пугается.
struct CharacterSettings {
    var scale: Double
    var wander: Bool
    var teleport: Bool
    var scare: Bool
    var chase: Bool
    var hideSeek: Bool
    var shoo: Bool
    var search: Bool
    var play: Bool
    var sing: Bool
    var pajamaAuto: Bool
    var pajamaFrom: Int
    var pajamaTo: Int
    var ghostStyle: Int
    var agility: Int
    var alwaysAsleep: Bool
    var celebrate: Bool
    var wanderFrequency: Frequency
    var talkEnabled: Bool
    var talkFrequency: Frequency
    var sleepMinutes: Int

    static func read(_ d: UserDefaults, _ character: CompanionCharacter) -> CharacterSettings {
        let p = character.keyPrefix
        let ab = character == .ab
        func bool(_ key: String, _ first: Bool, _ second: Bool) -> Bool {
            d.object(forKey: p + key) as? Bool ?? (ab ? second : first)
        }
        let savedScale = d.object(forKey: p + "scale") as? Double ?? 1.5
        let savedSleep = d.object(forKey: p + "sleepMinutes") as? Int ?? 5
        return CharacterSettings(
            scale: Prefs.scales.contains(savedScale) ? savedScale : 1.5,
            wander: bool("wanderEnabled", true, true),
            teleport: bool("teleportEnabled", true, true),
            scare: bool("scareEnabled", true, false),
            chase: bool("chaseEnabled", true, false),
            hideSeek: bool("hideSeekEnabled", true, false),
            shoo: bool("shooEnabled", true, true),
            search: bool("searchEnabled", true, true),
            play: bool("playEnabled", false, true),
            sing: bool("singEnabled", false, true),
            pajamaAuto: bool("pajamaAuto", false, false),
            pajamaFrom: min(max(d.object(forKey: p + "pajamaFrom") as? Int ?? 23, 0), 23),
            pajamaTo: min(max(d.object(forKey: p + "pajamaTo") as? Int ?? 7, 0), 23),
            ghostStyle: GhostStyle.clamp(d.object(forKey: p + "ghostStyle") as? Int ?? 0).rawValue,
            agility: Agility.clamp(d.object(forKey: p + "agility") as? Int ?? (ab ? 0 : Agility.defaultLevel)),
            alwaysAsleep: bool("alwaysAsleep", false, false),
            celebrate: bool("celebrateEnabled", true, true),
            wanderFrequency: Frequency(rawValue: d.string(forKey: p + "wanderFrequency") ?? "") ?? .normal,
            talkEnabled: bool("talkEnabled", true, true),
            talkFrequency: Frequency(rawValue: d.string(forKey: p + "talkFrequency") ?? "") ?? .normal,
            sleepMinutes: Prefs.sleepOptions.contains(savedSleep) ? savedSleep : 5
        )
    }
}
