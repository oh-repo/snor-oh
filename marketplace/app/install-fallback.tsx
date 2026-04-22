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
  const dialogRef = useRef<HTMLDialogElement | null>(null);
  const firstBtn = useRef<HTMLAnchorElement | null>(null);
  const titleId = `install-fallback-title-${packageId}`;

  useEffect(() => {
    const d = dialogRef.current;
    if (!d) return;
    if (open && !d.open) {
      d.showModal();
      firstBtn.current?.focus();
    } else if (!open && d.open) {
      d.close();
    }
  }, [open]);

  const downloadUrl = `/api/packages/${encodeURIComponent(packageId)}/download`;

  return (
    <dialog
      ref={dialogRef}
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(e) => {
        // close when backdrop is clicked — backdrop clicks hit the <dialog> itself
        if (e.target === dialogRef.current) onClose();
      }}
      className="rounded-2xl border border-[color:var(--border)] bg-[color:var(--bg)] p-0 shadow-xl backdrop:bg-black/40 w-full max-w-md"
    >
      <div className="p-6">
        <h2 id={titleId} className="text-lg font-semibold">
          {APP_NAME[format]} not installed?
        </h2>
        <p className="mt-2 text-sm opacity-70">
          Install the desktop app to one-click install packages straight from the marketplace.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <a
            ref={firstBtn}
            href={DOWNLOAD_URL[format]}
            target="_blank"
            rel="noreferrer"
            aria-label={`Get ${APP_NAME[format]} (opens in new tab)`}
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
    </dialog>
  );
}
