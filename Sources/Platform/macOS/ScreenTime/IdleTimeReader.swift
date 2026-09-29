import CoreGraphics

/// Seconds since the user's last input (mouse or keyboard), system-wide.
/// A duration only -- never which key, never window/app identity, never
/// content. That's the whole privacy boundary for screen-time tracking.
public enum IdleTimeReader {
    /// `kCGAnyInputEventType` (~0). The previous implementation passed
    /// `.null` (event type 0), which reports time since a "null" event --
    /// in practice days -- so every sample looked idle: screen time never
    /// accumulated and "is the user here?" checks always said no.
    private static let anyInput = CGEventType(rawValue: ~0)!

    public static func secondsSinceLastInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
