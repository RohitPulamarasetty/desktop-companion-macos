import Foundation

/// Consecutive-days streaks for "did something productive today".
public enum StreakCalculator {
    /// The number of consecutive days, ending today (or yesterday, so a streak
    /// isn't lost before you've had a chance to do today's thing), that appear
    /// in `activeDays` (any date within each day is fine).
    public static func streak(activeDays: [Date], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
