# Epic 06 — Notes & Text Snippets

**Tier**: 🟡 v1.5 differentiator · **Complexity**: S (1–1.5 weeks) · **Depends on**: Epic 01

## Problem Statement

Unclutter's Notes panel is cited as "note-taking becomes second nature" and Raycast/Clipboard Manager Pro users call text-expansion snippets "the reason I canceled TextExpander" ([research §Should-Have](../../research/bucket-feature-research.md#-should-have-high-value--mentioned-in-23-apps-strong-reviews)). Two related but distinct needs:

1. **Running scratchpad** — a single always-available text area for thoughts, todos, random strings that don't deserve a file.
2. **Reusable snippets** — short text blocks ("my signature", "bug report template") recalled via keyword trigger.

Both are low-effort adds on top of the bucket primitive.

## Hypothesis

> We believe **a lightweight notes panel + trigger-based snippet expansion inside the bucket** will reduce app-switching and replace TextExpander / Apple Notes for quick captures. We'll know we're right when >40% of users open the notes panel weekly and >15% create at least one snippet.

## Scope (MoSCoW)

| Priority | Capability | Why |
|---|---|---|
| Must | Plain-text notes panel — single scratchpad, autosaved | Unclutter's killer feature |
| Must | Search within notes | 20-year scratchpad problem |
| Must | Snippets as a new `BucketItem` kind with a `trigger` keyword | Text expansion surface |
| Must | Snippet expansion: type `;;sig` in any app, hit hotkey → expand to full content | Core expansion UX |
| Should | Multiple notes (tabs) — up to 10 | Organization without becoming a notes app |
| Should | Markdown-lite rendering in notes view (headers, bullets only) | Readability |
| Should | Export note as `.txt` or `.md` to Finder | Escape valve |
| Could | Apple Notes sync (two-way) — NotchPad's feature | Defer unless users ask |
| Won't | Rich text / images in notes | We are not a notes app |
| Won't | System-wide silent expansion (intercepting keystrokes) — that's TextExpander territory and requires accessibility permission nightmare | Use hotkey-triggered expansion only |
| Won't | Snippet sharing across peers | Can add in Epic 05's follow-up |

## Users & JTBD

**Primary** (notes): any snor-oh user who wants a scratchpad without opening Notes, Obsidian, or a text file. **Primary** (snippets): users who type the same email closer, signature, Git commit template, or code boilerplate repeatedly.

**JTBD (notes)**: *When a thought or string strikes me mid-task, I want to capture it without breaking flow — and find it two hours later.*

**JTBD (snippets)**: *When I'm about to type the same block of text I typed yesterday, I want to summon it with 3 keystrokes.*

## User Stories

1. I press ⌃⌥N (notes hotkey), type "remember to call DB team about latency", press Esc — saved, panel hides.
2. I hit ⌃⌥B, tap Notes tab, search "DB" — my note appears; I copy the line into Slack.
3. I create a snippet with trigger `;;mail-signature` and body "Best, Thanh · @thanh-dong". In Gmail compose, I type `;;mail-signature` and press ⌃⌥V → the line replaces the trigger.
4. I have 3 notes: "work-todo", "reading-list", "ideas" — tabbed in the notes panel.

## UX Flow

```
Bucket panel now has 3 tabs on the sidebar:
  [ Items | Notes | Snippets ]

Items      — existing bucket grid (Epic 01)
Notes      — tabbed scratchpad(s), typewriter-minimal
Snippets   — list of triggers + edit panel

Snippet expansion (in any app):
  1. User types "body ending with trigger keyword"
  2. User hits ⌃⌥V (expansion hotkey)
  3. snor-oh reads the last N chars from the focused app via Accessibility
     (if permission granted) OR from the clipboard (fallback: user Cmd-A, Cmd-C first)
  4. Matches trigger regex; if matched, types the expansion via CGEvent synthesis

  OR simpler fallback path (no Accessibility permission):
  1. User invokes snor-oh → Snippets tab, searches trigger, hits Enter
  2. Expansion is copied to clipboard, auto-pasted into focused app via CGEvent Cmd-V
```

## Acceptance Criteria

**Notes**
- [ ] Up to 10 notes, each with a name (editable)
- [ ] Autosave 500 ms after last keystroke
- [ ] Full-text search across all notes; results highlight the match in-context
- [ ] Markdown-lite render: `# header`, `## h2`, `- bullet`, `*italic*`, `**bold**`. Ignores everything else.
- [ ] Export-as-file via share button per note
- [ ] Dedicated hotkey ⌃⌥N opens panel on Notes tab with cursor in focused note
- [ ] Notes survive app crash (persisted on every autosave)

**Snippets**
- [ ] Snippet schema: `trigger: String (unique)`, `body: String`, `name: String`, `createdAt: Date`
- [ ] Trigger prefix convention: `;;` (documented, not enforced — user can use anything)
- [ ] Expansion via hotkey ⌃⌥V:
  - Primary path (Accessibility permission granted): read last ~64 chars from focused element, match trigger at end, replace via CGEvent synthesis
  - Fallback path (no permission): open Snippets tab with fuzzy search focused
- [ ] Snippet edit UI: name, trigger, body (plain text, 10k char max)
- [ ] Snippets list in Settings → Bucket → Snippets for manage/delete/export
- [ ] CSV import/export of snippets for migration from TextExpander

## Data Model

```swift
// Sources/Core/BucketTypes.swift — extend

public enum BucketItemKind: String, Codable, Sendable {
    case file, folder, image, url, text, richText, color
    case note, snippet                             // NEW
}

public struct Note: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var body: String                        // plain text with md-lite
    public var createdAt: Date
    public var updatedAt: Date
}

public struct Snippet: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var trigger: String                     // e.g. ";;sig"
    public var body: String
    public var createdAt: Date
    public var useCount: Int = 0
}

// BucketManager gets two new collections:
@Observable
public final class BucketManager {
    // existing ...
    public private(set) var notes: [Note] = []
    public private(set) var snippets: [Snippet] = []

    public func upsertNote(_ note: Note)
    public func deleteNote(_ id: UUID)
    public func upsertSnippet(_ snippet: Snippet)
    public func deleteSnippet(_ id: UUID)
    public func expandSnippet(matching: String) -> Snippet?
}
```

**Storage**:

```
~/.snor-oh/buckets/
├── notes.json           # [Note]
├── snippets.json        # [Snippet]
└── ...
```

## Implementation Notes

| Concern | Fit |
|---|---|
| Notes editor | SwiftUI `TextEditor` wrapped in custom view with markdown-lite rendering via `AttributedString` on display, raw text on edit (toggle with a small eye icon). |
| Autosave | Debounced 500ms — same pattern as `BucketStore` debounce. |
| Snippet hotkey | New registered Carbon event via `HotkeyRegistrar`. Distinct from bucket toggle. |
| Accessibility permission | Use `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — prompts user once. If denied, fall back to search-and-paste flow. |
| Expansion typing | `CGEventCreateKeyboardEvent` synthesis. Known-fragile on Secure Input contexts (1Password, Terminal sudo) — detect via `IsSecureEventInputEnabled()` and abort with a bubble warning. |
| Import/Export | CSV parser on a background queue. Standard format: `name,trigger,body` with quoted body. |
| Markdown-lite renderer | ~50 lines of regex → `AttributedString`. No dependency. |

**Concurrency**: Notes and Snippet operations on `@MainActor`. Storage via the same `BucketStore` actor.

## Out of Scope

- Rich text / image embedding in notes — we're not Apple Notes
- System-wide silent expansion (constant keylogging) — privacy boundary
- Snippet variables (`{{clipboard}}`, `{{cursor}}`, `{{date}}`) → add in Epic 08 if users request
- Apple Notes / Obsidian sync → different product
- Collaborative notes / shared snippets across peers → Epic 05 follow-up

## Open Questions

- [ ] Markdown-lite or plain text only? (Lean: plain with optional md-render toggle)
- [ ] Should snippet hotkey and bucket hotkey be distinct by default? (Lean: yes — ⌃⌥B bucket, ⌃⌥N notes, ⌃⌥V snippet expand)
- [ ] If the user already has TextExpander installed, detect and warn about conflicts? (Lean: no, leave it to the user)
- [ ] Snippet placeholder variables — ship with or without `{{clipboard}}`? (Lean: without in this epic; Epic 08)

## Rollout Plan

| # | Task | Files | Done |
|---|------|-------|------|
| 1 | Add `Note` and `Snippet` types | `Core/BucketTypes.swift` | ☐ |
| 2 | Extend `BucketManager` with notes/snippets CRUD | `Core/BucketManager.swift` | ☐ |
| 3 | Persist notes.json + snippets.json via `BucketStore` | `Core/BucketStore.swift` | ☐ |
| 4 | Notes SwiftUI view with tabs, autosave, search | `Views/BucketNotesView.swift` | ☐ |
| 5 | Markdown-lite renderer | `Views/MarkdownLite.swift` | ☐ |
| 6 | Snippets list & edit UI | `Views/BucketSnippetsView.swift` | ☐ |
| 7 | Dedicated notes hotkey ⌃⌥N | `Util/HotkeyRegistrar.swift` | ☐ |
| 8 | Snippet expansion hotkey ⌃⌥V, Accessibility detection, CGEvent typer | `Util/SnippetExpander.swift` | ☐ |
| 9 | Secure input detection + graceful fallback | `Util/SnippetExpander.swift` | ☐ |
| 10 | Settings: snippets CSV import/export | `Views/SettingsView.swift` | ☐ |
| 11 | First-use Accessibility prompt in Setup wizard | `Views/SetupWizard.swift` | ☐ |
| 12 | Release build verify | – | ☐ |

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| % of users who open Notes weekly | >40% | Tab-switch counter |
| Avg notes per active user | ≥2 | Count of Note records |
| % of users who create ≥1 snippet within 14d | >15% | Snippet count |
| Snippet expansion success rate | >90% | (Expansions that completed) / (Attempts) |
