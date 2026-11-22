import Foundation

/// Сколько токенов ушло на один запрос: вход (вопрос с историей) и выход (ответ).
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int

    public init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }

    public var total: Int { input + output }

    /// Поле `usage` из ответа API. Claude: `input_tokens` / `output_tokens` (плюс токены кэша);
    /// GigaChat, DeepSeek, GPT, Grok, Gemini: `prompt_tokens` / `completion_tokens`. nil — поля нет.
    public static func parse(_ data: Data) -> TokenUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
        func int(_ key: String) -> Int? { (usage[key] as? NSNumber)?.intValue }
        if let input = int("input_tokens") ?? int("prompt_tokens") {
            let cached = (int("cache_read_input_tokens") ?? 0) + (int("cache_creation_input_tokens") ?? 0)
            let output = int("output_tokens") ?? int("completion_tokens") ?? 0
            return TokenUsage(input: input + cached, output: output)
        }
        if let output = int("output_tokens") ?? int("completion_tokens") {
            return TokenUsage(input: 0, output: output)
        }
        return nil
    }
}

/// Ответ нейросети вместе с расходом токенов.
public struct LLMReply: Sendable {
    public var text: String
    public var usage: TokenUsage?

    public init(text: String, usage: TokenUsage?) {
        self.text = text
        self.usage = usage
    }
}

/// Итог за период.
public struct UsageTotals: Codable, Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var requests = 0

    public init(input: Int = 0, output: Int = 0, requests: Int = 0) {
        self.input = input
        self.output = output
        self.requests = requests
    }

    public var total: Int { input + output }
    /// Среднее число токенов на запрос.
    public var perRequest: Int { requests == 0 ? 0 : total / requests }

    static func + (lhs: UsageTotals, rhs: UsageTotals) -> UsageTotals {
        UsageTotals(input: lhs.input + rhs.input, output: lhs.output + rhs.output, requests: lhs.requests + rhs.requests)
    }
}

/// Журнал расхода токенов по моделям и дням. Хранится на диске целиком, это несколько килобайт.
public struct UsageLedger: Codable, Equatable, Sendable {
    public struct Model: Codable, Equatable, Sendable {
        public var provider: LLMProvider
        public var model: String
        /// День «yyyy-MM-dd» → итог за день.
        public var days: [String: UsageTotals]
        public var lastUsed: Date
    }

    /// Ключ «провайдер|модель».
    public private(set) var models: [String: Model] = [:]

    /// Сколько дней хранить.
    public static let keepDays = 400

    public init() {}

    public static func key(provider: LLMProvider, model: String) -> String { provider.rawValue + "|" + model }

    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public mutating func record(provider: LLMProvider, model: String, usage: TokenUsage?, at date: Date, calendar: Calendar = .current) {
        let key = Self.key(provider: provider, model: model)
        var entry = models[key] ?? Model(provider: provider, model: model, days: [:], lastUsed: date)
        let day = Self.day(date, calendar: calendar)
        entry.days[day, default: UsageTotals()] = entry.days[day, default: UsageTotals()]
            + UsageTotals(input: usage?.input ?? 0, output: usage?.output ?? 0, requests: 1)
        entry.lastUsed = max(entry.lastUsed, date)
        if let edge = calendar.date(byAdding: .day, value: -Self.keepDays, to: date) {
            let oldest = Self.day(edge, calendar: calendar)
            entry.days = entry.days.filter { $0.key >= oldest }
        }
        models[key] = entry
    }

    /// Модели для вкладок: сначала те, что использовались недавно.
    public var orderedKeys: [String] {
        models.sorted { $0.value.lastUsed > $1.value.lastUsed }.map(\.key)
    }

    /// Итог за последние `days` дней, включая сегодняшний; nil — за всё время.
    public func totals(_ key: String, lastDays days: Int?, now: Date, calendar: Calendar = .current) -> UsageTotals {
        guard let entry = models[key] else { return UsageTotals() }
        guard let days else { return entry.days.values.reduce(UsageTotals(), +) }
        let keys = Set(series(key, days: days, now: now, calendar: calendar).map(\.day))
        return entry.days.filter { keys.contains($0.key) }.values.reduce(UsageTotals(), +)
    }

    /// По дням за последние `days` дней, от старых к новым; пустые дни — нули.
    public func series(_ key: String, days: Int, now: Date, calendar: Calendar = .current) -> [(day: String, totals: UsageTotals)] {
        let entry = models[key]
        return (0..<max(days, 0)).reversed().compactMap { back -> (String, UsageTotals)? in
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { return nil }
            let day = Self.day(date, calendar: calendar)
            return (day, entry?.days[day] ?? UsageTotals())
        }
    }

    /// «950», «1,2 ТЫС», «3,4 МЛН» — коротко для плиток; тот же формат, что у лимитов на мониторе.
    public static func short(_ value: Int) -> String { TokenFormat.short(value) }
}
