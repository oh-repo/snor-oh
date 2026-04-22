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

// MARK: - Tracker

@Observable
final class UserIdleTracker {

    enum State: Equatable {
        case present
        case away(since: Date)
    }

    /// Threshold for present -> away transition, seconds. Default 10 min.
    var thresholdSecs: TimeInterval = 600

    /// Hysteresis guard on the away -> present edge: a single tick reading
    /// below this value triggers return. 2s absorbs any jitter from the 2s
    /// watchdog tick landing between a real away and a stray event.
    var returnHysteresisSecs: TimeInterval = 2

    /// Live-toggle gate. When false, `poll()` short-circuits.
    var enabled: Bool = true

    /// Injectable for tests. Production uses `SystemIdleProvider`.
    var provider: IdleSecondsProvider = SystemIdleProvider()

    private(set) var state: State = .present

    func poll() {
        guard enabled else { return }
        let secondsIdle = provider.secondsSinceLastEvent()
        let now = Date()

        switch state {
        case .present:
            if secondsIdle >= thresholdSecs {
                // Start of away window: approximate start as (now - secondsIdle).
                let start = now.addingTimeInterval(-secondsIdle)
                state = .away(since: start)
                NotificationCenter.default.post(name: .userAwayStarted, object: nil)
            }
        case .away(let since):
            if secondsIdle < returnHysteresisSecs {
                let duration = UInt64(max(0, now.timeIntervalSince(since)))
                state = .present
                NotificationCenter.default.post(
                    name: .userReturned,
                    object: nil,
                    userInfo: ["away_duration_secs": duration]
                )
            }
        }
    }
}
