import Foundation

/// Lightweight friendship/progression tracking. Deliberately just counters
/// and a first-launch date -- no energy meters, no streak-breaking penalty,
/// no forced daily login. UserDefaults-backed like AppSettings: this is a
/// handful of counters, not records worth querying.
public final class ProgressionStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(Date(), forKey: Key.firstLaunchDate)
        }
    }

    private enum Key {
        static let firstLaunchDate = "progression.firstLaunchDate"
        static let interactions = "progression.interactions"
        static let tasksCompleted = "progression.tasksCompleted"
        static let focusSessionsCompleted = "progression.focusSessionsCompleted"
        static let activeDayCount = "progression.activeDayCount"
        static let lastActiveDayIndex = "progression.lastActiveDayIndex"
    }

    public var firstLaunchDate: Date {
        (defaults.object(forKey: Key.firstLaunchDate) as? Date) ?? Date()
    }

    public func daysTogether(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstLaunchDate), to: calendar.startOfDay(for: referenceDate)).day ?? 0
        return max(1, days + 1) // day of first launch counts as day 1
    }

    public var interactions: Int {
        get { defaults.integer(forKey: Key.interactions) }
        set { defaults.set(newValue, forKey: Key.interactions) }
    }

    public var tasksCompleted: Int {
        get { defaults.integer(forKey: Key.tasksCompleted) }
        set { defaults.set(newValue, forKey: Key.tasksCompleted) }
    }

    public var focusSessionsCompleted: Int {
        get { defaults.integer(forKey: Key.focusSessionsCompleted) }
        set { defaults.set(newValue, forKey: Key.focusSessionsCompleted) }
    }

    public func recordTaskCompleted() { tasksCompleted += 1 }
    public func recordFocusSessionCompleted() { focusSessionsCompleted += 1 }

    /// Overwrites every persisted field at once -- used only by
    /// `DataPortability` import, after the incoming data has already been
    /// fully validated. Never called with partially-checked data.
    public func restore(firstLaunchDate: Date, interactions: Int, activeDayCount: Int, tasksCompleted: Int = 0, focusSessionsCompleted: Int = 0) {
        defaults.set(firstLaunchDate, forKey: Key.firstLaunchDate)
        self.interactions = interactions
        self.activeDayCount = activeDayCount
        self.tasksCompleted = tasksCompleted
        self.focusSessionsCompleted = focusSessionsCompleted
    }

    public func recordInteraction() { interactions += 1 }

    /// Distinct calendar days on which at least one interaction was
    /// recorded. Deliberately *not* the raw `interactions`
    /// count: that resets to a small, bounded number that can't be
    /// inflated by rapid clicking within a single day -- the relationship
    /// system's anti-farming guarantee lives here, not in a cooldown.
    public var activeDayCount: Int {
        get { defaults.integer(forKey: Key.activeDayCount) }
        set { defaults.set(newValue, forKey: Key.activeDayCount) }
    }

    /// `recordInteraction()`'s own day-tracking companion: call this
    /// alongside it (or standalone) to bump `activeDayCount` at most once
    /// per calendar day, regardless of how many interactions happen that
    /// day. `now`/`calendar` are injectable for deterministic testing.
    public func recordActiveDay(now: Date = Date(), calendar: Calendar = .current) {
        let dayIndex = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: calendar.startOfDay(for: now)).day ?? 0
        guard defaults.object(forKey: Key.lastActiveDayIndex) == nil || defaults.integer(forKey: Key.lastActiveDayIndex) != dayIndex else { return }
        defaults.set(dayIndex, forKey: Key.lastActiveDayIndex)
        activeDayCount += 1
    }

    /// Simple milestone unlocks -- cosmetic labels only, nothing gates core
    /// functionality behind these, and nothing punishes not reaching them.
    public struct Milestone {
        public let title: String
        public let isUnlocked: Bool
    }

    /// Familiarity, 0.4...1.0: a bounded, farming-resistant
    /// blend of calendar time (the floor -- gradually reaches 1.0 over
    /// ~2 weeks regardless of usage) and a small bonus for having
    /// actually been used on multiple distinct days (capped at +0.1,
    /// reached over 10 active days). A pure function so it's directly
    /// testable without needing a live ProgressionStore/Date: rapid
    /// clicking can inflate `interactions` in a single sitting, but
    /// `activeDayCount` only ever increments once per real calendar day,
    /// so no amount of clicking on day one can push this past
    /// `0.4 + 0.6/14 + 0.1` -- nowhere near "high familiarity."
    public static func familiarity(daysTogether: Int, activeDayCount: Int) -> Double {
        let timeFloor = 0.4 + 0.6 * min(1, Double(daysTogether) / 14)
        let engagementBonus = 0.1 * min(1, Double(activeDayCount) / 10)
        return min(1, timeFloor + engagementBonus)
    }

    /// Plain-language description of how well the companion knows the user.
    public static func familiarityLabel(_ familiarity: Double) -> String {
        switch familiarity {
        case ..<0.5: return "Just met"
        case ..<0.75: return "Getting comfortable"
        case ..<0.95: return "Good friends"
        default: return "Best friends"
        }
    }

    public func milestones() -> [Milestone] {
        [
            Milestone(title: "First day together", isUnlocked: daysTogether() >= 1),
            Milestone(title: "A week together", isUnlocked: daysTogether() >= 7),
            Milestone(title: "Two weeks together", isUnlocked: daysTogether() >= 14),
            Milestone(title: "50 interactions", isUnlocked: interactions >= 50),
            Milestone(title: "500 interactions", isUnlocked: interactions >= 500),
            Milestone(title: "First task done", isUnlocked: tasksCompleted >= 1),
            Milestone(title: "25 tasks done", isUnlocked: tasksCompleted >= 25),
            Milestone(title: "First focus session", isUnlocked: focusSessionsCompleted >= 1),
            Milestone(title: "25 focus sessions", isUnlocked: focusSessionsCompleted >= 25),
        ]
    }
}
