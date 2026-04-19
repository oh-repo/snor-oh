# snor-oh

Native macOS desktop mascot that reacts to terminal and Claude Code activity. Tamagotchi-style panel with collapsible session list.

## Quick Reference

- **Build**: `swift build`
- **Run**: `swift run`
- **Test**: `swift test`
- **Release**: `bash Scripts/build-release.sh` (outputs `.build/release-app/snor-oh.app`)
- **XcodeGen**: `xcodegen generate` (creates .xcodeproj)
- **Min macOS**: 14.0 (Sonoma) — required for @Observable

## Workflow

After completing a task, always build a release package for testing:

```bash
bash Scripts/build-release.sh
```

Run with `open .build/release-app/snor-oh.app` to verify changes end-to-end.

## Architecture

```
Shell hooks (curl) → HTTP :1234 → SessionManager → SwiftUI Views
Claude Code ←stdio→ MCP server (Node.js) ←HTTP→ :1234 → SwiftUI Views
Bonjour (NWBrowser/NWListener) → PeerDiscovery → SessionManager → PanelView
```

### App (`Sources/App/`)

| File | Responsibility |
|------|---------------|
| `SnorOhApp.swift` | @main entry, delegates to AppDelegate |
| `AppDelegate.swift` | Menu bar tray (status summary + popover bubbles), panel lifecycle, server startup, bubble observing |

### Core (`Sources/Core/`)

| File | Responsibility |
|------|---------------|
| `Types.swift` | Status enum, Session, PeerInfo, VisitingDog, ProjectStatus, CustomOhhData, all Codable payloads |
| `SessionManager.swift` | `@Observable` state: sessions, projects, peers, visitors, usage. Posts `.statusChanged` on every state transition |
| `Watchdog.swift` | 2s timer: heartbeat timeout, service→idle, idle→sleep |
| `HTTPServer.swift` | SwiftNIO server on `127.0.0.1:1234`, all route handlers |
| `ClaudeCodeConfig.swift` | `@Observable` manager: reads/writes Claude Code plugins, skills, commands, MCP, hooks from `~/.claude/` |

### Views (`Sources/Views/`)

| File | Responsibility |
|------|---------------|
| `SnorOhPanelWindow.swift` | NSPanel: transparent panel window, position persistence, drag-to-reposition |
| `SnorOhPanelView.swift` | Tamagotchi layout: mascot hero (transparent stage) + speech bubble + glass session area (collapsible summary + project rows with status rails) |
| `MascotView.swift` | `AnimatedSpriteView` driven by SpriteEngine |
| `SpeechBubble.swift` | BubbleManager (@Observable, auto-dismiss, task completion messages) |
| `SettingsView.swift` | Settings: General (+ MCP install/uninstall), Ohh (pet selection + Smart Import), Claude Code, About |
| `ClaudeCodeSettingsView.swift` | Claude Code tab: plugins, skills, commands, MCP servers (global + per-project), hooks (grouped by event) |
| `SmartImportView.swift` | Smart Import sheet: sprite sheet upload, frame detection preview, per-status assignment with animation preview |
| `SettingsWindow.swift` | Resizable NSWindow wrapper |
| `SetupWizard.swift` | First-launch flow: Welcome → Installing → Done |

### Animation (`Sources/Animation/`)

| File | Responsibility |
|------|---------------|
| `SpriteConfig.swift` | `SpriteSheetInfo` struct: filename, frame count, frame width/height, row, subdirectory. Maps (pet, status) → sheet info |
| `SpriteCache.swift` | CGImage frame cache, extracts rectangular frames with row selection from PNG sprite sheets |
| `SpriteEngine.swift` | @Observable animation driver: 80ms/frame, auto-freeze on idle |

### Sprites (`Sources/Sprites/`)

| File | Responsibility |
|------|---------------|
| `CustomOhhManager.swift` | @Observable singleton: CRUD for custom pets, file storage in ~/.snor-oh/custom-sprites/ |
| `SmartImport.swift` | Sprite sheet processor: bg detection, row/column detection, frame extraction, grid packing |
| `OhhExporter.swift` | .snoroh file export/import (JSON with base64-encoded PNG per status) |

### Network (`Sources/Network/`)

| File | Responsibility |
|------|---------------|
| `GitStatus.swift` | Polls `git status --porcelain` per project (30s interval) |
| `PeerDiscovery.swift` | NWBrowser + NWListener for Bonjour peer discovery |
| `VisitManager.swift` | Sends visit/visit-end requests to peers |

### Setup (`Sources/Setup/`)

| File | Responsibility |
|------|---------------|
| `MCPInstaller.swift` | Copies server.mjs to ~/.snor-oh/mcp/, registers/unregisters in ~/.claude.json, status checks |
| `ClaudeHooks.swift` | Configures Claude Code hooks in ~/.claude/settings.json |

### Util (`Sources/Util/`)

| File | Responsibility |
|------|---------------|
| `Defaults.swift` | `DefaultsKey` enum: all UserDefaults key constants |
| `Logger.swift` | `Log` enum: OSLog wrappers (app, http, session, network, setup categories) |

## Panel Layout (Tamagotchi)

```
     [ animated sprite ]          ← transparent stage, no background
        "All done!"               ← speech bubble (capsule, centered)

  ┌─────────────────────────────┐
  │ ▾ 4 sessions         ●2 ●2 │ ← glass card, collapsible
  │─────────────────────────────│
  │ ▌ project-a                 │ ← status rail (left colored bar)
  │ ▌ project-b          busy   │
  │ ▌ project-c          svc    │
  └─────────────────────────────┘
```

- Mascot is the hero — centered, transparent background, glow optional
- Session area is a separate glass card (VisualEffectBackground + rounded corners)
- Summary bar: chevron + session count (left) + status breakdown dots (right)
- Project rows: left status rail (3px colored bar) + name + status label (non-idle only)
- Collapsed mode: mascot + one-line summary only

## Menu Bar

- Icon: pawprint + colored dots with session counts (variable-length NSStatusItem)
- Left-click: toggle panel visibility
- Right-click: context menu (Show, Settings, Quit)
- Popover bubbles: task completion and MCP say messages pop from icon when panel is hidden
- Updates via `.statusChanged` notification (no polling timer)

## Key Constants

- Heartbeat timeout: 40s
- Service display: 2s then auto-revert to idle
- Idle to sleep: 120s
- Watchdog interval: 2s
- Shell heartbeat: 20s
- Animation: 80ms/frame (12.5 fps), auto-freeze after 10s on idle/disconnected
- Built-in pets: sprite (default, PMD 12-animation), samurai (128px), hancock (128px)
- Panel width: 240/280/320px (compact/regular/large)
- Peer discovery: Bonjour `_snor-oh._tcp`

## Status Priority

`busy (4) > service (3) > idle (2) > visiting (1) > disconnected/searching/initializing (0)`

## Custom Pets

- **Metadata**: `~/.snor-oh/custom-ohhs.json` (JSON array of CustomOhhData)
- **Sprites**: `~/.snor-oh/custom-sprites/` (PNG files per status)
- **Smart Import**: Upload sprite sheet → auto-detect frames → assign per status → preview animation → save
- **ID format**: `custom-<UUID>`
- **Frame size**: Always 128px (grid-packed by SmartImport)
- `.snoroh` export is lossy: does not include source sheet or frame inputs

## Settings

- **General tab**: Theme, glow, bubbles, card size, auto-start, dock/tray visibility, MCP install/uninstall with status indicators
- **Ohh tab**: Nickname, display scale (0.5x–2x), pet selection grid, Smart Import button, .snoroh import/export
- **Claude Code tab**: Plugins (toggle + bundled skills), MCP servers (global + per-project), commands (content preview), standalone skills, hooks (grouped by event, own-hook protection)
- **About tab**: Version, dev mode (10-click secret), GitHub link

## Important Patterns

- **Timer pattern**: Always `Timer(timeInterval:...)` + `RunLoop.main.add(t, forMode: .common)` — never `Timer.scheduledTimer` + `RunLoop.main.add` (causes double-fire)
- **Notification-driven updates**: Status bar and panel react to `.statusChanged` posted by SessionManager — no polling
- **NSApp.setActivationPolicy**: Main-thread only; wrap in `DispatchQueue.main.async`
- **File I/O at launch**: `MCPInstaller.installServer()` + `ClaudeHooks.migrate()` run on background queue
- **Sprite orientation**: CG bitmap context stores row 0 = visual top. No flip needed for thumbnail generation — CG `draw()` handles orientation. Only `createStripFromFrames` flips for SpriteCache compatibility
- **Window shadow**: Panel window has `hasShadow = false` (transparent mascot stage — system shadow would outline the sprite)
- **MCP server path**: Release bundle stores at `Scripts/mcp-server/server.mjs` — `findBundledServer()` checks `"Scripts/mcp-server"` subdirectory first

## Testing

- Unit tests: `Tests/SessionManagerTests.swift` (19 tests)
- Run: `swift test`
