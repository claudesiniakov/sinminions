import Foundation

/// Claude (Anthropic): родной Messages API.
public enum AnthropicAPI {
    public static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelsURL = URL(string: "https://api.anthropic.com/v1/models")!
    public static let version = "2023-06-01"

    /// От простой и быстрой модели к самой мощной.
    public static let models = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-2"]

    private static func authorized(_ request: inout URLRequest, key: String) {
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// Системное сообщение идёт отдельным полем `system`, остальные — в `messages`.
    /// Температуру и другие параметры выборки не передаём: новые модели их не принимают.
    public static func chatRequest(key: String, model: String, messages: [ChatMessage]) -> URLRequest {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorized(&request, key: key)
        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": messages.filter { $0.role != .system }.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if !system.isEmpty { body["system"] = system }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Проверка ключа: список моделей.
    public static func modelsRequest(key: String) -> URLRequest {
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        authorized(&request, key: key)
        return request
    }

    /// Текст ответа: склеенные блоки типа `text` (блоки размышлений пропускаются).
    public static func parseMessage(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw LLMError.invalidResponse }
        if (json["stop_reason"] as? String) == "refusal" { throw LLMError.refused }
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw LLMError.emptyAnswer }
        return text
    }
}

/// GPT (OpenAI), Grok (xAI) и Gemini (Google): общий формат chat completions.
public enum OpenAICompatibleAPI {
    public static let gptModels = ["gpt-6-luna", "gpt-6.1-terra", "gpt-6.2-sol", "gpt-6.2-astra"]
    public static let grokModels = ["grok-4.3", "grok-4.5", "grok-4.6", "grok-4.7"]
    public static let geminiModels = [
        "gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash",
        "gemini-4-hydrogen", "gemini-4-argon", "gemini-4-carbon",
    ]

    /// Адреса чата и списка моделей; nil — провайдер не из этой группы.
    public static func endpoints(for provider: LLMProvider) -> (chat: URL, models: URL)? {
        switch provider {
        case .gpt:
            return (URL(string: "https://api.openai.com/v1/chat/completions")!, URL(string: "https://api.openai.com/v1/models")!)
        case .grok:
            return (URL(string: "https://api.x.ai/v1/chat/completions")!, URL(string: "https://api.x.ai/v1/models")!)
        case .gemini:
            return (
                URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
                URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!
            )
        case .gigachat, .deepseek, .claude:
            return nil
        }
    }

    public static func chatRequest(provider: LLMProvider, key: String, model: String, messages: [ChatMessage]) -> URLRequest? {
        guard let endpoint = endpoints(for: provider) else { return nil }
        var request = URLRequest(url: endpoint.chat)
        request.httpMethod = "POST"
        // Модели с размышлением отвечают дольше, но соединение держится.
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            // Новым моделям OpenAI вместо system положено developer.
            "messages": messages.map { message -> [String: String] in
                let role = (provider == .gpt && message.role == .system) ? "developer" : message.role.rawValue
                return ["role": role, "content": message.content]
            },
            "stream": false,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func modelsRequest(provider: LLMProvider, key: String) -> URLRequest? {
        guard let endpoint = endpoints(for: provider) else { return nil }
        var request = URLRequest(url: endpoint.models)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
}
