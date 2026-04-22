// Sources/Core/InstallCoordinator.swift
import AppKit
import Foundation

@MainActor
final class InstallCoordinator: ObservableObject {
    static let shared = InstallCoordinator()
    @Published var pending: Prompt?

    struct Prompt: Identifiable, Equatable {
        let id: String
        let name: String
        let creator: String?
        let sizeBytes: Int
        let previewURL: URL
        let bundleData: Data
    }

    nonisolated static func extractID(from url: URL) -> String? {
        guard url.scheme == "snoroh", url.host == "install" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let raw = comps?.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        guard !raw.isEmpty, raw.count <= 64,
              raw.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" })
        else { return nil }
        return raw
    }

    // MARK: - Public entry point

    func handle(url: URL) {
        guard let id = Self.extractID(from: url) else { return }
        Task { await fetchAndPrompt(id: id) }
    }

    // MARK: - Fetch + prompt

    private func fetchAndPrompt(id: String) async {
        let baseURL = UserDefaults.standard.string(forKey: DefaultsKey.marketplaceURL)
            ?? DefaultsDefault.marketplaceURL
        do {
            let meta = try await MarketplaceClient.fetchMeta(id: id, baseURL: baseURL)
            guard meta.format == "snoroh" else {
                showBubble("Wrong format — expected .snoroh, got .\(meta.format)")
                return
            }
            let bundle = try await MarketplaceClient.fetchBundle(id: id, baseURL: baseURL)
            guard let previewURL = MarketplaceClient.previewURL(id: id, baseURL: baseURL) else {
                showBubble("Marketplace fetch failed")
                return
            }
            pending = Prompt(
                id: id,
                name: meta.name,
                creator: meta.creator,
                sizeBytes: bundle.count,
                previewURL: previewURL,
                bundleData: bundle
            )
        } catch {
            showBubble("Marketplace fetch failed")
        }
    }

    // MARK: - Confirm / Cancel

    func confirm() {
        guard let p = pending else { return }
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(p.id).snoroh")
            try p.bundleData.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            _ = try OhhExporter.importOhh(from: tmp)
            showBubble("Installed \(p.name)")
            pending = nil
        } catch {
            showBubble("Install failed: \(error.localizedDescription)")
            // intentionally keep `pending` so user can retry or cancel
        }
    }

    func cancel() {
        pending = nil
    }

    // MARK: - Private helpers

    private func showBubble(_ message: String) {
        NotificationCenter.default.post(
            name: .mcpSay,
            object: nil,
            userInfo: ["message": message, "duration_ms": UInt64(5000)]
        )
    }
}
