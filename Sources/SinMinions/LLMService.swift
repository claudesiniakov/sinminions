import Foundation
import SinMinionsCore

/// Единая точка для чата и проверки: выбирает клиента по провайдеру подключения.
final class LLMService: Sendable {
    private let gigaChat = GigaChatClient()
    private let deepSeek = DeepSeekClient()
    private let anthropic = AnthropicClient()
    private let gpt = OpenAICompatibleClient(provider: .gpt)
    private let grok = OpenAICompatibleClient(provider: .grok)
    private let gemini = OpenAICompatibleClient(provider: .gemini)

    func send(_ messages: [ChatMessage], connection: LLMConnection, key: String) async throws -> String {
        switch connection.provider {
        case .gigachat:
            return try await gigaChat.send(messages, key: key, scope: connection.scope, model: connection.model)
        case .deepseek:
            return try await deepSeek.send(messages, key: key, model: connection.model)
        case .claude:
            return try await anthropic.send(messages, key: key, model: connection.model)
        case .gpt:
            return try await gpt.send(messages, key: key, model: connection.model)
        case .grok:
            return try await grok.send(messages, key: key, model: connection.model)
        case .gemini:
            return try await gemini.send(messages, key: key, model: connection.model)
        }
    }

    /// Остаток токенов или средств на счёте для строки лимитов; nil — данных нет.
    func limits(connection: LLMConnection, key: String) async throws -> String? {
        switch connection.provider {
        case .gigachat:
            return try await gigaChat.limits(key: key, scope: connection.scope, model: connection.model)
        case .deepseek:
            return try await deepSeek.limits(key: key)
        case .claude, .gpt, .grok, .gemini:
            // Остаток по обычному ключу эти сервисы не отдают.
            return nil
        }
    }

    /// Проверка подключения. Строка — что показать рядом с «работает» (например, баланс).
    func check(connection: LLMConnection, key: String) async throws -> String? {
        switch connection.provider {
        case .gigachat:
            try await gigaChat.checkConnection(key: key, scope: connection.scope)
            return nil
        case .deepseek:
            return try await deepSeek.check(key: key)
        case .claude:
            return try await anthropic.check(key: key)
        case .gpt:
            return try await gpt.check(key: key)
        case .grok:
            return try await grok.check(key: key)
        case .gemini:
            return try await gemini.check(key: key)
        }
    }
}
