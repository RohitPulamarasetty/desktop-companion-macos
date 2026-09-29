import Foundation
import Core

/// Stage 11, Phase 14: a genuinely 24-simulated-hour run (86,400 seconds
/// of `PetContext.hour` progressing through a full day/night cycle),
/// which nothing in the existing suite did -- the longest prior
/// simulation (Stage 9's combined stress test) covered 10,000 ticks at
/// dt=0.3s, about 50 simulated minutes, not a full day.
private let dayRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let dayCharactersDir = dayRepoRoot.appendingPathComponent("Characters")

func runTwentyFourHourSimulationTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: dayCharactersDir)

    runner.run("TwentyFourHour.fullSimulatedDayAndNight_acrossSeveralCharacters_neverBreaksInvariants") {
        let sample = ["ginger", "smoky", "rusty", "mango"].compactMap { id in repo.characters.first { $0.id == id } }
        try expectTrue(sample.count == 4, "expected fox/bear/usagi/shellguard installed")
        for c in sample {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            let rng = SeededRandom(seed: 2026)
            let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: rng)
            var ctx = PetContext()
            ctx.bedX = 700; ctx.bedY = 0 // environment enabled throughout
            let dt = 30.0 // 30 simulated seconds per tick
            let totalSimulatedSeconds = 24.0 * 3600 // one full day
            var elapsed = 0.0
            var sawSleep = false, sawWalk = false, sawGoToBed = false
            var behaviorHistogram: [PetBehavior: Int] = [:]
            while elapsed < totalSimulatedSeconds {
                elapsed += dt
                // Real wall-clock-style hour progression across the
                // simulated day, plus periodic desktop-awareness/command
                // variation so this isn't just "one context forever."
                let simulatedHourOfDay = Int((elapsed / 3600).truncatingRemainder(dividingBy: 24))
                ctx.hour = simulatedHourOfDay
                if Int(elapsed) % 1800 == 0 {
                    ctx.cursorX = rng.chance(0.6) ? 500 : nil
                    ctx.cursorY = ctx.cursorX == nil ? nil : 0
                    ctx.cursorNearPet = rng.chance(0.25)
                    ctx.userIdleSeconds = rng.chance(0.3) ? rng.nextUnit() * 600 : 0
                    ctx.batteryLow = rng.chance(0.05)
                    ctx.continuousActiveMinutes = rng.chance(0.2) ? rng.nextUnit() * 100 : 0
                }
                if Int(elapsed) % 3600 == 0 {
                    let commands: [PetCommand] = [.comeHere, .play, .quiet, .follow(duration: nil), .stay(duration: nil)]
                    _ = brain.perform(commands[Int(rng.nextUnit() * Double(commands.count))], context: ctx)
                }
                brain.update(dt: dt, context: ctx)
                behaviorHistogram[brain.behavior, default: 0] += 1
                if brain.isAsleep { sawSleep = true }
                if brain.behavior == .walk { sawWalk = true }
                if brain.behavior == .goToBed { sawGoToBed = true }

                try expectFalse(brain.isAsleep && brain.isMoving, "\(c.id): impossible state at simulated hour \(simulatedHourOfDay), elapsed=\(elapsed)")
                try expectTrue(brain.x.isFinite && brain.y.isFinite && brain.energy.isFinite, "\(c.id): non-finite state at elapsed=\(elapsed)")
                try expectTrue(brain.x >= -1 && brain.x <= 1001, "\(c.id): out of bounds x=\(brain.x) at elapsed=\(elapsed)")
                try expectTrue(brain.energy >= 0 && brain.energy <= 1, "\(c.id): energy out of range at elapsed=\(elapsed)")
                try expectTrue(brain.affection >= 0 && brain.affection <= 1, "\(c.id): affection out of range at elapsed=\(elapsed)")
            }
            // Over a full day, a character should genuinely both sleep and
            // walk at some point -- if either never happened, the day/night
            // cycle isn't actually influencing behavior the way it should.
            try expectTrue(sawSleep, "\(c.id): never slept across a full simulated day")
            try expectTrue(sawWalk, "\(c.id): never walked across a full simulated day")
            _ = sawGoToBed // observational; not asserted, since going to the bed specifically remains a soft scoring signal (Stage 10.11) not a guarantee within any one day
            try expectFalse(behaviorHistogram.isEmpty)
        }
    }

    runner.run("TwentyFourHour.multipleSimulatedDays_bedToggling_noStateCorruptionOverTime") {
        // A longer, coarser run (3 simulated days) specifically exercising
        // the environment being enabled/disabled repeatedly across many
        // sleep/wake cycles, per Phase 14's "environment changes" and
        // "multiple simulated days" requirements.
        guard let fox = repo.characters.first(where: { $0.id == "ginger" }) else { try fail("ginger not installed"); return }
        var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: fox.availableClipNames)
        config.personality = fox.personality
        let rng = SeededRandom(seed: 42)
        let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: rng)
        var ctx = PetContext()
        let dt = 60.0
        let totalSimulatedSeconds = 3.0 * 24 * 3600
        var elapsed = 0.0
        while elapsed < totalSimulatedSeconds {
            elapsed += dt
            ctx.hour = Int((elapsed / 3600).truncatingRemainder(dividingBy: 24))
            // Bed toggles on/off every simulated 6 hours.
            let bedOn = Int(elapsed / 3600) % 12 < 6
            ctx.bedX = bedOn ? 700 : nil
            ctx.bedY = bedOn ? 0 : nil
            brain.update(dt: dt, context: ctx)
            try expectFalse(brain.isAsleep && brain.isMoving, "impossible state at elapsed=\(elapsed)")
            try expectTrue(brain.x.isFinite && brain.energy.isFinite, "non-finite state at elapsed=\(elapsed)")
        }
    }
}
