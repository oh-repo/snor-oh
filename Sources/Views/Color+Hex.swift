import SwiftUI

extension Color {
    /// Parses `#RRGGBB` and `#RRGGBBAA` (with or without leading `#`).
    /// Returns nil on any other shape so callers can fall back to a default.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            a = Double((v >> 24) & 0xFF) / 255.0
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8) & 0xFF) / 255.0
            b = Double(v & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8) & 0xFF) / 255.0
            b = Double(v & 0xFF) / 255.0
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
