import XCTest
import SwiftUI
@testable import SnorOhSwift

final class ColorHexTests: XCTestCase {

    func testParsesSixDigitHexWithHash() throws {
        let c = try XCTUnwrap(Color(hex: "#FF9500"))
        assertRGBA(c, r: 1.0, g: 0.5843, b: 0.0, a: 1.0)
    }

    func testParsesSixDigitHexWithoutHash() throws {
        let c = try XCTUnwrap(Color(hex: "007AFF"))
        assertRGBA(c, r: 0.0, g: 0.4784, b: 1.0, a: 1.0)
    }

    func testParsesEightDigitHexWithAlpha() throws {
        let c = try XCTUnwrap(Color(hex: "#80FFFFFF"))
        assertRGBA(c, r: 1.0, g: 1.0, b: 1.0, a: 0.5019)
    }

    func testTrimsWhitespace() throws {
        let c = try XCTUnwrap(Color(hex: "  #34C759  "))
        assertRGBA(c, r: 0.2039, g: 0.7803, b: 0.3490, a: 1.0)
    }

    // MARK: - Failure cases (must return nil, not trap)

    func testReturnsNilForInvalidCharacters() {
        XCTAssertNil(Color(hex: "#ZZZZZZ"))
    }

    func testReturnsNilForWrongLength() {
        XCTAssertNil(Color(hex: "#ABC"))
        XCTAssertNil(Color(hex: "#ABCDE"))
        XCTAssertNil(Color(hex: "#ABCDEFGHI"))
    }

    func testReturnsNilForEmptyString() {
        XCTAssertNil(Color(hex: ""))
        XCTAssertNil(Color(hex: "#"))
    }

    // MARK: - Palette round-trip

    func testEveryPaletteSwatchParses() {
        for hex in BucketPalette.swatches {
            XCTAssertNotNil(Color(hex: hex), "palette swatch \(hex) must parse")
        }
    }

    // MARK: - Helpers

    private func assertRGBA(
        _ color: Color,
        r: Double, g: Double, b: Double, a: Double,
        tolerance: Double = 0.005,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        XCTAssertEqual(Double(ns.redComponent), r, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(Double(ns.greenComponent), g, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(Double(ns.blueComponent), b, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(Double(ns.alphaComponent), a, accuracy: tolerance, file: file, line: line)
    }
}
