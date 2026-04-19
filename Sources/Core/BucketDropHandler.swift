import Foundation
import AppKit
import UniformTypeIdentifiers

/// Unpacks `NSItemProvider`s coming from SwiftUI `.onDrop(of:...)` into
/// `BucketItem`s and adds them to `BucketManager.shared`.
///
/// Priority (highest first): file URL > image bytes > web URL > rich text > plain text.
/// A single drop of N providers becomes N items sharing a `stackGroupID` if N > 1.
@MainActor
enum BucketDropHandler {

    /// UTTypes offered to SwiftUI's `.onDrop(of:)` matcher. Keep aligned with
    /// the `ingest(providers:source:)` switch below.
    static let supportedUTTypes: [UTType] = [
        .fileURL,
        .image,
        .url,
        .rtf,
        .utf8PlainText,
        .plainText,
    ]

    /// Entry point called from `.onDrop(of:supportedUTTypes)` closures.
    /// Returns `true` synchronously so SwiftUI accepts the drop; real work
    /// happens asynchronously as providers resolve.
    @discardableResult
    static func ingest(providers: [NSItemProvider], source: BucketChangeSource) -> Bool {
        guard !providers.isEmpty else { return false }
        let groupID: UUID? = providers.count > 1 ? UUID() : nil

        for provider in providers {
            Task { @MainActor in
                if let item = await resolveItem(from: provider, stackGroupID: groupID) {
                    BucketManager.shared.add(item, source: source)
                }
            }
        }
        return true
    }

    // MARK: - Provider → Item

    private static func resolveItem(
        from provider: NSItemProvider,
        stackGroupID: UUID?
    ) async -> BucketItem? {
        // 1. File URL (files + folders)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: provider) {
                return makeFileItem(at: url, stackGroupID: stackGroupID)
            }
        }

        // 2. Image bytes
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadData(from: provider, type: UTType.image.identifier) {
                return makeImageItem(data: data, stackGroupID: stackGroupID)
            }
        }

        // 3. Web URL (not file URL)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider), !url.isFileURL {
                return makeURLItem(urlString: url.absoluteString, stackGroupID: stackGroupID)
            }
        }

        // 4. Rich text (RTF)
        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
            if let data = await loadData(from: provider, type: UTType.rtf.identifier) {
                return makeRichTextItem(rtfData: data, stackGroupID: stackGroupID)
            }
        }

        // 5. Plain text
        for id in [UTType.utf8PlainText.identifier, UTType.plainText.identifier] {
            if provider.hasItemConformingToTypeIdentifier(id) {
                if let s = await loadString(from: provider, type: id) {
                    return BucketItem(kind: .text, stackGroupID: stackGroupID, text: s)
                }
            }
        }

        return nil
    }

    // MARK: - Factories

    /// Creates a file/folder item, kicking off an async copy into the bucket
    /// sidecar. The returned item has `cachedPath = nil` until the copy finishes;
    /// BucketManager will see the initial item and update it after copy.
    private static func makeFileItem(at url: URL, stackGroupID: UUID?) -> BucketItem {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let kind: BucketItemKind = isDir.boolValue ? .folder : inferFileKind(url: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let uti = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? (isDir.boolValue ? "public.folder" : "public.data")
        return BucketItem(
            id: UUID(),
            kind: kind,
            stackGroupID: stackGroupID,
            fileRef: .init(
                originalPath: url.path,
                cachedPath: nil,
                byteSize: size,
                uti: uti,
                displayName: url.lastPathComponent
            )
        )
    }

    private static func inferFileKind(url: URL) -> BucketItemKind {
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let t = UTType(uti) {
            if t.conforms(to: .image) { return .image }
        }
        return .file
    }

    private static func makeImageItem(data: Data, stackGroupID: UUID?) -> BucketItem {
        let id = UUID()
        return BucketItem(
            id: id,
            kind: .image,
            stackGroupID: stackGroupID,
            fileRef: .init(
                originalPath: "", // no original path for pasteboard-supplied bytes
                cachedPath: nil,
                byteSize: Int64(data.count),
                uti: UTType.image.identifier,
                displayName: "image-\(id.uuidString.prefix(8)).png"
            )
        )
    }

    private static func makeURLItem(urlString: String, stackGroupID: UUID?) -> BucketItem {
        BucketItem(
            kind: .url,
            stackGroupID: stackGroupID,
            urlMeta: .init(urlString: urlString, title: nil)
        )
    }

    private static func makeRichTextItem(rtfData: Data, stackGroupID: UUID?) -> BucketItem {
        BucketItem(
            kind: .richText,
            stackGroupID: stackGroupID,
            text: rtfData.base64EncodedString()
        )
    }

    // MARK: - Async NSItemProvider loaders

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url); return
                }
                if let url = item as? URL {
                    cont.resume(returning: url); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    cont.resume(returning: url); return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url); return
                }
                if let s = item as? String, let url = URL(string: s) {
                    cont.resume(returning: url); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let data = item as? Data {
                    cont.resume(returning: data); return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: data); return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private static func loadString(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let s = item as? String {
                    cont.resume(returning: s); return
                }
                if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                    cont.resume(returning: s); return
                }
                cont.resume(returning: nil)
            }
        }
    }
}
