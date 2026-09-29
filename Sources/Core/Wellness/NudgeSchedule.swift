import Foundation

/// When to ask about water or a break. Pure logic, no timers: the app asks
/// `nextCheck(...)` for the one moment it needs to wake up, and calls
/// `confirm` / `skip` / `timedOut` with the user's answer. Nothing polls.
///
/// Rules:
///  - asks `interval` after the last confirmation (or skip)
///  - never during quiet hours or a focus session (waits until after)
///  - never to an empty room (user idle): waits until they're back
///  - never on top of another question (`busy`)
///  - Skip: not asked again for at least `interval`, and never sooner than
///    `minimumSkipCooldown`
///  - no answer (bubble timed out): asks again after `retryAfterTimeout`
public final class NudgeSchedule {
    public enum Decision: Equatable {
        case disabled
        case ask
        case wait(until: Date)
    }

    public var enabled: Bool
    public var interval: TimeInterval
    public let minimumSkipCooldown: TimeInterval
    public let retryAfterTimeout: TimeInterval
    /// Last confirmation or skip (persisted by the app).
    public private(set) var anchor: Date
    public private(set) var notBefore: Date?
    public private(set) var isAsking = false

    public init(enabled: Bool, interval: TimeInterval, anchor: Date,
                minimumSkipCooldown: TimeInterval = 20 * 60, retryAfterTimeout: TimeInterval = 15 * 60) {
        self.enabled = enabled
        self.interval = max(60, interval)
        self.anchor = anchor
        self.minimumSkipCooldown = minimumSkipCooldown
        self.retryAfterTimeout = retryAfterTimeout
    }

    public var nextDue: Date? {
        guard enabled else { return nil }
        let due = anchor.addingTimeInterval(interval)
        if let notBefore, notBefore > due { return notBefore }
        return due
    }

    /// What to do at `now`. `.wait(until:)` is the next moment worth checking.
    public func evaluate(now: Date, userIdleSeconds: Double, focusActive: Bool, quietHours: QuietHours?, busy: Bool,
                         calendar: Calendar = .current) -> Decision {
        guard enabled, let due = nextDue else { return .disabled }
        if isAsking { return .wait(until: now.addingTimeInterval(60)) }
        if now < due { return .wait(until: due) }
        if let q = quietHours, q.contains(now, calendar: calendar) {
            // Check again at the top of the next hour (quiet hours are hourly).
            let next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            return .wait(until: next)
        }
        if focusActive { return .wait(until: now.addingTimeInterval(5 * 60)) }
        if userIdleSeconds > 120 { return .wait(until: now.addingTimeInterval(2 * 60)) }
        if busy { return .wait(until: now.addingTimeInterval(2 * 60)) }
        return .ask
    }

    public func beginAsking() { isAsking = true }

    /// "I drank" / "Take a break" (or the user logged it some other way).
    public func confirm(now: Date) {
        anchor = now
        notBefore = nil
        isAsking = false
    }

    /// "Skip": respect a cooldown; never re-ask right away.
    public func skip(now: Date) {
        anchor = now
        notBefore = now.addingTimeInterval(max(minimumSkipCooldown, 0))
        isAsking = false
    }

    /// "Snooze": ask again after `seconds`.
    public func snooze(now: Date, seconds: TimeInterval) {
        notBefore = now.addingTimeInterval(seconds)
        anchor = min(anchor, now) // keep the interval anchor; snooze just delays
        isAsking = false
    }

    /// The question went unanswered.
    public func timedOut(now: Date) {
        notBefore = now.addingTimeInterval(retryAfterTimeout)
        anchor = now.addingTimeInterval(retryAfterTimeout - interval)
        isAsking = false
    }

    /// A natural break (the user was away) counts for the break schedule.
    public func noteNaturalReset(now: Date) {
        guard !isAsking else { return }
        anchor = now
        notBefore = nil
    }
}
