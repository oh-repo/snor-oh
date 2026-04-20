# Epic 05 — Peer Sync via Bonjour

**Tier**: 🟡 v1.5 differentiator · **Complexity**: M (2 weeks) · **Depends on**: Epic 01 (hard); Epic 04 (soft — enables "send to named bucket on peer"; without it, receiver drops into active bucket only)

## Problem Statement

Yoink's iOS↔macOS Handoff is its single most-praised cross-device feature, and Paste justifies its $29.99/yr subscription mostly on iCloud sync ([research §Should-Have](../../research/bucket-feature-research.md#-should-have-high-value--mentioned-in-23-apps-strong-reviews)). snor-oh *already* has Bonjour peer discovery (`_snor-oh._tcp`) and an HTTP server on `:1425` — the infrastructure for moving things between two Macs on the same network is already deployed. Charging a subscription for iCloud would be absurd when a 200-line PR turns the existing visit channel into a bucket-share channel.

## Hypothesis

> We believe **zero-config bucket sharing between two snor-oh peers on the same LAN** will be our cheapest "oh wow" moment. We'll know we're right when >30% of users with 2+ discovered peers perform at least one cross-peer drop in their first month.

## Scope (MoSCoW)

| Priority | Capability | Why |
|---|---|---|
| Must | Send any bucket item to a selected peer | Core operation |
| Must | Receive bucket items from a peer (opt-in per peer, default asks) | Safety |
| Must | Sender UI: right-click → "Send to ▸ <peer list>" | Discoverable |
| Must | Receiver UI: incoming bubble "Alice sent you a file — accept?" | Trust gate |
| Must | Only share files, text, URLs, images. Never share clipboard auto-capture unless explicit. | Privacy |
| Should | Per-peer trust: remember "always accept from Alice" | Friction reduction |
| Should | Progress indicator for large files | UX |
| Could | Share an entire bucket (full snapshot) as a "drop" to a peer | Power user |
| Won't | Internet sync (requires account, NAT, identity) — LAN only | Complexity cliff |
| Won't | Continuous mirror/replication of a bucket across peers | That's Dropbox, not us |
| Won't | End-to-end encryption beyond what the LAN provides | LAN assumption, document this |

## Users & JTBD

**Primary**: A user who has snor-oh on a laptop *and* a desktop, or whose teammate next-desk also runs snor-oh. Single-user two-Mac setup is the most common case on launch.

**JTBD**: *When I'm at my desktop and I want something I just captured on my laptop, I want to grab it without using AirDrop, Messages, or a shared folder.*

## User Stories

1. I'm debugging on the desktop, spot a screenshot on my laptop's snor-oh bucket, right-click → "Send to Desktop-mac" — 2 seconds later it's in my desktop bucket.
2. A new peer appears (teammate joins), I get a bubble "Bob is nearby" (from existing visitor logic) — the first time he sends me something, I see an accept/deny modal.
3. I mark "Always accept from myself@laptop" once, and future sends from that peer auto-accept.
4. I disable "Allow receive" globally in settings when I'm on a conference-room WiFi.

## UX Flow

```
Sender                                        Receiver
─────────────────                             ──────────────────
Right-click item in bucket
  ↓
Menu: "Send to ▸"
  ↓
List of discovered peers (from PeerDiscovery)
  ↓
Click "desktop-mac"
  ↓
Item payload streamed over HTTP         →     Incoming bubble:
to peer's /bucket/receive endpoint             "desktop-mac sent file.png"
                                               [ Accept ] [ Deny ]
                                                 ↓
                                               Item added to active bucket
                                               mascot "catch" animation
```

## Acceptance Criteria

- [ ] New HTTP routes on `HTTPServer`:
  - `POST /bucket/receive` — receiver, accepts multipart (item JSON + optional file)
  - `GET /bucket/peer-info` — handshake, returns hostname + snor-oh version
  - `POST /bucket/accept/:transfer-id` — user-triggered acceptance after modal
- [ ] Sender "Send to" submenu lists all discovered peers from existing `PeerDiscovery`, sorted by recency
- [ ] Transfer max size: 50 MB (arbitrary; show error for larger and suggest manual transfer)
- [ ] Each incoming transfer creates a `PendingTransfer` record; panel shows a dedicated "Incoming" card until accept/deny
- [ ] Per-peer trust: `Set<String>` of trusted peer UUIDs, persisted in `BucketSettings.autoAcceptPeers`
- [ ] Settings → Bucket → "Peer sharing" section: global enable/disable, per-peer trust list with revoke
- [ ] If receiver has global enable off, sender gets 403 with reason; sender shows "peer is not accepting transfers"
- [ ] Progress bar in sender UI when file > 1 MB
- [ ] Transferred item's `sourceBundleID` stamped as `net.snor-oh.peer:<peer-uuid>` (see README sentinel convention); `.bucketChanged` posted with `source: "peer"`
- [ ] Documents: explicit README note that transfers are LAN-only, unencrypted (beyond WPA2), and trust is inherent to network identity

## Data Model

```swift
// Sources/Core/BucketTypes.swift — extend

public struct PendingTransfer: Identifiable, Codable, Sendable {
    public let id: UUID
    public let peerID: UUID                    // matches PeerInfo.id
    public let peerName: String
    public let item: BucketItem
    public let receivedAt: Date
    public var state: TransferState

    public enum TransferState: String, Codable, Sendable {
        case awaitingUser, accepted, denied, expired
    }
}

public struct BucketSettings: Codable, Sendable {
    // existing ...
    public var allowIncomingTransfers: Bool = true
    public var autoAcceptPeerIDs: Set<UUID> = []
    public var maxIncomingSizeBytes: Int64 = 50_000_000
}
```

## HTTP Wire Format

```http
POST /bucket/receive
Content-Type: multipart/mixed; boundary=snor
X-Snor-From-Peer: <peer-uuid>
X-Snor-From-Name: <hostname>

--snor
Content-Type: application/json

{ "item": { ...BucketItem JSON with fileRef.cachedPath elided... }, "transferID": "<uuid>" }
--snor
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="screenshot.png"

<binary bytes>
--snor--
```

Response: `202 Accepted` with body `{"transferID": "<uuid>", "state": "awaitingUser"}`.
If auto-accept: `200 OK` with body `{"transferID": "<uuid>", "state": "accepted"}`.

## Implementation Notes

| Concern | Fit |
|---|---|
| Transport | Reuse existing `HTTPServer` (`Sources/Core/HTTPServer.swift`) — add 3 routes. SwiftNIO is already configured. |
| Discovery | Reuse `PeerDiscovery` + `PeerInfo` — no new Bonjour records. |
| Sender | Extend existing `VisitManager` with `sendBucketItem(_:to:)` — mirrors the `sendVisit` pattern. |
| Payload | Use `URLSession.shared.uploadTask(with:fromFile:)` for large files; stream from sidecar `cachedPath`. |
| Receive handler | On `/bucket/receive` the server writes file bytes to a temp path, creates `PendingTransfer` on `BucketManager`, posts a `.bucketIncoming` notification. Panel displays an accept/deny card; on accept, file moves into bucket storage. |
| Auth | Current `:1425` server is bound to `127.0.0.1` — peer-facing server is a second NIO bootstrap bound to LAN interface, behind a Bonjour record. *Check existing code*: if `HTTPServer` already binds LAN-wide (for peer visit feature), reuse; otherwise add a second bootstrap. |
| Trust UI | Incoming modal is not a modal window — uses existing `BubbleManager` with tappable action buttons (same treatment as task-completion bubbles). |
| Privacy | Never send items whose `sourceBundleID` is in the global ignore list. |

**Concurrency**: all incoming transfer state mutations on `@MainActor`. File I/O in NIO's event loop as existing server already does.

## Out of Scope

- Internet / WAN sync (requires identity, relays, server-side)
- Mobile companion (iOS app) — mentioned in Yoink reviews but we don't have an iOS app yet
- Cross-peer bucket mirror (continuous sync)
- Encryption of payload at transport layer beyond network-layer WPA2 — document
- Multicast "send to everyone" — only direct peer-to-peer

## Open Questions

- [ ] Does `HTTPServer` currently bind LAN-wide for the visit feature? Read `Sources/Core/HTTPServer.swift` to confirm before choosing reuse vs second bootstrap.
- [ ] If sender can see peer but peer can't see sender (asymmetric Bonjour), how do we surface the error? (Lean: show "peer is unreachable" after 5s timeout)
- [ ] For auto-accept peers, do we still show a toast (non-blocking) so the user knows something arrived? (Lean: yes — bubble, no buttons)
- [ ] Rate limit: max incoming transfers per minute? (Lean: 10/min per peer, silent drop beyond with log)

## Rollout Plan

| # | Task | Files | Done |
|---|------|-------|------|
| 1 | Audit existing `HTTPServer` LAN binding & `VisitManager` send pattern | – (reading only) | ☐ |
| 2 | Add `PendingTransfer` type + `BucketSettings` extensions | `Core/BucketTypes.swift` | ☐ |
| 3 | Add 3 HTTP routes on server | `Core/HTTPServer.swift` | ☐ |
| 4 | Multipart parser for `/bucket/receive` | `Core/HTTPServer.swift` | ☐ |
| 5 | Extend `VisitManager` with bucket send | `Network/VisitManager.swift` | ☐ |
| 6 | Incoming transfer state on `BucketManager` + `.bucketIncoming` notification | `Core/BucketManager.swift` | ☐ |
| 7 | "Send to ▸" context menu listing peers | `Views/BucketItemCard.swift` | ☐ |
| 8 | Incoming accept/deny bubble with actions | `Views/SpeechBubble.swift` | ☐ |
| 9 | Settings: global toggle, per-peer trust list | `Views/SettingsView.swift` | ☐ |
| 10 | Progress indicator for large file sends | `Views/BucketItemCard.swift` | ☐ |
| 11 | End-to-end test with two sim'd peers | `Tests/PeerBucketTransferTests.swift` | ☐ |
| 12 | Release build verify, 2-machine smoke test | – | ☐ |

## Success Metrics

| Metric | Target | Method |
|---|---|---|
| % of multi-peer users who transfer at least once in first month | >30% | Count `sourceBundleID` starts with `net.snor-oh.peer` |
| Accept rate for non-trusted peer transfers | >80% | Accept / (Accept+Deny) counter |
| Transfer failure rate | <5% | Failure log |
| Median transfer time for <5MB file | <2 s | Timing in `VisitManager` |
