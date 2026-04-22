// Sources/Views/InstallPromptView.swift
import SwiftUI

struct InstallPromptView: View {
    let prompt: InstallCoordinator.Prompt

    private var sizeLabel: String {
        let kb = prompt.sizeBytes / 1024
        return kb > 0 ? "\(kb) KB" : "< 1 KB"
    }

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
                Text(sizeLabel)
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
        .task(id: url) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data) else { return }
            image = img
        }
    }
}
