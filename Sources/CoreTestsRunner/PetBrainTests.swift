import Foundation
import Core

/// The clip ids shipped by Characters/biscuit-proto/manifest.json.
private let biscuitClips: Set<String> = [
    "stand", "stand_bark", "sit", "sit_bark", "lie", "yawn", "sleep", "walk", "walk_bark",
    "run", "gallop", "beg", "beg_bark", "dragged", "fall", "land",
]

private func makeBrain(seed: UInt64 = 42, minX: Double = 0, maxX: Double = 1600, minY: Double = 70, maxY: Double = 900,
                       intro: Bool = true, energy: Double = 0.55) -> PetBrain {
    PetBrain(
        config: .init(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: biscuitClips),
        x: minX + 24, y: minY, minX: minX, maxX: maxX, minY: minY, maxY: maxY, energy: energy, intro: intro, rng: SeededRandom(seed: seed)
    )
}

private func ctx(hour: Int = 14, focus: Bool = false, quiet: Bool = false, idle: Double = 0, reducedMotion: Bool = false, cursorX: Double? = 800) -> PetContext {
    var c = PetContext()
    c.hour = hour
    c.focusActive = focus
    c.quietHours = quiet
    c.userIdleSeconds = idle
    c.reducedMotion = reducedMotion
    c.cursorX = cursorX
    return c
}

func runPetBrainTests(_ runner: TestRunner) {
    runner.run("PetBrain.catalogHasAtLeast50Behaviors_andMostAreRenderableWithRealArt") {
        let brain = makeBrain()
        try expectTrue(PetBehavior.allCases.count >= 50, "catalog has \(PetBehavior.allCases.count)")
        let available = brain.availableBehaviors
        try expectTrue(available.count >= 50, "only \(available.count) behaviors renderable with real clips")
        // Art-less behaviors are excluded rather than faked.
        try expectFalse(brain.isAvailable(.stretch))
        try expectFalse(brain.isAvailable(.playBow))
        try expectTrue(brain.isAvailable(.sleep))
    }

    runner.run("PetBrain.introSequence_sitsLooksAroundWalksAwayAndBack") {
        let brain = makeBrain()
        var seen: [PetBehavior] = [brain.behavior]
        brain.onBehaviorChange = { _, new in seen.append(new) }
        let c = ctx(cursorX: nil)
        for _ in 0..<(150 * 10) { brain.update(dt: 0.1, context: c) }
        try expectEqual(Array(seen.prefix(5)), [.settleIn, .lookAround, .walk, .returnHome, .sit])
    }

    runner.run("PetBrain.xAlwaysWithinBounds_andFacingMatchesMovement_over6SimulatedHours") {
        let brain = makeBrain(seed: 7)
        let rng = SeededRandom(seed: 99)
        var lastX = brain.x
        var lastY = brain.y
        var lastFacing = brain.facing
        var movingUpdates = 0
        var strictMismatches = 0
        var c = ctx()
        for i in 0..<(6 * 3600 * 10) {
            if i % 3000 == 0 { c.cursorX = rng.uniform(0...1600) }
            if i % 7919 == 0 { brain.handle(.click, context: c) }
            if i % 50_000 == 0 { brain.setBounds(minX: 0, maxX: rng.chance(0.5) ? 1600 : 900, minY: 70, maxY: rng.chance(0.5) ? 900 : 400); lastX = brain.x; lastY = brain.y }
            brain.update(dt: 0.1, context: c)
            try expectTrue(brain.x >= brain.minX - 1e-9 && brain.x <= brain.maxX + 1e-9, "x out of bounds: \(brain.x)")
            try expectTrue(brain.y >= brain.minY - 1e-9 && brain.y <= brain.maxY + 1e-9, "y out of bounds: \(brain.y)")
            try expectTrue(biscuitClips.contains(brain.clip), "unknown clip \(brain.clip)")
            let dx = brain.x - lastX
            let dy = brain.y - lastY
            if abs(dx) > 1e-6, abs(dx) >= abs(dy) * 0.25, brain.isMoving, ["walk", "walk_bark", "run", "gallop"].contains(brain.clip) {
                let dir: Facing = dx > 0 ? .right : .left
                movingUpdates += 1
                // A reversal can happen at the end of an update (arrive, then
                // turn), so the move may match the facing from before it.
                try expectTrue(dir == brain.facing || dir == lastFacing, "walked backwards: \(brain.behavior) dx \(dx)")
                if dir != brain.facing { strictMismatches += 1 }
            }
            lastFacing = brain.facing
            lastX = brain.x
            lastY = brain.y
        }
        try expectTrue(movingUpdates > 10_000, "barely moved: \(movingUpdates)")
        try expectTrue(Double(strictMismatches) / Double(movingUpdates) < 0.01, "\(strictMismatches) turn frames of \(movingUpdates)")
    }

    runner.run("PetBrain.naturalSleepLasts2to3Minutes_andNeverEndsEarlyWithoutUserAction") {
        let brain = makeBrain(seed: 3)
        var sleepStart: Double?
        var durations: [Double] = []
        brain.onBehaviorChange = { old, new in
            if new == .sleep { sleepStart = brain.clock }
            if old == .sleep, let s = sleepStart { durations.append(brain.clock - s) }
        }
        let c = ctx()
        for _ in 0..<(3 * 3600 * 10) { brain.update(dt: 0.1, context: c) }
        try expectTrue(durations.count >= 3, "expected several naps in 3h, got \(durations.count)")
        // The measured span covers the whole .sleep behavior, including its
        // yawn preamble (1.4...1.6s) before the sleep clip itself (120...180s),
        // since onBehaviorChange only fires at the outer behavior boundary.
        for d in durations { try expectTrue(d >= 119.9 && d <= 181.8, "sleep lasted \(d)s") }
    }

    runner.run("PetBrain.rhythm_liesDownBeforeSleeping_andSleepsWithinFirst10Minutes") {
        let brain = makeBrain(seed: 11)
        var firstSleepAt: Double?
        var clipBeforeSleep: String?
        var lastClip = brain.clip
        let c = ctx()
        for _ in 0..<(10 * 60 * 10) {
            brain.update(dt: 0.1, context: c)
            if brain.behavior == .sleep && firstSleepAt == nil { firstSleepAt = brain.clock; clipBeforeSleep = lastClip }
            if brain.clip != "sleep" { lastClip = brain.clip }
        }
        try expectNotNil(firstSleepAt)
        try expectTrue(["lie", "yawn"].contains(clipBeforeSleep ?? ""), "went to sleep from \(clipBeforeSleep ?? "nil")")
    }

    runner.run("PetBrain.clickWakesSleepingPet_withYawnThenLooksAtUser_andStaysAwake") {
        let brain = makeBrain(seed: 5)
        let c = ctx(cursorX: 1400)
        var guardSteps = 0
        while brain.behavior != .sleep && guardSteps < 20 * 60 * 10 { brain.update(dt: 0.1, context: c); guardSteps += 1 }
        try expectEqual(brain.behavior, .sleep)
        brain.update(dt: 10, context: c)
        let outcome = brain.handle(.click, context: c)
        try expectTrue(outcome.woke)
        try expectEqual(brain.behavior, .wakeUp)
        try expectEqual(brain.clip, "yawn")
        for _ in 0..<20 { brain.update(dt: 0.1, context: c) } // 2s: past the yawn
        try expectEqual(brain.clip, "sit")
        try expectEqual(brain.facing, .right) // toward cursor at x=1400
        var sleptAgainWithin60s = false
        for _ in 0..<600 { brain.update(dt: 0.1, context: c); if brain.behavior == .sleep { sleptAgainWithin60s = true } }
        try expectFalse(sleptAgainWithin60s)
    }

    runner.run("PetBrain.barkOnClick_isProbabilistic_andRespectsCooldown") {
        let brain = makeBrain(seed: 21, intro: false, energy: 1)
        let c = ctx()
        var barkTimes: [Double] = []
        var clicks = 0
        for _ in 0..<80 {
            for _ in 0..<50 { brain.update(dt: 0.1, context: c) } // 5s apart
            if brain.behavior == .sleep { continue }
            clicks += 1
            if brain.handle(.click, context: c).barked { barkTimes.append(brain.clock) }
        }
        try expectTrue(barkTimes.count > 3 && barkTimes.count < clicks / 2, "barked \(barkTimes.count)/\(clicks)")
        for (a, b) in zip(barkTimes, barkTimes.dropFirst()) { try expectTrue(b - a >= 10, "barks \(b - a)s apart") }
    }

    runner.run("PetBrain.noBarksOrRunningDuringFocusOrQuietHours") {
        for context in [ctx(focus: true), ctx(quiet: true)] {
            let brain = makeBrain(seed: 8, intro: false, energy: 1)
            for i in 0..<(30 * 60 * 10) {
                if i % 600 == 0 { brain.handle(.click, context: context) }
                if i % 3000 == 0 { brain.handle(.taskCompleted, context: context) }
                brain.update(dt: 0.1, context: context)
                try expectFalse(brain.clip.hasSuffix("_bark"), "barked (\(brain.behavior))")
                try expectFalse(brain.clip == "gallop")
            }
        }
    }

    runner.run("PetBrain.reducedMotion_neverRunsOrGallops") {
        let brain = makeBrain(seed: 13, intro: false, energy: 1)
        let c = ctx(reducedMotion: true)
        for i in 0..<(60 * 60 * 10) {
            if i % 400 == 0 { brain.handle(.click, context: c) }
            if i % 5000 == 0 { brain.handle(.focusCompleted, context: c) }
            brain.update(dt: 0.1, context: c)
            try expectFalse(brain.clip == "gallop" || brain.clip == "run", "clip \(brain.clip) in \(brain.behavior)")
        }
    }

    runner.run("PetBrain.clickBarkUsesPostureSpecificBark") {
        // Seed search: find a click that barks while sitting.
        var found = false
        for seed in UInt64(1)...200 where !found {
            let brain = makeBrain(seed: seed, intro: false, energy: 1)
            let c = ctx()
            for _ in 0..<100 { brain.update(dt: 0.1, context: c) }
            guard brain.posturePublic == "sit" && brain.behavior != .sleep else { continue }
            if brain.handle(.click, context: c).barked {
                try expectEqual(brain.clip, "sit_bark")
                found = true
            }
        }
        try expectTrue(found, "no sitting bark in 200 seeds")
    }

    runner.run("PetBrain.tinyOrCollapsedBounds_neverCrashOrEscape") {
        let brain = makeBrain(minX: 100, maxX: 100)
        let c = ctx()
        for _ in 0..<(10 * 60 * 10) { brain.update(dt: 0.1, context: c) }
        try expectEqual(brain.x, 100)
        brain.setBounds(minX: 50, maxX: 20) // inverted: collapses to minX
        try expectEqual(brain.x, 50)
        brain.setBounds(minX: 0, maxX: 1000)
        brain.place(x: 5000)
        try expectEqual(brain.x, 1000)
    }

    runner.run("PetBrain.dragFallLand_andClicksIgnoredWhileHeld") {
        let brain = makeBrain(intro: false)
        let c = ctx()
        brain.handle(.dragBegan, context: c)
        try expectEqual(brain.behavior, .dragged)
        try expectTrue(brain.handle(.click, context: c).ignored)
        brain.handle(.dropped, context: c)
        try expectEqual(brain.behavior, .landing)
        for _ in 0..<30 { brain.update(dt: 0.1, context: c) }
        try expectFalse(brain.behavior == .landing)
    }

    runner.run("PetBrain.taskCompletedWhileAsleep_wakesThenCelebrates") {
        let brain = makeBrain(seed: 5)
        let c = ctx()
        var n = 0
        while brain.behavior != .sleep && n < 20 * 60 * 10 { brain.update(dt: 0.1, context: c); n += 1 }
        let outcome = brain.handle(.taskCompleted, context: c)
        try expectTrue(outcome.woke)
        try expectEqual(brain.behavior, .wakeUp)
        try expectEqual(brain.queuedBehaviors.first, .celebrateTask)
    }

    runner.run("PetBrain.focusStarted_settlesIntoQuietCompanionPose") {
        let brain = makeBrain(intro: false, energy: 1)
        let c = ctx(focus: true)
        brain.handle(.focusStarted, context: c)
        try expectEqual(brain.behavior, .focusCompanion)
        for _ in 0..<(60 * 10) { brain.update(dt: 0.1, context: c) }
        try expectEqual(brain.clip, "lie")
        try expectFalse(brain.isMoving)
    }

    runner.run("PetBrain.repeatedWakingMakesPetGrumpy_notHyper") {
        let brain = makeBrain(seed: 5)
        let c = ctx()
        for _ in 0..<3 {
            brain.handle(.dragBegan, context: c); brain.handle(.dropped, context: c); brain.handle(.landed, context: c)
            // force back to sleep via the rest ladder
            var n = 0
            while brain.behavior != .sleep && brain.behavior != .grumpyWake && n < 30 * 60 * 10 { brain.update(dt: 0.1, context: c); n += 1 }
            brain.handle(.click, context: c)
        }
        try expectEqual(brain.behavior, .grumpyWake)
    }

    runner.run("PetBrain.sleepingPetGetsMicroTwitches") {
        let brain = makeBrain(seed: 5)
        let c = ctx()
        var n = 0
        while brain.behavior != .sleep && n < 20 * 60 * 10 { brain.update(dt: 0.1, context: c); n += 1 }
        var twitches = 0
        for _ in 0..<(110 * 10) {
            brain.update(dt: 0.1, context: c)
            if brain.takeMicroAnimation() == .twitch { twitches += 1 }
        }
        try expectTrue(twitches >= 1 && twitches <= 8, "twitches \(twitches)")
        try expectEqual(brain.behavior, .sleep) // twitching never ends the primary behavior
    }

    runner.run("PetBrain.hugeTimeJump_staysOnItsPath_neverTeleports") {
        let brain = makeBrain(intro: false, energy: 1)
        let c = ctx()
        var n = 0
        while brain.leg == nil && n < 10_000 { brain.update(dt: 0.1, context: c); n += 1 }
        guard let l = brain.leg else { try fail("never moved"); return }
        brain.update(dt: 3600, context: c)
        // Ends exactly where that leg was going -- along its path, never elsewhere.
        try expectTrue(abs(brain.x - l.toX) < 1e-6 && abs(brain.y - l.toY) < 1e-6, "ended at \(brain.x),\(brain.y)")
    }

    // MARK: 2-D movement

    runner.run("PetBrain2D.roamsTheWholeDesktop_includingTopAndDiagonals") {
        let brain = makeBrain(seed: 31, intro: false, energy: 1)
        let c = ctx()
        var maxYSeen = 0.0, legs = 0, diagonal = 0, lastLegRev = brain.legRevision
        for _ in 0..<(3 * 3600 * 10) {
            brain.update(dt: 0.1, context: c)
            maxYSeen = max(maxYSeen, brain.y)
            if brain.legRevision != lastLegRev, let l = brain.leg {
                legs += 1
                let dx = abs(l.toX - l.fromX), dy = abs(l.toY - l.fromY)
                if dx > 0.3 * l.distance && dy > 0.3 * l.distance { diagonal += 1 }
            }
            lastLegRev = brain.legRevision
        }
        try expectTrue(maxYSeen > 70 + (900 - 70) * 0.7, "never went near the top: \(maxYSeen)")
        try expectTrue(legs > 100, "legs \(legs)")
        try expectTrue(Double(diagonal) / Double(legs) > 0.15, "diagonal legs \(diagonal)/\(legs)")
    }

    runner.run("PetBrain2D.droppedAtTopStaysThere_andResumesFromThatSpot") {
        let brain = makeBrain(seed: 9, intro: false, energy: 1)
        let c = ctx()
        brain.handle(.dragBegan, context: c)
        brain.place(x: 1200, y: 850)
        brain.handle(.dropped, context: c)
        try expectEqual(brain.behavior, .landing)
        try expectEqual(brain.x, 1200)
        try expectEqual(brain.y, 850)
        var firstLeg: MovementLeg?
        for _ in 0..<(120 * 10) {
            brain.update(dt: 0.1, context: c)
            if firstLeg == nil, let l = brain.leg { firstLeg = l }
        }
        guard let l = firstLeg else { try fail("never moved again"); return }
        try expectTrue(abs(l.fromX - 1200) < 1 && abs(l.fromY - 850) < 1, "resumed from \(l.fromX),\(l.fromY)")
        try expectTrue(brain.y > 70 + 1 || brain.behavior != .returnHome, "snapped to the floor")
    }

    runner.run("PetBrain2D.legsEaseInAndOut_andArriveExactly") {
        let l = MovementLeg(fromX: 0, fromY: 0, toX: 300, toY: 400, duration: 2, elapsed: 0)
        try expectTrue(abs(MovementEasing.progress(0)) < 1e-9)
        try expectTrue(abs(MovementEasing.progress(1) - 1) < 1e-9)
        try expectTrue(abs(MovementEasing.progress(0.5) - 0.5) < 1e-3)
        let early = MovementEasing.progress(0.1), mid = MovementEasing.progress(0.55) - MovementEasing.progress(0.45)
        try expectTrue(early < 0.05, "no gentle start: \(early)")
        try expectTrue(mid > 0.1 * 1.3, "no cruise: \(mid)")
        var last = -1.0
        for i in 0...100 { let p = MovementEasing.progress(Double(i) / 100); try expectTrue(p >= last); last = p }
        try expectEqual(l.distance, 500)
    }

    runner.run("PetBrain2D.facingFollowsHorizontalDirectionOfEachLeg") {
        let brain = makeBrain(seed: 77, intro: false, energy: 1)
        let c = ctx()
        var lastLegRev = brain.legRevision, checked = 0
        for _ in 0..<(3600 * 10) {
            brain.update(dt: 0.1, context: c)
            if brain.legRevision != lastLegRev, let l = brain.leg, abs(l.toX - l.fromX) >= abs(l.toY - l.fromY) * 0.25 {
                try expectEqual(brain.facing, l.toX > l.fromX ? .right : .left)
                checked += 1
            }
            lastLegRev = brain.legRevision
        }
        try expectTrue(checked > 50)
    }

    runner.run("PetBrain2D.boundsShrink_clampsInPlaceWithoutGoingHome") {
        let brain = makeBrain(intro: false)
        brain.place(x: 800, y: 800)
        brain.setBounds(minX: 0, maxX: 1600, minY: 70, maxY: 500)
        try expectEqual(brain.x, 800)
        try expectEqual(brain.y, 500)
    }

    runner.run("PetBrain2D.nextEventIn_matchesWhenTheBrainNeedsToThink") {
        let brain = makeBrain(intro: false)
        let c = ctx()
        for _ in 0..<200 {
            let wait = brain.nextEventIn
            try expectTrue(wait > 0 && wait < 400)
            let rev = brain.behaviorRevision, leg = brain.legRevision, vis = brain.visualRevision
            brain.update(dt: wait * 0.5, context: c)
            // Nothing structural changes before the announced time (facing can for lookAround).
            try expectEqual(brain.behaviorRevision, rev)
            try expectEqual(brain.legRevision, leg)
            _ = vis
            brain.update(dt: wait * 0.5 + 0.001, context: c)
        }
    }

    runner.run("PetBrain2D.tuckInSleepsSoon_wakeRequestWakes") {
        let brain = makeBrain(intro: false, energy: 1)
        let c = ctx()
        brain.handle(.tuckIn, context: c)
        var slept = false
        for _ in 0..<(60 * 10) { brain.update(dt: 0.1, context: c); if brain.behavior == .sleep { slept = true; break } }
        try expectTrue(slept)
        try expectTrue(brain.handle(.wakeRequest, context: c).woke)
        try expectEqual(brain.behavior, .wakeUp)
    }

    runner.run("PetBrain2D.askUserWaitsAttentively_untilAnswered") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: biscuitClips.union(["happy"])),
                             x: 100, y: 70, minX: 0, maxX: 1600, minY: 70, maxY: 900, energy: 1, intro: false, rng: SeededRandom(seed: 4))
        let c = ctx()
        brain.handle(.askUser, context: c)
        try expectEqual(brain.behavior, .askUser)
        for _ in 0..<(10 * 10) { brain.update(dt: 0.1, context: c) }
        try expectEqual(brain.behavior, .askUser)
        try expectFalse(brain.isMoving)
        brain.handle(.answered(positive: true), context: c)
        try expectEqual(brain.behavior, .clickHappy)
    }

    runner.run("PetBrain2D.askUserHoldsForMinutes_whileQuestionOpen") {
        // Snooze follow-ups can sit open a long time; the pet must not wander off.
        let brain = PetBrain(config: .init(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: biscuitClips.union(["happy"])),
                             x: 400, y: 300, minX: 0, maxX: 1600, minY: 70, maxY: 900, energy: 1, intro: false, rng: SeededRandom(seed: 9))
        let c = ctx()
        brain.handle(.askUser, context: c)
        for _ in 0..<(6 * 60 * 10) {
            brain.update(dt: 0.1, context: c)
            if brain.behavior != .askUser || brain.isMoving { break }
        }
        try expectEqual(brain.behavior, .askUser)
        try expectFalse(brain.isMoving)
        try expectEqual(brain.x, 400)
    }

    // MARK: Round 5: sync, approach, mood

    let allClips = biscuitClips.union(["happy", "celebrate"])
    func brain5(seed: UInt64 = 5, energy: Double = 1) -> PetBrain {
        PetBrain(config: .init(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: allClips),
                 x: 800, y: 500, minX: 0, maxX: 1600, minY: 70, maxY: 900, energy: energy, intro: false, rng: SeededRandom(seed: seed))
    }

    runner.run("PetBrainSync.goHomeWalks_neverSlidesInAStillPose") {
        let b = brain5()
        var c = ctx(cursorX: nil)
        c.cursorY = nil
        b.handle(.goHome, context: c)
        try expectEqual(b.behavior, .returnHome)
        var sawWalkClip = false
        for _ in 0..<400 {
            b.update(dt: 0.1, context: c)
            if b.leg != nil {
                // Whenever the pet is actually travelling, it shows a locomotion clip.
                try expectTrue(["walk", "run", "gallop", "walk_bark"].contains(b.clip), "moving while showing \(b.clip)")
                sawWalkClip = true
            }
            if b.behavior != .returnHome { break }
        }
        try expectTrue(sawWalkClip)
        try expectTrue(abs(b.x - b.homeX) < 60 && abs(b.y - b.homeY) < 30, "ended at \(b.x),\(b.y)")
    }

    runner.run("PetBrainSync.neverTravelsInAStillPose_overHoursForAllBehaviors") {
        let b = brain5(seed: 44)
        var c = ctx()
        let rng = SeededRandom(seed: 3)
        for i in 0..<(4 * 3600 * 10) {
            if i % 3000 == 0 { c.cursorX = rng.uniform(0...1600); c.cursorY = rng.uniform(70...900) }
            if i % 9001 == 0 { b.handle(.comeTell, context: c) }
            if i % 12007 == 0 { b.handle(.checkIn, context: c) }
            if i % 7919 == 0 { b.handle(.click, context: c) }
            b.update(dt: 0.1, context: c)
            if b.leg != nil {
                try expectTrue(["walk", "run", "gallop", "walk_bark"].contains(b.clip), "\(b.behavior) travels as \(b.clip)")
            }
        }
    }

    runner.run("PetBrainSync.comeTell_walksAFewStepsTowardTheUser_thenAsks") {
        let b = brain5()
        var c = ctx(cursorX: 1500)
        c.cursorY = 850
        b.handle(.comeTell, context: c)
        try expectEqual(b.behavior, .comeTell)
        let start = (b.x, b.y)
        var n = 0
        while b.behavior != .askUser && n < 600 { b.update(dt: 0.1, context: c); n += 1 }
        try expectEqual(b.behavior, .askUser)
        let moved = hypot(b.x - start.0, b.y - start.1)
        try expectTrue(moved > 50 && moved <= 100 * 3 + 1, "moved \(moved)")
        // Already next to the user: asks straight away.
        let near = brain5()
        var c2 = ctx(cursorX: 850)
        c2.cursorY = 550
        near.handle(.comeTell, context: c2)
        try expectEqual(near.behavior, .askUser)
    }

    runner.run("PetBrainSync.sleepIsPrecededByAYawn") {
        let b = brain5(seed: 9, energy: 0.1)
        let c = ctx()
        var clipBeforeSleep = ""
        var last = b.clip
        for _ in 0..<(20 * 60 * 10) {
            b.update(dt: 0.1, context: c)
            if b.clip == "sleep" { clipBeforeSleep = last; break }
            last = b.clip
        }
        try expectEqual(clipBeforeSleep, "yawn")
    }

    runner.run("PetBrainMood.followCursorOff_neverReactsToTheCursor") {
        let b = brain5()
        b.setCursorInterest(0)
        var c = ctx(cursorX: 820)
        c.cursorNearPet = true
        var reacted = 0
        for i in 0..<(3600 * 10) {
            if i % 100 == 0 && !b.handle(.cursorApproached, context: c).ignored { reacted += 1 }
            b.update(dt: 0.1, context: c)
            try expectFalse([.followCursor, .investigate, .watchCursor].contains(b.behavior), "chose \(b.behavior)")
        }
        try expectEqual(reacted, 0)
    }

    runner.run("PetBrainMood.moodReflectsState") {
        let b = brain5(energy: 0.1)
        try expectEqual(b.mood(ctx()), .sleepy)
        let happy = brain5(energy: 0.6)
        var c = ctx()
        c.focusActive = true
        try expectEqual(happy.mood(c), .focused)
        happy.handle(.taskCompleted, context: ctx())
        try expectEqual(happy.mood(ctx()), .excited)
        let clicked = brain5(energy: 0.6)
        for _ in 0..<5 { clicked.handle(.click, context: ctx()); clicked.update(dt: 12, context: ctx()) }
        try expectTrue([.happy, .playful].contains(clicked.mood(ctx())), "\(clicked.mood(ctx()))")
    }
}
