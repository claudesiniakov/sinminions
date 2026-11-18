import Foundation

/// Повод для реплики.
public enum PhraseKind: String, Sendable, CaseIterable {
    case ambient, click, charging, lowBattery, wake, updateAvailable, needAccess, spotlightOff, teleport, scared, curious, boo
}

public struct BehaviorConfig: Equatable, Sendable {
    public var wanderEnabled = true
    /// Пауза между перелётами, секунды.
    public var wanderInterval: ClosedRange<Double> = 60...180
    public var talkEnabled = true
    /// Пауза между репликами, секунды.
    public var talkInterval: ClosedRange<Double> = 120...300
    /// Сколько реплика остаётся на экране.
    public var talkDuration: Double = 4
    /// Через сколько секунд без ввода компаньон засыпает; nil — никогда.
    public var sleepAfter: Double? = 300
    /// После перетаскивания компаньон остаётся на месте не меньше этого времени.
    public var holdAfterDrag: Double = 60
    public var spotlightEnabled = true
    /// Средний режим: двойной щелчок открывает терминал и монитор вместо Spotlight.
    public var consoleEnabled = false
    /// Телепорты через порталы; в настройках приложения включены по умолчанию.
    public var teleportEnabled = false
    /// Пауза между телепортами, секунды.
    public var teleportInterval: ClosedRange<Double> = 90...240
    /// Испуг: курсор быстро пронёсся рядом с призраком.
    public var scareEnabled = false
    /// Любопытство: вместо случайного перелёта призрак иногда подлетает к курсору.
    public var chaseEnabled = false
    /// Доля перелётов, которые превращаются в подлёт к курсору.
    public var chaseShare: Double = 0.3
    /// Выносливость 0: призрак всегда спит; потревоженный (щелчок, перетаскивание) засыпает снова.
    public var sleepsAlways = false
    /// Прятки: призрак тает на месте и выскакивает с «бу!».
    public var hideSeekEnabled = false
    public var hideInterval: ClosedRange<Double> = 240...600
    public var hideDuration: ClosedRange<Double> = 15...40
    /// Танец: призрак кружится от радости (например, когда подключили зарядку).
    public var celebrateEnabled = false

    public init() {}
}

public enum Mode: Equatable, Sendable {
    case idle, wandering, talking, reacting, sleeping, dragged
    /// Средний режим: призрак в центре экрана, под ним терминал, справа монитор.
    case console
    /// Телепорт: призрак уходит в один портал и выходит из другого.
    case teleporting
    /// Прятки: призрак почти невидим, пока курсор не подойдёт или не кончится время.
    case hiding
}

/// Что должен сделать интерфейс в ответ на переход автомата.
public enum Effect: Equatable, Sendable {
    case startWander, stopWander
    case say(PhraseKind), hideBubble
    case fallAsleep, wakeUp
    case hop
    case openSpotlight
    case openConsole, closeConsole
    case startTeleport, stopTeleport
    case shake, startChase
    case fadeOut, fadeIn, spin
}

public enum Event: Equatable, Sendable {
    case dragBegan, dragEnded
    case click, doubleClick
    /// Перелёт закончен.
    case arrived
    /// Показать реплику по системному поводу.
    case announce(PhraseKind)
    /// Усыпить на заданное число секунд: ввод с клавиатуры и мыши не будит.
    case nap(Double)
    case wake
    /// Компаньона скрыли: всё останавливается, сон сохраняется.
    case suspended
    case resumed
    /// Терминал закрыт (Esc, щелчок мимо, выполнена команда).
    case closeConsole
    /// Начать телепорт сейчас, не дожидаясь таймера.
    case teleportNow
    /// Телепорт закончен.
    case teleportDone
    /// Курсор быстро пронёсся рядом с призраком.
    case scare
    /// Курсор подошёл к спрятавшемуся призраку.
    case reveal
    /// Повод для радости; фраза — из этого набора.
    case celebrate(PhraseKind)
}

/// Конечный автомат поведения компаньона. Не знает об интерфейсе: время и случайность
/// приходят снаружи, наружу уходят эффекты.
public struct BehaviorEngine {
    public private(set) var mode: Mode = .idle
    public private(set) var config: BehaviorConfig
    public private(set) var nextWanderAt: Double
    public private(set) var nextTalkAt: Double
    public private(set) var nextTeleportAt: Double
    public private(set) var nextHideAt: Double
    public private(set) var napUntil: Double?
    private var modeEndsAt: Double = 0
    private var scareCooldownUntil: Double = 0
    /// После испуга призрак не пугается заново столько секунд.
    public static let scareCooldown: Double = 20
    private let random: (ClosedRange<Double>) -> Double

    /// Ввод моложе этого числа секунд будит спящего компаньона.
    public static let wakeThreshold: Double = 3
    /// После действий пользователя компаньон не начинает ничего сам хотя бы столько секунд.
    public static let quietAfterInteraction: Double = 5

    public var isNapping: Bool { napUntil != nil }

    public init(
        config: BehaviorConfig = BehaviorConfig(),
        now: Double,
        random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) {
        self.config = config
        self.random = random
        nextWanderAt = now + random(config.wanderInterval)
        nextTalkAt = now + random(config.talkInterval)
        nextTeleportAt = now + random(config.teleportInterval)
        nextHideAt = now + random(config.hideInterval)
    }

    /// Новые настройки: таймеры перелёта и реплик запускаются заново.
    public mutating func reconfigure(_ newConfig: BehaviorConfig, now: Double) {
        guard newConfig != config else { return }
        config = newConfig
        nextWanderAt = now + random(config.wanderInterval)
        nextTalkAt = now + random(config.talkInterval)
        nextTeleportAt = now + random(config.teleportInterval)
        nextHideAt = now + random(config.hideInterval)
    }

    /// Раз в секунду. `idleSeconds` — время с последнего ввода с клавиатуры или мыши.
    public mutating func tick(now: Double, idleSeconds: Double) -> [Effect] {
        switch mode {
        case .dragged, .wandering, .console, .teleporting:
            return []
        case .hiding:
            guard now >= modeEndsAt else { return [] }
            nextHideAt = now + random(config.hideInterval)
            postpone(now: now)
            return [.fadeIn] + startTalk(.boo, now: now)
        case .sleeping:
            if let nap = napUntil {
                return now >= nap ? wake(now: now) : []
            }
            if config.sleepsAlways { return [] }
            return idleSeconds < Self.wakeThreshold ? wake(now: now) : []
        case .talking, .reacting:
            guard now >= modeEndsAt else { return [] }
            mode = .idle
            return [.hideBubble]
        case .idle:
            if config.sleepsAlways {
                mode = .sleeping
                return [.fallAsleep]
            }
            if let limit = config.sleepAfter, idleSeconds >= limit {
                mode = .sleeping
                return [.fallAsleep]
            }
            if config.talkEnabled, now >= nextTalkAt {
                return startTalk(.ambient, now: now)
            }
            if config.teleportEnabled, now >= nextTeleportAt {
                mode = .teleporting
                return [.startTeleport]
            }
            if config.hideSeekEnabled, now >= nextHideAt {
                mode = .hiding
                modeEndsAt = now + random(config.hideDuration)
                nextHideAt = modeEndsAt + random(config.hideInterval)
                return [.fadeOut]
            }
            if config.wanderEnabled, now >= nextWanderAt {
                mode = .wandering
                // Иногда вместо случайной точки призрак подлетает к курсору.
                if config.chaseEnabled, random(0...1) < config.chaseShare { return [.startChase] }
                return [.startWander]
            }
            return []
        }
    }

    public mutating func handle(_ event: Event, now: Double) -> [Effect] {
        switch event {
        case .dragBegan:
            let effects = interrupt()
            mode = .dragged
            return effects

        case .dragEnded:
            guard mode == .dragged else { return [] }
            mode = .idle
            nextWanderAt = max(nextWanderAt, now + config.holdAfterDrag)
            nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
            return []

        case .click:
            guard mode != .dragged, mode != .console else { return [] }
            let effects = interrupt()
            mode = .reacting
            modeEndsAt = now + config.talkDuration
            postpone(now: now + config.talkDuration)
            return effects + [.hop, .say(.click)]

        case .doubleClick:
            guard mode != .dragged else { return [] }
            if mode == .console { return closeConsole(now: now) }
            let effects = interrupt()
            postpone(now: now)
            if config.consoleEnabled {
                mode = .console
                return effects + [.openConsole]
            }
            return effects + (config.spotlightEnabled ? [.openSpotlight] : [])

        case .arrived:
            guard mode == .wandering else { return [] }
            mode = .idle
            nextWanderAt = now + random(config.wanderInterval)
            nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
            return []

        case let .announce(kind):
            guard mode != .dragged, mode != .console else { return [] }
            let effects = interrupt()
            return effects + startTalk(kind, now: now)

        case let .nap(seconds):
            guard mode != .dragged else { return [] }
            if mode == .sleeping {
                napUntil = now + seconds
                return []
            }
            let effects = interrupt()
            mode = .sleeping
            napUntil = now + seconds
            return effects + [.fallAsleep]

        case .wake:
            return mode == .sleeping ? wake(now: now) : []

        case .suspended:
            switch mode {
            case .sleeping: return []
            case .wandering: mode = .idle; return [.stopWander]
            case .talking, .reacting: mode = .idle; return [.hideBubble]
            case .console: mode = .idle; return [.closeConsole]
            case .teleporting: mode = .idle; return [.stopTeleport]
            case .hiding: mode = .idle; return [.fadeIn]
            case .dragged, .idle: mode = .idle; return []
            }

        case .closeConsole:
            return mode == .console ? closeConsole(now: now) : []

        case .reveal:
            guard mode == .hiding else { return [] }
            mode = .reacting
            modeEndsAt = now + config.talkDuration
            nextHideAt = now + random(config.hideInterval)
            postpone(now: now + config.talkDuration)
            return [.fadeIn, .shake, .say(.boo)]

        case let .celebrate(kind):
            guard config.celebrateEnabled, mode == .idle || mode == .wandering || mode == .talking else { return [] }
            let effects = interrupt()
            mode = .reacting
            modeEndsAt = now + config.talkDuration
            postpone(now: now + config.talkDuration)
            return effects + [.spin, .say(kind)]

        case .scare:
            guard config.scareEnabled, now >= scareCooldownUntil,
                  mode == .idle || mode == .wandering else { return [] }
            scareCooldownUntil = now + Self.scareCooldown
            let effects = interrupt()
            mode = .reacting
            modeEndsAt = now + config.talkDuration
            postpone(now: now + config.talkDuration)
            return effects + [.shake, .say(.scared)]

        case .teleportNow:
            guard mode == .idle else { return [] }
            mode = .teleporting
            return [.startTeleport]

        case .teleportDone:
            guard mode == .teleporting else { return [] }
            mode = .idle
            nextTeleportAt = now + random(config.teleportInterval)
            postpone(now: now)
            return []

        case .resumed:
            postpone(now: now)
            return []
        }
    }

    // MARK: - Внутреннее

    /// Прерывает текущее занятие и возвращает в «Парит».
    private mutating func interrupt() -> [Effect] {
        defer { mode = .idle }
        switch mode {
        case .wandering: return [.stopWander]
        case .talking, .reacting: return [.hideBubble]
        case .sleeping:
            napUntil = nil
            return [.wakeUp]
        case .console: return [.closeConsole]
        case .teleporting: return [.stopTeleport]
        case .hiding: return [.fadeIn]
        case .idle, .dragged: return []
        }
    }

    private mutating func closeConsole(now: Double) -> [Effect] {
        mode = .idle
        nextWanderAt = max(nextWanderAt, now + config.holdAfterDrag)
        nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
        return [.closeConsole]
    }

    private mutating func wake(now: Double) -> [Effect] {
        mode = .idle
        napUntil = nil
        postpone(now: now)
        return [.wakeUp]
    }

    private mutating func startTalk(_ kind: PhraseKind, now: Double) -> [Effect] {
        mode = .talking
        modeEndsAt = now + config.talkDuration
        nextTalkAt = now + config.talkDuration + random(config.talkInterval)
        nextWanderAt = max(nextWanderAt, now + config.talkDuration + Self.quietAfterInteraction)
        return [.say(kind)]
    }

    private mutating func postpone(now: Double) {
        nextWanderAt = max(nextWanderAt, now + Self.quietAfterInteraction)
        nextTeleportAt = max(nextTeleportAt, now + Self.quietAfterInteraction)
        nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
    }
}
