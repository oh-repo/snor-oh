import Foundation

/// Sprite sheet configuration per character and status.
/// Maps each (pet, status) pair to a sprite sheet filename and frame count.
enum SpriteConfig {

    // MARK: - Constants

    static let frameBasePx: CGFloat = 128    // Display size (pixels)
    static let frameDurationMs: Double = 80  // 12.5 fps
    static let autoFreezeTimeout: TimeInterval = 10.0
    static let autoFreezeStatuses: Set<Status> = [.idle, .disconnected]

    // MARK: - Built-in Characters

    /// All built-in character IDs.
    static let builtInPets = ["rottweiler", "dalmatian", "samurai", "hancock"]

    /// Native frame size in the sprite sheet PNG.
    static func frameSize(for pet: String) -> Int {
        switch pet {
        case "rottweiler", "dalmatian": return 64
        case "samurai", "hancock": return 128
        default: return 128
        }
    }

    /// Returns true if the pet ID refers to a custom (non-built-in) pet.
    static func isCustomPet(_ pet: String) -> Bool {
        pet.hasPrefix("custom-")
    }

    /// Sprite sheet filename and frame count for a given (pet, status) pair.
    /// For custom pets, looks up CustomMimeManager.
    static func sheet(pet: String, status: Status) -> (filename: String, frames: Int) {
        switch pet {
        case "rottweiler":
            switch status {
            case .disconnected:  return ("SleepDogg",         8)
            case .busy:          return ("RottweilerSniff",  31)
            case .service:       return ("RottweilerBark",   12)
            case .idle:          return ("Sittiing",          8)
            case .searching:     return ("RottweilerIdle",    6)
            case .initializing:  return ("RottweilerIdle",    6)
            case .visiting:      return ("Sittiing",          8)
            }
        case "dalmatian":
            switch status {
            case .disconnected:  return ("SleepDogg",           8)
            case .busy:          return ("DalmatianSniff",     26)
            case .service:       return ("DalmatianBark",      12)
            case .idle:          return ("DalmatianSitting",    8)
            case .searching:     return ("DalmatianIdle",       7)
            case .initializing:  return ("DalmatianIdle",       7)
            case .visiting:      return ("DalmatianSitting",    8)
            }
        case "samurai":
            switch status {
            case .disconnected:  return ("SamuraiSleep",    3)
            case .busy:          return ("SamuraiBark",     6)
            case .service:       return ("SamuraiSniff",    8)
            case .idle:          return ("SamuraiSitting",  6)
            case .searching:     return ("SamuraiIdle",     8)
            case .initializing:  return ("SamuraiIdle",     8)
            case .visiting:      return ("SamuraiSitting",  6)
            }
        case "hancock":
            switch status {
            case .disconnected:  return ("HancockSleep",    1)
            case .busy:          return ("HancockBark",     9)
            case .service:       return ("HancockSniff",   18)
            case .idle:          return ("HancockSitting", 10)
            case .searching:     return ("HancockIdle",    17)
            case .initializing:  return ("HancockIdle",    17)
            case .visiting:      return ("HancockSitting", 10)
            }
        default:
            // Custom pets: look up from CustomMimeManager
            if let mime = CustomMimeManager.shared.mime(withID: pet),
               let entry = mime.sprite(for: status) {
                return (entry.fileName, entry.frames)
            }
            return ("unknown", 1)
        }
    }
}
