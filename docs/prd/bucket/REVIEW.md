# Cross-Epic Review & Overview

*Generated: 2026-04-19 — after Epic 01 ↔ 02 split adjustment.*

Purpose: one-page sanity check on the full PRD set — feature coverage, surface ownership, data-model evolution, dependency graph, and open gaps.

---

## 1. Feature Coverage Matrix

Each research-identified feature maps to exactly one owning epic. No orphans, no duplicates.

| Feature from research | Tier | Owner | Notes |
|---|---|---|---|
| Drop any content into bucket | 🟢 Must | 01 | Unified `BucketDropHandler` |
| Drop onto mascot | 🟢 Must | 01 (wiring) + 02 (reactions) | **Split clarified this round** |
| Finder modifier parity (⌥/⌘) | 🟢 Must | 01 | – |
| Gesture/hotkey activation | 🟢 Must | 01 | `⌃⌥B` default |
| Clipboard auto-capture | 🟢 Must | 01 | Pasteboard poll |
| Pin / favorite | 🟢 Must | 01 | – |
| Quick Look preview | 🟢 Must | 01 | Native Spacebar |
| Search / filter | 🟢 Must | 01 | – |
| Stack multi-file drops | 🟢 Must | 01 | `stackGroupID` |
| Rich previews (thumb / favicon / OG) | 🟢 Must | 01 | `URLMetadataFetcher` |
| LRU eviction (count/size cap) | 🟢 Must | 01 | – |
| Per-app ignore list | 🟡 Should | 01 | – |
| Mascot inventory badge | 🟢 Must | 02 | – |
| Mascot catch animation | 🟢 Must | 02 | Reacts to `.bucketChanged` source |
| "I'm heavy!" overflow bubble | 🟢 Must | 02 | 20/50/100 thresholds |
| Menu-bar count badge | 🟢 Must | 01 | **Now single owner** |
| Screenshot auto-catch | 🟡 Should | 03 | Opt-in, FSEvents |
| Multi-bucket (named, colored) | 🟡 Should | 04 | Schema v1→v2 migration |
| Per-app auto-route rules | 🟡 Should | 04 | Frontmost app → bucket |
| Peer send/receive via Bonjour | 🟡 Should | 05 | Reuses `:1234` HTTPServer |
| Per-peer trust / auto-accept | 🟡 Should | 05 | – |
| Notes scratchpad (≤10 tabs) | 🟡 Should | 06 | Hotkey `⌃⌥N` |
| Text snippets w/ trigger expansion | 🟡 Should | 06 | Hotkey `⌃⌥V`, Accessibility opt-in |
| Quick actions — resize/convert/OCR/strip EXIF | 🔵 Could | 07 | Vision + ImageIO |
| Quick actions — zip / stitch PDF / rename | 🔵 Could | 07 | – |
| Time-based auto-expiry | 🔵 Could | 08 | Per-item `lastAccessedAt` |
| macOS Shortcuts actions | 🔵 Could | 08 | `AppIntents` |
| Spotlight actions (macOS 15+) | 🔵 Could | 08 | Same intents |
| Watched folders | 🔵 Could | 08 | Shared `FileWatcher` with 03 |
| URL scheme `snor-oh://bucket/...` | 🔵 Could | 08 | – |

**Result**: every research-called feature has a home, nothing is double-counted.

---

## 2. Epic 01 ↔ 02 Split (this revision)

**Before**: Epic 02 owned both the `MascotView.onDrop` wiring *and* the visual reactions. This coupled MVP ship to mascot visual work.

**After**:

| Concern | Epic 01 (MVP) | Epic 02 (Integration) |
|---|---|---|
| Mascot as drop target | ✅ adds `.onDrop` → `BucketDropHandler` | — |
| Panel as drop target | ✅ | — |
| `.bucketChanged` with `source` tag | ✅ posts on every add | ✅ observes and reacts |
| Catch animation (one-frame + tint) | — | ✅ |
| Inventory badge on mascot | — | ✅ |
| `.carrying` status | — | ✅ |
| Overflow "I'm heavy!" bubble | — | ✅ |
| Menu-bar count badge | ✅ (simple numeric) | — *(moved)* |

**Why this is better**:
- MVP ships with a functional mascot drop target even if visual polish slips.
- Epic 02 becomes purely additive (it's all `@Observable` observers), so it can ship as a dot release.
- Single owner for menu bar — no surprise merge conflict between 01 and 02.

---

## 3. Surface / Ownership Map

| Surface | Owning Epic(s) | Conflicts risk |
|---|---|---|
| `BucketManager` (@Observable) | 01 creates; 04, 06, 08 extend | Low — additive fields only |
| `BucketItem` / `Bucket` types | 01 creates; 03, 04, 05, 06, 07, 08 extend | Low — additions + new kinds only; no renames |
| `BucketSettings` | 01 creates; 03, 04, 05, 08 extend | **Watch**: keep `Codable` additions non-breaking (default values for new fields) |
| `BucketStore` actor | 01 creates; 04 schema migration | Schema version bump lives in 04 |
| `HTTPServer` | 05 adds 3 routes | Only 05 touches |
| `BucketDropHandler` | 01 creates | Only 01 — reused by 02, 04 (auto-route decides destination) |
| `MascotView` | 01 adds drop; 02 adds badge+observer | Clean: 01=onDrop only, 02=overlay+observer |
| `AppDelegate` status bar | 01 adds count badge | Sole owner |
| `SettingsView` | 01 adds "Bucket" tab; 03/04/05/06/08 add sections | Tab is a `TabView` — sections are independent |
| `BubbleManager` | 02 (overflow), 05 (incoming transfer) | Both are posts, no shared state |
| `HotkeyRegistrar` | 01 (`⌃⌥B`), 04 (`⌃⌥1–9`), 06 (`⌃⌥N`, `⌃⌥V`) | **No collisions** |
| `FileWatcher` (shared) | 03 first introduces it as `ScreenshotWatcher`; 08 extracts base | Refactor happens in 08 |

---

## 4. Data Model Evolution (by epic)

All changes are **additive** (new optional fields or new cases in open-ended enums). No breaking renames.

```
Epic 01  base: BucketItem, Bucket, BucketSettings, FileRef, URLMetadata
         kinds: file, folder, image, url, text, richText, color

Epic 03  settings += autoCatchScreenshots, moveScreenshotsFromDesktop, screenshotLocationOverride

Epic 04  Bucket      += colorHex, emoji?, archived, keyboardIndex?
         settings    += autoRouteRules
         new types   : AutoRouteRule
         schema bump : v1 → v2 (migration ships in this epic)

Epic 05  settings  += allowIncomingTransfers, autoAcceptPeerIDs, maxIncomingSizeBytes
         new types : PendingTransfer (with TransferState)
         HTTP API  : POST /bucket/receive, GET /bucket/peer-info, POST /bucket/accept/:id

Epic 06  BucketItemKind += note, snippet
         new types      : Note, Snippet
         new storage    : notes.json, snippets.json

Epic 07  BucketItem += derivedFromItemID, derivedAction
         new protocol: QuickAction + registry

Epic 08  BucketItem += (already has lastAccessedAt from Epic 01) — no schema changes
         settings   += globalExpiryDays
         Bucket     += expiryDaysOverride?
         new types  : WatchedFolder
         extras     : AppIntents, URL scheme handler
```

**Migration risk**: only Epic 04 bumps schema version. All other epics add optional fields with defaults — safe for decode.

---

## 5. Hotkey Inventory

| Hotkey | Epic | Action | Default |
|---|---|---|---|
| `⌃⌥B` | 01 | Toggle bucket panel | ✅ |
| `⌃⌥1–9` | 04 | Switch to bucket N | ✅ |
| `⌃⌥N` | 06 | Toggle notes (opens panel to Notes tab) | ✅ |
| `⌃⌥V` | 06 | Expand snippet | ✅ |

All user-rebindable in Settings → Bucket → Hotkeys. No collisions with system shortcuts or existing snor-oh bindings.

---

## 6. `.bucketChanged` Source Contract (new this revision)

`userInfo["source"]` is an enumerated string — added to the shared architecture decisions in README. Every add-path sets it:

| Source | Epic | Trigger |
|---|---|---|
| `"panel"` | 01 | Drop into `BucketView` |
| `"mascot"` | 01 | Drop onto `MascotView` |
| `"clipboard"` | 01 | Pasteboard change detected |
| `"screenshot"` | 03 | FSEvents on screenshot dir |
| `"peer"` | 05 | `/bucket/receive` accepted |
| `"watched-folder"` | 08 | `WatchedFolderEngine` |
| `"shortcut"` | 08 | `AppIntents.perform` |

Epic 02's catch-reaction intensity is picked from this value (mascot = full reaction, panel = badge-only, clipboard = subtle pulse, etc.).

---

## 7. `sourceBundleID` Sentinel Convention (new this revision)

Real bundle IDs always take precedence (clipboard captures from `com.apple.safari`, etc.). For non-app origins we use dotted sentinels in the `net.snor-oh.*` namespace so a single field handles all cases without a parallel `origin` enum:

- `net.snor-oh.peer:<peer-uuid>`
- `net.snor-oh.screenshot`
- `net.snor-oh.watchedfolder:<folder-id>`
- `net.snor-oh.shortcut`
- `net.snor-oh.url-scheme`

Alternative considered: add a `BucketItemOrigin` enum. Rejected for YAGNI — we can always migrate later if the sentinel string parsing becomes painful.

---

## 8. Dependency Graph

```
                        ┌────────────┐
                        │ 01 Core    │
                        │   MVP      │
                        └─────┬──────┘
                              │
           ┌──────────┬───────┼────────┬──────────┬──────────┐
           │          │       │        │          │          │
           ▼          ▼       ▼        ▼          ▼          ▼
        02 Mascot  03 SS    04 Multi  05 Peer   06 Notes  07 Actions
                              │        │                       │
                              │ (soft) │                       │
                              └────────┤                       │
                                       │                       │
                                       ▼                       │
                                    08 Power  ◄────────────────┘
                                    (shares FileWatcher w/ 03)
```

- Hard deps: every epic needs 01.
- Epic 04 is a hard dep for Epic 08's watched-folders (need `destinationBucketID`).
- Epic 04 is a **soft** dep for Epic 05 (receiver can drop into active bucket if 04 isn't shipped).
- Epic 08's `FileWatcher` extraction is a refactor — Epic 03's `ScreenshotWatcher` ships first with its own implementation, Epic 08 pulls it into a shared base when it adds watched folders.

---

## 9. Gaps & Deferred Decisions

Items explicitly out of scope for every epic, surfaced here so nothing falls through cracks:

| Gap | Why deferred | When to revisit |
|---|---|---|
| iOS companion / Handoff | No iOS app exists yet | If snor-oh iOS ships |
| Hosted cloud share link (Dropover Cloud equivalent) | Needs backend, account system | If usage data shows peer-sync isn't enough |
| AES-256 encryption of bucket storage | macOS sandbox suffices for shelf utility | If a user specifically requests |
| Paste sequences / queue | <5% of users (research) | Only if specifically requested |
| OCR on bucket screenshots automatically | Should be opt-in user action (Epic 07) not automatic | N/A — ship as manual action |
| AI captions / summaries | Not the product | Never |
| Windows/Linux port | macOS-only product | Never |

---

## 10. Open Cross-Epic Questions

- [ ] **Default expiry**: Epic 08 suggests 30 days. Epic 01 has no time-based expiry. Should MVP ship with a hardcoded 90-day safety expiry so users don't accumulate items forever *before* Epic 08 ships? (Recommendation: yes — add to Epic 01's Musts as "90-day hard expiry for unpinned, non-configurable in v1")
- [ ] **Telemetry**: several epics reference "counter" metrics. We don't have telemetry infrastructure yet. Decision needed: file-local counters with opt-in upload, or skip formal metrics and rely on qualitative feedback? (Lean: local-only counters, no network)
- [ ] **First-launch onboarding**: Epic 01 adds a tip bubble; Epic 03 adds a wizard step. Should there be a *single* "tour" flow that introduces all enabled bucket features in order, vs piecemeal prompts? (Lean: piecemeal is fine, avoid wizard bloat)
- [ ] **Panel vs detached bucket**: README says "new tab on existing `SnorOhPanelWindow`, or new NSPanel when Bucket is detached". We haven't specified the detach UX — is there a pin icon on the panel? (Defer to Epic 01 implementation — TBD flag there)
- [ ] **Epic 06 Accessibility permission**: snippet expansion needs AX trust. If the user denies, we fall back to search-and-paste. But Epic 06 also lists the expansion UX as "Must". Should the search-fallback satisfy the Must, or is AX-required the spec? (Lean: search-fallback satisfies; AX is an accelerator, not a requirement)

---

## 11. Ship-Sequence Sanity Check

The README's 4-release roadmap is internally consistent post-split:

| Release | Epics | Value delivered | Ship risk |
|---|---|---|---|
| v1.0 | 01 + 02 | Functional + emotional MVP: the pet holds your stash | Medium — biggest chunk of work |
| v1.1 | 03 + 06 | Two quality-of-life wins that don't touch core | Low |
| v1.2 | 04 + 07 | Multi-bucket + inline transforms | Medium — 04 bumps schema |
| v2.0 | 05 + 08 | LAN sync + automation surface | Medium — requires existing HTTPServer audit |

**Sequence is defensible**: v1.0 validates the category, v1.1 ships cheap wins, v1.2 is a pro upgrade, v2.0 is the differentiator moat.

---

## 12. Actions Taken in This Revision

- ✅ Moved `MascotView.onDrop` wiring from Epic 02 → Epic 01
- ✅ Added "Drop onto mascot" Must to Epic 01 scope + acceptance + rollout
- ✅ Clarified Epic 02 as observer-only (`.bucketChanged` listener)
- ✅ Removed menu-bar duplication — Epic 01 owns, Epic 02 explicitly defers
- ✅ Codified `.bucketChanged` `userInfo["source"]` contract in README
- ✅ Codified `sourceBundleID` sentinel convention in README
- ✅ Relaxed Epic 05 dependency on Epic 04 from hard → soft
- ✅ Updated Epic 03 & 05 acceptance criteria to reference the sentinel convention

---

*If you make further cross-epic changes, edit this file's §2 (Actions Taken) rather than re-running the review.*
