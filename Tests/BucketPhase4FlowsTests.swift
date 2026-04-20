import XCTest
@testable import SnorOhSwift

/// Behavioral tests for the flows Phase 4's UI exposes: create-with-color-and-emoji,
/// edit-in-place rename+color+emoji, archive pre-switch, and delete confirmation
/// flows (merge and hard). The views themselves (popovers, sheets, grids) are
/// thin SwiftUI over these manager APIs.
@MainActor
final class BucketPhase4FlowsTests: XCTestCase {

    var tempRoot: URL!
    var manager: BucketManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-p4-test-\(UUID().uuidString)")
        manager = BucketManager(store: BucketStore(rootURL: tempRoot))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Create sheet behaviour

    func testCreateWithExplicitColorAndEmojiRetainsBoth() {
        let id = manager.createBucket(name: "Design", colorHex: "#AF52DE", emoji: "🎨")
        let b = manager.buckets.first { $0.id == id }
        XCTAssertEqual(b?.name, "Design")
        XCTAssertEqual(b?.colorHex, "#AF52DE")
        XCTAssertEqual(b?.emoji, "🎨")
    }

    /// Reviewer-specified scenario: user types the same name twice in the
    /// create popover. Second create silently suffixes " 2" rather than
    /// rejecting the submit — preserves one-tap ergonomics.
    func testUserProvidedCollidingNameSilentlySuffixes() {
        let first = manager.createBucket(name: "Acme")
        let second = manager.createBucket(name: "Acme")
        XCTAssertEqual(manager.buckets.first { $0.id == first }?.name, "Acme")
        XCTAssertEqual(manager.buckets.first { $0.id == second }?.name, "Acme 2")
    }

    // MARK: - Edit-in-place (what the in-place rename TextField does)

    func testEditSavesRenameColorAndEmojiInOneCommit() {
        let id = manager.createBucket(name: "Old", colorHex: "#FF9500")

        manager.renameBucket(id: id, to: "New")
        manager.setColor(id: id, colorHex: "#007AFF")
        manager.setEmoji(id: id, emoji: "📎")

        let b = manager.buckets.first { $0.id == id }
        XCTAssertEqual(b?.name, "New")
        XCTAssertEqual(b?.colorHex, "#007AFF")
        XCTAssertEqual(b?.emoji, "📎")
    }

    func testEditClearEmojiNilsIt() {
        let id = manager.createBucket(name: "With", emoji: "📎")
        manager.setEmoji(id: id, emoji: nil)
        XCTAssertNil(manager.buckets.first { $0.id == id }?.emoji)
    }

    // MARK: - Archive flow (what the context menu does: pre-switch + archive)

    func testArchiveFlowPreswitchesThenArchivesActiveBucket() {
        // User starts on Default; creates Work; activates Work; then archives Work.
        // Pill's Archive action pre-switches focus, then archives — which tabs do.
        let workID = manager.createBucket(name: "Work")
        manager.setActiveBucket(id: workID)

        // Simulate the context-menu Archive behaviour:
        if let fallback = manager.activeBuckets.first(where: { $0.id != workID })?.id {
            manager.setActiveBucket(id: fallback)
        }
        manager.archiveBucket(id: workID)

        XCTAssertTrue(manager.archivedBuckets.contains { $0.id == workID })
        XCTAssertNotEqual(manager.activeBucketID, workID)
    }

    // MARK: - Delete flows (what BucketDeleteConfirm invokes)

    func testDeleteMergeMovesItemsAndSwitchesActiveWhenNeeded() {
        let targetID = manager.activeBucketID
        let donorID = manager.createBucket(name: "Donor")
        manager.setActiveBucket(id: donorID)
        manager.add(BucketItem(kind: .text, text: "moved"), source: .panel)

        // User is looking at Donor when they pick Delete → Merge into target.
        manager.deleteBucket(id: donorID, mergeInto: targetID)

        XCTAssertFalse(manager.buckets.contains { $0.id == donorID })
        XCTAssertTrue(manager.buckets.first { $0.id == targetID }?.items
            .contains { $0.text == "moved" } ?? false)
        XCTAssertEqual(manager.activeBucketID, targetID,
                       "merge of the active bucket must move focus to the merge destination")
    }

    func testDeleteHardRemovesBucketEvenFromArchivedView() {
        let otherID = manager.createBucket(name: "Shelf")
        manager.archiveBucket(id: otherID)
        manager.deleteBucket(id: otherID)

        XCTAssertFalse(manager.buckets.contains { $0.id == otherID })
        XCTAssertTrue(manager.archivedBuckets.isEmpty)
    }

    func testDeleteHardRefusesIfBucketIsActive() {
        // This is the precondition BucketDeleteConfirm.performHardDelete pre-switches
        // around. Verify the manager guard still holds without that pre-switch.
        let otherID = manager.createBucket(name: "Other")
        manager.setActiveBucket(id: otherID)

        manager.deleteBucket(id: otherID, mergeInto: nil)
        XCTAssertTrue(manager.buckets.contains { $0.id == otherID },
                      "guard must still refuse hard-delete of active bucket")
    }

    // MARK: - Move-to item flow (what BucketCardView "Move to" submenu does)

    func testMoveItemSubmenuRelocatesItemToTarget() {
        let destID = manager.createBucket(name: "Dest")
        manager.add(BucketItem(kind: .text, text: "mobile"), source: .panel)
        let itemID = manager.activeBucket.items[0].id

        manager.moveItem(itemID, toBucket: destID)

        XCTAssertFalse(manager.activeBucket.items.contains { $0.id == itemID })
        XCTAssertTrue(manager.buckets.first { $0.id == destID }?.items
            .contains { $0.id == itemID } ?? false)
    }
}
