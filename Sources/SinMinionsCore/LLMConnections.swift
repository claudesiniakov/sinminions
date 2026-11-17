import Foundation

public enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case gigachat
    case deepseek

    public var title: String {
        switch self {
        case .gigachat: return "GigaChat"
        case .deepseek: return "DeepSeek"
        }
    }

    /// Модели, которые предлагаются списком; остальные можно ввести вручную.
    public var models: [String] {
        switch self {
        case .gigachat: return GigaChatAPI.models
        case .deepseek: return DeepSeekAPI.models
        }
    }

    public var defaultModel: String { models[0] }

    /// У GigaChat есть область доступа (физлица, ИП и юрлица); у DeepSeek её нет.
    public var usesScope: Bool { self == .gigachat }

    public func normalizedKey(_ raw: String) -> String? {
        switch self {
        case .gigachat: return GigaChatAPI.normalizedKey(raw)
        case .deepseek: return DeepSeekAPI.normalizedKey(raw)
        }
    }
}

/// Подключение к нейросети: название, провайдер, область доступа и модель.
/// Сам ключ в настройках не хранится — только имя записи в Связке ключей.
public struct LLMConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: LLMProvider
    public var scope: String
    public var model: String
    public var keyAccount: String

    public init(
        id: UUID = UUID(), name: String, provider: LLMProvider = .gigachat,
        scope: String = GigaChatAPI.scopes[0], model: String? = nil, keyAccount: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.scope = scope
        self.model = model ?? provider.defaultModel
        self.keyAccount = keyAccount ?? "llm-" + id.uuidString.lowercased()
    }
}

/// Список подключений (не больше десяти) и выбранное из них — «интеллект» компаньона.
public struct LLMConnections: Codable, Equatable, Sendable {
    public static let limit = 10

    public private(set) var items: [LLMConnection]
    public private(set) var activeID: UUID?

    public init(items: [LLMConnection] = [], activeID: UUID? = nil) {
        self.items = Array(items.prefix(Self.limit))
        self.activeID = activeID
        normalize()
    }

    /// Выбранное подключение; если выбранного нет в списке — первое.
    public var active: LLMConnection? {
        items.first { $0.id == activeID } ?? items.first
    }

    /// Номер выбранного подключения в списке, с единицы.
    public var activePosition: Int? {
        guard let active, let index = items.firstIndex(where: { $0.id == active.id }) else { return nil }
        return index + 1
    }

    public var isFull: Bool { items.count >= Self.limit }

    /// false — список уже полон.
    @discardableResult
    public mutating func add(_ connection: LLMConnection) -> Bool {
        guard !isFull else { return false }
        items.append(connection)
        if activeID == nil { activeID = connection.id }
        return true
    }

    public mutating func update(_ connection: LLMConnection) {
        guard let index = items.firstIndex(where: { $0.id == connection.id }) else { return }
        items[index] = connection
    }

    @discardableResult
    public mutating func remove(id: UUID) -> LLMConnection? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: index)
        normalize()
        return removed
    }

    public mutating func setActive(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    /// Переключает выбранное подключение на `delta` шагов по кругу; nil — список пуст.
    @discardableResult
    public mutating func cycle(by delta: Int) -> LLMConnection? {
        guard !items.isEmpty else { return nil }
        let current = items.firstIndex { $0.id == active?.id } ?? 0
        let count = items.count
        let next = ((current + delta) % count + count) % count
        activeID = items[next].id
        return items[next]
    }

    private mutating func normalize() {
        if !items.contains(where: { $0.id == activeID }) { activeID = items.first?.id }
    }

    public func json() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// nil — данных нет или они повреждены (тогда настройки берутся по умолчанию).
    public static func decode(_ data: Data?) -> LLMConnections? {
        guard let data, let decoded = try? JSONDecoder().decode(LLMConnections.self, from: data) else { return nil }
        // Через инициализатор: лишнее обрезается, выбранное приводится в порядок.
        return LLMConnections(items: decoded.items, activeID: decoded.activeID)
    }
}
