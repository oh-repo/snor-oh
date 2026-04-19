# Epic 04 — Multi-Bucket System

**Tier**: 🟡 v1.5 differentiator · **Complexity**: M (2–3 weeks) · **Depends on**: Epic 01

## Problem Statement

Dropover's most-cited weakness across every comparison article is that it only exposes one shelf at a time. ExtraDock, Droppy, and every "Dropover alternative" blog post converges on the same answer: users need buckets *per project* or *per context* so a screenshot they're triaging for client A doesn't crash into the CSV they're reviewing for client B ([research §Should-Have](../../research/bucket-feature-research.md#-should-have-high-value--mentioned-in-23-apps-strong-reviews)). Single-bucket v1 ships the category; multi-bucket closes the gap against the competitive frontier.

## Hypothesis

> We believe **named per-context buckets** will unlock power-user retention. We'll know we're right when >25% of active users create ≥2 buckets within 30 days and >60% of drops go into a non-default bucket once the user has created one.

## Scope (MoSCoW)

| Priority | Capability | Why |
|---|---|---|
| Must | Create, rename, delete buckets | Primitive operations |
| Must | Switch active bucket via tab bar in panel | Keep current UX for single-bucket users |
| Must | Per-bucket color (from a preset palette) | Visual distinction at a glance |
| Must | Auto-migrate v1 single bucket into a "Default" bucket on first launch | Backwards compatibility |
| Must | "Send to bucket…" context menu on any item | Reorg across buckets |
| Should | Per-bucket icon/emoji (default: color dot) | Personality |
| Should | Keyboard shortcut `⌃⌥1–9` to jump to Nth bucket | Speed |
| Should | Archive a bucket (hide from main list, restore later) | Project lifecycle |
| Could | Auto-route rule: "items dropped while `<app>` is frontmost go into bucket X" | Light automation |
| Won't | Tagging items across buckets (different mental model, defer) | |
| Won't | Smart buckets (auto-populate from search query) | YAGNI |

## Users & JTBD

**Primary**: Power users who work on ≥2 concurrent projects. The subset of existing users who hit the 50-item speech bubble from Epic 02 is a strong signal.

**JTBD**: *When I'm context-switching between clients/projects, I want a separate staging area per context so items don't bleed across and I don't have to think about file hygiene.*

## User Stories

1. As a freelance dev, I have buckets named "Acme", "Globex", "Personal" — all visible as colored tabs on the panel.
2. I drop a screenshot while VSCode-with-Acme-repo is frontmost and it lands in "Acme" automatically (opt-in rule).
3. I finish a project, archive its bucket, and it disappears from my tabs — but I can restore it from Settings → Buckets → Archive.
4. I right-click an item in "Personal" and move it to "Acme" because I was wrong about where it belonged.

## UX Flow

```
Panel header now looks like:
┌──────────────────────────────────────────┐
│  🟠 Default  🔵 Acme  🟢 Globex  [+ New] │
├──────────────────────────────────────────┤
│                                          │
│   [ item cards for active bucket ]       │
│                                          │
└──────────────────────────────────────────┘

New bucket flow:
Click [+ New] → popover with name + color swatches → Enter → tab appears, active.

Send-to flow:
Right-click item → "Move to ▸" → list of buckets → click → item relocates,
                                                         panel animates to show
                                                         destination briefly.
```

## Acceptance Criteria

- [ ] `BucketManager.buckets: [Bucket]` replaces `activeBucket` with `activeBucketID: UUID`
- [ ] On migration, existing single bucket's items move into a new `Bucket(name: "Default", id: ...)`
- [ ] Create bucket: max 12 active (arbitrary guardrail, raise if users ask). Archive counts separately.
- [ ] Rename: in-place double-click on tab → editable text field → Enter commits
- [ ] Delete: confirmation modal warns about item count, offers "Merge into Default" as alternative
- [ ] Color palette: 8 fixed swatches matching macOS tag colors
- [ ] Tab bar truncates with horizontal scroll when >5 visible; ellipsis menu for overflow
- [ ] Keyboard shortcut `⌃⌥1–9` switches active bucket by tab index
- [ ] Per-app auto-route rules editable in Settings → Buckets
- [ ] Archive appears in Settings, not in main tab bar
- [ ] Swift 6 strict: `Bucket` is `Sendable`, `BucketManager.buckets` mutations on `@MainActor`

## Data Model

```swift
// Sources/Core/BucketTypes.swift — extend

public struct Bucket: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [BucketItem]
    public var createdAt: Date
    public var colorHex: String                // e.g. "#FF9500"
    public var emoji: String?                  // optional
    public var archived: Bool = false
    public var keyboardIndex: Int?             // 1–9 slot, nil if not bound
}

public struct AutoRouteRule: Codable, Sendable, Hashable {
    public let id: UUID
    public var bucketID: UUID
    public var frontmostBundleID: String       // e.g. "com.microsoft.VSCode"
    public var enabled: Bool
}

public struct BucketSettings: Codable, Sendable {
    // existing fields ...
    public var autoRouteRules: [AutoRouteRule] = []
}
```

```swift
// Sources/Core/BucketManager.swift — replace/extend

@Observable
public final class BucketManager {
    public private(set) var buckets: [Bucket]                  // active only (archived filtered)
    public private(set) var archivedBuckets: [Bucket]
    public var activeBucketID: UUID

    public func createBucket(name: String, colorHex: String) -> Bucket
    public func renameBucket(_ id: UUID, to: String)
    public func setColor(_ id: UUID, hex: String)
    public func deleteBucket(_ id: UUID, mergeInto: UUID?)
    public func archiveBucket(_ id: UUID)
    public func restoreBucket(_ id: UUID)
    public func moveItem(_ itemID: UUID, toBucket: UUID)

    // Auto-route
    private func routeIncomingItem(_ item: BucketItem) -> UUID   // returns destination bucket ID
}
```

## Storage Layout Change

```
~/.snor-oh/buckets/
├── manifest.json                      # array of Bucket with archived flag
├── <bucket-id>/
│   ├── files/...
│   └── images/...
└── settings.json
```

Migration path: on launch, if `manifest.json` is schema v1 (single bucket), wrap into v2 schema with `archived: false, name: "Default"`.

## Implementation Notes

| Concern | Fit |
|---|---|
| Storage migration | `BucketStore` detects schema version, runs `migrateV1ToV2()` once, bumps version field |
| Tab UI | SwiftUI `HStack` of pill-shaped tabs, horizontally scrollable when overflowing. Use existing glass-card aesthetic. |
| Color picker | Built-in 8-swatch palette view, no `ColorPicker` (kept simple). |
| Auto-route | Monitor frontmost app via `NSWorkspace.shared.frontmostApplication` KVO; cache last bundle ID; on drop, `BucketDropHandler` passes current frontmost to `routeIncomingItem`. |
| Keyboard shortcuts | Single `HotkeyRegistrar` call with `⌃⌥<N>` for N=1..9; switch by `buckets[N-1]` (filtered to non-archived). |
| Settings page | New "Buckets" sub-tab under existing "Bucket" tab: list, create/rename/archive, auto-route rules list. |
| Concurrency | All mutations `@MainActor`. Actor-backed `BucketStore` handles atomic writes. |

**Concurrency specific note**: drops may arrive from multiple sources (panel, mascot, screenshot watcher) simultaneously. All routes enter through `BucketManager.add(_:)` which runs on `@MainActor`, so ordering is serialized.

## Out of Scope

- Nested buckets / folders within a bucket — defer until requested
- Shared buckets between local and peer (that's Epic 05's layer)
- Smart auto-populating buckets (saved search) — different product, defer
- Cross-bucket drag to reorder / merge via drag — use context menu
- Bucket templates — YAGNI

## Open Questions

- [ ] Hard limit on active buckets — 12 or unlimited? (Lean: 12 soft warning, no hard block)
- [ ] Archive: kept forever, or deleted after N days? (Lean: kept forever, user deletes manually)
- [ ] Auto-route: if the rule matches but the bucket is archived, what happens? (Lean: fall back to active default)
- [ ] Does the menu bar show total items across all buckets, or only the active one? (Lean: active only, with tooltip showing total)

## Rollout Plan

| # | Task | Files | Done |
|---|------|-------|------|
| 1 | Extend types: multi-bucket, auto-route rule, settings | `Core/BucketTypes.swift` | ☐ |
| 2 | Schema migration v1 → v2 with tests | `Core/BucketStore.swift`, `Tests/BucketStoreMigrationTests.swift` | ☐ |
| 3 | `BucketManager` multi-bucket APIs | `Core/BucketManager.swift` | ☐ |
| 4 | Tab bar UI | `Views/BucketTabsView.swift` | ☐ |
| 5 | Create / rename / delete flows | `Views/BucketCreateSheet.swift` | ☐ |
| 6 | "Move to…" context menu | `Views/BucketItemCard.swift` | ☐ |
| 7 | Auto-route rule engine + frontmost monitor | `Core/BucketManager.swift` | ☐ |
| 8 | Settings: buckets list, archive, rules | `Views/SettingsView.swift` | ☐ |
| 9 | Keyboard shortcuts `⌃⌥1–9` | `Util/HotkeyRegistrar.swift` | ☐ |
| 10 | Release build verify + migration smoke test | – | ☐ |

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| % of users who create ≥2 buckets within 30d | >25% | Count `buckets.count > 1` users |
| % of drops into non-default bucket (given user has >1 bucket) | >60% | Drop counter by bucket |
| Auto-route trigger rate (given user has ≥1 rule) | >80% of drops while matching app frontmost | Rule-fire counter |
