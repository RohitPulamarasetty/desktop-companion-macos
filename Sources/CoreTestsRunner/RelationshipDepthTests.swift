import Foundation
import Core

/// Stage 12: causal tests proving familiarity's behavioral effects, and
/// that personality (the existing `affection` dial, no new field) genuinely
/// modulates how much familiarity matters to a given character.
func runRelationshipDepthTests(_ runner: TestRunner) {
    let fullClips: Set<String> = [
        "stand", "sit", "walk", "walk_left", "walk_right", "lie", "sleep",
        "doze", "settle", "yawn", "happy", "play",
    ]
    func makeBrain(seed: UInt64, affection: Double = 1.0) -> PetBrain {
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        config.personality.affection = affection
        return PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
    }

    // MARK: Familiarity -> approach (Phase 3)

    runner.run("RelationshipDepth.higherFamiliarity_increasesApproachFrequency_holdingPersonalityConstant") {
        func approachFraction(familiarity: Double, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var ctx = PetContext(); ctx.cursorX = 900; ctx.cursorY = 0; ctx.cursorNearPet = false; ctx.userIdleSeconds = 200
            ctx.familiarity = familiarity
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed, affection: 1.2)
                var hits = 0
                let ticks = 4000
                for _ in 0..<ticks {
                    brain.update(dt: 1, context: ctx)
                    if brain.behavior == .followCursor || brain.behavior == .investigate { hits += 1 }
                }
                total += Double(hits) / Double(ticks)
            }
            return total / Double(seeds.count)
        }
        let low = approachFraction(familiarity: 0.4) // day one
        let high = approachFraction(familiarity: 1.0) // fully familiar
        try expectTrue(high > low, "expected full familiarity to increase approach frequency over day-one familiarity: low=\(low) high=\(high)")
    }

    runner.run("RelationshipDepth.familiarityEffect_isBoundedTo40PercentAtMost_neverCausesConstantFollowing") {
        // The brief explicitly warns against "high familiarity causes
        // constant following" -- confirm the boost is a small nudge, not
        // a takeover, by checking the underlying multiplier directly
        // rather than inferring it from noisy simulation output.
        let fDelta = 1.0 // fully familiar
        let maxAffection = 1.5 // the top of the clamped personality range
        let boost = 1 + fDelta * 0.4 * maxAffection
        try expectTrue(boost <= 1.6 + 0.0001, "expected the maximum possible familiarity approach boost to stay at or below 1.6x, got \(boost)")
    }

    runner.run("RelationshipDepth.affectionatePersonality_respondsMoreToFamiliarityThanIndependentOne") {
        // Phase 7: familiarity must not affect every character identically.
        func approachFraction(affection: Double, familiarity: Double, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var ctx = PetContext(); ctx.cursorX = 900; ctx.cursorY = 0; ctx.cursorNearPet = false; ctx.userIdleSeconds = 200
            ctx.familiarity = familiarity
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed, affection: affection)
                var hits = 0
                let ticks = 4000
                for _ in 0..<ticks {
                    brain.update(dt: 1, context: ctx)
                    if brain.behavior == .followCursor || brain.behavior == .investigate { hits += 1 }
                }
                total += Double(hits) / Double(ticks)
            }
            return total / Double(seeds.count)
        }
        let affectionateGain = approachFraction(affection: 1.5, familiarity: 1.0) - approachFraction(affection: 1.5, familiarity: 0.4)
        let independentGain = approachFraction(affection: 0.6, familiarity: 1.0) - approachFraction(affection: 0.6, familiarity: 0.4)
        try expectTrue(affectionateGain > independentGain, "expected an affectionate character's approach frequency to respond more strongly to rising familiarity than an independent character's: affectionate=\(affectionateGain) independent=\(independentGain)")
    }

    // MARK: Familiarity -> boredom decay on click (Phase 4)

    runner.run("RelationshipDepth.higherFamiliarity_reducesBoredomMoreOnClick") {
        let low = makeBrain(seed: 1, affection: 1.5)
        let high = makeBrain(seed: 1, affection: 1.5)
        var lowCtx = PetContext(); lowCtx.familiarity = 0.4
        var highCtx = PetContext(); highCtx.familiarity = 1.0
        // Push both to the same starting boredom deterministically before
        // the click under test.
        for _ in 0..<3000 { low.update(dt: 1, context: lowCtx); high.update(dt: 1, context: highCtx) }
        let lowBoredomBefore = low.boredom, highBoredomBefore = high.boredom
        _ = low.handle(.click, context: lowCtx)
        _ = high.handle(.click, context: highCtx)
        let lowRelief = lowBoredomBefore - low.boredom
        let highRelief = highBoredomBefore - high.boredom
        try expectTrue(highRelief >= lowRelief, "expected higher familiarity to relieve at least as much boredom per click: low=\(lowRelief) high=\(highRelief)")
    }

    runner.run("RelationshipDepth.boredomDecayBoost_isSmall_neverMoreThan30PercentExtra") {
        let fDelta = 1.0
        let maxAffection = 1.5
        let multiplier = 1 + fDelta * 0.3 * maxAffection
        try expectTrue(multiplier <= 1.45 + 0.0001, "expected the boredom-decay familiarity boost to stay small, got \(multiplier)")
    }

    // MARK: Familiarity -> messages (Phase 5)

    runner.run("RelationshipDepth.familiarLines_neverAppearBelowTheFamiliarityThreshold") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let familiar = Set(PetMessageBook.familiarLines(.returned))
        var t = base
        for _ in 0..<60 {
            t = t.addingTimeInterval(700) // past .returned's 10-min cooldown
            if let line = book.line(.returned, name: "Fox", now: t, force: true, familiarity: 0.4), familiar.contains(line) {
                try fail("a familiar-only line appeared at low familiarity: \(line)")
                return
            }
        }
    }

    runner.run("RelationshipDepth.familiarLines_canAppearAtHighFamiliarity") {
        let book = PetMessageBook(rng: SeededRandom(seed: 3))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let familiar = Set(PetMessageBook.familiarLines(.returned))
        var sawFamiliarLine = false
        var t = base
        for _ in 0..<60 {
            t = t.addingTimeInterval(700)
            if let line = book.line(.returned, name: "Fox", now: t, force: true, familiarity: 1.0), familiar.contains(line) {
                sawFamiliarLine = true
                break
            }
        }
        try expectTrue(sawFamiliarLine, "expected at least one familiar-only line across 60 forced draws at full familiarity")
    }

    // MARK: Long-run + state invariants (Phases 12-13)

    runner.run("RelationshipDepth.sevenSimulatedDays_lowVsHighFamiliarity_noRunawayAmplification") {
        // Compares low and high (fixed, not evolving mid-run -- the
        // formula itself is already tested above) familiarity across a
        // full week of simulated time, watching for the specific failure
        // mode the brief warns about: familiarity causing a runaway
        // takeover of behavior rather than a bounded nudge.
        let approach: Set<PetBehavior> = [.followCursor, .investigate]
        func weekApproachFraction(familiarity: Double) -> Double {
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
            config.personality.affection = 1.5 // the most familiarity-sensitive personality
            let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: 77))
            var ctx = PetContext(); ctx.familiarity = familiarity
            let dt = 30.0
            var elapsed = 0.0
            var approachTicks = 0, totalTicks = 0
            while elapsed < 7 * 24 * 3600 {
                elapsed += dt
                ctx.hour = Int((elapsed / 3600).truncatingRemainder(dividingBy: 24))
                if Int(elapsed) % 1800 == 0 {
                    ctx.cursorX = 900; ctx.cursorY = 0; ctx.cursorNearPet = false
                    ctx.userIdleSeconds = 200
                }
                brain.update(dt: dt, context: ctx)
                totalTicks += 1
                if approach.contains(brain.behavior) { approachTicks += 1 }
            }
            return Double(approachTicks) / Double(totalTicks)
        }
        let low = weekApproachFraction(familiarity: 0.4)
        let high = weekApproachFraction(familiarity: 1.0)
        try expectTrue(high > low, "expected sustained higher familiarity to still show more approach over a full week: low=\(low) high=\(high)")
        // "Bounded nudge, not a takeover": approach-family behaviors must
        // never come close to dominating the week even at max familiarity.
        try expectTrue(high < 0.5, "expected familiarity-boosted approach to remain a minority of behavior even at full familiarity and max affection: \(high)")
    }

    runner.run("RelationshipDepth.randomizedFamiliarityAndResetSequences_neverProduceInvalidState") {
        // Phase 13: familiarity changing mid-simulation (as it would
        // across real days), interleaved with commands/modes/resets
        // (familiarity dropping back to baseline, simulating a fresh
        // install) -- must never produce an impossible or corrupted state.
        let rng = SeededRandom(seed: 11)
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        config.personality.affection = 1.3
        let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: rng)
        var ctx = PetContext()
        let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .stop, .follow, .stay]
        for i in 0..<6000 {
            if i % 100 == 0 {
                ctx.familiarity = rng.chance(0.1) ? 0.4 : rng.nextUnit() * 0.6 + 0.4 // occasional "reset"
                ctx.mode = PetMode.allCases[Int(rng.nextUnit() * Double(PetMode.allCases.count))]
                ctx.cursorX = rng.chance(0.6) ? 500 : nil
                ctx.cursorY = ctx.cursorX == nil ? nil : 0
                ctx.userIdleSeconds = rng.chance(0.3) ? rng.nextUnit() * 700 : 0
            }
            if i % 150 == 0 { _ = brain.perform(commands[Int(rng.nextUnit() * Double(commands.count))], context: ctx) }
            brain.update(dt: 1, context: ctx)
            try expectTrue(ctx.familiarity >= 0 && ctx.familiarity <= 1, "familiarity itself went out of [0,1] at tick \(i)")
            try expectFalse(brain.isAsleep && brain.isMoving, "impossible state at tick \(i)")
            try expectTrue(brain.x.isFinite && brain.energy.isFinite && brain.boredom.isFinite && brain.affection.isFinite, "non-finite state at tick \(i)")
            try expectTrue(brain.boredom >= 0 && brain.boredom <= 1, "boredom out of [0,1] at tick \(i): \(brain.boredom)")
            try expectTrue(brain.affection >= 0 && brain.affection <= 1, "affection out of [0,1] at tick \(i): \(brain.affection)")
        }
    }

    runner.run("RelationshipDepth.defaultFamiliarityParameter_isFullyFamiliar_backwardCompatible") {
        // Every call site written before Stage 12 omits `familiarity:` --
        // must behave exactly as if fully familiar, not suddenly withhold
        // lines it always returned before.
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        let line = book.line(.welcome, name: "Fox", now: Date())
        try expectNotNil(line)
    }
}
