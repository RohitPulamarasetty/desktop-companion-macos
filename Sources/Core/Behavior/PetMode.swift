import Foundation

/// A user-selected companion mode. Deliberately thin:
/// each mode is a small, well-defined bias on the *existing* behavior
/// scoring and message-gating logic, not a parallel behavior system.
/// `.normal` changes nothing, so switching modes is always safe to no-op
/// back to today's exact behavior.
public enum PetMode: String, Codable, CaseIterable, Equatable {
    /// Full autonomous behavior, exactly as today -- the default.
    case normal
    /// Minimal interaction: quieter, less roaming, fewer vocal reactions.
    /// The user's own explicit "leave me alone" choice, distinct from
    /// quiet hours (a schedule).
    case quiet
    /// More interactive: boosts playful/social behaviors and cursor
    /// engagement.
    case play
    /// Strongly biased toward winding down and sleeping, without an
    /// abrupt forced transition -- still goes through the normal
    /// settle→lie→doze→sleep progression, just heavily favored.
    case sleep
    /// The companion actively seeks the user's attention: more cursor
    /// watching, more approaching, less independent wandering.
    case attention

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .quiet: return "Quiet"
        case .play: return "Play"
        case .sleep: return "Sleep"
        case .attention: return "Attention"
        }
    }
}
