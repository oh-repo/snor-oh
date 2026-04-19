# Epic 07 — Quick Actions on Items

**Tier**: 🔵 v2 power-user · **Complexity**: M (2 weeks) · **Depends on**: Epic 01

## Problem Statement

Dropover's "Instant Actions" — resize image, stitch PDFs, extract text, compress, share — are the #1 upsell in its marketing and a top power-user favorite across reviews ([research §Should-Have/Nice-to-Have](../../research/bucket-feature-research.md)). Once you have an image in the bucket, you often want to do *one* thing with it before sending it somewhere else (shrink it for email, flip to JPG, crop, OCR the text). Opening Preview.app breaks flow.

## Hypothesis

> We believe **a small menu of one-tap actions on bucket items** will dramatically increase drag-out-and-use rate vs drag-out-and-abandon. We'll know we're right when ≥20% of drops from the bucket are preceded by a quick action.

## Scope (MoSCoW)

Shipping a curated set. Pass if it's boring, fail if it's niche.

| Priority | Action | Applies to | Why |
|---|---|---|---|
| Must | Resize image (50% / 25% / custom) | image | Most common need |
| Must | Convert image format (PNG / JPG / HEIC) | image | File-attach compatibility |
| Must | Copy as plain text | text, richText | Universal pain point |
| Must | Extract text from image (Vision framework OCR) | image | Cheap with Apple's built-in |
| Must | Open with default app | all | Escape valve |
| Must | Share link (Dropover-cloud-style short URL) | all (opt-in service) | See "Deferred" below |
| Should | Rename item | all | Bucket hygiene |
| Should | Compress to ZIP (single or stack) | file, folder | Send-as-attachment flow |
| Should | Stitch multiple PDFs / images into one PDF | ≥2 selected PDFs or images | Power-user favorite |
| Should | Strip EXIF metadata | image | Privacy |
| Could | Rotate image | image | Minor |
| Could | Convert PDF to images | file (.pdf) | Minor |
| Won't | AI-powered actions (caption, summarize) | | Not our product |
| Won't | Video transcoding | | Too much scope |
| Won't | Background removal (Droppy's feature) | | Punt |

**Deferred**: "Share link" needs a hosted service for public URLs. In v1 of this epic, implement as: "copy item to clipboard as file-URL" plus optional integration with user's existing Dropbox/iCloud Drive/S3 via `rclone`-style configured target. Full hosted share link is its own epic.

## Users & JTBD

**Primary**: designers shrinking mocks for Figma comments, devs attaching logs to tickets, anyone emailing a photo.

**JTBD**: *When an item in my bucket needs one transform before it leaves, I want to do it inline without opening another app.*

## User Stories

1. I right-click a 4032×3024 iPhone photo → Resize → 50% → a new item appears in the bucket with the smaller version; original preserved.
2. I select 3 PDFs in the bucket → right-click → "Stitch to PDF" → a single combined PDF appears.
3. I right-click a screenshot of code → "Extract text" → the recognized text becomes a new `text` item in the bucket.
4. I select a file → "Compress to ZIP" → a `.zip` item appears, ready to drag out.

## UX Flow

```
Right-click item card → context menu:
  Quick Look
  Rename
  Copy as plain text
  ─────────────
  Actions ▸
    Resize image ▸
      50%
      25%
      Custom...
    Convert to ▸
      PNG
      JPG
      HEIC
    Extract text
    Strip EXIF
    Compress to ZIP
    Stitch with... ▸       (only if ≥1 other PDF/image)
  ─────────────
  Open with default
  Share link
  ─────────────
  Pin
  Move to ▸
  Delete
```

Multi-select (⌘+click / ⇧+click) enables the batch actions (Compress to ZIP, Stitch).

## Acceptance Criteria

- [ ] Actions run off `@MainActor` on a background `Task` when processing >1 MB or multiple files
- [ ] Result items preserve source item's provenance (new item's metadata records "derived from <source-item-id>")
- [ ] Original item never destructively modified
- [ ] Each action shows progress if it takes >500 ms (spinner on the source card)
- [ ] Resize: preserves aspect, uses `vImage` high-quality scaling
- [ ] Convert: uses `ImageIO` — supports PNG, JPEG, HEIC, TIFF
- [ ] Extract text: uses `VNRecognizeTextRequest` with `.accurate` mode, en-US + user's locale
- [ ] Compress: standard deflate .zip via `Compression` or shell out to `zip`
- [ ] Stitch PDFs: uses `PDFKit.PDFDocument.insert(_:at:)`
- [ ] Strip EXIF: removes everything except orientation
- [ ] Actions never network — all local-processing only (this epic)
- [ ] Errors surface as a red speech bubble + log via `Log.app`

## Data Model

Minor addition to link derived items:

```swift
public struct BucketItem {
    // existing ...
    public var derivedFromItemID: UUID?        // set when created by a quick action
    public var derivedAction: String?          // e.g. "resize:50", "extractText", "stitch"
}
```

No new top-level types. Actions are implemented as pure functions returning a new `BucketItem`.

## Action Interface

```swift
// Sources/Core/Actions/QuickAction.swift

public protocol QuickAction {
    static var id: String { get }
    static var title: String { get }
    static func appliesTo(_ items: [BucketItem]) -> Bool
    static func perform(_ items: [BucketItem], context: ActionContext) async throws -> [BucketItem]
}

public struct ActionContext: Sendable {
    let bucketStore: BucketStore
    let destinationBucketID: UUID
}

// Example:
public enum ResizeImageAction: QuickAction {
    public static var id = "resize-image"
    public static var title = "Resize image"

    public static func appliesTo(_ items: [BucketItem]) -> Bool {
        items.allSatisfy { $0.kind == .image }
    }

    public static func perform(_ items: [BucketItem], context: ActionContext) async throws -> [BucketItem] {
        // ...
    }
}
```

Registry:

```swift
public enum QuickActionRegistry {
    public static let all: [any QuickAction.Type] = [
        ResizeImageAction.self,
        ConvertImageAction.self,
        ExtractTextAction.self,
        StripExifAction.self,
        CompressZipAction.self,
        StitchPDFAction.self,
        CopyAsPlainTextAction.self,
        RenameAction.self,
    ]
}
```

## Implementation Notes

| Concern | Fit |
|---|---|
| Long-running tasks | `Task.detached` with explicit `@MainActor` hop on completion to update `BucketManager` |
| Image pipeline | `ImageIO` + `CoreImage` for conversion and resize. Matches existing SpriteCache image patterns. |
| OCR | Framework: `Vision`. Localization: follow user's `Locale.current` + en. Results: Copy as a new `.text` item. |
| PDF stitch | `PDFKit` — import of framework already exists if any PDF handling is in place; otherwise it's a system framework, no build change |
| Progress | Add `isProcessing: Bool` to `BucketItem` as transient (non-Codable) or a parallel `Set<UUID>` in `BucketManager.processingItemIDs` |
| Menu building | Use `onRightClick` → SwiftUI Menu, dynamically filtered by `appliesTo` |
| Multi-select | Extend `BucketItemCard` to participate in a selection set held by `BucketView` |

**Concurrency**: action `perform` is `async`. Each action uses `Task.detached(priority: .userInitiated)` and awaits. Swift 6 strict — no shared mutable state leaks.

## Out of Scope

- AI-powered actions (caption, summarize, translate) — not the product
- Video transcoding / encoding
- Cloud share service with hosted URLs — separate epic (needs backend decision)
- Background removal (visual ML)
- Batch rename with regex / patterns
- "Watch folder and auto-act" — that's Epic 08's watched folders
- Custom user-defined actions / scripts

## Open Questions

- [ ] Default JPEG quality on convert — 85 or 90? (Lean: 85, tweakable in settings)
- [ ] Should derived items be auto-pinned so the source can expire? (Lean: no, user decides)
- [ ] OCR result gets a new item; should the source screenshot remain? (Lean: yes, always non-destructive)
- [ ] Action telemetry — worth tracking which actions are used? (Lean: yes, anonymous counter per `QuickAction.id`)

## Rollout Plan

Group actions into shippable batches:

| # | Batch | Actions | Status |
|---|------|---------|--------|
| 1 | Image basics | Resize, Convert, Strip EXIF | ☐ |
| 2 | Text helpers | Copy as plain text, OCR extract text | ☐ |
| 3 | File ops | Compress ZIP, Rename | ☐ |
| 4 | PDF power | Stitch PDFs | ☐ |
| 5 | Context menu wiring + multi-select | `Views/BucketItemCard.swift` | ☐ |
| 6 | Progress + error UX | `Views/BucketView.swift` | ☐ |
| 7 | Release build verify | – | ☐ |

Ship each batch independently — no dependencies between batches.

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| Quick-action invocation rate per 10 bucket drags | ≥2 | Action counter |
| % of drops-out that were preceded by an action | ≥20% | Drop-out timestamp minus last action timestamp <60s |
| Most-used action share | Top 1 ≥30% | Histogram; confirms we're shipping the right ones |
| Action failure rate | <3% | Exception / error counter |
