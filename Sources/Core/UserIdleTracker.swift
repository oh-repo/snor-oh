import Foundation
import ApplicationServices

// MARK: - DI seam for testing

protocol IdleSecondsProvider {
    func secondsSinceLastEvent() -> TimeInterval
}

/// Reads combined-session idle seconds from Core Graphics. Merges HID +
/// synthetic events (so Raycast/tooling doesn't register as "away").
/// Single syscall, microsecond cost.
struct SystemIdleProvider: IdleSecondsProvider {
    func secondsSinceLastEvent() -> TimeInterval {
        // CGEventType is an OptionSet-ish RawRepresentable; ~0 asks "any event".
        let anyEvent = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }
}

// UserIdleTracker implementation — filled in by Task 6 (TDD).
