import Foundation
import Core

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("pet-state-test-\(UUID().uuidString).sqlite")
}

func runPetStateStoreTests(_ runner: TestRunner) {
    runner.run("PetStateStore.position_roundTripsAndSurvivesReopen") {
        let url = tempURL()
        do {
            let store = try PetStateStore(fileURL: url)
            try store.savePosition(.init(displayID: 69_734_208, fraction: 0.42))
            try store.saveEnergy(0.8)
            try store.saveLastInteraction(Date(timeIntervalSince1970: 1_000_000))
        }
        let reopened = try PetStateStore(fileURL: url)
        try expectEqual(reopened.savedPosition(), .init(displayID: 69_734_208, fraction: 0.42))
        try expectEqual(reopened.energy(), 0.8)
        try expectEqual(reopened.lastInteraction(), Date(timeIntervalSince1970: 1_000_000))
    }

    runner.run("PetStateStore.position_keepsVerticalPosition_andReadsOldRows") {
        let store = try PetStateStore(fileURL: tempURL())
        try store.savePosition(.init(displayID: 7, fraction: 0.3, fractionY: 0.9))
        try expectEqual(store.savedPosition(), .init(displayID: 7, fraction: 0.3, fractionY: 0.9))
        try store.set("7,0.5", for: "position") // v1 format
        try expectEqual(store.savedPosition(), .init(displayID: 7, fraction: 0.5, fractionY: 0))
    }

    runner.run("PetStateStore.position_fractionIsClamped") {
        let store = try PetStateStore(fileURL: tempURL())
        try store.savePosition(.init(displayID: 1, fraction: 7))
        try expectEqual(store.savedPosition()?.fraction, 1)
    }

    runner.run("PetStateStore.dailyStats_accumulateViaUpsert") {
        let store = try PetStateStore(fileURL: tempURL())
        var delta = PetStateStore.DailyStats()
        delta.clicks = 2; delta.barks = 1; delta.sleepSeconds = 30
        try store.addDaily(delta)
        try store.addDaily(delta)
        let today = store.daily()
        try expectEqual(today.clicks, 4)
        try expectEqual(today.barks, 2)
        try expectEqual(today.sleepSeconds, 60)
        try expectEqual(store.dailyRowCount(), 1)
    }

    runner.run("PetStateStore.prune_boundsGrowth") {
        let store = try PetStateStore(fileURL: tempURL())
        var delta = PetStateStore.DailyStats(); delta.clicks = 1
        let old = Calendar.current.date(byAdding: .day, value: -(PetStateStore.retentionDays + 5), to: Date())!
        try store.addDaily(delta, on: old)
        try store.addDaily(delta)
        try store.prune()
        try expectEqual(store.dailyRowCount(), 1)
    }

    runner.run("PetStateStore.discoveredBehaviors_writtenOnceAndPersist") {
        let url = tempURL()
        do {
            let store = try PetStateStore(fileURL: url)
            try expectTrue(store.recordDiscovered("sleep"))
            try expectFalse(store.recordDiscovered("sleep"))
            store.recordDiscovered("walk")
        }
        let reopened = try PetStateStore(fileURL: url)
        try expectEqual(reopened.discoveredBehaviors, ["sleep", "walk"])
    }
}
