import Foundation
import Core

private func freshSettings(_ suite: String) -> AppSettings {
    let defaults = UserDefaults(suiteName: "DataPortabilityTests.\(suite).\(UUID().uuidString)")!
    return AppSettings(defaults: defaults)
}

private func freshProgression(_ suite: String) -> ProgressionStore {
    let defaults = UserDefaults(suiteName: "DataPortabilityTests.\(suite).\(UUID().uuidString)")!
    return ProgressionStore(defaults: defaults)
}

func runDataPortabilityTests(_ runner: TestRunner) {
    // MARK: - Valid round-trip: export then import reproduces the same state

    runner.run("DataPortability.validRoundTrip_reproducesSameState") {
        let settings = freshSettings("roundtrip-src")
        settings.petSize = .large
        settings.activityLevel = .energetic
        settings.launchAtLogin = true
        settings.soundVolume = 0.75
        settings.selectedCharacterID = "biscuit-proto"
        settings.customPetName = "Noodle"
        settings.favoriteCharacterIDs = ["ginger", "smoky"]
        settings.setCharacterDisabled("rusty", true)
        settings.companionMode = .focus
        settings.quietHoursStart = 23
        settings.quietHoursEnd = 6
        settings.hasCompletedOnboarding = true

        let progression = freshProgression("roundtrip-src")
        progression.tasksCompleted = 12
        progression.focusSessionsCompleted = 4
        progression.interactions = 300
        progression.activeDayCount = 9

        let data = try DataPortability.exportJSON(settings: settings, progression: progression)

        let restoredSettings = freshSettings("roundtrip-dst")
        let restoredProgression = freshProgression("roundtrip-dst")
        let result = DataPortability.importJSON(data, into: restoredSettings, progression: restoredProgression)
        try expectEqual(result, .success)

        try expectEqual(restoredSettings.petSize, .large)
        try expectEqual(restoredSettings.activityLevel, .energetic)
        try expectEqual(restoredSettings.launchAtLogin, true)
        try expectEqual(restoredSettings.soundVolume, 0.75)
        try expectEqual(restoredSettings.selectedCharacterID, "biscuit-proto")
        try expectEqual(restoredSettings.customPetName, "Noodle")
        try expectEqual(restoredSettings.favoriteCharacterIDs, ["ginger", "smoky"])
        try expectTrue(restoredSettings.isCharacterDisabled("rusty"))
        try expectEqual(restoredSettings.companionMode, .focus)
        try expectEqual(restoredSettings.quietHoursStart, 23)
        try expectEqual(restoredSettings.quietHoursEnd, 6)
        try expectEqual(restoredSettings.hasCompletedOnboarding, true)

        try expectEqual(restoredProgression.tasksCompleted, 12)
        try expectEqual(restoredProgression.focusSessionsCompleted, 4)
        try expectEqual(restoredProgression.interactions, 300)
        try expectEqual(restoredProgression.activeDayCount, 9)
    }

    runner.run("DataPortability.roundTrip_defaultUntouchedSettings_alsoMatches") {
        // Freshly-constructed settings/progression (every field still at
        // its default) should round-trip identically too -- no field is
        // silently dropped or defaulted differently on the way back in.
        let settings = freshSettings("defaults-src")
        let progression = freshProgression("defaults-src")
        let data = try DataPortability.exportJSON(settings: settings, progression: progression)

        let restoredSettings = freshSettings("defaults-dst")
        let restoredProgression = freshProgression("defaults-dst")
        try expectEqual(DataPortability.importJSON(data, into: restoredSettings, progression: restoredProgression), .success)

        try expectEqual(restoredSettings.petSize, settings.petSize)
        try expectEqual(restoredSettings.waterGoal, settings.waterGoal)
        try expectEqual(restoredSettings.followCursor, settings.followCursor)
        try expectEqual(restoredSettings.talkativeness, settings.talkativeness)
        try expectEqual(restoredSettings.roamRange, settings.roamRange)
        try expectEqual(restoredSettings.startPosition, settings.startPosition)
    }

    // MARK: - Corrupt / malformed JSON is rejected safely, never crashes

    runner.run("DataPortability.malformedJSON_rejectedSafely_stateUntouched") {
        let settings = freshSettings("malformed")
        let progression = freshProgression("malformed")
        settings.customPetName = "KeepMe"
        progression.tasksCompleted = 5

        let garbage = "{ this is not valid json at all ]]".data(using: .utf8)!
        let result = DataPortability.importJSON(garbage, into: settings, progression: progression)
        try expectEqual(result, .failure(.malformedJSON))

        // Nothing was touched.
        try expectEqual(settings.customPetName, "KeepMe")
        try expectEqual(progression.tasksCompleted, 5)
    }

    runner.run("DataPortability.emptyData_rejectedSafely_neverCrashes") {
        let settings = freshSettings("empty")
        let progression = freshProgression("empty")
        let result = DataPortability.importJSON(Data(), into: settings, progression: progression)
        try expectEqual(result, .failure(.malformedJSON))
    }

    runner.run("DataPortability.validJSONWrongShape_rejectedSafely") {
        let settings = freshSettings("wrong-shape")
        let progression = freshProgression("wrong-shape")
        let wrongShape = #"{"hello": "world", "notAnExport": true}"#.data(using: .utf8)!
        let result = DataPortability.importJSON(wrongShape, into: settings, progression: progression)
        try expectEqual(result, .failure(.malformedJSON))
    }

    // MARK: - Wrong schema version is rejected safely

    runner.run("DataPortability.wrongSchemaVersion_rejectedSafely_stateUntouched") {
        let settings = freshSettings("wrong-version")
        let progression = freshProgression("wrong-version")
        settings.customPetName = "Untouched"

        var envelope = DataPortability.export(settings: freshSettings("wrong-version-src"), progression: freshProgression("wrong-version-src"))
        envelope.schemaVersion = 999
        let data = try JSONEncoder.forExport().encode(envelope)

        let result = DataPortability.importJSON(data, into: settings, progression: progression)
        try expectEqual(result, .failure(.unsupportedSchemaVersion(found: 999, supported: DataPortability.currentSchemaVersion)))
        try expectEqual(settings.customPetName, "Untouched")
    }

    runner.run("DataPortability.futureSchemaVersion_zero_rejectedSafely") {
        var envelope = DataPortability.export(settings: freshSettings("v0-src"), progression: freshProgression("v0-src"))
        envelope.schemaVersion = 0
        let data = try JSONEncoder.forExport().encode(envelope)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.unsupportedSchemaVersion(let found, _)): try expectEqual(found, 0)
        default: try fail("expected unsupportedSchemaVersion")
        }
    }

    // MARK: - Out-of-range values are rejected safely, never crash, never partially apply

    runner.run("DataPortability.negativeDayCounts_rejectedSafely_stateUntouched") {
        let settings = freshSettings("negative")
        let progression = freshProgression("negative")
        settings.customPetName = "StillHere"
        progression.activeDayCount = 3

        var envelope = DataPortability.export(settings: freshSettings("negative-src"), progression: freshProgression("negative-src"))
        envelope.progression = ExportedProgression(
            firstLaunchDate: envelope.progression.firstLaunchDate,
            tasksCompleted: -1,
            focusSessionsCompleted: 0,
            interactions: 0,
            activeDayCount: -5
        )
        let data = try JSONEncoder.forExport().encode(envelope)

        let result = DataPortability.importJSON(data, into: settings, progression: progression)
        try expectEqual(result, .failure(.outOfRange("progression.tasksCompleted")))
        try expectEqual(settings.customPetName, "StillHere")
        try expectEqual(progression.activeDayCount, 3)
    }

    runner.run("DataPortability.outOfRangeSoundVolume_rejectedSafely") {
        var envelope = DataPortability.export(settings: freshSettings("volume-src"), progression: freshProgression("volume-src"))
        envelope.settings.soundVolume = 4.5
        let data = try JSONEncoder.forExport().encode(envelope)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.outOfRange("settings.soundVolume")): break
        default: try fail("expected outOfRange(settings.soundVolume)")
        }
    }

    runner.run("DataPortability.outOfRangeQuietHours_rejectedSafely") {
        var envelope = DataPortability.export(settings: freshSettings("quiet-src"), progression: freshProgression("quiet-src"))
        envelope.settings.quietHoursStart = 27
        let data = try JSONEncoder.forExport().encode(envelope)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.outOfRange("settings.quietHoursStart")): break
        default: try fail("expected outOfRange(settings.quietHoursStart)")
        }
    }

    runner.run("DataPortability.invalidEnumRawValue_rejectedSafely") {
        var envelope = DataPortability.export(settings: freshSettings("enum-src"), progression: freshProgression("enum-src"))
        envelope.settings.petSize = "gigantic-not-a-real-size"
        let data = try JSONEncoder.forExport().encode(envelope)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.invalidValue("settings.petSize")): break
        default: try fail("expected invalidValue(settings.petSize)")
        }
    }

    runner.run("DataPortability.firstLaunchDateInTheFuture_rejectedSafely") {
        var envelope = DataPortability.export(settings: freshSettings("future-src"), progression: freshProgression("future-src"))
        envelope.progression = ExportedProgression(
            firstLaunchDate: envelope.exportedAt.addingTimeInterval(3600 * 24 * 30),
            tasksCompleted: 0, focusSessionsCompleted: 0, interactions: 0, activeDayCount: 0
        )
        let data = try JSONEncoder.forExport().encode(envelope)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.outOfRange("progression.firstLaunchDate")): break
        default: try fail("expected outOfRange(progression.firstLaunchDate)")
        }
    }

    // MARK: - Never crashes on adversarial input

    runner.run("DataPortability.randomBytes_neverCrashes") {
        let random = Data((0..<200).map { _ in UInt8.random(in: 0...255) })
        let settings = freshSettings("random")
        let progression = freshProgression("random")
        // Just must not crash/throw uncaught; result is allowed to be either,
        // but is overwhelmingly expected to be a failure.
        _ = DataPortability.importJSON(random, into: settings, progression: progression)
    }

    runner.run("DataPortability.truncatedValidExport_rejectedSafely") {
        let settings = freshSettings("truncated-src")
        let progression = freshProgression("truncated-src")
        let data = try DataPortability.exportJSON(settings: settings, progression: progression)
        let truncated = data.prefix(data.count / 2)
        let result = DataPortability.importJSON(Data(truncated), into: freshSettings("truncated-dst"), progression: freshProgression("truncated-dst"))
        try expectEqual(result, .failure(.malformedJSON))
    }

    // MARK: - Partial JSON (valid JSON, but missing fields the app actually
    // produces): must be rejected cleanly, never crash, never partially
    // apply. `ExportedSettings`/`ExportedProgression` have no defaulted
    // properties, so `Codable`'s synthesized decoder already fails a
    // structurally incomplete envelope outright -- confirmed here rather
    // than assumed, since a future field addition that quietly picks up a
    // default (e.g. via a custom `init(from:)`) could silently change this
    // to "half the fields are zeroed" instead of "cleanly rejected."

    runner.run("DataPortability.partialJSON_missingSettingsFields_rejectedSafely_neverCrashes") {
        let settings = freshSettings("partial-1")
        let progression = freshProgression("partial-1")
        settings.customPetName = "KeptOnPartialReject"
        progression.tasksCompleted = 4

        // A structurally valid envelope shape, but `settings` only has a
        // couple of the real fields -- simulating a hand-edited or
        // from-a-future-version file with fields missing, not corrupted.
        let partial = """
        {
          "schemaVersion": 1,
          "exportedAt": "2024-01-01T00:00:00Z",
          "settings": { "petSize": "normal", "activityLevel": "normal" },
          "progression": { "tasksCompleted": 1, "focusSessionsCompleted": 0, "interactions": 0, "activeDayCount": 0, "firstLaunchDate": "2024-01-01T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let result = DataPortability.importJSON(partial, into: settings, progression: progression)
        try expectEqual(result, .failure(.malformedJSON))
        // Rejected cleanly means untouched, exactly like every other
        // rejection path -- never a partial apply of just the fields that
        // happened to be present.
        try expectEqual(settings.customPetName, "KeptOnPartialReject")
        try expectEqual(progression.tasksCompleted, 4)
    }

    runner.run("DataPortability.partialJSON_missingProgressionEntirely_rejectedSafely") {
        let settings = freshSettings("partial-2")
        let progression = freshProgression("partial-2")
        let full = try DataPortability.exportJSON(settings: settings, progression: progression)
        guard var obj = try JSONSerialization.jsonObject(with: full) as? [String: Any] else { try fail("expected a JSON object") }
        obj.removeValue(forKey: "progression")
        let partial = try JSONSerialization.data(withJSONObject: obj)
        let result = DataPortability.importJSON(partial, into: settings, progression: progression)
        try expectEqual(result, .failure(.malformedJSON))
    }

    // MARK: - Unknown/extra fields (forward compatibility): a newer export
    // with fields this build doesn't know about yet must still import
    // everything it does recognize, not be rejected wholesale.

    runner.run("DataPortability.unknownExtraFields_areIgnoredGracefully_notRejected") {
        let settings = freshSettings("extra-src")
        settings.customPetName = "Zippy"
        settings.petSize = .large
        let progression = freshProgression("extra-src")
        progression.tasksCompleted = 3

        let full = try DataPortability.exportJSON(settings: settings, progression: progression)
        guard var obj = try JSONSerialization.jsonObject(with: full) as? [String: Any],
              var settingsObj = obj["settings"] as? [String: Any],
              var progressionObj = obj["progression"] as? [String: Any]
        else { try fail("expected a JSON object with settings/progression") }

        // Fields a *future* version of this app might add -- this build
        // has never heard of any of these.
        obj["futureTopLevelField"] = "some-new-thing"
        settingsObj["futureSettingsField"] = 42
        settingsObj["anotherUnknownFlag"] = true
        progressionObj["futureProgressionField"] = ["nested": "value"]
        obj["settings"] = settingsObj
        obj["progression"] = progressionObj

        let withExtras = try JSONSerialization.data(withJSONObject: obj)

        let restoredSettings = freshSettings("extra-dst")
        let restoredProgression = freshProgression("extra-dst")
        let result = DataPortability.importJSON(withExtras, into: restoredSettings, progression: restoredProgression)
        try expectEqual(result, .success)
        try expectEqual(restoredSettings.customPetName, "Zippy")
        try expectEqual(restoredSettings.petSize, .large)
        try expectEqual(restoredProgression.tasksCompleted, 3)
    }

    // MARK: - No machine-specific paths or secrets ever leave the app in an
    // export. The type system already excludes them (no URL/file-path
    // field, no credential field exists anywhere in this app), but this
    // asserts it directly against the actual exported bytes rather than
    // trusting the schema alone.

    runner.run("DataPortability.exportedJSON_neverContainsAbsolutePathsOrSecrets") {
        let settings = freshSettings("privacy-src")
        settings.customPetName = "Noodle"
        settings.selectedCharacterID = "biscuit-proto"
        settings.favoriteCharacterIDs = ["ginger", "smoky"]
        let progression = freshProgression("privacy-src")
        progression.tasksCompleted = 5

        let data = try DataPortability.exportJSON(settings: settings, progression: progression)
        let json = String(data: data, encoding: .utf8) ?? ""

        // No absolute filesystem paths (this Mac's home directory, /Users,
        // /var, ~, or a file:// URL) anywhere in the export.
        let home = NSHomeDirectory()
        try expectFalse(json.contains(home), "export must never contain this machine's home directory path")
        for forbidden in ["/Users/", "file://", "/private/var", "/var/folders"] {
            try expectFalse(json.contains(forbidden), "export must never contain a machine-specific path fragment: \(forbidden)")
        }
        // No credential-shaped keys anywhere in the export.
        let lower = json.lowercased()
        for forbidden in ["password", "secret", "apikey", "api_key", "token", "credential"] {
            try expectFalse(lower.contains(forbidden), "export must never contain a credential-shaped field: \(forbidden)")
        }
    }
}

private extension JSONEncoder {
    static func forExport() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
