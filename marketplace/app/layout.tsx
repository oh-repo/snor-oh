import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "snor-oh marketplace — share mascot packages",
  description:
    "Browse and share .snoroh and .animime mascot packages for the snor-oh desktop companion.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
