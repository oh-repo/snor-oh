import Foundation

/// Manages CRUD operations for custom pet sprites.
///
/// Storage:
/// - Metadata: `~/.snor-oh/custom-mimes.json`
/// - Sprite files: `~/.snor-oh/custom-sprites/`
///
/// Main-thread only (mutates @Observable state).
@Observable
final class CustomMimeManager {

    private(set) var mimes: [CustomMimeData] = []

    private let metadataFile: URL
    private let spritesDir: URL

    static let shared = CustomMimeManager()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".snor-oh")
        metadataFile = base.appendingPathComponent("custom-mimes.json")
        spritesDir = base.appendingPathComponent("custom-sprites")
    }

    // MARK: - Load

    func load() {
        ensureDirectories()
        guard FileManager.default.fileExists(atPath: metadataFile.path) else { return }
        do {
            let data = try Data(contentsOf: metadataFile)
            mimes = try JSONDecoder().decode([CustomMimeData].self, from: data)
        } catch {
            print("[custom-mimes] failed to load: \(error)")
        }
    }

    // MARK: - Create

    /// Add a custom mime from per-status PNG files on disk.
    @discardableResult
    func addMime(name: String, spriteFiles: [Status: (sourcePath: String, frames: Int)]) -> String? {
        // Validate all statuses are present before writing anything
        for status in Status.allCases {
            guard spriteFiles[status] != nil else {
                print("[custom-mimes] missing sprite for \(status.rawValue)")
                return nil
            }
        }

        let id = "custom-\(UUID().uuidString)"
        ensureDirectories()

        var written: [URL] = []
        var sprites: [String: CustomMimeData.SpriteEntry] = [:]

        for status in Status.allCases {
            let entry = spriteFiles[status]!
            let fileName = "\(id)-\(status.rawValue).png"
            let dest = spritesDir.appendingPathComponent(fileName)
            do {
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: entry.sourcePath),
                    to: dest
                )
                written.append(dest)
            } catch {
                print("[custom-mimes] copy failed for \(status.rawValue): \(error)")
                // Rollback: remove already-written files
                for url in written { try? FileManager.default.removeItem(at: url) }
                return nil
            }
            sprites[status.rawValue] = .init(fileName: fileName, frames: entry.frames)
        }

        let mime = CustomMimeData(id: id, name: name, sprites: sprites)
        mimes.append(mime)
        persist()
        return id
    }

    /// Add a custom mime from in-memory PNG blobs (used by Smart Import).
    @discardableResult
    func addMimeFromBlobs(
        name: String,
        spriteBlobs: [Status: (data: Data, frames: Int)],
        smartImportMeta: (sheetData: Data, frameInputs: [Status: String])? = nil
    ) -> String? {
        // Validate all statuses are present before writing anything
        for status in Status.allCases {
            guard spriteBlobs[status] != nil else {
                print("[custom-mimes] missing blob for \(status.rawValue)")
                return nil
            }
        }

        let id = "custom-\(UUID().uuidString)"
        ensureDirectories()

        var written: [URL] = []
        var sprites: [String: CustomMimeData.SpriteEntry] = [:]

        for status in Status.allCases {
            let entry = spriteBlobs[status]!
            let fileName = "\(id)-\(status.rawValue).png"
            let dest = spritesDir.appendingPathComponent(fileName)
            do {
                try entry.data.write(to: dest, options: .atomic)
                written.append(dest)
            } catch {
                print("[custom-mimes] write failed for \(status.rawValue): \(error)")
                for url in written { try? FileManager.default.removeItem(at: url) }
                return nil
            }
            sprites[status.rawValue] = .init(fileName: fileName, frames: entry.frames)
        }

        var meta: CustomMimeData.SmartImportMeta?
        if let smartImportMeta {
            let sheetFileName = "\(id)-source.png"
            let sheetDest = spritesDir.appendingPathComponent(sheetFileName)
            do {
                try smartImportMeta.sheetData.write(to: sheetDest, options: .atomic)
            } catch {
                print("[custom-mimes] write failed for source sheet: \(error)")
            }
            var inputs: [String: String] = [:]
            for (status, input) in smartImportMeta.frameInputs {
                inputs[status.rawValue] = input
            }
            meta = .init(sheetFileName: sheetFileName, frameInputs: inputs)
        }

        let mime = CustomMimeData(id: id, name: name, sprites: sprites, smartImportMeta: meta)
        mimes.append(mime)
        persist()
        return id
    }

    // MARK: - Update

    func updateMime(
        id: String,
        name: String,
        spriteFiles: [Status: (sourcePath: String?, frames: Int)]
    ) {
        guard let idx = mimes.firstIndex(where: { $0.id == id }) else { return }
        let existing = mimes[idx]
        ensureDirectories()

        var sprites: [String: CustomMimeData.SpriteEntry] = [:]
        for status in Status.allCases {
            if let entry = spriteFiles[status] {
                if let sourcePath = entry.sourcePath {
                    // Replace sprite file atomically
                    let fileName = "\(id)-\(status.rawValue).png"
                    let dest = spritesDir.appendingPathComponent(fileName)
                    let tmp = spritesDir.appendingPathComponent("\(fileName).tmp")
                    do {
                        try FileManager.default.copyItem(
                            at: URL(fileURLWithPath: sourcePath),
                            to: tmp
                        )
                        _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
                    } catch {
                        print("[custom-mimes] copy failed for \(status.rawValue): \(error)")
                        try? FileManager.default.removeItem(at: tmp)
                    }
                    sprites[status.rawValue] = .init(fileName: fileName, frames: entry.frames)
                } else if let existingEntry = existing.sprite(for: status) {
                    // Keep existing file, just update frame count
                    sprites[status.rawValue] = .init(fileName: existingEntry.fileName, frames: entry.frames)
                }
            } else if let existingEntry = existing.sprite(for: status) {
                // Status not in update map — preserve existing entry entirely
                sprites[status.rawValue] = existingEntry
            }
        }

        mimes[idx] = CustomMimeData(
            id: id,
            name: name,
            sprites: sprites,
            smartImportMeta: existing.smartImportMeta
        )
        SpriteCache.shared.purgeCustomPet(id)
        persist()
    }

    func updateMimeFromSmartImport(
        id: String,
        name: String,
        spriteBlobs: [Status: (data: Data, frames: Int)],
        sheetData: Data,
        frameInputs: [Status: String]
    ) {
        guard let idx = mimes.firstIndex(where: { $0.id == id }) else { return }
        ensureDirectories()

        // Write to temp files first, then rename — enables full rollback on failure
        var written: [URL] = []
        var sprites: [String: CustomMimeData.SpriteEntry] = [:]
        for status in Status.allCases {
            guard let entry = spriteBlobs[status] else {
                print("[custom-mimes] missing blob for \(status.rawValue) in smart import update")
                for url in written { try? FileManager.default.removeItem(at: url) }
                return
            }
            let fileName = "\(id)-\(status.rawValue).png"
            let dest = spritesDir.appendingPathComponent(fileName)
            do {
                try entry.data.write(to: dest, options: .atomic)
                written.append(dest)
            } catch {
                print("[custom-mimes] write failed for \(status.rawValue): \(error)")
                for url in written { try? FileManager.default.removeItem(at: url) }
                return
            }
            sprites[status.rawValue] = .init(fileName: fileName, frames: entry.frames)
        }

        let sheetFileName = "\(id)-source.png"
        let sheetDest = spritesDir.appendingPathComponent(sheetFileName)
        try? sheetData.write(to: sheetDest, options: .atomic)

        var inputs: [String: String] = [:]
        for (status, input) in frameInputs {
            inputs[status.rawValue] = input
        }

        mimes[idx] = CustomMimeData(
            id: id,
            name: name,
            sprites: sprites,
            smartImportMeta: .init(sheetFileName: sheetFileName, frameInputs: inputs)
        )
        SpriteCache.shared.purgeCustomPet(id)
        persist()
    }

    // MARK: - Delete

    func deleteMime(id: String) {
        guard let idx = mimes.firstIndex(where: { $0.id == id }) else { return }
        let mime = mimes[idx]

        // Remove sprite files
        for (_, entry) in mime.sprites {
            let path = spritesDir.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: path)
        }
        // Remove source sheet if present
        if let sheetName = mime.smartImportMeta?.sheetFileName {
            let path = spritesDir.appendingPathComponent(sheetName)
            try? FileManager.default.removeItem(at: path)
        }

        mimes.remove(at: idx)
        persist()
    }

    // MARK: - Lookup

    func mime(withID id: String) -> CustomMimeData? {
        mimes.first { $0.id == id }
    }

    /// Full file path for a custom sprite file.
    func spritePath(fileName: String) -> URL {
        spritesDir.appendingPathComponent(fileName)
    }

    /// All available pet IDs (built-in + custom).
    var allPetIDs: [String] {
        SpriteConfig.builtInPets + mimes.map(\.id)
    }

    // MARK: - Private

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: spritesDir, withIntermediateDirectories: true)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(mimes)
            try data.write(to: metadataFile, options: .atomic)
        } catch {
            print("[custom-mimes] failed to persist: \(error)")
        }
    }
}
