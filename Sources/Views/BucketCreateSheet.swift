import SwiftUI

/// Popover shown from the tab bar's `[+]` button. Collects a name, a color
/// swatch, and an optional one-character emoji. Commits via a caller
/// callback so the view stays dumb; wiring happens in `BucketTabsView`.
@MainActor
struct BucketCreateSheet: View {

    @Binding var isPresented: Bool
    /// (name, colorHex, emoji?). Caller decides how to apply it — usually
    /// `manager.createBucket(...)` + `setActiveBucket`.
    let onCreate: (String, String, String?) -> Void

    @State private var name: String = ""
    @State private var colorHex: String = BucketPalette.swatches[1]
    @State private var emoji: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Bucket")
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
                    SwatchCircle(
                        hex: swatch,
                        selected: swatch == colorHex,
                        onTap: { colorHex = swatch }
                    )
                }
            }

            TextField("Emoji (optional)", text: $emoji)
                .textFieldStyle(.roundedBorder)
                .onChange(of: emoji) { _, new in
                    if new.count > 1 {
                        emoji = String(new.prefix(1))
                    }
                }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmed, colorHex, e.isEmpty ? nil : e)
        isPresented = false
    }
}

private struct SwatchCircle: View {
    let hex: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color(hex: hex) ?? .orange)
                    .frame(width: 20, height: 20)
                if selected {
                    Circle()
                        .stroke(Color.primary.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .help(hex)
    }
}
