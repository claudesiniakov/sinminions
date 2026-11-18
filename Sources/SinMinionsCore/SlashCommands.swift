import Foundation

/// Команды терминала, которые вводятся со «/».
public enum SlashCommand: Equatable, Sendable, CaseIterable {
    case help, nap, coffee, hide, corner, unlock, lock, resetLayout, settings, clear, next, previous
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
        .coffee: ["/coffee", "/кофе"],
        .hide: ["/hide", "/скрыть"],
        .corner: ["/corner", "/угол"],
        .unlock: ["/unlock", "/разблокировать"],
        .lock: ["/lock", "/заблокировать"],
        .resetLayout: ["/reset", "/сброс"],
        .settings: ["/settings", "/настройки"],
        .clear: ["/clear", "/очистить"],
        .next: ["/next", "/след"],
        .previous: ["/prev", "/пред"],
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

    /// Краткие описания для подсказок при вводе.
    static let summaries: [SlashCommand: String] = [
        .help: "справка по командам", .nap: "усыпить на час", .coffee: "не давать ноутбуку уснуть (вкл/выкл)", .hide: "скрыть призрака",
        .corner: "вернуть в угол", .unlock: "разблокировать окна", .lock: "заблокировать окна",
        .resetLayout: "сбросить раскладку", .settings: "открыть настройки", .clear: "очистить чат",
        .next: "следующее подключение", .previous: "предыдущее подключение",
    ]

    public struct Hint: Equatable, Sendable {
        public let name: String
        public let summary: String
    }

    /// Подсказки по началу ввода: команды, чьё название начинается с введённого. Название берётся в той же
    /// раскладке, что набрана (русское, если ввод начат по-русски). Пустой результат — не команда или нет совпадений.
    public static func hints(for input: String) -> [Hint] {
        let text = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.hasPrefix("/"), !text.contains(" ") else { return [] }
        var result: [Hint] = []
        for command in SlashCommand.allCases {
            guard let variants = names[command] else { continue }
            let matching = variants.filter { $0.hasPrefix(text) && $0 != "/?" }
            guard let name = matching.first else { continue }
            if !result.contains(where: { $0.name == name }) {
                result.append(Hint(name: name, summary: summaries[command] ?? ""))
            }
        }
        return result
    }

    /// Дописывает ввод по Tab: единственная подсказка — целиком, несколько — общее начало. nil — нечего дописывать.
    public static func completion(for input: String) -> String? {
        let found = hints(for: input)
        guard let first = found.first else { return nil }
        var prefix = first.name
        for hint in found.dropFirst() {
            while !hint.name.hasPrefix(prefix) { prefix.removeLast() }
        }
        let typed = input.trimmingCharacters(in: .whitespaces).lowercased()
        if found.count == 1 { return first.name == typed ? nil : first.name }
        return prefix.count > typed.count ? prefix : nil
    }

    /// Справка для строки «/help»: по строке на команду и подсказка про русские названия.
    public static let helpLines: [String] = [
        "/help — ЭТА СПРАВКА",
        "/sleep — УСЫПИТЬ НА 1 ЧАС",
        "/coffee — НЕ ДАВАТЬ НОУТБУКУ УСНУТЬ (ВКЛ/ВЫКЛ), У ПРИЗРАКА ЧАШКА КОФЕ",
        "/hide — СКРЫТЬ ПРИЗРАКА",
        "/corner — ВЕРНУТЬ В УГОЛ",
        "/unlock, /lock — РАЗБЛОКИРОВАТЬ И ЗАБЛОКИРОВАТЬ ОКНА",
        "/reset — СБРОСИТЬ РАСКЛАДКУ ОКОН",
        "/settings — ОТКРЫТЬ НАСТРОЙКИ",
        "/clear — ОЧИСТИТЬ ЧАТ",
        "/next, /prev — СЛЕДУЮЩЕЕ И ПРЕДЫДУЩЕЕ ПОДКЛЮЧЕНИЕ",
        "РУССКИЕ НАЗВАНИЯ: /помощь /сон /кофе /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред",
    ]
}
