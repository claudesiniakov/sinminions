import Foundation

/// DeepSeek API: формат OpenAI, ключ передаётся заголовком `Authorization: Bearer`.
public enum DeepSeekAPI {
    public static let chatURL = URL(string: "https://api.deepseek.com/chat/completions")!
    public static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    /// Актуальные модели из документации; других (например, будущих) можно ввести вручную.
    public static let models = ["deepseek-flash", "deepseek-v4-pro"]

    /// Ключ без пробелов, переводов строк и приставки «Bearer »; nil — ключа нет.
    public static func normalizedKey(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased() == "bearer" { return nil }
        if text.lowercased().hasPrefix("bearer ") { text = String(text.dropFirst(7)) }
        text = text.filter { !$0.isWhitespace }
        return text.isEmpty ? nil : text
    }

    public static func chatRequest(key: String, model: String, messages: [ChatMessage]) -> URLRequest {
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        // Пока модель думает, сервер шлёт пустые строки, а ответ приходит целиком: ждём подольше.
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": false,
            // Режим размышления выключен: в терминале нужны короткие быстрые ответы.
            "thinking": ["type": "disabled"],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Запрос баланса: заодно проверяет, что ключ принят.
    public static func balanceRequest(key: String) -> URLRequest {
        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// «110.00 CNY» (несколько валют — через запятую); nil — ответ не разобрать.
    public static func balanceSummary(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]] else { return nil }
        let amounts = infos.compactMap { info -> String? in
            guard let total = info["total_balance"] as? String, let currency = info["currency"] as? String else { return nil }
            return "\(total) \(currency)"
        }
        return amounts.isEmpty ? nil : amounts.joined(separator: ", ")
    }

    /// «баланс 110.00 CNY» (несколько валют — через запятую); nil — ответ не разобрать.
    public static func parseBalance(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]] else { return nil }
        let amounts = infos.compactMap { info -> String? in
            guard let total = info["total_balance"] as? String, let currency = info["currency"] as? String else { return nil }
            return "\(total) \(currency)"
        }
        guard !amounts.isEmpty else { return nil }
        let text = "баланс " + amounts.joined(separator: ", ")
        return (json["is_available"] as? Bool) == false ? text + " (недостаточно для запросов)" : text
    }
}
