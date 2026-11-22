import XCTest
@testable import SinMinionsCore

final class ShellTextTests: XCTestCase {
    func testPrompt() {
        XCTAssertEqual(ShellText.prompt(user: "me", host: "mac", cwd: "/Users/me/Projects", home: "/Users/me"), "me@mac ~/Projects %")
        XCTAssertEqual(ShellText.abbreviate("/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(ShellText.abbreviate("/Users/meow", home: "/Users/me"), "/Users/meow")
    }

    func testCdArgument() {
        XCTAssertEqual(ShellText.cdArgument("cd"), "")
        XCTAssertEqual(ShellText.cdArgument("cd ~/Desktop"), "~/Desktop")
        XCTAssertEqual(ShellText.cdArgument("cd \"My Files\""), "My Files")
        XCTAssertEqual(ShellText.cdArgument("cd My\\ Files"), "My Files")
        XCTAssertNil(ShellText.cdArgument("cd x && ls"))
        XCTAssertNil(ShellText.cdArgument("cdx"))
        XCTAssertNil(ShellText.cdArgument("ls"))
    }

    func testResolve() {
        let home = "/Users/me"
        XCTAssertEqual(ShellText.resolve("", cwd: "/tmp", home: home, previous: nil), home)
        XCTAssertEqual(ShellText.resolve("..", cwd: "/Users/me/a", home: home, previous: nil), "/Users/me")
        XCTAssertEqual(ShellText.resolve("b/./c", cwd: "/x", home: home, previous: nil), "/x/b/c")
        XCTAssertEqual(ShellText.resolve("~/Docs", cwd: "/x", home: home, previous: nil), "/Users/me/Docs")
        XCTAssertEqual(ShellText.resolve("-", cwd: "/x", home: home, previous: "/y"), "/y")
        XCTAssertEqual(ShellText.resolve("../../..", cwd: "/a", home: home, previous: nil), "/")
    }

    func testStripANSI() {
        XCTAssertEqual(ShellText.stripANSI("\u{1B}[1;32mok\u{1B}[0m\r"), "ok")
        XCTAssertEqual(ShellText.stripANSI("\u{1B}]0;title\u{07}text"), "text")
        XCTAssertEqual(ShellText.stripANSI("ab\u{08}c"), "ac")
    }
}
