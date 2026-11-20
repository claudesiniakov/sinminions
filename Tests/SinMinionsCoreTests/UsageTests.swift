import XCTest
@testable import SinMinionsCore

final class UsageTests: XCTestCase {
    func testParseAnthropicUsageWithCache() {
        let data = Data(#"{"usage":{"input_tokens":100,"cache_read_input_tokens":20,"output_tokens":50}}"#.utf8)
        XCTAssertEqual(TokenUsage.parse(data), TokenUsage(input: 120, output: 50))
    }

    func testParseOpenAIUsage() {
        let data = Data(#"{"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10}}"#.utf8)
        XCTAssertEqual(TokenUsage.parse(data), TokenUsage(input: 7, output: 3))
    }

    func testParseWithoutUsage() {
        XCTAssertNil(TokenUsage.parse(Data(#"{"choices":[]}"#.utf8)))
    }

    func testLedgerTotalsAndSeries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weekAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        var ledger = UsageLedger()
        ledger.record(provider: .claude, model: "m", usage: TokenUsage(input: 10, output: 5), at: now, calendar: calendar)
        ledger.record(provider: .claude, model: "m", usage: TokenUsage(input: 1, output: 1), at: now, calendar: calendar)
        ledger.record(provider: .claude, model: "m", usage: nil, at: weekAgo, calendar: calendar)
        ledger.record(provider: .gpt, model: "g", usage: TokenUsage(input: 3, output: 3), at: weekAgo, calendar: calendar)
        let key = UsageLedger.key(provider: .claude, model: "m")
        XCTAssertEqual(ledger.totals(key, lastDays: 1, now: now, calendar: calendar), UsageTotals(input: 11, output: 6, requests: 2))
        XCTAssertEqual(ledger.totals(key, lastDays: 7, now: now, calendar: calendar).requests, 2)
        XCTAssertEqual(ledger.totals(key, lastDays: nil, now: now, calendar: calendar).requests, 3)
        let series = ledger.series(key, days: 14, now: now, calendar: calendar)
        XCTAssertEqual(series.count, 14)
        XCTAssertEqual(series.last?.totals.total, 17)
        XCTAssertEqual(ledger.orderedKeys.first, key)
    }

    func testShortNumbers() {
        XCTAssertEqual(UsageLedger.short(950), "950")
        XCTAssertEqual(UsageLedger.short(12_300), "12,3 ТЫС")
        XCTAssertEqual(UsageLedger.short(2_000_000), "2 МЛН")
    }
}
