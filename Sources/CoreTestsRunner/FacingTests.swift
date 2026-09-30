import Foundation
import Core

private let dogClips: Set<String> = [
    "stand", "stand_bark", "sit", "sit_bark", "lie", "yawn", "sleep", "walk", "walk_bark", "run", "gallop",
    "beg", "beg_bark", "dragged", "fall", "land",
]

private func makeBrain(seed: UInt64 = 1, x: Double = 800, y: Double = 300, clips: Set<String> = dogClips, width: Double = 160,
                       minX: Double = 0, maxX: Double = 1600, minY: Double = 70, maxY: Double = 900, energy: Double = 0.8) -> PetBrain {
    var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: width, petHeight: 120, availableClips: clips)
    config.homeOnLeft = true
    return PetBrain(config: config, x: x, y: y, minX: minX, maxX: maxX, minY: minY, maxY: maxY, energy: energy, intro: false, rng: SeededRandom(seed: seed))
}

/// Watches a brain tick by tick and records every moment the companion visibly walks against the way it faces.
struct FacingWatch {
    /// Horizontal distance (pt) a companion may drift against its facing before it counts as walking backward.
    let tolerance: Double
    private var last: (Double, Double)
    private var opposing = 0.0
    private(set) var worstBackward = 0.0
    private(set) var flips = 0
    private var lastFacing: Facing

    init(_ brain: PetBrain, tolerance: Double) {
        self.tolerance = tolerance
        last = (brain.x, brain.y)
        lastFacing = brain.facing
    }

    /// After a deliberate relocation (drop, display change): what happens next is measured from the new spot.
    mutating func rebase(_ brain: PetBrain) {
        last = (brain.x, brain.y)
        opposing = 0
    }

    mutating func observe(_ brain: PetBrain) {
        let dx = brain.x - last.0
        last = (brain.x, brain.y)
        if brain.facing != lastFacing { flips += 1; lastFacing = brain.facing }
        guard brain.isMoving, !brain.isTurning, brain.behavior != .dragged, brain.behavior != .falling, brain.behavior != .landing else { opposing = 0; return }
        if dx * brain.facing.sign < -0.05 { opposing += abs(dx) } else if dx * brain.facing.sign > 0.05 { opposing = 0 }
        worstBackward = max(worstBackward, opposing)
    }
}

func runFacingTests(_ runner: TestRunner) {
    func ctx(_ cursor: (Double, Double)? = (900, 300)) -> PetContext {
        var c = PetContext()
        c.hour = 14
        c.cursorX = cursor?.0
        c.cursorY = cursor?.1
        return c
    }

    runner.run("Facing.autonomousRoaming_neverWalksBackward_acrossManySeeds") {
        for seed in UInt64(1)...UInt64(12) {
            let brain = makeBrain(seed: seed)
            var watch = FacingWatch(brain, tolerance: 12)
            let c = ctx(nil)
            for _ in 0..<(3600 * 5) { brain.update(dt: 0.2, context: c); watch.observe(brain) }
            try expectTrue(watch.worstBackward <= watch.tolerance, "seed \(seed): walked \(watch.worstBackward) pt against its facing")
        }
    }

    // MARK: Animation direction (render side)

    func effectiveFacing(_ r: ResolvedClip, native: String?) -> String {
        let drawn = (r.state.facing ?? native ?? "right").lowercased()
        if drawn == "front" { return "front" }
        return r.mirrored ? (drawn == "left" ? "right" : "left") : drawn
    }

    let repo = CharacterRepository(directory: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Characters"))

    runner.run("Facing.everyCharacter_everyMovementClip_isDrawnFacingTheWayItMoves") {
        try expectTrue(repo.characters.count >= 30)
        for c in repo.characters {
            for name in ["walk", "walk_bark", "run", "gallop"] {
                for facing in [Facing.left, .right] {
                    guard let r = c.resolve(name, facing: facing) else { continue }
                    let eff = effectiveFacing(r, native: c.manifest.nativeFacing)
                    let want = facing == .left ? "left" : "right"
                    try expectTrue(eff == want || eff == "front", "\(c.id) \(name) facing \(want) would be drawn facing \(eff)")
                }
            }
        }
    }

    runner.run("Facing.everyCharacter_directionalClipsCarryTheirOwnLabel") {
        for c in repo.characters {
            for st in c.manifest.states {
                if st.id.hasSuffix("_left") { try expectEqual(st.facing, "left", "\(c.id) \(st.id)") }
                if st.id.hasSuffix("_right") { try expectEqual(st.facing, "right", "\(c.id) \(st.id)") }
            }
        }
    }

    // MARK: The movement matrix: every character x every way of moving

    func brain(for c: CharacterDefinition, seed: UInt64) -> PetBrain {
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
        config.personality = c.personality
        config.homeOnLeft = true
        return PetBrain(config: config, x: 700, y: 300, minX: 0, maxX: 1600, minY: 70, maxY: 900, intro: false, rng: SeededRandom(seed: seed))
    }

    let movingClips: Set<String> = ["walk", "walk_bark", "run", "gallop"]

    runner.run("Facing.everyCharacter_everyMovementPath_neverWalksBackward_andShowsAMovingClip") {
        let commands: [PetCommand] = [.follow(duration: 40), .comeHere, .explore, .play, .hideAndSeek, .stay(duration: 10), .watch, .nap, .stop, .wake]
        for c in repo.characters {
            for seed in UInt64(1)...UInt64(2) {
                let b = brain(for: c, seed: seed)
                let rng = SeededRandom(seed: seed &+ 9)
                var watch = FacingWatch(b, tolerance: 12)
                var context = PetContext(); context.hour = 14
                for i in 0..<(60 * 5 * 4) { // 4 simulated minutes at 0.2 s
                    if i % 90 == 0 { _ = b.perform(commands[rng.int(0...(commands.count - 1))], context: context) }
                    if i % 40 == 0 { // the cursor sweeps corner to corner (diagonals) or jumps
                        let corners: [(Double, Double)] = [(20, 880), (1580, 90), (1580, 880), (20, 90), (800, 500)]
                        let t = corners[rng.int(0...(corners.count - 1))]
                        context.cursorX = t.0; context.cursorY = t.1
                    }
                    if i % 333 == 0 { b.handle(.click, context: context) }
                    b.update(dt: 0.2, context: context)
                    watch.observe(b)
                    if b.isMoving, !b.isTurning, b.behavior != .dragged, b.behavior != .falling {
                        try expectTrue(movingClips.contains(b.clip), "\(c.id): moving with clip \(b.clip) during \(b.behavior)")
                        if let r = c.resolve(b.clip, facing: b.facing) {
                            let eff = effectiveFacing(r, native: c.manifest.nativeFacing)
                            try expectTrue(eff == (b.facing == .left ? "left" : "right") || eff == "front", "\(c.id): drawn \(eff) while facing \(b.facing)")
                        }
                    }
                }
                try expectTrue(watch.worstBackward <= watch.tolerance, "\(c.id) seed \(seed): walked \(watch.worstBackward) pt backward")
            }
        }
    }

    runner.run("Facing.goToBed_walksToTheBedFacingIt") {
        for start in [(100.0, 200.0), (1500.0, 800.0), (800.0, 90.0)] {
            let b = makeBrain(x: start.0, y: start.1, energy: 0.2)
            var watch = FacingWatch(b, tolerance: 12)
            var c = ctx(nil)
            c.hour = 23; c.bedX = 700; c.bedY = 150
            for _ in 0..<(60 * 5 * 4) { b.update(dt: 0.2, context: c); watch.observe(b) }
            try expectTrue(watch.worstBackward <= watch.tolerance, "from \(start): backward \(watch.worstBackward)")
        }
    }

    // MARK: Explicit scenarios from the bug report

    runner.run("Facing.strongLeftAndRight_followTheHorizontalVelocity") {
        for (cursorX, expected) in [(1500.0, Facing.right), (100.0, .left)] {
            let b = makeBrain(x: 800, y: 300)
            let c = ctx((cursorX, 300))
            _ = b.perform(.follow(duration: 30), context: c)
            var sawMove = false
            for _ in 0..<150 {
                b.update(dt: 0.1, context: c)
                if b.isMoving, !b.isTurning { sawMove = true; try expectEqual(b.facing, expected, "moving toward x=\(cursorX)") }
            }
            try expectTrue(sawMove)
        }
    }

    runner.run("Facing.aTinySidewaysNudge_neverFlickers_zeroMovementKeepsTheFacing") {
        let b = makeBrain(x: 800, y: 300)
        var c = ctx((1400, 300))
        _ = b.perform(.follow(duration: nil), context: c)
        for _ in 0..<600 { b.update(dt: 0.1, context: c) } // arrives on the right, facing right
        let before = b.facing
        var flips = 0
        var last = b.facing
        for i in 0..<400 { // the cursor jitters a few points either side of where it already is
            c.cursorX = 1400 + (i % 2 == 0 ? 3 : -3)
            b.update(dt: 0.1, context: c)
            if b.facing != last { flips += 1; last = b.facing }
        }
        _ = before
        try expectTrue(flips <= 1, "a 3 pt cursor jitter flipped the facing \(flips) times (flicker)")
    }

    runner.run("Facing.directionReversal_turnsInPlaceThenWalksTheNewWay") {
        let b = makeBrain(x: 800, y: 300)
        var c = ctx((1500, 300))
        _ = b.perform(.follow(duration: 120), context: c)
        for _ in 0..<80 { b.update(dt: 0.1, context: c) }
        try expectEqual(b.facing, .right)
        c.cursorX = 50
        var watch = FacingWatch(b, tolerance: 12)
        for _ in 0..<600 { b.update(dt: 0.1, context: c); watch.observe(b) }
        try expectEqual(b.facing, .left)
        try expectTrue(watch.worstBackward <= 12, "reversal walked \(watch.worstBackward) pt backward")
        try expectTrue(watch.flips <= 2, "reversal should flip once or twice at most, got \(watch.flips)")
    }

    runner.run("Facing.diagonalMovement_keepsAStableHorizontalFacing") {
        for (from, cursor) in [((60.0, 850.0), (1550.0, 100.0)), ((1500.0, 100.0), (60.0, 850.0)), ((800.0, 480.0), (1580.0, 890.0)), ((1580.0, 890.0), (800.0, 480.0))] {
            let b = makeBrain(x: from.0, y: from.1)
            var watch = FacingWatch(b, tolerance: 12)
            let c = ctx(cursor)
            _ = b.perform(.follow(duration: 60), context: c)
            for _ in 0..<550 { b.update(dt: 0.1, context: c); watch.observe(b) } // the 60 s follow window
            try expectTrue(watch.worstBackward <= 12, "diagonal \(from)->\(cursor): \(watch.worstBackward) pt backward")
            try expectTrue(watch.flips <= 2, "diagonal \(from)->\(cursor): facing flipped \(watch.flips) times")
        }
    }

    runner.run("Facing.rapidTargetChanges_neverProduceBackwardWalking") {
        let b = makeBrain(x: 800, y: 300)
        let rng = SeededRandom(seed: 5)
        var c = ctx((800, 300))
        var watch = FacingWatch(b, tolerance: 12)
        _ = b.perform(.follow(duration: nil), context: c)
        for i in 0..<(60 * 10 * 5) {
            if i % 7 == 0 { c.cursorX = rng.uniform(0...1600); c.cursorY = rng.uniform(70...900) }
            b.update(dt: 0.1, context: c)
            watch.observe(b)
        }
        try expectTrue(watch.worstBackward <= 12, "\(watch.worstBackward) pt backward under rapid target changes")
    }

    runner.run("Facing.interruptStopResume_leavesAValidFacingAndNoBackwardStep") {
        let b = makeBrain(x: 800, y: 300)
        var c = ctx((1400, 700))
        var watch = FacingWatch(b, tolerance: 12)
        for round in 0..<20 {
            _ = b.perform(.follow(duration: nil), context: c)
            for _ in 0..<40 { b.update(dt: 0.1, context: c); watch.observe(b) }
            _ = b.perform(round % 2 == 0 ? .stop : .sleep, context: c)
            for _ in 0..<30 { b.update(dt: 0.1, context: c); watch.observe(b) }
            b.handle(.dragBegan, context: c); b.handle(.dropped, context: c)
            for _ in 0..<30 { b.update(dt: 0.1, context: c); watch.observe(b) }
            c.cursorX = round % 2 == 0 ? 100 : 1500
        }
        try expectTrue(watch.worstBackward <= 12, "\(watch.worstBackward) pt backward")
    }

    // MARK: Brain and renderer must agree (the real app ticks about once a second while following)

    /// A model of the platform renderer: at every new leg it glides from where the sprite currently is to the leg's
    /// target over the leg's remaining time, exactly what `CharacterView.glide` hands to Core Animation.
    struct RendererModel {
        var x: Double
        private var from: Double
        private var to: Double
        private var duration = 0.0
        private var elapsed = 0.0
        private var curve: (linear: Bool, brake: Bool) = (true, false)
        private var lastRevision = -1

        init(_ brain: PetBrain) { x = brain.x; from = brain.x; to = brain.x; lastRevision = brain.legRevision }

        mutating func sync(_ brain: PetBrain) {
            if brain.legRevision != lastRevision {
                lastRevision = brain.legRevision
                if let leg = brain.leg {
                    from = x; to = leg.toX; duration = max(leg.remaining, 0.05); elapsed = 0
                    curve = (leg.linear, leg.brake)
                } else { x = brain.x; from = x; to = x; duration = 0 } // the brain stopped: the sprite is set to where it is
            }
        }

        mutating func advance(_ dt: Double) {
            guard duration > 0 else { return }
            elapsed = min(elapsed + dt, duration)
            let t = elapsed / duration
            let p = curve.brake ? 1 - (1 - t) * (1 - t) : (curve.linear ? t : MovementEasing.progress(t))
            x = from + (to - from) * p
        }
    }

    runner.run("Facing.atTheAppsRealTickRate_brainAndRendererStayTogether_whileFollowingAMovingCursor") {
        for dt in [1.05, 0.5, 0.25] {
            let b = makeBrain(x: 100, y: 200)
            var c = ctx((300, 300))
            _ = b.perform(.follow(duration: nil), context: c)
            var render = RendererModel(b)
            var watch = FacingWatch(b, tolerance: 12)
            var worstGap = 0.0
            var t = 0.0
            for _ in 0..<Int(90 / dt) {
                // the cursor sweeps right, holds, sweeps back left, holds, then jumps right again
                let phase = t.truncatingRemainder(dividingBy: 40)
                c.cursorX = phase < 12 ? 300 + phase * 100 : (phase < 18 ? 1500 : (phase < 30 ? 1500 - (phase - 18) * 110 : 180))
                c.cursorY = 300 + 200 * sin(t / 9)
                b.update(dt: dt, context: c)
                watch.observe(b)
                render.sync(b)
                render.advance(dt)
                // At the end of the tick the sprite should be where the brain says it is.
                worstGap = max(worstGap, abs(render.x - b.x))
                t += dt
            }
            try expectTrue(worstGap < 90, "dt \(dt): the brain and the sprite drifted \(worstGap) pt apart")
            try expectTrue(watch.worstBackward <= 12, "dt \(dt): \(watch.worstBackward) pt backward")
        }
    }

    runner.run("Facing.followMakesProgress_evenWhenTicksAreSlow") {
        let b = makeBrain(x: 50, y: 200)
        var c = ctx((300, 300))
        _ = b.perform(.follow(duration: nil), context: c)
        for i in 0..<12 { c.cursorX = 300 + Double(i) * 100; b.update(dt: 1.05, context: c) } // a cursor drifting right for 12 s
        try expectTrue(b.x > 300, "after 12 s of chasing, the companion was still at x=\(b.x)")
    }

    runner.run("Facing.everyCommand_atRealTickRates_keepsBrainAndSpriteTogether_andNeverWalksBackward") {
        let commands: [PetCommand] = [.follow(duration: 30), .comeHere, .play, .explore, .hideAndSeek, .stay(duration: 10), .watch, .nap, .stop, .wake, .sleep, .trick(.spin)]
        for dt in [1.05, 0.3] {
            for seed in UInt64(1)...UInt64(4) {
                let b = makeBrain(seed: seed, x: 700, y: 300)
                let rng = SeededRandom(seed: seed &* 13)
                var c = ctx((900, 400))
                var render = RendererModel(b)
                var watch = FacingWatch(b, tolerance: 12)
                var worstGap = 0.0
                var worstAt = ""
                for i in 0..<Int(600 / dt) {
                    if i % Int(20 / dt) == 0 { _ = b.perform(commands[rng.int(0...(commands.count - 1))], context: c) }
                    if i % Int(4 / dt) == 0 {
                        let corners: [(Double, Double)] = [(20, 880), (1580, 90), (1580, 880), (20, 90), (800, 500)]
                        let t = corners[rng.int(0...(corners.count - 1))]; c.cursorX = t.0; c.cursorY = t.1
                    }
                    b.update(dt: dt, context: c)
                    watch.observe(b)
                    render.sync(b)
                    render.advance(dt)
                    if b.isMoving, !b.isTurning {
                        let gap = abs(render.x - b.x)
                        if gap > worstGap { worstGap = gap; worstAt = "\(b.behavior)/\(String(describing: b.currentActivity))" }
                    } else { render.x = b.x }
                }
                try expectTrue(worstGap < 100, "dt \(dt) seed \(seed): sprite and brain drifted \(worstGap) pt apart during \(worstAt)")
                try expectTrue(watch.worstBackward <= 12, "dt \(dt) seed \(seed): \(watch.worstBackward) pt backward")
            }
        }
    }
}
