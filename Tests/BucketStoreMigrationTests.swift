import XCTest
@testable import SnorOhSwift

final class BucketStoreMigrationTests: XCTestCase {

    var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-mig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Scenario 1: empty state

    func testLoadManifestReturnsV2EnvelopeWhenNoManifest() async throws {
        let store = BucketStore(rootURL: tempRoot)
        let manifest = try await store.loadManifest()
        XCTAssertEqual(manifest.schemaVersion, BucketStore.currentSchemaVersion)
        XCTAssertEqual(manifest.buckets.count, 1)
        XCTAssertEqual(manifest.buckets[0].name, "Default")
        XCTAssertEqual(manifest.activeBucketID, manifest.buckets[0].id)

        let manifestFile = tempRoot.appendingPathComponent("manifest.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestFile.path),
                       "Empty-state load must not persist until caller calls saveManifest")
    }

    // MARK: - Scenario 2: populated v1 migrates to v2

    func testPopulatedV1MigratesAndPreservesItems() async throws {
        let stackID = UUID()
        let itemA = BucketItem(id: UUID(), kind: .text, pinned: true, text: "alpha")
        let itemB = BucketItem(
            id: UUID(),
            kind: .text,
            pinned: false,
            stackGroupID: stackID,
            text: "beta"
        )
        let itemC = BucketItem(
            id: UUID(),
            kind: .image,
            pinned: false,
            contentHash: "abcd1234",
            fileRef: .init(
                originalPath: "/tmp/img.png",
                cachedPath: "images/\(UUID().uuidString).png",
                byteSize: 10,
                uti: "public.png",
                displayName: "img.png"
            )
        )
        let v1 = Bucket(
            id: UUID(),
            name: "Legacy",
            items: [itemA, itemB, itemC],
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )

        try writeV1Manifest(v1)

        let store = BucketStore(rootURL: tempRoot)
        let manifest = try await store.loadManifest()

        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.buckets.count, 1)
        let bucket = manifest.buckets[0]
        XCTAssertEqual(bucket.id, v1.id)
        XCTAssertEqual(bucket.name, "Legacy")
        XCTAssertEqual(bucket.items.count, 3)
        XCTAssertEqual(bucket.items[0].id, itemA.id)
        XCTAssertTrue(bucket.items[0].pinned)
        XCTAssertEqual(bucket.items[1].stackGroupID, stackID)
        XCTAssertEqual(bucket.items[2].contentHash, "abcd1234")
        XCTAssertEqual(bucket.createdAt, v1.createdAt)
        XCTAssertEqual(bucket.colorHex, "#FF9500")
        XCTAssertFalse(bucket.archived)
        XCTAssertEqual(bucket.keyboardIndex, 1)

        let backup = store.backupURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        let diskBytes = try Data(contentsOf: tempRoot.appendingPathComponent("manifest.json"))
        let obj = try JSONSerialization.jsonObject(with: diskBytes) as? [String: Any]
        XCTAssertEqual(obj?["schemaVersion"] as? Int, 2)
    }

    // MARK: - Scenario 3: v2 already — no-op

    func testAlreadyV2LoadIsIdempotent() async throws {
        let bucket = Bucket(name: "Only", keyboardIndex: 1)
        let manifest = BucketManifestV2(
            schemaVersion: 2,
            activeBucketID: bucket.id,
            buckets: [bucket]
        )
        let store = BucketStore(rootURL: tempRoot)
        try await store.saveManifest(manifest)

        _ = try await store.loadManifest()

        let backup = store.backupURL()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path),
                       "v2 load must not create a v1 backup")

        let manifestFile = tempRoot.appendingPathComponent("manifest.json")
        let mtime1 = try FileManager.default.attributesOfItem(atPath: manifestFile.path)[.modificationDate] as? Date

        // Give FS clock room to advance if the second load did write.
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await store.loadManifest()

        let mtime2 = try FileManager.default.attributesOfItem(atPath: manifestFile.path)[.modificationDate] as? Date
        XCTAssertEqual(mtime1, mtime2, "Second v2 load must not rewrite manifest")
    }

    // MARK: - Scenario 4: forward-incompat

    func testForwardIncompatibleSchemaThrows() async throws {
        let forward: [String: Any] = [
            "schemaVersion": 99,
            "activeBucketID": UUID().uuidString,
            "buckets": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: forward)
        try data.write(to: tempRoot.appendingPathComponent("manifest.json"))

        let store = BucketStore(rootURL: tempRoot)
        do {
            _ = try await store.loadManifest()
            XCTFail("expected forward-incompat throw")
        } catch BucketStore.StoreError.forwardIncompatibleSchema(let v) {
            XCTAssertEqual(v, 99)
        }
    }

    // MARK: - Scenario 5: file path preservation

    func testFilePathsRewrittenAndResolveToNewNestedLocation() async throws {
        let itemID = UUID()
        let fileName = "\(itemID.uuidString).txt"
        let filesDir = tempRoot.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let fileURL = filesDir.appendingPathComponent(fileName)
        try "payload".data(using: .utf8)!.write(to: fileURL)

        let faviconItemID = UUID()
        let favName = "\(faviconItemID.uuidString).ico"
        let favDir = tempRoot.appendingPathComponent("favicons")
        try FileManager.default.createDirectory(at: favDir, withIntermediateDirectories: true)
        try Data([0x00, 0x01]).write(to: favDir.appendingPathComponent(favName))

        let ogName = "\(faviconItemID.uuidString).jpg"
        let ogDir = tempRoot.appendingPathComponent("og")
        try FileManager.default.createDirectory(at: ogDir, withIntermediateDirectories: true)
        try Data([0xFF, 0xD8]).write(to: ogDir.appendingPathComponent(ogName))

        let fileItem = BucketItem(
            id: itemID,
            kind: .file,
            fileRef: .init(
                originalPath: "/elsewhere/\(fileName)",
                cachedPath: "files/\(fileName)",
                byteSize: 7,
                uti: "public.plain-text",
                displayName: fileName
            )
        )
        let urlItem = BucketItem(
            id: faviconItemID,
            kind: .url,
            urlMeta: .init(
                urlString: "https://example.com",
                title: "Example",
                faviconPath: "favicons/\(favName)",
                ogImagePath: "og/\(ogName)"
            )
        )
        let v1 = Bucket(id: UUID(), name: "Legacy", items: [fileItem, urlItem])
        try writeV1Manifest(v1)

        let store = BucketStore(rootURL: tempRoot)
        let manifest = try await store.loadManifest()
        let bucket = manifest.buckets[0]

        let migratedFile = bucket.items.first { $0.id == itemID }!
        let cached = try XCTUnwrap(migratedFile.fileRef?.cachedPath)
        XCTAssertEqual(cached, "\(bucket.id.uuidString)/files/\(fileName)")
        let resolved = store.absoluteURL(forRelative: cached)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path),
                      "File must exist at migrated nested path: \(resolved.path)")
        XCTAssertEqual(try Data(contentsOf: resolved), "payload".data(using: .utf8))

        let migratedURL = bucket.items.first { $0.id == faviconItemID }!
        XCTAssertEqual(migratedURL.urlMeta?.faviconPath,
                       "\(bucket.id.uuidString)/favicons/\(favName)")
        XCTAssertEqual(migratedURL.urlMeta?.ogImagePath,
                       "\(bucket.id.uuidString)/og/\(ogName)")

        XCTAssertFalse(FileManager.default.fileExists(atPath: filesDir.path),
                       "Old root-level files/ should have been moved")
    }

    // MARK: - Scenario 6: partial-migration recovery

    func testPartialMigrationFailureLeavesV1Intact() async throws {
        let itemID = UUID()
        let fileName = "\(itemID.uuidString).txt"
        let filesDir = tempRoot.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try "src".data(using: .utf8)!.write(to: filesDir.appendingPathComponent(fileName))

        let fileItem = BucketItem(
            id: itemID,
            kind: .file,
            fileRef: .init(
                originalPath: "/src/\(fileName)",
                cachedPath: "files/\(fileName)",
                byteSize: 3,
                uti: "public.plain-text",
                displayName: fileName
            )
        )
        let bucketID = UUID()
        let v1 = Bucket(id: bucketID, name: "Legacy", items: [fileItem])
        try writeV1Manifest(v1)

        // Pre-create `<bucketID>` as a regular file, so `createDirectory` (and
        // hence the mv into it) fails. This simulates a corrupted prior state.
        let bucketDir = tempRoot.appendingPathComponent(bucketID.uuidString)
        try Data([0x00]).write(to: bucketDir)

        let store = BucketStore(rootURL: tempRoot)
        do {
            _ = try await store.loadManifest()
            XCTFail("expected migration to abort")
        } catch {
            // expected
        }

        // manifest.json should still decode as v1 (untouched).
        let raw = try Data(contentsOf: tempRoot.appendingPathComponent("manifest.json"))
        let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertNil(obj?["schemaVersion"],
                     "v1 manifest must remain untouched when migration aborts")
        let legacy = try JSONDecoder.iso8601.decode(Bucket.self, from: raw)
        XCTAssertEqual(legacy.id, bucketID)
        XCTAssertEqual(legacy.items.count, 1)
    }

    // MARK: - Helpers

    private func writeV1Manifest(_ bucket: Bucket) throws {
        // Serialize through a dictionary to strip any fields that v1 didn't
        // originally have. Also ensures no `schemaVersion` key is present.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(bucket)
        guard var obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw NSError(domain: "test", code: 1)
        }
        obj.removeValue(forKey: "schemaVersion")
        obj.removeValue(forKey: "colorHex")
        obj.removeValue(forKey: "emoji")
        obj.removeValue(forKey: "archived")
        obj.removeValue(forKey: "keyboardIndex")
        let stripped = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try stripped.write(to: tempRoot.appendingPathComponent("manifest.json"))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
