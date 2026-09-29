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

func runActivityTrackerTests(_ runner: TestRunner) {
    runner.run("ActivityTracker.countsOnlyRealActivity") {
        let t = ActivityTracker(idleThreshold: 120, naturalBreak: 300)
        // Typing continuously: whole interval active.
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 2), .init(active: 30, idle: 0, wasNaturalBreak: false))
        // Last input 130 s ago over a 30 s window: active until 10 s after the window start.
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 130).active, 20)
        // Long gone: nothing counts as active.
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 1000).active, 0)
    }

    runner.run("ActivityTracker.continuousWorkResetsOnNaturalBreak") {
        let t = ActivityTracker()
        for _ in 0..<100 { _ = t.record(dt: 30, secondsSinceLastInput: 5) }
        try expectEqual(t.continuousActive, 3000)
        let s = t.record(dt: 30, secondsSinceLastInput: 400)
        try expectTrue(s.wasNaturalBreak)
        try expectEqual(t.continuousActive, 0)
        _ = t.record(dt: 30, secondsSinceLastInput: 1)
        t.breakTaken()
        try expectEqual(t.continuousActive, 0)
    }

    runner.run("ActivityTracker.anHourOfUptimeIdleIsNotScreenTime") {
        let t = ActivityTracker()
        var active = 0.0
        var s = 0.0
        for _ in 0..<120 { s += 30; active += t.record(dt: 30, secondsSinceLastInput: s).active } // 1 h, no input at all
        try expectEqual(active, 120) // only the first 2 minutes after the last input
    }
}
