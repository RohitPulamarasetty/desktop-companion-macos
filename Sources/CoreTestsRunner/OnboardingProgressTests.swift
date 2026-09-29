import Foundation
import Core

/// `OnboardingProgress` is the persisted state machine behind the
/// first-run tour (P1-7): has it been completed, does skipping count as
/// completing, and does a reset actually clear it. The AppKit window that
/// presents the tour can't be unit-tested here (no display in CI), but
/// every rule about *when the tour shows again* lives in this Core type,
/// so it is fully covered without one.
func runOnboardingProgressTests(_ runner: TestRunner) {
    func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
    }

    runner.run("OnboardingProgress.freshInstall_hasNotCompleted") {
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        try expectFalse(progress.hasCompleted)
    }

    runner.run("OnboardingProgress.complete_marksItCompleted") {
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        try expectFalse(progress.hasCompleted)
        progress.complete()
        try expectTrue(progress.hasCompleted)
    }

    runner.run("OnboardingProgress.skip_alsoMarksItCompleted_soItNeverShowsAgainUnasked") {
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        progress.skip()
        try expectTrue(progress.hasCompleted, "skipping the tour must count as completing it")
    }

    runner.run("OnboardingProgress.reset_clearsCompletion_evenAfterFinishing") {
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        progress.complete()
        try expectTrue(progress.hasCompleted)
        progress.reset()
        try expectFalse(progress.hasCompleted, "reset must actually clear completion, not just re-show the window")
    }

    runner.run("OnboardingProgress.reset_afterSkip_alsoClearsIt") {
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        progress.skip()
        progress.reset()
        try expectFalse(progress.hasCompleted)
    }

    runner.run("OnboardingProgress.completion_persistsAcrossAFreshInstance_sharedDefaults") {
        // Mirrors the real relaunch case: a new AppSettings/OnboardingProgress
        // wrapping the same UserDefaults suite must see the same completion
        // state, since that's the actual persistence mechanism (not an
        // in-memory flag).
        let defaults = makeDefaults()
        OnboardingProgress(settings: AppSettings(defaults: defaults)).complete()
        let reopened = OnboardingProgress(settings: AppSettings(defaults: defaults))
        try expectTrue(reopened.hasCompleted)
    }

    runner.run("OnboardingProgress.reset_thenComplete_canBeCompletedAgain") {
        // A user who replays the tour and finishes it again should end up
        // completed, not stuck in some half-reset state.
        let progress = OnboardingProgress(settings: AppSettings(defaults: makeDefaults()))
        progress.complete()
        progress.reset()
        try expectFalse(progress.hasCompleted)
        progress.complete()
        try expectTrue(progress.hasCompleted)
    }
}
