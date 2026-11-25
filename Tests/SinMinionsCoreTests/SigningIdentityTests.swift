import XCTest
@testable import SinMinionsCore

/// Подпись обновления: список отпечатков — единственное, на чём держится доверие к архиву,
/// поэтому проверяем формат требования и поведение при смене сертификата.
final class SigningIdentityTests: XCTestCase {
    func testRequirementContainsEveryPinnedLeaf() {
        let requirement = SigningIdentity.requirement
        XCTAssertFalse(SigningIdentity.leafHashes.isEmpty)
        for hash in SigningIdentity.leafHashes {
            XCTAssertTrue(requirement.contains(#"certificate leaf = H"\#(hash)""#), "нет отпечатка \(hash) в \(requirement)")
        }
    }

    func testSingleLeafHasNoDisjunction() {
        XCTAssertFalse(SigningIdentity.requirement.contains(" or "))
    }

    func testAcceptsPinnedLeafRegardlessOfCase() throws {
        let leaf = try XCTUnwrap(SigningIdentity.leafHashes.first)
        XCTAssertTrue(SigningIdentity.accepts(leafHash: leaf))
        XCTAssertTrue(SigningIdentity.accepts(leafHash: leaf.lowercased()))
        XCTAssertFalse(SigningIdentity.accepts(leafHash: "0000000000000000000000000000000000000000"))
        XCTAssertFalse(SigningIdentity.accepts(leafHash: ""))
    }

    func testRequirementIsValidForCodesign() throws {
        // Требование проверяет сама система, поэтому оно должно разбираться её же парсером
        // (`csreq` — тот же компилятор требований, которым пользуется codesign).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csreq")
        process.arguments = ["-r=\(SigningIdentity.requirement)", "-t"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, errorText)
        XCTAssertTrue(text.lowercased().contains("certificate leaf"), text)
    }
}
