import Foundation

/// A user-startable activity. Activities never run their own behavior
/// engine: `PetBrain` owns all of the state and drives them through the same
/// behavior scheduler as everything else. This type is only the declarative
/// description (name, duration, cooldown, what art it needs).
public enum Activity: String, CaseIterable, Equatable {
    case followCursor, comeHere, play, explore, hideAndSeek, stay

    public var displayName: String {
        switch self {
        case .followCursor: return "Follow Cursor"
        case .comeHere: return "Come Here"
        case .play: return "Play"
        case .explore: return "Explore"
        case .hideAndSeek: return "Hide & Seek"
        case .stay: return "Stay"
        }
    }

    /// Seconds the activity runs when no duration is given. `nil` = until stopped.
    public var defaultDuration: Double? {
        switch self {
        case .followCursor: return nil
        case .comeHere: return 20
        case .play: return 30
        case .explore: return 60
        case .hideAndSeek: return 60
        case .stay: return 300
        }
    }

    /// Seconds after the activity ends before it can be started again.
    public var cooldown: Double {
        switch self {
        case .followCursor, .stay: return 0
        case .comeHere: return 3
        case .play: return 30
        case .explore: return 45
        case .hideAndSeek: return 60
        }
    }

    /// Whether a click/drag by the user interrupts it. Follow, stay and
    /// explore resume after a drag; hide & seek treats a click on the pet as
    /// "found you"; play and come-here just finish their short script.
    public var needsCursor: Bool {
        switch self {
        case .followCursor, .comeHere, .play: return true
        case .explore, .hideAndSeek, .stay: return false
        }
    }

    /// Behaviors that must be drawable for this activity (a character
    /// without the art simply doesn't get the activity).
    public var requiredBehaviors: [PetBehavior] {
        switch self {
        case .followCursor: return [.followCursor]
        case .comeHere: return [.comeHere]
        case .play: return [.followCursor, .excited]
        case .explore: return [.explore]
        case .hideAndSeek: return [.hide, .hideWait]
        case .stay: return [.sit]
        }
    }
}

public enum ActivityAvailability: Equatable {
    case available
    case asleep
    case needsCursor
    case cooldown(seconds: Double)
    case unsupported
}
