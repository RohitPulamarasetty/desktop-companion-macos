import Foundation

/// A character package's full behavior description: states, their animations,
/// and the transitions the engine is allowed to execute between them.
/// This is pure data — no executable code — loaded from a character's manifest.json.
public struct CharacterManifest: Codable, Equatable {
    public let id: String
    public let displayName: String
    public let attribution: String?
    /// Which way artwork without a per-state `facing` faces as drawn:
    /// "left", "right" or "front" (default "right"). The engine mirrors a
    /// clip only when its facing differs from the pet's movement direction
    /// and it has no dedicated directional variant -- getting this wrong is
    /// exactly what makes a pet "walk backwards".
    public let nativeFacing: String?
    public let initialState: String
    public let states: [StateDefinition]
    public let transitions: [TransitionDefinition]

    // Format v2 (all optional so v1 packages keep decoding).
    public let formatVersion: Int?
    public let description: String?
    public let tagline: String?
    /// "calm" | "normal" | "energetic" -- descriptive only (shown in the
    /// picker); every character runs the exact same behavior engine.
    public let energy: String?
    public let source: String?
    /// Screen points per source pixel at the Normal size.
    public let pointsPerPixel: Double?
    /// Locomotion speed multiplier so each art style's walk cycle covers
    /// ground at a speed that matches its drawn stride.
    public let gait: Double?
    /// Small looping animation for the character picker.
    public let preview: AnimationDefinition?
    /// Temperament: subtle multipliers on the shared behavior engine.
    public let personality: PersonalityDefinition?
    /// Artwork credit (author / source), shown in About and the picker.
    public let license: LicenseMetadata?

    public init(
        id: String,
        displayName: String,
        attribution: String?,
        nativeFacing: String? = nil,
        initialState: String,
        states: [StateDefinition],
        transitions: [TransitionDefinition],
        formatVersion: Int? = nil,
        description: String? = nil,
        tagline: String? = nil,
        energy: String? = nil,
        source: String? = nil,
        pointsPerPixel: Double? = nil,
        gait: Double? = nil,
        preview: AnimationDefinition? = nil,
        personality: PersonalityDefinition? = nil,
        license: LicenseMetadata? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.attribution = attribution
        self.nativeFacing = nativeFacing
        self.initialState = initialState
        self.states = states
        self.transitions = transitions
        self.formatVersion = formatVersion
        self.description = description
        self.tagline = tagline
        self.energy = energy
        self.source = source
        self.pointsPerPixel = pointsPerPixel
        self.gait = gait
        self.preview = preview
        self.personality = personality
        self.license = license
    }
}

/// `"personality": { "trait": "curious", "restfulness": 0.9, "roaming": 1.2, ... }`
/// Every field optional; 1.0 = neutral.
public struct PersonalityDefinition: Codable, Equatable {
    public let trait: String?
    public let restfulness: Double?
    public let roaming: Double?
    public let reactivity: Double?
    public let chattiness: Double?
    /// Resting curiosity baseline and how eagerly it investigates the
    /// cursor/new areas.
    public let curiosity: Double?
    /// How fast it warms up per interaction and its resting affection
    /// baseline.
    public let affection: Double?
    /// How much it plays, zooms and begs (activities and idle play).
    public let playfulness: Double?
    public init(
        trait: String? = nil, restfulness: Double? = nil, roaming: Double? = nil,
        reactivity: Double? = nil, chattiness: Double? = nil, curiosity: Double? = nil, affection: Double? = nil,
        playfulness: Double? = nil
    ) {
        self.trait = trait
        self.restfulness = restfulness
        self.roaming = roaming
        self.reactivity = reactivity
        self.chattiness = chattiness
        self.curiosity = curiosity
        self.affection = affection
        self.playfulness = playfulness
    }
}

public struct StateDefinition: Codable, Equatable {
    public let id: String
    public let animation: AnimationDefinition
    /// "left" | "right" | "front"; nil = the manifest's `nativeFacing`.
    public let facing: String?

    public init(id: String, animation: AnimationDefinition, facing: String? = nil) {
        self.id = id
        self.animation = animation
        self.facing = facing
    }
}

/// One state's animation clip: which sprite sheet to slice, how to slice it
/// (frameWidth/frameHeight, grid-based), and how fast to play it.
public struct AnimationDefinition: Codable, Equatable {
    public let spriteSheet: String
    public let frameWidth: Int
    public let frameHeight: Int
    public let frameCount: Int
    public let framesPerSecond: Double
    public let loop: Bool

    public init(
        spriteSheet: String,
        frameWidth: Int,
        frameHeight: Int,
        frameCount: Int,
        framesPerSecond: Double,
        loop: Bool
    ) {
        self.spriteSheet = spriteSheet
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.frameCount = frameCount
        self.framesPerSecond = framesPerSecond
        self.loop = loop
    }
}

/// The engine-level events that can drive a transition. The manifest declares
/// which trigger fires which from->to edge; the engine decides *when* each
/// trigger actually occurs (elapsed time, mouse events, cursor proximity).
public enum TransitionTrigger: String, Codable, Equatable {
    case timeout
    case idleTimeout
    case cursorProximity
    case mouseDown
    case dragReleased
    /// Fired by the platform layer's gravity simulation when a dropped
    /// character's fall comes to rest, driving fall -> land.
    case landed
    /// Fired by the app layer when the user completes a task or a focus
    /// session, so the character can react (reusing an existing reaction
    /// state such as "bark") regardless of what it was doing at the time.
    case taskCompleted
    case focusCompleted
}

public struct TransitionDefinition: Codable, Equatable {
    public let from: String
    public let to: String
    public let trigger: TransitionTrigger
    public let weight: Double
    /// Only meaningful for .timeout / .idleTimeout triggers: minimum seconds
    /// spent in `from` before this transition becomes eligible.
    public let minimumDuration: Double?

    public init(from: String, to: String, trigger: TransitionTrigger, weight: Double, minimumDuration: Double?) {
        self.from = from
        self.to = to
        self.trigger = trigger
        self.weight = weight
        self.minimumDuration = minimumDuration
    }
}
