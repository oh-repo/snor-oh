import XCTest
@testable import SnorOhSwift

/// Coverage for the Phase 5 auto-route engine: the pure `evaluateCondition`
/// matcher, the `routeIncomingItem` resolution pipeline (disabled / missing /
/// archived fallbacks), and round-trip persistence of `AutoRouteRule`.
@MainActor
final class AutoRouteTests: XCTestCase {

    var tempRoot: URL!
    var manager: BucketManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bucket-autoroute-test-\(UUID().uuidString)")
        let store = BucketStore(rootURL: tempRoot)
        manager = BucketManager(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - evaluateCondition (pure helper)

    func testEvaluateCondition_frontmostApp_matchesOnlyWhenBundleIDEqual() {
        let vscode = "com.microsoft.VSCode"
        let matches = BucketManager.evaluateCondition(
            .frontmostApp(bundleID: vscode),
            itemKind: .text,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: vscode
        )
        XCTAssertTrue(matches)

        let mismatch = BucketManager.evaluateCondition(
            .frontmostApp(bundleID: vscode),
            itemKind: .text,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: "com.apple.Safari"
        )
        XCTAssertFalse(mismatch)

        let noFrontmost = BucketManager.evaluateCondition(
            .frontmostApp(bundleID: vscode),
            itemKind: .text,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: nil
        )
        XCTAssertFalse(noFrontmost)
    }

    func testEvaluateCondition_itemKind() {
        XCTAssertTrue(BucketManager.evaluateCondition(
            .itemKind(.image),
            itemKind: .image,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: nil
        ))
        XCTAssertFalse(BucketManager.evaluateCondition(
            .itemKind(.image),
            itemKind: .url,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: nil
        ))
    }

    func testEvaluateCondition_sourceApp() {
        let safari = "com.apple.Safari"
        XCTAssertTrue(BucketManager.evaluateCondition(
            .sourceApp(bundleID: safari),
            itemKind: .url,
            sourceBundleID: safari,
            urlHost: nil,
            frontmostBundleID: nil
        ))
        XCTAssertFalse(BucketManager.evaluateCondition(
            .sourceApp(bundleID: safari),
            itemKind: .url,
            sourceBundleID: "com.google.Chrome",
            urlHost: nil,
            frontmostBundleID: nil
        ))
    }

    func testEvaluateCondition_urlHost_caseInsensitive() {
        XCTAssertTrue(BucketManager.evaluateCondition(
            .urlHost("GitHub.com"),
            itemKind: .url,
            sourceBundleID: nil,
            urlHost: "github.com",
            frontmostBundleID: nil
        ))
        XCTAssertTrue(BucketManager.evaluateCondition(
            .urlHost("github.com"),
            itemKind: .url,
            sourceBundleID: nil,
            urlHost: "GITHUB.COM",
            frontmostBundleID: nil
        ))
        XCTAssertFalse(BucketManager.evaluateCondition(
            .urlHost("github.com"),
            itemKind: .url,
            sourceBundleID: nil,
            urlHost: "gitlab.com",
            frontmostBundleID: nil
        ))
        XCTAssertFalse(BucketManager.evaluateCondition(
            .urlHost("github.com"),
            itemKind: .url,
            sourceBundleID: nil,
            urlHost: nil,
            frontmostBundleID: nil
        ))
    }

    // MARK: - routeIncomingItem (full engine)

    func testRouteIncomingItem_noRules_returnsActive() {
        XCTAssertTrue(manager.settings.autoRouteRules.isEmpty)
        let routed = manager.routeIncomingItem(kind: .text)
        XCTAssertEqual(routed, manager.activeBucketID)
    }

    func testRouteIncomingItem_matchesFirstEnabledRule() {
        let bucketA = manager.createBucket(name: "Images-A")
        let bucketB = manager.createBucket(name: "Images-B")

        let ruleA = AutoRouteRule(
            bucketID: bucketA,
            condition: .itemKind(.image),
            enabled: false
        )
        let ruleB = AutoRouteRule(
            bucketID: bucketB,
            condition: .itemKind(.image),
            enabled: true
        )
        manager.addAutoRouteRule(ruleA)
        manager.addAutoRouteRule(ruleB)

        let routed = manager.routeIncomingItem(kind: .image)
        XCTAssertEqual(routed, bucketB, "disabled rule must be skipped even if earlier in the list")
    }

    func testRouteIncomingItem_archivedTargetFallsBackToActive() {
        let toArchive = manager.createBucket(name: "Will Archive")
        let fallback = manager.createBucket(name: "Fallback")
        manager.setActiveBucket(id: fallback)
        manager.archiveBucket(id: toArchive)
        XCTAssertTrue(manager.buckets.first { $0.id == toArchive }?.archived ?? false)

        // Rule pointing at archived bucket — survives because the delete hook
        // only prunes on hard-delete, not archive.
        manager.addAutoRouteRule(
            AutoRouteRule(
                bucketID: toArchive,
                condition: .itemKind(.image),
                enabled: true
            )
        )

        let routed = manager.routeIncomingItem(kind: .image)
        XCTAssertEqual(routed, manager.activeBucketID,
                       "archived rule target must silently fall back to active bucket")
    }

    func testRouteIncomingItem_multipleMatches_firstWins() {
        let first = manager.createBucket(name: "First")
        let second = manager.createBucket(name: "Second")

        manager.addAutoRouteRule(
            AutoRouteRule(bucketID: first, condition: .itemKind(.url), enabled: true)
        )
        manager.addAutoRouteRule(
            AutoRouteRule(bucketID: second, condition: .itemKind(.url), enabled: true)
        )

        XCTAssertEqual(manager.routeIncomingItem(kind: .url), first,
                       "earliest matching rule in the list must win")
    }

    #if DEBUG
    func testRouteIncomingItem_frontmostApp_usesInjectedBundleID() {
        let vscode = "com.microsoft.VSCode"
        let target = manager.createBucket(name: "Code Snippets")
        manager.addAutoRouteRule(
            AutoRouteRule(
                bucketID: target,
                condition: .frontmostApp(bundleID: vscode),
                enabled: true
            )
        )

        manager._setLastFrontmostBundleID(vscode)
        XCTAssertEqual(manager.routeIncomingItem(kind: .text), target)

        manager._setLastFrontmostBundleID("com.apple.Safari")
        XCTAssertEqual(manager.routeIncomingItem(kind: .text), manager.activeBucketID)
    }
    #endif

    // MARK: - Persistence

    func testAutoRouteRulePersists() async throws {
        let target = manager.createBucket(name: "Shots")
        let rule = AutoRouteRule(
            bucketID: target,
            condition: .urlHost("github.com"),
            enabled: true
        )
        manager.addAutoRouteRule(rule)
        await manager.flushPendingWrites()

        let fresh = BucketManager(store: BucketStore(rootURL: tempRoot))
        fresh.load()
        try await Task.sleep(nanoseconds: 150_000_000)

        let persisted = fresh.settings.autoRouteRules.first { $0.id == rule.id }
        XCTAssertNotNil(persisted, "rule must round-trip through disk")
        XCTAssertEqual(persisted?.bucketID, target)
        XCTAssertEqual(persisted?.enabled, true)
        if case let .urlHost(host) = persisted?.condition {
            XCTAssertEqual(host, "github.com")
        } else {
            XCTFail("condition did not round-trip as urlHost")
        }
    }
}
