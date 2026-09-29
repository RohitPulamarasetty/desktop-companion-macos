import Foundation

/// A pure, Core-level (no AppKit) local export/import of the user's own
/// preferences, character selection/favorites, and relationship/progression
/// state. Deliberately **excludes**:
/// - Any SQLite store's raw interaction/event history (tasks, reminders,
///   focus sessions, wellness log, screen time, per-day pet stats,
///   discovered-behavior timestamps): `ProgressionStore`'s own counters
///   already are the durable "how far along is this relationship" state;
///   the SQLite stores hold day-to-day operational history that isn't
///   meaningful to migrate and isn't needed to reconstruct progression.
/// - Machine-specific paths (nothing here ever touches a `URL`/file path).
/// - Credentials/secrets (there are none anywhere in this app; nothing here
///   introduces any).
///
/// The export/import boundary is pure data in, pure data out: reading and
/// writing files (`NSSavePanel`/`NSOpenPanel`) is AppKit-level wiring that
/// calls into this file, never the other way around.
public enum DataPortability {
    /// Bumped only if a field is removed or its meaning changes in a way
    /// that would make an old export misleading if silently accepted.
    /// Adding a new optional field does NOT require a bump.
    public static let currentSchemaVersion = 1

    // MARK: - Export

    public static func export(settings: AppSettings, progression: ProgressionStore, now: Date = Date()) -> DataExportEnvelope {
        DataExportEnvelope(
            schemaVersion: currentSchemaVersion,
            exportedAt: now,
            settings: ExportedSettings(from: settings),
            progression: ExportedProgression(from: progression)
        )
    }

    public static func exportJSON(settings: AppSettings, progression: ProgressionStore, now: Date = Date()) throws -> Data {
        try encoder.encode(export(settings: settings, progression: progression, now: now))
    }

    // MARK: - Import

    public enum ImportResult: Equatable {
        case success
        case failure(DataPortabilityError)
    }

    /// Decodes, validates, and -- only if every check passes -- applies
    /// `data` to `settings`/`progression`. On any failure, returns the
    /// specific error and **leaves both stores completely untouched**: this
    /// function never writes anything partway through.
    @discardableResult
    public static func importJSON(_ data: Data, into settings: AppSettings, progression: ProgressionStore) -> ImportResult {
        switch decodeAndValidate(data) {
        case .failure(let error):
            return .failure(error)
        case .success(let envelope):
            apply(envelope, to: settings, progression: progression)
            return .success
        }
    }

    /// Decode + validate only, with no side effects -- used by `importJSON`
    /// and directly by tests that want to assert rejection without needing
    /// live `AppSettings`/`ProgressionStore` instances.
    public static func decodeAndValidate(_ data: Data) -> Result<DataExportEnvelope, DataPortabilityError> {
        guard let envelope = try? decoder.decode(DataExportEnvelope.self, from: data) else {
            return .failure(.malformedJSON)
        }
        guard envelope.schemaVersion == currentSchemaVersion else {
            return .failure(.unsupportedSchemaVersion(found: envelope.schemaVersion, supported: currentSchemaVersion))
        }
        if let firstError = validate(envelope).first {
            return .failure(firstError)
        }
        return .success(envelope)
    }

    /// Every defensive, out-of-range/malformed-value check. Structural
    /// decoding (missing fields, wrong types) is already handled by
    /// `Codable` failing to decode at all (`.malformedJSON`); this only
    /// covers values that decode fine as the right *type* but are outside
    /// what the app ever actually produces or accepts.
    public static func validate(_ envelope: DataExportEnvelope) -> [DataPortabilityError] {
        var errors: [DataPortabilityError] = []
        let s = envelope.settings
        let p = envelope.progression

        if PetSize(rawValue: s.petSize) == nil { errors.append(.invalidValue("settings.petSize")) }
        if ActivityLevel(rawValue: s.activityLevel) == nil { errors.append(.invalidValue("settings.activityLevel")) }
        if StartPosition(rawValue: s.startPosition) == nil { errors.append(.invalidValue("settings.startPosition")) }
        if RoamRange(rawValue: s.roamRange) == nil { errors.append(.invalidValue("settings.roamRange")) }
        if FollowCursor(rawValue: s.followCursor) == nil { errors.append(.invalidValue("settings.followCursor")) }
        if Talkativeness(rawValue: s.talkativeness) == nil { errors.append(.invalidValue("settings.talkativeness")) }
        if PetMode(rawValue: s.companionMode) == nil { errors.append(.invalidValue("settings.companionMode")) }

        if !(0...1).contains(s.soundVolume) { errors.append(.outOfRange("settings.soundVolume")) }
        if !(0...23).contains(s.quietHoursStart) { errors.append(.outOfRange("settings.quietHoursStart")) }
        if !(0...23).contains(s.quietHoursEnd) { errors.append(.outOfRange("settings.quietHoursEnd")) }
        if s.waterIntervalMinutes <= 0 || !s.waterIntervalMinutes.isFinite { errors.append(.outOfRange("settings.waterIntervalMinutes")) }
        if s.waterGoal <= 0 { errors.append(.outOfRange("settings.waterGoal")) }
        if s.breakIntervalMinutes <= 0 || !s.breakIntervalMinutes.isFinite { errors.append(.outOfRange("settings.breakIntervalMinutes")) }
        if let name = s.customPetName, name.count > 200 { errors.append(.outOfRange("settings.customPetName")) }
        if let id = s.selectedCharacterID, id.trimmingCharacters(in: .whitespaces).isEmpty { errors.append(.invalidValue("settings.selectedCharacterID")) }
        if s.favoriteCharacterIDs.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            errors.append(.invalidValue("settings.favoriteCharacterIDs"))
        }

        if p.tasksCompleted < 0 { errors.append(.outOfRange("progression.tasksCompleted")) }
        if p.focusSessionsCompleted < 0 { errors.append(.outOfRange("progression.focusSessionsCompleted")) }
        if p.interactions < 0 { errors.append(.outOfRange("progression.interactions")) }
        if p.activeDayCount < 0 { errors.append(.outOfRange("progression.activeDayCount")) }
        if p.firstLaunchDate > envelope.exportedAt.addingTimeInterval(60) {
            // A first-launch date after the export was taken (beyond a
            // small clock-skew allowance) can't be real.
            errors.append(.outOfRange("progression.firstLaunchDate"))
        }

        return errors
    }

    private static func apply(_ envelope: DataExportEnvelope, to settings: AppSettings, progression: ProgressionStore) {
        let s = envelope.settings
        settings.petSize = PetSize(rawValue: s.petSize) ?? settings.petSize
        settings.activityLevel = ActivityLevel(rawValue: s.activityLevel) ?? settings.activityLevel
        settings.launchAtLogin = s.launchAtLogin
        settings.soundEnabled = s.soundEnabled
        settings.soundVolume = s.soundVolume
        settings.reducedMotion = s.reducedMotion
        settings.hasCompletedOnboarding = s.hasCompletedOnboarding
        settings.waterIntervalMinutes = s.waterIntervalMinutes
        settings.quietHoursStart = s.quietHoursStart
        settings.quietHoursEnd = s.quietHoursEnd
        settings.selectedCharacterID = s.selectedCharacterID
        settings.showPetEverywhere = s.showPetEverywhere
        settings.hideInFullscreen = s.hideInFullscreen
        settings.hideInPresentations = s.hideInPresentations
        settings.hideInGames = s.hideInGames
        settings.keepAboveWindows = s.keepAboveWindows
        settings.barkOnClick = s.barkOnClick
        settings.speechBubbles = s.speechBubbles
        settings.startPosition = StartPosition(rawValue: s.startPosition) ?? settings.startPosition
        settings.roamRange = RoamRange(rawValue: s.roamRange) ?? settings.roamRange
        settings.customPetName = s.customPetName
        settings.waterReminders = s.waterReminders
        settings.waterGoal = s.waterGoal
        settings.breakNudges = s.breakNudges
        settings.breakIntervalMinutes = s.breakIntervalMinutes
        settings.followCursor = FollowCursor(rawValue: s.followCursor) ?? settings.followCursor
        settings.talkativeness = Talkativeness(rawValue: s.talkativeness) ?? settings.talkativeness
        settings.urgentBreaksQuiet = s.urgentBreaksQuiet
        settings.favoriteCharacterIDs = Set(s.favoriteCharacterIDs)
        settings.disabledCharacterIDs = Set(s.disabledCharacterIDs)
        settings.companionMode = PetMode(rawValue: s.companionMode) ?? settings.companionMode
        settings.bedEnabled = s.bedEnabled

        let p = envelope.progression
        progression.restore(
            firstLaunchDate: p.firstLaunchDate,
            tasksCompleted: p.tasksCompleted,
            focusSessionsCompleted: p.focusSessionsCompleted,
            interactions: p.interactions,
            activeDayCount: p.activeDayCount
        )
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Everything wrong an import can find, each safe to surface directly to
/// the user (no internal detail leaked, no crash either way).
public enum DataPortabilityError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidValue(String)
    case outOfRange(String)

    public var description: String {
        switch self {
        case .malformedJSON:
            return "This file isn't a valid export -- it's not readable as the expected data format."
        case .unsupportedSchemaVersion(let found, let supported):
            return "This export was made with a different version (\(found)) of this app's data format; this app supports version \(supported)."
        case .invalidValue(let field):
            return "This export has an invalid value for \(field)."
        case .outOfRange(let field):
            return "This export has an out-of-range value for \(field)."
        }
    }
}

// MARK: - Wire format

public struct DataExportEnvelope: Codable, Equatable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var settings: ExportedSettings
    public var progression: ExportedProgression

    public init(schemaVersion: Int, exportedAt: Date, settings: ExportedSettings, progression: ExportedProgression) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.progression = progression
    }
}

public struct ExportedSettings: Codable, Equatable {
    public var petSize: String
    public var activityLevel: String
    public var launchAtLogin: Bool
    public var soundEnabled: Bool
    public var soundVolume: Double
    public var reducedMotion: Bool
    public var hasCompletedOnboarding: Bool
    public var waterIntervalMinutes: Double
    public var quietHoursStart: Int
    public var quietHoursEnd: Int
    public var selectedCharacterID: String?
    public var showPetEverywhere: Bool
    public var hideInFullscreen: Bool
    public var hideInPresentations: Bool
    public var hideInGames: Bool
    public var keepAboveWindows: Bool
    public var barkOnClick: Bool
    public var speechBubbles: Bool
    public var startPosition: String
    public var roamRange: String
    public var customPetName: String?
    public var waterReminders: Bool
    public var waterGoal: Int
    public var breakNudges: Bool
    public var breakIntervalMinutes: Double
    public var followCursor: String
    public var talkativeness: String
    public var urgentBreaksQuiet: Bool
    public var favoriteCharacterIDs: [String]
    public var disabledCharacterIDs: [String]
    public var companionMode: String
    public var bedEnabled: Bool

    public init(from settings: AppSettings) {
        petSize = settings.petSize.rawValue
        activityLevel = settings.activityLevel.rawValue
        launchAtLogin = settings.launchAtLogin
        soundEnabled = settings.soundEnabled
        soundVolume = settings.soundVolume
        reducedMotion = settings.reducedMotion
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        waterIntervalMinutes = settings.waterIntervalMinutes
        quietHoursStart = settings.quietHoursStart
        quietHoursEnd = settings.quietHoursEnd
        selectedCharacterID = settings.selectedCharacterID
        showPetEverywhere = settings.showPetEverywhere
        hideInFullscreen = settings.hideInFullscreen
        hideInPresentations = settings.hideInPresentations
        hideInGames = settings.hideInGames
        keepAboveWindows = settings.keepAboveWindows
        barkOnClick = settings.barkOnClick
        speechBubbles = settings.speechBubbles
        startPosition = settings.startPosition.rawValue
        roamRange = settings.roamRange.rawValue
        customPetName = settings.customPetName
        waterReminders = settings.waterReminders
        waterGoal = settings.waterGoal
        breakNudges = settings.breakNudges
        breakIntervalMinutes = settings.breakIntervalMinutes
        followCursor = settings.followCursor.rawValue
        talkativeness = settings.talkativeness.rawValue
        urgentBreaksQuiet = settings.urgentBreaksQuiet
        favoriteCharacterIDs = Array(settings.favoriteCharacterIDs).sorted()
        disabledCharacterIDs = Array(settings.disabledCharacterIDs).sorted()
        companionMode = settings.companionMode.rawValue
        bedEnabled = settings.bedEnabled
    }

    public init(
        petSize: String, activityLevel: String, launchAtLogin: Bool, soundEnabled: Bool, soundVolume: Double,
        reducedMotion: Bool, hasCompletedOnboarding: Bool, waterIntervalMinutes: Double, quietHoursStart: Int,
        quietHoursEnd: Int, selectedCharacterID: String?, showPetEverywhere: Bool, hideInFullscreen: Bool,
        hideInPresentations: Bool, hideInGames: Bool, keepAboveWindows: Bool, barkOnClick: Bool, speechBubbles: Bool,
        startPosition: String, roamRange: String, customPetName: String?, waterReminders: Bool, waterGoal: Int,
        breakNudges: Bool, breakIntervalMinutes: Double, followCursor: String, talkativeness: String,
        urgentBreaksQuiet: Bool, favoriteCharacterIDs: [String], disabledCharacterIDs: [String], companionMode: String, bedEnabled: Bool
    ) {
        self.petSize = petSize
        self.activityLevel = activityLevel
        self.launchAtLogin = launchAtLogin
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
        self.reducedMotion = reducedMotion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.waterIntervalMinutes = waterIntervalMinutes
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.selectedCharacterID = selectedCharacterID
        self.showPetEverywhere = showPetEverywhere
        self.hideInFullscreen = hideInFullscreen
        self.hideInPresentations = hideInPresentations
        self.hideInGames = hideInGames
        self.keepAboveWindows = keepAboveWindows
        self.barkOnClick = barkOnClick
        self.speechBubbles = speechBubbles
        self.startPosition = startPosition
        self.roamRange = roamRange
        self.customPetName = customPetName
        self.waterReminders = waterReminders
        self.waterGoal = waterGoal
        self.breakNudges = breakNudges
        self.breakIntervalMinutes = breakIntervalMinutes
        self.followCursor = followCursor
        self.talkativeness = talkativeness
        self.urgentBreaksQuiet = urgentBreaksQuiet
        self.favoriteCharacterIDs = favoriteCharacterIDs
        self.disabledCharacterIDs = disabledCharacterIDs
        self.companionMode = companionMode
        self.bedEnabled = bedEnabled
    }
}

public struct ExportedProgression: Codable, Equatable {
    public var firstLaunchDate: Date
    public var tasksCompleted: Int
    public var focusSessionsCompleted: Int
    public var interactions: Int
    public var activeDayCount: Int

    public init(from progression: ProgressionStore) {
        firstLaunchDate = progression.firstLaunchDate
        tasksCompleted = progression.tasksCompleted
        focusSessionsCompleted = progression.focusSessionsCompleted
        interactions = progression.interactions
        activeDayCount = progression.activeDayCount
    }

    public init(firstLaunchDate: Date, tasksCompleted: Int, focusSessionsCompleted: Int, interactions: Int, activeDayCount: Int) {
        self.firstLaunchDate = firstLaunchDate
        self.tasksCompleted = tasksCompleted
        self.focusSessionsCompleted = focusSessionsCompleted
        self.interactions = interactions
        self.activeDayCount = activeDayCount
    }
}
