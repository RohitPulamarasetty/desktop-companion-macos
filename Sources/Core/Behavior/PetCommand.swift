import Foundation

/// A user-issued instruction to the companion, whatever its source (menu,
/// keyboard shortcut). Every command is translated into the same events and
/// activity requests the UI already uses -- there is exactly one behavior
/// engine, `PetBrain`.
public enum PetCommand: Equatable {
    case sleep
    case wake
    /// Come to the cursor and greet.
    case comeHere
    /// A short chase of the cursor that ends in a celebration.
    case play
    /// Settle down and watch quietly.
    case quiet
    /// Stop the current activity and go back to ambient behavior.
    case stop
    /// Follow the cursor for `duration` seconds, or until stopped when nil.
    case follow(duration: Double?)
    /// Stay put for `duration` seconds (default 5 minutes).
    case stay(duration: Double?)
    case explore
    case hideAndSeek

    public var activity: Activity? {
        switch self {
        case .comeHere: return .comeHere
        case .play: return .play
        case .follow: return .followCursor
        case .stay: return .stay
        case .explore: return .explore
        case .hideAndSeek: return .hideAndSeek
        case .sleep, .wake, .quiet, .stop: return nil
        }
    }
}

public enum PetCommandResult: Equatable {
    case handled
    /// Recognized, but not possible right now (asleep, on cooldown, no cursor
    /// on this display, or the character lacks the art).
    case ignored
}

public extension PetBrain {
    @discardableResult
    func perform(_ command: PetCommand, context: PetContext) -> PetCommandResult {
        let result = performLocal(command, context: context)
        if result == .handled { recordCommandInMemory(command) }
        return result
    }

    private func performLocal(_ command: PetCommand, context: PetContext) -> PetCommandResult {
        switch command {
        case .sleep:
            guard !isAsleep else { return .ignored }
            _ = handle(.tuckIn, context: context)
            return .handled
        case .wake:
            guard isAsleep else { return .ignored }
            _ = handle(.wakeRequest, context: context)
            return .handled
        case .quiet:
            endActivityForCommand(context)
            _ = handle(.askUser, context: context)
            return .handled
        case .stop:
            stopActivity(context: context)
            _ = handle(.goHome, context: context)
            return .handled
        case .follow(let duration):
            return startCommand(.followCursor, duration: duration, context: context)
        case .stay(let duration):
            return startCommand(.stay, duration: duration, context: context)
        case .comeHere, .play, .explore, .hideAndSeek:
            guard let activity = command.activity else { return .ignored }
            return startCommand(activity, duration: nil, context: context)
        }
    }

    private func startCommand(_ activity: Activity, duration: Double?, context: PetContext) -> PetCommandResult {
        startActivity(activity, duration: duration, context: context) == .available ? .handled : .ignored
    }

    private func endActivityForCommand(_ context: PetContext) { stopActivity(context: context) }
}
