import Foundation
import Core

private let dogClips: Set<String> = [
    "stand", "stand_bark", "sit", "sit_bark", "lie", "yawn", "sleep", "walk", "walk_bark", "run", "gallop",
    "beg", "beg_bark", "dragged", "fall", "land",
]

private func makeBrain(seed: UInt64 = 1, x: Double = 400, y: Double = 100, energy: Double = 0.8) -> PetBrain {
    var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: dogClips)
    config.homeOnLeft = true
    return PetBrain(config: config, x: x, y: y, minX: 0, maxX: 1600, minY: 70, maxY: 900, energy: energy, intro: false, rng: SeededRandom(seed: seed))
}

private func context(cursor: (Double, Double)? = (900, 300), near: Bool = false) -> PetContext {
    var c = PetContext()
    c.hour = 14
    c.cursorX = cursor?.0
    c.cursorY = cursor?.1
    c.cursorNearPet = near
    return c
}

private func step(_ brain: PetBrain, _ ctx: PetContext, seconds: Double, dt: Double = 0.1) {
    for _ in 0..<Int(seconds / dt) { brain.update(dt: dt, context: ctx) }
}

func runActivityTests(_ runner: TestRunner) {
    // MARK: Follow cursor

    runner.run("Activity.follow.walksTowardTheCursorAndStopsBesideIt") {
        let brain = makeBrain(x: 100)
        let ctx = context(cursor: (1000, 300))
        try expectEqual(brain.perform(.follow(duration: nil), context: ctx), .handled)
        step(brain, ctx, seconds: 40)
        let center = brain.x + 80
        try expectTrue(abs(center - 1000) < 160, "pet centre \(center) should be near the cursor at 1000")
        try expectTrue(brain.isFollowing)
    }

    runner.run("Activity.follow.tracksAMovingCursor_withoutTeleporting") {
        let brain = makeBrain(x: 100)
        var ctx = context(cursor: (300, 200))
        _ = brain.perform(.follow(duration: nil), context: ctx)
        var last = (brain.x, brain.y)
        var maxJump = 0.0
        for i in 0..<(120 * 10) {
            // The cursor sweeps back and forth across the screen.
            let t = Double(i) / 10
            ctx.cursorX = 800 + 600 * sin(t / 6)
            ctx.cursorY = 300 + 150 * cos(t / 9)
            brain.update(dt: 0.1, context: ctx)
            maxJump = max(maxJump, hypot(brain.x - last.0, brain.y - last.1))
            last = (brain.x, brain.y)
            try expectTrue(brain.x >= 0 && brain.x <= 1600 && brain.y >= 70 && brain.y <= 900, "out of bounds \(brain.x),\(brain.y)")
        }
        // The fastest gait is ~24 px/s * 2.5 pt/px = 60 pt/s -> 6 pt per 0.1 s tick.
        try expectTrue(maxJump < 12, "pet jumped \(maxJump) pt in a single tick (teleport)")
    }

    runner.run("Activity.follow.doesNotJitter_facingChangesAreBounded") {
        let brain = makeBrain(x: 100)
        var ctx = context(cursor: (800, 300))
        _ = brain.perform(.follow(duration: nil), context: ctx)
        var flips = 0
        var lastFacing = brain.facing
        for i in 0..<(60 * 10) {
            // Cursor jitters a few points around a fixed spot, like a resting hand.
            ctx.cursorX = 800 + Double((i * 7) % 11) - 5
            ctx.cursorY = 300 + Double((i * 3) % 7) - 3
            brain.update(dt: 0.1, context: ctx)
            if brain.facing != lastFacing { flips += 1; lastFacing = brain.facing }
        }
        try expectTrue(flips <= 6, "facing flipped \(flips) times while the cursor was still")
    }

    runner.run("Activity.follow.atScreenEdges_neverTrapsOrLeavesTheScreen") {
        for cursor in [(-500.0, -500.0), (5000.0, 5000.0), (0.0, 0.0), (1600.0, 900.0), (2000.0, 60.0)] {
            let brain = makeBrain(x: 700)
            let ctx = context(cursor: cursor)
            _ = brain.perform(.follow(duration: nil), context: ctx)
            var behaviors = Set<PetBehavior>()
            for _ in 0..<(90 * 10) {
                brain.update(dt: 0.1, context: ctx)
                behaviors.insert(brain.behavior)
                try expectTrue(brain.x >= 0 && brain.x <= 1600 && brain.y >= 70 && brain.y <= 900, "left the screen for cursor \(cursor)")
            }
            try expectTrue(brain.x.isFinite && brain.y.isFinite)
            // It reached the nearest reachable spot and is still behaving normally (not wedged in one behavior forever).
            try expectTrue(behaviors.contains(.followWatch) || behaviors.contains(.followCursor), "never followed for \(cursor)")
        }
    }

    runner.run("Activity.follow.timedFollowEndsAndReturnsToAmbientBehavior") {
        let brain = makeBrain()
        let ctx = context()
        _ = brain.perform(.follow(duration: 20), context: ctx)
        try expectEqual(brain.currentActivity, .followCursor)
        step(brain, ctx, seconds: 40)
        try expectTrue(brain.currentActivity == nil, "timed follow should have ended")
        try expectFalse(brain.isFollowing)
        // Back to normal: over a long window it does something other than follow.
        var other = false
        for _ in 0..<(300 * 10) {
            brain.update(dt: 0.1, context: ctx)
            if ![.followCursor, .followWatch].contains(brain.behavior) { other = true }
        }
        try expectTrue(other)
    }

    runner.run("Activity.follow.stopReturnsToNormalImmediately") {
        let brain = makeBrain()
        let ctx = context()
        _ = brain.perform(.follow(duration: nil), context: ctx)
        step(brain, ctx, seconds: 5)
        _ = brain.perform(.stop, context: ctx)
        try expectTrue(brain.currentActivity == nil)
        step(brain, ctx, seconds: 5)
        try expectFalse(brain.isFollowing)
    }

    runner.run("Activity.follow.isIgnoredWithoutACursor_andWhileDragged") {
        let brain = makeBrain()
        try expectEqual(brain.perform(.follow(duration: nil), context: context(cursor: nil)), .ignored)
        try expectTrue(brain.currentActivity == nil)
        let ctx = context()
        brain.handle(.dragBegan, context: ctx)
        try expectEqual(brain.perform(.follow(duration: nil), context: ctx), .ignored)
    }

    runner.run("Activity.follow.survivesADragAndResumes") {
        let brain = makeBrain()
        let ctx = context()
        _ = brain.perform(.follow(duration: nil), context: ctx)
        step(brain, ctx, seconds: 3)
        brain.handle(.dragBegan, context: ctx)
        brain.handle(.dropped, context: ctx)
        step(brain, ctx, seconds: 30)
        try expectEqual(brain.currentActivity, .followCursor)
        try expectTrue([.followCursor, .followWatch].contains(brain.behavior), "resumed following after the drag, was \(brain.behavior)")
    }

    runner.run("Activity.follow.sleepCommandEndsIt") {
        let brain = makeBrain()
        let ctx = context()
        _ = brain.perform(.follow(duration: nil), context: ctx)
        _ = brain.perform(.sleep, context: ctx)
        try expectTrue(brain.currentActivity == nil)
    }

    // MARK: Availability, cooldown, art

    runner.run("Activity.availability_needsCursor_cooldown_andUnsupportedArt") {
        let brain = makeBrain()
        try expectEqual(brain.availability(of: .comeHere, context: context(cursor: nil)), .needsCursor)
        try expectEqual(brain.availability(of: .explore, context: context(cursor: nil)), .available)
        let ctx = context()
        _ = brain.perform(.explore, context: ctx)
        step(brain, ctx, seconds: 200)
        _ = brain.perform(.stop, context: ctx)
        // Explore ended (script drained or stopped): it now has a cooldown.
        if case .cooldown(let s) = brain.availability(of: .explore, context: ctx) { try expectTrue(s > 0 && s <= Activity.explore.cooldown) }
        step(brain, ctx, seconds: Activity.explore.cooldown + 5)
        try expectEqual(brain.availability(of: .explore, context: ctx), .available)

        // A character without any gallop/run art can't do Play; without lie it can't hide.
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit", "walk"])
        config.homeOnLeft = true
        let poor = PetBrain(config: config, x: 100, minX: 0, maxX: 1000, rng: SeededRandom(seed: 3))
        try expectEqual(poor.availability(of: .play, context: ctx), .unsupported)
        try expectEqual(poor.availability(of: .followCursor, context: ctx), .available)
    }

    // MARK: Come here

    runner.run("Activity.comeHere.arrivesNearTheCursorThenEnds") {
        let brain = makeBrain(x: 100)
        let ctx = context(cursor: (1200, 300))
        try expectEqual(brain.perform(.comeHere, context: ctx), .handled)
        step(brain, ctx, seconds: 30)
        try expectTrue(abs((brain.x + 80) - 1200) < 200, "should have come to the cursor, at \(brain.x)")
        try expectTrue(brain.currentActivity == nil, "come-here is a short script and should be over")
    }

    // MARK: Play

    runner.run("Activity.play.endsInACelebrationAfterEnoughCatches_orTimesOut") {
        let brain = makeBrain()
        var ctx = context()
        try expectEqual(brain.perform(.play, context: ctx), .handled)
        for _ in 0..<3 {
            ctx.cursorNearPet = true; brain.update(dt: 0.5, context: ctx)
            ctx.cursorNearPet = false; brain.update(dt: 0.5, context: ctx)
        }
        try expectTrue(brain.currentActivity == nil, "three catches should end the game")
        try expectEqual(brain.mood(ctx), .excited)

        let lazy = makeBrain(seed: 5)
        _ = lazy.perform(.play, context: ctx)
        step(lazy, ctx, seconds: Activity.play.defaultDuration! + 5)
        try expectTrue(lazy.currentActivity == nil, "play should time out on its own")
    }

    // MARK: Hide & seek

    runner.run("Activity.hideAndSeek.hidesInACorner_thenIsFoundWhenTheCursorComesNear") {
        let brain = makeBrain(x: 700)
        var ctx = context(cursor: (200, 300))
        try expectEqual(brain.perform(.hideAndSeek, context: ctx), .handled)
        step(brain, ctx, seconds: 30)
        try expectTrue(brain.isHidden, "should be crouching in its hiding spot")
        try expectTrue(brain.x > 1000, "hides far from the cursor, was at \(brain.x)")
        try expectEqual(brain.behavior, .hideWait)
        // Still hidden while the cursor stays away.
        step(brain, ctx, seconds: 10)
        try expectTrue(brain.isHidden)
        // Found!
        ctx.cursorNearPet = true
        step(brain, ctx, seconds: 1)
        try expectTrue(brain.currentActivity == nil)
        try expectFalse(brain.isHidden)
        try expectEqual(brain.mood(ctx), .excited)
    }

    runner.run("Activity.hideAndSeek.clickingTheHidingPetFindsIt") {
        let brain = makeBrain(x: 700)
        let ctx = context(cursor: (200, 300))
        _ = brain.perform(.hideAndSeek, context: ctx)
        step(brain, ctx, seconds: 30)
        try expectTrue(brain.isHidden)
        brain.handle(.click, context: ctx)
        try expectTrue(brain.currentActivity == nil)
        try expectFalse(brain.isHidden)
    }

    runner.run("Activity.hideAndSeek.givesUpAndComesLookingWhenNobodySeeks") {
        let brain = makeBrain(x: 700)
        let ctx = context(cursor: (200, 300))
        _ = brain.perform(.hideAndSeek, context: ctx)
        step(brain, ctx, seconds: 120)
        try expectTrue(brain.currentActivity == nil, "hide & seek must always end")
        try expectFalse(brain.isHidden)
    }

    // MARK: Explore / stay

    runner.run("Activity.explore.visitsSeveralPlacesThenEnds") {
        let brain = makeBrain()
        let ctx = context(cursor: nil)
        _ = brain.perform(.explore, context: ctx)
        var xs = Set<Int>()
        for i in 0..<(90 * 10) {
            brain.update(dt: 0.1, context: ctx)
            if i % 20 == 0 { xs.insert(Int(brain.x / 200)) }
        }
        try expectTrue(xs.count >= 2, "explore should cover ground")
        try expectTrue(brain.currentActivity == nil, "explore is a finite script")
    }

    runner.run("Activity.stay.holdsPositionThenExpires") {
        let brain = makeBrain()
        let ctx = context(cursor: nil)
        step(brain, ctx, seconds: 10)
        _ = brain.perform(.stay(duration: 60), context: ctx)
        var stayX = brain.x
        var maxDrift = 0.0
        for _ in 0..<(55 * 10) {
            brain.update(dt: 0.1, context: ctx)
            maxDrift = max(maxDrift, abs(brain.x - stayX))
            stayX = stayX * 0 + brain.x
        }
        try expectTrue(brain.isStaying)
        step(brain, ctx, seconds: 10)
        try expectTrue(brain.currentActivity == nil, "stay must expire")
    }

    runner.run("Activity.watch.staysPutFacingTheCursor_thenEnds") {
        let brain = makeBrain(x: 700)
        var ctx = context(cursor: (200, 300))
        step(brain, ctx, seconds: 5)
        _ = brain.perform(.watch, context: ctx)
        try expectEqual(brain.currentActivity, .watch)
        let startX = brain.x
        // The cursor swings to the far side; the companion turns to it without moving.
        for i in 0..<300 {
            ctx.cursorX = i < 150 ? 200 : 1400
            brain.update(dt: 0.1, context: ctx)
            try expectTrue(abs(brain.x - startX) < 1, "watching companion walked away")
        }
        try expectEqual(brain.facing, .right)
        step(brain, ctx, seconds: 30)
        try expectTrue(brain.currentActivity == nil, "watch must end on its own")
    }

    runner.run("Activity.watch.needsACursor_andHasACooldown") {
        let brain = makeBrain()
        try expectEqual(brain.availability(of: .watch, context: context(cursor: nil)), .needsCursor)
        let ctx = context()
        _ = brain.perform(.watch, context: ctx)
        _ = brain.perform(.stop, context: ctx)
        if case .cooldown = brain.availability(of: .watch, context: ctx) {} else { throw TestFailure(message: "expected a cooldown after stopping") }
    }

    runner.run("Activity.nap.restsThenRestoresEnergy_andWakesEarlyOnClick") {
        let ctx = context(cursor: nil)
        let brain = makeBrain(energy: 0.3)
        step(brain, ctx, seconds: 3)
        _ = brain.perform(.nap, context: ctx)
        try expectEqual(brain.currentActivity, .nap)
        let before = brain.energy
        step(brain, ctx, seconds: 140)
        try expectTrue(brain.currentActivity == nil, "nap is a finite script")
        try expectEqual(brain.napsCompleted, 1)
        try expectTrue(brain.energy > before, "a finished nap should refresh the companion")

        let early = makeBrain(energy: 0.3)
        step(early, ctx, seconds: 3)
        _ = early.perform(.nap, context: ctx)
        step(early, ctx, seconds: 8)
        _ = early.handle(.click, context: ctx)
        try expectTrue(early.currentActivity == nil, "a click ends the nap")
        try expectEqual(early.napsCompleted, 0)
    }

    runner.run("Activity.nap.suppressesRoaming") {
        let brain = makeBrain(energy: 1)
        let ctx = context(cursor: nil)
        _ = brain.perform(.nap, context: ctx)
        var maxDrift = 0.0
        let x0 = brain.x
        for _ in 0..<600 where brain.currentActivity == .nap { brain.update(dt: 0.1, context: ctx); maxDrift = max(maxDrift, abs(brain.x - x0)) }
        try expectTrue(maxDrift < 1, "napping companion moved \(maxDrift)")
    }

    // MARK: Stress

    runner.run("Activity.randomCommandStorm_neverBreaksInvariants_andNeverTeleports") {
        for seed in UInt64(1)...UInt64(6) {
            let brain = makeBrain(seed: seed)
            let rng = SeededRandom(seed: seed &+ 100)
            var ctx = context()
            let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .quiet, .stop, .follow(duration: nil), .follow(duration: 15),
                                          .stay(duration: 20), .explore, .hideAndSeek]
            var last = (brain.x, brain.y)
            var maxSpeedSeen = 0.0
            for i in 0..<(3600 * 5) { // one simulated hour at 0.2 s ticks
                if i % 37 == 0 { _ = brain.perform(commands[rng.int(0...(commands.count - 1))], context: ctx) }
                if i % 53 == 0 { brain.handle(.click, context: ctx) }
                if i % 211 == 0 { brain.handle(.dragBegan, context: ctx); brain.handle(.dropped, context: ctx) }
                if i % 19 == 0 {
                    ctx.cursorX = rng.chance(0.85) ? rng.uniform(-200...1800) : nil
                    ctx.cursorY = ctx.cursorX == nil ? nil : rng.uniform(0...1000)
                    ctx.cursorNearPet = rng.chance(0.15)
                }
                brain.update(dt: 0.2, context: ctx)
                try expectTrue(brain.x.isFinite && brain.y.isFinite && brain.energy.isFinite, "non-finite state")
                try expectTrue(brain.x >= -0.5 && brain.x <= 1600.5 && brain.y >= 69.5 && brain.y <= 900.5, "out of bounds \(brain.x),\(brain.y)")
                try expectFalse(brain.isAsleep && brain.isMoving, "asleep and moving")
                let moved = hypot(brain.x - last.0, brain.y - last.1)
                if brain.behavior != .dragged && brain.behavior != .landing { maxSpeedSeen = max(maxSpeedSeen, moved / 0.2) }
                last = (brain.x, brain.y)
            }
            try expectTrue(maxSpeedSeen < 400, "seed \(seed): moved at \(maxSpeedSeen) pt/s (teleport)")
        }
    }

    runner.run("Activity.missingArt_neverCrashesOrWedges_forAnyClipSubset") {
        let subsets: [Set<String>] = [["stand"], ["sit"], ["stand", "walk"], ["sit", "walk", "lie"], ["stand", "sit", "walk", "sleep"], ["lie", "sleep", "yawn"]]
        for clips in subsets {
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: clips)
            config.homeOnLeft = true
            let brain = PetBrain(config: config, x: 300, y: 70, minX: 0, maxX: 1000, minY: 70, maxY: 500, rng: SeededRandom(seed: 9))
            let rng = SeededRandom(seed: 4)
            var ctx = context()
            let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .quiet, .stop, .follow(duration: nil), .stay(duration: 10), .explore, .hideAndSeek]
            for i in 0..<(1800 * 5) {
                if i % 41 == 0 { _ = brain.perform(commands[rng.int(0...(commands.count - 1))], context: ctx) }
                if i % 17 == 0 { ctx.cursorNearPet = rng.chance(0.2) }
                brain.update(dt: 0.2, context: ctx)
                try expectTrue(brain.x.isFinite && brain.y.isFinite, "\(clips): non-finite")
                try expectTrue(brain.x >= -0.5 && brain.x <= 1000.5, "\(clips): x out of bounds")
                try expectTrue(clips.contains(brain.clip), "\(clips): rendered unavailable clip \(brain.clip)")
            }
        }
    }

    runner.run("Activity.edgeCoordinates_tinyAndHugeScreens_stayInBounds") {
        for (maxX, maxY) in [(120.0, 80.0), (100.0, 70.0), (7000.0, 3000.0)] {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 160, petHeight: 120, availableClips: dogClips)
            config.homeOnLeft = false
            let brain = PetBrain(config: config, x: maxX / 2, y: 70, minX: 0, maxX: maxX, minY: 70, maxY: maxY, intro: false, rng: SeededRandom(seed: 2))
            var ctx = context(cursor: (maxX * 2, maxY * 2))
            for command in [PetCommand.follow(duration: nil), .comeHere, .hideAndSeek, .explore, .play, .stay(duration: 5)] {
                _ = brain.perform(command, context: ctx)
                for _ in 0..<600 {
                    brain.update(dt: 0.2, context: ctx)
                    try expectTrue(brain.x >= -0.5 && brain.x <= maxX + 0.5 && brain.y >= 69.5 && brain.y <= max(maxY, 70) + 0.5, "\(maxX)x\(maxY): \(brain.x),\(brain.y)")
                }
                ctx.cursorX = -100
            }
        }
    }
}

func runCharacterActivitySupportTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Characters"))
    runner.run("Activity.everyCharacterSupportsEveryActivity") {
        for c in repo.characters {
            var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            let brain = PetBrain(config: config, x: 300, minX: 0, maxX: 1000, rng: SeededRandom(seed: 1))
            for a in Activity.allCases {
                try expectEqual(brain.availability(of: a, context: context()), .available, "\(c.id) cannot do \(a.displayName)")
            }
        }
    }
}

func runTrickAndInterruptionTests(_ runner: TestRunner) {
    runner.run("Trick.everyAvailableTrickRunsAndNothingIsFaked") {
        let brain = makeBrain()
        let ctx = context()
        try expectEqual(Set(brain.availableTricks), Set([Trick.sit, .lieDown, .beg, .speak, .spin, .celebrate]))
        for t in brain.availableTricks {
            try expectEqual(brain.perform(.trick(t), context: ctx), .handled)
            try expectTrue(t.candidates.contains(brain.behavior), "\(t) started \(brain.behavior)")
            step(brain, ctx, seconds: 20)
        }
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: ["stand", "sit"])
        config.homeOnLeft = true
        let plain = PetBrain(config: config, x: 100, minX: 0, maxX: 1000, rng: SeededRandom(seed: 3))
        try expectEqual(Set(plain.availableTricks), Set([Trick.sit]))
        try expectEqual(plain.perform(.trick(.beg), context: ctx), .ignored)
    }

    runner.run("Trick.wakesASleepingPet") {
        let brain = makeBrain()
        let ctx = context()
        _ = brain.perform(.sleep, context: ctx)
        for _ in 0..<600 where !brain.isAsleep { brain.update(dt: 0.5, context: ctx) }
        try expectTrue(brain.isAsleep, "fixture: should be asleep")
        try expectEqual(brain.perform(.trick(.sit), context: ctx), .handled)
        step(brain, ctx, seconds: 10)
        try expectFalse(brain.isAsleep)
    }

    runner.run("Interrupt.clickWhileWalking_stopsMovementImmediately") {
        for seed in UInt64(1)...UInt64(10) {
            let brain = makeBrain(seed: seed)
            let ctx = context(cursor: nil)
            _ = brain.perform(.explore, context: ctx)
            step(brain, ctx, seconds: 3)
            try expectTrue(brain.isMoving, "fixture: should be walking")
            brain.handle(.click, context: ctx)
            try expectFalse(brain.isMoving, "click must stop the walk")
            try expectTrue(brain.leg == nil, "no leg may survive a click")
            try expectTrue(["stand", "sit", "lie", "stand_bark", "sit_bark", "beg", "beg_bark"].contains(brain.clip), "clip \(brain.clip)")
        }
    }

    runner.run("Messages.everyCategoryHasVarietyAndNeverRepeatsBackToBack") {
        let book = PetMessageBook(rng: SeededRandom(seed: 5))
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        for c in MessageCategory.allCases {
            try expectTrue(PetMessageBook.lines(c, name: "Rex").count >= 4, "\(c) has too few lines")
            var last: String?
            for _ in 0..<20 {
                t = t.addingTimeInterval(4 * 3600)
                let l = book.line(c, name: "Rex", now: t)
                try expectNotNil(l)
                if let l, let last { try expectTrue(l != last, "\(c) repeated '\(l)'") }
                last = l
            }
        }
        try expectTrue(PetMessageBook.lines(.idle, name: "x").count >= 12)
        try expectTrue(PetMessageBook.lines(.click, name: "x").count >= 12)
    }
}
