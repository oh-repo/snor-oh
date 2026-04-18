import AppKit
import CoreGraphics

/// Caches extracted CGImage frames from sprite sheet PNGs.
/// Key: "pet/filename", Value: array of frames.
/// Thread-safety: accessed only from main thread (same as animation timer).
final class SpriteCache {
    static let shared = SpriteCache()

    private var cache: [String: [CGImage]] = [:]

    /// Returns cached frames, or loads + extracts from the sprite sheet PNG.
    ///
    /// For custom pets, the SpriteConfig.sheet lookup (which reads CustomMimeManager)
    /// is deferred until after the cache check, so cached hits avoid the singleton read.
    func frames(pet: String, status: Status) -> [CGImage] {
        // For built-in pets, we can compute the key cheaply
        // For custom pets, use a status-based key to check cache first
        let cacheKey: String
        if SpriteConfig.isCustomPet(pet) {
            cacheKey = "\(pet)/\(status.rawValue)"
        } else {
            let (filename, _) = SpriteConfig.sheet(pet: pet, status: status)
            cacheKey = "\(pet)/\(filename)"
        }

        if let cached = cache[cacheKey] {
            return cached
        }

        // Cache miss — resolve full config and load
        let (filename, frameCount) = SpriteConfig.sheet(pet: pet, status: status)

        let image: CGImage?
        if SpriteConfig.isCustomPet(pet) {
            image = loadCustomSpriteSheet(fileName: filename)
        } else {
            image = loadSpriteSheet(named: filename)
        }

        guard let image else { return [] }

        // Custom pets always use 128px frames (grid-packed by SmartImport)
        let frameSize = SpriteConfig.isCustomPet(pet) ? 128 : SpriteConfig.frameSize(for: pet)
        let extracted = extractFrames(from: image, frameSize: frameSize, count: frameCount)
        cache[cacheKey] = extracted
        return extracted
    }

    /// Remove all cached frames (e.g., when switching pet).
    func purge() {
        cache.removeAll()
    }

    /// Invalidate cached frames for a specific custom pet (e.g., after re-import).
    func purgeCustomPet(_ petID: String) {
        cache = cache.filter { !$0.key.hasPrefix("\(petID)/") }
    }

    // MARK: - Private

    /// Load a custom sprite from ~/.snor-oh/custom-sprites/
    private func loadCustomSpriteSheet(fileName: String) -> CGImage? {
        let url = CustomMimeManager.shared.spritePath(fileName: fileName)
        return loadCGImage(from: url)
    }

    private func loadSpriteSheet(named name: String) -> CGImage? {
        // Try bundled resources first
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Sprites") {
            return loadCGImage(from: url)
        }
        // Fallback: search in bundle root (SPM copies into bundle)
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return loadCGImage(from: url)
        }
        return nil
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let image = CGImage(
                  pngDataProviderSource: dataProvider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }
        return image
    }

    private func extractFrames(from sheet: CGImage, frameSize: Int, count: Int) -> [CGImage] {
        let cols = sheet.width / frameSize
        guard cols > 0 else { return [] }

        var frames: [CGImage] = []
        frames.reserveCapacity(count)

        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            let rect = CGRect(
                x: col * frameSize,
                y: row * frameSize,
                width: frameSize,
                height: frameSize
            )
            if let cropped = sheet.cropping(to: rect) {
                frames.append(cropped)
            }
        }
        return frames
    }
}
