import { Gallery } from "./gallery";
import { UploadForm } from "./upload-form";

export const dynamic = "force-dynamic";

export default function Home() {
  return (
    <main className="min-h-screen">
      <div className="dot-grid">
        <div className="mx-auto max-w-6xl px-6 pb-10 pt-16 sm:pt-24">
          <header className="flex flex-col items-start gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-3">
              <Logo />
              <div>
                <div className="font-mono text-[11px] uppercase tracking-widest opacity-60">
                  snor-oh · marketplace
                </div>
                <h1 className="mt-1 text-3xl font-semibold tracking-tight sm:text-4xl">
                  Mascot packages,
                  <br className="hidden sm:block" />
                  <span className="text-[color:var(--accent)]"> share yours</span>.
                </h1>
              </div>
            </div>
            <div className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-widest opacity-60">
              <span className="inline-block h-2 w-2 rounded-full bg-[color:var(--accent)]" />
              <span>anonymous · free · rate-limited</span>
            </div>
          </header>
          <p className="mt-6 max-w-2xl text-sm leading-relaxed opacity-70">
            Upload any <code className="font-mono text-[color:var(--accent)]">.snoroh</code> or{" "}
            <code className="font-mono text-[color:var(--accent)]">.animime</code> bundle exported
            from the desktop app. Previews animate at the same 80&nbsp;ms/frame rate as the mascot
            itself. No accounts. 5 uploads per day per IP.
          </p>
        </div>
      </div>

      <section className="mx-auto max-w-6xl px-6">
        <UploadForm />
      </section>

      <section className="mx-auto max-w-6xl px-6 py-12">
        <div className="mb-6 flex items-baseline justify-between">
          <h2 className="font-mono text-[11px] uppercase tracking-widest opacity-60">
            Recently shared
          </h2>
          <span className="font-mono text-[11px] opacity-40">newest first</span>
        </div>
        <Gallery />
      </section>

      <footer className="mx-auto max-w-6xl px-6 pb-12 pt-4 font-mono text-[10px] uppercase tracking-widest opacity-40">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-[color:var(--border)] pt-6">
          <span>snor-oh · 2026</span>
          <span>·</span>
          <a
            href="https://github.com/thanh-dong/snor-oh"
            className="hover:text-[color:var(--accent)]"
          >
            github
          </a>
          <span>·</span>
          <span>packages validated server-side · max 2&nbsp;MiB</span>
        </div>
      </footer>
    </main>
  );
}

function Logo() {
  // 8x8 pixel mascot: small face with blush
  return (
    <div
      aria-hidden
      className="grid h-14 w-14 animate-bob shrink-0 grid-cols-8 gap-0 rounded-lg bg-[color:var(--bg-subtle)] p-1.5 shadow-sm ring-1 ring-[color:var(--border)]"
    >
      {PIXELS.map((row, y) =>
        row.split("").map((ch, x) => (
          <span
            key={`${y}-${x}`}
            className="h-1 w-1"
            style={{
              backgroundColor:
                ch === "#" ? "var(--fg)" :
                ch === "o" ? "var(--accent)" :
                "transparent",
            }}
          />
        ))
      )}
    </div>
  );
}

// tiny mascot sprite: # = dark, o = accent, . = transparent
const PIXELS = [
  "..####..",
  ".######.",
  "########",
  "#.####.#",
  "########",
  "#o####o#",
  ".######.",
  "..#..#..",
];
