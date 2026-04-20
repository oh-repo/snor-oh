import XCTest
@testable import SnorOhSwift

/// Phase 6 — tests for the ⌃⌥N bucket-switcher hotkey's pure resolver.
///
/// The Carbon event plumbing (`HotkeyRegistrar.registerBucketSwitchers`)
/// requires real keystrokes to exercise and is explicitly out of scope — the
/// untested surface is ~10 lines of glue. These tests cover the resolver
/// logic (`BucketManager.resolveBucketSwitcherTarget`) plus the integration
/// point of that resolver with `setActiveBucket(id:)`, which is what the
/// AppDelegate wire-up does at runtime.
@MainActor
final class BucketSwitcherTests: XCTestCase {

    var tempRoot: URL!
    var manager: BucketManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-switcher-test-\(UUID().uuidString)")
        let store = BucketStore(rootURL: tempRoot)
        manager = BucketManager(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Resolver

    func testBucketSwitcherIndexResolvesToCorrectBucket() {
        // Seed: Default (auto), Acme, Globex. ⌃⌥2 should resolve to Acme.
        let acmeID = manager.createBucket(name: "Acme")
        _ = manager.createBucket(name: "Globex")

        let visible = manager.activeBuckets
        XCTAssertEqual(visible.count, 3)

        let target = BucketManager.resolveBucketSwitcherTarget(n: 2, activeBuckets: visible)
        XCTAssertEqual(target, acmeID)

        // Drive through the same path AppDelegate uses at runtime.
        if let target { manager.setActiveBucket(id: target) }
        XCTAssertEqual(manager.activeBucketID, acmeID)
    }

    func testBucketSwitcherIgnoresArchivedBuckets() {
        // Seed: Default, Work, Refs, Old (archived).
        let workID = manager.createBucket(name: "Work")
        let refsID = manager.createBucket(name: "Refs")
        let oldID = manager.createBucket(name: "Old")

        // Archive Old. Can't archive if it's the active bucket, so switch first.
        manager.setActiveBucket(id: workID)
        manager.archiveBucket(id: oldID)

        let visible = manager.activeBuckets
        XCTAssertEqual(visible.count, 3, "archived Old must drop out of the visible list")

        // ⌃⌥3 targets the THIRD visible bucket — Refs — not Old.
        let target = BucketManager.resolveBucketSwitcherTarget(n: 3, activeBuckets: visible)
        XCTAssertEqual(target, refsID)
        XCTAssertNotEqual(target, oldID)

        if let target { manager.setActiveBucket(id: target) }
        XCTAssertEqual(manager.activeBucketID, refsID)
    }

    func testBucketSwitcherOutOfRangeIsNoOp() {
        _ = manager.createBucket(name: "Acme") // 2 active buckets total
        let originalActive = manager.activeBucketID

        let visible = manager.activeBuckets
        XCTAssertEqual(visible.count, 2)

        // ⌃⌥9 — out of range. Resolver returns nil; no switch happens.
        let target = BucketManager.resolveBucketSwitcherTarget(n: 9, activeBuckets: visible)
        XCTAssertNil(target)

        if let target { manager.setActiveBucket(id: target) }
        XCTAssertEqual(manager.activeBucketID, originalActive,
                       "out-of-range N must not mutate active bucket")
    }

    func testBucketSwitcherN1IsFirstBucket() {
        _ = manager.createBucket(name: "Acme")
        let firstID = manager.activeBuckets[0].id

        let target = BucketManager.resolveBucketSwitcherTarget(n: 1, activeBuckets: manager.activeBuckets)
        XCTAssertEqual(target, firstID)
    }

    func testBucketSwitcherZeroAndNegativeAreNoOp() {
        _ = manager.createBucket(name: "Acme")
        let visible = manager.activeBuckets

        XCTAssertNil(BucketManager.resolveBucketSwitcherTarget(n: 0, activeBuckets: visible))
        XCTAssertNil(BucketManager.resolveBucketSwitcherTarget(n: -1, activeBuckets: visible))
    }
}
