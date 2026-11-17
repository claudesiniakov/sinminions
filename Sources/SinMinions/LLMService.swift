import Foundation
import SinMinionsCore

/// Единая точка для чата и проверки: выбирает клиента по провайдеру подключения.
final class LLMService: Sendable {
    private let gigaChat = GigaChatClient()
    private let deepSeek = DeepSeekClient()

    func send(_ messages: [ChatMessage], connection: LLMConnection, key: String) async throws -> String {
        switch connection.provider {
        case .gigachat:
            return try await gigaChat.send(messages, key: key, scope: connection.scope, model: connection.model)
        case .deepseek:
            return try await deepSeek.send(messages, key: key, model: connection.model)
        }
    }

    /// Остаток токенов или средств на счёте для строки лимитов; nil — данных нет.
    func limits(connection: LLMConnection, key: String) async throws -> String? {
        switch connection.provider {
        case .gigachat:
            return try await gigaChat.limits(key: key, scope: connection.scope, model: connection.model)
        case .deepseek:
            return try await deepSeek.limits(key: key)
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
        }
    }
}
