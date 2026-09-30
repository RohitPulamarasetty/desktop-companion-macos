import Foundation

/// How much unprompted talking is acceptable. A friend who is always chattering is tiring, so spontaneous
/// remarks (idle thoughts, mood lines, check-ins) share one budget: a minimum gap that grows at night and
/// shrinks only for a talkative character. Answers to things the user did are never limited by this.
public enum SpeechBudget {
    public static let baseGap: TimeInterval = 7 * 60

    public static func isNight(hour: Int) -> Bool { hour >= 22 || hour < 6 }

    public static func minimumGap(chattiness: Double, hour: Int) -> TimeInterval {
        let chatty = min(max(chattiness, 0.5), 2)
        return baseGap / chatty * (isNight(hour: hour) ? 2.5 : 1)
    }

    public static func allows(now: Date, lastSpontaneous: Date?, chattiness: Double, hour: Int) -> Bool {
        guard let last = lastSpontaneous else { return true }
        return now.timeIntervalSince(last) >= minimumGap(chattiness: chattiness, hour: hour)
    }
}
