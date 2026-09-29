import Foundation
import Core

func runActivityTrackerTests(_ runner: TestRunner) {
    runner.run("ActivityTracker.countsOnlyRealActivity") {
        let t = ActivityTracker(idleThreshold: 120, naturalBreak: 300)
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 2), .init(active: 30, idle: 0, wasNaturalBreak: false))
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 130).active, 20)
        try expectEqual(t.record(dt: 30, secondsSinceLastInput: 1000).active, 0)
    }

    runner.run("ActivityTracker.continuousWorkResetsOnNaturalBreak") {
        let t = ActivityTracker()
        for _ in 0..<100 { _ = t.record(dt: 30, secondsSinceLastInput: 5) }
        try expectEqual(t.continuousActive, 3000)
        let s = t.record(dt: 30, secondsSinceLastInput: 400)
        try expectTrue(s.wasNaturalBreak)
        try expectEqual(t.continuousActive, 0)
    }

    runner.run("ActivityTracker.anHourOfUptimeIdleIsNotActiveTime") {
        let t = ActivityTracker()
        var active = 0.0
        var s = 0.0
        for _ in 0..<120 { s += 30; active += t.record(dt: 30, secondsSinceLastInput: s).active }
        try expectEqual(active, 120)
    }

    runner.run("QuietHours.wrapsPastMidnight") {
        let cal = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: hour))! }
        let q = QuietHours(startHour: 22, endHour: 7)
        try expectTrue(q.contains(at(23), calendar: cal))
        try expectTrue(q.contains(at(3), calendar: cal))
        try expectFalse(q.contains(at(7), calendar: cal))
        try expectFalse(q.contains(at(12), calendar: cal))
        try expectFalse(QuietHours(startHour: 5, endHour: 5).contains(at(5), calendar: cal))
    }
}
