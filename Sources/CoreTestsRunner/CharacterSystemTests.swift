import Foundation
import Core

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let charactersDir = repoRoot.appendingPathComponent("Characters")
/// The shipped characters. A floor, not an exact set.
private let expectedIDs: Set<String> = ["biscuit-proto", "ginger", "smoky", "rusty", "snowy", "mango"]

func runCharacterSystemTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: charactersDir)

    runner.run("Characters.repositoryLoadsEveryPackWithoutFailures") {
        try expectTrue(repo.failures.isEmpty, "failures: \(repo.failures.map { "\($0.id): \($0.error)" })")
        let loadedIDs = Set(repo.characters.map(\.id))
        try expectTrue(expectedIDs.isSubset(of: loadedIDs), "missing originals: \(expectedIDs.subtracting(loadedIDs))")
    }

    runner.run("Characters.everyCharacterResolvesTheCoreVocabularyInBothDirections") {
        let core = ["stand", "sit", "lie", "yawn", "sleep", "walk", "run", "gallop", "happy", "celebrate", "beg",
                    "stand_bark", "sit_bark", "dragged", "fall", "land"]
        for c in repo.characters {
            for clip in core {
                for f in [Facing.left, .right] {
                    try expectTrue(c.resolve(clip, facing: f) != nil, "\(c.id) cannot render \(clip)")
                }
            }
        }
    }

    runner.run("Characters.movementClipsAlwaysFaceTheDirectionOfTravel") {
        for c in repo.characters {
            for clip in ["walk", "run"] {
                for f in [Facing.left, .right] {
                    guard let r = c.resolve(clip, facing: f) else { try fail("\(c.id) \(clip)"); return }
                    let drawn = r.state.facing ?? c.manifest.nativeFacing ?? "right"
                    try expectTrue(drawn != "front", "\(c.id) \(clip) is front-facing art")
                    let visible = r.mirrored ? (drawn == "left" ? "right" : "left") : drawn
                    try expectEqual(visible, f == .left ? "left" : "right")
                }
            }
        }
    }

    runner.run("Characters.leftFacingArtIsMirroredOnlyWhenWalkingRight") {
        for c in repo.characters {
            try expectEqual(c.resolve("walk", facing: .left)?.mirrored, false, c.id)
            try expectEqual(c.resolve("walk", facing: .right)?.mirrored, true, c.id)
        }
    }

    runner.run("Characters.missingAnimationsFallBackGracefully") {
        let biscuit = repo.character(id: "biscuit-proto")!
        try expectEqual(biscuit.resolve("happy", facing: .left)?.state.id, "beg")
        try expectEqual(biscuit.resolve("celebrate", facing: .left)?.state.id, "beg")
        try expectTrue(biscuit.resolve("stretch", facing: .left) == nil)   // art-only, no fake fallback
        try expectTrue(biscuit.resolve("think", facing: .left) == nil)
        try expectFalse(biscuit.availableClipNames.contains("think"))
    }

    runner.run("Characters.spriteStripsMatchTheirManifests") {
        for c in repo.characters {
            let (w, h) = c.frameSize
            for s in c.manifest.states {
                try expectEqual(s.animation.frameWidth, w)
                try expectEqual(s.animation.frameHeight, h)
                let url = c.baseURL.appendingPathComponent(s.animation.spriteSheet)
                try expectTrue(FileManager.default.fileExists(atPath: url.path), "\(c.id)/\(s.animation.spriteSheet)")
            }
            if let p = c.manifest.preview {
                try expectTrue(FileManager.default.fileExists(atPath: c.baseURL.appendingPathComponent(p.spriteSheet).path))
            }
        }
    }

    runner.run("Characters.selectionFallsBackSafely") {
        try expectEqual(repo.resolveSelection("snowy").id, "snowy")
        try expectEqual(repo.resolveSelection("does-not-exist").id, CharacterRepository.defaultCharacterID)
        try expectEqual(repo.resolveSelection(nil).id, CharacterRepository.defaultCharacterID)
        try expectEqual(CharacterRepository(characters: []).resolveSelection("ginger").id, SafeDefaultCharacter.manifest.id)
    }

    runner.run("Characters.brainRunsEveryCharacterForAnHour_everyClipRenderable") {
        for c in repo.characters {
            let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: c.availableClipNames),
                                 x: 0, minX: 0, maxX: 1400, rng: SeededRandom(seed: 17))
            try expectTrue(brain.availableBehaviors.count >= 50, "\(c.id): \(brain.availableBehaviors.count) behaviors")
            var ctx = PetContext(); ctx.cursorX = 700
            for i in 0..<(3600 * 5) {
                if i % 997 == 0 { brain.handle(.click, context: ctx) }
                if i % 4001 == 0 { brain.handle(.doubleClick, context: ctx) }
                brain.update(dt: 0.2, context: ctx)
                if c.resolve(brain.clip, facing: brain.facing) == nil { try fail("\(c.id) can't render \(brain.clip) in \(brain.behavior)") }
            }
        }
    }

    runner.run("Characters.switchingCharacterPreservesPetState") {
        let ginger = repo.character(id: "ginger")!, smoky = repo.character(id: "biscuit-proto")!
        let brain = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ginger.availableClipNames),
                             x: 300, minX: 0, maxX: 1400, energy: 0.7, intro: false, rng: SeededRandom(seed: 3))
        let ctx = PetContext()
        for _ in 0..<300 { brain.update(dt: 0.1, context: ctx) }
        brain.handle(.click, context: ctx)
        let before = (brain.x, brain.energy, brain.stats, brain.behavior)
        brain.setAvailableClips(smoky.availableClipNames, context: ctx)
        try expectEqual(brain.x, before.0)
        try expectEqual(brain.energy, before.1)
        try expectEqual(brain.stats, before.2)
        try expectEqual(brain.behavior, before.3)
        try expectTrue(smoky.resolve(brain.clip, facing: brain.facing) != nil)
        // Switching to a character without a behavior's art degrades to standing, never crashes.
        let limited = PetBrain(config: .init(pointsPerPixel: 2, petWidth: 100, availableClips: ginger.availableClipNames),
                               x: 300, minX: 0, maxX: 1400, intro: false, rng: SeededRandom(seed: 3))
        limited.handle(.dragBegan, context: ctx)
        limited.setAvailableClips(["stand", "sit"], context: ctx)
        try expectTrue(["stand", "sit"].contains(limited.clip))
    }
}
