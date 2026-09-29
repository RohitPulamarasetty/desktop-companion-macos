import Foundation
import Core

private func makeStore() throws -> TaskStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-test-\(UUID().uuidString).sqlite")
    return try TaskStore(fileURL: url)
}

func runTaskStoreTests(_ runner: TestRunner) {
    runner.run("TaskStore.completedOnDay_onlyReturnsThatDaysCompletions") {
        let store = try makeStore()
        let today = TaskItem(title: "today"), yesterday = TaskItem(title: "yesterday"), open = TaskItem(title: "open")
        try store.add(today); try store.add(yesterday); try store.add(open)
        try store.complete(id: today.id)
        try store.complete(id: yesterday.id, completedAt: Date().addingTimeInterval(-86_400 * 1.5))
        try expectEqual(try store.completedOnDay().map(\.title), ["today"])
        try expectEqual(try store.incomplete().map(\.title), ["open"])
    }

    runner.run("TaskStore.addAndRetrieve") {
        let store = try makeStore()
        let task = TaskItem(title: "Finish ML assignment")
        try store.add(task)
        let all = try store.all()
        try expectEqual(all.count, 1)
        try expectEqual(all[0].title, "Finish ML assignment")
        try expectFalse(all[0].isCompleted)
    }

    runner.run("TaskStore.complete_setsCompletedAtAndFlag") {
        let store = try makeStore()
        let task = TaskItem(title: "Water the plants")
        try store.add(task)
        try store.complete(id: task.id)
        let all = try store.all()
        try expectTrue(all[0].isCompleted)
        try expectNotNil(all[0].completedAt)
    }

    runner.run("TaskStore.uncomplete_clearsCompletedAt") {
        let store = try makeStore()
        let task = TaskItem(title: "Reply to email")
        try store.add(task)
        try store.complete(id: task.id)
        try store.uncomplete(id: task.id)
        let all = try store.all()
        try expectFalse(all[0].isCompleted)
    }

    runner.run("TaskStore.delete_removesTask") {
        let store = try makeStore()
        let task = TaskItem(title: "Temporary")
        try store.add(task)
        try store.delete(id: task.id)
        let all = try store.all()
        try expectTrue(all.isEmpty)
    }

    runner.run("TaskStore.update_changesFields") {
        let store = try makeStore()
        var task = TaskItem(title: "Draft", priority: .low)
        try store.add(task)
        task.title = "Draft v2"
        task.priority = .high
        try store.update(task)
        let all = try store.all()
        try expectEqual(all[0].title, "Draft v2")
        try expectEqual(all[0].priority, .high)
    }

    runner.run("TaskStore.today_excludesCompletedAndFutureDated") {
        let store = try makeStore()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!

        let dueToday = TaskItem(title: "Today task")
        let dueTomorrow = TaskItem(title: "Tomorrow task", dueDate: tomorrow)
        let noDate = TaskItem(title: "No date task")
        let completedToday = TaskItem(title: "Completed today", isCompleted: true)

        try store.add(dueToday)
        try store.add(dueTomorrow)
        try store.add(noDate)
        try store.add(completedToday)

        let today = try store.today()
        let titles = Set(today.map(\.title))
        try expectTrue(titles.contains("Today task"))
        try expectTrue(titles.contains("No date task"))
        try expectFalse(titles.contains("Tomorrow task"))
        try expectFalse(titles.contains("Completed today"))
    }

    runner.run("TaskStore.recurringDaily_spawnsNextOccurrence") {
        let store = try makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let task = TaskItem(title: "Daily standup", dueDate: today, recurrence: .daily)
        try store.add(task)
        try store.complete(id: task.id)

        let next = try store.spawnNextOccurrenceIfRecurring(after: task, calendar: calendar)
        try expectNotNil(next)
        try expectEqual(next?.title, "Daily standup")
        try expectFalse(next?.isCompleted ?? true)
        let expectedNextDate = calendar.date(byAdding: .day, value: 1, to: today)!
        try expectTrue(calendar.isDate(next!.dueDate!, inSameDayAs: expectedNextDate))

        let all = try store.all()
        try expectEqual(all.count, 2) // original + spawned occurrence
    }

    runner.run("TaskStore.nonRecurring_doesNotSpawn") {
        let store = try makeStore()
        let task = TaskItem(title: "One-off")
        try store.add(task)
        let next = try store.spawnNextOccurrenceIfRecurring(after: task)
        try expectTrue(next == nil)
    }

    runner.run("TaskStore.persistsAcrossReopen") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-persist-\(UUID().uuidString).sqlite")
        let task = TaskItem(title: "Persisted task")
        do {
            let store = try TaskStore(fileURL: url)
            try store.add(task)
        }
        let reopened = try TaskStore(fileURL: url)
        let all = try reopened.all()
        try expectEqual(all.count, 1)
        try expectEqual(all[0].title, "Persisted task")
    }
}
