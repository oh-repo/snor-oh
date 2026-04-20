import SwiftUI

/// Settings sub-section that lists all buckets (active first, then
/// archived) with Rename / Archive-Restore / Delete controls and the
/// ⌃⌥1–⌃⌥9 keyboard-hint footer. The tab bar remains the primary
/// surface for bucket management; this list is for bulk admin.
@MainActor
struct BucketsManagementSection: View {
    @Bindable var manager: BucketManager

    @State private var showCreate: Bool = false
    @State private var editingBucketID: UUID? = nil
    @State private var deleteTarget: DeleteTarget? = nil

    /// Active buckets first in their current order (matches tab-bar order
    /// and keyboard-index assignment), then archived buckets.
    private var sortedBuckets: [Bucket] {
        manager.activeBuckets + manager.archivedBuckets
    }

    /// `⌃⌥N` label for an active bucket, or nil for archived / out-of-range.
    private func keyboardHint(for bucket: Bucket) -> String? {
        guard !bucket.archived else { return nil }
        guard let idx = manager.activeBuckets.firstIndex(where: { $0.id == bucket.id }),
              idx < 9 else { return nil }
        return "\u{2303}\u{2325}\(idx + 1)"
    }

    var body: some View {
        Section("Buckets") {
            ForEach(sortedBuckets) { bucket in
                BucketsManagementRow(
                    manager: manager,
                    bucket: bucket,
                    keyboardHint: keyboardHint(for: bucket),
                    onRename: { editingBucketID = bucket.id },
                    onRequestDelete: { deleteTarget = DeleteTarget(id: bucket.id) }
                )
            }

            HStack {
                Spacer()
                Button { showCreate = true } label: {
                    Label("New bucket", systemImage: "plus")
                }
                .popover(isPresented: $showCreate, arrowEdge: .top) {
                    BucketCreateSheet(isPresented: $showCreate) { name, color, emoji in
                        let id = manager.createBucket(name: name, colorHex: color, emoji: emoji)
                        manager.setActiveBucket(id: id)
                    }
                }
            }

            Text("\u{2303}\u{2325}1 – \u{2303}\u{2325}9 switches to the corresponding bucket in order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $deleteTarget) { target in
            BucketDeleteSheet(
                manager: manager,
                targetID: target.id,
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                )
            )
        }
        .sheet(item: Binding(
            get: { editingBucketID.map { EditingTarget(id: $0) } },
            set: { editingBucketID = $0?.id }
        )) { target in
            BucketRenameSheet(
                manager: manager,
                bucketID: target.id,
                isPresented: Binding(
                    get: { editingBucketID != nil },
                    set: { if !$0 { editingBucketID = nil } }
                )
            )
        }
    }

    private struct DeleteTarget: Identifiable { let id: UUID }
    private struct EditingTarget: Identifiable { let id: UUID }
}

// MARK: - Management row

@MainActor
private struct BucketsManagementRow: View {
    let manager: BucketManager
    let bucket: Bucket
    let keyboardHint: String?
    let onRename: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: bucket.colorHex) ?? .orange)
                .frame(width: 10, height: 10)

            if let emoji = bucket.emoji, !emoji.isEmpty {
                Text(emoji)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    Text("\(bucket.items.count) item\(bucket.items.count == 1 ? "" : "s")")
                    if bucket.archived {
                        Text("archived").foregroundStyle(.orange)
                    } else if let hint = keyboardHint {
                        Text(hint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Rename", action: onRename)
                .buttonStyle(.borderless)

            if bucket.archived {
                Button("Restore") { manager.restoreBucket(id: bucket.id) }
                    .buttonStyle(.borderless)
            } else {
                Button("Archive") {
                    if manager.activeBucketID == bucket.id,
                       let fallback = manager.activeBuckets.first(where: { $0.id != bucket.id })?.id {
                        manager.setActiveBucket(id: fallback)
                    }
                    manager.archiveBucket(id: bucket.id)
                }
                .buttonStyle(.borderless)
                .disabled(manager.activeBuckets.count <= 1)
            }

            Button("Delete\u{2026}", role: .destructive, action: onRequestDelete)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rename sheet

/// Small sheet that lets the user edit an existing bucket's name, color,
/// and emoji. The create flow reuses `BucketCreateSheet`; this sheet is
/// the edit counterpart, kept minimal so `BucketCreateSheet` can stay a
/// pure "new" affordance without a mode enum.
@MainActor
private struct BucketRenameSheet: View {
    let manager: BucketManager
    let bucketID: UUID
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var colorHex: String = BucketPalette.swatches[0]
    @State private var emoji: String = ""
    @FocusState private var nameFocused: Bool

    private var bucket: Bucket? {
        manager.buckets.first { $0.id == bucketID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Bucket")
                .font(.system(size: 12, weight: .semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(commit)

            Text("Color")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(BucketPalette.swatches, id: \.self) { swatch in
                    Button {
                        colorHex = swatch
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: swatch) ?? .orange)
                                .frame(width: 20, height: 20)
                            if swatch == colorHex {
                                Circle()
                                    .stroke(Color.primary.opacity(0.9), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(swatch)
                }
            }

            TextField("Emoji (optional)", text: $emoji)
                .textFieldStyle(.roundedBorder)
                .onChange(of: emoji) { _, new in
                    if new.count > 1 { emoji = String(new.prefix(1)) }
                }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            if let b = bucket {
                name = b.name
                colorHex = b.colorHex
                emoji = b.emoji ?? ""
            }
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func commit() {
        guard let b = bucket else { isPresented = false; return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if trimmedName != b.name {
            manager.renameBucket(id: bucketID, to: trimmedName)
        }
        if colorHex != b.colorHex {
            manager.setColor(id: bucketID, colorHex: colorHex)
        }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEmoji: String? = trimmedEmoji.isEmpty ? nil : trimmedEmoji
        if newEmoji != b.emoji {
            manager.setEmoji(id: bucketID, emoji: newEmoji)
        }
        isPresented = false
    }
}
