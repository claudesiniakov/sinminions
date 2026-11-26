import Foundation

/// Язык интерфейса. `system` — как в macOS: если языка системы нет в списке, английский.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, ru, en, de, es

    public var id: String { rawValue }

    /// Название в списке — на самом языке, чтобы его нашёл тот, кто текущий язык не понимает.
    public var title: String {
        switch self {
        case .system: return tr("Как в системе")
        case .ru: return "Русский"
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    /// Конкретный язык: «как в системе» раскрывается по предпочтениям macOS.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferred {
            let code = String(identifier.prefix(2)).lowercased()
            if let language = AppLanguage(rawValue: code), language != .system { return language }
        }
        return .en
    }
}

/// Перевод строк интерфейса. Ключ — русский текст из исходников; `%@` — подстановки.
/// Нет перевода — показывается русский текст.
public enum L10n {
    /// Текущий язык (уже раскрытый). По умолчанию русский: так работают тесты и исходные тексты.
    /// Читается и с главного потока (интерфейс), и из фоновых задач (ошибки, лимиты), поэтому под замком.
    nonisolated(unsafe) private static var storedCurrent: AppLanguage = .ru
    private static let currentLock = NSLock()

    public static var current: AppLanguage {
        get {
            currentLock.lock()
            defer { currentLock.unlock() }
            return storedCurrent
        }
        set {
            currentLock.lock()
            storedCurrent = newValue
            currentLock.unlock()
        }
    }

    public static func translate(_ key: String, to language: AppLanguage) -> String {
        switch language {
        case .ru, .system: return key
        case .en: return Translations.en[key] ?? key
        case .de: return Translations.de[key] ?? key
        case .es: return Translations.es[key] ?? key
        }
    }

    /// Подставляет аргументы по порядку вместо `%@`.
    public static func fill(_ format: String, _ args: [String]) -> String {
        var result = ""
        var rest = Substring(format)
        var index = 0
        while let range = rest.range(of: "%@") {
            result += rest[..<range.lowerBound]
            result += index < args.count ? args[index] : ""
            index += 1
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}

/// Строка интерфейса на текущем языке.
public func tr(_ key: String) -> String {
    L10n.translate(key, to: L10n.current)
}

/// Строка с подстановками: `trf("Версия %@", version)`.
public func trf(_ key: String, _ args: String...) -> String {
    L10n.fill(tr(key), args)
}
