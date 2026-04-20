import XCTest
@testable import SnorOhSwift

final class OhhExporterTests: XCTestCase {

    // MARK: - File-shape decode (no disk)

    func testV1FileDecodes() throws {
        let json = """
        {
          "version": 1,
          "name": "Sample",
          "sprites": {
            "idle":         {"frames": 4, "data": "aGVsbG8="},
            "busy":         {"frames": 4, "data": "aGVsbG8="},
            "service":      {"frames": 4, "data": "aGVsbG8="},
            "searching":    {"frames": 4, "data": "aGVsbG8="},
            "initializing": {"frames": 4, "data": "aGVsbG8="},
            "disconnected": {"frames": 4, "data": "aGVsbG8="},
            "visiting":     {"frames": 4, "data": "aGVsbG8="}
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OhhExporter.SnorohFile.self, from: json)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.name, "Sample")
        XCTAssertEqual(decoded.sprites?.count, 7)
        XCTAssertNil(decoded.smartImportMeta,
                     "v1 file without smartImportMeta should leave the field nil")
    }

    func testV2FileDecodes() throws {
        // v2: no `sprites` key — only smartImportMeta with base64 sheet + frame inputs.
        let json = """
        {
          "version": 2,
          "name": "Kyuubi",
          "smartImportMeta": {
            "sourceSheet": "aGVsbG8=",
            "frameInputs": {
              "idle": "1-4",
              "busy": "5-12",
              "service": "1-4",
              "searching": "1",
              "initializing": "1",
              "disconnected": "1",
              "visiting": "1-2"
            }
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OhhExporter.SnorohFile.self, from: json)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.name, "Kyuubi")
        XCTAssertNil(decoded.sprites, "v2 must carry no per-status sprite payload")
        XCTAssertEqual(decoded.smartImportMeta?.frameInputs["idle"], "1-4")
        XCTAssertNotNil(decoded.smartImportMeta?.sourceSheet)
    }

    func testV2RejectsMissingName() throws {
        let json = """
        {
          "version": 2,
          "name": "",
          "smartImportMeta": {
            "sourceSheet": "aGVsbG8=",
            "frameInputs": {}
          }
        }
        """.data(using: .utf8)!

        // File decodes fine, but the importer guards on empty name and throws
        // `.invalidFormat` before dispatching to the v2 branch. We test the
        // decode layer + guard behavior via a malformed path to ensure the
        // guard isn't silently bypassed.
        let url = tempFile(json)
        XCTAssertThrowsError(try OhhExporter.importOhh(from: url)) { error in
            if case OhhExporter.ImportError.invalidFormat = error { return }
            XCTFail("expected .invalidFormat, got \(error)")
        }
    }

    func testUnsupportedVersionThrows() throws {
        let json = """
        {"version": 99, "name": "Future"}
        """.data(using: .utf8)!

        let url = tempFile(json)
        XCTAssertThrowsError(try OhhExporter.importOhh(from: url)) { error in
            if case OhhExporter.ImportError.unsupportedVersion(let v) = error {
                XCTAssertEqual(v, 99)
                return
            }
            XCTFail("expected .unsupportedVersion, got \(error)")
        }
    }

    func testV1InvalidWhenSpritesMissing() throws {
        // v1 file with no `sprites` payload — guard must fire in the v1 branch.
        let json = """
        {"version": 1, "name": "Broken"}
        """.data(using: .utf8)!
        let url = tempFile(json)
        XCTAssertThrowsError(try OhhExporter.importOhh(from: url)) { error in
            if case OhhExporter.ImportError.invalidFormat = error { return }
            XCTFail("expected .invalidFormat, got \(error)")
        }
    }

    func testV2InvalidWhenMetaMissing() throws {
        // v2 file with no smartImportMeta — guard must fire before dispatch
        // into the detection pipeline.
        let json = """
        {"version": 2, "name": "Broken"}
        """.data(using: .utf8)!
        let url = tempFile(json)
        XCTAssertThrowsError(try OhhExporter.importOhh(from: url)) { error in
            if case OhhExporter.ImportError.invalidFormat = error { return }
            XCTFail("expected .invalidFormat, got \(error)")
        }
    }

    // MARK: - Helpers

    private func tempFile(_ data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohh-exporter-test-\(UUID().uuidString).snoroh")
        try? data.write(to: url)
        return url
    }
}
