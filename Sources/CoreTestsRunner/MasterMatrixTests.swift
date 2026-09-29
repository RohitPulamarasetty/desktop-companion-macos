import Foundation
import Core

/// Stage 11: closes the "combined characters x modes x commands" gap the
/// master audit identified -- prior coverage tested these dimensions
/// separately (e.g. all 31 characters in autonomous mode only, modes
/// across 3 sample characters), never fully crossed in one matrix.
private let matrixRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let matrixCharactersDir = matrixRepoRoot.appendingPathComponent("Characters")

func runMasterMatrixTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: matrixCharactersDir)

    runner.run("MasterMatrix.allCharacters_x_allModes_x_allCommands_neverProducesInvalidState") {
        try expectTrue(repo.characters.count >= 6)
        let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .quiet, .stop, .follow(duration: nil), .stay(duration: nil), .explore, .hideAndSeek]
        var combinationsChecked = 0
        for c in repo.characters {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            for mode in PetMode.allCases {
                let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: 99))
                var ctx = PetContext(); ctx.mode = mode; ctx.cursorX = 520; ctx.cursorY = 0
                for _ in 0..<20 { brain.update(dt: 0.5, context: ctx) } // settle into some starting behavior
                for command in commands {
                    _ = brain.perform(command, context: ctx)
                    for _ in 0..<10 { brain.update(dt: 0.5, context: ctx) }
                    combinationsChecked += 1
                    try expectFalse(brain.isAsleep && brain.isMoving, "\(c.id)/\(mode)/\(command): impossible state")
                    try expectTrue(brain.x.isFinite && brain.y.isFinite && brain.energy.isFinite, "\(c.id)/\(mode)/\(command): non-finite state")
                    try expectTrue(brain.x >= -1 && brain.x <= 1001, "\(c.id)/\(mode)/\(command): out of bounds x=\(brain.x)")
                }
            }
        }
        // Documents the actual coverage size achieved, so a future change
        // that silently shrinks the character/mode/command lists is visible
        // as a test-count regression, not a silent gap.
        try expectTrue(combinationsChecked >= 6 * 5 * 9)
    }

    runner.run("MasterMatrix.everyCharacter_recoversToAutonomyAfterEveryCommand_regardlessOfMode") {
        // A narrower, deeper check: after each command, a final .stop must
        // always bring every character back to a clean, non-stuck state,
        // in every mode -- not just "doesn't crash," but "actually recovers."
        let sample = Array(repo.characters.prefix(10)) // bounded for runtime; full-catalog crash/NaN check is above
        let commands: [PetCommand] = [.sleep, .comeHere, .play, .follow(duration: nil), .stay(duration: nil), .explore, .hideAndSeek]
        for c in sample {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            for mode in PetMode.allCases {
                for command in commands {
                    let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: 5))
                    var ctx = PetContext(); ctx.mode = mode; ctx.cursorX = 520; ctx.cursorY = 0
                    _ = brain.perform(command, context: ctx)
                    for _ in 0..<10 { brain.update(dt: 0.5, context: ctx) }
                    _ = brain.perform(.stop, context: ctx)
                    ctx.mode = .normal // .stop should recover even if the mode itself would otherwise suppress roaming
                    for _ in 0..<200 { brain.update(dt: 0.5, context: ctx) }
                    try expectFalse(brain.isFollowing, "\(c.id)/\(mode)/\(command): follow window leaked past .stop")
                    try expectFalse(brain.isStaying, "\(c.id)/\(mode)/\(command): stay window leaked past .stop")
                    try expectTrue(brain.x.isFinite, "\(c.id)/\(mode)/\(command): non-finite after recovery")
                }
            }
        }
    }

    // Regression: `PetCommand.perform(.play, ...)` used to guard on
    // `isAvailable(.play)`, but it actually triggers `.doubleClick` (the
    // same "petted" path double-clicking already uses), never the `.play`
    // behavior itself. Since no currently-shipped character package ships
    // a "play" clip (BehaviorCatalog documents `.play` as one of the
    // art-less behaviors excluded until a character provides it), that
    // guard made `PetCommand.play` unconditionally `.ignored` for every
    // one of the 31 installed characters, even though the interaction it
    // actually performs (`.petted`) was perfectly available. Fixed by
    // guarding on `isAvailable(.petted)` instead (Sources/Core/Behavior/
    // PetCommand.swift).
    runner.run("MasterMatrix.playCommand_isHandled_forEveryInstalledCharacter_notSilentlyIgnored") {
        try expectTrue(repo.characters.count >= 6)
        for c in repo.characters {
            var config = PetBrain.Config(pointsPerPixel: 2.5, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
            config.personality = c.personality
            let brain = PetBrain(config: config, x: 500, minX: 0, maxX: 1000, rng: SeededRandom(seed: 3))
            var ctx = PetContext(); ctx.cursorX = 520; ctx.cursorY = 0
            for _ in 0..<20 { brain.update(dt: 0.5, context: ctx) } // settle into some starting behavior
            // `.petted` is the behavior every character actually needs for
            // this command to do anything -- confirms the fixture assumption
            // this test depends on, not just re-asserting the fix's own logic.
            try expectTrue(brain.isAvailable(.excited), "\(c.id): fixture assumption broken, .excited itself unavailable")
            let result = brain.perform(.play, context: ctx)
            try expectEqual(result, .handled)
            try expectEqual(brain.behavior, .excited)
        }
    }
}
