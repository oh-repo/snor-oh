"use client";

import { useCallback, useRef, useState } from "react";

type Message = { kind: "err" | "ok"; text: string } | null;

export function UploadForm() {
  const [file, setFile] = useState<File | null>(null);
  const [creator, setCreator] = useState("");
  const [busy, setBusy] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [message, setMessage] = useState<Message>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const acceptFile = useCallback((f: File | null | undefined) => {
    if (!f) return;
    const n = f.name.toLowerCase();
    if (!n.endsWith(".snoroh") && !n.endsWith(".animime")) {
      setMessage({ kind: "err", text: "File must end in .snoroh or .animime" });
      return;
    }
    setMessage(null);
    setFile(f);
  }, []);

  const onDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragging(false);
      acceptFile(e.dataTransfer.files?.[0]);
    },
    [acceptFile]
  );

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!file) {
      setMessage({ kind: "err", text: "Pick a .snoroh or .animime file first" });
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      const fd = new FormData();
      fd.set("file", file);
      fd.set("filename", file.name);
      fd.set("creator", creator);
      const res = await fetch("/api/upload", { method: "POST", body: fd });
      const data = await res.json();
      if (!res.ok) {
        setMessage({ kind: "err", text: data?.error?.message ?? "Upload failed" });
      } else {
        setMessage({ kind: "ok", text: "Shared! Refreshing gallery…" });
        setFile(null);
        setCreator("");
        if (inputRef.current) inputRef.current.value = "";
        setTimeout(() => location.reload(), 700);
      }
    } catch (e) {
      setMessage({ kind: "err", text: e instanceof Error ? e.message : "Upload failed" });
    } finally {
      setBusy(false);
    }
  }

  const sizeKb = file ? Math.round(file.size / 1024) : 0;

  return (
    <form
      onSubmit={submit}
      className="overflow-hidden rounded-2xl border border-[color:var(--card-border)] bg-[color:var(--card)] shadow-sm"
    >
      <div className="grid gap-0 md:grid-cols-[1fr_320px]">
        {/* drop zone */}
        <label
          onDragOver={(e) => {
            e.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
          className={[
            "relative flex min-h-[200px] cursor-pointer flex-col items-center justify-center gap-3 border-b border-dashed border-[color:var(--border)] px-6 py-10 text-center transition md:border-b-0 md:border-r",
            dragging
              ? "bg-[color:var(--accent)]/10"
              : "bg-[color:var(--bg-subtle)] hover:bg-[color:var(--bg-subtle)]/70",
          ].join(" ")}
        >
          <input
            ref={inputRef}
            type="file"
            accept=".snoroh,.animime,application/json"
            className="absolute inset-0 cursor-pointer opacity-0"
            onChange={(e) => acceptFile(e.target.files?.[0])}
          />
          <UploadIcon />
          {file ? (
            <div className="space-y-1">
              <div className="font-mono text-sm">{file.name}</div>
              <div className="font-mono text-[11px] opacity-50">{sizeKb} KB · ready</div>
            </div>
          ) : (
            <div className="space-y-1">
              <div className="text-sm font-medium">Drop a package here</div>
              <div className="font-mono text-[11px] opacity-50">
                or click · .snoroh / .animime · max 2 MiB
              </div>
            </div>
          )}
        </label>

        {/* details + submit */}
        <div className="flex flex-col gap-3 p-6">
          <label className="flex flex-col gap-1.5">
            <span className="font-mono text-[10px] uppercase tracking-widest opacity-50">
              Creator <span className="opacity-60">(optional)</span>
            </span>
            <input
              type="text"
              maxLength={40}
              value={creator}
              onChange={(e) => setCreator(e.target.value)}
              className="rounded-md border border-[color:var(--border)] bg-transparent px-3 py-2 text-sm focus:border-[color:var(--accent)] focus:outline-none focus:ring-1 focus:ring-[color:var(--accent)]"
              placeholder="@yourhandle"
            />
          </label>

          <div className="min-h-[36px] text-xs">
            {message && (
              <p
                className={
                  message.kind === "ok"
                    ? "rounded-md border border-green-500/30 bg-green-500/10 px-3 py-2 text-green-700 dark:text-green-400"
                    : "rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-red-700 dark:text-red-400"
                }
              >
                {message.text}
              </p>
            )}
          </div>

          <button
            type="submit"
            disabled={busy || !file}
            className="mt-auto inline-flex items-center justify-center gap-2 rounded-md bg-[color:var(--accent)] px-4 py-2.5 text-sm font-semibold text-[color:var(--accent-fg)] shadow-sm transition hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {busy ? (
              <>
                <Spinner />
                <span>Uploading…</span>
              </>
            ) : (
              <span>Share package</span>
            )}
          </button>

          <p className="font-mono text-[10px] leading-relaxed opacity-40">
            5 uploads/day per IP · validated server-side · anonymous
          </p>
        </div>
      </div>
    </form>
  );
}

function UploadIcon() {
  return (
    <svg
      width="32"
      height="32"
      viewBox="0 0 32 32"
      fill="none"
      className="opacity-60"
      aria-hidden
    >
      <path
        d="M16 22V8M16 8L10 14M16 8L22 14"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect
        x="5"
        y="24"
        width="22"
        height="2"
        rx="1"
        fill="currentColor"
      />
    </svg>
  );
}

function Spinner() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" className="animate-spin" aria-hidden>
      <circle cx="7" cy="7" r="5" stroke="currentColor" strokeWidth="2" opacity="0.25" fill="none" />
      <path
        d="M12 7a5 5 0 0 0-5-5"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}
