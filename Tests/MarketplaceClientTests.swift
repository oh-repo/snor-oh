import XCTest
@testable import SnorOhSwift

final class MarketplaceClientTests: XCTestCase {
    func testPreviewURLComposesFromBase() {
        let url = MarketplaceClient.previewURL(
            id: "abc", baseURL: "https://example.test"
        )
        XCTAssertEqual(url?.absoluteString,
                       "https://example.test/api/packages/abc/preview")
    }

    func testPreviewURLTolleratesTrailingSlash() {
        let url = MarketplaceClient.previewURL(
            id: "abc", baseURL: "https://example.test/"
        )
        XCTAssertEqual(url?.absoluteString,
                       "https://example.test/api/packages/abc/preview")
    }

    func testPreviewURLRejectsMalformedBase() {
        XCTAssertNil(MarketplaceClient.previewURL(id: "abc", baseURL: "::::"))
    }

    func testPackageMetaDecodesMinimal() throws {
        let json = #"""
        {"id":"abc","name":"Mochi","creator":"cat",
         "format":"snoroh","size_bytes":12345,
         "frame_counts":{"idle":4}}
        """#.data(using: .utf8)!
        let meta = try JSONDecoder().decode(
            MarketplaceClient.PackageMeta.self, from: json
        )
        XCTAssertEqual(meta.name, "Mochi")
        XCTAssertEqual(meta.creator, "cat")
        XCTAssertEqual(meta.format, "snoroh")
        XCTAssertEqual(meta.sizeBytes, 12345)
    }

    func testPackageMetaAllowsNullCreator() throws {
        let json = #"""
        {"id":"x","name":"y","creator":null,
         "format":"animime","size_bytes":0}
        """#.data(using: .utf8)!
        let meta = try JSONDecoder().decode(
            MarketplaceClient.PackageMeta.self, from: json
        )
        XCTAssertNil(meta.creator)
    }

    // MARK: - ID validation tests

    func testPreviewURLRejectsPathTraversalInID() {
        let url = MarketplaceClient.previewURL(
            id: "abc/../bad", baseURL: "https://x.test"
        )
        XCTAssertNil(url)
    }

    func testPreviewURLRejectsEmptyID() {
        let url = MarketplaceClient.previewURL(
            id: "", baseURL: "https://x.test"
        )
        XCTAssertNil(url)
    }

    func testPreviewURLRejectsOverlongID() {
        let longID = String(repeating: "a", count: 65)
        let url = MarketplaceClient.previewURL(
            id: longID, baseURL: "https://x.test"
        )
        XCTAssertNil(url)
    }

    func testFetchMetaThrowsOnInvalidID() async throws {
        do {
            _ = try await MarketplaceClient.fetchMeta(
                id: "abc/bad", baseURL: "https://x.test"
            )
            XCTFail("Expected UploadError.invalidURL to be thrown")
        } catch MarketplaceClient.UploadError.invalidURL {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPreviewURLRejectsUnicodeLetterID() {
        // "café" — é is a valid Unicode letter but not ASCII; must be rejected
        let url = MarketplaceClient.previewURL(
            id: "caf\u{00E9}", baseURL: "https://x.test"
        )
        XCTAssertNil(url)
    }
}
