import Foundation
import Security
import SinMinionsCore

/// Клиент GigaChat: получает токен доступа (живёт 30 минут), кэширует его и отправляет переписку.
///
/// Транспорта два: встроенный сетевой клиент и системный `curl`. На macOS 27 встроенный обрывает
/// рукопожатие с серверами GigaChat, поэтому при такой ошибке запрос повторяется через `curl`,
/// а удачный транспорт запоминается и в следующий раз пробуется первым.
actor GigaChatClient {
    private enum Transport { case urlSession, curl }

    private struct TransportFailure: Error {
        let text: String
        /// Ошибка соединения, при которой есть смысл попробовать другой транспорт.
        let canFallBack: Bool
    }

    private static let preferCurlKey = "gigachatPreferCurl"

    private let session: URLSession
    private var preferCurl = UserDefaults.standard.bool(forKey: GigaChatClient.preferCurlKey)
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

    // MARK: - Транспорт

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let first: Transport = preferCurl ? .curl : .urlSession
        let second: Transport = preferCurl ? .urlSession : .curl
        do {
            do {
                return try await run(request, via: first)
            } catch let failure as TransportFailure where failure.canFallBack {
                do {
                    let result = try await run(request, via: second)
                    // Запоминаем рабочий транспорт: неудачную попытку больше не повторяем.
                    preferCurl = second == .curl
                    UserDefaults.standard.set(preferCurl, forKey: Self.preferCurlKey)
                    return result
                } catch let other as TransportFailure {
                    throw TransportFailure(text: failure.text + "; запасной путь: " + other.text, canFallBack: false)
                }
            }
        } catch let failure as TransportFailure {
            throw LLMError.network(failure.text)
        }
    }

    private func run(_ request: URLRequest, via transport: Transport) async throws -> (Data, Int) {
        switch transport {
        case .urlSession:
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
                return (data, http.statusCode)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw TransportFailure(text: Self.describe(error), canFallBack: Self.isHandshakeFailure(error))
            }
        case .curl:
            do {
                return try await CurlTransport.run(request)
            } catch let failure as CurlTransport.Failure {
                if Task.isCancelled { throw CancellationError() }
                let canFallBack = failure.exitCode < 0 || CurlTransport.tlsExitCodes.contains(failure.exitCode)
                throw TransportFailure(
                    text: "curl: \(failure.message) (код \(failure.exitCode))", canFallBack: canFallBack
                )
            }
        }
    }

    private static func isHandshakeFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid: return true
        default: return false
        }
    }

    private static func describe(_ error: URLError) -> String {
        // Вложенные коды системы: по ним видно, на каком шаге оборвалось соединение.
        let ns = error as NSError
        var codes = ["код \(error.code.rawValue)"]
        if let stream = ns.userInfo["_kCFStreamErrorCodeKey"] as? Int { codes.append("поток \(stream)") }
        if let inner = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code { codes.append("вложенная \(inner)") }
        let suffix = " (" + codes.joined(separator: ", ") + ")"
        let trust = GigaChatTrust.lastNote.map { ". Проверка доверия: " + $0 } ?? ""
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "Нет подключения к сети" + suffix
        case .timedOut: return "Сервер не ответил вовремя" + suffix
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Не удалось связаться с сервером GigaChat" + suffix
        case .secureConnectionFailed:
            return "Встроенный клиент не установил защищённое соединение" + suffix + trust
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            return "Не удалось проверить сертификат сервера GigaChat" + suffix + trust
        default:
            return error.localizedDescription + suffix
        }
    }
}
