import Foundation
import Core

/// Stage 11: closes a real coverage gap found by the master audit --
/// PetMessageBook had no direct tests for cooldown timing or repetition
/// avoidance, only indirect coverage through other test files.
func runPetMessagesTests(_ runner: TestRunner) {
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    runner.run("PetMessages.everyCategoryHasAtLeastOneLine") {
        for c in MessageCategory.allCases {
            try expectFalse(PetMessageBook.lines(c, name: "Fox").isEmpty, "\(c) has no lines at all")
        }
    }

    runner.run("PetMessages.firstCall_alwaysReturnsALine_noPriorCooldown") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        let line = book.line(.welcome, name: "Fox", now: base)
        try expectNotNil(line)
    }

    runner.run("PetMessages.secondCallWithinCooldown_returnsNil") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        _ = book.line(.sleep, name: "Fox", now: base) // cooldown: 15 min
        let again = book.line(.sleep, name: "Fox", now: base.addingTimeInterval(60))
        try expectTrue(again == nil, "expected a line well within the 15-minute sleep cooldown to be suppressed")
    }

    runner.run("PetMessages.callAfterCooldownElapses_returnsALineAgain") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        _ = book.line(.sleep, name: "Fox", now: base)
        let later = book.line(.sleep, name: "Fox", now: base.addingTimeInterval(15 * 60 + 1))
        try expectNotNil(later) // expected a line once the 15-minute sleep cooldown has fully elapsed
    }

    runner.run("PetMessages.force_ignoresCooldownEntirely") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        _ = book.line(.sleep, name: "Fox", now: base)
        let forced = book.line(.sleep, name: "Fox", now: base.addingTimeInterval(1), force: true)
        try expectNotNil(forced) // expected force: true to bypass the cooldown
    }

    runner.run("PetMessages.categoriesWithNoCooldown_canFireRepeatedlyAtTheSameInstant") {
        // .welcome is not in the cooldown switch, so its default is 0 --
        // repeated identical-timestamp calls should still return a line.
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        _ = book.line(.welcome, name: "Fox", now: base)
        let again = book.line(.welcome, name: "Fox", now: base)
        try expectNotNil(again)
    }

    runner.run("PetMessages.neverRepeatsTheExactSameLineTwiceInARow_whenMultipleLinesExist") {
        // .click has 5 lines and an 8s cooldown -- force past cooldown each
        // time and confirm no two consecutive picks are identical, across
        // many draws and several seeds (ruling out a lucky RNG sequence).
        for seed: UInt64 in [1, 2, 3, 4, 5] {
            let book = PetMessageBook(rng: SeededRandom(seed: seed))
            var previous: String?
            var t = base
            for _ in 0..<40 {
                t = t.addingTimeInterval(9)
                guard let line = book.line(.click, name: "Fox", now: t) else { try fail("expected a line past cooldown"); return }
                if let previous { try expectTrue(line != previous, "seed \(seed): got the same line twice in a row: \(line)") }
                previous = line
            }
        }
    }

    runner.run("PetMessages.traitLines_areIncludedInThePoolForMatchingTrait") {
        // "curious" adds 2 extra idle lines on top of the 5 base ones. Over
        // enough draws (force: true each time to bypass the 25-minute idle
        // cooldown), at least one trait-specific line should appear.
        let book = PetMessageBook(rng: SeededRandom(seed: 7))
        var sawTraitLine = false
        let traitLines = Set(PetMessageBook.traitLines(.idle, trait: "curious"))
        var t = base
        for _ in 0..<60 {
            t = t.addingTimeInterval(1)
            if let line = book.line(.idle, name: "Fox", trait: "curious", now: t, force: true), traitLines.contains(line) {
                sawTraitLine = true
                break
            }
        }
        try expectTrue(sawTraitLine, "expected at least one curious-trait idle line across 60 forced draws")
    }

    runner.run("PetMessages.unmatchedTrait_fallsBackToBaseLinesOnly_neverCrashes") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        // "friendly" has explicit .idle traitLines; a trait with no entry
        // for this category (e.g. a made-up one) must still work, falling
        // back to the base pool.
        let line = book.line(.idle, name: "Fox", trait: "totally-unknown-trait", now: base, force: true)
        try expectNotNil(line)
        try expectTrue(PetMessageBook.lines(.idle, name: "Fox").contains(line!))
    }

    runner.run("PetMessages.chattiness_shortensIdleCooldown") {
        let calm = PetMessageBook(rng: SeededRandom(seed: 1)); calm.chattiness = 0.5
        let chatty = PetMessageBook(rng: SeededRandom(seed: 1)); chatty.chattiness = 2
        try expectTrue(chatty.cooldown(.idle) < calm.cooldown(.idle), "expected higher chattiness to shorten the idle cooldown")
    }

    runner.run("PetMessages.categoriesAreIndependent_oneCooldownNeverBlocksAnother") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        _ = book.line(.sleep, name: "Fox", now: base) // long cooldown
        let wake = book.line(.wake, name: "Fox", now: base.addingTimeInterval(1)) // unrelated, short cooldown
        try expectNotNil(wake) // a cooldown on one category must never suppress an unrelated category
    }
}
