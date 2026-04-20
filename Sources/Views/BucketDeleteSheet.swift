import SwiftUI

/// Modal sheet shown when the user picks "Delete…" on a bucket.
///
/// Primary action merges items into another active bucket (default: the
/// first other active bucket). A secondary "Delete forever" removes items
/// and sidecar files without merging. Refuses both operations when the
/// target is the last active bucket (no valid merge destination and the
/// app requires at least one active bucket).
@MainActor
struct BucketDeleteSheet: View {

    let manager: BucketManager
    let targetID: UUID
    @Binding var isPresented: Bool

    @State private var mergeIntoID: UUID?

    private var targetBucket: Bucket? {
        manager.buckets.first { $0.id == targetID }
    }

    private var mergeCandidates: [Bucket] {
        manager.activeBuckets.filter { $0.id != targetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete \"\(targetBucket?.name ?? "bucket")\"?")
                .font(.system(size: 13, weight: .semibold))

            if let count = targetBucket?.items.count, count > 0 {
                Text("\(count) item\(count == 1 ? "" : "s") will be moved or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if mergeCandidates.isEmpty {
                Text("This is the only active bucket. Create another one before deleting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Close") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                Text("Move items into another bucket, or remove them entirely.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("Merge into", selection: $mergeIntoID) {
                    ForEach(mergeCandidates, id: \.id) { b in
                        Text(b.emoji.map { "\($0)  \(b.name)" } ?? b.name)
                            .tag(Optional(b.id))
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Delete Forever", role: .destructive) {
                        performHardDelete()
                    }
                    Button("Merge") { performMerge() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(mergeIntoID == nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            mergeIntoID = mergeCandidates.first?.id
        }
    }

    // MARK: - Actions

    private func performMerge() {
        guard let destID = mergeIntoID else { return }
        // Merge-delete handles the active-switch itself if targetID was active.
        manager.deleteBucket(id: targetID, mergeInto: destID)
        isPresented = false
    }

    private func performHardDelete() {
        // Hard delete refuses on the active bucket; pre-switch to the chosen
        // merge candidate (or first candidate) so the call succeeds.
        if manager.activeBucketID == targetID,
           let fallback = mergeIntoID ?? mergeCandidates.first?.id {
            manager.setActiveBucket(id: fallback)
        }
        manager.deleteBucket(id: targetID, mergeInto: nil)
        isPresented = false
    }
}
