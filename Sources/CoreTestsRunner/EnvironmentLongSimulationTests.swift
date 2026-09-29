import Foundation
import Core

/// Stage 10.10: a long-running simulation with the environment (bed)
/// enabled, across real installed characters, personalities, modes, and
/// randomized commands/interruptions -- checking both reliability
/// (no impossible/stuck states) and behavior balance (the bed influences
/// behavior, it does not dominate it).
private let envSimRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let envSimCharactersDir = envSimRepoRoot.appendingPathComponent("Characters")

func runEnvironmentLongSimulationTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: envSimCharactersDir)

    runner.run("EnvironmentLongSimulation.bedInfluencesButNeverDominatesBehavior_acrossRealCharactersAndModes") {
        let sample = ["ginger", "smoky", "rusty", "snowy", "mango"].compactMap { id in repo.characters.first { $0.id == id } }
        try expectTrue(sample.count == 5, "expected all 5 sample characters installed")
        let bedRelated: Set<PetBehavior> = [.goToBed, .lie, .sleep, .doze]
        for c in sample {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            let rng = SeededRandom(seed: 42)
            let brain = PetBrain(config: config, x: 300, minX: 0, maxX: 1000, rng: rng)
            var ctx = PetContext(); ctx.bedX = 700; ctx.bedY = 0
            let modes = PetMode.allCases
            var bedRelatedTicks = 0
            let totalTicks = 12_000
            for i in 0..<totalTicks {
                if i % 60 == 0 {
                    ctx.hour = Int(rng.nextUnit() * 24)
                    ctx.mode = modes[Int(rng.nextUnit() * Double(modes.count))]
                    ctx.cursorX = rng.chance(0.5) ? 500 : nil
                    ctx.cursorNearPet = rng.chance(0.2)
                }
                brain.update(dt: 1, context: ctx)
                if bedRelated.contains(brain.behavior) { bedRelatedTicks += 1 }
                try expectFalse(brain.isAsleep && brain.isMoving, "\(c.id): impossible state at tick \(i)")
                try expectTrue(brain.x.isFinite && brain.energy.isFinite, "\(c.id): non-finite state at tick \(i)")
            }
            let bedFraction = Double(bedRelatedTicks) / Double(totalTicks)
            // "Influences, does not dominate": across a full day/night mix
            // of hours and every mode, rest-related behavior (bed or
            // otherwise) should never consume nearly the entire
            // simulation -- there must be real room left for walking,
            // exploring, and everything else.
            try expectTrue(bedFraction < 0.6, "\(c.id): rest/bed-related behavior dominated the simulation (\(bedFraction * 100)%)")
        }
    }

    runner.run("EnvironmentLongSimulation.everyCharacterStillPerformsNonRestActivity_withBedEnabled") {
        // Confirms walking/exploring/social behaviors still genuinely
        // happen for every character even with a bed always available --
        // not just that rest doesn't dominate on average.
        let nonRest: Set<PetBehavior> = [.walk, .stroll, .explore, .patrol, .lookAround, .sniff, .tailWag, .sit]
        for c in repo.characters {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            let brain = PetBrain(config: config, x: 300, minX: 0, maxX: 1000, rng: SeededRandom(seed: 7))
            var ctx = PetContext(); ctx.hour = 14; ctx.bedX = 700; ctx.bedY = 0 // midday: low sleepiness, bed shouldn't crowd anything out
            var sawNonRest = false
            for _ in 0..<3000 {
                brain.update(dt: 1, context: ctx)
                if nonRest.contains(brain.behavior) { sawNonRest = true; break }
            }
            try expectTrue(sawNonRest, "\(c.id): never performed any ordinary non-rest activity even at midday with the bed enabled")
        }
    }

    runner.run("EnvironmentLongSimulation.bedRemovalAndReintroduction_neverCorruptsState") {
        // "Environment removal/re-addition" from the brief: toggling the
        // bed on and off repeatedly (mirroring the Settings checkbox)
        // must never leave the brain in a bad state.
        let brain = PetBrain(config: PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: [
            "stand", "sit", "walk", "walk_left", "walk_right", "lie", "sleep", "doze", "settle", "yawn",
        ]), x: 300, minX: 0, maxX: 1000, rng: SeededRandom(seed: 8))
        var ctx = PetContext(); ctx.hour = 2
        for i in 0..<6000 {
            ctx.bedX = (i / 500) % 2 == 0 ? 700 : nil // flips every 500 ticks
            ctx.bedY = ctx.bedX == nil ? nil : 0
            brain.update(dt: 1, context: ctx)
            try expectFalse(brain.isAsleep && brain.isMoving, "impossible state at tick \(i) during bed toggling")
            try expectTrue(brain.x.isFinite, "non-finite position at tick \(i) during bed toggling")
        }
    }
}
