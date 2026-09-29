import Foundation
import Core

private func makeStore() throws -> WellnessStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wellness-test-\(UUID().uuidString).sqlite")
    return try WellnessStore(fileURL: url)
}

func runWellnessStoreTests(_ runner: TestRunner) {
    runner.run("WellnessStore.addAndRetrieve") {
        let store = try makeStore()
        try store.add(WellnessEntry(kind: .water, action: .done))
        let all = try store.all()
        try expectEqual(all.count, 1)
        try expectEqual(all[0].kind, .water)
        try expectEqual(all[0].action, .done)
    }

    runner.run("WellnessStore.todayDoneCount_countsOnlyDoneActionsOfMatchingKind") {
        let store = try makeStore()
        try store.add(WellnessEntry(kind: .water, action: .done))
        try store.add(WellnessEntry(kind: .water, action: .done))
        try store.add(WellnessEntry(kind: .water, action: .snoozed))
        try store.add(WellnessEntry(kind: .shortBreak, action: .done))
        let waterDone = try store.todayDoneCount(kind: .water)
        try expectEqual(waterDone, 2)
        let breakDone = try store.todayDoneCount(kind: .shortBreak)
        try expectEqual(breakDone, 1)
    }

    runner.run("WellnessStore.today_excludesOtherDays") {
        let store = try makeStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try store.add(WellnessEntry(kind: .longBreak, action: .done, timestamp: yesterday))
        let todayEntries = try store.today(kind: .longBreak)
        try expectTrue(todayEntries.isEmpty)
    }

    runner.run("WellnessStore.dayQueryAndLastDoneUseTheIndex") {
        let store = try WellnessStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString).sqlite"))
        try store.add(WellnessEntry(kind: .water, action: .done, timestamp: Date().addingTimeInterval(-3 * 86400)))
        try store.add(WellnessEntry(kind: .water, action: .done, timestamp: Date().addingTimeInterval(-60)))
        try store.add(WellnessEntry(kind: .water, action: .skipped))
        try store.add(WellnessEntry(kind: .focusBreak, action: .done))
        try expectEqual(try store.todayDoneCount(kind: .water), 1)
        try expectEqual(try store.todayDoneCount(kind: .focusBreak), 1)
        let last = try store.lastDone(kind: .water)!
        try expectTrue(abs(last.timeIntervalSinceNow + 60) < 2)
    }

    runner.run("Nudge.snoozeDelaysByTheChosenAmount") {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let n = NudgeSchedule(enabled: true, interval: 1800, anchor: t0)
        n.beginAsking()
        n.snooze(now: t0.addingTimeInterval(1900), seconds: 1200)
        try expectEqual(n.nextDue, t0.addingTimeInterval(1900 + 1200))
        try expectFalse(n.isAsking)
    }
}
