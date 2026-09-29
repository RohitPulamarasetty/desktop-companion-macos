import Foundation
import Core

private func makeDefaults() -> UserDefaults {
    let suiteName = "settings-test-\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

func runAppSettingsTests(_ runner: TestRunner) {
    // MARK: Environment persistence (Stage 10.7)

    runner.run("AppSettings.bedEnabled_defaultsToTrue") {
        let settings = AppSettings(defaults: makeDefaults())
        try expectTrue(settings.bedEnabled)
    }

    runner.run("AppSettings.bedEnabled_roundTripsAndSurvivesAFreshInstance") {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.bedEnabled = false
        try expectFalse(settings.bedEnabled)
        let reloaded = AppSettings(defaults: defaults)
        try expectFalse(reloaded.bedEnabled, "expected bedEnabled=false to persist across a fresh AppSettings instance")
    }

    runner.run("AppSettings.bedEnabled_missingValueRecoversToDefaultNotCrash") {
        // Simulates an old install's UserDefaults that predates this key
        // entirely -- must read as the safe default (true), never crash
        // or read a garbage value.
        let defaults = makeDefaults()
        try expectTrue(defaults.object(forKey: "environment.bedEnabled") == nil)
        try expectTrue(AppSettings(defaults: defaults).bedEnabled)
    }

    runner.run("AppSettings.petSize_defaultsToNormal") {
        let settings = AppSettings(defaults: makeDefaults())
        try expectEqual(settings.petSize, .normal)
    }

    runner.run("AppSettings.petSize_roundTrips") {
        let settings = AppSettings(defaults: makeDefaults())
        settings.petSize = .small
        try expectEqual(settings.petSize, .small)
    }

    runner.run("AppSettings.rememberedPosition_nilWhenNeverSet") {
        let settings = AppSettings(defaults: makeDefaults())
        try expectTrue(settings.rememberedPosition() == nil)
    }

    runner.run("AppSettings.rememberedPosition_roundTrips") {
        let settings = AppSettings(defaults: makeDefaults())
        settings.rememberPosition(x: 100, y: 200, screenFrame: (0, 0, 1920, 1080))
        let remembered = settings.rememberedPosition()
        try expectNotNil(remembered)
        try expectEqual(remembered!.x, 100)
        try expectEqual(remembered!.y, 200)
        try expectEqual(remembered!.screenFrame.width, 1920)
    }

    runner.run("AppSettings.clearRememberedPosition_removesIt") {
        let settings = AppSettings(defaults: makeDefaults())
        settings.rememberPosition(x: 1, y: 2, screenFrame: (0, 0, 100, 100))
        settings.clearRememberedPosition()
        try expectTrue(settings.rememberedPosition() == nil)
    }

    runner.run("PetSize.multipliers_orderedAndBiscuitStaysOnWholeDevicePixels") {
        try expectTrue(PetSize.small.scaleMultiplier < PetSize.normal.scaleMultiplier)
        try expectTrue(PetSize.normal.scaleMultiplier < PetSize.large.scaleMultiplier)
        let biscuitNormal = 2.5 // Characters/biscuit-proto pointsPerPixel
        let ratio = biscuitNormal * PetSize.normal.scaleMultiplier / 4.0 // previous build: 4pt per sprite pixel
        try expectTrue(ratio >= 0.5 && ratio <= 0.7, "normal is \(ratio) of previous")
        for size in PetSize.allCases {
            let devicePixels = biscuitNormal * size.scaleMultiplier * 2 // 2x Retina
            try expectTrue(abs(devicePixels - devicePixels.rounded()) < 1e-9)
        }
    }

    runner.run("PetState.selectedCharacter_persistsAcrossReopen") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sel-\(UUID().uuidString).sqlite")
        do { try PetStateStore(fileURL: url).setSelectedCharacterID("snowy") }
        try expectEqual(try PetStateStore(fileURL: url).selectedCharacterID(), "snowy")
    }

    runner.run("AppSettings.displayDefaults_petVisibleEverywhereWithNoHideExceptions") {
        let settings = AppSettings(defaults: makeDefaults())
        try expectTrue(settings.showPetEverywhere)
        try expectFalse(settings.hideInFullscreen)
        try expectFalse(settings.hideInPresentations)
        try expectFalse(settings.hideInGames)
        try expectTrue(settings.keepAboveWindows)
        try expectEqual(settings.startPosition, .bottomLeft)
        try expectTrue(settings.barkOnClick)
    }

    runner.run("AppSettings.customPetName_blankMeansUseCharacterName") {
        let settings = AppSettings(defaults: makeDefaults())
        try expectTrue(settings.customPetName == nil)
        settings.customPetName = "   "
        try expectTrue(settings.customPetName == nil)
        settings.customPetName = "Mochi"
        try expectEqual(settings.customPetName, "Mochi")
    }
}

func runProgressionStoreTests(_ runner: TestRunner) {
    runner.run("ProgressionStore.daysTogether_isAtLeastOneOnFirstLaunch") {
        let store = ProgressionStore(defaults: makeDefaults())
        try expectEqual(store.daysTogether(), 1)
    }

    runner.run("ProgressionStore.daysTogether_countsElapsedDays") {
        let store = ProgressionStore(defaults: makeDefaults())
        let future = Calendar.current.date(byAdding: .day, value: 6, to: Date())!
        try expectEqual(store.daysTogether(referenceDate: future), 7)
    }

    runner.run("ProgressionStore.milestones_unlockBasedOnCounters") {
        let store = ProgressionStore(defaults: makeDefaults())
        try expectTrue(store.milestones().first(where: { $0.title == "50 interactions" })!.isUnlocked == false)
        for _ in 0..<50 { store.recordInteraction() }
        try expectTrue(store.milestones().first(where: { $0.title == "50 interactions" })!.isUnlocked == true)
    }

    // MARK: Stage 11 additions -- closing the milestone-coverage gap the
    // master audit found (only the single-threshold case above was tested).

    runner.run("ProgressionStore.firstLaunchDate_setOnceAndPersistsAcrossInstances") {
        let defaults = makeDefaults()
        let first = ProgressionStore(defaults: defaults).firstLaunchDate
        let reloaded = ProgressionStore(defaults: defaults).firstLaunchDate
        try expectEqual(first.timeIntervalSince1970.rounded(), reloaded.timeIntervalSince1970.rounded())
    }

    runner.run("ProgressionStore.milestones_dayBasedOnesUnlockOnlyOnceTheWeekThresholdIsReached") {
        let defaults = makeDefaults()
        // Backdate first launch by pre-seeding the key before construction,
        // so daysTogether() (using its real Date() default) reports >= 7
        // without faking the system clock.
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        defaults.set(eightDaysAgo, forKey: "progression.firstLaunchDate")
        let store = ProgressionStore(defaults: defaults)
        func unlocked(_ title: String) -> Bool { store.milestones().first { $0.title == title }?.isUnlocked ?? false }
        try expectTrue(unlocked("First day together"))
        try expectTrue(unlocked("A week together"))
    }

    runner.run("ProgressionStore.freshStore_onlyFirstDayMilestoneIsUnlocked") {
        let store = ProgressionStore(defaults: makeDefaults())
        let unlockedTitles = store.milestones().filter(\.isUnlocked).map(\.title)
        try expectEqual(unlockedTitles, ["First day together"])
    }

    runner.run("ProgressionStore.milestones_alwaysReturnsTheSameFiveTitles_neverGatesAnything") {
        // Milestone only carries a title and a Bool -- nothing that could
        // be checked elsewhere to unlock/disable a capability. This
        // documents that guarantee rather than probing behavior that
        // doesn't exist.
        let store = ProgressionStore(defaults: makeDefaults())
        try expectEqual(store.milestones().count, 5)
        for m in store.milestones() { try expectFalse(m.title.isEmpty) }
    }

    // MARK: Stage 12 -- relationship depth

    runner.run("ProgressionStore.familiarity_isBoundedBetween0Point4And1") {
        try expectEqual(ProgressionStore.familiarity(daysTogether: 0, activeDayCount: 0), 0.4)
        try expectEqual(ProgressionStore.familiarity(daysTogether: 1, activeDayCount: 0) >= 0.4, true)
        try expectEqual(ProgressionStore.familiarity(daysTogether: 9999, activeDayCount: 9999), 1.0)
    }

    runner.run("ProgressionStore.familiarity_growsWithDaysTogether_holdingEngagementConstant") {
        let day1 = ProgressionStore.familiarity(daysTogether: 1, activeDayCount: 0)
        let day14 = ProgressionStore.familiarity(daysTogether: 14, activeDayCount: 0)
        try expectTrue(day14 > day1, "expected more calendar days together to raise the floor: day1=\(day1) day14=\(day14)")
        try expectEqual(day14, 1.0) // the floor alone reaches full familiarity at 14 days
    }

    runner.run("ProgressionStore.familiarity_activeDayCount_addsABoundedBonus_notARawMultiplier") {
        let noEngagement = ProgressionStore.familiarity(daysTogether: 1, activeDayCount: 0)
        let someEngagement = ProgressionStore.familiarity(daysTogether: 1, activeDayCount: 10)
        try expectTrue(someEngagement > noEngagement, "expected active-day engagement to raise familiarity above the pure time floor")
        try expectTrue(someEngagement - noEngagement <= 0.1 + 0.0001, "expected the engagement bonus to never exceed its +0.1 cap")
    }

    runner.run("ProgressionStore.familiarity_resistsFarming_activeDayCountCannotReachHighFamiliarityOnDayOne") {
        // The actual anti-farming guarantee: no matter how large
        // activeDayCount somehow got (which itself can't happen from
        // clicking alone -- see recordActiveDay tests below), a day-one
        // companion can never read as genuinely "familiar" (>= 0.9, the
        // threshold PetMessageBook.familiarLines uses).
        let maxedOut = ProgressionStore.familiarity(daysTogether: 1, activeDayCount: 999_999)
        try expectTrue(maxedOut < 0.9, "expected day-one familiarity to stay well below the 'familiar' threshold even with an unrealistic engagement count: \(maxedOut)")
    }

    runner.run("ProgressionStore.recordActiveDay_incrementsAtMostOnceForTheSameCalendarDay") {
        let store = ProgressionStore(defaults: makeDefaults())
        try expectEqual(store.activeDayCount, 0)
        let now = Date()
        store.recordActiveDay(now: now)
        try expectEqual(store.activeDayCount, 1)
        // Simulates rapid clicking: many calls, same day -- must not budge.
        for _ in 0..<500 { store.recordActiveDay(now: now.addingTimeInterval(Double.random(in: 0..<60))) }
        try expectEqual(store.activeDayCount, 1) // expected 500 more calls on the same calendar day to add nothing
    }

    runner.run("ProgressionStore.recordActiveDay_incrementsOnANewCalendarDay") {
        let store = ProgressionStore(defaults: makeDefaults())
        let day1 = Date()
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
        store.recordActiveDay(now: day1)
        store.recordActiveDay(now: day2)
        try expectEqual(store.activeDayCount, 2)
    }
}
