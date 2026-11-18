import Foundation

public enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case gigachat
    case deepseek
    case claude
    case gpt
    case grok
    case gemini

    public var title: String {
        switch self {
        case .gigachat: return "GigaChat"
        case .deepseek: return "DeepSeek"
        case .claude: return "Claude"
        case .gpt: return "GPT"
        case .grok: return "Grok"
        case .gemini: return "Gemini"
        }
    }

    /// Модели, которые предлагаются списком; остальные можно ввести вручную.
    public var models: [String] {
        switch self {
        case .gigachat: return GigaChatAPI.models
        case .deepseek: return DeepSeekAPI.models
        case .claude: return AnthropicAPI.models
        case .gpt: return OpenAICompatibleAPI.gptModels
        case .grok: return OpenAICompatibleAPI.grokModels
        case .gemini: return OpenAICompatibleAPI.geminiModels
        }
    }

    public var defaultModel: String { models[0] }

    /// Есть ли у провайдера способ узнать остаток по обычному ключу (у остальных такого нет).
    public var supportsLimits: Bool { self == .gigachat || self == .deepseek }

    /// У GigaChat есть область доступа (физлица, ИП и юрлица); у DeepSeek её нет.
    public var usesScope: Bool { self == .gigachat }

    public func normalizedKey(_ raw: String) -> String? {
        switch self {
        case .gigachat: return GigaChatAPI.normalizedKey(raw)
        case .deepseek, .claude, .gpt, .grok, .gemini: return DeepSeekAPI.normalizedKey(raw)
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
    /// Запрашивать остаток и показывать его в блоке «Лимиты» на мониторе.
    public var showLimits: Bool
    /// Участвует ли подключение в чате: выбирается «интеллектом» и переключается кнопками «+» и «−».
    public var useInChat: Bool

    public init(
        id: UUID = UUID(), name: String, provider: LLMProvider = .gigachat,
        scope: String = GigaChatAPI.scopes[0], model: String? = nil, keyAccount: String? = nil,
        showLimits: Bool = true, useInChat: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.scope = scope
        self.model = model ?? provider.defaultModel
        self.keyAccount = keyAccount ?? "llm-" + id.uuidString.lowercased()
        self.showLimits = showLimits
        self.useInChat = useInChat
    }

    /// Старые сохранённые подключения без новых полей читаются с включёнными переключателями.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        provider = try c.decode(LLMProvider.self, forKey: .provider)
        scope = try c.decode(String.self, forKey: .scope)
        model = try c.decode(String.self, forKey: .model)
        keyAccount = try c.decode(String.self, forKey: .keyAccount)
        showLimits = try c.decodeIfPresent(Bool.self, forKey: .showLimits) ?? true
        useInChat = try c.decodeIfPresent(Bool.self, forKey: .useInChat) ?? true
    }
}

/// Список подключений (без ограничения по числу) и выбранное из них — «интеллект» компаньона.
public struct LLMConnections: Codable, Equatable, Sendable {
    public private(set) var items: [LLMConnection]
    public private(set) var activeID: UUID?

    public init(items: [LLMConnection] = [], activeID: UUID? = nil) {
        self.items = items
        self.activeID = activeID
        normalize()
    }

    /// Подключения, которые участвуют в чате (переключатель «Использовать в чате»), в порядке списка.
    public var chatItems: [LLMConnection] { items.filter(\.useInChat) }

    /// Выбранное подключение для чата; если выбранное не в чате — первое из чата; nil — в чате никого нет.
    public var active: LLMConnection? {
        let chat = chatItems
        return chat.first { $0.id == activeID } ?? chat.first
    }

    /// Номер выбранного подключения среди участвующих в чате, с единицы.
    public var activePosition: Int? {
        guard let active, let index = chatItems.firstIndex(where: { $0.id == active.id }) else { return nil }
        return index + 1
    }

    public mutating func add(_ connection: LLMConnection) {
        items.append(connection)
        normalize()
    }

    public mutating func update(_ connection: LLMConnection) {
        guard let index = items.firstIndex(where: { $0.id == connection.id }) else { return }
        items[index] = connection
        normalize()
    }

    @discardableResult
    public mutating func remove(id: UUID) -> LLMConnection? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: index)
        normalize()
        return removed
    }

    /// Сдвигает подключение на одну позицию выше (delta < 0) или ниже (delta > 0). Порядок задаёт
    /// последовательность переключения «+» и «−» и строк лимитов; выбранное подключение не меняется.
    public mutating func move(id: UUID, by delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + (delta > 0 ? 1 : -1)
        guard delta != 0, items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    public mutating func setActive(_ id: UUID) {
        guard items.contains(where: { $0.id == id && $0.useInChat }) else { return }
        activeID = id
    }

    /// Переключает выбранное подключение на `delta` шагов по кругу; nil — список пуст.
    @discardableResult
    public mutating func cycle(by delta: Int) -> LLMConnection? {
        let chat = chatItems
        guard !chat.isEmpty else { return nil }
        let current = chat.firstIndex { $0.id == active?.id } ?? 0
        let count = chat.count
        let next = ((current + delta) % count + count) % count
        activeID = chat[next].id
        return chat[next]
    }

    private mutating func normalize() {
        if !items.contains(where: { $0.id == activeID && $0.useInChat }) { activeID = chatItems.first?.id }
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
