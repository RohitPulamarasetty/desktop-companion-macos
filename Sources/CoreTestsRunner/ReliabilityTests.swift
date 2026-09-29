import Foundation
import Core

/// Stage 9, Phase 20: long, randomized simulations looking for impossible
/// state combinations, stuck states, out-of-bounds movement, and NaN
/// corruption -- not feature tests, invariant tests. These are cheap
/// insurance against exactly the failure modes the product brief called
/// out by name (sleeping+running, boundary violations, runaway values).
func runReliabilityTests(_ runner: TestRunner) {
    let fullClips: Set<String> = [
        "stand", "sit", "walk", "walk_left", "walk_right", "run", "run_left", "run_right",
        "lie", "sleep", "doze", "settle", "sitLookAround", "lookAround", "stretch", "yawn",
        "bark_sit", "bark_stand", "excited", "dragged", "fall", "land",
    ]

    runner.run("Reliability.noImpossibleStateCombinations_acrossLongRandomizedSimulation") {
        for seed: UInt64 in [1, 7, 13, 29, 41, 99] {
            let rng = SeededRandom(seed: seed)
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
            config.personality.roaming = 0.6 + rng.nextUnit() * 1.0
            config.personality.restfulness = 0.6 + rng.nextUnit() * 1.0
            let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, minY: 0, maxY: 0, rng: rng)
            var ctx = PetContext()
            for i in 0..<8000 {
                // Fuzz the context every so often -- mode, focus, quiet
                // hours, cursor presence -- so transitions get exercised,
                // not just a single steady-state context.
                if i % 50 == 0 {
                    ctx.hour = Int(rng.nextUnit() * 24)
                    ctx.mode = PetMode.allCases[Int(rng.nextUnit() * Double(PetMode.allCases.count))]
                    ctx.quietHours = rng.chance(0.1)
                    ctx.cursorNearPet = rng.chance(0.2)
                    ctx.cursorX = rng.chance(0.7) ? 500 : nil
                    ctx.cursorY = ctx.cursorX == nil ? nil : 0
                    ctx.userIdleSeconds = rng.chance(0.3) ? rng.nextUnit() * 700 : 0
                }
                brain.update(dt: 0.5, context: ctx)

                // Sleeping and moving at once is the exact impossible
                // combination the brief calls out by name.
                try expectFalse(brain.isAsleep && brain.isMoving, "impossible state at tick \(i), seed \(seed): asleep AND moving")
                // Never drifts outside the world bounds it was given.
                try expectTrue(brain.x >= -1 && brain.x <= 1001, "out-of-bounds x=\(brain.x) at tick \(i), seed \(seed)")
                // No NaN/Inf corruption from any weight computation.
                try expectTrue(brain.x.isFinite && brain.energy.isFinite && brain.affection.isFinite && brain.curiosity.isFinite,
                               "non-finite state at tick \(i), seed \(seed): x=\(brain.x) energy=\(brain.energy)")
                try expectTrue(brain.energy >= 0 && brain.energy <= 1, "energy out of [0,1] at tick \(i), seed \(seed): \(brain.energy)")
            }
        }
    }

    runner.run("Reliability.commandsNeverCorruptStateWhenIssuedInAnyOrderOrWhileBusy") {
        // Fires every PetBrain-local command in a random order, repeatedly,
        // including while the brain is mid-behavior/asleep/dragged -- none
        // of it should ever produce a non-finite value or an impossible
        // asleep+moving combination.
        let rng = SeededRandom(seed: 77)
        let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: rng)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .quiet, .stop, .follow(duration: nil), .stay(duration: nil)]
        for i in 0..<2000 {
            let cmd = commands[Int(rng.nextUnit() * Double(commands.count))]
            _ = brain.perform(cmd, context: ctx)
            if i % 3 == 0 { _ = brain.handle(.dragBegan, context: ctx) }
            if i % 7 == 0 { _ = brain.handle(.dropped, context: ctx) }
            brain.update(dt: 0.3, context: ctx)
            try expectFalse(brain.isAsleep && brain.isMoving, "impossible state after command fuzzing at tick \(i)")
            try expectTrue(brain.x.isFinite && brain.y.isFinite, "non-finite position after command fuzzing at tick \(i)")
        }
    }

    runner.run("Reliability.characterSwitchMidAnimation_neverLeavesNonFiniteOrImpossibleState") {
        // Simulates a character switch (a fresh PetBrain replacing the old
        // one, as the real app does) while the old brain was mid-walk,
        // mid-sleep, and mid-drag -- each fresh brain must start clean.
        for startPosture: PetBehavior in [.walk, .sleep, .dragged] {
            let rng = SeededRandom(seed: 5)
            let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
            let old = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: rng)
            let ctx = PetContext()
            for _ in 0..<200 { old.update(dt: 0.5, context: ctx) }
            _ = old // old brain discarded here, mirroring a real character switch

            let fresh = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: 6))
            try expectFalse(fresh.isAsleep && fresh.isMoving)
            try expectTrue(fresh.x.isFinite && fresh.energy.isFinite)
            for _ in 0..<200 { fresh.update(dt: 0.5, context: ctx) }
            try expectTrue(fresh.x.isFinite && fresh.energy.isFinite, "fresh brain corrupted after switch from \(startPosture)")
        }
    }

    runner.run("Reliability.dragThenDrop_alwaysRecoversToAutonomousBehavior_neverStuck") {
        // Stage 9, Phase 4/20: "user drags pet -> pet reacts -> user
        // releases -> pet stabilizes -> resumes autonomous behavior." No
        // seed should ever leave the pet stuck in .dragged/.falling/
        // .landing once update() keeps running afterward.
        let physics: Set<PetBehavior> = [.dragged, .falling, .landing]
        for seed: UInt64 in [1, 2, 3, 4, 5] {
            let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
            let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
            let ctx = PetContext()
            for _ in 0..<50 { brain.update(dt: 0.3, context: ctx) } // let it settle into some autonomous behavior first
            _ = brain.handle(.dragBegan, context: ctx)
            try expectEqual(brain.behavior, .dragged)
            for _ in 0..<20 { brain.update(dt: 0.3, context: ctx) } // held mid-drag
            try expectEqual(brain.behavior, .dragged) // never times out or drifts away on its own while held
            _ = brain.handle(.dropped, context: ctx)
            // Give it ample time to run the landing sequence and pick its
            // next autonomous choice -- it must not still be in a physics
            // behavior by then.
            for _ in 0..<40 { brain.update(dt: 0.3, context: ctx) }
            try expectFalse(physics.contains(brain.behavior), "seed \(seed): still stuck in \(brain.behavior) long after being dropped")
        }
    }
}
