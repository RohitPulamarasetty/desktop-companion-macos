import Foundation
import Core

private func makeStore() throws -> ScreenTimeStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("screentime-test-\(UUID().uuidString).sqlite")
    return try ScreenTimeStore(fileURL: url)
}

func runScreenTimeStoreTests(_ runner: TestRunner) {
    runner.run("ScreenTimeStore.addActiveSeconds_accumulates") {
        let store = try makeStore()
        try store.addActiveSeconds(30)
        try store.addActiveSeconds(15)
        let totals = try store.totals()
        try expectEqual(totals.activeSeconds, 45)
    }

    runner.run("ScreenTimeStore.tracksActiveIdleFocusIndependently") {
        let store = try makeStore()
        try store.addActiveSeconds(100)
        try store.addIdleSeconds(20)
        try store.addFocusSeconds(50)
        let totals = try store.totals()
        try expectEqual(totals.activeSeconds, 100)
        try expectEqual(totals.idleSeconds, 20)
        try expectEqual(totals.focusSeconds, 50)
    }

    runner.run("ScreenTimeStore.separateDays_areIndependent") {
        let store = try makeStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try store.addActiveSeconds(100, date: yesterday)
        try store.addActiveSeconds(30, date: Date())
        let todayTotals = try store.totals()
        try expectEqual(todayTotals.activeSeconds, 30)
    }

    runner.run("ActivityClassifier.belowThreshold_isActive") {
        try expectTrue(ActivityClassifier.isActive(secondsSinceLastInput: 5, idleThresholdSeconds: 90))
    }

    runner.run("ActivityClassifier.aboveThreshold_isIdle") {
        try expectFalse(ActivityClassifier.isActive(secondsSinceLastInput: 200, idleThresholdSeconds: 90))
    }
}
