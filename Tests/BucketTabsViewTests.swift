import XCTest
import SwiftUI
@testable import SnorOhSwift

@MainActor
final class BucketTabsViewTests: XCTestCase {

    var tempRoot: URL!
    var manager: BucketManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-tabs-test-\(UUID().uuidString)")
        manager = BucketManager(store: BucketStore(rootURL: tempRoot))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Manager integration points

    func testSetActiveBucketUpdatesIDAndPostsNotification() {
        let other = manager.createBucket(name: "Other")

        let exp = expectation(forNotification: .bucketChanged, object: nil) { note in
            return note.userInfo?["change"] as? String == "active-bucket-changed"
                && note.userInfo?["bucketID"] as? UUID == other
        }
        manager.setActiveBucket(id: other)
        wait(for: [exp], timeout: 0.2)
        XCTAssertEqual(manager.activeBucketID, other)
    }

    // MARK: - Name uniqueness (Phase 3 spec: create from "New Bucket")

    func testCreateBucketAutoSuffixesCollidingDefaultName() {
        let a = manager.createBucket(name: "New Bucket")
        let b = manager.createBucket(name: "New Bucket")
        let c = manager.createBucket(name: "New Bucket")

        let names = [a, b, c].compactMap { id in manager.buckets.first { $0.id == id }?.name }
        XCTAssertEqual(names, ["New Bucket", "New Bucket 2", "New Bucket 3"])
    }

    func testUniqueBucketNameHelperHandlesGapsByPickingSmallestFreeSuffix() {
        _ = manager.createBucket(name: "Work")
        _ = manager.createBucket(name: "Work")       // "Work 2"
        _ = manager.createBucket(name: "Work")       // "Work 3"

        // Simulate the user renaming "Work 2" away to free that slot.
        if let middleID = manager.buckets.first(where: { $0.name == "Work 2" })?.id {
            manager.renameBucket(id: middleID, to: "Moved")
        }

        // Next create should reuse the gap at "Work 2".
        XCTAssertEqual(manager.uniqueBucketName(from: "Work"), "Work 2")
    }

    func testUniqueBucketNameForNovelBaseReturnsBaseUntouched() {
        _ = manager.createBucket(name: "Work")
        XCTAssertEqual(manager.uniqueBucketName(from: "Refs"), "Refs")
    }

    func testUniqueBucketNameTreatsArchivedBucketsAsTaken() {
        let shelved = manager.createBucket(name: "Shelf")
        manager.archiveBucket(id: shelved)
        // Archived buckets still occupy the name — otherwise restoring later
        // would silently collide.
        XCTAssertEqual(manager.uniqueBucketName(from: "Shelf"), "Shelf 2")
    }

    // MARK: - Create button placeholder behavior (what BucketWindow wires up)

    func testCreateBucketPlaceholderProducesUniqueNamesOnRepeatedTaps() {
        // Simulate tapping [+] three times — matches the closure in BucketWindow.
        for _ in 0..<3 {
            let id = manager.createBucket(name: "New Bucket")
            manager.setActiveBucket(id: id)
        }

        let names = manager.activeBuckets.map(\.name).sorted()
        XCTAssertTrue(names.contains("New Bucket"))
        XCTAssertTrue(names.contains("New Bucket 2"))
        XCTAssertTrue(names.contains("New Bucket 3"))
    }

    // MARK: - View construction (smoke — ensures init doesn't trap)

    func testBucketTabsViewConstructsWithoutCrashing() {
        let view = BucketTabsView(manager: manager) { /* no-op */ }
        // Render the body to ensure no preconditions fire in-view.
        _ = view.body
    }
}
