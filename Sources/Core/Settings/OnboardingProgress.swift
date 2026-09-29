import Foundation

/// The first-run tour's completion state, as a small explicit state
/// machine on top of `AppSettings.hasCompletedOnboarding`. Kept in Core
/// (no AppKit) so the actual rules -- "skipping counts as done, exactly
/// like finishing", "reset means show it again" -- live in one place and
/// are unit-testable without a display, instead of being implicit inside
/// the AppKit window controller that presents the tour.
public struct OnboardingProgress {
    private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    /// Whether the tour should be skipped at launch -- true once the user
    /// has either finished it or explicitly skipped it.
    public var hasCompleted: Bool { settings.hasCompletedOnboarding }

    /// Reaching the end of every page marks the tour done.
    public func complete() { settings.hasCompletedOnboarding = true }

    /// Skipping is a deliberate choice, not an interruption -- it must
    /// never show the tour again unasked, exactly like finishing it
    /// normally. Expressed as its own case (even though it currently does
    /// the same thing as `complete()`) so that guarantee is explicit and
    /// tested, rather than something a future change to `complete()`
    /// could quietly break.
    public func skip() { complete() }

    /// Clears completion so the tour shows again at next launch, or can
    /// be replayed immediately (Settings -> Advanced -> "Show the welcome
    /// tour again").
    public func reset() { settings.hasCompletedOnboarding = false }
}
