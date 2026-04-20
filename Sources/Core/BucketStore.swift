import Foundation

/// Owns on-disk state for the Bucket feature — manifest JSON + sidecar files.
///
/// Layout (v1, single-bucket; Epic 04 bumps to v2 schema):
/// ```
/// <rootURL>/
/// ├── manifest.json          # Bucket JSON
/// ├── settings.json          # BucketSettings JSON
/// ├── files/<itemID>.<ext>   # dropped file copies
/// ├── images/<itemID>.png    # screenshot + image copies
/// ├── favicons/<itemID>.ico  # URL favicons
/// └── og/<itemID>.jpg        # URL og:image
/// ```
///
/// All disk I/O goes through this actor so the @MainActor `BucketManager`
/// never blocks the UI thread.
actor BucketStore {

    static let currentSchemaVersion = 2

    enum StoreError: Error {
        case forwardIncompatibleSchema(Int)
        case migrationAborted(underlying: Error)
    }

    /// Sendable `let` — safe to read synchronously from any context.
    nonisolated let rootURL: URL

    /// Default production root: `~/.snor-oh/buckets/`.
    /// Tests should inject a temp directory.
    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.rootURL = home
                .appendingPathComponent(".snor-oh")
                .appendingPathComponent("buckets")
        }
    }

    // MARK: - Manifest (v2)

    /// Canonical entry point for Epic 04+. Reads `manifest.json` and returns a
    /// v2 envelope, migrating v1 on disk if needed. Returns an empty envelope
    /// (not persisted) when no manifest exists yet.
    func loadManifest() throws -> BucketManifestV2 {
        try ensureDirectories()
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            let fresh = Bucket(name: "Default", keyboardIndex: 1)
            return BucketManifestV2(
                schemaVersion: Self.currentSchemaVersion,
                activeBucketID: fresh.id,
                buckets: [fresh]
            )
        }
        let data = try Data(contentsOf: url)
        let version = try peekSchemaVersion(data: data)
        switch version {
        case nil:
            return try migrateV1ToV2(rawV1Bytes: data)
        case .some(2):
            return try decoder.decode(BucketManifestV2.self, from: data)
        case .some(let v) where v > 2:
            NSLog("[bucket] manifest schemaVersion=\(v) is newer than this build (current=\(Self.currentSchemaVersion)); refusing to load")
            throw StoreError.forwardIncompatibleSchema(v)
        default:
            // Unknown older version — treat like v1 if it decodes as legacy Bucket.
            return try migrateV1ToV2(rawV1Bytes: data)
        }
    }

    /// Atomically persists a v2 envelope.
    func saveManifest(_ manifest: BucketManifestV2) throws {
        try ensureDirectories()
        var toWrite = manifest
        toWrite.schemaVersion = Self.currentSchemaVersion
        let data = try encoder.encode(toWrite)
        try atomicWrite(data, to: manifestURL)
    }

    /// Epic 01 compatibility: returns the manifest's active bucket. Runs
    /// migration transparently if disk is still v1.
    func loadBucket() throws -> Bucket {
        let manifest = try loadManifest()
        if let active = manifest.buckets.first(where: { $0.id == manifest.activeBucketID }) {
            return active
        }
        return manifest.buckets.first ?? Bucket(name: "Default", keyboardIndex: 1)
    }

    /// Epic 01 compatibility: updates the active bucket inside the v2 manifest.
    /// If no manifest exists, writes a fresh one with this bucket active.
    func saveBucket(_ bucket: Bucket) throws {
        try ensureDirectories()
        let url = manifestURL
        if FileManager.default.fileExists(atPath: url.path) {
            var manifest = try loadManifest()
            if let idx = manifest.buckets.firstIndex(where: { $0.id == bucket.id }) {
                manifest.buckets[idx] = bucket
            } else {
                manifest.buckets.append(bucket)
            }
            manifest.activeBucketID = bucket.id
            try saveManifest(manifest)
        } else {
            let manifest = BucketManifestV2(
                schemaVersion: Self.currentSchemaVersion,
                activeBucketID: bucket.id,
                buckets: [bucket]
            )
            try saveManifest(manifest)
        }
    }

    // MARK: - Settings

    func loadSettings() throws -> BucketSettings {
        try ensureDirectories()
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BucketSettings()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(BucketSettings.self, from: data)
    }

    func saveSettings(_ settings: BucketSettings) throws {
        try ensureDirectories()
        let data = try encoder.encode(settings)
        try atomicWrite(data, to: settingsURL)
    }

    // MARK: - Sidecars

    /// Copies `source` into a bucket-scoped sidecar directory
    /// (`<rootURL>/<bucketID>/<subdir>/<itemID>.<ext>`). Returns the path
    /// relative to `rootURL` — that's what gets stored on `BucketItem.fileRef.cachedPath`.
    ///
    /// If `move: true`, the source is renamed (FS-rename); cross-volume moves
    /// automatically fall back to copy+delete.
    func copySidecar(
        from source: URL,
        bucketID: UUID,
        itemID: UUID,
        subdir: String,
        ext: String? = nil,
        move: Bool = false
    ) throws -> String {
        try ensureDirectories()
        let relDir = "\(bucketID.uuidString)/\(subdir)"
        let subdirURL = rootURL.appendingPathComponent(relDir)
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)

        let resolvedExt = ext ?? source.pathExtension
        let fileName = resolvedExt.isEmpty
            ? itemID.uuidString
            : "\(itemID.uuidString).\(resolvedExt)"
        let dest = subdirURL.appendingPathComponent(fileName)

        // If dest exists (crash recovery), remove it first — itemID is unique enough
        // that we prefer the caller's new bytes.
        try? FileManager.default.removeItem(at: dest)

        if move {
            do {
                try FileManager.default.moveItem(at: source, to: dest)
            } catch {
                // Cross-volume or permission — fall back to copy+delete.
                try FileManager.default.copyItem(at: source, to: dest)
                try? FileManager.default.removeItem(at: source)
            }
        } else {
            try FileManager.default.copyItem(at: source, to: dest)
        }

        return "\(relDir)/\(fileName)"
    }

    /// Writes raw bytes (e.g. clipboard image data) into the bucket's sidecar
    /// directory and returns the relative path.
    func writeSidecar(
        _ data: Data,
        bucketID: UUID,
        itemID: UUID,
        subdir: String,
        ext: String
    ) throws -> String {
        try ensureDirectories()
        let relDir = "\(bucketID.uuidString)/\(subdir)"
        let subdirURL = rootURL.appendingPathComponent(relDir)
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)

        let fileName = "\(itemID.uuidString).\(ext)"
        let dest = subdirURL.appendingPathComponent(fileName)
        try atomicWrite(data, to: dest)
        return "\(relDir)/\(fileName)"
    }

    /// Removes sidecar files for evicted items. Relative paths are resolved
    /// against `rootURL`. Missing paths are ignored (idempotent).
    func deleteSidecars(relativePaths: [String]) {
        for rel in relativePaths {
            let url = rootURL.appendingPathComponent(rel)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Recursively deletes a bucket's entire sidecar tree. Used by
    /// `deleteBucket(id:mergeInto: nil)`.
    func deleteBucketDirectory(bucketID: UUID) {
        let bucketDir = rootURL.appendingPathComponent(bucketID.uuidString)
        try? FileManager.default.removeItem(at: bucketDir)
    }

    /// Renames `<src>/` to `<dst>/` — used by `deleteBucket(mergeInto:)` to
    /// fold one bucket's sidecars into another. Returns the per-item path
    /// rewrites so callers can patch `BucketItem.fileRef.cachedPath`.
    ///
    /// If both directories exist (partial prior merge), contents of `src` are
    /// moved individually into `dst`. After the call, `<src>/` no longer exists.
    func mergeBucketDirectory(from src: UUID, into dst: UUID) throws {
        let fm = FileManager.default
        let srcDir = rootURL.appendingPathComponent(src.uuidString)
        let dstDir = rootURL.appendingPathComponent(dst.uuidString)
        guard fm.fileExists(atPath: srcDir.path) else { return }
        if !fm.fileExists(atPath: dstDir.path) {
            try fm.moveItem(at: srcDir, to: dstDir)
            return
        }
        // Both exist — walk sub-entries, move contents, then remove src.
        let entries = try fm.contentsOfDirectory(
            at: srcDir,
            includingPropertiesForKeys: nil,
            options: []
        )
        for entry in entries {
            let target = dstDir.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                // Merge sub-dir (e.g. both have `files/`) by moving individual files.
                let inner = try fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                for file in inner {
                    let finalDest = target.appendingPathComponent(file.lastPathComponent)
                    try? fm.removeItem(at: finalDest)
                    try fm.moveItem(at: file, to: finalDest)
                }
                try? fm.removeItem(at: entry)
            } else {
                try fm.moveItem(at: entry, to: target)
            }
        }
        try? fm.removeItem(at: srcDir)
    }

    /// Moves a single sidecar file from `<src>/<subdir>/<name>` to
    /// `<dst>/<subdir>/<name>`. Returns the new relative path. Missing source
    /// is a no-op — caller gets nil.
    func moveSidecarBetweenBuckets(
        relativePath: String,
        from src: UUID,
        to dst: UUID
    ) throws -> String? {
        let srcPrefix = "\(src.uuidString)/"
        guard relativePath.hasPrefix(srcPrefix) else { return nil }
        let tail = String(relativePath.dropFirst(srcPrefix.count))
        let newRel = "\(dst.uuidString)/\(tail)"
        let srcURL = rootURL.appendingPathComponent(relativePath)
        let dstURL = rootURL.appendingPathComponent(newRel)
        let fm = FileManager.default
        guard fm.fileExists(atPath: srcURL.path) else { return nil }
        try fm.createDirectory(
            at: dstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fm.removeItem(at: dstURL)
        try fm.moveItem(at: srcURL, to: dstURL)
        return newRel
    }

    /// Resolves a relative sidecar path back to an absolute URL.
    nonisolated func absoluteURL(forRelative relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    /// Total sidecar storage on disk in bytes — used by BucketManager for
    /// size-based LRU eviction. Walks every `<bucketID>/` tree at the root.
    func sidecarStorageBytes() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let rootEntries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return 0
        }
        for entry in rootEntries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, UUID(uuidString: entry.lastPathComponent) != nil else { continue }
            guard let e = fm.enumerator(at: entry, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }
            for case let url as URL in e {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Migration v1 → v2

    /// Returns the path where the pre-migration v1 manifest is preserved on
    /// first upgrade. Exposed for tests; production callers shouldn't need it.
    nonisolated func backupURL() -> URL {
        rootURL.appendingPathComponent("manifest.v1.backup.json")
    }

    private func peekSchemaVersion(data: Data) throws -> Int? {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["schemaVersion"] as? Int
    }

    /// Migration is idempotent: a successful run always ends with a v2 manifest
    /// on disk, so re-entry from a v2 manifest goes through the v2 decode path
    /// instead and never calls this. The backup is written only on first run
    /// (skipped if `manifest.v1.backup.json` already exists).
    private func migrateV1ToV2(rawV1Bytes: Data) throws -> BucketManifestV2 {
        let legacyBucket = try decoder.decode(Bucket.self, from: rawV1Bytes)

        let backup = backupURL()
        if !FileManager.default.fileExists(atPath: backup.path) {
            try atomicWrite(rawV1Bytes, to: backup)
        }

        var migrated = legacyBucket
        migrated.archived = false
        migrated.colorHex = "#FF9500"
        migrated.emoji = nil
        migrated.keyboardIndex = 1

        do {
            try moveSidecarDirectoriesIntoBucket(bucketID: migrated.id)
        } catch {
            throw StoreError.migrationAborted(underlying: error)
        }

        migrated.items = migrated.items.map { item in
            rewritePaths(in: item, bucketID: migrated.id)
        }

        let manifest = BucketManifestV2(
            schemaVersion: Self.currentSchemaVersion,
            activeBucketID: migrated.id,
            buckets: [migrated]
        )
        try saveManifest(manifest)
        return manifest
    }

    private func moveSidecarDirectoriesIntoBucket(bucketID: UUID) throws {
        let fm = FileManager.default
        let subdirs = ["files", "images", "favicons", "og"]
        let bucketDir = rootURL.appendingPathComponent(bucketID.uuidString)

        for sub in subdirs {
            let oldPath = rootURL.appendingPathComponent(sub)
            let newPath = bucketDir.appendingPathComponent(sub)

            let oldExists = fm.fileExists(atPath: oldPath.path)
            let newExists = fm.fileExists(atPath: newPath.path)

            if !oldExists { continue }

            if newExists {
                // Already nested from a previous partial migration — leave alone.
                continue
            }

            try fm.createDirectory(at: bucketDir, withIntermediateDirectories: true)
            try fm.moveItem(at: oldPath, to: newPath)
        }
    }

    private func rewritePaths(in item: BucketItem, bucketID: UUID) -> BucketItem {
        var updated = item
        let prefix = "\(bucketID.uuidString)/"
        if var fileRef = updated.fileRef, let cached = fileRef.cachedPath, !cached.hasPrefix(prefix) {
            fileRef.cachedPath = prefix + cached
            updated.fileRef = fileRef
        }
        if var urlMeta = updated.urlMeta {
            if let fav = urlMeta.faviconPath, !fav.hasPrefix(prefix) {
                urlMeta.faviconPath = prefix + fav
            }
            if let og = urlMeta.ogImagePath, !og.hasPrefix(prefix) {
                urlMeta.ogImagePath = prefix + og
            }
            updated.urlMeta = urlMeta
        }
        return updated
    }

    // MARK: - Private

    private var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }
    private var settingsURL: URL { rootURL.appendingPathComponent("settings.json") }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        // replaceItemAt handles the case where `url` doesn't yet exist.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
