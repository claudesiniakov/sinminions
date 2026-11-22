import Foundation
import SinMinionsCore

/// Клиент DeepSeek: обычный HTTPS через общий транспорт (`HTTPTransport`) с системной проверкой сертификатов.
actor DeepSeekClient {
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
        try await HTTPTransport.perform(request, service: "DeepSeek")
    }
}
