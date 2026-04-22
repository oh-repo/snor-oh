// Tests/InstallCoordinatorTests.swift
import XCTest
@testable import SnorOhSwift

final class InstallCoordinatorTests: XCTestCase {
    func testValidURLExtractsID() {
        XCTAssertEqual(
            InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=abc-123_X&v=1")!),
            "abc-123_X"
        )
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "animime://install?id=abc")!))
    }

    func testRejectsWrongHost() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://run?id=abc")!))
    }

    func testRejectsEmptyID() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=")!))
    }

    func testRejectsMissingIDParam() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install")!))
    }

    func testRejectsBadCharacters() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=a/b")!))
    }

    func testRejectsOverlyLongID() {
        let longID = String(repeating: "a", count: 65)
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=\(longID)")!))
    }

    func testExtractIDRejectsUnicodeLetter() {
        // "café" contains é (U+00E9) — a Unicode letter but not ASCII; must be rejected
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=caf%C3%A9")!))
    }

    func testExtractIDRejectsCJKLetter() {
        // CJK characters are Unicode letters but not ASCII; must be rejected
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=%E4%B8%AD%E6%96%87")!))
    }
}
