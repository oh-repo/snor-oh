# Epic 03 — Screenshot Auto-Catch

**Tier**: 🟡 v1.5 differentiator · **Complexity**: S (3–5 days) · **Depends on**: Epic 01

## Problem Statement

macOS screenshots land on the Desktop by default. Users take many per day for design review, bug reports, memes — and the Desktop becomes a landfill. Dropover's "Screenshot Shelves" (shelf auto-pops the moment you capture) is consistently cited as a surprise-favorite feature ([research §Should-Have](../../research/bucket-feature-research.md#-should-have-high-value--mentioned-in-23-apps-strong-reviews)). If snor-oh's bucket can be the automatic catcher, the user never decides "do I delete this screenshot?" — it's already in the bucket with a TTL.

## Hypothesis

> We believe **automatically sending new screenshots into the bucket (with optional Desktop suppression)** will reduce Desktop clutter and increase bucket engagement. We'll know we're right when >70% of users with the feature enabled have at least one screenshot item in their bucket weekly, and bucket DAU increases vs baseline.

## Scope (MoSCoW)

| Priority | Capability | Why |
|---|---|---|
| Must | Watch the user's screenshot directory and add new files as `BucketItem` within 2 seconds of capture | Core behavior |
| Must | Setting toggle: "Auto-catch screenshots" (default OFF on first run, opt-in wizard prompt) | Privacy — some users screenshot sensitive things |
| Must | Setting: "Move screenshots out of Desktop" (default OFF) — if ON, the file is moved into bucket storage, not copied | Respect the user's fs |
| Should | Show an inline bubble: "Caught a screenshot!" on capture | Discoverability |
| Should | Detect Apple's system screenshot format (`Screenshot YYYY-MM-DD at HH.MM.SS.png`) to avoid catching unrelated files that happen to land in the screenshots dir | Noise reduction |
| Could | Respect the user's system screenshot location setting (not hardcoded to `~/Desktop`) | Real users customize this |
| Won't | Capture screenshots *for* the user (we don't implement a screenshot tool) | Apple's shortcut is already perfect |
| Won't | OCR the screenshot contents | Epic 07 / v2 at earliest |

## Users & JTBD

**Primary**: Users who screenshot often — devs filing issues, designers reviewing visual bugs, PMs annotating mockups.

**JTBD**: *When I take a screenshot, I want it held for me so I can drag it where it needs to go without stepping into Finder or cleaning up my Desktop later.*

## User Stories

1. I hit ⌘⇧4, drag a region, and immediately see my snor-oh's inventory count tick up. No file on my Desktop.
2. I take 5 screenshots in a row while debugging, then drag all 5 out of the bucket into a single Slack message as a batch.
3. I turn the feature off because I'm reviewing a compliance doc and want screenshots to stay outside the app.

## UX Flow

```
User hits ⌘⇧4 → selects region → screenshot saved to configured location
                                         │
                                         ▼
                       FSEventStream fires — watcher sees new .png
                                         │
                                         ▼
                       File name matches "Screenshot*.png"? Yes
                                         │
                                         ├─ Setting "move"? → move into bucket/images/
                                         │                    original path removed
                                         └─ else → copy into bucket/images/
                                         │
                                         ▼
                       Create BucketItem(kind: .image) with stackGroupID = nil
                                         │
                                         ▼
                       "catch" animation on mascot, bubble: "Got it!"
```

## Acceptance Criteria

- [ ] FSEventStream or `DispatchSource.makeFileSystemObjectSource` watches the user's screenshots dir (read from `defaults read com.apple.screencapture location`, fallback `~/Desktop`)
- [ ] File added to bucket within 2 seconds of system write
- [ ] `sourceBundleID` set to the sentinel `net.snor-oh.screenshot` (see README shared architecture); `.bucketChanged` posted with `source: "screenshot"`
- [ ] Bubble "Got it!" uses existing `BubbleManager`, fires at most once per 10 seconds to avoid spam on burst screenshots
- [ ] Toggle in Settings → Bucket tab ("Auto-catch screenshots" checkbox + "Move file" sub-option)
- [ ] First-launch wizard (existing `SetupWizard`) adds a step offering to enable this, default OFF
- [ ] When the setting changes, watcher starts/stops without app restart
- [ ] No double-capture if user also has clipboard capture on and copies a screenshot afterwards (dedupe via file path + hash)
- [ ] Handles the edge case of `com.apple.screencapture` writing a temp file then renaming — ignore incomplete writes

## Data Model

No new persistent types. Extension to settings:

```swift
// Sources/Core/BucketTypes.swift — extend BucketSettings

public struct BucketSettings: Codable, Sendable {
    // existing ...
    public var autoCatchScreenshots: Bool = false
    public var moveScreenshotsFromDesktop: Bool = false
    public var screenshotLocationOverride: String? = nil   // respects system default if nil
}
```

## Implementation Notes

| Concern | Fit |
|---|---|
| Watcher | New `Sources/Core/ScreenshotWatcher.swift`. Use `DispatchSource.makeFileSystemObjectSource(fileDescriptor:, eventMask: .write)` + `FSEventStreamCreate` fallback. |
| System screenshot location | `UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")` — tested pattern |
| Dedupe | On add, compute sha256 of file bytes (cheap — screenshots are small). Skip if hash matches an existing bucket item. |
| Move vs copy | `FileManager.default.moveItem(at:to:)` when move is on. Wrap in `try?` and fall back to copy+delete sequence with logging via existing `Log.app`. |
| Bubble throttle | Static `Date?` last-bubble in `ScreenshotWatcher`, 10s debounce |
| Start/stop | `ScreenshotWatcher.shared.setEnabled(_ enabled: Bool)` — called from `BucketManager` whenever `settings.autoCatchScreenshots` changes |

**macOS permission note**: watching `~/Desktop` may require Full Disk Access *only* if the user puts screenshots in an unusual location; the default `~/Desktop` is inside the sandbox container when app is sandboxed. For the unsandboxed `.build/release-app/snor-oh.app` path the watcher works without prompts. Document in settings help text.

## Out of Scope

- Creating screenshots (no custom capture tool)
- Auto-tagging screenshots by content
- OCR → text extraction (Epic 07)
- Screenshot annotation tools (Skitch territory)
- Watching arbitrary user-chosen folders → that's Epic 08's "watched folders"

## Open Questions

- [ ] Should a sandboxed build ask for Full Disk Access, or should we document that the feature needs the unsandboxed release build? (Lean: document, snor-oh ships unsandboxed today)
- [ ] If the user has `Screenshot Shelf` from Dropover installed, both apps will catch. OK? (Lean: it's the user's choice)
- [ ] Default on or off? Research says Dropover defaults ON, users love it, but we don't know our users yet — keep OFF, prompt in wizard.

## Rollout Plan

| # | Task | Files | Done |
|---|------|-------|------|
| 1 | Extend `BucketSettings` with 3 new fields | `Core/BucketTypes.swift` | ☐ |
| 2 | Implement `ScreenshotWatcher` with start/stop | `Core/ScreenshotWatcher.swift` | ☐ |
| 3 | Filename match + dedupe via sha256 | inside watcher | ☐ |
| 4 | Wire to `BucketManager` + `.bucketChanged` | `Core/BucketManager.swift` | ☐ |
| 5 | Settings UI checkboxes | `Views/SettingsView.swift` (Bucket tab) | ☐ |
| 6 | Wizard step for first-launch opt-in | `Views/SetupWizard.swift` | ☐ |
| 7 | Bubble throttle | – | ☐ |
| 8 | Manual test: system screenshot location override, network volume path, burst capture | – | ☐ |
| 9 | Release build verify | – | ☐ |

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| % of opt-in users with ≥1 screenshot item weekly | >70% | Count items where `sourceBundleID == com.apple.screencapture` |
| False-catch rate (user manually deletes caught screenshot) | <15% | Manual delete counter filtered by source bundle |
| Feature opt-in rate after wizard | >40% | Wizard opt-in telemetry |
