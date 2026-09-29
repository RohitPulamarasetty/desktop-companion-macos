import Foundation
import Core

func runFocusTimerTests(_ runner: TestRunner) {
    runner.run("FocusTimer.startsIdle") {
        let timer = FocusTimer()
        try expectEqual(timer.phase, .idle)
        try expectFalse(timer.isActive)
    }

    runner.run("FocusTimer.start_entersFocusingWithCorrectDuration") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        try expectEqual(timer.phase, .focusing(remainingSeconds: 1500))
        try expectTrue(timer.isActive)
    }

    runner.run("FocusTimer.tick_countsDown") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        _ = timer.tick(deltaTime: 10)
        try expectEqual(timer.phase, .focusing(remainingSeconds: 1490))
    }

    runner.run("FocusTimer.focusCompletion_movesToBreakAndFiresEvent") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 0.1, breakMinutes: 5) // 6 seconds
        let event = timer.tick(deltaTime: 10)
        try expectEqual(event, .focusCompleted)
        try expectEqual(timer.phase, .onBreak(remainingSeconds: 300))
    }

    runner.run("FocusTimer.breakCompletion_returnsToIdleAndFiresEvent") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 0.1, breakMinutes: 0.1) // 6s focus, 6s break
        _ = timer.tick(deltaTime: 10) // completes focus -> break
        let event = timer.tick(deltaTime: 10) // completes break -> idle
        try expectEqual(event, .breakCompleted)
        try expectEqual(timer.phase, .idle)
    }

    runner.run("FocusTimer.pauseThenResume_preservesRemainingTime") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        _ = timer.tick(deltaTime: 100)
        timer.pause()
        try expectEqual(timer.phase, .paused(resumePhase: .focusing, remainingSeconds: 1400))
        // ticks while paused are no-ops
        _ = timer.tick(deltaTime: 50)
        try expectEqual(timer.phase, .paused(resumePhase: .focusing, remainingSeconds: 1400))
        timer.resume()
        try expectEqual(timer.phase, .focusing(remainingSeconds: 1400))
    }

    runner.run("FocusTimer.skip_fromFocusing_movesToBreak") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        let event = timer.skip()
        try expectEqual(event, .focusCompleted)
        try expectEqual(timer.phase, .onBreak(remainingSeconds: 300))
    }

    runner.run("FocusTimer.skip_fromBreak_movesToIdle") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        _ = timer.skip()
        let event = timer.skip()
        try expectEqual(event, .breakCompleted)
        try expectEqual(timer.phase, .idle)
    }

    runner.run("FocusTimer.cancel_returnsToIdleFromAnyPhase") {
        let timer = FocusTimer()
        timer.start(focusMinutes: 25, breakMinutes: 5)
        timer.cancel()
        try expectEqual(timer.phase, .idle)
    }
}

private func makeHistoryStore() throws -> FocusHistoryStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("focus-history-test-\(UUID().uuidString).sqlite")
    return try FocusHistoryStore(fileURL: url)
}

func runFocusHistoryStoreTests(_ runner: TestRunner) {
    runner.run("FocusHistoryStore.addAndRetrieve") {
        let store = try makeHistoryStore()
        let record = FocusSessionRecord(startedAt: Date(), endedAt: Date(), plannedFocusMinutes: 25, completedFully: true)
        try store.add(record)
        let all = try store.all()
        try expectEqual(all.count, 1)
    }

    runner.run("FocusHistoryStore.todayTotalFocusMinutes_sumsOnlyCompletedToday") {
        let store = try makeHistoryStore()
        let now = Date()
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now, plannedFocusMinutes: 25, completedFully: true))
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now, plannedFocusMinutes: 50, completedFully: true))
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now, plannedFocusMinutes: 25, completedFully: false)) // skipped, not counted
        let total = try store.todayTotalFocusMinutes(referenceDate: now)
        try expectEqual(total, 75)
    }

    runner.run("FocusHistoryStore.todayCompletedSessionCount") {
        let store = try makeHistoryStore()
        let now = Date()
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now, plannedFocusMinutes: 25, completedFully: true))
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now, plannedFocusMinutes: 25, completedFully: true))
        let count = try store.todayCompletedSessionCount(referenceDate: now)
        try expectEqual(count, 2)
    }
}
