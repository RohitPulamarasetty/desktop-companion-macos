import Foundation

/// Everything the pet may need to bring to the user's attention.
public enum ReminderKind: String, CaseIterable {
    case task, focus, water, screenBreak, custom, eyeBreak, stretch, bedtime

    /// Base priority when several things are due at once.
    public var basePriority: Int {
        switch self {
        case .task: return 60
        case .focus: return 80
        case .custom: return 55
        case .water: return 40
        case .screenBreak: return 30
        case .eyeBreak: return 28
        case .stretch: return 26
        case .bedtime: return 35
        }
    }

    /// Snooze choices offered for this kind (seconds; `nil` = "tomorrow
    /// morning"). Tasks can be pushed further out than wellness nudges.
    public var snoozeOptions: [(label: String, seconds: TimeInterval?)] {
        switch self {
        case .task: return [("10 min", 600), ("30 min", 1800), ("1 hour", 3600), ("Tomorrow", nil)]
        case .custom: return [("10 min", 600), ("30 min", 1800), ("1 hour", 3600)]
        case .water, .screenBreak, .eyeBreak, .stretch: return [("10 min", 600), ("20 min", 1200), ("30 min", 1800)]
        case .bedtime: return [("15 min", 900), ("30 min", 1800)]
        case .focus: return [("5 min", 300), ("10 min", 600)]
        }
    }
}

/// How insistent a reminder is. Task deadlines escalate:
/// a day before = gentle, an hour before = noticeable, at the deadline = important.
public enum ReminderUrgency: Int, Comparable {
    case gentle = 0, noticeable = 1, important = 2
    public static func < (a: ReminderUrgency, b: ReminderUrgency) -> Bool { a.rawValue < b.rawValue }
}

/// One thing that is (or will be) due.
public struct DueReminder: Equatable {
    public let id: String
    public let kind: ReminderKind
    public let dueAt: Date
    public let title: String
    public let urgency: ReminderUrgency
    /// Allowed to break through quiet hours (important task deadlines, if
    /// the user allows it).
    public let breaksQuietHours: Bool
    public let taskID: UUID?

    public init(id: String, kind: ReminderKind, dueAt: Date, title: String, urgency: ReminderUrgency = .noticeable,
                breaksQuietHours: Bool = false, taskID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.dueAt = dueAt
        self.title = title
        self.urgency = urgency
        self.breaksQuietHours = breaksQuietHours
        self.taskID = taskID
    }

    public var priority: Int { kind.basePriority + urgency.rawValue * 15 }
}

/// When a task's next reminder is, and how insistent. Pure function of the
/// task's fields and `now`, so it survives restarts and is fully tested.
///
/// Two separate ideas, never conflated:
///  - deadline reminder (`remindBeforeMinutes`): fires that long before the
///    deadline; if that's a day or more ahead, it's gentle and followed by a
///    noticeable one an hour before; a task with a due *time* also gets an
///    important one at the deadline itself.
///  - repeating nudge (`repeatEveryMinutes`): "every 45 min until it's done",
///    counted from the last time the user dealt with it.
public enum TaskReminderPlanner {
    public static func next(for task: TaskItem, now: Date, calendar: Calendar = .current) -> DueReminder? {
        guard !task.isCompleted else { return nil }
        let handled = task.reminderHandledAt ?? .distantPast
        var candidates: [(Date, ReminderUrgency, String)] = []

        if let before = task.remindBeforeMinutes, let deadline = task.deadline(calendar: calendar) {
            var stages: [(Date, ReminderUrgency)] = []
            let first = deadline.addingTimeInterval(-Double(before) * 60)
            stages.append((first, before >= 1440 ? .gentle : .noticeable))
            if before > 60 { stages.append((deadline.addingTimeInterval(-3600), .noticeable)) }
            if task.hasDueTime { stages.append((deadline, .important)) }
            // The earliest stage the user hasn't dealt with yet.
            if let stage = stages.sorted(by: { $0.0 < $1.0 }).first(where: { $0.0 > handled }) {
                candidates.append((stage.0, stage.1, "deadline"))
            }
        }
        if let every = task.repeatEveryMinutes, every > 0 {
            let base = max(handled, task.createdAt)
            candidates.append((base.addingTimeInterval(Double(every) * 60), .gentle, "repeat"))
        }
        guard var best = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        if let snoozed = task.reminderSnoozedUntil, snoozed > best.0 { best.0 = snoozed }
        return DueReminder(id: "task:\(task.id.uuidString)", kind: .task, dueAt: best.0, title: task.title,
                           urgency: best.1, breaksQuietHours: best.1 == .important && task.priority == .high, taskID: task.id)
    }
}

/// The one reminder engine: holds everything that's scheduled, decides
/// what (if anything) to present right now, presents one thing at a time,
/// and says when it next needs to wake up. No timers inside -- the app
/// sleeps until `nextWakeDate` and asks `next(...)`.
public final class ReminderQueue {
    public private(set) var items: [String: DueReminder] = [:]
    public private(set) var presenting: DueReminder?

    public init() {}

    /// Adds, replaces (same id) or removes (`nil`) one scheduled reminder.
    public func set(_ id: String, _ reminder: DueReminder?) {
        items[id] = reminder
    }

    /// Replaces all reminders of a kind (e.g. all task reminders at once).
    public func replaceAll(of kind: ReminderKind, with reminders: [DueReminder]) {
        items = items.filter { $0.value.kind != kind }
        for r in reminders { items[r.id] = r }
    }

    /// Earliest moment something could become presentable.
    public var nextWakeDate: Date? {
        items.values.filter { $0.id != presenting?.id }.map(\.dueAt).min()
    }

    public struct Conditions {
        public var quietHours = false
        public var focusActive = false
        public var userAway = false
        public var allowUrgentInQuietHours = true
        public init() {}
    }

    /// Whether a reminder may interrupt under the current conditions.
    public static func allowed(_ r: DueReminder, _ c: Conditions) -> Bool {
        if c.userAway { return false }
        if c.quietHours { return r.breaksQuietHours && (c.allowUrgentInQuietHours || r.kind == .bedtime) }
        if c.focusActive {
            // During focus only the focus session itself and important
            // task deadlines interrupt.
            return r.kind == .focus || (r.kind == .task && r.urgency == .important)
        }
        return true
    }

    /// The highest-priority reminder that is due and allowed, if nothing is
    /// being presented already. Marks it as presenting.
    public func next(now: Date, conditions: Conditions) -> DueReminder? {
        guard presenting == nil else { return nil }
        let due = items.values.filter { $0.dueAt <= now && Self.allowed($0, conditions) }
        guard let pick = due.max(by: { ($0.priority, -$0.dueAt.timeIntervalSince1970) < ($1.priority, -$1.dueAt.timeIntervalSince1970) }) else {
            return nil
        }
        presenting = pick
        return pick
    }

    /// The presented reminder was answered (done / snoozed / dismissed /
    /// timed out). The caller updates the underlying schedule and calls
    /// `set` with the reminder's next occurrence (or nil).
    public func finishPresenting() {
        if let p = presenting { items[p.id] = nil }
        presenting = nil
    }
}
