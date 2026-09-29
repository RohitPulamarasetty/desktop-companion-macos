import Foundation
import Core

func runNudgeAndMessageTests(_ runner: TestRunner) {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000) // fixed reference
    let noQuiet: QuietHours? = nil
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!

    runner.run("Nudge.asksOnlyAfterTheInterval_thenConfirmResets") {
        let n = NudgeSchedule(enabled: true, interval: 3600, anchor: t0)
        try expectEqual(n.evaluate(now: t0.addingTimeInterval(1800), userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false),
                        .wait(until: t0.addingTimeInterval(3600)))
        try expectEqual(n.evaluate(now: t0.addingTimeInterval(3601), userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false), .ask)
        n.beginAsking()
        n.confirm(now: t0.addingTimeInterval(3610))
        try expectEqual(n.nextDue, t0.addingTimeInterval(3610 + 3600))
    }

    runner.run("Nudge.skipRespectsCooldown_neverReasksImmediately") {
        let n = NudgeSchedule(enabled: true, interval: 15 * 60, anchor: t0, minimumSkipCooldown: 20 * 60)
        let now = t0.addingTimeInterval(16 * 60)
        try expectEqual(n.evaluate(now: now, userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false), .ask)
        n.beginAsking()
        n.skip(now: now)
        // Not at +15 min (interval) -- the 20 min skip cooldown wins.
        try expectEqual(n.nextDue, now.addingTimeInterval(20 * 60))
        try expectEqual(n.evaluate(now: now.addingTimeInterval(60), userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false),
                        .wait(until: now.addingTimeInterval(20 * 60)))
    }

    runner.run("Nudge.waitsOutQuietHoursFocusIdleAndOtherQuestions") {
        let n = NudgeSchedule(enabled: true, interval: 600, anchor: t0)
        let due = t0.addingTimeInterval(700)
        let quiet = QuietHours(startHour: 0, endHour: 23) // covers almost the whole day
        if case .wait = n.evaluate(now: due, userIdleSeconds: 0, focusActive: false, quietHours: quiet, busy: false, calendar: utc) {} else { try fail("asked in quiet hours") }
        if case .wait = n.evaluate(now: due, userIdleSeconds: 0, focusActive: true, quietHours: noQuiet, busy: false) {} else { try fail("asked in focus") }
        if case .wait = n.evaluate(now: due, userIdleSeconds: 600, focusActive: false, quietHours: noQuiet, busy: false) {} else { try fail("asked an empty room") }
        if case .wait = n.evaluate(now: due, userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: true) {} else { try fail("stacked questions") }
        try expectEqual(n.evaluate(now: due, userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false), .ask)
    }

    runner.run("Nudge.unansweredRetriesLater_disabledNeverAsks") {
        let n = NudgeSchedule(enabled: true, interval: 3600, anchor: t0, retryAfterTimeout: 900)
        let now = t0.addingTimeInterval(4000)
        n.beginAsking()
        n.timedOut(now: now)
        try expectEqual(n.nextDue, now.addingTimeInterval(900))
        n.enabled = false
        try expectEqual(n.evaluate(now: now.addingTimeInterval(99_999), userIdleSeconds: 0, focusActive: false, quietHours: noQuiet, busy: false), .disabled)
    }

    runner.run("Messages.cooldownsAndNoImmediateRepeats") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        let a = book.line(.click, name: "Fox", now: t0)
        try expectNotNil(a)
        try expectTrue(book.line(.click, name: "Fox", now: t0.addingTimeInterval(2)) == nil) // cooldown
        var previous = a
        for i in 1...20 {
            let l = book.line(.click, name: "Fox", now: t0.addingTimeInterval(Double(i) * 10))
            try expectTrue(l != nil && l != previous, "repeated \(String(describing: l))")
            previous = l
        }
        try expectTrue(book.line(.idle, name: "Fox", now: t0) != nil)
        try expectTrue(book.line(.idle, name: "Fox", now: t0.addingTimeInterval(60)) == nil)
        try expectTrue(book.line(.idle, name: "Fox", now: t0.addingTimeInterval(60), force: true) != nil)
    }

    runner.run("Messages.everyCategoryHasLines_andTraitsAddFlavour") {
        for c in MessageCategory.allCases { try expectFalse(PetMessageBook.lines(c, name: "X").isEmpty) }
        try expectFalse(PetMessageBook.traitLines(.idle, trait: "curious").isEmpty)
    }

    // Every trait actually shipped by an installed character (Characters/*/manifest.json)
    // should get flavoured idle/click lines, not silently fall through to the
    // generic pool -- catches a new character shipping an unflavoured trait.
    runner.run("Messages.everyShippedTraitHasIdleAndClickFlavour") {
        let shippedTraits = ["calm", "friendly", "dreamy", "loyal", "curious", "playful", "mischievous", "energetic", "gentle"]
        for trait in shippedTraits {
            try expectFalse(PetMessageBook.traitLines(.idle, trait: trait).isEmpty, "idle has no flavour for trait '\(trait)'")
            try expectFalse(PetMessageBook.traitLines(.click, trait: trait).isEmpty, "click has no flavour for trait '\(trait)'")
        }
    }

    runner.run("Characters.personalityIsDataDriven_andClamped") {
        let m = CharacterManifest(id: "x", displayName: "X", attribution: nil, initialState: "sit", states: [], transitions: [],
                                  personality: PersonalityDefinition(trait: "calm", restfulness: 9, roaming: 0.1))
        let p = CharacterDefinition(manifest: m, baseURL: URL(fileURLWithPath: "/")).personality
        try expectEqual(p.trait, "calm")
        try expectEqual(p.restfulness, 1.5)
        try expectEqual(p.roaming, 0.6)
        try expectEqual(p.reactivity, 1)
    }
}
