import Foundation
import SinMinionsCore

/// Клиент DeepSeek: обычный HTTPS с системной проверкой сертификатов.
actor DeepSeekClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        // Пока модель думает, сервер шлёт пустые строки, поэтому соединение не простаивает.
        configuration.timeoutIntervalForRequest = 180
        session = URLSession(configuration: configuration)
    }

    func send(_ messages: [ChatMessage], key: String, model: String) async throws -> LLMReply {
        let request = DeepSeekAPI.chatRequest(key: key, model: model, messages: ChatHistory.trimmed(messages))
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw LLMError.http(status, LLMResponse.errorDetail(data), .direct)
        }
        return LLMReply(text: try LLMResponse.parseChat(data), usage: TokenUsage.parse(data))
    }

    /// Проверка ключа: запрашивает баланс. Строка — что показать рядом с «работает».
    func check(key: String) async throws -> String? {
        let (data, status) = try await perform(DeepSeekAPI.balanceRequest(key: key))
        guard status == 200 else { throw LLMError.http(status, LLMResponse.errorDetail(data), .direct) }
        return DeepSeekAPI.parseBalance(data)
    }

    /// Остаток на счёте: «110.00 CNY»; nil — в ответе нет данных.
    func limits(key: String) async throws -> String? {
        let (data, status) = try await perform(DeepSeekAPI.balanceRequest(key: key))
        guard status == 200 else { throw LLMError.http(status, LLMResponse.errorDetail(data), .direct) }
        return DeepSeekAPI.balanceSummary(data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
            return (data, http.statusCode)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw LLMError.network(Self.describe(error))
        }
    }

    private static func describe(_ error: URLError) -> String {
        let suffix = " (код \(error.code.rawValue))"
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "Нет подключения к сети" + suffix
        case .timedOut: return "Сервер не ответил вовремя" + suffix
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Не удалось связаться с сервером DeepSeek" + suffix
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "Не удалось установить защищённое соединение с DeepSeek" + suffix
        default: return error.localizedDescription + suffix
        }
    }
}
