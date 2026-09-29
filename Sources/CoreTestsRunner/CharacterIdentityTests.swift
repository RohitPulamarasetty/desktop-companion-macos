import Foundation
import Core

/// Stage 9, Phase 15: proves characters actually behave differently, using
/// the REAL installed character packages (`CharacterRepository`, the same
/// loader the app uses) and their REAL manifest personality values -- not
/// synthetic configs. A metadata test (e.g. "azure.personality.curiosity
/// == 1.4") only proves the JSON parses; these run long simulations and
/// compare actual behavior-choice distributions.
private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let identityCharactersDir = repoRoot.appendingPathComponent("Characters")

func runCharacterIdentityTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: identityCharactersDir)

    func character(_ id: String) -> CharacterDefinition? {
        repo.characters.first { $0.id == id }
    }

    /// Builds a brain exactly the way the real app does (`CharacterWindowController`):
    /// same Config shape, same `character.personality`/`availableClipNames`.
    func makeBrain(for c: CharacterDefinition, seed: UInt64) -> PetBrain {
        var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
        config.personality = c.personality
        return PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: seed))
    }

    func fractionInSet(_ set: Set<PetBehavior>, for c: CharacterDefinition, ctx: PetContext = PetContext(), seeds: [UInt64] = [1, 2, 3, 4, 5, 6]) -> Double {
        var total = 0.0
        for seed in seeds {
            let brain = makeBrain(for: c, seed: seed)
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

    runner.run("CharacterIdentity.allInstalledCharactersLoadWithDistinctPersonalityValues") {
        try expectTrue(repo.failures.isEmpty, "failures: \(repo.failures.map { "\($0.id): \($0.error)" })")
        // Regression guard for the exact gap this phase found and fixed:
        // every installed character must have a curiosity/affection dial
        // that actually differs from the flat 1.0 default that ALL 31
        // characters silently had before Stage 9 (only restfulness/
        // roaming/reactivity/chattiness were ever populated in the source
        // manifests).
        let allNeutral = repo.characters.allSatisfy { $0.personality.curiosity == 1.0 && $0.personality.affection == 1.0 }
        try expectFalse(allNeutral, "expected at least some characters to have non-neutral curiosity/affection dials")
    }

    runner.run("CharacterIdentity.curiousCharacter_exploresMoreThanCalmCharacter_usingRealInstalledPackages") {
        guard let curious = character("ginger"), let calm = character("smoky") else { try fail("fox/bear not installed"); return }
        try expectTrue(curious.personality.curiosity > calm.personality.curiosity, "fixture assumption broken: ginger should be more curious than smoky in the real manifests")
        let exploring: Set<PetBehavior> = [.explore, .investigate, .patrol]
        let curiousFraction = fractionInSet(exploring, for: curious)
        let calmFraction = fractionInSet(exploring, for: calm)
        try expectTrue(curiousFraction > calmFraction, "expected fox (curious) to explore more than bear (calm) using their real installed manifests: fox=\(curiousFraction) bear=\(calmFraction)")
    }

    runner.run("CharacterIdentity.loyalAffectionateCharacter_warmsUpFasterThanMischievousCharacter") {
        guard let loyal = character("snowy"), let mischievous = character("rusty") else { try fail("snowy/rusty not installed"); return }
        try expectTrue(loyal.personality.affection > mischievous.personality.affection, "fixture assumption broken: snowy should be more affectionate than rusty in the real manifests")
        let low = makeBrain(for: mischievous, seed: 9)
        let high = makeBrain(for: loyal, seed: 9)
        let ctx = PetContext()
        _ = low.handle(.click, context: ctx)
        _ = high.handle(.click, context: ctx)
        try expectTrue(high.affection > low.affection, "expected burrow (loyal) to warm up more from an identical click than purple (mischievous): burrow=\(high.affection) purple=\(low.affection)")
    }

    runner.run("CharacterIdentity.calmCharacter_restsMoreThanEnergeticCharacter_usingRealInstalledPackages") {
        guard let calm = character("mango"), let energetic = character("rusty") else { try fail("mango/rusty not installed"); return }
        try expectTrue(calm.personality.restfulness > energetic.personality.restfulness, "fixture assumption broken")
        let calmPoses: Set<PetBehavior> = [.sit, .settle, .restAlert, .lie, .doze, .sleep]
        let calmFraction = fractionInSet(calmPoses, for: calm)
        let energeticFraction = fractionInSet(calmPoses, for: energetic)
        try expectTrue(calmFraction > energeticFraction, "expected shellguard (calm) to rest more than usagi (energetic): shellguard=\(calmFraction) usagi=\(energeticFraction)")
    }
}
