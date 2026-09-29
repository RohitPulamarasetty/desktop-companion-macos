import Foundation
import Core

private func makeStore() throws -> ReminderStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("reminders-test-\(UUID().uuidString).sqlite")
    return try ReminderStore(fileURL: url)
}

func runReminderStoreTests(_ runner: TestRunner) {
    runner.run("ReminderStore.pendingAndNextDueDate_ignoreCompletedHistory") {
        let store = try makeStore()
        let soon = ReminderItem(title: "soon", fireDate: Date().addingTimeInterval(600))
        let later = ReminderItem(title: "later", fireDate: Date().addingTimeInterval(3600))
        let done = ReminderItem(title: "done", fireDate: Date().addingTimeInterval(-60))
        try store.add(soon); try store.add(later); try store.add(done)
        try store.dismiss(id: done.id)
        try expectEqual(try store.pending().map(\.title), ["soon", "later"])
        try expectEqual(try store.nextDueDate().map { Int($0.timeIntervalSince1970) }, Int(soon.fireDate.timeIntervalSince1970))
        try store.snooze(id: soon.id, until: Date().addingTimeInterval(7200))
        try expectEqual(try store.nextDueDate().map { Int($0.timeIntervalSince1970) }, Int(later.fireDate.timeIntervalSince1970))
    }

    runner.run("ReminderStore.addAndRetrieve") {
        let store = try makeStore()
        try store.add(ReminderItem(title: "Drink water", fireDate: Date()))
        let all = try store.all()
        try expectEqual(all.count, 1)
        try expectEqual(all[0].title, "Drink water")
    }

    runner.run("ReminderStore.due_includesPastFireDate") {
        let store = try makeStore()
        let past = Date().addingTimeInterval(-60)
        try store.add(ReminderItem(title: "Overdue", fireDate: past))
        let due = try store.due()
        try expectEqual(due.count, 1)
    }

    runner.run("ReminderStore.due_excludesFutureFireDate") {
        let store = try makeStore()
        let future = Date().addingTimeInterval(3600)
        try store.add(ReminderItem(title: "Later", fireDate: future))
        let due = try store.due()
        try expectTrue(due.isEmpty)
    }

    runner.run("ReminderStore.snooze_suppressesUntilSnoozeExpires") {
        let store = try makeStore()
        let reminder = ReminderItem(title: "Snoozeable", fireDate: Date().addingTimeInterval(-60))
        try store.add(reminder)
        try store.snooze(id: reminder.id, until: Date().addingTimeInterval(3600))
        let due = try store.due()
        try expectTrue(due.isEmpty)
    }

    runner.run("ReminderStore.dismiss_marksCompleted") {
        let store = try makeStore()
        let reminder = ReminderItem(title: "Dismiss me", fireDate: Date().addingTimeInterval(-60))
        try store.add(reminder)
        try store.dismiss(id: reminder.id)
        let due = try store.due()
        try expectTrue(due.isEmpty)
    }

    runner.run("ReminderStore.delete_removesReminder") {
        let store = try makeStore()
        let reminder = ReminderItem(title: "Temp", fireDate: Date())
        try store.add(reminder)
        try store.delete(id: reminder.id)
        try expectTrue(try store.all().isEmpty)
    }

    runner.run("ReminderStore.quietHours_suppressesDuringWindow") {
        let store = try makeStore()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 23
        let lateNight = calendar.date(from: components)!
        try store.add(ReminderItem(title: "Late reminder", fireDate: lateNight.addingTimeInterval(-3600)))

        let quietHours = QuietHours(startHour: 22, endHour: 7)
        let due = try store.due(referenceDate: lateNight, quietHours: quietHours)
        try expectTrue(due.isEmpty)
    }

    runner.run("ReminderStore.quietHours_allowsOutsideWindow") {
        let store = try makeStore()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        let afternoon = calendar.date(from: components)!
        try store.add(ReminderItem(title: "Afternoon reminder", fireDate: afternoon.addingTimeInterval(-3600)))

        let quietHours = QuietHours(startHour: 22, endHour: 7)
        let due = try store.due(referenceDate: afternoon, quietHours: quietHours)
        try expectEqual(due.count, 1)
    }

    runner.run("ReminderStore.recurringWeekly_spawnsSevenDaysLater") {
        let store = try makeStore()
        let calendar = Calendar.current
        let fireDate = Date()
        let reminder = ReminderItem(title: "Weekly review", fireDate: fireDate, recurrence: .weekly)
        try store.add(reminder)
        let next = try store.spawnNextOccurrenceIfRecurring(after: reminder, calendar: calendar)
        try expectNotNil(next)
        let expected = calendar.date(byAdding: .day, value: 7, to: fireDate)!
        try expectTrue(abs(next!.fireDate.timeIntervalSince(expected)) < 1)
    }

    runner.run("QuietHours.wrapsPastMidnight") {
        let quietHours = QuietHours(startHour: 22, endHour: 7)
        let calendar = Calendar.current
        var late = DateComponents(); late.year = 2026; late.month = 1; late.day = 1; late.hour = 23
        var early = DateComponents(); early.year = 2026; early.month = 1; early.day = 1; early.hour = 5
        var midday = DateComponents(); midday.year = 2026; midday.month = 1; midday.day = 1; midday.hour = 13
        try expectTrue(quietHours.contains(calendar.date(from: late)!))
        try expectTrue(quietHours.contains(calendar.date(from: early)!))
        try expectFalse(quietHours.contains(calendar.date(from: midday)!))
    }
}
