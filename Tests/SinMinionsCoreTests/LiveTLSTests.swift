import XCTest
@testable import SinMinionsCore

/// Живая проверка TLS: серверы GigaChat с корнем Минцифры. Запускается только в CI (SINMINIONS_LIVE_TLS=1)
/// и ходит с заведомо неверным ключом — достаточно, чтобы сервер ответил кодом, а не ошибкой сертификата.
final class LiveTLSTests: XCTestCase {
    private func status(of request: URLRequest, label: String, tls12Only: Bool = false) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        if tls12Only { configuration.tlsMaximumSupportedProtocolVersion = .TLSv12 }
        let session = URLSession(configuration: configuration, delegate: GigaChatTrust(), delegateQueue: nil)
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("LIVE \(label): HTTP \(code) \(String(data: data.prefix(120), encoding: .utf8) ?? "")")
            print("LIVE \(label): доверие — \(GigaChatTrust.lastNote ?? "делегат не вызывался")")
            return code
        } catch let error as URLError {
            let ns = error as NSError
            print("LIVE \(label): URLError \(error.code.rawValue) \(ns.localizedDescription)")
            print("LIVE \(label): userInfo \(ns.userInfo)")
            print("LIVE \(label): наша проверка — \(GigaChatTrust.lastNote ?? "не вызывалась")")
            XCTFail("\(label): \(error.code.rawValue) \(ns.localizedDescription); \(GigaChatTrust.lastNote ?? "делегат ничего не записал")")
            return -1
        }
    }

    func testTokenHost() async throws {
        guard ProcessInfo.processInfo.environment["SINMINIONS_LIVE_TLS"] != nil else { throw XCTSkip("только в CI") }
        let request = GigaChatAPI.tokenRequest(authorizationKey: "dGVzdDp0ZXN0", scope: "GIGACHAT_API_PERS")
        let code = try await status(of: request, label: "ngw.devices.sberbank.ru:9443")
        XCTAssertTrue([400, 401].contains(code), "ожидали 400 или 401, получили \(code)")
    }

    /// Запасной транспорт приложения: те же серверы через системный curl.
    func testBothHostsOverCurl() async throws {
        guard ProcessInfo.processInfo.environment["SINMINIONS_LIVE_TLS"] != nil else { throw XCTSkip("только в CI") }
        let token = GigaChatAPI.tokenRequest(authorizationKey: "dGVzdDp0ZXN0", scope: "GIGACHAT_API_PERS")
        let (tokenBody, tokenCode) = try await CurlTransport.run(token)
        print("LIVE curl ngw.devices.sberbank.ru:9443: HTTP \(tokenCode) \(String(data: tokenBody.prefix(120), encoding: .utf8) ?? "")")
        XCTAssertTrue([400, 401].contains(tokenCode), "ожидали 400 или 401, получили \(tokenCode)")
        let chat = GigaChatAPI.chatRequest(token: "x", model: "GigaChat", messages: [ChatMessage(.user, "привет \"мир\"")])
        let (chatBody, chatCode) = try await CurlTransport.run(chat)
        print("LIVE curl api.giga.chat: HTTP \(chatCode) \(String(data: chatBody.prefix(120), encoding: .utf8) ?? "")")
        XCTAssertTrue([400, 401, 403].contains(chatCode), "ожидали 400, 401 или 403, получили \(chatCode)")
    }

    func testChatHost() async throws {
        guard ProcessInfo.processInfo.environment["SINMINIONS_LIVE_TLS"] != nil else { throw XCTSkip("только в CI") }
        let request = GigaChatAPI.chatRequest(token: "x", model: "GigaChat", messages: [ChatMessage(.user, "привет")])
        let code = try await status(of: request, label: "api.giga.chat")
        XCTAssertTrue([400, 401, 403].contains(code), "ожидали 400, 401 или 403, получили \(code)")
    }
}
