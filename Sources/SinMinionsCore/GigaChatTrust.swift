import Foundation
import Security

/// Проверка сертификата сервера: хостам GigaChat дополнительно доверяем по корню Минцифры.
/// Всем остальным хостам — обычная системная проверка.
public final class GigaChatTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var failure: String?

    /// Почему последняя проверка не прошла (для сообщения об ошибке и диагностики).
    public static var lastFailure: String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private static func record(_ text: String?) {
        lock.lock()
        failure = text
        lock.unlock()
    }

    private let anchors: [SecCertificate] = {
        guard let der = RussianTrustedRoot.der,
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return [] }
        return [certificate]
    }()

    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              GigaChatAPI.trustedHosts.contains(space.host) else { return (.performDefaultHandling, nil) }
        guard !anchors.isEmpty else {
            Self.record("встроенный сертификат Минцифры не прочитан")
            return (.performDefaultHandling, nil)
        }
        _ = SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        // Системные корни остаются в силе: меняется только набор доверенных точек для этих хостов.
        _ = SecTrustSetAnchorCertificatesOnly(trust, false)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            Self.record(nil)
            return (.useCredential, URLCredential(trust: trust))
        }
        let reason = error.map { CFErrorCopyDescription($0) as String } ?? "причина неизвестна"
        Self.record("\(space.host): \(reason) (цепочка из \(SecTrustGetCertificateCount(trust)) сертификатов)")
        // Не прошла и наша проверка: пусть система сама откажет с понятной ошибкой сертификата.
        return (.performDefaultHandling, nil)
    }
}
