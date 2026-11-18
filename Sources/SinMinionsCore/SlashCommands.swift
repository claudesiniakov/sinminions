import Foundation

/// Команды терминала, которые вводятся со «/».
public enum SlashCommand: Equatable, Sendable, CaseIterable {
    case help, nap, hide, corner, unlock, lock, resetLayout, settings, clear, next, previous, special
}

public enum SlashParseResult: Equatable, Sendable {
    case notACommand
    /// Начинается со «/», но такой команды нет; строка — как набрал пользователь (без аргументов).
    case unknown(String)
    case command(SlashCommand)
}

public enum SlashParser {
    /// Названия команд: латиница и русский вариант, чтобы не переключать раскладку.
    static let names: [SlashCommand: [String]] = [
        .help: ["/help", "/?", "/помощь", "/справка"],
        .nap: ["/sleep", "/nap", "/сон", "/спать"],
        .hide: ["/hide", "/скрыть"],
        .corner: ["/corner", "/угол"],
        .unlock: ["/unlock", "/разблокировать"],
        .lock: ["/lock", "/заблокировать"],
        .resetLayout: ["/reset", "/сброс"],
        .settings: ["/settings", "/настройки"],
        .clear: ["/clear", "/очистить"],
        .next: ["/next", "/след"],
        .previous: ["/prev", "/пред"],
        .special: ["/special", "/stats", "/статы"],
    ]

    public static func parse(_ text: String) -> SlashParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return .notACommand }
        // Аргументов у команд нет: берём первое слово.
        let word = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let lowered = word.lowercased()
        for (command, variants) in names where variants.contains(lowered) {
            return .command(command)
        }
        return .unknown(word)
    }

    /// Справка для строки «/help»: по строке на команду и подсказка про русские названия.
    public static let helpLines: [String] = [
        "/help — ЭТА СПРАВКА",
        "/sleep — УСЫПИТЬ НА 1 ЧАС",
        "/hide — СКРЫТЬ ПРИЗРАКА",
        "/corner — ВЕРНУТЬ В УГОЛ",
        "/unlock, /lock — РАЗБЛОКИРОВАТЬ И ЗАБЛОКИРОВАТЬ ОКНА",
        "/reset — СБРОСИТЬ РАСКЛАДКУ ОКОН",
        "/settings — ОТКРЫТЬ НАСТРОЙКИ",
        "/clear — ОЧИСТИТЬ ЧАТ",
        "/next, /prev — СЛЕДУЮЩЕЕ И ПРЕДЫДУЩЕЕ ПОДКЛЮЧЕНИЕ",
        "/special — S.P.E.C.I.A.L.: РАЗМЕР, СКОРОСТЬ, СОН",
        "РУССКИЕ НАЗВАНИЯ: /помощь /сон /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред /статы",
    ]
}
