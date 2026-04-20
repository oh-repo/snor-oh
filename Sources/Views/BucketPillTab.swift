import SwiftUI

/// Inline emoji picks for the tab context menu. Short and opinionated —
/// full emoji-picker integration is overkill for a tag selector.
enum BucketPillEmojiPicks {
    static let options: [String] = [
        "📦", "🎨", "💼", "🏠", "🎯", "🔖", "⭐", "🔥", "💡", "🛠",
    ]

    /// Labels for the 8 palette swatches — order-matched with
    /// `BucketPalette.swatches`. Kept adjacent to the emoji list because
    /// both are UI-level curations of the underlying data.
    static let swatchLabels: [String] = [
        "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray", "Brown",
    ]
}

/// A single pill in the `BucketTabsView`. Handles:
/// - Single-click → activate.
/// - Double-click → in-place TextField rename.
/// - Context menu → Rename / Color ▸ / Emoji ▸ / Archive / Delete…
///
/// Delete requests are forwarded via `onRequestDelete` since the sheet is
/// owned by `BucketTabsView` at the tab-bar level.
@MainActor
struct BucketPillTab: View {
    let bucket: Bucket
    let isActive: Bool
    let manager: BucketManager
    let onTap: () -> Void
    let onRequestDelete: () -> Void

    @State private var isRenaming: Bool = false
    @State private var editingName: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: bucket.colorHex) ?? .orange)
                .frame(width: 6, height: 6)
            if let emoji = bucket.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 11))
            }
            if isRenaming {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .focused($renameFocused)
                    .fixedSize()
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
            } else {
                Text(bucket.name)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((Color(hex: bucket.colorHex) ?? .orange).opacity(isActive ? 0.28 : 0.0))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    (Color(hex: bucket.colorHex) ?? .orange).opacity(isActive ? 0.55 : 0.0),
                    lineWidth: 1
                )
        )
        .contentShape(Capsule())
        .onTapGesture(count: 2) { beginRename() }
        .onTapGesture(count: 1) { if !isRenaming { onTap() } }
        .contextMenu { menuContents }
    }

    private func beginRename() {
        editingName = bucket.name
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != bucket.name {
            manager.renameBucket(id: bucket.id, to: trimmed)
        }
        isRenaming = false
    }

    @ViewBuilder
    private var menuContents: some View {
        Button("Rename") { beginRename() }

        Menu("Color") {
            ForEach(Array(BucketPalette.swatches.enumerated()), id: \.offset) { index, swatch in
                Button {
                    manager.setColor(id: bucket.id, colorHex: swatch)
                } label: {
                    Label(
                        BucketPillEmojiPicks.swatchLabels.indices.contains(index)
                            ? BucketPillEmojiPicks.swatchLabels[index]
                            : "Color \(index + 1)",
                        systemImage: bucket.colorHex == swatch ? "checkmark" : "circle.fill"
                    )
                }
            }
        }

        Menu("Emoji") {
            Button("None") { manager.setEmoji(id: bucket.id, emoji: nil) }
                .disabled(bucket.emoji == nil)
            Divider()
            ForEach(BucketPillEmojiPicks.options, id: \.self) { candidate in
                Button {
                    manager.setEmoji(id: bucket.id, emoji: candidate)
                } label: {
                    Text(candidate + (bucket.emoji == candidate ? "  ✓" : ""))
                }
            }
        }

        Divider()

        Button("Archive") {
            if manager.activeBucketID == bucket.id,
               let fallback = manager.activeBuckets.first(where: { $0.id != bucket.id })?.id {
                manager.setActiveBucket(id: fallback)
            }
            manager.archiveBucket(id: bucket.id)
        }
        .disabled(manager.activeBuckets.count <= 1)

        Button("Delete…", role: .destructive) { onRequestDelete() }
            .disabled(manager.activeBuckets.count <= 1)
    }
}
