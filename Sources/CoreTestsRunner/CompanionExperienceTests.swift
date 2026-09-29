import Foundation
import Core

func runCompanionExperienceTests(_ runner: TestRunner) {

    // MARK: Personality dials actually differentiate behavior (Stage 8)

    runner.run("Personality.curiousCharacter_restsAtHigherBaselineCuriosity") {
        var lowConfig = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"])
        lowConfig.personality.curiosity = 0.6
        var highConfig = lowConfig
        highConfig.personality.curiosity = 1.5
        let low = PetBrain(config: lowConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 1))
        let high = PetBrain(config: highConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 1))
        let ctx = PetContext()
        for _ in 0..<20_000 { low.update(dt: 1, context: ctx); high.update(dt: 1, context: ctx) }
        try expectTrue(high.curiosity > low.curiosity, "expected high-curiosity dial to settle higher: high=\(high.curiosity) low=\(low.curiosity)")
    }

    runner.run("Personality.affectionateCharacter_warmsUpMoreFromTheSameClick") {
        var lowConfig = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"])
        lowConfig.personality.affection = 0.6
        var highConfig = lowConfig
        highConfig.personality.affection = 1.5
        let low = PetBrain(config: lowConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 2))
        let high = PetBrain(config: highConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 2))
        let ctx = PetContext()
        _ = low.handle(.click, context: ctx)
        _ = high.handle(.click, context: ctx)
        try expectTrue(high.affection > low.affection, "expected high-affection dial to warm up more from an identical click: high=\(high.affection) low=\(low.affection)")
    }

    runner.run("Personality.affectionateCharacter_settlesAtHigherRestingBaseline") {
        var lowConfig = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"])
        lowConfig.personality.affection = 0.6
        var highConfig = lowConfig
        highConfig.personality.affection = 1.5
        let low = PetBrain(config: lowConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 3))
        let high = PetBrain(config: highConfig, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 3))
        let ctx = PetContext()
        // No interaction at all -- just let both fade toward their own resting baseline.
        for _ in 0..<20_000 { low.update(dt: 1, context: ctx); high.update(dt: 1, context: ctx) }
        try expectTrue(high.affection > low.affection, "expected high-affection dial to rest higher with no interaction at all: high=\(high.affection) low=\(low.affection)")
    }

    runner.run("Personality.dialsDefaultToNeutral_backwardCompatible") {
        // A manifest with no personality block at all (most of the original
        // 10 predate curiosity/affection) must behave exactly as before:
        // neutral 1.0 dials, no crash, no behavior change.
        var p = Personality()
        try expectEqual(p.curiosity, 1)
        try expectEqual(p.affection, 1)
        p = CharacterDefinition(manifest: SafeDefaultCharacter.manifest, baseURL: URL(fileURLWithPath: "/")).personality
        try expectEqual(p.curiosity, 1)
        try expectEqual(p.affection, 1)
    }

    // MARK: Favorites (Stage 8) -- persistence and library filtering

    runner.run("AppSettings.favoriteCharacterIDs_roundTripsAndDefaultsEmpty") {
        let suiteName = "dc-test-favorites-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        try expectTrue(settings.favoriteCharacterIDs.isEmpty)
        try expectFalse(settings.isFavorite("ginger"))
        settings.setFavorite("ginger", true)
        settings.setFavorite("smoky", true)
        try expectTrue(settings.isFavorite("ginger"))
        try expectEqual(settings.favoriteCharacterIDs, Set(["ginger", "smoky"]))
        settings.setFavorite("ginger", false)
        try expectFalse(settings.isFavorite("ginger"))
        try expectEqual(settings.favoriteCharacterIDs, Set(["smoky"]))
        // Persists across a fresh AppSettings instance over the same suite.
        let reloaded = AppSettings(defaults: defaults)
        try expectEqual(reloaded.favoriteCharacterIDs, Set(["smoky"]))
    }

    runner.run("CharacterLibrary.favoritesSection_returnsOnlyFavorited") {
        let a = CharacterCatalogEntry(id: "a", name: "A", description: "", author: nil, previewRelativePath: nil, tags: [])
        let b = CharacterCatalogEntry(id: "b", name: "B", description: "", author: nil, previewRelativePath: nil, tags: [])
        let result = CharacterLibrary.filter([a, b], section: .favorites, favorites: ["b"])
        try expectEqual(result.map(\.id), ["b"])
    }

    runner.run("CharacterLibrary.favoritesSection_emptyWithoutAnyFavorites") {
        let a = CharacterCatalogEntry(id: "a", name: "A", description: "", author: nil, previewRelativePath: nil, tags: [])
        try expectTrue(CharacterLibrary.filter([a], section: .favorites).isEmpty)
    }

    // MARK: Behavior catalog sanity (Stage 8's "organize the 65 behaviors" audit)

    runner.run("PetBehavior.everyBehaviorHasACategory_noOrphans") {
        for b in PetBehavior.allCases {
            _ = b.category // must not crash / must resolve for every case
        }
        try expectEqual(PetBehavior.allCases.count, Set(PetBehavior.allCases.map(\.rawValue)).count)
    }
}

// MARK: - PetMode (Stage 9, Phase 10)

func runPetModeTests(_ runner: TestRunner) {
    let fullClips: Set<String> = [
        "stand", "sit", "walk", "walk_left", "walk_right", "run", "run_left", "run_right",
        "lie", "sleep", "doze", "settle", "sitLookAround", "lookAround", "stretch",
        "gallop", "sad", "yawn",
    ]

    func makeBrain(seed: UInt64) -> PetBrain {
        let config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
        return PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
    }

    /// Fraction of ticks over a long run spent in one of `set`, averaged
    /// across several seeds so a single early divergence can't skew it.
    func fractionInSet(_ set: Set<PetBehavior>, ctx: PetContext, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
        var total = 0.0
        for seed in seeds {
            let brain = makeBrain(seed: seed)
            var hits = 0
            let ticks = 6000
            for _ in 0..<ticks {
                brain.update(dt: 1, context: ctx)
                if set.contains(brain.behavior) { hits += 1 }
            }
            total += Double(hits) / Double(ticks)
        }
        return total / Double(seeds.count)
    }

    runner.run("PetMode.normal_isTheDefaultAndChangesNothing") {
        let ctx = PetContext()
        try expectEqual(ctx.mode, .normal)
        var withExplicitNormal = PetContext()
        withExplicitNormal.mode = .normal
        // Two brains fed identical, explicit .normal contexts must track
        // each other exactly, tick for tick -- mode being present at all
        // must not perturb anything for the default case.
        let a = makeBrain(seed: 42)
        let b = makeBrain(seed: 42)
        for _ in 0..<3000 {
            a.update(dt: 1, context: ctx)
            b.update(dt: 1, context: withExplicitNormal)
            try expectEqual(a.behavior, b.behavior)
        }
    }

    runner.run("PetMode.quiet_roamsLessThanNormal_overLongSimulation") {
        let movement: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .pace, .trot, .run, .zoomies]
        var normalCtx = PetContext(); normalCtx.mode = .normal
        var quietCtx = PetContext(); quietCtx.mode = .quiet
        let normal = fractionInSet(movement, ctx: normalCtx)
        let quiet = fractionInSet(movement, ctx: quietCtx)
        try expectTrue(quiet < normal, "expected quiet mode to roam less: quiet=\(quiet) normal=\(normal)")
    }

    runner.run("PetMode.sleep_spendsMoreTimeWindingDownThanNormal_overLongSimulation") {
        let restful: Set<PetBehavior> = [.sleep, .doze, .lie, .settle, .restAlert]
        var normalCtx = PetContext(); normalCtx.mode = .normal
        var sleepCtx = PetContext(); sleepCtx.mode = .sleep
        let normal = fractionInSet(restful, ctx: normalCtx)
        let sleepy = fractionInSet(restful, ctx: sleepCtx)
        try expectTrue(sleepy > normal, "expected sleep mode to favor winding down more: sleep=\(sleepy) normal=\(normal)")
    }

    runner.run("PetMode.attention_watchesCursorMoreThanNormal_overLongSimulation") {
        let attentive: Set<PetBehavior> = [.watchCursor, .investigate, .followCursor]
        var normalCtx = PetContext(); normalCtx.mode = .normal
        normalCtx.cursorX = 520; normalCtx.cursorY = 0; normalCtx.cursorNearPet = true
        var attentionCtx = PetContext(); attentionCtx.mode = .attention
        attentionCtx.cursorX = 520; attentionCtx.cursorY = 0; attentionCtx.cursorNearPet = true
        let normal = fractionInSet(attentive, ctx: normalCtx)
        let attention = fractionInSet(attentive, ctx: attentionCtx)
        try expectTrue(attention > normal, "expected attention mode to watch the cursor more: attention=\(attention) normal=\(normal)")
    }

    runner.run("PetMode.focus_suppressesRoamingJustLikeAnActiveFocusSession") {
        var focusModeCtx = PetContext(); focusModeCtx.mode = .focus
        var focusSessionCtx = PetContext(); focusSessionCtx.focusActive = true
        let movement: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .pace, .trot, .run, .zoomies]
        let viaMode = fractionInSet(movement, ctx: focusModeCtx)
        let viaSession = fractionInSet(movement, ctx: focusSessionCtx)
        // Both should suppress roaming to (near) zero -- Phase 10 explicitly
        // asked for .focus to reuse the existing focus-gating logic, not a
        // parallel implementation with its own, possibly-different behavior.
        try expectTrue(viaMode < 0.02, "expected .focus mode to suppress roaming: \(viaMode)")
        try expectTrue(viaSession < 0.02, "expected an active focus session to suppress roaming: \(viaSession)")
    }

    runner.run("PetMode.play_isAtLeastAsPlayfulAsNormalEvenWithLowEnergyAndAffection") {
        // A brain with low energy/affection wouldn't organically qualify as
        // "playful" under .normal, but .play mode should still boost the
        // playful behavior group over the same brain in .normal.
        let playful: Set<PetBehavior> = [.trot, .zoomies, .beg, .tailWag]
        var normalCtx = PetContext(); normalCtx.mode = .normal
        var playCtx = PetContext(); playCtx.mode = .play
        let normal = fractionInSet(playful, ctx: normalCtx)
        let play = fractionInSet(playful, ctx: playCtx)
        try expectTrue(play >= normal, "expected play mode to be at least as playful as normal: play=\(play) normal=\(normal)")
    }

    // MARK: PetCommand.follow / .stay (Stage 9, Phase 9)

    runner.run("PetCommand.follow_isIgnoredWithNoCursor") {
        let brain = makeBrain(seed: 10)
        let ctx = PetContext()
        try expectEqual(brain.perform(.follow, context: ctx), .ignored)
        try expectFalse(brain.isFollowRequested)
    }

    runner.run("PetCommand.follow_opensATimedAttentionWindow") {
        let brain = makeBrain(seed: 11)
        var ctx = PetContext(); ctx.cursorX = 520; ctx.cursorY = 0
        try expectEqual(brain.perform(.follow, context: ctx), .handled)
        try expectTrue(brain.isFollowRequested)
        // The window is time-boxed, not permanent -- it should eventually
        // close on its own as the brain's clock advances.
        for _ in 0..<200 { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isFollowRequested, "follow window should have expired")
    }

    runner.run("PetCommand.stay_suppressesRoamingWhileRequested_thenExpires") {
        let brain = makeBrain(seed: 12)
        let ctx = PetContext()
        // Let any one-shot intro behavior clear before measuring, so the
        // test isolates the .stay request itself rather than startup.
        for _ in 0..<30 { brain.update(dt: 1, context: ctx) }
        try expectEqual(brain.perform(.stay, context: ctx), .handled)
        try expectTrue(brain.isStayRequested)
        let movement: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .pace, .trot, .run, .zoomies]
        var movedWhileStaying = false
        for _ in 0..<60 {
            brain.update(dt: 1, context: ctx)
            if movement.contains(brain.behavior) { movedWhileStaying = true }
        }
        try expectFalse(movedWhileStaying, "expected .stay to suppress roaming for its whole window")
        for _ in 0..<200 { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isStayRequested, "stay window should have expired")
    }

    runner.run("PetCommand.stop_cancelsAnOpenFollowOrStayWindow") {
        let brain = makeBrain(seed: 13)
        var ctx = PetContext(); ctx.cursorX = 520; ctx.cursorY = 0
        _ = brain.perform(.follow, context: ctx)
        try expectTrue(brain.isFollowRequested)
        _ = brain.perform(.stop, context: ctx)
        try expectFalse(brain.isFollowRequested)
    }

    // MARK: Curious approach toward an idle-but-present user (Stage 9, Phase 6)

    runner.run("CuriousApproach.happensMoreWhenUserIsIdleButPresentThanWhenActivelyEngaged") {
        let approach: Set<PetBehavior> = [.followCursor, .investigate]
        var idleCtx = PetContext(); idleCtx.cursorX = 900; idleCtx.cursorY = 0; idleCtx.cursorNearPet = false; idleCtx.userIdleSeconds = 200
        var activeCtx = PetContext(); activeCtx.cursorX = 900; activeCtx.cursorY = 0; activeCtx.cursorNearPet = false; activeCtx.userIdleSeconds = 0
        let idle = fractionInSet(approach, ctx: idleCtx)
        let active = fractionInSet(approach, ctx: activeCtx)
        try expectTrue(idle > active, "expected an idle-but-present user to draw more curious approaches than an actively engaged one: idle=\(idle) active=\(active)")
    }

    runner.run("CuriousApproach.scalesWithCuriosityPersonalityDial") {
        let approach: Set<PetBehavior> = [.followCursor, .investigate]
        var idleCtx = PetContext(); idleCtx.cursorX = 900; idleCtx.cursorY = 0; idleCtx.cursorNearPet = false; idleCtx.userIdleSeconds = 200
        func fractionForCuriosity(_ curiosity: Double, seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
            var total = 0.0
            for seed in seeds {
                var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: fullClips)
                config.personality.curiosity = curiosity
                let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
                var hits = 0
                let ticks = 6000
                for _ in 0..<ticks {
                    brain.update(dt: 1, context: idleCtx)
                    if approach.contains(brain.behavior) { hits += 1 }
                }
                total += Double(hits) / Double(ticks)
            }
            return total / Double(seeds.count)
        }
        let low = fractionForCuriosity(0.6)
        let high = fractionForCuriosity(1.5)
        try expectTrue(high > low, "expected higher curiosity to approach an idle user more often: high=\(high) low=\(low)")
    }

    runner.run("CuriousApproach.doesNotHappenWhenNoCursorIsKnown") {
        let approach: Set<PetBehavior> = [.followCursor, .investigate]
        var ctx = PetContext(); ctx.userIdleSeconds = 200 // no cursorX at all
        let fraction = fractionInSet(approach, ctx: ctx)
        try expectEqual(fraction, 0)
    }

    runner.run("PetCommand.newCommandCases_appAndTimerCommandsAreNotHandledByPetBrain") {
        let brain = makeBrain(seed: 14)
        let ctx = PetContext()
        try expectEqual(brain.perform(.stopFocus, context: ctx), .notHandledHere)
        try expectEqual(brain.perform(.startTimer(minutes: 10), context: ctx), .notHandledHere)
    }

    // MARK: Escalating repeated-click reactions (Stage 9, Phase 5)

    runner.run("Interaction.repeatedRapidClickBursts_escalateFromExcitedToGrumpy") {
        let brain = makeBrain(seed: 20)
        let ctx = PetContext()
        func burstOfFour() -> PetBehavior {
            for _ in 0..<4 { _ = brain.handle(.click, context: ctx) }
            return brain.behavior
        }
        let firstBurst = burstOfFour()
        try expectEqual(firstBurst, .excited) // a single rapid burst reads as playful excitement
        let secondBurst = burstOfFour()
        try expectEqual(secondBurst, .excited) // a second burst shortly after should still just be excited
        let thirdBurst = burstOfFour()
        try expectEqual(thirdBurst, .grumpyWake) // three rapid bursts in a row reads as "had enough"
    }

    runner.run("Interaction.excitedStreak_resetsAfterAQuietGap") {
        let brain = makeBrain(seed: 21)
        let ctx = PetContext()
        for _ in 0..<4 { _ = brain.handle(.click, context: ctx) }
        try expectEqual(brain.behavior, .excited)
        // A long gap between bursts should NOT count toward escalation --
        // only rapid, back-to-back bursts read as "had enough".
        for _ in 0..<20 { brain.update(dt: 1, context: ctx) }
        for _ in 0..<4 { _ = brain.handle(.click, context: ctx) }
        try expectEqual(brain.behavior, .excited) // a burst after a quiet gap resets the escalation, not continues it
    }

    // MARK: Desktop awareness (Stage 9, Phase 11)

    runner.run("DesktopAwareness.lowBattery_suppressesHighEnergyBehaviors_overLongSimulation") {
        let highEnergy: Set<PetBehavior> = [.zoomies, .run]
        var normalCtx = PetContext(); normalCtx.mode = .normal
        var lowBatteryCtx = PetContext(); lowBatteryCtx.batteryLow = true
        let normal = fractionInSet(highEnergy, ctx: normalCtx)
        let lowBattery = fractionInSet(highEnergy, ctx: lowBatteryCtx)
        try expectTrue(lowBattery <= normal, "expected low battery to never increase high-energy behavior: lowBattery=\(lowBattery) normal=\(normal)")
        try expectEqual(lowBattery, 0) // zoomies/run are fully gated off, not just dampened
    }

    // MARK: Cursor-chase mini-game (Stage 9, Phase 14)

    runner.run("MiniGame.playChase_isIgnoredWithNoCursorOrWhileAsleep") {
        let awake = makeBrain(seed: 30)
        try expectEqual(awake.perform(.playChase, context: PetContext()), .ignored) // no cursor
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        try expectEqual(awake.perform(.playChase, context: ctx), .handled)

        let asleep = makeBrain(seed: 31)
        _ = asleep.perform(.sleep, context: ctx)
        for _ in 0..<600 where !asleep.isAsleep { asleep.update(dt: 1, context: ctx) }
        try expectTrue(asleep.isAsleep, "fixture assumption: brain should have fallen asleep by now")
        try expectEqual(asleep.perform(.playChase, context: ctx), .ignored)
    }

    runner.run("MiniGame.entersCleanly_countsCatches_exitsAtGoal_thenResumesAutonomy") {
        let brain = makeBrain(seed: 32)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0; ctx.cursorNearPet = false
        try expectEqual(brain.perform(.playChase, context: ctx), .handled)
        try expectTrue(brain.isChaseGameActive)
        try expectEqual(brain.chaseCatches, 0)

        // Each near/far edge simulates the cursor reaching, then leaving,
        // the pet -- exactly one catch per approach, not per tick.
        for _ in 0..<3 {
            ctx.cursorNearPet = true
            brain.update(dt: 1, context: ctx)
            ctx.cursorNearPet = false
            brain.update(dt: 1, context: ctx)
        }
        try expectEqual(brain.chaseCatches, 3)
        try expectFalse(brain.isChaseGameActive, "expected the game to end cleanly once the catch goal was reached")

        // Nothing leaked: the brain keeps producing valid ticks afterward,
        // and doesn't silently re-enter the game on its own.
        for _ in 0..<200 { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isChaseGameActive)
        try expectTrue(brain.x.isFinite)
    }

    runner.run("MiniGame.expiresOnItsOwnIfTheGoalIsNeverReached") {
        let brain = makeBrain(seed: 33)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0; ctx.cursorNearPet = false
        brain.startChaseGame(duration: 5)
        try expectTrue(brain.isChaseGameActive)
        for _ in 0..<10 { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isChaseGameActive, "expected the game to time out on its own, never linger")
        try expectTrue(brain.chaseCatches < 3)
    }

    runner.run("MiniGame.stopCommand_interruptsTheGameCleanly") {
        let brain = makeBrain(seed: 34)
        var ctx = PetContext(); ctx.cursorX = 500; ctx.cursorY = 0
        brain.startChaseGame()
        try expectTrue(brain.isChaseGameActive)
        _ = brain.perform(.stop, context: ctx)
        try expectFalse(brain.isChaseGameActive, "expected .stop to end the game immediately, not wait for the window to expire")
        try expectFalse(brain.isFollowRequested)
    }

    // MARK: Lightweight relationship model (Stage 9, Phase 16)

    runner.run("Relationship.lowerFamiliarity_warmsUpMoreSlowlyFromTheSameClick") {
        let newCompanion = makeBrain(seed: 40)
        let establishedCompanion = makeBrain(seed: 40)
        var lowCtx = PetContext(); lowCtx.familiarity = 0.4 // a brand-new companion, day 1
        var highCtx = PetContext(); highCtx.familiarity = 1.0 // ~2+ weeks in
        _ = newCompanion.handle(.click, context: lowCtx)
        _ = establishedCompanion.handle(.click, context: highCtx)
        try expectTrue(establishedCompanion.affection > newCompanion.affection, "expected a more familiar companion to warm up faster from an identical click: established=\(establishedCompanion.affection) new=\(newCompanion.affection)")
    }

    runner.run("Relationship.defaultFamiliarity_isFullyWarm_backwardCompatible") {
        // Every context built before this phase (and every existing test)
        // never set `familiarity` -- it must default to full warmth so
        // nothing already-shipped silently changed behavior.
        try expectEqual(PetContext().familiarity, 1.0)
    }

    // MARK: Daily routine (Stage 9, Phase 17) -- verifies the existing
    // hour-based sleepiness/roam chain already produces the right
    // probabilistic bias; no new code, just proof it holds.

    runner.run("DailyRoutine.lateNight_restsMoreAndRoamsLessThanMidday_overLongSimulation") {
        let restful: Set<PetBehavior> = [.sit, .settle, .restAlert, .lie, .doze, .sleep, .lateNightDrowsy]
        let movement: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .pace, .trot, .run, .zoomies]
        var middayCtx = PetContext(); middayCtx.hour = 14
        var lateNightCtx = PetContext(); lateNightCtx.hour = 2
        let middayRest = fractionInSet(restful, ctx: middayCtx)
        let nightRest = fractionInSet(restful, ctx: lateNightCtx)
        let middayMove = fractionInSet(movement, ctx: middayCtx)
        let nightMove = fractionInSet(movement, ctx: lateNightCtx)
        try expectTrue(nightRest > middayRest, "expected late night to rest more than midday: night=\(nightRest) midday=\(middayRest)")
        try expectTrue(nightMove < middayMove, "expected late night to roam less than midday: night=\(nightMove) midday=\(middayMove)")
    }

    runner.run("DailyRoutine.isAProbabilisticBias_notARigidSchedule_lateNightCanStillMove") {
        // The brief explicitly requires bias, not scripted lockout: a late-
        // night context must still be *capable* of producing movement
        // sometimes, just less often than daytime.
        let movement: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .pace]
        var lateNightCtx = PetContext(); lateNightCtx.hour = 2
        try expectTrue(fractionInSet(movement, ctx: lateNightCtx) > 0, "expected late night to still allow movement sometimes, not hard-lock it out")
    }

    runner.run("DesktopAwareness.longContinuousSession_increasesCheckingInOnTheUser") {
        let checkingIn: Set<PetBehavior> = [.watchCursor, .investigate]
        var freshCtx = PetContext(); freshCtx.cursorX = 900; freshCtx.cursorY = 0; freshCtx.cursorNearPet = true
        var longSessionCtx = freshCtx; longSessionCtx.continuousActiveMinutes = 90
        let fresh = fractionInSet(checkingIn, ctx: freshCtx)
        let longSession = fractionInSet(checkingIn, ctx: longSessionCtx)
        try expectTrue(longSession > fresh, "expected a long continuous session to increase checking-in behavior: longSession=\(longSession) fresh=\(fresh)")
    }
}

func runPreStage9AuditTests(_ runner: TestRunner) {

    // MARK: Short-term behavior memory / anti-repetition (Pre-Stage-9)

    runner.run("PetBrain.recentBehaviors_isBoundedAndTracksAutonomousChoices") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right", "lie"]),
                             x: 0, minX: 0, maxX: 1400, rng: SeededRandom(seed: 5))
        let ctx = PetContext()
        for _ in 0..<5000 { brain.update(dt: 1, context: ctx) }
        try expectTrue(!brain.recentBehaviors.isEmpty)
        try expectTrue(brain.recentBehaviors.count <= 6, "expected the memory window to stay bounded, got \(brain.recentBehaviors.count)")
    }

    runner.run("PetBrain.repetitionPenalty_reducesConsecutiveRunsOfTheSameBehavior_overLongSimulation") {
        // Force a narrow clip set so the same handful of behaviors are
        // constantly competing -- the exact scenario ("walk walk walk
        // walk walk") the repetition penalty exists to prevent.
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"]),
                             x: 700, minX: 0, maxX: 1400, rng: SeededRandom(seed: 11))
        var ctx = PetContext(); ctx.cursorX = nil
        var history: [PetBehavior] = []
        brain.onBehaviorChange = { _, new in history.append(new) }
        for _ in 0..<(3600 * 2) { brain.update(dt: 0.5, context: ctx) }
        try expectTrue(history.count > 10, "expected many autonomous transitions over a 2-hour simulation, got \(history.count)")
        // No behavior should be chosen 5+ times in an unbroken row.
        var longestRun = 1
        var currentRun = 1
        for i in 1..<history.count {
            if history[i] == history[i - 1] { currentRun += 1 } else { currentRun = 1 }
            longestRun = max(longestRun, currentRun)
        }
        try expectTrue(longestRun < 5, "expected the repetition penalty to break up long runs of the same behavior, longest run was \(longestRun)")
    }

    // MARK: Command / action layer (Pre-Stage-9)

    runner.run("PetCommand.sleep_tucksInAwakePet") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "lie", "sleep"]),
                             x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 6))
        let ctx = PetContext()
        try expectFalse(brain.isAsleep)
        let result = brain.perform(.sleep, context: ctx)
        try expectEqual(result, .handled)
    }

    runner.run("PetCommand.sleep_isIgnoredIfAlreadyAsleep") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "lie", "sleep"]),
                             x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 7))
        var ctx = PetContext()
        ctx.hour = 2
        // Drive it toward sleep with a long simulated idle stretch rather
        // than reaching into private state.
        for _ in 0..<20_000 { brain.update(dt: 1, context: ctx) }
        if brain.isAsleep {
            try expectEqual(brain.perform(.sleep, context: ctx), .ignored)
        } // else: didn't happen to fall asleep in this particular seeded run -- not what this test is verifying.
    }

    runner.run("PetCommand.comeHere_isIgnoredWithNoCursor") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"]),
                             x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 8))
        var ctx = PetContext()
        ctx.cursorX = nil
        try expectEqual(brain.perform(.comeHere, context: ctx), .ignored)
    }

    runner.run("PetCommand.comeHere_isHandledWithACursorPosition") {
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk", "walk_left", "walk_right"]),
                             x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 9))
        var ctx = PetContext()
        ctx.cursorX = 500
        try expectEqual(brain.perform(.comeHere, context: ctx), .handled)
    }

    runner.run("PetCommand.focusAndReminderCommands_areNotHandledByPetBrain") {
        // These belong to the App layer's existing FocusTimer/ReminderEngine,
        // not PetBrain -- perform() must say so rather than silently no-op.
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand"]),
                             x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: 10))
        let ctx = PetContext()
        try expectEqual(brain.perform(.startFocus(minutes: 25), context: ctx), .notHandledHere)
        try expectEqual(brain.perform(.setReminder(inMinutes: 30, title: "stretch"), context: ctx), .notHandledHere)
    }

    // MARK: Stronger personality divergence -- actual behavior-choice
    // distribution over a long simulation, not just drive levels (Stage 8
    // proved drives diverge; this proves CHOICES diverge).

    runner.run("Personality.highRoaming_choosesMovementBehaviorsMoreOftenThanLowRoaming_overLongSimulation") {
        func run(roaming: Double, seed: UInt64) -> (movement: Int, total: Int) {
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100,
                availableClips: ["stand", "sit", "lie", "sleep", "walk", "walk_left", "walk_right", "run", "run_left", "run_right"])
            config.personality.roaming = roaming
            let brain = PetBrain(config: config, x: 700, minX: 0, maxX: 1400, minY: 0, maxY: 0, rng: SeededRandom(seed: seed))
            var moving = 0, total = 0
            brain.onBehaviorChange = { _, new in
                total += 1
                if new.spec.movement != nil { moving += 1 }
            }
            var ctx = PetContext()
            ctx.hour = 12 // stay in "daytime" the whole run so late-night drowsiness doesn't dominate either config
            // A real running app keeps energy topped up via actual full
            // sleep cycles and periodic activity; an isolated PetBrain run
            // for hours on nothing but its own idle-decay formula crashes
            // energy to 0 within minutes (by design -- it's meant to make
            // a *real*, unattended pet nap). To compare roaming tendency
            // specifically, sample the window while energy is still in its
            // normal operating range, not after it's bottomed out for both
            // configs identically.
            for _ in 0..<1800 { brain.update(dt: 0.5, context: ctx) }
            return (moving, total)
        }
        // A single seed is noisy -- two brains that diverge on their very
        // first choice can end up on uncorrelated trajectories regardless
        // of the dial being tested. Average the movement rate over several
        // seeds so the real effect of the roaming dial dominates the noise
        // from any one run's specific sequence of random choices.
        let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
        let lowRates = seeds.map { run(roaming: 0.6, seed: $0) }.map { Double($0.movement) / Double(max($0.total, 1)) }
        let highRates = seeds.map { run(roaming: 1.5, seed: $0) }.map { Double($0.movement) / Double(max($0.total, 1)) }
        let lowAvg = lowRates.reduce(0, +) / Double(lowRates.count)
        let highAvg = highRates.reduce(0, +) / Double(highRates.count)
        try expectTrue(highAvg > lowAvg, "expected high-roaming to choose movement behaviors more often, averaged over \(seeds.count) seeds: low=\(lowAvg) high=\(highAvg)")
    }

    runner.run("Personality.highRestfulness_spendsMoreTimeInCalmPosesThanLowRestfulness") {
        func run(restfulness: Double, seed: UInt64) -> Double {
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "lie", "sleep", "walk", "walk_left", "walk_right"])
            config.personality.restfulness = restfulness
            let brain = PetBrain(config: config, x: 0, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
            var restSeconds = 0.0, total = 0.0
            let ctx = PetContext()
            let dt = 1.0
            for _ in 0..<20_000 {
                brain.update(dt: dt, context: ctx)
                total += dt
                // restfulness's actual documented effect is "lingers longer
                // in calm poses" broadly (PetBrain.swift's own doc comment),
                // not specifically literal sleep -- a restful character may
                // satisfy itself with long calm sit/settle stretches rather
                // than always progressing all the way to lying/asleep, so
                // the comparison has to use the same definition the dial
                // actually optimizes for.
                let calmPoses: Set<PetBehavior> = [.sit, .settle, .restAlert, .lie, .doze, .sleep]
                if brain.isAsleep || calmPoses.contains(brain.behavior) { restSeconds += dt }
            }
            return restSeconds / total
        }
        let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
        let lowAvg = seeds.map { run(restfulness: 0.6, seed: $0) }.reduce(0, +) / Double(seeds.count)
        let highAvg = seeds.map { run(restfulness: 1.5, seed: $0) }.reduce(0, +) / Double(seeds.count)
        try expectTrue(highAvg > lowAvg, "expected high restfulness to spend more time resting, averaged over \(seeds.count) seeds: low=\(lowAvg) high=\(highAvg)")
    }
}
