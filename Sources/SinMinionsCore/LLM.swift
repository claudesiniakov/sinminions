import Foundation

public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case system, user, assistant }
    public let role: Role
    public let content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// Этап запроса: у GigaChat сначала токен, потом чат; `direct` — провайдеры, где ключ идёт прямо в запросе.
public enum LLMStage: Sendable { case token, chat, direct }

public enum LLMError: LocalizedError, Equatable, Sendable {
    case noCredentials
    case http(Int, String?, LLMStage)
    case network(String)
    case invalidResponse
    case emptyAnswer

    private static func describeDirect(_ status: Int, _ detail: String?) -> String {
        let base: String
        switch status {
        case 400: base = "Некорректный запрос"
        case 401: base = "Ключ API не подходит"
        case 402: base = "Недостаточно средств на балансе"
        case 404: base = "Модель или адрес не найдены"
        case 422: base = "Сервер отклонил параметры запроса"
        case 429: base = "Слишком много запросов"
        case 500: base = "Ошибка на стороне сервиса"
        case 503: base = "Сервис перегружен, попробуйте позже"
        default: base = "Ошибка \(status)"
        }
        return detail.map { "\(base) — \($0)" } ?? base
    }

    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "Ключ GigaChat не задан"
        case let .http(status, detail, stage):
            if stage == .direct { return Self.describeDirect(status, detail) }
            let base: String
            switch status {
            case 400: base = stage == .token ? "Запрос токена отклонён, проверьте ключ" : "Некорректный запрос"
            case 401: base = stage == .token ? "Ключ авторизации не подходит: проверьте ключ и область доступа" : "Токен не принят"
            case 402: base = "Токены закончились"
            case 403: base = "Доступ запрещён"
            case 404: base = "Модель не найдена: выберите другую в настройках"
            case 413: base = "Слишком длинный запрос"
            case 422: base = "Сервер отклонил запрос"
            case 429: base = "Слишком много запросов: ключ физлица принимает один запрос за раз"
            case 500...599: base = "Сервис GigaChat недоступен (\(status))"
            default: base = "Ошибка \(status)"
            }
            return detail.map { "\(base) — \($0)" } ?? base
        case let .network(text):
            return text
        case .invalidResponse:
            return "Сервер вернул неожиданный ответ"
        case .emptyAnswer:
            return "Модель вернула пустой ответ"
        }
    }
}

public struct AccessToken: Equatable, Sendable {
    public let value: String
    public let expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }

    /// Токен живёт 30 минут; за минуту до конца уже считаем его негодным.
    public func isUsable(at now: Date, margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }
}

/// Протокол GigaChat API: запросы и разбор ответов. Сетевой слой — в приложении.
public enum GigaChatAPI {
    public static let tokenURL = URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!
    public static let chatURL = URL(string: "https://api.giga.chat/v1/chat/completions")!

    /// Только этим хостам приложение доверяет по корневому сертификату Минцифры.
    public static let trustedHosts: Set<String> = [
        "ngw.devices.sberbank.ru", "api.giga.chat", "gigachat.devices.sberbank.ru",
    ]

    /// Область доступа ключа: физлица, ИП и юрлица с пакетами, ИП и юрлица с оплатой по факту.
    public static let scopes = ["GIGACHAT_API_PERS", "GIGACHAT_API_B2B", "GIGACHAT_API_CORP"]
    /// Модели из документации (тарифы для физлиц, 7 октября 2026). `GigaChat-3-Ultra` доступна физлицам
    /// только по бесплатному пакету; псевдонимы `GigaChat-Pro` и `GigaChat-Max` вводятся вручную.
    public static let models = ["GigaChat", "GigaChat-2", "GigaChat-2-Pro", "GigaChat-2-Max", "GigaChat-3-Ultra"]

    /// Ключ авторизации без пробелов, переводов строк и приставки «Basic »; nil — ключа нет.
    public static func normalizedKey(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased() == "basic" { return nil }
        if text.lowercased().hasPrefix("basic ") { text = String(text.dropFirst(6)) }
        text = text.filter { !$0.isWhitespace }
        return text.isEmpty ? nil : text
    }

    public static func tokenRequest(
        authorizationKey: String, scope: String, rqUID: String = UUID().uuidString.lowercased()
    ) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(rqUID, forHTTPHeaderField: "RqUID")
        request.setValue("Basic \(authorizationKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("scope=\(scope)".utf8)
        return request
    }

    public static func chatRequest(token: String, model: String, messages: [ChatMessage]) -> URLRequest {
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Без User-Agent api.giga.chat отвечает 403.
        request.setValue("SinMinions", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": false,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// `expires_at` в документации приведён примером в секундах, но единица не оговорена, поэтому
    /// слишком большое число считаем миллисекундами.
    public static func parseToken(_ data: Data) throws -> AccessToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty,
              let expires = (json["expires_at"] as? NSNumber)?.doubleValue
        else { throw LLMError.invalidResponse }
        let seconds = expires >= 100_000_000_000 ? expires / 1000 : expires
        return AccessToken(value: token, expiresAt: Date(timeIntervalSince1970: seconds))
    }

    public static func parseChat(_ data: Data) throws -> String { try LLMResponse.parseChat(data) }

    /// Пояснение из тела ошибки; не длиннее 120 знаков.
    public static func errorDetail(_ data: Data) -> String? { LLMResponse.errorDetail(data) }
}

/// Разбор ответов в формате OpenAI: так отвечают GigaChat и DeepSeek.
public enum LLMResponse {
    public static func parseChat(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw LLMError.invalidResponse }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw LLMError.emptyAnswer }
        return text
    }

    /// Пояснение из тела ошибки: `{"message": "..."}` или `{"error": {"message": "..."}}`.
    public static func errorDetail(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message: String?
        if let top = json["message"] as? String {
            message = top
        } else if let error = json["error"] as? [String: Any] {
            message = error["message"] as? String
        } else {
            message = json["error"] as? String
        }
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }
}

public enum ChatHistory {
    /// Укорачивает переписку до `maxCharacters` знаков: системное сообщение и последнее остаются всегда,
    /// старые отбрасываются; диалог всегда начинается с сообщения пользователя.
    public static func trimmed(_ messages: [ChatMessage], maxCharacters: Int = 6000) -> [ChatMessage] {
        let system = messages.first?.role == .system ? [messages[0]] : []
        var dialog = Array(messages.dropFirst(system.count))
        func size() -> Int { (system + dialog).reduce(0) { $0 + $1.content.count } }
        while dialog.count > 1, size() > maxCharacters { dialog.removeFirst() }
        while dialog.count > 1, dialog.first?.role == .assistant { dialog.removeFirst() }
        return system + dialog
    }
}
