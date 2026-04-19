# Epic 08 — Power Features

**Tier**: 🔵 v2 power-user · **Complexity**: L (3–4 weeks, ship in slices) · **Depends on**: Epic 01, Epic 04

## Problem Statement

The remaining long-tail of features requested by power users across competitor research are small individually but compound into a strong "pro user" value proposition: macOS Shortcuts integration, Spotlight actions, watched folders (auto-collect from a directory), and time-based auto-expiry. Each one is a single-digit % of users but they're the users who evangelize and retain.

## Hypothesis

> We believe **a small suite of automation primitives (Shortcuts, Spotlight, watched folders, auto-expiry)** will convert curious users into daily users by making the bucket invisible-when-needed and self-maintaining. We'll know we're right when >80% of users who enable any one of these still have it enabled after 30 days.

## Scope (MoSCoW)

Four sub-features, each shippable independently. Order by dependency-free first.

| Priority | Sub-feature | Complexity | Dependency |
|---|---|---|---|
| Must | Time-based auto-expiry | S | None |
| Must | macOS Shortcuts actions | M | Shortcuts framework |
| Should | Spotlight actions (macOS 14+ Spotlight / macOS 15 "actions") | S | None |
| Should | Watched folders (auto-collect into a bucket) | M | Epic 04 (for bucket targeting) |
| Could | URL scheme (`snor-oh://bucket/add?...`) | S | None |
| Won't | Command bar (Dropover's ⌘K) | Could add later; feels like over-engineering for solo dev |
| Won't | AppleScript suite (Unclutter's feature) | Shortcuts supersedes |
| Won't | Custom scripting / JS plugin system | Way out of scope |

## Users & JTBD

**Primary**: power users who live in Shortcuts, customize Raycast, and automate everything. They are the subset most likely to write reviews.

**JTBD**: *When my workflow includes the bucket, I want my existing automation tools to reach into it without me having to script around the app.*

---

## Sub-feature 1: Time-based Auto-Expiry

### Scope
Items untouched for N days are silently evicted (unless pinned). Prevents the bucket from becoming a graveyard — the single most-criticized failure mode of shelf apps.

### Acceptance Criteria
- [ ] Per-item `lastAccessedAt: Date` updated on view / drag-out / action
- [ ] Global setting: "Auto-expire unpinned items after [7 / 30 / 90 / never] days"
- [ ] Per-bucket override in Settings (defaults to global)
- [ ] Expiry sweep runs once on launch + every 6 hours
- [ ] Expired items are logged via `Log.app` so a user can diagnose
- [ ] Pinned items never expire

### Data Model
```swift
public struct BucketSettings {
    // existing ...
    public var globalExpiryDays: Int? = 30          // nil = never
}

public struct Bucket {
    // existing ...
    public var expiryDaysOverride: Int? = nil        // nil = inherit
}
```

### Implementation
- `BucketManager.runExpirySweep()` called from launch + `Timer` with 6h interval.
- Zero UI surface beyond Settings checkboxes.

---

## Sub-feature 2: macOS Shortcuts Actions

### Scope
App-provided actions visible in the Shortcuts app so users can compose workflows.

### Actions to Ship
- **Add to Bucket** — input: file/text/URL; optional target bucket; returns: item ID
- **Get Bucket Items** — input: bucket name (optional), limit (default 20); returns: array of items
- **Create Bucket** — input: name, color; returns: bucket ID
- **Clear Bucket** — input: bucket name; returns: count cleared
- **Capture Clipboard** — no input; forces current clipboard into the bucket

### Acceptance Criteria
- [ ] Actions defined via `AppIntent` (iOS 16 / macOS 13+ API)
- [ ] Each action visible in Shortcuts app after install
- [ ] Parameters typed (file, text, URL) with appropriate UI picker
- [ ] Actions succeed without snor-oh app being visible (works in background)
- [ ] Documented in Settings → Bucket → Automation → "Shortcuts"

### Implementation
- New `Sources/Intents/BucketIntents.swift`
- Uses `AppIntents` framework — `struct AddToBucketIntent: AppIntent`
- Each intent's `perform()` calls `BucketManager.shared` on `@MainActor`
- No additional auth needed — macOS handles intent permission

---

## Sub-feature 3: Spotlight Actions (macOS 15+)

### Scope
macOS 15's Spotlight exposes app "actions". Register bucket actions so users can type "add to bucket" in Spotlight and act without opening the panel.

### Actions
- "New Bucket Shelf" → creates empty active bucket
- "Clipboard to Bucket" → captures current clipboard as an item
- "Show Bucket" → opens panel

### Acceptance Criteria
- [ ] Actions visible in macOS 15+ Spotlight
- [ ] No UI opened when action runs headlessly — only result confirmation bubble
- [ ] Gracefully absent on macOS 14 (no error)

### Implementation
- Implemented via same `AppIntents` that power Shortcuts — macOS promotes them automatically.
- Annotate key intents with `openAppWhenRun = false` where headless.

---

## Sub-feature 4: Watched Folders

### Scope
Point at a directory on disk; any new file added there lands in a specified bucket automatically. Dropover's "Folder Observation" is the reference.

### Acceptance Criteria
- [ ] Settings: list of watched folders, each with: path, destination bucket, include/exclude glob (e.g. `*.png`)
- [ ] Additive rules: optional "move file from watched folder to bucket storage" (default: copy)
- [ ] Bonus: "only if file is >N seconds old" (avoid catching in-progress downloads)
- [ ] Uses `FSEventStream` — same primitive as Screenshot Watcher in Epic 03
- [ ] At most 10 watched folders (sanity guardrail)
- [ ] Disable all quickly with a master switch

### Data Model
```swift
public struct WatchedFolder: Identifiable, Codable, Sendable {
    public let id: UUID
    public var path: String
    public var destinationBucketID: UUID
    public var fileGlob: String = "*"          // e.g. "*.png"
    public var moveFiles: Bool = false
    public var minAgeSeconds: Double = 2.0      // avoid in-progress writes
    public var enabled: Bool = true
}
```

### Implementation
- `Sources/Core/WatchedFolderEngine.swift`
- Delegates to per-folder `FSEventStream`. Generalization of `ScreenshotWatcher` from Epic 03 — extract shared code into `FileWatcher` base.

---

## Sub-feature 5: URL Scheme

### Scope
`snor-oh://bucket/add?text=...&bucket=Acme` and related — enables third-party tools (e.g. Alfred workflows, Safari bookmarklet) to drop into the bucket.

### Acceptance Criteria
- [ ] Registered URL scheme in Info.plist: `snor-oh`
- [ ] Handler in `AppDelegate.application(_:open:)`
- [ ] Supported actions: `bucket/add`, `bucket/toggle`, `bucket/clear`
- [ ] Query params documented in Settings help text

### Implementation
- Extend existing `AppDelegate`
- Reuse `BucketManager` APIs
- URL parsed into a `URLCommand` enum with exhaustive switch

---

## Shared Implementation Notes

| Concern | Fit |
|---|---|
| `AppIntents` availability | macOS 13+ is already our min target (14 actually); compatible |
| FS watching | Extract `ScreenshotWatcher`'s core into `Sources/Core/FileWatcher.swift`, both epics use it |
| Expiry Timer | Use existing `Timer + RunLoop.main.add(t, forMode: .common)` pattern — explicitly the one CLAUDE.md calls out |
| Settings page | New "Automation" sub-tab in Settings → Bucket with sections for each sub-feature |
| Doc pages | Each sub-feature gets a short section in the in-app help text; no new docs files needed |

**Concurrency**: all sub-features run `@MainActor` for state mutations. Timers and FS events dispatch through `MainActor.run` or `Task { @MainActor in }`.

## Out of Scope

- Custom scripting (JS / Lua plugin host)
- Command bar (⌘K palette) — could revisit if needed but adds a whole search+command subsystem
- Distributed automation (e.g. trigger workflow on peer) — not worth it
- AI-assisted auto-categorization of new items — not the product

## Open Questions

- [ ] Default expiry — 30 days, or "never" with a prompt to set it? (Lean: 30 days, shown as a default but overridable)
- [ ] Spotlight actions are macOS 15+; should we gate the UI that mentions them? (Lean: yes — hide setting on older versions rather than show a disabled option)
- [ ] Watched folder max count — 10 feels arbitrary; should we remove? (Lean: keep 10 for v1; raise on demand)
- [ ] URL scheme security — should we require a hash/token to prevent a local malicious app from clearing buckets via URL? (Lean: no hash for `add`, require prompt for `clear`)

## Rollout Plan

Ship in slices, not one big PR. Order by value-to-complexity ratio.

| # | Slice | Files | Ship | Done |
|---|------|-------|------|------|
| 1 | Auto-expiry (simplest, biggest quality-of-life win) | `Core/BucketManager.swift`, `Views/SettingsView.swift` | Week 1 | ☐ |
| 2 | URL scheme | `App/AppDelegate.swift`, `Info.plist` | Week 1 | ☐ |
| 3 | Shortcuts actions (5 intents) | `Intents/BucketIntents.swift` | Week 2–3 | ☐ |
| 4 | Spotlight surfacing (same intents, annotations only) | `Intents/BucketIntents.swift` | Week 3 | ☐ |
| 5 | Watched folders engine + settings UI | `Core/WatchedFolderEngine.swift`, `Core/FileWatcher.swift`, `Views/SettingsView.swift` | Week 4 | ☐ |
| 6 | Release build verify for each slice | – | per slice | ☐ |

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| % of users with any automation enabled | >25% | Setting-enabled count |
| Retention of automation users @ 30 days | >80% | Cohort |
| Auto-expiry silent sweep — % of bucket items that age out vs user-deleted | 60–80% | Eviction reason counter |
| Shortcut action invocations per week per user (when enabled) | ≥3 | Invocation counter |
| URL scheme invocations per week per user (when used) | ≥2 | URL handler counter |
