import Foundation
import Core

/// Stage 10.2-10.6: the environment object model, its integration into
/// behavior scoring via PetContext.bedX/bedY, and its failure/interruption
/// recovery.
func runEnvironmentObjectTests(_ runner: TestRunner) {
    let fullClips: Set<String> = [
        "stand", "sit", "walk", "walk_left", "walk_right", "run", "run_left", "run_right",
        "lie", "sleep", "doze", "settle", "yawn",
    ]
    func makeBrain(seed: UInt64, x: Double = 500) -> PetBrain {
        let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        return PetBrain(config: config, x: x, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
    }

    // MARK: Registration / discovery (10.2)

    runner.run("EnvironmentObject.nearestAvailable_findsTheClosestOne_ignoresUnavailableAndWrongKind") {
        let far = EnvironmentObject(id: "far-bed", kind: .bed, x: 900, y: 0)
        let near = EnvironmentObject(id: "near-bed", kind: .bed, x: 520, y: 0)
        let unavailable = EnvironmentObject(id: "closed-bed", kind: .bed, x: 500, y: 0, isAvailable: false)
        let found = EnvironmentObject.nearestAvailable(of: .bed, in: [far, unavailable, near], fromX: 500, fromY: 0)
        try expectEqual(found?.id, "near-bed")
    }

    runner.run("EnvironmentObject.nearestAvailable_returnsNilWhenNoneQualify") {
        let unavailable = EnvironmentObject(id: "closed-bed", kind: .bed, x: 500, y: 0, isAvailable: false)
        try expectTrue(EnvironmentObject.nearestAvailable(of: .bed, in: [unavailable], fromX: 500, fromY: 0) == nil)
        try expectTrue(EnvironmentObject.nearestAvailable(of: .bed, in: [], fromX: 500, fromY: 0) == nil)
    }

    // MARK: Behavior integration (10.5) -- environment as another scoring input

    runner.run("EnvironmentObject.sleepyPet_choosesGoToBedMoreOftenWhenABedIsAvailable") {
        let noBedCtx = PetContext()
        var bedCtx = PetContext(); bedCtx.bedX = 300; bedCtx.bedY = 0
        func fractionGoingToBed(_ ctx: PetContext, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed)
                var hits = 0
                let ticks = 4000
                for _ in 0..<ticks {
                    brain.update(dt: 1, context: ctx)
                    if brain.behavior == .goToBed { hits += 1 }
                }
                total += Double(hits) / Double(ticks)
            }
            return total / Double(seeds.count)
        }
        try expectEqual(fractionGoingToBed(noBedCtx), 0) // never chosen when no bed exists
        try expectTrue(fractionGoingToBed(bedCtx) > 0, "expected a sleepy pet to sometimes choose an available bed")
    }

    // MARK: Approach -> interact -> complete -> return to autonomy (10.3/10.4)

    runner.run("EnvironmentObject.goToBed_walksToTheBedThenLiesDownThere") {
        // Late night -> naturally high sleepiness over time, purely through
        // the existing autonomous scoring (never a forced command) -- so a
        // real goToBed choice, not a scripted one, is what's being proven.
        let brain = makeBrain(seed: 10, x: 100)
        var ctx = PetContext(); ctx.hour = 2; ctx.bedX = 700; ctx.bedY = 0
        var reachedBedBeforeLying = false
        for _ in 0..<20_000 {
            brain.update(dt: 1, context: ctx)
            if brain.behavior == .goToBed, abs(brain.x - 700) < 40 { reachedBedBeforeLying = true }
            if reachedBedBeforeLying, brain.behavior == .lie || brain.behavior == .sleep {
                try expectTrue(abs(brain.x - 700) < 40, "expected it to still be at the bed once lying down, x=\(brain.x)")
                return
            }
        }
        try fail("expected the pet to eventually choose goToBed, reach the bed, and lie down there within the simulation window")
    }

    // MARK: Interruption / fallback (10.6) -- object disappears mid-approach

    runner.run("EnvironmentObject.bedRemovedMidApproach_neverGetsStuckApproachingForever") {
        let brain = makeBrain(seed: 11, x: 100)
        var ctx = PetContext(); ctx.bedX = 900; ctx.bedY = 0
        // Let it commit to heading toward the (distant) bed.
        for _ in 0..<20 { brain.update(dt: 0.5, context: ctx) }
        // The object vanishes (e.g. removed, or another character/user
        // claims it) -- exactly the failure case Stage 10.6 asks for.
        ctx.bedX = nil
        ctx.bedY = nil
        var everStuckApproaching = true
        for _ in 0..<3000 {
            brain.update(dt: 0.5, context: ctx)
            if brain.behavior != .goToBed { everStuckApproaching = false; break }
        }
        try expectFalse(everStuckApproaching, "expected the pet to abandon the approach and fall back to ordinary autonomous behavior, never approach forever")
        // And it keeps producing valid state afterward -- no leaked target.
        for _ in 0..<200 { brain.update(dt: 0.5, context: ctx) }
        try expectTrue(brain.x.isFinite)
    }

    runner.run("EnvironmentObject.fullBedCycle_approachLieSleepWakeThenResumesAutonomy") {
        // Stage 10.8B's full flow, driven entirely by natural sleepiness
        // (never a forced command): approach -> lie -> sleep -> wake ->
        // leave the bed behind by resuming ordinary autonomous behavior.
        let brain = makeBrain(seed: 10, x: 100)
        var ctx = PetContext(); ctx.hour = 2; ctx.bedX = 700; ctx.bedY = 0
        var sawApproach = false, sawLie = false, sawSleep = false, sawWakeOrAfter = false
        for _ in 0..<60_000 {
            brain.update(dt: 1, context: ctx)
            switch brain.behavior {
            case .goToBed: sawApproach = true
            case .lie where sawApproach: sawLie = true
            case .sleep where sawLie: sawSleep = true
            case .naturalWake where sawSleep: sawWakeOrAfter = true
            case .stand where sawSleep: sawWakeOrAfter = true
            case .sitLookAround where sawSleep: sawWakeOrAfter = true
            case .lookAround where sawSleep: sawWakeOrAfter = true
            default: break
            }
            if sawWakeOrAfter { break }
        }
        try expectTrue(sawApproach, "never approached the bed")
        try expectTrue(sawLie, "never lay down at the bed")
        try expectTrue(sawSleep, "never actually fell asleep at the bed")
        try expectTrue(sawWakeOrAfter, "never woke up and resumed some other behavior afterward")
        try expectTrue(brain.x.isFinite && brain.energy.isFinite)
    }

    runner.run("EnvironmentObject.invalidOrExtremeBedCoordinates_neverProduceNonFiniteOrOutOfBoundsMovement") {
        // Stage 10.9: a corrupted/invalid persisted position (or a screen
        // dimension change leaving a stale coordinate way off-screen) must
        // never leak into an out-of-bounds or non-finite pet position --
        // pickTarget's own clamp() is the single place this is enforced.
        for badX: Double in [999_999, -999_999, Double.infinity, -Double.infinity] {
            let brain = makeBrain(seed: 15, x: 500)
            var ctx = PetContext(); ctx.hour = 2; ctx.bedX = badX; ctx.bedY = 0
            for _ in 0..<3000 {
                brain.update(dt: 1, context: ctx)
                try expectTrue(brain.x.isFinite, "non-finite x from bad bedX=\(badX)")
                try expectTrue(brain.x >= -1 && brain.x <= 1001, "out-of-bounds x=\(brain.x) from bad bedX=\(badX)")
            }
        }
    }

    runner.run("EnvironmentObject.stopCommand_abandonsAnInProgressBedApproach") {
        let brain = makeBrain(seed: 16, x: 100)
        var ctx = PetContext(); ctx.hour = 2; ctx.bedX = 900; ctx.bedY = 0
        var reachedApproach = false
        for _ in 0..<5000 {
            brain.update(dt: 1, context: ctx)
            if brain.behavior == .goToBed { reachedApproach = true; break }
        }
        try expectTrue(reachedApproach, "fixture assumption: expected to be approaching the bed before testing .stop")
        _ = brain.perform(.stop, context: ctx)
        // .stop's .goHome event takes over immediately (it doesn't wait for
        // the in-flight leg) -- confirms the command layer can always
        // override an object interaction, never fight it silently.
        try expectEqual(brain.behavior, .returnHome)
        for _ in 0..<200 { brain.update(dt: 1, context: ctx) }
        try expectTrue(brain.x.isFinite)
    }

    // MARK: Behavior balance (10.11) -- the bed is a scoring input, never a forced action

    runner.run("EnvironmentObject.lowSleepiness_limitsBedInfluence_almostNeverChosen") {
        var ctx = PetContext(); ctx.hour = 14; ctx.bedX = 300; ctx.bedY = 0 // midday: naturally low sleepiness
        var total = 0.0
        for seed: UInt64 in [1, 2, 3, 4, 5, 6] {
            let brain = makeBrain(seed: seed)
            var hits = 0
            for _ in 0..<4000 {
                brain.update(dt: 1, context: ctx)
                if brain.behavior == .goToBed { hits += 1 }
            }
            total += Double(hits) / 4000
        }
        try expectTrue(total / 6 < 0.02, "expected the bed to have very limited influence at low sleepiness: \(total / 6)")
    }

    runner.run("EnvironmentObject.sleepMode_increasesBedInfluence_playModeDecreasesIt") {
        func fraction(_ mode: PetMode, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var ctx = PetContext(); ctx.hour = 2; ctx.bedX = 300; ctx.bedY = 0; ctx.mode = mode
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed)
                var hits = 0
                for _ in 0..<4000 {
                    brain.update(dt: 1, context: ctx)
                    if brain.behavior == .goToBed { hits += 1 }
                }
                total += Double(hits) / 4000
            }
            return total / Double(seeds.count)
        }
        let normal = fraction(.normal)
        let sleep = fraction(.sleep)
        let play = fraction(.play)
        try expectTrue(sleep > normal, "expected .sleep mode to increase bed influence: sleep=\(sleep) normal=\(normal)")
        try expectTrue(play < normal, "expected .play mode to decrease bed influence: play=\(play) normal=\(normal)")
    }

    runner.run("EnvironmentObject.explicitFollowCommand_heavilyDeprioritizesTheBed") {
        // A soft scoring signal, not an absolute lock (nothing in this
        // scoring model is a hard veto) -- so this compares the fraction
        // of time spent going to the bed with vs. without an open .follow
        // request, rather than asserting it can never happen at all.
        func fractionGoingToBed(follow: Bool, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var ctx = PetContext(); ctx.hour = 2; ctx.cursorX = 900; ctx.cursorY = 0; ctx.bedX = 700; ctx.bedY = 0
            var total = 0.0
            for seed in seeds {
                let brain = makeBrain(seed: seed, x: 100)
                if follow { _ = brain.startActivity(.followCursor, duration: 4000, context: ctx) }
                var hits = 0
                for _ in 0..<4000 {
                    brain.update(dt: 1, context: ctx)
                    if brain.behavior == .goToBed { hits += 1 }
                }
                total += Double(hits) / 4000
            }
            return total / Double(seeds.count)
        }
        let withoutFollow = fractionGoingToBed(follow: false)
        let withFollow = fractionGoingToBed(follow: true)
        try expectTrue(withFollow < withoutFollow, "expected an active .follow request to reduce time spent going to the bed: withFollow=\(withFollow) withoutFollow=\(withoutFollow)")
    }

    runner.run("EnvironmentObject.characterSwitchWhileHeadingToBed_freshBrainStartsClean") {
        let old = makeBrain(seed: 12, x: 100)
        var ctx = PetContext(); ctx.bedX = 900; ctx.bedY = 0
        for _ in 0..<50 { old.update(dt: 0.5, context: ctx) } // possibly mid-approach
        _ = old // discarded, mirroring a real character switch

        let fresh = makeBrain(seed: 13, x: 100)
        try expectFalse(fresh.isAsleep && fresh.isMoving)
        for _ in 0..<200 { fresh.update(dt: 0.5, context: ctx) }
        try expectTrue(fresh.x.isFinite && fresh.energy.isFinite)
    }
}
