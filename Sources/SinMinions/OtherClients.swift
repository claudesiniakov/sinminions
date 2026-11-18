import Foundation
import SinMinionsCore

/// Общий HTTPS-транспорт для провайдеров с обычной системной проверкой сертификатов.
enum HTTPTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Модели с размышлением отвечают долго, но соединение не простаивает.
        configuration.timeoutIntervalForRequest = 180
        return URLSession(configuration: configuration)
    }()

    static func perform(_ request: URLRequest, service: String) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
            return (data, http.statusCode)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw LLMError.network(describe(error, service: service))
        }
    }

    private static func describe(_ error: URLError, service: String) -> String {
        let suffix = " (код \(error.code.rawValue))"
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "Нет подключения к сети" + suffix
        case .timedOut: return "Сервер не ответил вовремя" + suffix
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Не удалось связаться с сервером \(service)" + suffix
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "Не удалось установить защищённое соединение с \(service)" + suffix
        default: return error.localizedDescription + suffix
        }
    }

    /// «моделей: 12» из списка моделей `{"data": [...]}`.
    static func modelCount(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [Any] else { return nil }
        return "моделей: \(items.count)"
    }
}

/// Клиент Claude: родной Messages API Anthropic.
actor AnthropicClient {
    func send(_ messages: [ChatMessage], key: String, model: String) async throws -> String {
        let request = AnthropicAPI.chatRequest(key: key, model: model, messages: ChatHistory.trimmed(messages))
        let (data, status) = try await HTTPTransport.perform(request, service: "Claude")
        guard (200..<300).contains(status) else {
            throw LLMError.http(status, LLMResponse.errorDetail(data), .direct)
        }
        return try AnthropicAPI.parseMessage(data)
    }

    /// Проверка ключа: список моделей. Строка — что показать рядом с «работает».
    func check(key: String) async throws -> String? {
        let (data, status) = try await HTTPTransport.perform(AnthropicAPI.modelsRequest(key: key), service: "Claude")
        guard status == 200 else { throw LLMError.http(status, LLMResponse.errorDetail(data), .direct) }
        return HTTPTransport.modelCount(data)
    }
}

/// Клиент GPT (OpenAI), Grok (xAI) и Gemini (Google): общий формат chat completions.
actor OpenAICompatibleClient {
    private let provider: LLMProvider

    init(provider: LLMProvider) {
        self.provider = provider
    }

    func send(_ messages: [ChatMessage], key: String, model: String) async throws -> String {
        guard let request = OpenAICompatibleAPI.chatRequest(
            provider: provider, key: key, model: model, messages: ChatHistory.trimmed(messages)
        ) else { throw LLMError.invalidResponse }
        let (data, status) = try await HTTPTransport.perform(request, service: provider.title)
        guard (200..<300).contains(status) else {
            throw LLMError.http(status, LLMResponse.errorDetail(data), .direct)
        }
        return try LLMResponse.parseChat(data)
    }

    func check(key: String) async throws -> String? {
        guard let request = OpenAICompatibleAPI.modelsRequest(provider: provider, key: key) else {
            throw LLMError.invalidResponse
        }
        let (data, status) = try await HTTPTransport.perform(request, service: provider.title)
        guard status == 200 else { throw LLMError.http(status, LLMResponse.errorDetail(data), .direct) }
        return HTTPTransport.modelCount(data)
    }
}
