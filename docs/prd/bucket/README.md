# Bucket Feature — PRD Index

The Bucket is snor-oh's utility surface: a single place to stash anything during daily work — files, clipboard, URLs, text, images. One product spec per epic, each implementation-ready.

Research backing all decisions: [`docs/research/bucket-feature-research.md`](../../research/bucket-feature-research.md).

## Epics

| # | Epic | Tier | Complexity | Depends | Ship Order |
|---|------|------|------------|---------|------------|
| 01 | [Core Bucket MVP](bucket-01-core-mvp.md) | 🟢 Must | M | – | 1 |
| 02 | [Mascot Integration](bucket-02-mascot-integration.md) | 🟢 Must | S | 01 | 2 |
| 03 | [Screenshot Auto-Catch](bucket-03-screenshot-autocatch.md) | 🟡 Should | S | 01 | 3 |
| 04 | [Multi-Bucket System](bucket-04-multi-bucket.md) | 🟡 Should | M | 01 | 4 |
| 05 | [Peer Sync via Bonjour](bucket-05-peer-sync.md) | 🟡 Should | M | 01 (04 soft) | 5 |
| 06 | [Notes & Text Snippets](bucket-06-notes-snippets.md) | 🟡 Should | S | 01 | 6 |
| 07 | [Quick Actions on Items](bucket-07-quick-actions.md) | 🔵 Could | M | 01 | 7 |
| 08 | [Power Features](bucket-08-power-features.md) | 🔵 Could | L | 01, 04 | 8 |

**Tier legend**: 🟢 v1 blocker · 🟡 v1.5 differentiator · 🔵 v2 power user

## North Star

> One panel. Anything draggable goes in. Anything draggable comes out. The pet reacts to what's inside.

## Shared Architecture Decisions (cross-epic)

Recorded once here; every epic inherits these.

| Decision | Choice | Rationale |
|---|---|---|
| Storage location | `~/.snor-oh/buckets/<bucket-id>/` | Sibling to existing `~/.snor-oh/custom-sprites/` — matches conventions in `AppDelegate` |
| Item payloads | JSON manifest + sidecar files (images, file copies) | Fits existing `OhhExporter` pattern |
| State | `@Observable BucketManager` singleton, registered alongside `SessionManager` | Matches existing `@Observable` pattern (SessionManager, BubbleManager, CustomOhhManager) |
| UI host | New tab on existing `SnorOhPanelWindow`, or new NSPanel when Bucket is detached | Reuses transparent-glass aesthetic already in `SnorOhPanelView` |
| Notifications | `NSNotification.Name.bucketChanged` with `userInfo["source"]` ∈ `{mascot, panel, clipboard, screenshot, peer, watched-folder, shortcut}` | Mirrors `.statusChanged`; the `source` tag lets Epic 02 pick catch-reaction intensity and Epic 08 route auto-expiry |
| Item origin | `BucketItem.sourceBundleID: String?` for real bundle IDs; non-app origins use reserved sentinels: `net.snor-oh.peer:<peer-uuid>`, `net.snor-oh.screenshot`, `net.snor-oh.watchedfolder:<folder-id>`, `net.snor-oh.shortcut`, `net.snor-oh.url-scheme` | Keeps a single field, avoids adding parallel enum until we actually need it |
| Drop target | Native `NSPasteboard` + `DropDelegate` | Zero 3rd-party; same stack as SwiftUI |
| Hotkey | Carbon `RegisterEventHotKey` with user-configurable binding | Already have shortcut infra via Defaults |
| Bonjour transport | Existing `_snor-oh._tcp` + `PeerDiscovery` + `HTTPServer :1425` | Do not add new transport |

## What We're Not Building (Ever)

- **Cloud account** — Bonjour peer sync only. iCloud Drive optional via user-chosen folder, not managed.
- **Paste sequences / queue** — Pastebot's territory, <5% of users need it.
- **AES-256 encryption** — macOS Keychain + sandbox is enough for a shelf utility. Add only if a user asks.
- **AI / OCR / summarization** — Not the product. snor-oh is a mascot, not an LLM client.
- **Cross-platform port** — macOS only. Full stop.

## Ship Sequence

```
v1.0 (6–8 weeks)   v1.1 (2 weeks)   v1.2 (3 weeks)   v2.0 (6 weeks)
┌──────────────┐   ┌────────────┐   ┌────────────┐   ┌──────────────┐
│ 01 Core MVP  │ → │ 03 Screens │ → │ 04 Multi   │ → │ 05 Peer Sync │
│ 02 Mascot    │   │ 06 Notes   │   │ 07 Actions │   │ 08 Power     │
└──────────────┘   └────────────┘   └────────────┘   └──────────────┘
```

Epic 02 ships alongside 01 because the mascot *is* the differentiator; without it this is just Dropover-with-extra-steps.

## Review

See [REVIEW.md](REVIEW.md) for the cross-epic consistency pass — feature ownership matrix, hotkey inventory, data-model evolution, dependency graph, open questions.

## Glossary

- **Bucket** — a named collection of items. v1 has one default bucket; v1.2 allows many.
- **Item** — one entry. Kind is `file | folder | image | url | text | richText | color | snippet | note`.
- **Stack** — items dropped together (same drag session), rendered as one card that expands.
- **Pin** — protects an item from auto-expiry / clear-all.

## How to Use These PRDs

Each PRD has a **Rollout** section with ordered tasks. Pick the epic, read the acceptance criteria, implement, verify against criteria. When done, check the box in the epic's rollout table. Cross-epic decisions stay here in this README.
