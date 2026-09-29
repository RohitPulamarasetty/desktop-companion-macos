import Foundation
import Core

func runReminderEngineTests(_ runner: TestRunner) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func task(due: Date?, time: Bool = true, before: Int? = nil, every: Int? = nil, priority: TaskPriority = .medium,
              handled: Date? = nil, snoozed: Date? = nil) -> TaskItem {
        TaskItem(title: "Report", priority: priority, dueDate: due, createdAt: now.addingTimeInterval(-7200), hasDueTime: time,
                 remindBeforeMinutes: before, repeatEveryMinutes: every, reminderSnoozedUntil: snoozed, reminderHandledAt: handled)
    }

    runner.run("TaskReminder.deadlineReminderFiresBeforeTheDeadline") {
        let t = task(due: now.addingTimeInterval(3 * 3600), before: 30)
        let r = TaskReminderPlanner.next(for: t, now: now, calendar: cal)
        try expectEqual(r?.dueAt, now.addingTimeInterval(3 * 3600 - 1800))
        try expectEqual(r?.urgency, .noticeable)
    }

    runner.run("TaskReminder.escalates_gentleThenNoticeableThenImportant") {
        let due = now.addingTimeInterval(2 * 86400)
        let t0 = task(due: due, before: 1440)
        let r0 = TaskReminderPlanner.next(for: t0, now: now, calendar: cal)!
        try expectEqual(r0.urgency, .gentle)
        try expectEqual(r0.dueAt, due.addingTimeInterval(-86400))
        let r1 = TaskReminderPlanner.next(for: task(due: due, before: 1440, handled: r0.dueAt), now: now, calendar: cal)!
        try expectEqual(r1.urgency, .noticeable)
        try expectEqual(r1.dueAt, due.addingTimeInterval(-3600))
        let r2 = TaskReminderPlanner.next(for: task(due: due, before: 1440, handled: r1.dueAt), now: now, calendar: cal)!
        try expectEqual(r2.urgency, .important)
        try expectEqual(r2.dueAt, due)
        try expectTrue(TaskReminderPlanner.next(for: task(due: due, before: 1440, handled: due), now: now, calendar: cal) == nil)
    }

    runner.run("TaskReminder.repeatingNudgeIsSeparateFromDeadline") {
        let t = task(due: nil, every: 45)
        let r = TaskReminderPlanner.next(for: t, now: now, calendar: cal)!
        try expectEqual(r.dueAt, t.createdAt.addingTimeInterval(45 * 60))
        let after = TaskReminderPlanner.next(for: task(due: nil, every: 45, handled: now), now: now, calendar: cal)!
        try expectEqual(after.dueAt, now.addingTimeInterval(45 * 60))
        try expectTrue(TaskReminderPlanner.next(for: task(due: nil), now: now, calendar: cal) == nil)
    }

    runner.run("TaskReminder.snoozeDelays_completedNeverReminds") {
        let due = now.addingTimeInterval(3600)
        let r = TaskReminderPlanner.next(for: task(due: due, before: 30, snoozed: now.addingTimeInterval(2400)), now: now, calendar: cal)!
        try expectEqual(r.dueAt, now.addingTimeInterval(2400))
        var done = task(due: due, before: 30)
        done.isCompleted = true
        try expectTrue(TaskReminderPlanner.next(for: done, now: now, calendar: cal) == nil)
    }

    runner.run("TaskReminder.dateOnlyDeadlineIsEndOfThatDay") {
        let day = cal.startOfDay(for: now).addingTimeInterval(86400)
        let t = task(due: day, time: false, before: 60)
        let r = TaskReminderPlanner.next(for: t, now: now, calendar: cal)!
        try expectEqual(r.dueAt, day.addingTimeInterval(23 * 3600 + 59 * 60 - 3600))
    }

    runner.run("ReminderQueue.presentsOneAtATime_highestPriorityFirst") {
        let q = ReminderQueue()
        q.set("water", DueReminder(id: "water", kind: .water, dueAt: now.addingTimeInterval(-60), title: "Water"))
        q.set("break", DueReminder(id: "break", kind: .screenBreak, dueAt: now.addingTimeInterval(-120), title: "Break"))
        q.set("task:1", DueReminder(id: "task:1", kind: .task, dueAt: now.addingTimeInterval(-10), title: "Report", urgency: .important))
        q.set("later", DueReminder(id: "later", kind: .task, dueAt: now.addingTimeInterval(600), title: "Later"))
        let c = ReminderQueue.Conditions()
        try expectEqual(q.next(now: now, conditions: c)?.id, "task:1")
        try expectTrue(q.next(now: now, conditions: c) == nil) // one at a time
        q.finishPresenting()
        try expectEqual(q.next(now: now, conditions: c)?.id, "water")
        q.finishPresenting()
        try expectEqual(q.next(now: now, conditions: c)?.id, "break")
        q.finishPresenting()
        try expectTrue(q.next(now: now, conditions: c) == nil)
        try expectEqual(q.nextWakeDate, now.addingTimeInterval(600))
    }

    runner.run("ReminderQueue.quietHoursFocusAndAwayRules") {
        let q = ReminderQueue()
        q.set("water", DueReminder(id: "water", kind: .water, dueAt: now, title: "Water"))
        q.set("t", DueReminder(id: "t", kind: .task, dueAt: now, title: "Due", urgency: .important, breaksQuietHours: true))
        var quiet = ReminderQueue.Conditions(); quiet.quietHours = true
        try expectEqual(q.next(now: now, conditions: quiet)?.id, "t")
        q.finishPresenting()
        try expectTrue(q.next(now: now, conditions: quiet) == nil) // water waits out quiet hours
        quiet.allowUrgentInQuietHours = false
        q.set("t", DueReminder(id: "t", kind: .task, dueAt: now, title: "Due", urgency: .important, breaksQuietHours: true))
        try expectTrue(q.next(now: now, conditions: quiet) == nil)
        var focus = ReminderQueue.Conditions(); focus.focusActive = true
        try expectEqual(q.next(now: now, conditions: focus)?.id, "t")
        q.finishPresenting()
        try expectTrue(q.next(now: now, conditions: focus) == nil)
        var away = ReminderQueue.Conditions(); away.userAway = true
        try expectTrue(q.next(now: now, conditions: away) == nil)
    }

    runner.run("ReminderKind.snoozeOptionsDependOnType") {
        try expectEqual(ReminderKind.task.snoozeOptions.map(\.label), ["10 min", "30 min", "1 hour", "Tomorrow"])
        try expectEqual(ReminderKind.water.snoozeOptions.map(\.label), ["10 min", "20 min", "30 min"])
    }

    runner.run("TaskStore.v2FieldsRoundTrip_andOldDatabasesMigrate") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-v2-\(UUID().uuidString).sqlite")
        do { // an old-format database
            let db = try SQLiteDatabase(fileURL: url)
            try db.execute("CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, priority INTEGER NOT NULL, dueDate TEXT, recurrence TEXT NOT NULL, isCompleted INTEGER NOT NULL, createdAt TEXT NOT NULL, completedAt TEXT)")
            try db.execute("INSERT INTO tasks VALUES ('\(UUID().uuidString)', 'old task', 1, NULL, 'none', 0, '2026-09-01T10:00:00.000Z', NULL)")
        }
        let store = try TaskStore(fileURL: url)
        try expectEqual(try store.all().map(\.title), ["old task"])
        let t = TaskItem(title: "new", dueDate: now, notes: "details", hasDueTime: true, remindBeforeMinutes: 45, repeatEveryMinutes: 30,
                         reminderSnoozedUntil: now.addingTimeInterval(60), reminderHandledAt: now)
        try store.add(t)
        let back = try store.task(id: t.id)!
        try expectEqual(back.notes, "details")
        try expectTrue(back.hasDueTime)
        try expectEqual(back.remindBeforeMinutes, 45)
        try expectEqual(back.repeatEveryMinutes, 30)
        try expectEqual(back.reminderSnoozedUntil.map { Int($0.timeIntervalSince1970) }, Int(now.timeIntervalSince1970) + 60)
        try expectEqual(try store.withReminders().map(\.title), ["new"])
    }

    runner.run("TaskItem.overdueTasksStayOnTodaysList") {
        let yesterday = Date().addingTimeInterval(-86400)
        try expectTrue(TaskItem(title: "late", dueDate: yesterday).isDueToday())
        try expectFalse(TaskItem(title: "future", dueDate: Date().addingTimeInterval(3 * 86400)).isDueToday())
    }
}
