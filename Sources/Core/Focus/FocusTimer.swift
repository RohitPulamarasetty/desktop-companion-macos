import Foundation

public enum FocusPhase: Equatable {
    case idle
    case focusing(remainingSeconds: TimeInterval)
    case onBreak(remainingSeconds: TimeInterval)
    case paused(resumePhase: PausedPhase, remainingSeconds: TimeInterval)

    public enum PausedPhase: Equatable { case focusing, onBreak }
}

public enum FocusEvent: Equatable {
    case focusCompleted
    case breakCompleted
}

/// Pure timer/state logic for a Pomodoro-style focus session -- no AppKit,
/// no persistence. Driven by an external `tick(deltaTime:)` call, so it's
/// independently testable with a fake clock.
public final class FocusTimer {
    public private(set) var phase: FocusPhase = .idle
    private var focusDuration: TimeInterval = 0
    private var breakDuration: TimeInterval = 0

    public init() {}

    public var isActive: Bool {
        switch phase {
        case .idle: return false
        default: return true
        }
    }

    public func start(focusMinutes: Double, breakMinutes: Double) {
        focusDuration = focusMinutes * 60
        breakDuration = breakMinutes * 60
        phase = .focusing(remainingSeconds: focusDuration)
    }

    public func pause() {
        switch phase {
        case .focusing(let remaining):
            phase = .paused(resumePhase: .focusing, remainingSeconds: remaining)
        case .onBreak(let remaining):
            phase = .paused(resumePhase: .onBreak, remainingSeconds: remaining)
        case .idle, .paused:
            break
        }
    }

    public func resume() {
        guard case .paused(let resumePhase, let remaining) = phase else { return }
        switch resumePhase {
        case .focusing: phase = .focusing(remainingSeconds: remaining)
        case .onBreak: phase = .onBreak(remainingSeconds: remaining)
        }
    }

    /// Skips directly to the break (from focusing) or back to idle (from break).
    @discardableResult
    public func skip() -> FocusEvent? {
        switch phase {
        case .focusing:
            phase = .onBreak(remainingSeconds: breakDuration)
            return .focusCompleted
        case .onBreak:
            phase = .idle
            return .breakCompleted
        case .idle, .paused:
            return nil
        }
    }

    public func cancel() {
        phase = .idle
    }

    /// Advances the countdown. Returns an event exactly at the tick where a
    /// phase naturally completes (focus -> break, or break -> idle), so the
    /// caller can log history and trigger a character reaction once, not
    /// every subsequent tick.
    @discardableResult
    public func tick(deltaTime: TimeInterval) -> FocusEvent? {
        switch phase {
        case .focusing(let remaining):
            let next = remaining - deltaTime
            if next <= 0 {
                phase = .onBreak(remainingSeconds: breakDuration)
                return .focusCompleted
            }
            phase = .focusing(remainingSeconds: next)
            return nil
        case .onBreak(let remaining):
            let next = remaining - deltaTime
            if next <= 0 {
                phase = .idle
                return .breakCompleted
            }
            phase = .onBreak(remainingSeconds: next)
            return nil
        case .idle, .paused:
            return nil
        }
    }
}
