import Foundation
import Core

/// Stage 11.5 follow-up audit: every prior persistence test exercises one
/// store's one field at a time (e.g. `AppSettings.bedEnabled_roundTripsAnd
/// SurvivesAFreshInstance`). Nothing previously simulated a *real app
/// restart* -- close every store, reopen fresh instances against the same
/// UserDefaults suite, and check settings, character selection/favorites,
/// and relationship/progression all survive together, the way an actual
/// quit-and-relaunch would exercise them. This file is exactly that: one
/// UserDefaults suite standing in for "the same Mac", closed and reopened.
func runRestartPersistenceTests(_ runner: TestRunner) {
    func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "restart-persistence-\(UUID().uuidString)")!
    }

    runner.run("RestartPersistence.everyStore_survivesACloseAndReopen_againstTheSameDefaults") {
        let defaults = sharedDefaults()

        // "Session 1": the user configures things, plays with the pet, and
        // the app is about to quit.
        do {
            let settings = AppSettings(defaults: defaults)
            settings.petSize = .large
            settings.activityLevel = .energetic
            settings.selectedCharacterID = "fox-proto"
            settings.setFavorite("fox-proto", true)
            settings.setFavorite("bear-proto", true)
            settings.setCharacterDisabled("usagi-proto", true)
            settings.customPetName = "Noodle"
            settings.companionMode = .play
            settings.hasCompletedOnboarding = true
            settings.quietHoursStart = 23
            settings.quietHoursEnd = 6

            let progression = ProgressionStore(defaults: defaults)
            progression.tasksCompleted = 7
            progression.focusSessionsCompleted = 2
            progression.recordInteraction()
            progression.recordInteraction()
            progression.recordActiveDay()
        }

        // "Session 2": app relaunches -- brand new instances, same
        // UserDefaults suite (the only thing that actually survives a real
        // restart; nothing here is an in-memory cache carried over).
        let reopenedSettings = AppSettings(defaults: defaults)
        let reopenedProgression = ProgressionStore(defaults: defaults)

        // Settings.
        try expectEqual(reopenedSettings.petSize, .large)
        try expectEqual(reopenedSettings.activityLevel, .energetic)
        try expectEqual(reopenedSettings.companionMode, .play)
        try expectTrue(reopenedSettings.hasCompletedOnboarding)
        try expectEqual(reopenedSettings.quietHoursStart, 23)
        try expectEqual(reopenedSettings.quietHoursEnd, 6)
        try expectEqual(reopenedSettings.customPetName, "Noodle")

        // Character selection + favorites/disabled (Stage 8 lifecycle).
        try expectEqual(reopenedSettings.selectedCharacterID, "fox-proto")
        try expectTrue(reopenedSettings.isFavorite("fox-proto"))
        try expectTrue(reopenedSettings.isFavorite("bear-proto"))
        try expectFalse(reopenedSettings.isFavorite("usagi-proto"))
        try expectTrue(reopenedSettings.isCharacterDisabled("usagi-proto"))

        // Relationship/progression.
        try expectEqual(reopenedProgression.tasksCompleted, 7)
        try expectEqual(reopenedProgression.focusSessionsCompleted, 2)
        try expectEqual(reopenedProgression.interactions, 2)
        try expectEqual(reopenedProgression.activeDayCount, 1)
        // firstLaunchDate must not be re-stamped by the second "session" --
        // ProgressionStore's init only sets it when the key is entirely
        // absent.
        let firstLaunchAfterReopen = reopenedProgression.firstLaunchDate
        let thirdInstance = ProgressionStore(defaults: defaults)
        try expectTrue(abs(thirdInstance.firstLaunchDate.timeIntervalSince1970 - firstLaunchAfterReopen.timeIntervalSince1970) < 0.001,
                       "firstLaunchDate must not be re-stamped on every reopen")
    }

    runner.run("RestartPersistence.onboardingCompletion_survivesRestart_tourNeverReshowsUnasked") {
        let defaults = sharedDefaults()
        OnboardingProgress(settings: AppSettings(defaults: defaults)).complete()

        // Simulate two more "restarts" in a row: still complete both times.
        try expectTrue(OnboardingProgress(settings: AppSettings(defaults: defaults)).hasCompleted)
        try expectTrue(OnboardingProgress(settings: AppSettings(defaults: defaults)).hasCompleted)
    }

    runner.run("RestartPersistence.favoritesAndDisabledSets_areIndependentAndBothSurvive") {
        let defaults = sharedDefaults()
        do {
            let settings = AppSettings(defaults: defaults)
            settings.setFavorite("a", true)
            settings.setFavorite("b", true)
            settings.setCharacterDisabled("b", true) // favorited AND disabled: independent bits, both must persist as-is
        }
        let reopened = AppSettings(defaults: defaults)
        try expectTrue(reopened.isFavorite("a"))
        try expectTrue(reopened.isFavorite("b"))
        try expectTrue(reopened.isCharacterDisabled("b"))
        try expectFalse(reopened.isCharacterDisabled("a"))
    }

    runner.run("RestartPersistence.progressionCounters_defaultsToZero_onATrulyFreshDefaultsSuite_notCrash") {
        // A brand-new Mac / first launch: no prior key at all. Every
        // counter must read as a safe zero, never crash reading missing
        // UserDefaults keys.
        let defaults = sharedDefaults()
        let progression = ProgressionStore(defaults: defaults)
        try expectEqual(progression.tasksCompleted, 0)
        try expectEqual(progression.focusSessionsCompleted, 0)
        try expectEqual(progression.interactions, 0)
        try expectEqual(progression.activeDayCount, 0)
        try expectEqual(progression.daysTogether(), 1)
    }
}
