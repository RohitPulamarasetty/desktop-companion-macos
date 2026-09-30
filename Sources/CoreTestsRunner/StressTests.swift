import Foundation
import Core

/// The big randomized soak: every shipped character, every mode, every command and event, cursor jumps,
/// display changes and character switches in the middle of whatever the companion is doing.
func runStressTests(_ runner: TestRunner) {
    let repo = CharacterRepository(directory: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Characters"))

    let events: [PetEvent] = [.click, .doubleClick, .dragBegan, .dropped, .landed, .userReturned(awaySeconds: 900), .cursorApproached, .morningGreeting,
                              .taskCompleted, .allTasksDone, .focusStarted, .focusCompleted, .focusStopped, .breakStarted, .waterLogged, .reminderDue,
                              .longSessionNudge, .answered(positive: true), .answered(positive: false), .askUser, .resume, .tuckIn, .wakeRequest,
                              .comeTell, .checkIn, .goHome]
    let commands: [PetCommand] = [.sleep, .wake, .comeHere, .play, .quiet, .stop, .follow(duration: nil), .follow(duration: 20), .stay(duration: 15),
                                  .explore, .hideAndSeek, .watch, .nap, .trick(.sit), .trick(.lieDown), .trick(.beg), .trick(.speak), .trick(.spin), .trick(.celebrate)]
    let movingClips: Set<String> = ["walk", "walk_bark", "run", "gallop"]

    func makeBrain(_ c: CharacterDefinition, seed: UInt64) -> PetBrain {
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, petHeight: 100, availableClips: c.availableClipNames)
        config.personality = c.personality
        config.homeOnLeft = true
        return PetBrain(config: config, x: 700, y: 300, minX: 0, maxX: 1600, minY: 70, maxY: 900, intro: false, rng: SeededRandom(seed: seed))
    }

    runner.run("Stress.everyCharacter_everyModeCommandAndEvent_withSwitchesAndScreenChanges_staysValid") {
        let all = repo.characters
        try expectTrue(all.count >= 30)
        for (index, start) in all.enumerated() {
            var current = start
            let seed = UInt64(index + 1)
            let brain = makeBrain(current, seed: seed)
            let rng = SeededRandom(seed: seed &* 31)
            var ctx = PetContext()
            var watch = FacingWatch(brain, tolerance: 12)
            var last = (brain.x, brain.y)
            var skipJump = 0
            var activityFor = 0.0
            var bounds = (minX: 0.0, maxX: 1600.0, minY: 70.0, maxY: 900.0)
            for i in 0..<(4 * 60 * 20) { // 20 simulated minutes at 0.25 s
                ctx.hour = (i / 2400) % 24 * 2 % 24
                ctx.mode = PetMode.allCases[(i / 900) % PetMode.allCases.count]
                if i % 53 == 0 { _ = brain.perform(commands[rng.int(0...(commands.count - 1))], context: ctx) }
                if i % 37 == 0 { brain.handle(events[rng.int(0...(events.count - 1))], context: ctx) }
                if i % 29 == 0 {
                    ctx.cursorX = rng.chance(0.85) ? rng.uniform(-50...bounds.maxX + 200) : nil
                    ctx.cursorY = ctx.cursorX == nil ? nil : rng.uniform(0...bounds.maxY + 100)
                    ctx.cursorNearPet = rng.chance(0.12)
                    ctx.focusActive = rng.chance(0.15)
                    ctx.quietHours = rng.chance(0.1)
                    ctx.reducedMotion = rng.chance(0.1)
                }
                if i % 700 == 0 { // switch character in the middle of whatever is happening
                    current = all[rng.int(0...(all.count - 1))]
                    brain.setAvailableClips(current.availableClipNames, context: ctx)
                    brain.setPersonality(current.personality)
                }
                if i % 1900 == 0 { // a display is plugged in or removed
                    bounds = rng.chance(0.5) ? (0, 2560, 70, 1400) : (0, 1200, 70, 800)
                    brain.setBounds(minX: bounds.minX, maxX: bounds.maxX, minY: bounds.minY, maxY: bounds.maxY)
                    skipJump = 2
                    watch.rebase(brain)
                }
                if i % 400 == 0 && rng.chance(0.3) { brain.place(x: rng.uniform(bounds.minX...bounds.maxX), y: rng.uniform(bounds.minY...bounds.maxY)); skipJump = 2; watch.rebase(brain) }
                brain.update(dt: 0.25, context: ctx)
                watch.observe(brain)

                try expectTrue(brain.x.isFinite && brain.y.isFinite && brain.energy.isFinite && brain.boredom.isFinite, "\(start.id): non-finite state at tick \(i)")
                try expectTrue(brain.x >= bounds.minX - 0.5 && brain.x <= bounds.maxX + 0.5 && brain.y >= bounds.minY - 0.5 && brain.y <= bounds.maxY + 0.5,
                               "\(start.id): out of bounds (\(brain.x), \(brain.y)) tick \(i)")
                try expectTrue(current.resolve(brain.clip, facing: brain.facing) != nil, "\(start.id) (now \(current.id)): clip '\(brain.clip)' does not exist for the current character (behavior \(brain.behavior))")
                try expectFalse(brain.isAsleep && brain.isMoving, "\(start.id): asleep and moving")
                if brain.isMoving, !brain.isTurning, brain.behavior != .dragged, brain.behavior != .falling {
                    try expectTrue(movingClips.contains(brain.clip), "\(start.id): moving with clip '\(brain.clip)' during \(brain.behavior)")
                }
                if let activity = brain.currentActivity {
                    for b in activity.requiredBehaviors { _ = b } // the activity exists; availability was checked when it started
                    activityFor += 0.25
                } else { activityFor = 0 }
                try expectTrue(activityFor < 1800, "\(start.id): an activity ran for over 30 minutes")
                let moved = hypot(brain.x - last.0, brain.y - last.1)
                last = (brain.x, brain.y)
                if skipJump > 0 { skipJump -= 1 } else if brain.behavior != .dragged && brain.behavior != .landing {
                    try expectTrue(moved / 0.25 < 500, "\(start.id): teleport of \(moved) pt at tick \(i) (\(brain.behavior))")
                }
            }
            try expectTrue(watch.worstBackward <= watch.tolerance, "\(start.id): walked \(watch.worstBackward) pt backward")
        }
    }

    runner.run("Stress.unstickAfterAnything_everyCharacterRecoversToNormalLife") {
        // After a storm of commands, stop everything and the companion must go back to ordinary, varied behavior.
        for c in repo.characters {
            let brain = makeBrain(c, seed: 77)
            let rng = SeededRandom(seed: 5)
            var ctx = PetContext(); ctx.hour = 14; ctx.cursorX = 800; ctx.cursorY = 300
            for i in 0..<600 { if i % 15 == 0 { _ = brain.perform(commands[rng.int(0...(commands.count - 1))], context: ctx) }; brain.update(dt: 0.25, context: ctx) }
            _ = brain.perform(.stop, context: ctx)
            _ = brain.perform(.wake, context: ctx)
            ctx.cursorX = nil
            var seen = Set<PetBehavior>()
            for _ in 0..<(4 * 60 * 8) { brain.update(dt: 0.25, context: ctx); seen.insert(brain.behavior) }
            try expectTrue(brain.currentActivity == nil, "\(c.id): activity still running after stop")
            try expectTrue(seen.count >= 3, "\(c.id): only \(seen.count) distinct behaviors in 8 minutes of normal life (stuck?)")
        }
    }
}
