import Foundation

/// Handles `.snoroh` file export and import.
///
/// Format: JSON with version, name, and base64-encoded PNG sprites for each status.
/// Note: Export is lossy — source sheets and frame inputs (smartImportMeta) are NOT
/// included. Imported mimes always open in Manual editor on re-edit.
enum MimeExporter {

    // MARK: - Types

    struct SnorohFile: Codable {
        let version: Int
        let name: String
        let sprites: [String: SpriteData]

        struct SpriteData: Codable {
            let frames: Int
            let data: String  // Base64-encoded PNG
        }
    }

    enum ExportError: Error, LocalizedError {
        case mimeNotFound
        case spriteReadFailed(status: String)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .mimeNotFound: return "Mime not found"
            case .spriteReadFailed(let s): return "Failed to read sprite for \(s)"
            case .writeFailed(let e): return "Failed to write file: \(e.localizedDescription)"
            }
        }
    }

    enum ImportError: Error, LocalizedError {
        case readFailed
        case invalidFormat
        case missingSprite(status: String)
        case decodeFailed(status: String)

        var errorDescription: String? {
            switch self {
            case .readFailed: return "Failed to read .snoroh file"
            case .invalidFormat: return "Invalid .snoroh file"
            case .missingSprite(let s): return "Missing sprite data for \"\(s)\""
            case .decodeFailed(let s): return "Failed to decode sprite for \"\(s)\""
            }
        }
    }

    // MARK: - Export

    /// Export a custom mime to an .snoroh file at the given destination path.
    static func export(mimeID: String, to destination: URL) throws {
        let manager = CustomMimeManager.shared
        guard let mime = manager.mime(withID: mimeID) else {
            throw ExportError.mimeNotFound
        }

        var spriteEntries: [String: SnorohFile.SpriteData] = [:]
        for status in Status.allCases {
            guard let entry = mime.sprite(for: status) else {
                throw ExportError.spriteReadFailed(status: status.rawValue)
            }
            let path = manager.spritePath(fileName: entry.fileName)
            guard let data = try? Data(contentsOf: path) else {
                throw ExportError.spriteReadFailed(status: status.rawValue)
            }
            spriteEntries[status.rawValue] = .init(
                frames: entry.frames,
                data: data.base64EncodedString()
            )
        }

        let file = SnorohFile(version: 1, name: mime.name, sprites: spriteEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(file)

        do {
            try jsonData.write(to: destination, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Generate a default filename for export.
    static func defaultFilename(for mime: CustomMimeData) -> String {
        let safeName = mime.name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let date = dateFormatter.string(from: Date())
        return "snoroh-\(safeName)-\(date).snoroh"
    }

    // MARK: - Import

    /// Import a custom mime from an .snoroh file.
    /// Returns the new mime ID on success.
    @discardableResult
    static func importMime(from source: URL) throws -> String {
        guard let fileData = try? Data(contentsOf: source) else {
            throw ImportError.readFailed
        }

        let file: SnorohFile
        do {
            file = try JSONDecoder().decode(SnorohFile.self, from: fileData)
        } catch {
            throw ImportError.invalidFormat
        }

        guard file.version == 1, !file.name.isEmpty else {
            throw ImportError.invalidFormat
        }

        var blobs: [Status: (data: Data, frames: Int)] = [:]
        for status in Status.allCases {
            guard let entry = file.sprites[status.rawValue], !entry.data.isEmpty else {
                throw ImportError.missingSprite(status: status.rawValue)
            }
            guard let decoded = Data(base64Encoded: entry.data) else {
                throw ImportError.decodeFailed(status: status.rawValue)
            }
            // Validate that the decoded data is a valid image
            guard SmartImport.loadImage(from: decoded) != nil else {
                throw ImportError.decodeFailed(status: status.rawValue)
            }
            blobs[status] = (data: decoded, frames: entry.frames)
        }

        guard let id = CustomMimeManager.shared.addMimeFromBlobs(
            name: file.name,
            spriteBlobs: blobs
        ) else {
            throw ImportError.invalidFormat
        }

        return id
    }
}
