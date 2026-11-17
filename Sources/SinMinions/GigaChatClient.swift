import Foundation
import Security
import SinMinionsCore

/// Клиент GigaChat: получает токен доступа (живёт 30 минут), кэширует его и отправляет переписку.
actor GigaChatClient {
    private let session: URLSession
    /// Запасной сеанс только на TLS 1.2: если рукопожатие по TLS 1.3 обрывается (сервер не принимает
    /// начало рукопожатия новой системы), повторяем по TLS 1.2 — серверы GigaChat его поддерживают.
    private let legacySession: URLSession
    private var useLegacy = false
    private var cached: (tag: String, token: AccessToken)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        session = URLSession(configuration: configuration, delegate: GigaChatTrust(), delegateQueue: nil)
        let legacy = URLSessionConfiguration.ephemeral
        legacy.timeoutIntervalForRequest = 90
        legacy.tlsMaximumSupportedProtocolVersion = .TLSv12
        legacySession = URLSession(configuration: legacy, delegate: GigaChatTrust(), delegateQueue: nil)
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

    private func fetch(_ request: URLRequest, on session: URLSession) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        return (data, http.statusCode)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        var retriedOverTLS12 = false
        do {
            if useLegacy { return try await fetch(request, on: legacySession) }
            do {
                return try await fetch(request, on: session)
            } catch let error as URLError where error.code == .secureConnectionFailed {
                retriedOverTLS12 = true
                let result = try await fetch(request, on: legacySession)
                // Дальше сразу идём по TLS 1.2, чтобы не повторять неудачное рукопожатие.
                useLegacy = true
                return result
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw LLMError.network(Self.describe(error, retriedOverTLS12: retriedOverTLS12))
        }
    }

    private static func describe(_ error: URLError, retriedOverTLS12: Bool) -> String {
        // Вложенные коды системы: по ним видно, на каком шаге оборвалось соединение.
        let ns = error as NSError
        var codes = ["код \(error.code.rawValue)"]
        if let stream = ns.userInfo["_kCFStreamErrorCodeKey"] as? Int { codes.append("поток \(stream)") }
        if let inner = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code { codes.append("вложенная \(inner)") }
        let suffix = " (" + codes.joined(separator: ", ") + ")"
        let trust = GigaChatTrust.lastNote.map { ". Проверка доверия: " + $0 } ?? ". Проверка доверия не вызывалась"
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "Нет подключения к сети" + suffix
        case .timedOut: return "Сервер не ответил вовремя" + suffix
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Не удалось связаться с сервером GigaChat" + suffix
        case .secureConnectionFailed:
            let tried = retriedOverTLS12 ? " (повтор по TLS 1.2 тоже не удался)" : ""
            return "Защищённое соединение с GigaChat не установилось" + tried + suffix + trust
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            return "Не удалось проверить сертификат сервера GigaChat" + suffix + trust
        default:
            return error.localizedDescription + suffix
        }
    }
}
