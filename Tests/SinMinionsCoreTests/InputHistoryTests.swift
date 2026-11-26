import XCTest
@testable import SinMinionsCore

/// История ввода для стрелок ↑/↓ в чате.
final class InputHistoryTests: XCTestCase {
    func testOlderWalksBackFromNewest() {
        var history = InputHistory()
        history.remember("первый")
        history.remember("второй")
        XCTAssertEqual(history.older(), "второй")
        XCTAssertEqual(history.older(), "первый")
        // Дальше история не двигается: первая реплика остаётся на экране.
        XCTAssertEqual(history.older(), "первый")
    }

    func testNewerWalksForwardAndEndsWithNil() {
        var history = InputHistory()
        history.remember("первый")
        history.remember("второй")
        _ = history.older()
        _ = history.older()
        XCTAssertEqual(history.newer(), "второй")
        XCTAssertNil(history.newer(), "после последней реплики поле очищается")
        XCTAssertNil(history.newer(), "дальше листать нечего")
    }

    func testRememberResetsBrowsing() {
        var history = InputHistory()
        history.remember("один")
        _ = history.older()
        history.remember("два")
        XCTAssertEqual(history.older(), "два")
    }

    func testEmptyAndDuplicateLinesAreIgnored() {
        var history = InputHistory()
        history.remember("   ")
        XCTAssertTrue(history.entries.isEmpty)
        history.remember("одно и то же")
        history.remember("одно и то же")
        XCTAssertEqual(history.entries, ["одно и то же"])
    }

    func testHistoryIsBounded() {
        var history = InputHistory()
        for index in 0..<(InputHistory.limit + 20) { history.remember("строка \(index)") }
        XCTAssertEqual(history.entries.count, InputHistory.limit)
        XCTAssertEqual(history.entries.last, "строка \(InputHistory.limit + 19)")
        XCTAssertEqual(history.entries.first, "строка 20")
    }

    func testEmptyHistoryReturnsNil() {
        var history = InputHistory()
        XCTAssertNil(history.older())
        XCTAssertNil(history.newer())
    }
}
