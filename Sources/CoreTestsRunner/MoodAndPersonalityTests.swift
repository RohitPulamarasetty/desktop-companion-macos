import Foundation
import Core

private let clips: Set<String> = [
    "stand", "stand_bark", "sit", "sit_bark", "lie", "yawn", "sleep", "walk", "walk_bark", "run", "gallop",
    "beg", "beg_bark", "dragged", "fall", "land",
]

private func makeBrain(seed: UInt64, personality: Personality = Personality(), energy: Double = 0.8) -> PetBrain {
    var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: clips)
    config.personality = personality
    return PetBrain(config: config, x: 500, y: 100, minX: 0, maxX: 1600, minY: 70, maxY: 900, energy: energy, intro: false, rng: SeededRandom(seed: seed))
}

private func fraction(_ set: Set<PetBehavior>, seeds: ClosedRange<UInt64> = 1...12, ticks: Int = 4000,
                      personality: Personality = Personality(), prepare: (PetBrain, PetContext) -> Void = { _, _ in },
                      context: PetContext = PetContext()) -> Double {
    var total = 0.0
    for seed in seeds {
        let brain = makeBrain(seed: seed, personality: personality)
        prepare(brain, context)
        var hits = 0
        for _ in 0..<ticks {
            brain.update(dt: 1, context: context)
            if set.contains(brain.behavior) { hits += 1 }
        }
        total += Double(hits) / Double(ticks)
    }
    return total / Double(seeds.count)
}

private func annoy(_ brain: PetBrain, _ ctx: PetContext) {
    // Three rapid bursts of clicks in a row: "had enough".
    for _ in 0..<3 { for _ in 0..<4 { brain.handle(.click, context: ctx) } }
}

func runMoodAndPersonalityTests(_ runner: TestRunner) {
    // MARK: Mood

    runner.run("Mood.repeatedClickBursts_makeThePetAnnoyed_thenItFadesByItself") {
        let brain = makeBrain(seed: 3)
        let ctx = PetContext()
        try expectFalse(brain.isAnnoyed)
        annoy(brain, ctx)
        try expectTrue(brain.isAnnoyed)
        try expectEqual(brain.mood(ctx), .annoyed)
        for _ in 0..<Int(PetBrain.annoyedDuration + 5) { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isAnnoyed, "annoyance must decay")
        try expectTrue(brain.mood(ctx) != .annoyed)
    }

    runner.run("Mood.aGentlePat_soothesAnAnnoyedPetSooner") {
        let brain = makeBrain(seed: 3)
        let ctx = PetContext()
        annoy(brain, ctx)
        brain.handle(.doubleClick, context: ctx)
        for _ in 0..<20 { brain.update(dt: 1, context: ctx) }
        try expectFalse(brain.isAnnoyed, "a pat should shorten the sulk to ~15 s")
    }

    runner.run("Mood.annoyedPet_seeksTheCursorLess_andKeepsItsDistance") {
        var ctx = PetContext(); ctx.cursorX = 800; ctx.cursorY = 100; ctx.cursorNearPet = true
        let seeking: Set<PetBehavior> = [.followCursor, .investigate, .watchCursor, .tailWag, .beg, .play]
        let calm = fraction(seeking, ticks: 100, context: ctx)
        let sulking = fraction(seeking, ticks: 100, prepare: { b, c in annoy(b, c) }, context: ctx) // only the sulking window
        try expectTrue(sulking < calm * 0.6, "annoyed=\(sulking) calm=\(calm)")
    }

    runner.run("Mood.everyMoodIsReachable_andNoneGetsStuck") {
        var seen = Set<PetMood>()
        for seed in UInt64(1)...UInt64(8) {
            let brain = makeBrain(seed: seed, energy: 0.9)
            var ctx = PetContext(); ctx.cursorX = 700; ctx.cursorY = 100
            let rng = SeededRandom(seed: seed &+ 50)
            var lastClick = -Double.infinity
            for i in 0..<(4 * 3600) {
                if i % 400 == 0, rng.chance(0.2) { annoy(brain, ctx); lastClick = brain.clock }
                if i % 90 == 0, rng.chance(0.4) { brain.handle(.click, context: ctx); lastClick = brain.clock }
                if i % 700 == 0, rng.chance(0.3) { for _ in 0..<4 { brain.handle(.click, context: ctx) }; lastClick = brain.clock } // one playful burst
                brain.update(dt: 1, context: ctx)
                let m = brain.mood(ctx)
                seen.insert(m)
                // However it got there, annoyance never outlives the last poke by more than its duration.
                if m == .annoyed { try expectTrue(brain.clock - lastClick <= PetBrain.annoyedDuration + 1, "annoyed \(brain.clock - lastClick)s after the last click") }
            }
        }
        for mood in [PetMood.sleepy, .annoyed, .excited] { try expectTrue(seen.contains(mood), "never reached \(mood)") }
        try expectTrue(seen.count >= 5, "only reached \(seen)")
    }

    runner.run("Mood.playfulActivitiesRaiseAffection_butOnlyBoundedly") {
        let brain = makeBrain(seed: 4)
        var ctx = PetContext(); ctx.cursorX = 800; ctx.cursorY = 100
        let before = brain.affection
        for _ in 0..<50 {
            _ = brain.perform(.play, context: ctx)
            for _ in 0..<3 {
                ctx.cursorNearPet = true; brain.update(dt: 0.5, context: ctx)
                ctx.cursorNearPet = false; brain.update(dt: 0.5, context: ctx)
            }
            for _ in 0..<40 { brain.update(dt: 1, context: ctx) }
        }
        try expectTrue(brain.affection >= before && brain.affection <= 1)
    }

    // MARK: Personality has causal effects

    runner.run("Personality.playfulness_drivesPlayfulBehavior") {
        var low = Personality(); low.playfulness = 0.6
        var high = Personality(); high.playfulness = 1.5
        let playful: Set<PetBehavior> = [.zoomies, .spin, .trot, .beg, .tailWag, .play]
        let l = fraction(playful, personality: low), h = fraction(playful, personality: high)
        try expectTrue(h > l * 1.15, "high=\(h) low=\(l)")
    }

    runner.run("Personality.energy_lowActivityMeansMoreRestingAndLessRoaming") {
        var calm = PetContext(); calm.activityMultiplier = 0.6
        var lively = PetContext(); lively.activityMultiplier = 1.6
        let roaming: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .trot, .run]
        let resting: Set<PetBehavior> = [.sit, .lie, .doze, .sleep, .settle]
        let calmRoam = fraction(roaming, context: calm), livelyRoam = fraction(roaming, context: lively)
        let calmRest = fraction(resting, context: calm), livelyRest = fraction(resting, context: lively)
        try expectTrue(livelyRoam > calmRoam, "roaming lively=\(livelyRoam) calm=\(calmRoam)")
        try expectTrue(calmRest > livelyRest, "resting calm=\(calmRest) lively=\(livelyRest)")
    }

    runner.run("Personality.curiosity_drivesInvestigation") {
        var low = Personality(); low.curiosity = 0.6
        var high = Personality(); high.curiosity = 1.5
        let looking: Set<PetBehavior> = [.explore, .investigate, .patrol, .sniff]
        let l = fraction(looking, personality: low), h = fraction(looking, personality: high)
        try expectTrue(h > l, "high=\(h) low=\(l)")
    }

    runner.run("Personality.affection_warmsUpFasterAndSettlesHigher") {
        func settled(_ affection: Double) -> Double {
            var p = Personality(); p.affection = affection
            let brain = makeBrain(seed: 2, personality: p)
            var total = 0.0
            let ctx = PetContext()
            for _ in 0..<5 { brain.handle(.doubleClick, context: ctx); brain.update(dt: 30, context: ctx); total += brain.affection }
            return total
        }
        try expectTrue(settled(1.5) > settled(0.6))
    }

    runner.run("Personality.restfulness_lowerMeansLessSleeping") {
        var sleepy = Personality(); sleepy.restfulness = 1.5
        var restless = Personality(); restless.restfulness = 0.6
        let asleep: Set<PetBehavior> = [.sleep, .doze, .lie, .settle]
        let a = fraction(asleep, personality: sleepy), b = fraction(asleep, personality: restless)
        try expectTrue(a > b, "sleepy=\(a) restless=\(b)")
    }

    runner.run("Personality.reactivity_moreReactiveBarksMoreOnClicks") {
        func barks(_ reactivity: Double) -> Int {
            var p = Personality(); p.reactivity = reactivity
            var total = 0
            for seed in UInt64(1)...UInt64(20) {
                let brain = makeBrain(seed: seed, personality: p)
                let ctx = PetContext()
                for _ in 0..<20 { brain.handle(.click, context: ctx); brain.update(dt: 12, context: ctx) }
                total += brain.stats.barks
            }
            return total
        }
        try expectTrue(barks(1.5) > barks(0.6))
    }
}
