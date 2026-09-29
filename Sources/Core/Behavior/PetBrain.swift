import Foundation

// MARK: - Randomness (injectable so behavior is testable and reproducible)

public protocol RandomSource: AnyObject {
    /// Uniform in [0, 1).
    func nextUnit() -> Double
}

/// SplitMix64 -- tiny, fast, fully deterministic for a given seed.
public final class SeededRandom: RandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

extension RandomSource {
    public func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }
    public func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + min(range.upperBound - range.lowerBound, Int(nextUnit() * Double(range.upperBound - range.lowerBound + 1)))
    }
    public func chance(_ p: Double) -> Bool { nextUnit() < p }
}

// MARK: - Inputs / outputs

/// Everything the brain is allowed to know about the world. All local,
/// all cheap to compute; no content, titles or keystrokes.
public struct PetContext {
    public var hour: Int = 12
    public var userIdleSeconds: Double = 0
    public var quietHours = false
    /// Cursor X in the same coordinate space as the pet's `x` (screen
    /// points), or nil when it's on another display / unknown.
    public var cursorX: Double?
    public var cursorY: Double?
    public var cursorNearPet = false
    /// From AppSettings.activityLevel (calm 0.6 / normal 1 / energetic 1.6).
    public var activityMultiplier: Double = 1
    public var reducedMotion = false
    /// User-selected companion mode. `.normal` changes nothing.
    public var mode: PetMode = .normal
    /// True when the machine is genuinely low on battery and not plugged
    /// in. A single input into the
    /// existing scoring model -- dampens high-energy behaviors -- never a
    /// parallel system, and never anything the app collects or transmits.
    public var batteryLow = false
    /// Minutes of continuous active use without a break, mirroring what already drives the screen-break reminder so
    /// PetBrain can lean the same way ambiently, not just via the reminder
    /// toast.
    public var continuousActiveMinutes: Double = 0
    /// How familiar the companion has grown with this user, 0...1. Defaults to 1 -- fully
    /// familiar -- so omitting it (every existing test, every caller that
    /// predates this field) behaves exactly as before. The app derives it
    /// from `ProgressionStore.daysTogether`, gradually reaching 1 over the
    /// companion's first couple of weeks; it is never an RPG stat, never
    /// shown as a number to the user, and never gates any capability --
    /// it only scales how fast affection warms up per interaction.
    public var familiarity: Double = 1
    /// Position of the nearest available bed object, if the environment
    /// has one. Read exactly like `cursorX`/`cursorY` -- a
    /// plain optional input, nil when no bed exists or none is available,
    /// never a separate subsystem PetBrain has to track itself.
    public var bedX: Double?
    public var bedY: Double?

    public init() {}
}

public enum PetEvent: Equatable {
    case click
    case doubleClick
    case dragBegan
    case dropped
    case landed
    case userReturned(awaySeconds: Double)
    case cursorApproached
    case morningGreeting
    /// The app is asking the user something through the pet (water, break):
    /// the pet stops, turns to the user and waits attentively.
    case askUser
    /// Release the pet from `.askUser` (a menu closed, the user moved on).
    case resume
    /// Menu "Sleep": lie down and nap now. / Menu "Wake up".
    case tuckIn
    case wakeRequest
    /// Like `askUser`, but for something important: the pet first walks a
    /// little toward the user, then waits attentively.
    case comeTell
    /// A rare unprompted visit ("Hey… how's it going?").
    case checkIn
    /// "Bring home": walk (never slide) back to the home spot.
    case goHome
}

/// Structured short-term memory. Each field is the
/// brain's `clock` value (seconds since this session started, not wall
/// time) when that kind of thing last happened, or nil if it never has.
/// `elapsedSince*` helpers below convert that into "how long ago" at a
/// given clock reading. Deliberately flat and bounded -- one fact per
/// kind of event, always overwritten, never a growing history.
public struct InteractionMemory: Equatable {
    public var lastInteractionAt: Double?
    public var lastCommand: PetCommand?
    public var lastCommandAt: Double?
    public var lastPlayAt: Double?
    public var lastSleepAt: Double?
    public var lastApproachAt: Double?

    public init() {}

    private func elapsed(since t: Double?, now: Double) -> Double? { t.map { max(0, now - $0) } }
    public func secondsSinceLastInteraction(now: Double) -> Double? { elapsed(since: lastInteractionAt, now: now) }
    public func secondsSinceLastPlay(now: Double) -> Double? { elapsed(since: lastPlayAt, now: now) }
    public func secondsSinceLastSleep(now: Double) -> Double? { elapsed(since: lastSleepAt, now: now) }
    public func secondsSinceLastApproach(now: Double) -> Double? { elapsed(since: lastApproachAt, now: now) }
}

/// A light, readable summary of the pet's inner state (for copy and the
/// dashboard). Derived from the internal drives; not a game mechanic.
public enum PetMood: String, CaseIterable {
    case happy, calm, curious, sleepy, playful, annoyed, excited

    public var label: String {
        switch self {
        case .happy: return "Happy 😊"
        case .calm: return "Calm"
        case .curious: return "Curious 👀"
        case .sleepy: return "Sleepy 💤"
        case .playful: return "Playful ✨"
        case .annoyed: return "Annoyed 😒"
        case .excited: return "Excited 🎉"
        }
    }
}

public struct PetEventOutcome: Equatable {
    public var woke = false
    public var barked = false
    public var ignored = false
}

public struct PetStats: Equatable {
    public var clicks = 0
    public var barks = 0
    public var naps = 0
    public var sleepSeconds: Double = 0
    public var walkedPoints: Double = 0
    public var celebrations = 0
    public init() {}
}

// MARK: - Easing

/// The single easing curve shared by the brain (to know where the pet is)
/// and the renderer (Core Animation `CAMediaTimingFunction(controlPoints:)`
/// with the same control points), so logic and visuals agree exactly.
public enum MovementEasing {
    /// Cubic bezier (0.3, 0, 0.7, 1): a short accelerate, cruise, a short decelerate
    /// (long legs would otherwise crawl for seconds before reaching speed).
    public static let controlPoints: (Float, Float, Float, Float) = (0.3, 0, 0.7, 1)

    /// Progress (0...1) at normalized time t (0...1).
    public static func progress(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        let (x1, y1, x2, y2) = (Double(controlPoints.0), Double(controlPoints.1), Double(controlPoints.2), Double(controlPoints.3))
        func bez(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u
        }
        // Solve bez_x(u) = t by bisection (monotonic for these points).
        var lo = 0.0, hi = 1.0, u = t
        for _ in 0..<30 {
            u = (lo + hi) / 2
            if bez(u, x1, x2) < t { lo = u } else { hi = u }
        }
        return bez(u, y1, y2)
    }
}

/// One planned straight-line movement. The pet's position during a leg is
/// a pure function of time, so the renderer can hand the whole leg to the
/// render server instead of stepping it every tick.
public struct MovementLeg: Equatable {
    public let fromX: Double, fromY: Double, toX: Double, toY: Double
    public let duration: Double
    public var elapsed: Double
    /// Constant-speed leg (no ease in/out): used when a leg continues an
    /// already-moving pet (following the cursor) so it never stops and
    /// restarts between legs.
    public let linear: Bool
    public init(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double, elapsed: Double, linear: Bool = false) {
        self.fromX = fromX; self.fromY = fromY; self.toX = toX; self.toY = toY
        self.duration = duration; self.elapsed = elapsed; self.linear = linear
    }
    public var distance: Double { ((toX - fromX) * (toX - fromX) + (toY - fromY) * (toY - fromY)).squareRoot() }
    public var remaining: Double { max(0, duration - elapsed) }
    public func position(at elapsed: Double) -> (Double, Double) {
        let t = duration > 0 ? elapsed / duration : 1
        let p = linear ? min(max(t, 0), 1) : MovementEasing.progress(t)
        return (fromX + (toX - fromX) * p, fromY + (toY - fromY) * p)
    }
}

/// Per-character temperament (from the character package). Subtle
/// multipliers on the same behavior engine -- never separate logic.
public struct Personality: Equatable {
    /// > 1 = lingers longer in calm poses, naps more.
    public var restfulness: Double = 1
    /// > 1 = roams more often.
    public var roaming: Double = 1
    /// > 1 = reacts (vocal/happy/cursor) more readily.
    public var reactivity: Double = 1
    /// > 1 = more idle thoughts (used by the app's message scheduler).
    public var chattiness: Double = 1
    /// > 1 = rests at a higher baseline curiosity and explores/investigates
    /// more readily; < 1 settles for a calmer resting curiosity.
    public var curiosity: Double = 1
    /// > 1 = warms up faster per interaction and settles at a higher
    /// resting affection baseline; < 1 stays more reserved.
    public var affection: Double = 1
    /// > 1 = plays, zooms and begs more; < 1 is more sedate.
    public var playfulness: Double = 1
    public var trait: String = "friendly"
    public init() {}
}

// MARK: - Brain

/// The pet's behavior scheduler ("pet brain"). Platform-independent and
/// deterministic given a `RandomSource`; everything is unit tested.
///
///  - exactly one PRIMARY behavior at a time (`behavior`)
///  - true 2-D life: position (x, y) anywhere in the display's usable area,
///    movement as eased legs toward 2-D targets (turn -> accelerate ->
///    travel -> decelerate -> arrive), no floor, no leash
///  - energy rhythm: roam -> pause -> sit -> lie down -> sleep (2-3 min,
///    only a user action wakes it) -> yawn/wake -> look around -> roam
///  - event reactions (click, drag, tasks, focus, water, break, ...)
///  - a concurrent micro-animation layer (sleep twitch, ear flick)
public final class PetBrain {
    public struct Config {
        public var pointsPerPixel: Double
        public var petWidth: Double
        public var petHeight: Double
        public var availableClips: Set<String>
        public var barkProbability: Double = 0.35
        public var barkCooldown: Double = 10
        /// Which corner is "home" (start/preferred spot, not a leash).
        public var homeOnLeft = true
        public var personality = Personality()
        /// "Follow cursor" preference: 0 = off, 0.4 = rare, 1 = occasional.
        public var cursorInterest: Double = 1
        public init(pointsPerPixel: Double, petWidth: Double, petHeight: Double? = nil, availableClips: Set<String>) {
            self.pointsPerPixel = pointsPerPixel
            self.petWidth = petWidth
            self.petHeight = petHeight ?? petWidth
            self.availableClips = availableClips
        }
    }

    public private(set) var config: Config
    public private(set) var behavior: PetBehavior
    public private(set) var clip: String = "stand"
    public private(set) var facing: Facing
    /// Pet's bottom-left corner, screen points.
    public private(set) var x: Double
    public private(set) var y: Double
    public private(set) var minX: Double, maxX: Double, minY: Double, maxY: Double
    public private(set) var energy: Double
    public private(set) var isMoving = false
    /// The current movement leg (nil while turning in place or not moving).
    public private(set) var leg: MovementLeg?
    /// Incremented whenever a leg starts, is re-planned or ends.
    public private(set) var legRevision = 0
    /// Animation playback-rate multiplier so the gait matches ground speed.
    public private(set) var playbackRate: Double = 1
    public private(set) var stats = PetStats()
    public private(set) var clock: Double = 0
    public private(set) var visualRevision = 0
    public private(set) var behaviorRevision = 0
    public private(set) var timeInBehavior: Double = 0
    /// Short-term memory: the last several *autonomously chosen* primary
    /// behaviors, most recent last. Used by `chooseNext` to penalize
    /// repetition (walk/walk/walk/walk or sit/sit/sit/sit) with a graduated
    /// weight, not just a one-step-back halving. Capped, not persisted --
    /// this is working memory for "what have I been doing," not a log.
    public private(set) var recentBehaviors: [PetBehavior] = []
    private static let recentBehaviorsCapacity = 6
    /// Structured short-term memory: a handful of
    /// "when did X last happen" facts, distinct from `recentBehaviors`
    /// (which is about *what* was chosen, for repetition avoidance). This
    /// is about *when* specific kinds of things last happened, for future
    /// behavior/message logic to reference (e.g. "it's been a while since
    /// we played"). Deliberately just timestamps + light labels, not a
    /// growing log -- bounded by construction, nothing to prune.
    public private(set) var memory = InteractionMemory()
    /// Lets `PetCommand.perform` (a different file, same module) record a
    /// handled command without widening `memory`'s setter access.
    func recordCommandInMemory(_ command: PetCommand) {
        memory.lastCommand = command
        memory.lastCommandAt = clock
    }
    /// True while the pet is asleep (the platform shows 💤, slows its timer).
    public var isAsleep: Bool { clip == "sleep" }

    // Internal drives (0...1). Simple, deterministic, gently changing.
    /// Rises while nothing happens; falls with interaction, play, exploring.
    public private(set) var boredom: Double = 0.2
    /// Rises with clicks and petting; slowly fades.
    public private(set) var affection: Double = 0.5
    /// Temperament-based wish to explore; nudged by random drift.
    public private(set) var curiosity: Double = 0.5
    private var excitedUntil: Double = -1
    /// Set when the pet has been woken or clicked at too much; fades on its
    /// own (`annoyedDuration`) and is soothed by a gentle double-click.
    private var annoyedUntil: Double = -1
    public static let annoyedDuration: Double = 120
    public var isAnnoyed: Bool { clock < annoyedUntil }

    /// The mood the pet is in right now (derived; see `PetMood`).
    public func mood(_ ctx: PetContext) -> PetMood {
        if isAsleep || behavior == .doze || energy < 0.25 { return .sleepy }
        if clock < annoyedUntil { return .annoyed }
        if clock < excitedUntil { return .excited }
        if energy > 0.7 && affection > 0.6 { return .playful }
        if curiosity > 0.65 || behavior == .explore || behavior == .investigate { return .curious }
        if affection > 0.55 { return .happy }
        return .calm
    }

    public var onBehaviorChange: ((PetBehavior, PetBehavior) -> Void)?
    public var onActivityStarted: ((Activity) -> Void)?

    private let rng: RandomSource
    private var steps: [BehaviorStep] = []
    private var stepIndex = 0
    private var stepElapsed: Double = 0
    private var stepDuration: Double = 0
    private var lookFlipsDone = 0
    private var queue: [PetBehavior] = []
    private var posture = "sit"

    private var movement: MovementSpec?
    private var moveClip = "walk"
    private var targetX: Double = 0
    private var targetY: Double = 0
    private var speed: Double = 0
    private var reversalsLeft = 0
    private var turnPause: Double = 0
    private var lastFollowReplan: Double = -1
    /// True while the pet is turning in place before a leg.
    public var isTurning: Bool { turnPause > 0 }

    /// Coarse 2-D visit history (4 columns x 3 rows) for exploring.
    private var visits = [Double](repeating: 0, count: 12)
    private var lastBarkAt = -Double.infinity
    private var lastCursorReactionAt = -Double.infinity
    private var clickTimes: [Double] = []
    private var wakeTimes: [Double] = []
    /// Escalation state for repeated rapid-click bursts while awake: a single burst reads as playful (`.excited`); several
    /// bursts in quick succession read as the character having had enough
    /// -- reusing `.grumpyWake` (already used for "poked awake too much")
    /// rather than inventing an "annoyed" clip no character actually ships.
    private var excitedStreak = 0
    private var lastExcitedAt = -Double.infinity
    private var nextMicroAt: Double = 0
    private var sleepLockUntil: Double = 0
    private var pendingMicro: MicroAnimation?
    // MARK: Activities
    //
    // Activities are user-started (menu / shortcut / PetCommand) and run
    // *through* the normal behavior scheduler: follow-style activities
    // override `chooseNext` while they last; scripted ones (explore, hide
    // and seek, come here, play's finale) queue ordinary behaviors and end
    // when the queue drains. Every activity has a hard deadline so none can
    // linger, and `stopActivity` always returns to ambient behavior.

    public private(set) var currentActivity: Activity?
    public private(set) var activityStartedAt: Double = 0
    private var activityEndsAt: Double = .infinity
    private var activityCooldownUntil: [Activity: Double] = [:]
    /// Number of times each activity was started (favorite activity, dashboard).
    public private(set) var activityCounts: [Activity: Int] = [:]
    private var scriptActive = false
    private var playCatches = 0
    private var playLastNear = false
    private let playCatchGoal = 3
    private enum HidePhase { case hiding, waiting }
    private var hidePhase: HidePhase?
    private var hideWaitStartedAt: Double = 0
    private let hideWaitLimit: Double = 40

    /// True while a follow-style activity (follow cursor / play) is running.
    public var isFollowing: Bool { currentActivity == .followCursor || currentActivity == .play }
    /// True while a Stay activity is running.
    public var isStaying: Bool { currentActivity == .stay }
    public var isHidden: Bool { hidePhase == .waiting }
    public var playCatchCount: Int { playCatches }

    public func availability(of activity: Activity, context ctx: PetContext) -> ActivityAvailability {
        if !activity.requiredBehaviors.allSatisfy({ isAvailable($0) }) { return .unsupported }
        if activity.needsCursor, ctx.cursorX == nil { return .needsCursor }
        if let until = activityCooldownUntil[activity], clock < until { return .cooldown(seconds: until - clock) }
        if behavior == .dragged || behavior == .falling { return .unsupported }
        return .available
    }

    /// Starts an activity if it is available. Sleeping pets are woken by
    /// the user's request first (the menu offers activities while asleep).
    @discardableResult
    public func startActivity(_ activity: Activity, duration: Double? = nil, context ctx: PetContext) -> ActivityAvailability {
        let avail = availability(of: activity, context: ctx)
        guard avail == .available else { return avail }
        if currentActivity != nil { endActivity(cooldown: false) }
        let asleep = isAsleep || behavior == .doze
        currentActivity = activity
        activityStartedAt = clock
        activityCounts[activity, default: 0] += 1
        onActivityStarted?(activity)
        memory.lastInteractionAt = clock
        let length = duration ?? activity.defaultDuration
        activityEndsAt = length.map { clock + max(1, $0) } ?? .infinity
        scriptActive = false
        hidePhase = nil
        queue.removeAll()
        if asleep { energy = max(energy, 0.7); sleepLockUntil = clock + 60 }
        switch activity {
        case .followCursor:
            start(.followCursor, ctx)
        case .comeHere:
            scriptActive = true
            start(.comeHere, ctx)
        case .play:
            playCatches = 0
            playLastNear = false
            boredom = 0
            memory.lastPlayAt = clock
            start(.excited, ctx)
        case .explore:
            scriptActive = true
            queue = [.sniff, .explore, .lookAround, .explore, .sitLookAround]
            start(.explore, ctx)
        case .hideAndSeek:
            scriptActive = true
            hidePhase = .hiding
            start(.hide, ctx)
        case .stay:
            start(posture == "lie" ? .lie : .sit, ctx)
        }
        return .available
    }

    /// Ends whatever activity is running and returns to ambient behavior at
    /// the next natural break (a moving pet finishes its current leg).
    public func stopActivity(context ctx: PetContext) {
        guard currentActivity != nil else { return }
        let hiding = hidePhase != nil
        endActivity(cooldown: true)
        if behavior == .hideWait || (hiding && !isMoving) { start(.getUp, ctx) }
    }

    private func endActivity(cooldown: Bool) {
        guard let a = currentActivity else { return }
        if cooldown { activityCooldownUntil[a] = clock + a.cooldown }
        currentActivity = nil
        activityEndsAt = .infinity
        scriptActive = false
        hidePhase = nil
        queue.removeAll()
    }

    /// Where to pursue while following: the cursor position clamped to the
    /// pet's safe area, or nil without a cursor.
    private func followTarget(_ ctx: PetContext) -> (Double, Double)? {
        guard ctx.cursorX != nil else { return nil }
        return pickTarget(.cursor, ctx)
    }

    private func tickActivity(_ ctx: PetContext) {
        guard let a = currentActivity else { return }
        if clock >= activityEndsAt {
            let hiding = hidePhase == .waiting
            endActivity(cooldown: true)
            if hiding { start(.clickBark, ctx) }
            return
        }
        switch a {
        case .play:
            if ctx.cursorNearPet, !playLastNear {
                playCatches += 1
                if playCatches >= playCatchGoal {
                    endActivity(cooldown: true)
                    excitedUntil = clock + 60
                    affection = min(1, affection + 0.1 * config.personality.affection)
                    queue = [.zoomies, .tailWag]
                    start(.excited, ctx)
                }
            }
            playLastNear = ctx.cursorNearPet
        case .hideAndSeek:
            if hidePhase == .waiting {
                if ctx.cursorNearPet { foundWhileHiding(ctx) }
                else if clock - hideWaitStartedAt > hideWaitLimit {
                    endActivity(cooldown: true)
                    queue = [.clickBark, .comeHere]
                    start(.getUp, ctx)
                }
            }
        case .followCursor:
            if ctx.cursorX == nil, isMoving == false, behavior == .followWatch { /* waits until the cursor is back */ }
        default:
            break
        }
    }

    private func foundWhileHiding(_ ctx: PetContext) {
        endActivity(cooldown: true)
        excitedUntil = clock + 60
        affection = min(1, affection + 0.08 * config.personality.affection)
        queue = [.excited]
        start(.clickBark, ctx)
    }

    public init(config: Config, x: Double, y: Double = 0, minX: Double, maxX: Double, minY: Double = 0, maxY: Double = 0,
                facing: Facing = .right, energy: Double = 0.55, intro: Bool = true, rng: RandomSource) {
        self.config = config
        self.minX = minX
        self.maxX = max(minX, maxX)
        self.minY = minY
        self.maxY = max(minY, maxY)
        self.x = min(max(x, minX), max(minX, maxX))
        self.y = min(max(y, minY), max(minY, maxY))
        self.facing = facing
        self.energy = min(max(energy, 0), 1)
        self.rng = rng
        self.behavior = .settleIn
        if intro {
            // Launch choreography: sit quietly, look around, walk away,
            // come back home, sit. Then the energy rhythm takes over.
            queue = [.lookAround, .walk, .returnHome, .sit]
        }
        start(.settleIn, PetContext())
    }

    // MARK: Public API

    private var homeInset: Double { min(config.petWidth * 0.2, (maxX - minX) / 4) }
    public var homeX: Double { config.homeOnLeft ? minX + homeInset : maxX - homeInset }
    public var homeY: Double { minY }

    public func setBarkProbability(_ p: Double) { config.barkProbability = min(max(p, 0), 1) }
    public func setHomeOnLeft(_ left: Bool) { config.homeOnLeft = left }
    public func setPersonality(_ p: Personality) { config.personality = p }
    public func setCursorInterest(_ v: Double) { config.cursorInterest = min(max(v, 0), 1) }
    public var posturePublic: String { posture }
    public var queuedBehaviors: [PetBehavior] { queue }

    public func isAvailable(_ b: PetBehavior) -> Bool {
        let spec = b.spec
        if let m = spec.movement {
            return m.clips.contains(where: config.availableClips.contains)
        }
        for step in spec.steps where !step.optional {
            if resolveClip(step.clips) == nil { return false }
        }
        return !spec.steps.isEmpty
    }

    public var availableBehaviors: [PetBehavior] { PetBehavior.allCases.filter(isAvailable) }

    /// 1-D convenience (tests, legacy callers): keeps the current y range.
    public func setBounds(minX newMin: Double, maxX newMax: Double) {
        setBounds(minX: newMin, maxX: newMax, minY: minY, maxY: maxY)
    }

    /// The platform recomputes these from the full pet frame vs. the display's
    /// visible frame whenever screens/Dock/size change. The pet is clamped in
    /// place (never sent home) and an active leg is re-planned to its clamped
    /// target.
    public func setBounds(minX nx: Double, maxX mx: Double, minY ny: Double, maxY my: Double) {
        minX = nx; maxX = max(nx, mx); minY = ny; maxY = max(ny, my)
        x = clampX(x); y = clampY(y)
        if isMoving, leg != nil {
            targetX = clampX(targetX); targetY = clampY(targetY)
            planLeg()
        }
    }

    /// Hard placement: after a drag/drop, a display change, or to sync the
    /// brain to where the renderer actually shows the pet. Cancels any leg
    /// (the caller is about to change behavior or has moved the pet itself).
    public func place(x nx: Double, y ny: Double? = nil) {
        x = clampX(nx)
        if let ny { y = clampY(ny) }
        if leg != nil {
            if isMoving { targetX = clampX(targetX); targetY = clampY(targetY); planLeg() }
        }
    }

    public func setAvailableClips(_ clips: Set<String>, context ctx: PetContext) {
        config.availableClips = clips
        if !isAvailable(behavior) {
            start(isAvailable(.stand) ? .stand : .sit, ctx)
            return
        }
        if isMoving, let m = movement {
            moveClip = m.clips.first(where: clips.contains) ?? moveClip
            if turnPause <= 0 { setClip(moveClip) }
        } else if stepIndex < steps.count {
            if let c = resolveClip(steps[stepIndex].clips) {
                setClip(c)
            } else {
                steps = steps.filter { resolveClip($0.clips) != nil }
                beginStep(min(stepIndex, steps.count), ctx)
            }
        }
        visualRevision += 1
    }

    public func setScale(pointsPerPixel: Double, petWidth: Double, petHeight: Double? = nil) {
        config.pointsPerPixel = pointsPerPixel
        config.petWidth = petWidth
        if let petHeight { config.petHeight = petHeight }
    }

    public func takeMicroAnimation() -> MicroAnimation? {
        defer { pendingMicro = nil }
        return pendingMicro
    }

    /// Seconds until the brain next needs an update to make a decision
    /// (step end, turn end, leg arrival, micro-animation). The platform
    /// schedules its timer from this instead of polling.
    public var nextEventIn: Double {
        var t: Double
        if turnPause > 0 { t = turnPause }
        else if let leg { t = leg.remaining }
        else { t = max(0, stepDuration - stepElapsed) }
        if ["sleep", "lie", "sit"].contains(clip), nextMicroAt > clock { t = min(t, nextMicroAt - clock) }
        return max(0.02, t)
    }

    /// Advance the brain by `dt` seconds.
    public func update(dt rawDT: Double, context ctx: PetContext) {
        guard rawDT > 0 else { return }
        clock += rawDT
        timeInBehavior += rawDT
        updateEnergy(dt: rawDT)
        updateDrives(dt: rawDT)
        recordVisit(dt: min(rawDT, 5))
        scheduleMicro()
        tickActivity(ctx)

        if isMoving {
            stepMovement(dt: rawDT, ctx)
            return
        }
        stepElapsed += rawDT
        applyContinuousFacing(ctx)
        var guardCount = 0
        while !isMoving && stepElapsed >= stepDuration && guardCount < 8 {
            let overflow = stepElapsed - stepDuration
            beginStep(stepIndex + 1, ctx)
            stepElapsed = min(overflow, stepDuration)
            guardCount += 1
        }
    }

    @discardableResult
    public func handle(_ event: PetEvent, context ctx: PetContext) -> PetEventOutcome {
        var outcome = PetEventOutcome()
        let barksBefore = stats.barks
        let asleep = behavior == .sleep || behavior == .doze || (behavior == .grumpyWake && clip == "sleep")
        let beingHandled = behavior == .dragged || behavior == .falling

        switch event {
        case .dragBegan:
            start(.dragged, ctx)
            return outcome
        case .dropped, .landed:
            // Wherever it's put down is where it stays: a brief settle, a
            // look around, then it carries on living from that spot.
            start(.landing, ctx)
            return outcome
        default:
            break
        }
        if beingHandled { outcome.ignored = true; return outcome }

        // Hide & seek: clicking the crouching pet is "found you".
        if hidePhase == .waiting, event == .click || event == .doubleClick {
            memory.lastInteractionAt = clock
            stats.clicks += 1
            foundWhileHiding(ctx)
            outcome.barked = true
            return outcome
        }

        // Structured short-term memory: record *when*
        // kinds of things happen, separate from deciding *what* happens
        // below. Never gates or changes behavior -- purely observational.
        switch event {
        case .click, .doubleClick, .comeTell, .checkIn, .askUser:
            memory.lastInteractionAt = clock
        default: break
        }
        switch event {
        case .comeTell, .cursorApproached:
            memory.lastApproachAt = clock
        default: break
        }

        let react = config.personality.reactivity
        switch event {
        case .click:
            stats.clicks += 1
            affection = min(1, affection + 0.08 * config.personality.affection * ctx.familiarity)
            // A familiar, affectionate companion settles a little
            // faster when petted -- small (up to +30% relief at full
            // familiarity for the most affectionate dial), reusing the
            // same normalized fDelta the approach boost above uses, not a
            // second unrelated formula.
            let fDeltaClick = max(0, ctx.familiarity - 0.4) / 0.6
            boredom = max(0, boredom - 0.3 * (1 + fDeltaClick * 0.3 * config.personality.affection))
            clickTimes = clickTimes.filter { clock - $0 < 3 } + [clock]
            if asleep {
                wakeTimes = wakeTimes.filter { clock - $0 < 900 } + [clock]
                outcome.woke = true
                if wakeTimes.count >= 3 {
                    annoyedUntil = clock + Self.annoyedDuration
                    start(.grumpyWake, ctx)
                } else {
                    wake(ctx)
                }
            } else if clickTimes.count >= 4, !ctx.reducedMotion, isAvailable(.excited) {
                clickTimes.removeAll()
                excitedStreak = (clock - lastExcitedAt < 8) ? excitedStreak + 1 : 1
                lastExcitedAt = clock
                if excitedStreak >= 3, isAvailable(.grumpyWake) {
                    excitedStreak = 0
                    annoyedUntil = clock + Self.annoyedDuration
                    start(.grumpyWake, ctx)
                } else {
                    start(.excited, ctx)
                }
            } else if canBark(ctx), rng.chance(min(1, config.barkProbability * react)), isAvailable(.clickBark) {
                start(.clickBark, ctx)
            } else {
                var options: [(PetBehavior, Double)] = [(.clickAttention, 0.55)]
                if posture != "lie" {
                    options.append((.clickHappy, 0.25 * react))
                    options.append((.tailWag, 0.2))
                }
                start(pick(options) ?? .clickAttention, ctx)
            }
        case .doubleClick:
            affection = min(1, affection + 0.12 * config.personality.affection * ctx.familiarity)
            if isAnnoyed { annoyedUntil = min(annoyedUntil, clock + 15) } // a gentle pat soothes
            if asleep { outcome.woke = true; queue = [.petted]; wake(ctx) }
            else { start(.petted, ctx) }
        case .wakeRequest:
            if asleep { outcome.woke = true; wake(ctx) } else { outcome.ignored = true }
        case .tuckIn:
            if asleep { outcome.ignored = true } else {
                endActivity(cooldown: false)
                sleepLockUntil = 0
                energy = min(energy, 0.3)
                queue = [.sleep]
                start(posture == "lie" ? .lie : .settle, ctx)
            }
        case .askUser:
            if asleep { outcome.woke = true; queue = [.askUser]; wake(ctx) } else { start(.askUser, ctx) }
        case .resume:
            if behavior == .askUser { start(.lookAround, ctx) } else { outcome.ignored = true }
        case .comeTell:
            if asleep { outcome.woke = true; queue = [.comeTell]; wake(ctx) }
            else if ctx.cursorX != nil, isAvailable(.comeTell) { start(.comeTell, ctx) }
            else { start(.askUser, ctx) }
        case .checkIn:
            if asleep || isMoving || ctx.cursorX == nil { outcome.ignored = true } else {
                affection = min(1, affection + 0.05 * config.personality.affection)
                start(.checkIn, ctx)
            }
        case .goHome:
            endActivity(cooldown: false)
            start(.returnHome, ctx)
        case .userReturned(let away):
            if asleep || away < 300 { outcome.ignored = true }
            else if ctx.cursorX != nil { start(.greetReturn, ctx) }
            else { start(.tailWag, ctx) }
        case .cursorApproached:
            let calm = !isMoving && (behavior.category == .rest || behavior.category == .personality)
            if !asleep, calm, clock - lastCursorReactionAt > 20, rng.chance(min(0.9, 0.35 * react * config.personality.reactivity * config.cursorInterest)) {
                lastCursorReactionAt = clock
                start(posture == "stand" ? .clickAttention : .watchCursor, ctx)
            } else {
                outcome.ignored = true
            }
        case .morningGreeting:
            if asleep { outcome.ignored = true } else { start(.morningStretch, ctx) }
        case .dragBegan, .dropped, .landed:
            break
        }
        outcome.barked = stats.barks > barksBefore
        return outcome
    }

    private func wake(_ ctx: PetContext) {
        energy = max(energy, 0.7)
        sleepLockUntil = clock + 180
        start(.wakeUp, ctx)
    }

    // MARK: Behavior lifecycle

    private func start(_ requested: PetBehavior, _ ctx: PetContext) {
        var b = requested
        if !isAvailable(b) { b = isAvailable(.stand) ? .stand : (availableBehaviors.first ?? .stand) }
        if ctx.reducedMotion {
            switch b {
            case .zoomies, .run, .spin, .excited, .hide: b = .walk
            default: break
            }
            if !isAvailable(b) { b = .stand }
        }
        let old = behavior
        behavior = b
        recentBehaviors.append(b)
        if recentBehaviors.count > Self.recentBehaviorsCapacity { recentBehaviors.removeFirst() }
        behaviorRevision += 1
        timeInBehavior = 0
        if leg != nil || isMoving { legRevision += 1 }
        isMoving = false
        leg = nil
        turnPause = 0
        playbackRate = 1
        movement = nil
        let spec = b.spec
        if b == .sleep { stats.naps += 1; memory.lastSleepAt = clock }
        if b == .play || b == .petted { memory.lastPlayAt = clock }
        // Also covers the autonomous curious-approach path (chooseNext
        // picking .followCursor/.investigate on its own), not just the
        // explicit .comeTell/.cursorApproached events handled above --
        // otherwise the memory-based approach cooldown below could never
        // actually engage for the behavior it's meant to pace out.
        if b == .followCursor || b == .investigate || b == .comeHere { memory.lastApproachAt = clock }
        if b == .excited { excitedUntil = clock + 60; stats.celebrations += 1 }
        if b == .hideWait, currentActivity == .hideAndSeek { hidePhase = .waiting; hideWaitStartedAt = clock }
        onBehaviorChange?(old, b)

        if let m = spec.movement {
            beginMovement(m, ctx)
        } else {
            steps = spec.steps.filter { resolveClip($0.clips) != nil }
            beginStep(0, ctx)
        }
    }

    private func finish(_ ctx: PetContext) {
        let spec = behavior.spec
        // Follow-style activities keep the pet pursuing the cursor: walk when
        // it is away, pause briefly (facing it) when it is close.
        if isFollowing, hidePhase == nil {
            queue.removeAll()
            if let t = followTarget(ctx), hypot(t.0 - x, t.1 - y) > config.petWidth * 0.45 {
                start(.followCursor, ctx)
            } else {
                start(.followWatch, ctx)
            }
            return
        }
        if !spec.followUps.isEmpty { queue.insert(contentsOf: spec.followUps, at: 0) }
        if scriptActive, queue.isEmpty, hidePhase == nil { endActivity(cooldown: true) }
        var next: PetBehavior
        if !queue.isEmpty {
            next = queue.removeFirst()
            if !next.spec.quiet && ctx.quietHours { next = chooseNext(ctx) }
        } else {
            next = chooseNext(ctx)
        }
        start(next, ctx)
    }

    private func beginStep(_ index: Int, _ ctx: PetContext) {
        guard index < steps.count else { finish(ctx); return }
        stepIndex = index
        stepElapsed = 0
        lookFlipsDone = 0
        let step = steps[index]
        var d = rng.uniform(step.duration)
        // Temperament: calm characters linger in quiet poses (never
        // stretches sleep itself or scripted reactions).
        if ["stand", "sit", "lie", "look"].contains(step.clips.first ?? ""),
           behavior.category == .rest || behavior.category == .personality, behavior != .sleep {
            d *= config.personality.restfulness
        }
        stepDuration = max(0.05, d)
        if let c = resolveClip(step.clips) { setClip(c) }
        switch step.facing {
        case .towardCursor, .trackCursor: faceCursor(ctx)
        case .keep, .lookAround: break
        }
    }

    private func applyContinuousFacing(_ ctx: PetContext) {
        guard stepIndex < steps.count else { return }
        switch steps[stepIndex].facing {
        case .trackCursor:
            faceCursor(ctx)
        case .lookAround:
            let progress = stepElapsed / stepDuration
            if lookFlipsDone == 0 && progress >= 0.35 { setFacing(facing.flipped); lookFlipsDone = 1 }
            if lookFlipsDone == 1 && progress >= 0.7 { setFacing(facing.flipped); lookFlipsDone = 2 }
        default:
            break
        }
    }

    private func faceCursor(_ ctx: PetContext) {
        guard let cx = ctx.cursorX else { return }
        let center = x + config.petWidth / 2
        let dead = config.petWidth * 0.15
        if cx > center + dead { setFacing(.right) } else if cx < center - dead { setFacing(.left) }
    }

    // MARK: Movement (2-D legs)

    private func beginMovement(_ m: MovementSpec, _ ctx: PetContext) {
        movement = m
        moveClip = m.clips.first(where: config.availableClips.contains) ?? "walk"
        let activity = 0.85 + 0.15 * min(max(ctx.activityMultiplier, 0.5), 1.8)
        speed = rng.uniform(m.speed) * config.pointsPerPixel * activity
        if behavior == .followCursor, isFollowing, let t = followTarget(ctx), config.availableClips.contains("run") {
            // Sprint when the cursor is far away (or while playing); walk when close.
            let far = hypot(t.0 - x, t.1 - y) > config.petWidth * 4
            if far || currentActivity == .play {
                moveClip = "run"
                speed = rng.uniform(18.0...22.0) * config.pointsPerPixel * activity
            }
        }
        reversalsLeft = rng.int(m.reversals)
        guard let t = pickTarget(m.target, ctx), hypot(t.0 - x, t.1 - y) >= 8 else {
            if behavior == .comeTell { start(.askUser, ctx); return } // already close: just ask
            // No room to move: stand and look around instead of jittering.
            steps = [BehaviorStep(["stand"], 1.5...3, facing: .lookAround)].filter { resolveClip($0.clips) != nil }
            movement = nil
            beginStep(0, ctx)
            return
        }
        targetX = t.0
        targetY = t.1
        isMoving = true
        headOut(ctx)
    }

    /// Faces the target (turning in place first if that's a reversal),
    /// then starts the leg.
    private func headOut(_ ctx: PetContext) {
        let dx = targetX - x, dy = targetY - y
        // Mostly-vertical legs keep the current facing (side-view art).
        let dir: Facing? = abs(dx) < abs(dy) * 0.25 ? nil : (dx > 0 ? .right : .left)
        if let dir, dir != facing {
            setFacing(dir)
            // isMoving is already true at this point (set by beginMovement before
            // headOut runs), so the clip must never be a sit/lie posture here even
            // if the pet was sitting the instant before it decided to move —
            // otherwise the render layer shows a sit animation while locomotion
            // is active.
            setClip(resolveClip(["stand", "sit", "lie"]) ?? moveClip)
            turnPause = moveClip == "gallop" ? 0.12 : rng.uniform(0.28...0.45)
        } else {
            turnPause = 0
            setClip(moveClip)
            planLeg()
        }
    }

    /// Plans an eased leg from the current position to the target.
    private func planLeg(linear: Bool = false) {
        let dist = hypot(targetX - x, targetY - y)
        // Ease-in-out: average speed = dist/duration; peak is ~1.5x average.
        // Allow for the acceleration/deceleration so cruise speed ~= `speed`.
        let duration = max(0.35, dist / max(speed, 1) * 1.2)
        leg = MovementLeg(fromX: x, fromY: y, toX: targetX, toY: targetY, duration: linear ? max(0.2, dist / max(speed, 1)) : duration, elapsed: 0, linear: linear)
        legRevision += 1
        if let m = movement {
            playbackRate = min(max((dist / duration) / (m.nominalSpeed * config.pointsPerPixel) * 1.15, 0.5), 1.6)
        }
    }

    private func stepMovement(dt: Double, _ ctx: PetContext) {
        guard movement != nil else { isMoving = false; finish(ctx); return }
        if turnPause > 0 {
            turnPause -= dt
            if turnPause <= 0 {
                setClip(moveClip)
                planLeg()
            }
            return
        }
        guard var l = leg else { planLeg(); return }
        // Following: re-aim mid-leg as the cursor moves (same direction only,
        // constant speed, so it never stops and restarts or jitters).
        if behavior == .followCursor, isFollowing, clock - lastFollowReplan > 0.3,
           let t = followTarget(ctx), hypot(t.0 - targetX, t.1 - targetY) > config.petWidth * 0.6,
           abs(t.0 - x) < config.petWidth * 0.25 || (t.0 > x) == (facing == .right) {
            targetX = t.0; targetY = t.1
            lastFollowReplan = clock
            leg = nil
            planLeg(linear: true)
            guard var nl = leg else { return }
            nl.elapsed = 0
            leg = nl
            return
        }
        let before = (x, y)
        l.elapsed += dt
        let p = l.position(at: min(l.elapsed, l.duration))
        x = clampX(p.0)
        y = clampY(p.1)
        leg = l
        stats.walkedPoints += hypot(x - before.0, y - before.1)
        if l.elapsed >= l.duration {
            x = clampX(l.toX); y = clampY(l.toY)
            leg = nil
            legRevision += 1
            if reversalsLeft > 0, let t = reversalTarget(), hypot(t.0 - x, t.1 - y) >= 8 {
                reversalsLeft -= 1
                targetX = t.0; targetY = t.1
                headOut(ctx)
                if moveClip == "gallop" { turnPause = min(turnPause, 0.1) }
            } else if behavior == .followCursor, isFollowing, let t = followTarget(ctx),
                      hypot(t.0 - x, t.1 - y) > config.petWidth * 0.45,
                      abs(t.0 - x) < config.petWidth * 0.25 || (t.0 > x) == (facing == .right) {
                targetX = t.0; targetY = t.1
                lastFollowReplan = clock
                planLeg(linear: true)
            } else {
                isMoving = false
                playbackRate = 1
                finish(ctx)
            }
        }
    }

    private func reversalTarget() -> (Double, Double)? {
        let w = config.petWidth
        let d = rng.uniform(0.7...1.8) * w
        guard safeHiX - safeLoX > 4 else { return nil }
        let back = facing == .right ? x - d : x + d
        let dy = rng.uniform(-0.4...0.4) * w
        return (min(max(back, safeLoX), safeHiX), min(max(y + dy, safeLoY), safeHiY))
    }

    private var edgeBufferX: Double { min(config.petWidth * 0.2, (maxX - minX) / 4) }
    private var edgeBufferY: Double { min(config.petHeight * 0.1, (maxY - minY) / 4) }
    private var safeLoX: Double { minX + edgeBufferX }
    private var safeHiX: Double { maxX - edgeBufferX }
    private var safeLoY: Double { minY }
    private var safeHiY: Double { maxY - edgeBufferY }

    /// Weighted 2-D destination selection, always inside the safe area.
    /// Returns nil when there's no meaningful room to move.
    func pickTarget(_ strategy: TargetStrategy, _ ctx: PetContext) -> (Double, Double)? {
        let loX = safeLoX, hiX = safeHiX, loY = safeLoY, hiY = max(safeLoY, safeHiY)
        guard hiX - loX > 4 || hiY - loY > 4 else { return nil }
        let w = config.petWidth
        func clamp(_ p: (Double, Double)) -> (Double, Double) { (min(max(p.0, loX), hiX), min(max(p.1, loY), hiY)) }
        func fits(_ p: (Double, Double)) -> Bool { p.0 >= loX && p.0 <= hiX && p.1 >= loY && p.1 <= hiY }
        /// A hop of length d, heading mostly the way the pet faces (65%),
        /// at an angle up to ~70 degrees off horizontal -- real diagonals,
        /// with a preference for gentle slopes so it reads as walking.
        func hop(_ d: Double) -> (Double, Double) {
            var best: (Double, Double)?
            for attempt in 0..<8 {
                let forward = attempt < 4 ? rng.chance(0.65) : rng.chance(0.5)
                let base = (forward ? facing : facing.flipped) == .right ? 0.0 : Double.pi
                let spread = rng.uniform(-1.0...1.0)
                let angle = base + spread * abs(spread) * 1.22 // bias toward horizontal, max ~70 degrees
                let p = (x + cos(angle) * d, y + sin(angle) * d)
                if fits(p) { return p }
                if best == nil { best = clamp(p) }
            }
            return best ?? clamp((x, y))
        }
        switch strategy {
        case .tiny:   return hop(rng.uniform(0.12...0.35) * w)
        case .short:  return hop(rng.uniform(0.6...2.0) * w)
        case .medium: return hop(rng.uniform(2.0...5.0) * w)
        case .long:   return hop(rng.uniform(5.0...10.0) * w)
        case .explore:
            // Least-visited cell of a 4x3 grid that isn't where we are.
            let cw = (maxX - minX) / 4, ch = (maxY - minY) / 3
            var best: (Int, Double)?
            for (i, v) in visits.enumerated() {
                let cx = minX + (Double(i % 4) + 0.5) * cw, cy = minY + (Double(i / 4) + 0.5) * ch
                guard hypot(cx - x, cy - y) > w else { continue }
                if best == nil || v < best!.1 { best = (i, v) }
            }
            guard let (i, _) = best else { return hop(rng.uniform(1...3) * w) }
            return clamp((minX + (Double(i % 4) + rng.uniform(0.2...0.8)) * cw,
                          minY + (Double(i / 4) + rng.uniform(0.2...0.8)) * ch))
        case .farSide:
            let midX = (loX + hiX) / 2, midY = (loY + hiY) / 2
            let tx = x < midX ? rng.uniform((midX + (hiX - midX) * 0.3)...max(midX + (hiX - midX) * 0.3, hiX))
                              : rng.uniform(min(loX, midX - (midX - loX) * 0.3)...(midX - (midX - loX) * 0.3))
            let ty = rng.chance(0.5) ? y + rng.uniform(-1...1) * (hiY - loY) * 0.3 : (y < midY ? rng.uniform(midY...hiY) : rng.uniform(loY...midY))
            return clamp((tx, ty))
        case .home:
            let jitter = rng.uniform(0...(w * 0.4))
            return clamp((config.homeOnLeft ? homeX + jitter : homeX - jitter, homeY + rng.uniform(0...(w * 0.2))))
        case .cursorNear:
            // A few steps toward the user -- not a trek across the screen.
            guard let cx = ctx.cursorX else { return nil }
            let cy = (ctx.cursorY ?? y) - config.petHeight / 2
            let center = x + w / 2
            let dx = cx - center, dy = cy - y
            let dist = hypot(dx, dy)
            guard dist > w * 1.2 else { return nil } // already close
            let step = min(dist - w * 0.9, w * 3)
            return clamp((x + dx / dist * step, y + dy / dist * step))
        case .cursor:
            guard let cx = ctx.cursorX else { return hop(rng.uniform(0.6...2.0) * w) }
            let center = x + w / 2
            let tx = center < cx ? cx - w * 0.75 - w / 2 : cx + w * 0.75 - w / 2
            let ty = (ctx.cursorY ?? (y + config.petHeight / 2)) - config.petHeight / 2
            return clamp((tx, ty))
        case .hideout:
            // The corner farthest from the cursor (or from the pet), inset so
            // the whole pet stays visible.
            let refX = ctx.cursorX ?? x, refY = ctx.cursorY ?? y
            let cx = refX < (loX + hiX) / 2 ? hiX : loX
            let cy = refY < (loY + hiY) / 2 ? hiY : loY
            return clamp((cx, cy))
        case .object:
            guard let ox = ctx.bedX else { return nil }
            return clamp((ox, ctx.bedY ?? y))
        }
    }

    // MARK: Decision making

    private func sleepiness(_ ctx: PetContext) -> Double {
        var s = 1 - energy
        if ctx.hour >= 23 || ctx.hour < 6 { s += 0.3 } else if ctx.hour >= 21 { s += 0.15 }
        if ctx.userIdleSeconds > 300 { s += 0.25 } else if ctx.userIdleSeconds > 120 { s += 0.1 }
        s *= 0.85 + 0.15 * config.personality.restfulness
        return min(s, 1.5)
    }

    /// Weighted, context-aware choice of the next ambient behavior.
    func chooseNext(_ ctx: PetContext) -> PetBehavior {
        let s = sleepiness(ctx)
        let e = energy
        let a = ctx.activityMultiplier
        let canRoam = e > 0.25 && !isStaying && currentActivity != .hideAndSeek
        // Mode is a small, explicit multiplier on top of everything else --
        // .normal (the default) is exactly 1, so selecting it changes
        // nothing. See PetMode.swift for what each one means.
        let modeRoam: Double
        switch ctx.mode {
        case .normal: modeRoam = 1
        case .quiet: modeRoam = 0.4
        case .play: modeRoam = 1.3
        case .sleep: modeRoam = 0.3
        case .attention: modeRoam = 0.5 // less independent wandering, more staying near the user
        }
        // `.follow` shares the exact same cursor-attention boost `.attention`
        // mode uses, just time-boxed by requestFollow(duration:) instead of
        // an ongoing mode choice.
        let attentive = ctx.mode == .attention || isFollowing
        let roam = canRoam ? a * e * max(0.2, 1.2 - s) * config.personality.roaming * modeRoam : 0
        let w = config.petWidth
        var options: [(PetBehavior, Double)] = []

        switch posture {
        case "lie":
            options += [
                (.sleep, s > 0.5 ? 8 * s : (s > 0.35 ? 0.8 : 0.03)),
                (.doze, 1.2 * s),
                (.restAlert, 0.7),
                (.lie, 0.8),
                (.getUp, canRoam ? 1.4 * e * a : 0.1),
                (.sit, 0.4),
            ]
            if ctx.hour >= 23 || ctx.hour < 6 { options.append((.lateNightDrowsy, 1)) }
        case "sit":
            options += [
                (.settle, 0.3 + 3 * s),
                (.lie, 0.2 + 1.2 * s),
                (.sit, 0.7),
                (.sitLookAround, 0.9),
                (.ponder, 0.5),
                (.sitBark, 0.04),
                (.stand, 0.7 * e),
                (.walk, 1.4 * roam),
                (.stroll, 0.7 * roam),
                (.explore, 0.5 * roam),
            ]
            if ctx.cursorNearPet { options.append((.watchCursor, 1.0 * config.cursorInterest)) }
            if ctx.hour >= 21 && ctx.hour < 23 { options.append((.eveningWindDown, 0.6)) }
        default:
            options += [
                (.walk, 3 * roam), (.stroll, 1.5 * roam), (.explore, 1.4 * roam), (.patrol, 0.6 * roam),
                (.pace, 0.3 * roam), (.sniff, 1.0 * max(roam, 0.15)),
                (.trot, e > 0.6 ? 0.8 * roam : 0), (.run, e > 0.7 ? 0.3 * roam : 0),
                (.zoomies, e > 0.8 ? 0.1 * roam : 0), (.spin, e > 0.8 ? 0.04 * roam : 0),
                (.walkBark, 0.04 * roam),
                (.returnHome, hypot(x - homeX, y - homeY) > 6 * w ? 0.15 * (0.4 + s) : 0),
                (.lookAround, 1.5), (.stand, 0.8), (.tailWag, 0.35), (.beg, 0.12), (.play, 0.25),
                (.barkAtNothing, 0.05), (.sit, 1.2 + 3.5 * s),
                (.stretch, 0.15), (.playBow, 0.08), (.scratch, 0.12), (.shake, 0.08), (.chaseTail, 0.04), (.dig, 0.04),
            ]
            // Sleepy + a bed is available + not already standing on it ->
            // an increasingly likely detour to go rest there instead of
            // wherever it happens to be. Gated by
            // canRoam like every other movement option, so focus/stay
            // already suppress it the same way they suppress roaming;
            // .sleep mode leans into it further, .play mode away from it,
            // and an explicit .follow request dampens it heavily rather
            // than letting the bed quietly win over what the user asked
            // for.
            if canRoam, let bx = ctx.bedX, s > 0.4, hypot(x - bx, y - (ctx.bedY ?? y)) > w {
                var bedWeight = 2.5 * s * max(0.3, e)
                if ctx.mode == .sleep { bedWeight *= 2 }
                if ctx.mode == .play { bedWeight *= 0.4 }
                if isFollowing { bedWeight *= 0.3 }
                options.append((.goToBed, bedWeight))
            }
            if ctx.cursorNearPet {
                let ci = config.cursorInterest
                options += [(.investigate, 0.4 * roam * ci), (.followCursor, 0.25 * roam * ci), (.watchCursor, 0.4 * ci)]
            } else if ctx.cursorX != nil, ctx.userIdleSeconds > 60, ctx.userIdleSeconds < 600, canRoam,
                      (memory.secondsSinceLastApproach(now: clock) ?? .infinity) > 120 {
                // The user has gone quiet but hasn't actually left (idle,
                // not away) -- a curious character may wander over to check
                // in, exactly the causal "notices inactivity -> gets
                // curious -> approaches" chain the product brief asks for.
                // Distinct from `.userReturned`, which only fires once the
                // user comes *back* after a real absence. Gated by
                // `memory.lastApproachAt` so it can't fire
                // again and again every few seconds while the user stays
                // idle -- one approach earns a real cooldown, the same way
                // a person wouldn't keep wandering over repeatedly.
                let ci = config.cursorInterest * config.personality.curiosity
                // A more familiar companion leans a little more
                // into proactively checking on the user -- bounded (never
                // more than +40%) and scaled by the existing affection
                // dial, so an affectionate character's willingness to
                // approach grows with familiarity noticeably more than an
                // independent one's does, without a new personality field.
                let fDelta = max(0, ctx.familiarity - 0.4) / 0.6 // 0 on day one, 1 once fully familiar
                let familiarityBoost = 1 + fDelta * 0.4 * config.personality.affection
                options += [(.followCursor, 0.15 * roam * ci * familiarityBoost), (.investigate, 0.1 * roam * ci * familiarityBoost)]
            }
        }

        // Drives: boredom -> look around / play / explore; curiosity ->
        // explore / investigate; playful mood -> play / trot.
        let playful = (energy > 0.7 && affection > 0.6) || ctx.mode == .play
        let pf = config.personality.playfulness
        let annoyed = isAnnoyed
        // A genuine gap from the InteractionMemory-consumption audit
        //: memory was written everywhere but never read back
        // into a decision. This is the smallest meaningful fix -- it's
        // been a while since the last play session, so play reads a
        // little more inviting, the same way boredom already does, not a
        // second parallel drive.
        let playDrought = (memory.secondsSinceLastPlay(now: clock).map { min($0 / 1800, 1) }) ?? 0
        options = options.map { (b, w) in
            switch b {
            case .lookAround, .sniff: return (b, w * (1 + boredom))
            case .play: return (b, w * (1 + boredom + 0.5 * playDrought) * pf * (annoyed ? 0.2 : 1))
            case .explore, .patrol, .investigate:
                // Attention (mode or a `.follow` command) favors staying
                // close over independent exploring, so it dampens this
                // group instead of boosting it. A long continuous active
                // session nudges .investigate specifically up a little --
                // the companion leans toward checking on the user, reusing
                // this same ambient curiosity behavior rather than a
                // separate "concerned" system.
                let base = w * (0.7 + curiosity * 0.8 + boredom * 0.5)
                var adjusted = attentive ? base * 0.4 : base
                if annoyed { adjusted *= (b == .patrol ? 1.8 : 0.3) } // sulks away, doesn't investigate
                if b == .investigate, ctx.continuousActiveMinutes > 50 { adjusted *= 1.4 }
                return (b, adjusted)
            case .trot, .zoomies, .beg, .tailWag: return (b, w * (playful ? 1.6 : 1) * pf * (annoyed ? 0.3 : 1))
            case .sleep, .doze, .lie, .settle:
                return (b, (ctx.mode == .sleep ? w * 3 : w) * config.personality.restfulness)
            case .returnHome, .sit:
                // An annoyed pet keeps its distance and sulks.
                return (b, annoyed ? w * 1.8 : w)
            case .watchCursor, .followCursor:
                var adjusted = (attentive ? w * 2.5 : w) * (annoyed ? 0.25 : 1)
                if ctx.continuousActiveMinutes > 50 { adjusted *= 1.4 }
                return (b, adjusted)
            default: return (b, w)
            }
        }

        let recentlyBarked = clock - lastBarkAt < 45
        options = options.compactMap { (b, weight) in
            guard weight > 0, isAvailable(b) else { return nil }
            if !b.spec.quiet && (ctx.quietHours || recentlyBarked) { return nil }
            if ctx.reducedMotion, [.zoomies, .run, .spin, .trot].contains(b) { return nil }
            // Low battery, unplugged -> the character calms down rather
            // than sprinting around; a plugged-in low battery is not
            // dampened, matching how a user would actually read it.
            if ctx.batteryLow, [.zoomies, .run].contains(b) { return nil }
            if clock < sleepLockUntil, [.sleep, .doze, .lateNightDrowsy].contains(b) { return nil }
            var adjusted = weight
            // Graduated repetition penalty from short-term memory: the more
            // often this behavior shows up in the last few choices, the
            // less likely it is picked again -- prevents "walk walk walk
            // walk walk" or "sit sit sit sit" without banning a behavior
            // outright (a character that's genuinely sleepy should still
            // be allowed to choose sleep repeatedly; that's handled by the
            // sleepiness weight itself being large enough to win anyway).
            let recentCount = recentBehaviors.suffix(4).filter { $0 == b }.count
            if recentCount > 0 { adjusted *= pow(0.55, Double(recentCount)) }
            return (b, adjusted)
        }
        return pick(options) ?? (isAvailable(.stand) ? .stand : .sit)
    }

    private func pick(_ options: [(PetBehavior, Double)]) -> PetBehavior? {
        let valid = options.filter { $0.1 > 0 && isAvailable($0.0) }
        let total = valid.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = rng.nextUnit() * total
        for (b, w) in valid {
            roll -= w
            if roll <= 0 { return b }
        }
        return valid.last?.0
    }

    private func canBark(_ ctx: PetContext) -> Bool {
        !ctx.quietHours && clock - lastBarkAt >= config.barkCooldown
    }

    // MARK: Helpers

    private func resolveClip(_ clips: [String]) -> String? {
        for c in clips {
            let resolved: String
            switch c {
            case ClipToken.posture:
                resolved = ["stand", "sit", "lie"].contains(posture) ? posture : "stand"
            case ClipToken.postureBark:
                resolved = posture == "stand" ? "stand_bark" : "sit_bark"
            default:
                resolved = c
            }
            if config.availableClips.contains(resolved) { return resolved }
        }
        return nil
    }

    private func isBarkClip(_ c: String) -> Bool { c.hasSuffix("_bark") }

    private func setClip(_ c: String) {
        if isBarkClip(c) { lastBarkAt = clock; stats.barks += 1 }
        guard c != clip else { return }
        clip = c
        visualRevision += 1
        switch c {
        case "stand", "stand_bark", "walk", "walk_bark", "run", "gallop", "beg", "beg_bark", "land",
             "happy", "celebrate", "look", "play": posture = "stand"
        case "sit", "sit_bark", "think", "sad": posture = "sit"
        case "lie", "yawn", "sleep": posture = "lie"
        default: break
        }
    }

    private func setFacing(_ f: Facing) {
        guard f != facing else { return }
        facing = f
        visualRevision += 1
    }

    private func clampX(_ v: Double) -> Double { min(max(v, minX), maxX) }
    private func clampY(_ v: Double) -> Double { min(max(v, minY), maxY) }

    private func updateEnergy(dt: Double) {
        if behavior == .sleep || clip == "sleep" {
            energy += dt / 100
            stats.sleepSeconds += dt
        } else if isMoving {
            let intensity = movement.map { sqrt(max($0.speed.lowerBound, 1) / 9.5) } ?? 1
            energy -= dt / 230 * intensity
        } else if posture == "lie" {
            energy += dt / 1500
        } else {
            energy -= dt / 1300
        }
        energy = min(max(energy, 0), 1)
    }

    private func updateDrives(dt: Double) {
        let d = min(dt, 60)
        if isMoving || behavior.category == .interaction || behavior == .play {
            boredom -= d / 60
        } else if !isAsleep {
            boredom += d / 900
        } else {
            boredom -= d / 300
        }
        // Each character fades/settles toward its own resting baseline,
        // not a shared constant -- an affectionate character stays warmer
        // between interactions, a curious one idles at a higher baseline
        // curiosity even before anything happens on screen.
        let affectionBaseline = min(0.6, 0.35 * config.personality.affection)
        affection -= d / 3600 * max(0, affection - affectionBaseline) * 4
        let target = 0.35 * config.personality.curiosity + 0.3 * config.personality.roaming / 1.5 + (rng.nextUnit() - 0.5) * 0.2
        curiosity += (target - curiosity) * min(1, d / 600)
        boredom = min(max(boredom, 0), 1)
        affection = min(max(affection, 0), 1)
        curiosity = min(max(curiosity, 0), 1)
    }

    private func recordVisit(dt: Double) {
        let sx = maxX - minX, sy = maxY - minY
        let decay = exp(-dt / 600)
        for i in visits.indices { visits[i] *= decay }
        let cx = sx > 1 ? min(3, max(0, Int((x - minX) / sx * 4))) : 0
        let cy = sy > 1 ? min(2, max(0, Int((y - minY) / sy * 3))) : 0
        visits[cy * 4 + cx] += dt
    }

    private func scheduleMicro() {
        switch clip {
        case "sleep":
            if clock >= nextMicroAt {
                if nextMicroAt > 0 { pendingMicro = .twitch }
                nextMicroAt = clock + rng.uniform(14...40)
            }
        case "lie", "sit":
            if clock >= nextMicroAt {
                if nextMicroAt > 0 && rng.chance(0.5) { pendingMicro = .earFlick }
                nextMicroAt = clock + rng.uniform(18...45)
            }
        default:
            if nextMicroAt < clock { nextMicroAt = clock + 12 }
        }
    }
}
