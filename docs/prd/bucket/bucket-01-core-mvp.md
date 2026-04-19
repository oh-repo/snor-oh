# Epic 01 — Core Bucket MVP

**Tier**: 🟢 v1 blocker · **Complexity**: M (6–8 weeks solo) · **Depends on**: –

## Problem Statement

During a work session a macOS user repeatedly juggles ephemeral items — screenshots they just took, URLs they want to revisit, files waiting to attach to an email, text snippets they're about to paste. Today they dump this on the Desktop, in Slack's "Saved Items", across 40 browser tabs, or in the single-slot system clipboard. Nothing has a home, and context evaporates the moment they copy the next thing. Shelf apps (Dropover, Yoink) and clipboard managers (Paste, Maccy) each solve ⅓ of this but users end up running two apps and still forget where things are ([research §1](../../research/bucket-feature-research.md#1-category-landscape)).

## Hypothesis

> We believe **one panel that accepts anything draggable plus auto-captures the clipboard** will reduce "where did I put that?" moments for snor-oh users. We'll know we're right when >40% of daily active users have ≥3 items in their bucket after one week.

## Scope (MoSCoW)

| Priority | Capability | Why |
|---|---|---|
| Must | Drop files, folders, URLs, images, plain text, rich text into bucket | Universal input is the category definition |
| Must | **Drop onto the mascot sprite** as an alternative drop target (same UTTypes as panel) | Mascot is our unfair advantage — it must be the primary drop surface |
| Must | Drag out to any destination (Finder, Mail, chat) with Finder modifier parity (⌥ copy, ⌘ move) | Table stakes across all shelf apps |
| Must | Global hotkey + menu-bar click to toggle bucket panel | Gesture activation is the #1 feature in research |
| Must | Clipboard auto-capture (text, image, link, file path, color) with enable/disable toggle | Half of category's value |
| Must | Pin, delete, clear-all | Pins protect from rollover |
| Must | Rich previews: image thumbnails, URL favicon+title, file icon+name+size | Table stakes |
| Must | Search / filter across items | #1 r/macapps request |
| Must | Stack multi-file drops into one expandable card | Pattern every shelf app uses |
| Must | Spacebar Quick Look preview | Native macOS expectation |
| Must | Configurable history cap (default 200 items, 100MB) with LRU eviction of unpinned items | Prevents the bucket-as-graveyard failure mode |
| Should | Per-app ignore list (never capture clipboard when source app is, e.g., 1Password) | Privacy must-have |
| Should | "Copy as plain text" action on rich-text items | Universal pain point |
| Won't | Multiple buckets | → Epic 04 |
| Won't | Screenshot auto-catch | → Epic 03 |
| Won't | Pet animation integration | → Epic 02 (ships concurrently) |

## Users & Job-to-Be-Done

**Primary**: The snor-oh user who's already installed the mascot — a developer or designer on macOS 14+, comfortable with keyboard shortcuts, working across 3+ apps at once.

**JTBD**: *When I find something I might need in the next 30 minutes, I want to park it somewhere that survives my next copy so I can retrieve it without retracing my steps.*

## User Stories

1. As a developer, I drag a screenshot off my browser, into the bucket, then drag it out into a GitHub comment — without ever touching the Desktop.
2. As a writer, I copy a quote, copy a URL, copy an author name — then open the bucket and paste all three in order.
3. As a support engineer, I drag a log file and a JSON blob into the bucket, pin them, and reuse them across three tickets.
4. As a privacy-conscious user, I add 1Password to the ignore list and never see password strings in my history.
5. As any user, I hit ⌃⌥B, type "log" in search, hit Enter, and the matching item pastes into my focused app.

## UX Flow — Critical Path

**Drop path A — panel**:
```
User starts dragging → bucket panel fades in at configured edge
  → drop → item card animates into bucket with thumbnail
  → panel auto-hides after 2s (configurable, or pin-open)
```

**Drop path B — mascot** (hero interaction):
```
User starts dragging → mascot (always visible) accepts the drop directly
  → drop → item lands in active bucket (panel stays closed)
```

Both paths use the same `BucketDropHandler` — mascot is a drop-through, not a separate pipeline. Epic 02 adds the visual "catch" animation on top.

**Retrieval**:
```
⌃⌥B → panel appears → type "screen" → filtered → Enter pastes into focused app
  or: drag card out into Mail (⌥ held = copy, ⌘ held = move)
```

**Clipboard path**: every Cmd-C adds an item to the bucket automatically (unless the source app is in the ignore list). Visible in panel under a "Clipboard" filter chip.

## Acceptance Criteria

- [ ] Drop any of: file, folder, image bytes, URL (with metadata fetched within 500 ms), plain text, rich text (RTF), NSPasteboard color
- [ ] Mascot sprite (in `MascotView`) accepts the same set of UTTypes as the panel drop zone — both surfaces route through the same `BucketDropHandler`
- [ ] Drag-out to Finder produces a *copy* by default, *move* if ⌘ held
- [ ] Drag-out to any app that accepts the underlying UTType works
- [ ] Clipboard capture deduplicates identical consecutive copies
- [ ] Ignore list supports bundle ID entry (e.g. `com.agilebits.onepassword7`) with autocomplete from running apps
- [ ] Search matches against: text content, file name, URL, URL title
- [ ] Pinned items never auto-evict
- [ ] LRU eviction triggers when either item count > 200 OR sidecar storage > 100MB (user-configurable both)
- [ ] Panel position, size, edge preference persisted across launches
- [ ] Hotkey is user-configurable in Settings → Bucket tab
- [ ] First-launch tip speech bubble: "Drag anything onto me to bucket it!" (uses existing `BubbleManager`)
- [ ] Dark mode + Light mode + Auto match system appearance

## Data Model

```swift
// Sources/Core/BucketTypes.swift (new)

public enum BucketItemKind: String, Codable, Sendable {
    case file, folder, image, url, text, richText, color
}

public struct BucketItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var kind: BucketItemKind
    public var createdAt: Date
    public var lastAccessedAt: Date
    public var pinned: Bool
    public var sourceBundleID: String?
    public var stackGroupID: UUID?      // items sharing this ID render as one card

    // Payload — exactly one of these non-nil, enforced in init
    public var fileRef: FileRef?         // file / folder / image-from-file
    public var text: String?             // text / richText (RTF base64)
    public var urlMeta: URLMetadata?
    public var colorHex: String?

    public struct FileRef: Codable, Sendable, Hashable {
        public var originalPath: String      // may be stale
        public var cachedPath: String?       // sidecar copy in bucket storage
        public var byteSize: Int64
        public var uti: String
        public var displayName: String
    }

    public struct URLMetadata: Codable, Sendable, Hashable {
        public var urlString: String
        public var title: String?
        public var faviconPath: String?      // sidecar
        public var ogImagePath: String?      // sidecar
    }
}

public struct Bucket: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [BucketItem]           // newest first
    public var createdAt: Date
}
```

```swift
// Sources/Core/BucketManager.swift (new)

@Observable
public final class BucketManager {
    public static let shared = BucketManager()

    public private(set) var activeBucket: Bucket
    public private(set) var settings: BucketSettings

    public func add(_ item: BucketItem)
    public func remove(_ id: UUID)
    public func togglePin(_ id: UUID)
    public func clearUnpinned()
    public func search(_ query: String) -> [BucketItem]

    // Clipboard capture
    private var clipboardMonitor: Timer?     // NSPasteboard.changeCount poll, 500ms
    private func onPasteboardChange(_ pb: NSPasteboard)
}

public struct BucketSettings: Codable, Sendable {
    public var maxItems: Int = 200
    public var maxStorageBytes: Int64 = 100_000_000
    public var captureClipboard: Bool = true
    public var ignoredBundleIDs: Set<String> = []
    public var autoHideSeconds: Double = 2.0
    public var preferredEdge: ScreenEdge = .right
    public var hotkey: HotkeyBinding = .init(key: "B", modifiers: [.control, .option])
}
```

## Storage Layout

```
~/.snor-oh/buckets/
├── manifest.json                      # array of Bucket, items metadata only
├── <bucket-id>/
│   ├── files/<item-id>.<ext>          # copies of dropped files
│   ├── images/<item-id>.png
│   ├── favicons/<item-id>.ico
│   └── og/<item-id>.jpg
└── settings.json                      # BucketSettings
```

## Implementation Notes (fits existing snor-oh architecture)

| Layer | Existing file | Change |
|---|---|---|
| Types | `Sources/Core/Types.swift` | Leave alone. Put bucket types in new `Sources/Core/BucketTypes.swift` |
| State | `Sources/Core/SessionManager.swift` | No change. `BucketManager` is a sibling `@Observable` singleton |
| UI root | `Sources/Views/SnorOhPanelView.swift` | Add a "Bucket" segmented tab next to "Sessions" — reuse glass card |
| UI drop zone | new `Sources/Views/BucketView.swift` | SwiftUI grid of cards with native `.onDrop(of:)` |
| Mascot drop target | existing `Sources/Views/MascotView.swift` | Add `.onDrop(of: BucketDropHandler.supportedUTTypes, delegate: bucketDropDelegate)` to the mascot sprite — no duplication, same handler as the panel. Visual reactions (catch frame, badge) ship in Epic 02 but the drop pipe itself lives here. |
| Hotkey | new `Sources/Util/HotkeyRegistrar.swift` | Carbon `RegisterEventHotKey` — isolated file so we only write it once |
| Menu bar | `Sources/App/AppDelegate.swift` | Add bucket count badge (tiny bubble on the status item, same renderer as session dots) |
| Settings | `Sources/Views/SettingsView.swift` | New "Bucket" tab between "Ohh" and "Claude Code" |
| Drop handler | `Sources/Core/BucketDropHandler.swift` (new) | Unpack `NSItemProvider` → `BucketItem` |
| URL metadata | `Sources/Core/URLMetadataFetcher.swift` (new) | `URLSession` → OpenGraph parse, 3s timeout |
| Clipboard watch | `BucketManager.clipboardMonitor` | 500 ms `Timer` polling `NSPasteboard.general.changeCount`; existing `RunLoop.main.add(t, forMode: .common)` pattern |
| Persistence | `Sources/Core/BucketStore.swift` (new) | Debounced 1s writes to JSON — same debounce idea as `CustomOhhManager` |
| Notifications | `Notification.Name.bucketChanged` | Panel + menu bar subscribe, same as `.statusChanged` |

**Concurrency**: Swift 6 strict. `BucketManager` runs on `@MainActor`. File I/O via a dedicated `actor BucketStore`. Follows `ecc:swift-actor-persistence` pattern.

## Out of Scope

- Multiple named buckets → Epic 04
- Screenshot auto-capture → Epic 03
- Pet inventory animation → Epic 02
- Any quick actions (resize, compress, extract text) → Epic 07
- Bonjour peer sync of bucket → Epic 05
- Text snippet expansion → Epic 06

## Open Questions

- [ ] Should clipboard capture store the full history or dedupe within a 10s window? (Lean: dedupe)
- [ ] On first drag-in, where should the panel default-appear — always right edge, or near cursor like DropPoint? (Lean: near cursor on first use, then remember edge)
- [ ] What's the UX when the original file has moved/deleted? Keep the cached copy, badge it as "orphaned"?
- [ ] Clipboard capture on RTF: store RTF, or convert to plain text? (Lean: store both, let user choose on paste-out)

## Rollout Plan

| # | Task | Files | Done |
|---|------|-------|------|
| 1 | Define `BucketItem` / `Bucket` / `BucketSettings` types + unit tests | `Core/BucketTypes.swift`, `Tests/BucketTypesTests.swift` | ☐ |
| 2 | `BucketStore` actor with atomic JSON write + sidecar file copy | `Core/BucketStore.swift` | ☐ |
| 3 | `BucketManager` @Observable + add/remove/pin/search + eviction | `Core/BucketManager.swift` | ☐ |
| 4 | Hotkey registrar + Settings persistence | `Util/HotkeyRegistrar.swift` | ☐ |
| 5 | Drop handler — unpack `NSItemProvider` across all UTTypes | `Core/BucketDropHandler.swift` | ☐ |
| 6 | URL metadata fetcher | `Core/URLMetadataFetcher.swift` | ☐ |
| 7 | Clipboard monitor + ignore list | inside `BucketManager` | ☐ |
| 8 | `BucketView` SwiftUI: drop zone, card grid, pin/delete buttons, Quick Look | `Views/BucketView.swift` | ☐ |
| 9 | Panel integration — tab switcher on `SnorOhPanelView` | `Views/SnorOhPanelView.swift` | ☐ |
| 9b | Wire `MascotView.onDrop` to shared `BucketDropHandler` (no visual reaction — Epic 02 adds that) | `Views/MascotView.swift` | ☐ |
| 10 | Menu bar bucket-count badge | `App/AppDelegate.swift` | ☐ |
| 11 | Settings "Bucket" tab | `Views/SettingsView.swift` | ☐ |
| 12 | First-launch bubble tip | `Views/SpeechBubble.swift` integration | ☐ |
| 13 | Release build verify — `bash Scripts/build-release.sh` | – | ☐ |

## Success Metrics (post-ship)

| Metric | Target | Method |
|---|---|---|
| % of DAU with ≥3 items after 7d | >40% | Local anonymous telemetry counter (opt-in) |
| Median bucket retrieval time (drag-in → drag-out) | <20 s | Time delta between `.bucketChanged` add/remove |
| Clipboard capture false-positive rate (user manually deletes captured item) | <10% | Count manual deletes of clipboard-origin items |
| Crash-free sessions | >99.5% | Existing OSLog capture |
