import Foundation

/// Повод для реплики.
public enum PhraseKind: String, Sendable, CaseIterable {
    case ambient, click, charging, lowBattery, wake, updateAvailable, needAccess, spotlightOff
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

    public init() {}
}

public enum Mode: Equatable, Sendable {
    case idle, wandering, talking, reacting, sleeping, dragged
}

/// Что должен сделать интерфейс в ответ на переход автомата.
public enum Effect: Equatable, Sendable {
    case startWander, stopWander
    case say(PhraseKind), hideBubble
    case fallAsleep, wakeUp
    case hop
    case openSpotlight
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
}

/// Конечный автомат поведения компаньона. Не знает об интерфейсе: время и случайность
/// приходят снаружи, наружу уходят эффекты.
public struct BehaviorEngine {
    public private(set) var mode: Mode = .idle
    public private(set) var config: BehaviorConfig
    public private(set) var nextWanderAt: Double
    public private(set) var nextTalkAt: Double
    public private(set) var napUntil: Double?
    private var modeEndsAt: Double = 0
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
    }

    /// Новые настройки: таймеры перелёта и реплик запускаются заново.
    public mutating func reconfigure(_ newConfig: BehaviorConfig, now: Double) {
        guard newConfig != config else { return }
        config = newConfig
        nextWanderAt = now + random(config.wanderInterval)
        nextTalkAt = now + random(config.talkInterval)
    }

    /// Раз в секунду. `idleSeconds` — время с последнего ввода с клавиатуры или мыши.
    public mutating func tick(now: Double, idleSeconds: Double) -> [Effect] {
        switch mode {
        case .dragged, .wandering:
            return []
        case .sleeping:
            if let nap = napUntil {
                return now >= nap ? wake(now: now) : []
            }
            return idleSeconds < Self.wakeThreshold ? wake(now: now) : []
        case .talking, .reacting:
            guard now >= modeEndsAt else { return [] }
            mode = .idle
            return [.hideBubble]
        case .idle:
            if let limit = config.sleepAfter, idleSeconds >= limit {
                mode = .sleeping
                return [.fallAsleep]
            }
            if config.talkEnabled, now >= nextTalkAt {
                return startTalk(.ambient, now: now)
            }
            if config.wanderEnabled, now >= nextWanderAt {
                mode = .wandering
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
            guard mode != .dragged else { return [] }
            let effects = interrupt()
            mode = .reacting
            modeEndsAt = now + config.talkDuration
            postpone(now: now + config.talkDuration)
            return effects + [.hop, .say(.click)]

        case .doubleClick:
            guard mode != .dragged else { return [] }
            let effects = interrupt()
            postpone(now: now)
            return effects + (config.spotlightEnabled ? [.openSpotlight] : [])

        case .arrived:
            guard mode == .wandering else { return [] }
            mode = .idle
            nextWanderAt = now + random(config.wanderInterval)
            nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
            return []

        case let .announce(kind):
            guard mode != .dragged else { return [] }
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
            case .dragged, .idle: mode = .idle; return []
            }

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
        case .idle, .dragged: return []
        }
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
        nextTalkAt = max(nextTalkAt, now + Self.quietAfterInteraction)
    }
}
