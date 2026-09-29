import Foundation

/// Turns periodic "seconds since last input" samples into real active and
/// idle time, plus continuous-work time.
///
/// Over an interval of `dt` seconds ending now, the user's last input was
/// `s` seconds ago. They count as active until `idleThreshold` seconds after
/// that input, so the active share of the interval is
/// `clamp(dt - s + idleThreshold, 0, dt)`. Samples can be sparse (every 30 s)
/// without over- or under-counting, and long idle periods (or a locked /
/// sleeping Mac) add nothing.
public final class ActivityTracker {
    public let idleThreshold: TimeInterval
    /// Away this long = a natural break (resets continuous work).
    public let naturalBreak: TimeInterval
    /// Active seconds since the last break (natural or taken).
    public private(set) var continuousActive: TimeInterval = 0

    public init(idleThreshold: TimeInterval = 120, naturalBreak: TimeInterval = 300) {
        self.idleThreshold = idleThreshold
        self.naturalBreak = naturalBreak
    }

    public struct Sample: Equatable {
        public let active: TimeInterval
        public let idle: TimeInterval
        /// True when this sample shows the user has been away long enough
        /// to count as a break.
        public let wasNaturalBreak: Bool
        public init(active: TimeInterval, idle: TimeInterval, wasNaturalBreak: Bool) {
            self.active = active
            self.idle = idle
            self.wasNaturalBreak = wasNaturalBreak
        }
    }

    public func record(dt: TimeInterval, secondsSinceLastInput s: TimeInterval) -> Sample {
        let dt = max(0, dt)
        let active = min(max(dt - s + idleThreshold, 0), dt)
        let brk = s >= naturalBreak
        if brk { continuousActive = 0 } else { continuousActive += active }
        return Sample(active: active, idle: dt - active, wasNaturalBreak: brk)
    }

    /// The user took a break (or it was recorded).
    public func breakTaken() { continuousActive = 0 }

    public func isUserActive(secondsSinceLastInput s: TimeInterval) -> Bool { s < idleThreshold }
}
