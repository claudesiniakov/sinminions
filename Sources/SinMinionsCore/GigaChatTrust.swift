import Foundation
import Security

/// Проверка сертификата сервера: хостам GigaChat дополнительно доверяем по корню Минцифры.
/// Всем остальным хостам — обычная системная проверка.
public final class GigaChatTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var note: String?

    /// Что произошло при последней проверке: пройдена или причина отказа (для сообщения об ошибке и диагностики).
    public static var lastNote: String? {
        lock.lock()
        defer { lock.unlock() }
        return note
    }

    private static func record(_ text: String?) {
        lock.lock()
        note = text
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
            Self.record(tr("встроенный сертификат Минцифры не прочитан"))
            return (.performDefaultHandling, nil)
        }
        _ = SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        // Системные корни остаются в силе: меняется только набор доверенных точек для этих хостов.
        _ = SecTrustSetAnchorCertificatesOnly(trust, false)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            Self.record(trf("%@: проверка пройдена", "\(space.host)"))
            return (.useCredential, URLCredential(trust: trust))
        }
        let reason = error.map { CFErrorCopyDescription($0) as String } ?? tr("причина неизвестна")
        // Запасной путь: имя хоста, срок действия и цепочка до встроенного корня остаются обязательными,
        // но отзыв сертификата по сети не проверяется и ничего из сети не подгружается
        // (сервер сам присылает промежуточный сертификат). Так недоступный сервер отзыва не блокирует чат.
        SecTrustSetNetworkFetchAllowed(trust, false)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, space.host as CFString))
        var fallbackError: CFError?
        if SecTrustEvaluateWithError(trust, &fallbackError) {
            Self.record(trf("%@: пройдена без проверки отзыва; первая попытка не прошла: %@", "\(space.host)", "\(reason)"))
            return (.useCredential, URLCredential(trust: trust))
        }
        let fallbackReason = fallbackError.map { CFErrorCopyDescription($0) as String } ?? tr("причина неизвестна")
        Self.record(trf("%@: отказ — %@; без отзыва — %@; цепочка из %@ сертификатов", "\(space.host)", "\(reason)", "\(fallbackReason)", "\(SecTrustGetCertificateCount(trust))"))
        // Не прошла и наша проверка: пусть система сама откажет с понятной ошибкой сертификата.
        return (.performDefaultHandling, nil)
    }
}
