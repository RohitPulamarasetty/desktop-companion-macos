import Foundation

/// A Pomodoro routine: work sessions with short breaks, and a long break
/// after every `sessionsBeforeLongBreak` sessions.
public struct PomodoroPlan: Equatable {
    public var workMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    public var sessionsBeforeLongBreak: Int
    /// Start the next work session automatically when a break ends.
    public var autoStartNext: Bool

    public init(workMinutes: Double = 25, shortBreakMinutes: Double = 5, longBreakMinutes: Double = 15,
                sessionsBeforeLongBreak: Int = 4, autoStartNext: Bool = false) {
        self.workMinutes = min(max(workMinutes, 1), 240)
        self.shortBreakMinutes = min(max(shortBreakMinutes, 1), 60)
        self.longBreakMinutes = min(max(longBreakMinutes, 1), 120)
        self.sessionsBeforeLongBreak = min(max(sessionsBeforeLongBreak, 2), 10)
        self.autoStartNext = autoStartNext
    }

    public static let classic = PomodoroPlan()
    public static let deepWork = PomodoroPlan(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, sessionsBeforeLongBreak: 3)
    public static let quick = PomodoroPlan(workMinutes: 15, shortBreakMinutes: 3, longBreakMinutes: 10, sessionsBeforeLongBreak: 4)

    /// Is the break that follows the `completed`-th session of the current cycle a long one?
    public func isLongBreak(afterCompleted completed: Int) -> Bool {
        completed > 0 && completed % sessionsBeforeLongBreak == 0
    }

    public func breakMinutes(afterCompleted completed: Int) -> Double {
        isLongBreak(afterCompleted: completed) ? longBreakMinutes : shortBreakMinutes
    }

    /// "🍅🍅⚪⚪" — progress through the current cycle.
    public func cycleDots(completed: Int) -> String {
        let done = completed % sessionsBeforeLongBreak
        let shown = (completed > 0 && done == 0) ? sessionsBeforeLongBreak : done
        return String(repeating: "🍅", count: shown) + String(repeating: "⚪", count: sessionsBeforeLongBreak - shown)
    }
}
