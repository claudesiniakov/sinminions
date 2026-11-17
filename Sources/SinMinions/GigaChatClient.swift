import Foundation
import Security
import SinMinionsCore

/// Клиент GigaChat: получает токен доступа (живёт 30 минут), кэширует его и отправляет переписку.
actor GigaChatClient {
    private let session: URLSession
    private var cached: (tag: String, token: AccessToken)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        session = URLSession(configuration: configuration, delegate: GigaChatTrust(), delegateQueue: nil)
    }

    /// Проверка ключа: запрашивает новый токен.
    func checkConnection(key: String, scope: String) async throws {
        _ = try await token(key: key, scope: scope, forceRefresh: true)
    }

    func send(_ messages: [ChatMessage], key: String, scope: String, model: String) async throws -> String {
        var refreshed = false
        while true {
            let token = try await token(key: key, scope: scope, forceRefresh: refreshed)
            let request = GigaChatAPI.chatRequest(token: token.value, model: model, messages: ChatHistory.trimmed(messages))
            let (data, status) = try await perform(request)
            // Токен могли отозвать раньше срока: один раз получаем новый и повторяем.
            if status == 401, !refreshed {
                refreshed = true
                continue
            }
            guard (200..<300).contains(status) else {
                throw LLMError.http(status, GigaChatAPI.errorDetail(data), .chat)
            }
            return try GigaChatAPI.parseChat(data)
        }
    }

    private func token(key rawKey: String, scope: String, forceRefresh: Bool) async throws -> AccessToken {
        guard let key = GigaChatAPI.normalizedKey(rawKey) else { throw LLMError.noCredentials }
        let tag = scope + "|" + String(key.hashValue)
        if !forceRefresh, let cached, cached.tag == tag, cached.token.isUsable(at: Date()) {
            return cached.token
        }
        let (data, status) = try await perform(GigaChatAPI.tokenRequest(authorizationKey: key, scope: scope))
        guard status == 200 else { throw LLMError.http(status, GigaChatAPI.errorDetail(data), .token) }
        let token = try GigaChatAPI.parseToken(data)
        cached = (tag, token)
        return token
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
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "Нет подключения к сети"
        case .timedOut: return "Сервер не ответил вовремя"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Не удалось связаться с сервером GigaChat"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            var text = "Не удалось проверить сертификат сервера GigaChat (код \(error.code.rawValue))"
            if let reason = GigaChatTrust.lastFailure { text += ": " + reason }
            return text
        default: return error.localizedDescription + " (код \(error.code.rawValue))"
        }
    }
}
