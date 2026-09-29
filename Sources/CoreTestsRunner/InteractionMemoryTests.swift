import Foundation
import Core

/// Stage 11, Phase 2: structured short-term memory. Verifies each field
/// records the right kind of event, stays nil until that kind of thing
/// has happened, and is bounded (a handful of timestamps, never a
/// growing log).
func runInteractionMemoryTests(_ runner: TestRunner) {
    let fullClips: Set<String> = [
        "stand", "sit", "walk", "walk_left", "walk_right", "lie", "sleep",
        "doze", "settle", "yawn", "dragged", "fall", "land", "happy", "play", "run", "gallop",
    ]
    func makeBrain(seed: UInt64) -> PetBrain {
        let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        return PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
    }

    runner.run("InteractionMemory.startsEmpty_everyFieldNilUntilItHappens") {
        let brain = makeBrain(seed: 1)
        try expectTrue(brain.memory.lastInteractionAt == nil)
        try expectTrue(brain.memory.lastCommand == nil)
        try expectTrue(brain.memory.lastCommandAt == nil)
        try expectTrue(brain.memory.lastPlayAt == nil)
        try expectTrue(brain.memory.lastSleepAt == nil)
        try expectTrue(brain.memory.lastApproachAt == nil)
    }

    runner.run("InteractionMemory.click_recordsLastInteractionOnly") {
        let brain = makeBrain(seed: 2)
        let ctx = PetContext()
        _ = brain.handle(.click, context: ctx)
        try expectTrue(brain.memory.lastInteractionAt != nil)
        try expectEqual(brain.memory.lastInteractionAt, brain.clock)
        // A plain click is not a play session, a sleep, an approach, or a command.
        try expectTrue(brain.memory.lastPlayAt == nil)
        try expectTrue(brain.memory.lastSleepAt == nil)
        try expectTrue(brain.memory.lastApproachAt == nil)
        try expectTrue(brain.memory.lastCommand == nil)
    }

    runner.run("InteractionMemory.doubleClick_recordsInteractionAndPlay") {
        let brain = makeBrain(seed: 3)
        let ctx = PetContext()
        _ = brain.handle(.doubleClick, context: ctx)
        try expectTrue(brain.memory.lastInteractionAt != nil)
        try expectTrue(brain.memory.lastPlayAt != nil, "doubleClick starts .petted, which should count as play")
    }

    runner.run("InteractionMemory.playCommand_recordsCommandAndPlay") {
        let brain = makeBrain(seed: 4)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        try expectEqual(brain.perform(.play, context: ctx), .handled)
        try expectEqual(brain.memory.lastCommand, .play)
        try expectTrue(brain.memory.lastCommandAt != nil)
        try expectTrue(brain.memory.lastPlayAt != nil)
    }

    runner.run("InteractionMemory.ignoredCommand_isNeverRecorded") {
        let brain = makeBrain(seed: 5)
        let ctx = PetContext() // no cursorX -- .comeHere and .follow are both ignored without one
        try expectEqual(brain.perform(.comeHere, context: ctx), .ignored)
        try expectTrue(brain.memory.lastCommand == nil, "an ignored command must never be recorded as having happened")
        try expectTrue(brain.memory.lastCommandAt == nil)
    }

    runner.run("InteractionMemory.tuckIn_eventuallyRecordsSleep") {
        let brain = makeBrain(seed: 7)
        let ctx = PetContext()
        _ = brain.perform(.sleep, context: ctx)
        for _ in 0..<600 where brain.memory.lastSleepAt == nil { brain.update(dt: 1, context: ctx) }
        try expectTrue(brain.memory.lastSleepAt != nil, "expected the brain to actually reach .sleep and record it within the simulation window")
    }

    runner.run("InteractionMemory.comeTell_recordsApproach") {
        let brain = makeBrain(seed: 8)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        _ = brain.perform(.comeHere, context: ctx)
        try expectTrue(brain.memory.lastApproachAt != nil)
    }

    runner.run("InteractionMemory.cursorApproached_recordsApproachEvenWhenTheReactionItselfIsGated") {
        // cursorApproached can be ignored by its own cooldown/chance roll,
        // but the *fact* that the cursor approached should still be
        // memorable -- this is an observation, not a reaction.
        let brain = makeBrain(seed: 9)
        let ctx = PetContext()
        _ = brain.handle(.cursorApproached, context: ctx)
        try expectTrue(brain.memory.lastApproachAt != nil)
    }

    runner.run("InteractionMemory.secondsSinceHelpers_computeElapsedCorrectly") {
        var m = InteractionMemory()
        try expectTrue(m.secondsSinceLastPlay(now: 100) == nil)
        m.lastPlayAt = 40
        try expectEqual(m.secondsSinceLastPlay(now: 100), 60)
        // Never negative, even if `now` is somehow earlier than the recorded time.
        try expectEqual(m.secondsSinceLastPlay(now: 10), 0)
    }

    // MARK: Memory is actually consumed (Stage 11.5) -- not just recorded

    runner.run("InteractionMemory.recentApproach_suppressesAnotherApproachWithinItsCooldown") {
        let brain = makeBrain(seed: 20)
        var ctx = PetContext(); ctx.cursorX = 900; ctx.cursorY = 0; ctx.cursorNearPet = false; ctx.userIdleSeconds = 200
        let approach: Set<PetBehavior> = [.followCursor, .investigate]
        var enteredApproach = false, leftApproachAt: Double?
        for _ in 0..<3000 {
            brain.update(dt: 1, context: ctx)
            if approach.contains(brain.behavior) {
                enteredApproach = true
            } else if enteredApproach, leftApproachAt == nil {
                leftApproachAt = brain.clock // the first approach behavior just finished
                break
            }
        }
        guard let leftAt = leftApproachAt else { try fail("expected at least one curious approach to start and finish"); return }
        // For the rest of the 120s cooldown window (measured from when
        // memory.lastApproachAt was recorded, not from when this test
        // happened to notice the behavior end), another approach must not
        // start again, even though the context hasn't changed at all.
        var approachedAgainWithinCooldown = false
        while brain.clock - leftAt < 110 {
            brain.update(dt: 1, context: ctx)
            if approach.contains(brain.behavior) { approachedAgainWithinCooldown = true; break }
        }
        try expectFalse(approachedAgainWithinCooldown, "expected memory.lastApproachAt to suppress a second approach within its own cooldown")
    }

    runner.run("InteractionMemory.playDrought_increasesPlayWeightTheLongerItsBeenSinceLastPlay") {
        // Two brains, identical except for how long ago (in simulated
        // time) their one play session was: the one with the longer
        // drought should show a measurably higher fraction of .play once
        // both are given the same long window to choose behaviors in.
        func playFraction(droughtSeconds: Double, seeds: [UInt64] = Array(1...24)) -> Double {
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed)
                let ctx = PetContext()
                _ = brain.handle(.doubleClick, context: ctx) // records memory.lastPlayAt at clock≈0
                brain.update(dt: droughtSeconds, context: ctx) // fast-forward the drought without scoring in between
                var hits = 0
                let ticks = 4000
                for _ in 0..<ticks { brain.update(dt: 1, context: ctx); if brain.behavior == .play { hits += 1 } }
                total += Double(hits) / Double(ticks)
            }
            return total / Double(seeds.count)
        }
        let shortDrought = playFraction(droughtSeconds: 10)
        let longDrought = playFraction(droughtSeconds: 1800) // the full 30-minute cap
        try expectTrue(longDrought > shortDrought, "expected a longer play drought to increase play's weight: long=\(longDrought) short=\(shortDrought)")
    }

    runner.run("InteractionMemory.isBounded_neverGrowsAcrossManyEvents") {
        // Unlike a log, this is a fixed handful of fields -- repeatedly
        // triggering the same kind of event just overwrites the same
        // field, never accumulates.
        let brain = makeBrain(seed: 10)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        for _ in 0..<50 {
            _ = brain.handle(.click, context: ctx)
            brain.update(dt: 1, context: ctx)
        }
        // Still exactly one InteractionMemory value with 6 fields -- there is
        // no way for this type to hold more than that, which is the actual
        // guarantee (this assertion documents the intent rather than
        // testing storage, since Swift's type system already guarantees it).
        try expectTrue(brain.memory.lastInteractionAt != nil)
    }
}
