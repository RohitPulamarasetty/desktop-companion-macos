import Foundation

/// Which way the pet is facing / moving on screen.
public enum Facing: Int, Equatable {
    case left = -1
    case right = 1

    public var flipped: Facing { self == .left ? .right : .left }
    public var sign: Double { Double(rawValue) }
}

public enum BehaviorCategory: String, CaseIterable {
    case movement, rest, personality, interaction, productivity, timeOfDay, physics
}

/// Every PRIMARY behavior the pet can be in. Exactly one is active at a
/// time (`PetBrain.behavior` is a single value -- there is no way to be
/// "walking and sleeping" at once). Micro-animations (sleep breathing,
/// twitches) are a separate, concurrent layer -- see `MicroAnimation`.
///
/// Honest accounting: the catalog defines 65 behaviors. Each is a distinct
/// combination of clip sequence, timing, facing logic, movement pattern and
/// trigger, but they are rendered with the 16 real clips the current
/// character ships (see `Characters/biscuit-proto/manifest.json`). A handful
/// (`stretch`, `playBow`, `scratch`, `shake`, `chaseTail`, `dig`, and for
/// some characters `ponder`/`play`) need artwork a given character may not have; they are automatically excluded
/// from scheduling until a character package provides those clips, rather
/// than being faked with an unrelated animation.
public enum PetBehavior: String, CaseIterable {
    // movement
    case walk, stroll, trot, run, zoomies, explore, patrol, returnHome, followCursor, walkBark, pace
    /// Walks to an available bed object, then lies down there (Stage 10.4).
    /// No dedicated clip needed -- reuses the existing walk + lie/sleep
    /// sequence, just at the bed's position instead of wherever it happens
    /// to be standing.
    case goToBed
    // rest
    case stand, sit, lie, doze, sleep, wakeUp, naturalWake, settle, restAlert, getUp, stretch, yawn
    // personality
    case lookAround, sitLookAround, sniff, tailWag, beg, playBow, spin, barkAtNothing, sitBark,
         watchCursor, investigate, scratch, shake, chaseTail, dig, ponder, play
    // interaction
    case clickAttention, clickHappy, clickBark, petted, grumpyWake, excited, greetReturn, askUser, comeTell, checkIn
    // physics (driven by the platform's drag/fall simulation)
    case dragged, falling, landing
    // productivity
    case celebrateTask, celebrateAllDone, celebrateFocus, focusCompanion, breakPlay, waterCheer,
         reminderNudge, nudgeBreak
    // time of day / session
    case morningStretch, eveningWindDown, lateNightDrowsy, settleIn

    public var spec: BehaviorSpec { BehaviorCatalog.spec(for: self) }
    public var category: BehaviorCategory { spec.category }
    public var isSleeping: Bool { self == .sleep }
}

/// How the pet decides which way to face during a step.
public enum FacingDirective: Equatable {
    case keep
    /// Face the cursor once, at the start of the step.
    case towardCursor
    /// Keep facing the cursor for the whole step (re-evaluated each update).
    case trackCursor
    /// Glance one way then the other (flips at ~35% and ~70% of the step).
    case lookAround
}

/// Clip ids may be concrete manifest state ids, or one of these tokens,
/// resolved against the pet's current posture so e.g. "bark" uses the
/// sitting bark when it's sitting and the standing bark when standing.
public enum ClipToken {
    public static let posture = "@posture"
    public static let postureBark = "@posture_bark"
}

public struct BehaviorStep: Equatable {
    /// Preference-ordered clip ids; the first one the character provides
    /// is used. If none are available, the step is skipped.
    public let clips: [String]
    public let duration: ClosedRange<Double>
    public let facing: FacingDirective
    /// Optional steps are silently skipped if their clip is unavailable,
    /// without making the whole behavior unavailable.
    public let optional: Bool

    public init(_ clips: [String], _ duration: ClosedRange<Double>, facing: FacingDirective = .keep, optional: Bool = false) {
        self.clips = clips
        self.duration = duration
        self.facing = facing
        self.optional = optional
    }
}

public enum TargetStrategy: Equatable {
    case tiny      // 15-45pt shuffle
    case short     // ~0.6-2 pet widths
    case medium    // ~2-5 pet widths
    case long      // ~5+ pet widths
    case explore   // centre of the least-visited region of the screen
    case farSide   // the far half of the screen from where the pet is
    case home      // the pet's home spot (bottom-left)
    case cursor    // stop beside the cursor
    case cursorNear // toward the cursor, but at most a few body lengths
    /// An environment object's position, e.g. a bed (Stage 10). Read from
    /// `PetContext` exactly the way `.cursor` reads cursorX/cursorY --
    /// another plain context input, not a parallel targeting system.
    case object
}

public struct MovementSpec: Equatable {
    public let clips: [String]
    /// Speed in native sprite pixels per second (scaled to points by the
    /// platform's display scale), so a larger pet covers more ground per
    /// step and the gait never looks like it's sliding.
    public let speed: ClosedRange<Double>
    /// The speed at which the clip's authored frame rate looks right;
    /// playback rate = actual speed / nominalSpeed (prevents moonwalking).
    public let nominalSpeed: Double
    public let target: TargetStrategy
    /// Number of quick direction reversals after the first leg (zoomies).
    public let reversals: ClosedRange<Int>

    public init(_ clips: [String], speed: ClosedRange<Double>, nominal: Double, target: TargetStrategy, reversals: ClosedRange<Int> = 0...0) {
        self.clips = clips
        self.speed = speed
        self.nominalSpeed = nominal
        self.target = target
        self.reversals = reversals
    }
}

public struct BehaviorSpec {
    public let behavior: PetBehavior
    public let category: BehaviorCategory
    public let steps: [BehaviorStep]
    public let movement: MovementSpec?
    /// Behaviors queued automatically once this one completes.
    public let followUps: [PetBehavior]
    /// False for anything noisy/energetic that must not happen while the
    /// user is in a focus session or quiet hours (barks, zoomies).
    public let quiet: Bool
}

/// Micro-animation layer: runs concurrently with (on top of) whatever the
/// primary behavior is. Implemented by the platform as render-server
/// Core Animation (no per-frame work in this process).
public enum MicroAnimation: Equatable {
    case twitch
    case earFlick
}

public enum BehaviorCatalog {
    private static let walkClip = ["walk"]
    private static let walkSpeed: ClosedRange<Double> = 8.5...10.5

    public static func spec(for b: PetBehavior) -> BehaviorSpec {
        func still(_ c: BehaviorCategory, _ steps: [BehaviorStep], quiet: Bool = true, then: [PetBehavior] = []) -> BehaviorSpec {
            BehaviorSpec(behavior: b, category: c, steps: steps, movement: nil, followUps: then, quiet: quiet)
        }
        func moving(_ c: BehaviorCategory, _ m: MovementSpec, quiet: Bool = true, then: [PetBehavior] = []) -> BehaviorSpec {
            BehaviorSpec(behavior: b, category: c, steps: [], movement: m, followUps: then, quiet: quiet)
        }
        typealias S = BehaviorStep
        switch b {
        // MARK: movement
        case .walk:         return moving(.movement, MovementSpec(walkClip, speed: walkSpeed, nominal: 9.5, target: .medium))
        case .stroll:       return moving(.movement, MovementSpec(walkClip, speed: 6...7.5, nominal: 9.5, target: .short))
        case .trot:         return moving(.movement, MovementSpec(["run"], speed: 15...18, nominal: 20, target: .medium))
        case .run:          return moving(.movement, MovementSpec(["run"], speed: 20...24, nominal: 20, target: .long), quiet: false)
        case .zoomies:      return moving(.movement, MovementSpec(["gallop"], speed: 30...36, nominal: 32, target: .short, reversals: 2...3), quiet: false, then: [.stand])
        case .explore:      return moving(.movement, MovementSpec(walkClip, speed: walkSpeed, nominal: 9.5, target: .explore))
        case .patrol:       return moving(.movement, MovementSpec(walkClip, speed: walkSpeed, nominal: 9.5, target: .farSide))
        case .returnHome:   return moving(.movement, MovementSpec(walkClip, speed: walkSpeed, nominal: 9.5, target: .home))
        case .followCursor: return moving(.movement, MovementSpec(walkClip, speed: 9.5...11.5, nominal: 9.5, target: .cursor), then: [.watchCursor])
        case .goToBed:      return moving(.movement, MovementSpec(walkClip, speed: 8...10, nominal: 9.5, target: .object), then: [.lie])
        case .walkBark:     return moving(.movement, MovementSpec(["walk_bark", "walk"], speed: walkSpeed, nominal: 9.5, target: .short), quiet: false)
        case .pace:         return moving(.movement, MovementSpec(walkClip, speed: 7...9, nominal: 9.5, target: .short, reversals: 1...1))

        // MARK: rest
        case .stand:        return still(.rest, [S(["stand"], 2...5)])
        case .sit:          return still(.rest, [S(["sit"], 7...16)])
        case .lie:          return still(.rest, [S(["lie"], 9...20)])
        case .doze:         return still(.rest, [S(["lie"], 5...9), S(["yawn"], 1.6...1.6), S(["lie"], 6...10)])
        case .sleep:        return still(.rest, [S(["yawn"], 1.4...1.6, optional: true), S(["sleep"], 120...180)], then: [.naturalWake])
        case .wakeUp:       return still(.rest, [S(["yawn"], 1.6...1.6), S(["stretch"], 1.4...1.4, optional: true),
                                                 S(["sit"], 1.2...1.6, facing: .towardCursor), S(["stand"], 1.5...2.2, facing: .trackCursor)])
        case .naturalWake:  return still(.rest, [S(["yawn"], 1.6...1.6), S(["stretch"], 1.4...1.4, optional: true),
                                                 S(["sit"], 2...3.5, facing: .lookAround), S(["stand"], 1...1.8)])
        case .settle:       return still(.rest, [S(["sit"], 1...2), S(["lie"], 4...7)])
        case .restAlert:    return still(.rest, [S(["lie"], 4...7, facing: .lookAround)])
        case .getUp:        return still(.rest, [S(["sit"], 1...1.5), S(["stand"], 1...2)])
        case .stretch:      return still(.rest, [S(["stretch"], 1.4...1.4)])
        case .yawn:         return still(.rest, [S(["yawn"], 1.6...1.6)])

        // MARK: personality
        case .lookAround:   return still(.personality, [S(["look", "stand"], 3...5, facing: .lookAround)])
        case .sitLookAround: return still(.personality, [S(["sit"], 4...7, facing: .lookAround)])
        case .sniff:        return moving(.personality, MovementSpec(["sniff", "walk"], speed: 3.5...4.5, nominal: 9.5, target: .tiny))
        case .tailWag:      return still(.personality, [S(["stand"], 2.5...4.5, facing: .towardCursor)])
        case .beg:          return still(.personality, [S(["beg"], 2.5...4.5, facing: .towardCursor)])
        case .playBow:      return still(.personality, [S(["play_bow"], 1.5...2)], quiet: false)
        case .spin:         return moving(.personality, MovementSpec(["gallop"], speed: 24...28, nominal: 32, target: .tiny, reversals: 3...4), quiet: false, then: [.stand])
        case .barkAtNothing: return still(.personality, [S(["stand_bark"], 0.75...0.75), S(["stand"], 1.2...2)], quiet: false)
        case .sitBark:      return still(.personality, [S(["sit_bark"], 0.75...0.75), S(["sit"], 1.5...3)], quiet: false)
        case .watchCursor:  return still(.personality, [S(["sit"], 4...8, facing: .trackCursor)])
        case .investigate:  return moving(.personality, MovementSpec(walkClip, speed: 7...9, nominal: 9.5, target: .cursor), then: [.sitLookAround])
        case .scratch:      return still(.personality, [S(["scratch"], 2...3)])
        case .shake:        return still(.personality, [S(["shake"], 1...1.2)])
        case .chaseTail:    return still(.personality, [S(["chase_tail"], 2...3)], quiet: false)
        case .dig:          return still(.personality, [S(["dig"], 2...3)])
        case .ponder:       return still(.personality, [S(["think"], 3...6)])
        case .play:         return still(.personality, [S(["play"], 3...5, facing: .towardCursor)], quiet: false)

        // MARK: interaction
        case .clickAttention: return still(.interaction, [S([ClipToken.posture], 1.6...2.6, facing: .trackCursor)])
        case .clickHappy:   return still(.interaction, [S(["happy"], 1.6...2.2, facing: .towardCursor), S(["stand"], 1...1.5)])
        case .clickBark:    return still(.interaction, [S([ClipToken.postureBark], 0.75...0.75, facing: .towardCursor),
                                                        S([ClipToken.posture], 1.2...1.8, facing: .trackCursor)], quiet: false)
        case .petted:       return still(.interaction, [S(["happy"], 1.2...1.6, facing: .towardCursor), S(["stand"], 1.5...2.5, facing: .trackCursor)])
        case .grumpyWake:   return still(.interaction, [S(["sad", "yawn"], 1.6...1.6), S(["sleep"], 40...60)], then: [.naturalWake])
        case .excited:      return moving(.interaction, MovementSpec(["gallop"], speed: 28...34, nominal: 32, target: .short, reversals: 1...2), quiet: false, then: [.clickHappy])
        // Waits attentively (facing the user) while a question bubble is up;
        // `answered` ends it early.
        // Open-ended: the question's answer (or its own timeout) ends it.
        case .askUser:      return still(.interaction, [S(["happy", "stand"], 0.8...1.0, facing: .towardCursor), S(["stand"], 900...900, facing: .trackCursor)])
        // Walks a little toward the user before asking something important
        // ("the pet came to tell me"), then waits attentively.
        case .comeTell:     return moving(.interaction, MovementSpec(walkClip, speed: 10...12, nominal: 9.5, target: .cursorNear), then: [.askUser])
        // A rare unprompted visit after a long quiet stretch.
        case .checkIn:      return moving(.interaction, MovementSpec(walkClip, speed: 8...10, nominal: 9.5, target: .cursorNear), then: [.tailWag])
        case .greetReturn:  return moving(.interaction, MovementSpec(walkClip, speed: 10...12, nominal: 9.5, target: .cursor), then: [.tailWag])

        // MARK: physics
        case .dragged:      return still(.physics, [S(["dragged"], 3600...3600)])
        case .falling:      return still(.physics, [S(["fall"], 3600...3600)])
        case .landing:      return still(.physics, [S(["land"], 0.3...0.3), S(["stand"], 1.2...1.8, facing: .lookAround)])

        // MARK: productivity
        case .celebrateTask:    return still(.productivity, [S(["stand_bark", "stand"], 0.75...0.75, facing: .towardCursor), S(["celebrate"], 1.8...2.2)], quiet: false)
        case .celebrateAllDone: return moving(.productivity, MovementSpec(["gallop"], speed: 30...34, nominal: 32, target: .short, reversals: 2...2), quiet: false, then: [.celebrateTask])
        case .celebrateFocus:   return moving(.productivity, MovementSpec(["run"], speed: 20...23, nominal: 20, target: .short, reversals: 1...1), quiet: false, then: [.clickHappy])
        case .focusCompanion:   return still(.productivity, [S(["think", "sit"], 1.5...2, facing: .towardCursor), S(["lie"], 600...900)])
        case .breakPlay:        return moving(.productivity, MovementSpec(["run"], speed: 18...22, nominal: 20, target: .medium, reversals: 1...1), quiet: false, then: [.tailWag])
        case .waterCheer:       return still(.productivity, [S(["stand"], 0.5...0.8, facing: .towardCursor), S(["happy"], 1.4...1.8)])
        case .reminderNudge:    return still(.productivity, [S(["stand_bark", "stand"], 0.75...0.75, facing: .towardCursor), S(["stand"], 2...3, facing: .trackCursor)])
        case .nudgeBreak:       return still(.productivity, [S(["sit"], 2...3, facing: .towardCursor), S(["sit_bark", "sit"], 0.75...0.75), S(["sit"], 2...3, facing: .trackCursor)])

        // MARK: time of day / session
        case .morningStretch:   return still(.timeOfDay, [S(["yawn"], 1.6...1.6), S(["stretch"], 1.4...1.4, optional: true), S(["stand"], 2...3)])
        case .eveningWindDown:  return still(.timeOfDay, [S(["sit"], 8...14, facing: .lookAround), S(["lie"], 10...18)])
        case .lateNightDrowsy:  return still(.timeOfDay, [S(["lie"], 4...6), S(["yawn"], 1.6...1.6), S(["lie"], 5...8)])
        case .settleIn:         return still(.timeOfDay, [S(["sit"], 3...5), S(["sit"], 3...4.5, facing: .lookAround)])
        }
    }
}
