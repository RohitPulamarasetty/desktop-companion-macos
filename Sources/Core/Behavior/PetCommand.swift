import Foundation

/// A user-issued instruction to the companion, independent of how it was
/// captured (typed text, a future voice front-end, a menu item, or a
/// future slash-command box). Deliberately NOT an LLM/NLP layer -- this is
/// the clean dispatch surface the product brief asked for; a future text
/// parser maps a string to one of these cases, nothing more.
///
/// Split into two groups by where they're handled:
/// - `PetBrain`-local commands (sleep, wake, comeHere, play, quiet, stop)
///   are pure behavior-engine concerns and dispatched by
///   `PetBrain.perform(_:context:)` below.
/// - Everything else (focus/reminders/tasks) already has a real,
///   independent implementation in the App layer (`FocusTimer`,
///   `ReminderEngine`, `TaskStore`) -- this enum names the command, but
///   dispatch for those lives where that logic already lives, not
///   duplicated here. See `docs/PRE_STAGE_9_AUDIT.md`'s command-layer
///   section for exactly which cases are wired today.
public enum PetCommand: Equatable {
    case sleep
    case wake
    case comeHere
    case play
    case quiet
    case stop
    /// Keep watching/approaching the user for a while (Stage 9, Phase 9).
    /// PetBrain-local: opens a timed attention window, the same mechanism
    /// `.attention` mode uses, just scoped to a single request.
    case follow
    /// Stop roaming and stay near the current spot for a while.
    /// PetBrain-local, mirrors `.follow`'s timed-window approach.
    case stay
    /// Starts the cursor-chase mini-game (Stage 9, Phase 14). PetBrain-local:
    /// reuses `.follow`'s attention window, adding only a bounded catch
    /// counter on top -- see `PetBrain.startChaseGame`.
    case playChase
    case startFocus(minutes: Double)
    case stopFocus
    case setReminder(inMinutes: Double, title: String)
    case startTimer(minutes: Double)
}

public enum PetCommandResult: Equatable {
    case handled
    /// This command isn't a PetBrain-local one -- the App layer should
    /// route it to Focus/Reminders/Tasks instead.
    case notHandledHere
    /// Recognized, but not possible right now (e.g. asked to sleep while
    /// already asleep from a user-initiated tuck-in).
    case ignored
}

public extension PetBrain {
    /// Dispatches the PetBrain-local commands by translating them to the
    /// exact same events the UI already sends (`.tuckIn`, `.wakeRequest`,
    /// `.comeTell`, ...) -- a command is never a second, parallel way to
    /// change behavior; it's just another caller of the same entry point.
    @discardableResult
    func perform(_ command: PetCommand, context: PetContext) -> PetCommandResult {
        let result = performLocal(command, context: context)
        // Structured memory (Stage 11, Phase 2): only record commands that
        // actually took effect -- an ignored or not-handled-here command
        // never happened as far as memory is concerned.
        if result == .handled {
            recordCommandInMemory(command)
        }
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
        case .comeHere:
            guard context.cursorX != nil else { return .ignored }
            _ = handle(.comeTell, context: context)
            return .handled
        case .play:
            // Guards on `.petted` (not `.play`) because that's the behavior
            // this actually triggers below, via the same path `.doubleClick`
            // already uses. Every currently-shipped character package lacks
            // a "play" clip (see BehaviorCatalog's note on art-less
            // behaviors), so gating on `isAvailable(.play)` made this
            // command permanently `.ignored` for all 31 installed
            // characters even though the interaction it actually performs
            // (`.petted`) is available and works fine.
            guard isAvailable(.petted) else { return .ignored }
            _ = handle(.doubleClick, context: context) // reuses the existing "petted"/attention path
            return .handled
        case .quiet:
            _ = handle(.askUser, context: context) // settles and watches the user, the same "pause" the pet menu already uses
            return .handled
        case .stop:
            cancelFollowAndStay()
            endChaseGame()
            _ = handle(.goHome, context: context)
            return .handled
        case .follow:
            guard context.cursorX != nil else { return .ignored }
            requestFollow()
            return .handled
        case .stay:
            requestStay()
            return .handled
        case .playChase:
            guard context.cursorX != nil, !isAsleep else { return .ignored }
            startChaseGame()
            return .handled
        case .startFocus, .stopFocus, .setReminder, .startTimer:
            return .notHandledHere
        }
    }
}
