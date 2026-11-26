import Foundation
import Security
import SinMinionsCore

enum GigaChatAccount {
    static let key = "gigachat-authorization-key"
}

struct KeychainError: LocalizedError, Equatable {
    let status: OSStatus
    /// Пользователь отказал или система не дала показать запрос доступа.
    var isAccessDenied: Bool {
        status == errSecAuthFailed || status == errSecUserCanceled
            || status == errSecInteractionNotAllowed || status == errSecMissingEntitlement
    }

    var errorDescription: String? {
        if isAccessDenied { return tr("Нет доступа к ключу в Связке ключей") }
        return (SecCopyErrorMessageString(status, nil) as String?) ?? trf("Ошибка Связки ключей (%@)", "\(status)")
    }
}

/// Секреты приложения лежат в Связке ключей, а не в настройках.
///
/// Запись создаётся с ACL, привязанным к подписи приложения: обновления с тем же
/// сертификатом доступа не спрашивают, а запуск неподписанной копии (например, отладочного
/// бинарника из `.build`) — спрашивает. Поэтому доступ к Связке закрыт, если приложение
/// запущено не из бандла: такой запуск не должен трогать настоящий профиль.
enum Keychain {
    static let service = "com.claudesiniakov.sinminions"

    /// Работаем только из собранного приложения: у запуска из `.build` нет бандла,
    /// а значит, и той подписи, под которой запись создавалась.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Есть ли запись. Сам секрет при этом не читается, поэтому система ничего не спрашивает.
    static func exists(_ account: String) -> Bool {
        guard available else { return false }
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    /// Запись целиком. `keychainStatus` отличает «нет записи» от «пользователь не разрешил» —
    /// это нужно, чтобы показать не «нет ключа», а понятную причину.
    static func readChecked(_ account: String) -> (value: String?, status: OSStatus) {
        guard available else { return (nil, errSecItemNotFound) }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess else { return (nil, status) }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            return (nil, errSecDecode)
        }
        return (text, errSecSuccess)
    }

    static func read(_ account: String) -> String? {
        readChecked(account).value
    }

    static func write(_ value: String, account: String) throws {
        guard available else { throw KeychainError(status: errSecMissingEntitlement) }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = query(account)
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    static func delete(_ account: String) {
        guard available else { return }
        SecItemDelete(query(account) as CFDictionary)
    }
}
