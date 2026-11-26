import XCTest
@testable import SinMinionsCore

final class L10nTests: XCTestCase {
    override func tearDown() {
        L10n.current = .ru
        super.tearDown()
    }

    func testRussianIsIdentity() {
        L10n.current = .ru
        XCTAssertEqual(tr("Система"), "Система")
        XCTAssertEqual(trf("Версия %@", "1.0"), "Версия 1.0")
    }

    func testTranslations() {
        XCTAssertEqual(L10n.translate("Система", to: .en), "System")
        XCTAssertEqual(L10n.translate("Система", to: .de), "System")
        XCTAssertEqual(L10n.translate("Система", to: .es), "Sistema")
        L10n.current = .de
        XCTAssertEqual(trf("Версия %@", "2"), "Version 2")
        // Перевод строки внутри ключа.
        XCTAssertTrue(tr("ДАННЫХ ПОКА НЕТ.\nЗАДАЙТЕ ВОПРОС В ЧАТЕ — РАСХОД ТОКЕНОВ ПРИДЁТ В ОТВЕТЕ API.").hasPrefix("NOCH KEINE DATEN.\n"))
        // Нет перевода — русский текст.
        XCTAssertEqual(tr("строка без перевода"), "строка без перевода")
    }

    func testEveryLanguageHasSameKeys() {
        XCTAssertGreaterThan(Translations.en.count, 500)
        XCTAssertEqual(Translations.en.count, Translations.de.count)
        XCTAssertEqual(Translations.en.count, Translations.es.count)
    }

    /// Все реплики V должны быть переведены: иначе в en/de/es она молча переходит на русский.
    /// Гейт check-l10n видит только литералы `tr(...)`, а реплики берутся из наборов,
    /// поэтому нужна отдельная проверка.
    func testEveryVPhraseIsTranslated() {
        var missing: [String] = []
        for kind in PhraseKind.allCases {
            for hour in [3, 9, 15, 20] {
                for phrase in PhraseBook.pool(kind, hour: hour, character: .v) {
                    if Translations.en[phrase] == nil || Translations.de[phrase] == nil || Translations.es[phrase] == nil {
                        missing.append("\(kind): \(phrase)")
                    }
                }
            }
        }
        XCTAssertTrue(missing.isEmpty, "нет перевода у \(missing.count) реплик:\n" + missing.prefix(10).joined(separator: "\n"))
    }

    func testPhrasesAndAnthemTranslated() {
        L10n.current = .en
        var book = PhraseBook(character: .ab)
        let phrase = book.next(.click, hour: 12)
        XCTAssertNil(phrase.range(of: "[А-Яа-яЁё]", options: .regularExpression), phrase)
        XCTAssertTrue(Anthem.lines.last?.contains("to battle") == true)
    }

    func testResolvedLanguage() {
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["de-DE", "en"]), .de)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["fr-FR"]), .en)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["ru-RU"]), .ru)
        XCTAssertEqual(AppLanguage.es.resolved(preferred: ["ru"]), .es)
    }

    func testFill() {
        XCTAssertEqual(L10n.fill("%@ → %@", ["a", "b"]), "a → b")
        XCTAssertEqual(L10n.fill("100 %", []), "100 %")
    }
}
