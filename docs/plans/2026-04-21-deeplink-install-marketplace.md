# Deeplink Install from Marketplace — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One-click install of a marketplace package into the matching desktop app via custom URL scheme (`animime://` / `snoroh://`), with a confirm dialog on the app side and a "not installed?" fallback modal on the web side.

**Architecture:** Marketplace card fires a format-matched deeplink + 1.5s visibility-timer fallback. ani-mime registers `animime://` via `tauri-plugin-deep-link`; snor-oh registers `snoroh://` via `CFBundleURLTypes` + `kAEGetURL`. Both apps fetch metadata from the existing `/api/packages/:id` endpoint, show a confirm dialog, fetch the bundle, and hand it to the existing importer.

**Tech Stack:** Next.js 15 (marketplace), Swift / AppKit / SwiftUI (snor-oh), Tauri 2 / Rust / React 19 (ani-mime).

**Worktrees:**

- snor-oh: `.worktrees/deeplink-install` on branch `feature/deeplink-install` (already created)
- ani-mime: created in Task 12

**Design doc:** `docs/plans/2026-04-21-deeplink-install-marketplace-design.md`

---

## Phase A — Marketplace (Next.js, inside snor-oh worktree)

### Task 1: Add deeplink URL builder

**Files:**
- Create: `marketplace/lib/deeplink.ts`

**No test runner** is configured in `marketplace/` (package.json confirms only
dev/build/lint/start). We deliberately skip a unit test for this two-function
pure-logic file — coverage is provided by the tsc type check + the Task 3
browser smoke. If someone later adds vitest to the marketplace, this file is
trivial to add a test for.

**Step 1: Implement**

```ts
// marketplace/lib/deeplink.ts
export type PkgFormat = "snoroh" | "animime";

const SCHEME: Record<PkgFormat, string> = {
  animime: "animime",
  snoroh: "snoroh",
};

export function buildInstallUrl(format: PkgFormat, id: string): string {
  return `${SCHEME[format]}://install?id=${encodeURIComponent(id)}&v=1`;
}

export const DOWNLOAD_URL: Record<PkgFormat, string> = {
  animime: "https://github.com/vietnguyenhoangw/ani-mime/releases/latest",
  snoroh: "https://github.com/thanh-dong/snor-oh/releases/latest",
};
```

**Step 2: Type-check**

```
cd marketplace && npx tsc --noEmit
```
Expected: no errors.

**Step 3: Commit**

```bash
git add marketplace/lib/deeplink.ts
git commit -m "marketplace: deeplink URL builder for install buttons"
```

---

### Task 2: Install-fallback modal component

**Files:**
- Create: `marketplace/app/install-fallback.tsx`

**Step 1: Implement**

```tsx
// marketplace/app/install-fallback.tsx
"use client";

import { useEffect, useRef } from "react";
import { DOWNLOAD_URL, type PkgFormat } from "@/lib/deeplink";

interface Props {
  open: boolean;
  format: PkgFormat;
  packageId: string;
  onClose: () => void;
}

const APP_NAME: Record<PkgFormat, string> = {
  animime: "ani-mime",
  snoroh: "snor-oh",
};

export function InstallFallback({ open, format, packageId, onClose }: Props) {
  const firstBtn = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (open) firstBtn.current?.focus();
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  const downloadUrl = `/api/packages/${encodeURIComponent(packageId)}/download`;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="install-fallback-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-2xl border border-[color:var(--border)] bg-[color:var(--bg)] p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 id="install-fallback-title" className="text-lg font-semibold">
          {APP_NAME[format]} not installed?
        </h2>
        <p className="mt-2 text-sm opacity-70">
          Install the desktop app to one-click install packages straight from the marketplace.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <a
            ref={firstBtn as unknown as React.RefObject<HTMLAnchorElement>}
            href={DOWNLOAD_URL[format]}
            target="_blank"
            rel="noreferrer"
            className="rounded-md border border-[color:var(--accent)] bg-[color:var(--accent)] px-3 py-1.5 font-mono text-[11px] uppercase tracking-widest text-[color:var(--accent-fg)]"
          >
            Get {APP_NAME[format]}
          </a>
          <a
            href={downloadUrl}
            download
            className="rounded-md border border-[color:var(--border)] px-3 py-1.5 font-mono text-[11px] uppercase tracking-widest"
          >
            Download package only
          </a>
          <button
            type="button"
            onClick={onClose}
            className="ml-auto rounded-md border border-transparent px-2 py-1 font-mono text-[11px] uppercase tracking-widest opacity-60 hover:opacity-100"
            aria-label="Close"
          >
            ✕
          </button>
        </div>
      </div>
    </div>
  );
}
```

**Step 2: Type-check**

```
cd marketplace && npx tsc --noEmit
```
Expected: no errors.

**Step 3: Commit**

```bash
git add marketplace/app/install-fallback.tsx
git commit -m "marketplace: install-fallback modal component"
```

---

### Task 3: Wire Install button into PackageCard

**Files:**
- Modify: `marketplace/app/gallery.tsx` (replace the single `<a download>` inside `PackageCard`)

**Step 1: Replace the card's action row with Install + Download + fallback state**

Replace the `<div className="mt-2 flex items-center justify-between gap-2">…</div>` block at the bottom of `PackageCard` with:

```tsx
<CardActions pkg={pkg} />
```

Add the new component at the bottom of `gallery.tsx`:

```tsx
import { useCallback, useEffect, useRef, useState } from "react";
import { buildInstallUrl } from "@/lib/deeplink";
import { InstallFallback } from "./install-fallback";

// ...existing imports/components unchanged above...

function CardActions({ pkg }: { pkg: PackageRow }) {
  const [fallback, setFallback] = useState(false);
  const timerRef = useRef<number | null>(null);

  const cancelTimer = useCallback(() => {
    if (timerRef.current != null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === "hidden") cancelTimer();
    };
    const onHide = () => cancelTimer();
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pagehide", onHide);
    return () => {
      cancelTimer();
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", onHide);
    };
  }, [cancelTimer]);

  const handleInstall = () => {
    cancelTimer();
    window.location.href = buildInstallUrl(pkg.format, pkg.id);
    timerRef.current = window.setTimeout(() => {
      if (document.visibilityState === "visible") setFallback(true);
    }, 1500);
  };

  const dateLabel = timeAgo(pkg.created_at);

  return (
    <>
      <div className="mt-2 flex items-center justify-between gap-2">
        <span className="font-mono text-[10px] opacity-50">{dateLabel}</span>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleInstall}
            className="rounded-md border border-[color:var(--accent)] px-2.5 py-1 font-mono text-[10px] uppercase tracking-widest transition hover:bg-[color:var(--accent)] hover:text-[color:var(--accent-fg)]"
            aria-label={`Install ${pkg.name}`}
          >
            install
          </button>
          <a
            href={`/api/packages/${pkg.id}/download`}
            download
            className="rounded-md border border-[color:var(--border)] px-2.5 py-1 font-mono text-[10px] uppercase tracking-widest transition hover:border-[color:var(--accent)]"
          >
            download
          </a>
        </div>
      </div>
      <InstallFallback
        open={fallback}
        format={pkg.format}
        packageId={pkg.id}
        onClose={() => setFallback(false)}
      />
    </>
  );
}
```

Remove the old `dateLabel` const from `PackageCard` (now inside `CardActions`).

**Step 2: Type-check**

```
cd marketplace && npx tsc --noEmit
```
Expected: no errors.

**Step 3: Manual smoke test**

```
cd marketplace && bun run dev
```

Open `http://localhost:3000`, click **install** on a card:

- On a machine without the app: modal should appear after 1.5s with two links.
- On a machine with the app (after Phase B/C): dialog should open in the app; web page visibility changes so modal should NOT appear.

**Step 4: Commit**

```bash
git add marketplace/app/gallery.tsx
git commit -m "marketplace: install button + visibility-timer fallback"
```

---

## Phase B — snor-oh (Swift, same worktree)

### Task 4: Register `snoroh://` URL scheme in Info.plist + project.yml

**Files:**
- Modify: `Info.plist`
- Modify: `project.yml`

**Step 1: Add CFBundleURLTypes to `Info.plist`**

Insert inside the top-level `<dict>`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.snoroh.deeplink</string>
        <key>CFBundleURLSchemes</key>
        <array><string>snoroh</string></array>
    </dict>
</array>
```

**Step 2: Mirror in `project.yml`**

Under the target's `info.properties`, add:

```yaml
CFBundleURLTypes:
  - CFBundleURLName: com.snoroh.deeplink
    CFBundleURLSchemes: [snoroh]
```

(Verify placement by reading adjacent Info keys — file a small cleanup if formatting drifts.)

**Step 3: Regenerate and build**

```
xcodegen generate
swift build
```
Expected: build succeeds. No test run yet.

**Step 4: Commit**

```bash
git add Info.plist project.yml
git commit -m "snor-oh: register snoroh:// URL scheme"
```

---

### Task 5: MarketplaceClient — add fetchMeta / fetchBundle / previewURL

**Files:**
- Modify: `Sources/Network/MarketplaceClient.swift`
- Create: `Tests/MarketplaceClientTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/MarketplaceClientTests.swift
import XCTest
@testable import SnorOhSwift

final class MarketplaceClientTests: XCTestCase {
    func testPreviewURLComposesFromBase() {
        let url = MarketplaceClient.previewURL(
            id: "abc", baseURL: "https://example.test"
        )
        XCTAssertEqual(url?.absoluteString,
                       "https://example.test/api/packages/abc/preview")
    }

    func testPreviewURLRejectsMalformedBase() {
        XCTAssertNil(MarketplaceClient.previewURL(id: "abc", baseURL: "::::"))
    }

    func testPackageMetaDecodesMinimal() throws {
        let json = #"""
        {"id":"abc","name":"Mochi","creator":"cat",
         "format":"snoroh","size_bytes":12345,
         "frame_counts":{"idle":4}}
        """#.data(using: .utf8)!
        let meta = try JSONDecoder().decode(
            MarketplaceClient.PackageMeta.self, from: json
        )
        XCTAssertEqual(meta.name, "Mochi")
        XCTAssertEqual(meta.format, "snoroh")
        XCTAssertEqual(meta.sizeBytes, 12345)
    }
}
```

**Step 2: Run — must fail**

```
swift test --filter MarketplaceClientTests
```
Expected: FAIL (`previewURL` / `PackageMeta` not found).

**Step 3: Extend `MarketplaceClient`**

Append to `Sources/Network/MarketplaceClient.swift`:

```swift
extension MarketplaceClient {
    struct PackageMeta: Decodable, Equatable {
        let id: String
        let name: String
        let creator: String?
        let format: String
        let sizeBytes: Int

        enum CodingKeys: String, CodingKey {
            case id, name, creator, format
            case sizeBytes = "size_bytes"
        }
    }

    static func previewURL(id: String, baseURL: String) -> URL? {
        let trimmed = baseURL
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: trimmed) else { return nil }
        comps.path = "/api/packages/\(id)/preview"
        return comps.url
    }

    static func fetchMeta(id: String, baseURL: String) async throws -> PackageMeta {
        let trimmed = baseURL
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: trimmed) else {
            throw UploadError.invalidURL
        }
        comps.path = "/api/packages/\(id)"
        guard let url = comps.url else { throw UploadError.invalidURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.invalidResponse
        }
        return try JSONDecoder().decode(PackageMeta.self, from: data)
    }

    static func fetchBundle(id: String, baseURL: String) async throws -> Data {
        let trimmed = baseURL
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: trimmed) else {
            throw UploadError.invalidURL
        }
        comps.path = "/api/packages/\(id)/download"
        guard let url = comps.url else { throw UploadError.invalidURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.invalidResponse
        }
        return data
    }
}
```

**Step 4: Re-run**

```
swift test --filter MarketplaceClientTests
```
Expected: PASS (3 tests).

**Step 5: Commit**

```bash
git add Sources/Network/MarketplaceClient.swift Tests/MarketplaceClientTests.swift
git commit -m "snor-oh: MarketplaceClient fetchMeta/fetchBundle/previewURL"
```

---

### Task 6: InstallCoordinator — URL parse + pending-prompt state

**Files:**
- Create: `Sources/Core/InstallCoordinator.swift`
- Create: `Tests/InstallCoordinatorTests.swift`

**Step 1: Write failing tests — pure parse only**

```swift
// Tests/InstallCoordinatorTests.swift
import XCTest
@testable import SnorOhSwift

final class InstallCoordinatorTests: XCTestCase {
    func testValidURLExtractsID() {
        XCTAssertEqual(
            InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=abc-123_X&v=1")!),
            "abc-123_X"
        )
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "animime://install?id=abc")!))
    }

    func testRejectsWrongHost() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://run?id=abc")!))
    }

    func testRejectsEmptyID() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=")!))
    }

    func testRejectsBadCharacters() {
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=a/b")!))
    }

    func testRejectsOverlyLongID() {
        let longID = String(repeating: "a", count: 65)
        XCTAssertNil(InstallCoordinator.extractID(from: URL(string: "snoroh://install?id=\(longID)")!))
    }
}
```

**Step 2: Run — must fail**

```
swift test --filter InstallCoordinatorTests
```
Expected: FAIL (symbol not found).

**Step 3: Implement (parse only; networking added in Task 7)**

```swift
// Sources/Core/InstallCoordinator.swift
import Foundation

@MainActor
final class InstallCoordinator: ObservableObject {
    static let shared = InstallCoordinator()
    @Published var pending: Prompt?

    struct Prompt: Identifiable, Equatable {
        let id: String
        let name: String
        let creator: String?
        let sizeBytes: Int
        let previewURL: URL
        let bundleData: Data
    }

    static func extractID(from url: URL) -> String? {
        guard url.scheme == "snoroh", url.host == "install" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let raw = comps?.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        guard !raw.isEmpty, raw.count <= 64,
              raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }
        return raw
    }
}
```

**Step 4: Re-run**

```
swift test --filter InstallCoordinatorTests
```
Expected: PASS (6 tests).

**Step 5: Commit**

```bash
git add Sources/Core/InstallCoordinator.swift Tests/InstallCoordinatorTests.swift
git commit -m "snor-oh: InstallCoordinator URL parsing + pending state"
```

---

### Task 7: InstallCoordinator — fetch + confirm

**Files:**
- Modify: `Sources/Core/InstallCoordinator.swift`

**Step 1: Extend the coordinator**

Add to `InstallCoordinator`:

```swift
// at top of file
import AppKit

extension InstallCoordinator {
    func handle(url: URL) {
        guard let id = Self.extractID(from: url) else { return }
        Task { await fetchAndPrompt(id: id) }
    }

    private func fetchAndPrompt(id: String) async {
        let base = UserDefaults.standard.string(forKey: DefaultsKey.marketplaceURL)
            ?? DefaultsDefault.marketplaceURL
        do {
            let meta = try await MarketplaceClient.fetchMeta(id: id, baseURL: base)
            guard meta.format == "snoroh" else {
                await MainActor.run {
                    BubbleManager.shared.show("Wrong format — that is an .animime package")
                }
                return
            }
            let bundle = try await MarketplaceClient.fetchBundle(id: id, baseURL: base)
            guard let preview = MarketplaceClient.previewURL(id: id, baseURL: base) else {
                return
            }
            await MainActor.run {
                self.pending = Prompt(
                    id: id,
                    name: meta.name,
                    creator: meta.creator,
                    sizeBytes: bundle.count,
                    previewURL: preview,
                    bundleData: bundle
                )
            }
        } catch {
            await MainActor.run {
                BubbleManager.shared.show("Marketplace fetch failed")
            }
        }
    }

    func confirm() {
        guard let p = pending else { return }
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(p.id).snoroh")
            try p.bundleData.write(to: tmp)
            try OhhExporter.importOhh(from: tmp)
            BubbleManager.shared.show("Installed \(p.name)")
        } catch {
            BubbleManager.shared.show("Install failed: \(error.localizedDescription)")
        }
        pending = nil
    }

    func cancel() { pending = nil }
}
```

> `DefaultsKey.marketplaceURL` (plain `static let`, not `rawValue`) and `DefaultsDefault.marketplaceURL` (`"https://snor-oh.vercel.app"`) are already defined in `Sources/Util/Defaults.swift`. Use them verbatim.

**Step 2: Build**

```
swift build
```
Expected: succeed. No new tests — networking path is integration-only.

**Step 3: Commit**

```bash
git add Sources/Core/InstallCoordinator.swift
git commit -m "snor-oh: InstallCoordinator fetch + confirm + cancel"
```

---

### Task 8: AppDelegate URL-event handler

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

**Step 1: Register handler in `applicationDidFinishLaunching(_:)`**

Add near the end of `applicationDidFinishLaunching`:

```swift
NSAppleEventManager.shared().setEventHandler(
    self,
    andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)
```

Add method to `AppDelegate`:

```swift
@objc func handleURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent: NSAppleEventDescriptor
) {
    guard
        let str = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
        let url = URL(string: str)
    else { return }

    Task { @MainActor in
        InstallCoordinator.shared.handle(url: url)
        self.showPanel()  // or whatever the existing method is named
    }
}
```

> Confirm the exact method name used to reveal the panel. Look in `AppDelegate` for the panel-toggle action and call that instead of inventing `showPanel`.

**Step 2: Build**

```
swift build
```

**Step 3: Manual smoke**

After the view (Task 9) and wiring (Task 10) land, we test end-to-end. For now confirm: no duplicate handler registrations, no warnings. Skip until later.

**Step 4: Commit**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "snor-oh: route snoroh:// URLs into InstallCoordinator"
```

---

### Task 9: InstallPromptView SwiftUI sheet

**Files:**
- Create: `Sources/Views/InstallPromptView.swift`

**Step 1: Implement**

```swift
// Sources/Views/InstallPromptView.swift
import SwiftUI

struct InstallPromptView: View {
    let prompt: InstallCoordinator.Prompt

    var body: some View {
        VStack(spacing: 16) {
            Text("Install from marketplace")
                .font(.headline)

            RemotePreview(url: prompt.previewURL)
                .frame(width: 128, height: 128)

            VStack(spacing: 4) {
                Text(prompt.name).font(.system(.title3, design: .rounded)).bold()
                if let c = prompt.creator, !c.isEmpty {
                    Text("by \(c)").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(prompt.sizeBytes / 1024) KB")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { InstallCoordinator.shared.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install") { InstallCoordinator.shared.confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}

private struct RemotePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data) else { return }
            image = img
        }
    }
}
```

> If a sprite-strip animated preview is strongly desired, swap `RemotePreview` for a call into the existing `AnimatedSpriteView` with an ad-hoc sheet built from the fetched image. For v1 a static first-frame preview is acceptable — the confirm dialog just needs to identify the package.

**Step 2: Build**

```
swift build
```

**Step 3: Commit**

```bash
git add Sources/Views/InstallPromptView.swift
git commit -m "snor-oh: InstallPromptView confirm sheet"
```

---

### Task 10: Wire sheet into panel view

**Files:**
- Modify: `Sources/Views/SnorOhPanelView.swift`

**Step 1: Attach `.sheet(item:)`**

Locate the top-level `VStack` (or equivalent) in `SnorOhPanelView.body`. Append:

```swift
.sheet(item: Binding(
    get: { InstallCoordinator.shared.pending },
    set: { if $0 == nil { InstallCoordinator.shared.cancel() } }
)) { prompt in
    InstallPromptView(prompt: prompt)
}
```

`InstallCoordinator` needs to be observed — if the view was not already holding it, add:

```swift
@ObservedObject private var installer = InstallCoordinator.shared
```

and read `installer.pending` inside the binding rather than `InstallCoordinator.shared.pending`.

**Step 2: Build + run**

```
swift build && swift run
```

Leave the app running. In another shell:

```
open 'snoroh://install?id=<a-real-marketplace-id>'
```

Expected: panel reveals, confirm sheet appears with name/creator/size. Cancel dismisses; Install imports and shows a bubble.

**Step 3: Commit**

```bash
git add Sources/Views/SnorOhPanelView.swift
git commit -m "snor-oh: host install confirm sheet on panel"
```

---

### Task 11: snor-oh release build verification

**Files:** none (build + manual verify)

**Step 1:**

```
bash Scripts/build-release.sh && open .build/release-app/snor-oh.app
```

**Step 2:** Deeplink test via `open 'snoroh://install?id=<id>'`. Verify:

- Panel becomes visible
- Confirm sheet shows preview, name, creator, size
- Install writes to `~/.snor-oh/custom-ohhs.json` + `~/.snor-oh/custom-sprites/`
- Bubble says "Installed <name>"
- Re-running with an `.animime` id triggers "Wrong format" bubble and no sheet
- Malformed URL (`snoroh://install?id=a/b`) is silently ignored

**Step 3:** No code changes → no commit. Log any regressions as fix-up commits.

---

## Phase C — ani-mime (Tauri, separate worktree)

### Task 12: Create ani-mime worktree

**Files:**
- Modify: `/Users/cuongtran/Desktop/repo/ani-mime/.gitignore`

**Step 1: Verify `.gitignore`**

```
cd /Users/cuongtran/Desktop/repo/ani-mime
grep -q "^\.worktrees/$" .gitignore || echo "MISSING"
```

If missing, append `.worktrees/` and commit:

```bash
printf "\n.worktrees/\n" >> .gitignore
git add .gitignore
git commit -m "chore: ignore .worktrees/"
```

**Step 2: Create worktree**

```
git worktree add .worktrees/deeplink-install -b feature/deeplink-install
cd .worktrees/deeplink-install
bun install
```

**Step 3: Baseline tests**

```
bunx vitest run
cd src-tauri && cargo check
```
Expected: all pre-existing tests pass; `cargo check` clean.

**Step 4:** No additional commit (worktree itself isn't tracked; `.gitignore` commit above covers the setup).

---

### Task 13: Register animime:// scheme

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/Info.plist`
- Modify: `src-tauri/tauri.conf.json`
- Modify: `src-tauri/capabilities/default.json`

**Step 1: Add plugin dep**

```toml
# src-tauri/Cargo.toml
[dependencies]
# ...existing...
tauri-plugin-deep-link = "2"
url = "2"
```

Run to regenerate lock:

```
cd src-tauri && cargo check
```

> Verify current Tauri version in `Cargo.toml`. If it is `"2.0"` family, the `tauri-plugin-deep-link = "2"` major matches. If Tauri is on a different major, resolve via `cargo search tauri-plugin-deep-link` and pick the matching version.

**Step 2: Info.plist**

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.ani-mime.deeplink</string>
    <key>CFBundleURLSchemes</key>
    <array><string>animime</string></array>
  </dict>
</array>
```

**Step 3: tauri.conf.json**

Inside `plugins` (create the object if absent):

```json
"deep-link": {
  "desktop": {
    "schemes": ["animime"]
  }
}
```

**Step 4: Capabilities**

Append to `src-tauri/capabilities/default.json` permissions array:

```json
"deep-link:default"
```

**Step 5: Build**

```
cd src-tauri && cargo check
bun run tauri build --debug
```

**Step 6: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/Info.plist src-tauri/tauri.conf.json src-tauri/capabilities/default.json
git commit -m "ani-mime: register animime:// scheme via deep-link plugin"
```

---

### Task 14: deeplink.rs — parse + fetch + emit

**Files:**
- Create: `src-tauri/src/deeplink.rs`

**Step 1: Implement**

```rust
// src-tauri/src/deeplink.rs
use tauri::{AppHandle, Emitter};
use url::Url;

const MARKETPLACE_BASE: &str = "https://snor-oh.vercel.app";

#[derive(serde::Serialize, Clone)]
pub struct InstallPromptPayload {
    pub id: String,
    pub name: String,
    pub creator: Option<String>,
    pub size_bytes: u64,
    pub preview_url: String,
    pub download_url: String,
}

pub fn extract_id(raw: &str) -> Option<String> {
    let url = Url::parse(raw).ok()?;
    if url.scheme() != "animime" { return None; }
    if url.host_str() != Some("install") { return None; }
    let id = url.query_pairs()
        .find(|(k, _)| k == "id")
        .map(|(_, v)| v.into_owned())?;
    if id.is_empty() || id.len() > 64 { return None; }
    if !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return None;
    }
    Some(id)
}

pub async fn handle(app: AppHandle, raw_url: String) {
    let Some(id) = extract_id(&raw_url) else { return };
    let meta_url = format!("{MARKETPLACE_BASE}/api/packages/{id}");
    let Ok(resp) = reqwest::get(&meta_url).await else {
        let _ = app.emit("install-error", "Marketplace fetch failed");
        return;
    };
    let Ok(meta) = resp.json::<serde_json::Value>().await else {
        let _ = app.emit("install-error", "Malformed marketplace response");
        return;
    };
    if meta["format"].as_str() != Some("animime") {
        let _ = app.emit("install-error", "Wrong format — that is a .snoroh package");
        return;
    }
    let payload = InstallPromptPayload {
        id: id.clone(),
        name: meta["name"].as_str().unwrap_or("").to_string(),
        creator: meta["creator"].as_str().map(String::from),
        size_bytes: meta["size_bytes"].as_u64().unwrap_or(0),
        preview_url: format!("{MARKETPLACE_BASE}/api/packages/{id}/preview"),
        download_url: format!("{MARKETPLACE_BASE}/api/packages/{id}/download"),
    };
    let _ = app.emit("install-prompt", payload);
}

#[cfg(test)]
mod tests {
    use super::extract_id;

    #[test]
    fn accepts_valid() {
        assert_eq!(extract_id("animime://install?id=abc-123_X&v=1").as_deref(),
                   Some("abc-123_X"));
    }
    #[test]
    fn rejects_wrong_scheme() {
        assert_eq!(extract_id("snoroh://install?id=abc"), None);
    }
    #[test]
    fn rejects_wrong_host() {
        assert_eq!(extract_id("animime://run?id=abc"), None);
    }
    #[test]
    fn rejects_bad_chars() {
        assert_eq!(extract_id("animime://install?id=a/b"), None);
    }
    #[test]
    fn rejects_too_long() {
        let long = "a".repeat(65);
        assert_eq!(extract_id(&format!("animime://install?id={long}")), None);
    }
}
```

**Step 2: Register module in `src-tauri/src/lib.rs`**

Add at the top with other `mod` lines:

```rust
mod deeplink;
```

**Step 3: Run tests**

```
cd src-tauri && cargo test deeplink
```
Expected: 5 tests pass.

**Step 4: Commit**

```bash
git add src-tauri/src/deeplink.rs src-tauri/src/lib.rs
git commit -m "ani-mime: deeplink URL parse + marketplace fetch"
```

---

### Task 15: Wire plugin + on_open_url in lib.rs

**Files:**
- Modify: `src-tauri/src/lib.rs`

**Step 1: Builder chain**

In the `tauri::Builder::default()` chain inside `run()`:

```rust
.plugin(tauri_plugin_deep_link::init())
```

Inside the existing `.setup(|app| { ... })` (append to the end, before `Ok(())`):

```rust
use tauri_plugin_deep_link::DeepLinkExt;
let handle = app.handle().clone();
app.deep_link().on_open_url(move |event| {
    for url in event.urls() {
        let h = handle.clone();
        let raw = url.to_string();
        tauri::async_runtime::spawn(crate::deeplink::handle(h, raw));
    }
});
```

**Step 2: Build**

```
cd src-tauri && cargo check
bun run tauri build --debug
```

**Step 3: Manual deeplink check (no UI yet — just Rust dispatch)**

Run the debug app, then:

```
open 'animime://install?id=<real-id>'
```

Tail logs to confirm `install-prompt` was emitted (use existing `tauri-plugin-log` file path per `ani-mime/CLAUDE.md`).

**Step 4: Commit**

```bash
git add src-tauri/src/lib.rs
git commit -m "ani-mime: route animime:// URLs to deeplink handler"
```

---

### Task 16: useInstallPrompt hook

**Files:**
- Create: `src/hooks/useInstallPrompt.ts`
- Create: `src/__tests__/hooks/useInstallPrompt.test.ts`

**Step 1: Failing test**

```ts
// src/__tests__/hooks/useInstallPrompt.test.ts
import { renderHook, act } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { useInstallPrompt } from "../../hooks/useInstallPrompt";

type Handler = (e: { payload: unknown }) => void;
const handlers: Record<string, Handler> = {};

vi.mock("@tauri-apps/api/event", () => ({
  listen: (name: string, fn: Handler) => {
    handlers[name] = fn;
    return Promise.resolve(() => { delete handlers[name]; });
  },
}));

describe("useInstallPrompt", () => {
  it("captures install-prompt event payloads", async () => {
    const { result } = renderHook(() => useInstallPrompt());
    await new Promise((r) => setTimeout(r, 0));
    act(() => handlers["install-prompt"]({
      payload: {
        id: "abc",
        name: "Cat",
        creator: "me",
        size_bytes: 1024,
        preview_url: "/p",
        download_url: "/d",
      },
    }));
    expect(result.current.prompt?.name).toBe("Cat");
    act(() => result.current.clear());
    expect(result.current.prompt).toBeNull();
  });
});
```

**Step 2: Run — must fail**

```
bunx vitest run src/__tests__/hooks/useInstallPrompt.test.ts
```
Expected: FAIL (module missing).

**Step 3: Implement**

```ts
// src/hooks/useInstallPrompt.ts
import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";

export interface InstallPromptPayload {
  id: string;
  name: string;
  creator: string | null;
  size_bytes: number;
  preview_url: string;
  download_url: string;
}

export function useInstallPrompt() {
  const [prompt, setPrompt] = useState<InstallPromptPayload | null>(null);

  useEffect(() => {
    const offPromise = listen<InstallPromptPayload>(
      "install-prompt",
      (e) => setPrompt(e.payload),
    );
    return () => { offPromise.then((fn) => fn()); };
  }, []);

  return { prompt, clear: () => setPrompt(null) };
}
```

**Step 4: Re-run**

```
bunx vitest run src/__tests__/hooks/useInstallPrompt.test.ts
```
Expected: PASS.

**Step 5: Commit**

```bash
git add src/hooks/useInstallPrompt.ts src/__tests__/hooks/useInstallPrompt.test.ts
git commit -m "ani-mime: useInstallPrompt hook for deeplink payload"
```

---

### Task 17: InstallPromptDialog component

**Files:**
- Create: `src/components/InstallPromptDialog.tsx`

**Step 1: Implement**

```tsx
// src/components/InstallPromptDialog.tsx
import { useEffect, useRef, useState } from "react";
import type { InstallPromptPayload } from "../hooks/useInstallPrompt";
import { useCustomMimes } from "../hooks/useCustomMimes";

interface Props {
  prompt: InstallPromptPayload | null;
  onDone: () => void;
}

export function InstallPromptDialog({ prompt, onDone }: Props) {
  const { importFromBytes } = useCustomMimes();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const firstBtn = useRef<HTMLButtonElement | null>(null);

  useEffect(() => { if (prompt) firstBtn.current?.focus(); }, [prompt]);

  if (!prompt) return null;

  const handleInstall = async () => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(prompt.download_url);
      if (!res.ok) throw new Error(`Download failed (HTTP ${res.status})`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      await importFromBytes(bytes, `${prompt.name}.animime`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="install-title"
      data-testid="install-prompt-dialog"
      className="install-prompt"
    >
      <div className="install-prompt__card">
        <h2 id="install-title">Install from marketplace</h2>
        <img
          src={prompt.preview_url}
          alt=""
          width={128}
          height={128}
          className="install-prompt__preview pixel"
        />
        <div className="install-prompt__meta">
          <div className="install-prompt__name">{prompt.name}</div>
          {prompt.creator && (
            <div className="install-prompt__creator">by {prompt.creator}</div>
          )}
          <div className="install-prompt__size">
            {Math.round(prompt.size_bytes / 1024)} KB
          </div>
        </div>
        {error && <div className="install-prompt__error" role="alert">{error}</div>}
        <div className="install-prompt__actions">
          <button
            ref={firstBtn}
            type="button"
            onClick={onDone}
            disabled={busy}
            data-testid="install-cancel"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleInstall}
            disabled={busy}
            data-testid="install-confirm"
          >
            {busy ? "Installing…" : "Install"}
          </button>
        </div>
      </div>
    </div>
  );
}
```

Add minimal styles inline or in a new `src/styles/install-prompt.css` imported from `App.tsx`. Example:

```css
.install-prompt {
  position: fixed; inset: 0;
  display: grid; place-items: center;
  background: rgba(0,0,0,0.4);
  z-index: 100;
}
.install-prompt__card {
  background: var(--bg);
  border-radius: 12px;
  padding: 1.5rem;
  min-width: 260px;
  display: grid; gap: 0.75rem; justify-items: center;
  box-shadow: 0 8px 24px rgba(0,0,0,0.3);
}
.install-prompt__actions { display: flex; gap: 0.5rem; margin-top: 0.5rem; }
.install-prompt__error { color: #c00; font-size: 0.8rem; }
```

**Step 2: Commit**

```bash
git add src/components/InstallPromptDialog.tsx src/styles/install-prompt.css
git commit -m "ani-mime: InstallPromptDialog component"
```

---

### Task 18: expose importFromBytes in useCustomMimes

**Files:**
- Modify: `src/hooks/useCustomMimes.ts`

**Step 1: Find existing import path**

Open `src/hooks/useCustomMimes.ts` and identify the function that currently takes a `File` or path and imports it (likely called from `SmartImport.tsx`). Extract the byte-accepting core and expose it:

```ts
// inside useCustomMimes, add to return value
importFromBytes: async (bytes: Uint8Array, filename: string) => {
  // write bytes to a temp file via @tauri-apps/plugin-fs, then delegate to
  // the existing import routine. Exact implementation depends on the current
  // helper — do NOT duplicate logic, refactor the file-import helper to accept
  // Uint8Array if possible.
}
```

> This is the one non-trivial refactor in the plan. Do not skip reading the existing code before editing.

**Step 2: Update existing tests**

If `useCustomMimes.test.ts` exercises the file path, add one case for the byte path that writes a known-good fixture from `public/` or `e2e/fixtures/`.

**Step 3: Run**

```
bunx vitest run src/__tests__/hooks/useCustomMimes.test.ts
```
Expected: PASS.

**Step 4: Commit**

```bash
git add src/hooks/useCustomMimes.ts src/__tests__/hooks/useCustomMimes.test.ts
git commit -m "ani-mime: accept Uint8Array in useCustomMimes import path"
```

---

### Task 19: Mount dialog in App.tsx

**Files:**
- Modify: `src/App.tsx`

**Step 1: Wire it**

```tsx
import { useInstallPrompt } from "./hooks/useInstallPrompt";
import { InstallPromptDialog } from "./components/InstallPromptDialog";
import "./styles/install-prompt.css";

// inside App component:
const { prompt, clear } = useInstallPrompt();

return (
  <>
    {/* existing layout */}
    <InstallPromptDialog prompt={prompt} onDone={clear} />
  </>
);
```

**Step 2: Type-check + run**

```
npx tsc --noEmit
bun run tauri dev
```

Use `open 'animime://install?id=<real-id>'`; expect dialog, install, mascot now animates with the new pet.

**Step 3: Commit**

```bash
git add src/App.tsx
git commit -m "ani-mime: host InstallPromptDialog in App"
```

---

### Task 20: ani-mime release verification

**Files:** none

**Step 1: Release build**

```
bun run tauri build && bash src-tauri/script/post-build-sign.sh
```

**Step 2: Manual verify:**

- `animime://install?id=<real-id>` shows the dialog
- Cancel closes without side effects
- Install downloads + saves under `~/.ani-mime/custom-mimes/` and mascot list includes the new pet
- `animime://install?id=<snoroh-id>` emits `install-error` with "Wrong format"
- `open 'animime://install?id=a/b'` is silently ignored (no dialog, no error)

**Step 3:** No code change → no commit. Fix-up commits for regressions only.

---

## Phase D — cross-repo end-to-end

### Task 21: Web-to-app smoke

**Files:** none

**Steps:**

1. In snor-oh worktree: `cd marketplace && bun run dev` (port 3000).
2. In snor-oh worktree root: `bash Scripts/build-release.sh && open .build/release-app/snor-oh.app`.
3. In ani-mime worktree: `bun run tauri dev` (or release build).
4. Upload one `.snoroh` and one `.animime` package through the existing upload form.
5. Click **install** on each card. Verify:
   - `.snoroh` card → snor-oh confirm sheet
   - `.animime` card → ani-mime confirm dialog
   - Both install correctly; both show bubbles; both appear in the app's pet list
6. With both apps quit, click **install** — 1.5s later the web fallback modal appears.

**Artifacts:** Capture screenshots or a quick screen recording for the PR description.

---

## Rollout

- snor-oh release: bump patch, update `CHANGELOG.md`, merge worktree branch, tag + release per snor-oh release process.
- ani-mime release: bump all 4 version files (see `ani-mime/CLAUDE.md`), merge worktree branch, tag + CI release, update Homebrew cask.
- Marketplace deploys automatically on merge to main.

## Rollback

- Feature is additive. Reverting the merge commits on each repo plus the marketplace commit cleanly reverts behavior. No data migrations involved.
