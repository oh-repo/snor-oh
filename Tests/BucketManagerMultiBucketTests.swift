import XCTest
@testable import SnorOhSwift

@MainActor
final class BucketManagerMultiBucketTests: XCTestCase {

    var tempRoot: URL!
    var manager: BucketManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-multi-test-\(UUID().uuidString)")
        let store = BucketStore(rootURL: tempRoot)
        manager = BucketManager(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // Helper: synchronously wait until a condition is true (bounded), to
    // observe effects that complete via background `Task`s (sidecar I/O).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Initial state

    func testManagerStartsWithOneDefaultActiveBucket() {
        XCTAssertEqual(manager.buckets.count, 1)
        XCTAssertEqual(manager.activeBuckets.count, 1)
        XCTAssertTrue(manager.archivedBuckets.isEmpty)
        XCTAssertEqual(manager.activeBucket.name, "Default")
        XCTAssertEqual(manager.activeBucketID, manager.buckets[0].id)
        XCTAssertEqual(manager.activeBucket.keyboardIndex, 1)
    }

    // MARK: - createBucket

    func testCreateBucketAppendsAndAssignsPaletteAndKey() {
        let workID = manager.createBucket(name: "Work")
        let refsID = manager.createBucket(name: "Refs")

        XCTAssertEqual(manager.buckets.count, 3)
        XCTAssertEqual(manager.activeBuckets.count, 3)

        let work = manager.buckets.first { $0.id == workID }!
        let refs = manager.buckets.first { $0.id == refsID }!
        XCTAssertEqual(work.keyboardIndex, 2)
        XCTAssertEqual(refs.keyboardIndex, 3)
        XCTAssertNotEqual(work.colorHex, manager.buckets[0].colorHex,
                          "auto-assigned color should differ from Default")
        XCTAssertNotEqual(work.colorHex, refs.colorHex,
                          "consecutive buckets should take different palette slots")
    }

    func testCreateBucketFiresBucketCreatedNotification() {
        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            let info = note.userInfo ?? [:]
            return info["change"] as? String == "bucket-created"
                && info["bucketID"] is UUID
        }
        _ = manager.createBucket(name: "New")
        wait(for: [exp], timeout: 0.2)
    }

    func testCreateBucketTrimsAndDefaultsEmptyName() {
        let id = manager.createBucket(name: "   ")
        XCTAssertEqual(manager.buckets.first { $0.id == id }?.name, "Untitled")
    }

    // MARK: - rename / setColor / setEmoji

    func testRenameBucketUpdatesNameAndPostsUpdated() {
        let id = manager.createBucket(name: "Old")

        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            return note.userInfo?["change"] as? String == "bucket-updated"
                && note.userInfo?["bucketID"] as? UUID == id
        }
        manager.renameBucket(id: id, to: "New")
        wait(for: [exp], timeout: 0.2)

        XCTAssertEqual(manager.buckets.first { $0.id == id }?.name, "New")
    }

    func testRenameBucketIgnoresEmptyName() {
        let id = manager.createBucket(name: "Stay")
        manager.renameBucket(id: id, to: "   ")
        XCTAssertEqual(manager.buckets.first { $0.id == id }?.name, "Stay")
    }

    func testSetColorUpdates() {
        let id = manager.createBucket(name: "C")
        manager.setColor(id: id, colorHex: "#007AFF")
        XCTAssertEqual(manager.buckets.first { $0.id == id }?.colorHex, "#007AFF")
    }

    func testSetEmojiStoresNonEmptyAndClearsEmpty() {
        let id = manager.createBucket(name: "E")
        manager.setEmoji(id: id, emoji: "📎")
        XCTAssertEqual(manager.buckets.first { $0.id == id }?.emoji, "📎")
        manager.setEmoji(id: id, emoji: "")
        XCTAssertNil(manager.buckets.first { $0.id == id }?.emoji)
    }

    // MARK: - archive / restore

    func testArchiveRefusesToArchiveActiveBucket() {
        let otherID = manager.createBucket(name: "Other")
        manager.setActiveBucket(id: otherID)
        manager.archiveBucket(id: otherID)

        XCTAssertFalse(manager.buckets.first { $0.id == otherID }?.archived ?? true,
                       "archive should refuse while target is active; caller must switch first")
        XCTAssertEqual(manager.activeBucketID, otherID)
    }

    func testArchiveMovesInactiveBucketOutOfActiveList() {
        let otherID = manager.createBucket(name: "Other")
        // activeBucketID is still the seed Default — archive "Other" which is inactive.
        manager.archiveBucket(id: otherID)

        XCTAssertFalse(manager.activeBuckets.contains { $0.id == otherID })
        XCTAssertTrue(manager.archivedBuckets.contains { $0.id == otherID })
        XCTAssertNil(manager.buckets.first { $0.id == otherID }?.keyboardIndex)
    }

    func testArchiveRefusesToArchiveLastActiveBucket() {
        // Only one active bucket exists; it's also active — guard stops it.
        let only = manager.activeBucket.id
        manager.archiveBucket(id: only)
        XCTAssertEqual(manager.activeBuckets.count, 1)
        XCTAssertFalse(manager.buckets[0].archived)
    }

    func testRestoreMakesBucketActiveListAgainAndReassignsKey() {
        let otherID = manager.createBucket(name: "Other")
        manager.archiveBucket(id: otherID)
        XCTAssertNil(manager.buckets.first { $0.id == otherID }?.keyboardIndex)

        manager.restoreBucket(id: otherID)
        let restored = manager.buckets.first { $0.id == otherID }
        XCTAssertFalse(restored?.archived ?? true)
        XCTAssertNotNil(restored?.keyboardIndex)
    }

    // MARK: - delete

    func testDeleteWithoutMergeRefusesIfActive() {
        let otherID = manager.createBucket(name: "Other")
        manager.setActiveBucket(id: otherID)

        manager.deleteBucket(id: otherID)
        XCTAssertTrue(manager.buckets.contains { $0.id == otherID },
                      "hard delete of active bucket must be refused; caller must switch first")
    }

    func testDeleteWithoutMergeRemovesBucketAndItems() {
        let otherID = manager.createBucket(name: "Other")
        manager.add(BucketItem(kind: .text, text: "doomed"), source: .panel, toBucket: otherID)

        manager.deleteBucket(id: otherID)
        XCTAssertFalse(manager.buckets.contains { $0.id == otherID })
    }

    func testDeleteWithoutMergeRemovesBucketSidecarDirectory() async throws {
        // Drop a file into a non-active bucket, then hard-delete. Its sidecar
        // directory at `<id>/files/...` must be removed.
        let otherID = manager.createBucket(name: "Other")
        let src = tempRoot.appendingPathComponent("doomed.txt")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "x".data(using: .utf8)!.write(to: src)

        // Route files into Other so the sidecar lands there (replacing the
        // old "setActive → add" trick that relied on the deprecated active-as-
        // fallback semantic).
        var s = manager.settings
        s.autoRouteRules = [AutoRouteRule(bucketID: otherID, condition: .itemKind(.file))]
        manager.updateSettings(s)

        await manager.add(fileAt: src, source: .panel)

        let bucketDir = tempRoot.appendingPathComponent(otherID.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bucketDir.path))

        manager.deleteBucket(id: otherID)
        await waitUntil {
            !FileManager.default.fileExists(atPath: bucketDir.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: bucketDir.path))
    }

    func testDeleteWithMergeFoldsItemsAndMovesSidecarFile() async throws {
        let targetID = manager.activeBucketID
        let donorID = manager.createBucket(name: "Donor")

        let src = tempRoot.appendingPathComponent("donated.txt")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "bytes".data(using: .utf8)!.write(to: src)

        // Route files into Donor (no more active-as-fallback shortcut).
        var s = manager.settings
        s.autoRouteRules = [AutoRouteRule(bucketID: donorID, condition: .itemKind(.file))]
        manager.updateSettings(s)

        await manager.add(fileAt: src, source: .panel)
        let movedItem = manager.buckets.first { $0.id == donorID }?.items.first
        XCTAssertNotNil(movedItem)
        let oldCachedPath = movedItem?.fileRef?.cachedPath ?? ""
        XCTAssertTrue(oldCachedPath.hasPrefix("\(donorID.uuidString)/"))

        manager.setActiveBucket(id: targetID)
        manager.deleteBucket(id: donorID, mergeInto: targetID)

        XCTAssertFalse(manager.buckets.contains { $0.id == donorID })
        let merged = manager.buckets.first { $0.id == targetID }?.items
            .first { $0.id == movedItem?.id }
        XCTAssertNotNil(merged)
        XCTAssertTrue(merged?.fileRef?.cachedPath?.hasPrefix("\(targetID.uuidString)/") ?? false,
                      "merged item's cachedPath must be rewritten into the destination bucket prefix")

        let donorDir = tempRoot.appendingPathComponent(donorID.uuidString)
        await waitUntil {
            !FileManager.default.fileExists(atPath: donorDir.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: donorDir.path),
                       "donor's sidecar dir must be gone after merge")

        let newAbs = tempRoot.appendingPathComponent(merged?.fileRef?.cachedPath ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newAbs.path),
                      "merged sidecar file must exist at its new path")
    }

    func testDeleteMergeMigratesAutoRouteRulesToTarget() {
        let targetID = manager.activeBucketID
        let donorID = manager.createBucket(name: "Donor")
        var s = manager.settings
        s.autoRouteRules = [
            AutoRouteRule(bucketID: donorID, condition: .itemKind(.text)),
        ]
        manager.updateSettings(s)

        manager.deleteBucket(id: donorID, mergeInto: targetID)
        XCTAssertEqual(manager.settings.autoRouteRules.first?.bucketID, targetID)
    }

    func testDeleteWithoutMergeDropsAutoRouteRulesForDeletedBucket() {
        let donorID = manager.createBucket(name: "Donor")
        var s = manager.settings
        s.autoRouteRules = [
            AutoRouteRule(bucketID: donorID, condition: .itemKind(.text)),
        ]
        manager.updateSettings(s)

        manager.deleteBucket(id: donorID)
        XCTAssertTrue(manager.settings.autoRouteRules.isEmpty)
    }

    func testDeleteMergeRefusesIfMergeTargetArchived() {
        let donorID = manager.createBucket(name: "Donor")
        let shelfID = manager.createBucket(name: "Shelf")
        manager.archiveBucket(id: shelfID)

        manager.deleteBucket(id: donorID, mergeInto: shelfID)
        XCTAssertTrue(manager.buckets.contains { $0.id == donorID })
    }

    // MARK: - moveItem

    func testMoveItemRelocatesAndPostsBothBucketIDs() {
        let src = manager.activeBucketID
        let dstID = manager.createBucket(name: "Dest")
        let item = BucketItem(kind: .text, text: "mobile")
        manager.add(item, source: .panel)

        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            let info = note.userInfo ?? [:]
            return info["change"] as? String == "added"
                && info["itemID"] as? UUID == item.id
                && info["bucketID"] as? UUID == dstID
        }

        manager.moveItem(item.id, toBucket: dstID)
        wait(for: [exp], timeout: 0.2)

        XCTAssertFalse(manager.buckets.first { $0.id == src }?.items
            .contains { $0.id == item.id } ?? true)
        XCTAssertTrue(manager.buckets.first { $0.id == dstID }?.items
            .contains { $0.id == item.id } ?? false)
    }

    func testMoveItemMovesSidecarFileOnDisk() async throws {
        let dstID = manager.createBucket(name: "Dest")

        let src = tempRoot.appendingPathComponent("movable.txt")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "pay".data(using: .utf8)!.write(to: src)
        await manager.add(fileAt: src, source: .panel)

        let item = manager.activeBucket.items.first!
        let oldRel = item.fileRef?.cachedPath ?? ""
        let srcAbs = tempRoot.appendingPathComponent(oldRel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcAbs.path))

        manager.moveItem(item.id, toBucket: dstID)

        let moved = manager.buckets.first { $0.id == dstID }?.items
            .first { $0.id == item.id }
        let newRel = moved?.fileRef?.cachedPath ?? ""
        XCTAssertTrue(newRel.hasPrefix("\(dstID.uuidString)/"),
                      "cachedPath must be rewritten to destination bucket prefix")
        let newAbs = tempRoot.appendingPathComponent(newRel)

        await waitUntil {
            FileManager.default.fileExists(atPath: newAbs.path)
                && !FileManager.default.fileExists(atPath: srcAbs.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: newAbs.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: srcAbs.path))
    }

    // MARK: - setActiveBucket

    func testSetActiveBucketSwitchesAndPostsActiveChanged() {
        let otherID = manager.createBucket(name: "Other")

        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            return note.userInfo?["change"] as? String == "active-bucket-changed"
                && note.userInfo?["bucketID"] as? UUID == otherID
        }

        manager.setActiveBucket(id: otherID)
        wait(for: [exp], timeout: 0.2)
        XCTAssertEqual(manager.activeBucketID, otherID)
    }

    func testSetActiveBucketRefusesArchivedTarget() {
        let otherID = manager.createBucket(name: "Other")
        manager.archiveBucket(id: otherID)

        manager.setActiveBucket(id: otherID)
        XCTAssertNotEqual(manager.activeBucketID, otherID)
    }

    // MARK: - Sidecar path correctness (v2 nested layout)

    func testAddFileAtNestsSidecarUnderRoutedBucketID() async throws {
        // Route files to a non-seed bucket so we're sure the sidecar path
        // uses the *routed* UUID, not the default's.
        let workID = manager.createBucket(name: "Work")
        var s = manager.settings
        s.autoRouteRules = [AutoRouteRule(bucketID: workID, condition: .itemKind(.file))]
        manager.updateSettings(s)

        let src = tempRoot.appendingPathComponent("payload.txt")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "hi".data(using: .utf8)!.write(to: src)

        await manager.add(fileAt: src, source: .panel)

        let item = manager.buckets.first { $0.id == workID }?.items.first
        XCTAssertNotNil(item)
        let cached = try XCTUnwrap(item?.fileRef?.cachedPath)
        XCTAssertTrue(cached.hasPrefix("\(workID.uuidString)/files/"),
                      "new file sidecar must nest under <routedBucketID>/files/ — got \(cached)")

        let nested = tempRoot.appendingPathComponent(cached)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))

        // Flat v1 path must NOT exist (would indicate regression).
        let itemUUID = cached.split(separator: "/").last.map(String.init) ?? ""
        let flat = tempRoot.appendingPathComponent("files").appendingPathComponent(itemUUID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: flat.path),
                       "no flat rootURL/files/... file should exist — schema regression")
    }

    func testAddImageDataNestsSidecarUnderRoutedBucketID() async throws {
        let workID = manager.createBucket(name: "Work")
        var s = manager.settings
        s.autoRouteRules = [AutoRouteRule(bucketID: workID, condition: .itemKind(.image))]
        manager.updateSettings(s)

        // Minimal PNG header bytes — classifyFile isn't invoked on imageData path,
        // but we include a recognizable prefix so the file is clearly not empty.
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
        await manager.add(imageData: bytes, source: .clipboard)

        let item = manager.buckets.first { $0.id == workID }?.items.first
        let cached = try XCTUnwrap(item?.fileRef?.cachedPath)
        XCTAssertTrue(cached.hasPrefix("\(workID.uuidString)/images/"),
                      "new image sidecar must nest under <routedBucketID>/images/ — got \(cached)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(cached).path))

        // Flat v1 path must NOT exist.
        let itemUUID = cached.split(separator: "/").last.map(String.init) ?? ""
        let flat = tempRoot.appendingPathComponent("images").appendingPathComponent(itemUUID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: flat.path),
                       "no flat rootURL/images/... file should exist — schema regression")
    }

    // MARK: - routeIncomingItem

    /// With no auto-route rules, items must fall into the default bucket
    /// (first non-archived in tab order) — NOT whichever tab is currently active.
    func testRouteIncomingItemFallsBackToDefaultBucketNotActive() {
        let defaultID = manager.buckets[0].id
        let otherID = manager.createBucket(name: "Other")
        manager.setActiveBucket(id: otherID)

        let routed = manager.routeIncomingItem(kind: .text)
        XCTAssertEqual(routed, defaultID,
                       "no rules should route to the default (first) bucket, not the active tab")
    }

    func testAddLandsInDefaultBucketWhenNoRulesMatch() {
        let defaultID = manager.buckets[0].id
        let otherID = manager.createBucket(name: "Other")
        manager.setActiveBucket(id: otherID)

        let item = BucketItem(kind: .text, text: "routed")
        manager.add(item, source: .clipboard)

        XCTAssertTrue(manager.buckets.first { $0.id == defaultID }?.items
            .contains { $0.id == item.id } ?? false,
            "item should land in default bucket despite active being Other")
        XCTAssertFalse(manager.buckets.first { $0.id == otherID }?.items
            .contains { $0.id == item.id } ?? true,
            "item must NOT land in the active bucket when no rule matches")
    }

    /// A matching enabled rule still wins over the default fallback.
    func testAddFollowsMatchingRuleOverDefault() {
        let targetID = manager.createBucket(name: "Images")
        var s = manager.settings
        s.autoRouteRules = [
            AutoRouteRule(bucketID: targetID, condition: .itemKind(.image), enabled: true)
        ]
        manager.updateSettings(s)

        let item = BucketItem(kind: .image)
        manager.add(item, source: .clipboard)

        XCTAssertTrue(manager.buckets.first { $0.id == targetID }?.items
            .contains { $0.id == item.id } ?? false,
            "image item should route to the Images bucket via rule")
    }

    // MARK: - Per-bucket LRU

    func testLRUEvictionIsScopedPerBucket() {
        var s = manager.settings
        s.maxItems = 2
        manager.updateSettings(s)

        let aID = manager.activeBucketID
        let bID = manager.createBucket(name: "B")

        // Fill A to cap (2 items).
        manager.add(BucketItem(kind: .text, text: "a1"), source: .panel, toBucket: aID)
        manager.add(BucketItem(kind: .text, text: "a2"), source: .panel, toBucket: aID)
        XCTAssertEqual(manager.buckets.first { $0.id == aID }?.items.count, 2)

        // Adding to B must not evict from A.
        manager.add(BucketItem(kind: .text, text: "b1"), source: .panel, toBucket: bID)
        manager.add(BucketItem(kind: .text, text: "b2"), source: .panel, toBucket: bID)
        manager.add(BucketItem(kind: .text, text: "b3"), source: .panel, toBucket: bID)

        XCTAssertEqual(manager.buckets.first { $0.id == aID }?.items.count, 2,
                       "A's items must not be evicted by B's growth")
        XCTAssertEqual(manager.buckets.first { $0.id == bID }?.items.count, 2)
    }

    // MARK: - bucketChanged carries bucketID

    func testAddNotificationIncludesBucketID() {
        let item = BucketItem(kind: .text, text: "hello")
        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            return note.userInfo?["bucketID"] as? UUID == self.manager.activeBucketID
                && note.userInfo?["change"] as? String == "added"
        }
        manager.add(item, source: .panel)
        wait(for: [exp], timeout: 0.2)
    }

    // MARK: - Persistence

    func testMultiBucketStatePersistsAcrossReload() async throws {
        let secondID = manager.createBucket(name: "Second")
        manager.setActiveBucket(id: secondID)
        // Explicit toBucket: — routing now goes to default, not active.
        manager.add(BucketItem(kind: .text, text: "in-second"), source: .panel, toBucket: secondID)
        await manager.flushPendingWrites()

        let fresh = BucketManager(store: BucketStore(rootURL: tempRoot))
        fresh.load()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(fresh.buckets.count, 2)
        XCTAssertEqual(fresh.activeBucketID, secondID)
        XCTAssertTrue(fresh.buckets.first { $0.id == secondID }?.items
            .contains { $0.text == "in-second" } ?? false)
    }

    func testRenameColorEmojiRoundTripThroughFlushAndReload() async throws {
        let id = manager.createBucket(name: "First")
        manager.renameBucket(id: id, to: "Renamed")
        manager.setColor(id: id, colorHex: "#34C759")
        manager.setEmoji(id: id, emoji: "🎯")
        await manager.flushPendingWrites()

        let fresh = BucketManager(store: BucketStore(rootURL: tempRoot))
        fresh.load()
        try await Task.sleep(nanoseconds: 150_000_000)
        let reloaded = fresh.buckets.first { $0.id == id }
        XCTAssertEqual(reloaded?.name, "Renamed")
        XCTAssertEqual(reloaded?.colorHex, "#34C759")
        XCTAssertEqual(reloaded?.emoji, "🎯")
    }

    // MARK: - Cross-bucket dedupe is independent

    func testDuplicateAcrossBucketsIsNotDeduped() {
        let defaultID = manager.buckets[0].id
        let otherID = manager.createBucket(name: "Other")
        manager.add(BucketItem(kind: .text, text: "same"), source: .panel, toBucket: defaultID)
        manager.add(BucketItem(kind: .text, text: "same"), source: .panel, toBucket: otherID)

        XCTAssertEqual(manager.buckets[0].items.count, 1)
        XCTAssertEqual(manager.buckets.first { $0.id == otherID }?.items.count, 1,
                       "dedupe must be scoped per bucket — same text in another bucket is fine")
    }
}
