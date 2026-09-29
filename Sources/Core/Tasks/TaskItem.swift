import Foundation

public enum TaskPriority: Int, Codable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
}

public enum RecurrenceRule: String, Codable, CaseIterable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    public var displayName: String {
        switch self {
        case .none: return "Doesn't repeat"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    /// The occurrence after `date`, or nil for `.none`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date)
            while let x = d, calendar.isDateInWeekend(x) { d = calendar.date(byAdding: .day, value: 1, to: x) }
            return d
        }
    }
}

public struct TaskItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var priority: TaskPriority
    public var dueDate: Date?
    public var recurrence: RecurrenceRule
    public var isCompleted: Bool
    public let createdAt: Date
    public var completedAt: Date?
    public var notes: String
    /// false = due some time that day (the date part of `dueDate` only).
    public var hasDueTime: Bool
    /// Deadline reminder: remind this many minutes before the deadline
    /// (nil = no deadline reminder). 1440 = one day before.
    public var remindBeforeMinutes: Int?
    /// Separate, recurring nudge until the task is done ("every 45 min").
    /// Not the same thing as the deadline reminder.
    public var repeatEveryMinutes: Int?
    /// Reminder bookkeeping: snoozed until / last handled (done, dismissed,
    /// snoozed) -- so reminders survive restarts and never re-fire a stage
    /// the user already dealt with.
    public var reminderSnoozedUntil: Date?
    public var reminderHandledAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        recurrence: RecurrenceRule = .none,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        notes: String = "",
        hasDueTime: Bool = false,
        remindBeforeMinutes: Int? = nil,
        repeatEveryMinutes: Int? = nil,
        reminderSnoozedUntil: Date? = nil,
        reminderHandledAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.notes = notes
        self.hasDueTime = hasDueTime
        self.remindBeforeMinutes = remindBeforeMinutes
        self.repeatEveryMinutes = repeatEveryMinutes
        self.reminderSnoozedUntil = reminderSnoozedUntil
        self.reminderHandledAt = reminderHandledAt
    }

    /// True if the task belongs on today's list: no due date (quick
    /// capture), due today, or overdue.
    public func isDueToday(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return true }
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        return dueDate < endOfToday
    }

    /// The moment the task is due: the exact time, or the end of its day.
    public func deadline(calendar: Calendar = .current) -> Date? {
        guard let dueDate else { return nil }
        if hasDueTime { return dueDate }
        let start = calendar.startOfDay(for: dueDate)
        return calendar.date(byAdding: DateComponents(hour: 23, minute: 59), to: start)
    }
}
