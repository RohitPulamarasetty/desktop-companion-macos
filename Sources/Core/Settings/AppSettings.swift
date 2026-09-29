import Foundation

public enum PetSize: String, CaseIterable, Codable {
    case small
    case normal
    case large

    /// Multiplier on the character's own Normal scale (each character
    /// package declares `pointsPerPixel` for Normal). Normal is ~62% of the
    /// original build's size, as requested. For Biscuit (2.5 pt/px) the
    /// three sizes land on whole device pixels on a 2x display (4, 5, 7);
    /// for the Codex packs Normal is exactly 1 sheet pixel per device pixel.
    public var scaleMultiplier: Double {
        switch self {
        case .small: return 0.8
        case .normal: return 1.0
        case .large: return 1.4
        }
    }

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }
}

public enum FollowCursor: String, CaseIterable, Codable {
    case off, rare, occasional
    public var interest: Double { self == .off ? 0 : (self == .rare ? 0.4 : 1) }
    public var displayName: String { rawValue.capitalized }
}

public enum Talkativeness: String, CaseIterable, Codable {
    case quiet, normal, chatty
    /// Multiplies the character's own chattiness.
    public var multiplier: Double { self == .quiet ? 0.3 : (self == .normal ? 1 : 1.8) }
    public var displayName: String { rawValue.capitalized }
}

/// Where the pet appears when the app launches.
public enum StartPosition: String, CaseIterable, Codable {
    case bottomLeft
    case bottomRight
    case lastPosition

    public var displayName: String {
        switch self {
        case .bottomLeft: return "Bottom-left corner"
        case .bottomRight: return "Bottom-right corner"
        case .lastPosition: return "Where I left it"
        }
    }
}

/// How much of the screen's bottom edge the pet may wander over.
public enum RoamRange: String, CaseIterable, Codable {
    case wholeScreen
    case nearHome

    public var displayName: String {
        switch self {
        case .wholeScreen: return "Whole screen"
        case .nearHome: return "Stay near its corner"
        }
    }
}

public enum ActivityLevel: String, CaseIterable, Codable {
    case calm
    case normal
    case energetic

    /// Multiplies how often the behavior scheduler picks movement over
    /// resting, and how fast the character walks.
    public var movementWeightMultiplier: Double {
        switch self {
        case .calm: return 0.6
        case .normal: return 1.0
        case .energetic: return 1.6
        }
    }
}

/// Local, UserDefaults-backed app preferences. Deliberately not SQLite --
/// this is small key-value state, not records worth querying, and
/// UserDefaults is the idiomatic, zero-dependency mechanism for exactly
/// this on macOS.
public final class AppSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let petSize = "petSize"
        static let activityLevel = "activityLevel"
        static let launchAtLogin = "launchAtLogin"
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
        static let reducedMotion = "reducedMotion"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let rememberedPositionX = "rememberedPositionX"
        static let rememberedPositionY = "rememberedPositionY"
        static let rememberedScreenFrame = "rememberedScreenFrame"
        static let waterIntervalMinutes = "waterIntervalMinutes"
        static let quietHoursStart = "quietHoursStart"
        static let quietHoursEnd = "quietHoursEnd"
        static let selectedCharacterID = "selectedCharacterID"
        static let showPetEverywhere = "showPetEverywhere"
        static let hideInFullscreen = "hideInFullscreen"
        static let hideInPresentations = "hideInPresentations"
        static let hideInGames = "hideInGames"
        static let keepAboveWindows = "keepAboveWindows"
        static let barkOnClick = "barkOnClick"
        static let speechBubbles = "speechBubbles"
        static let startPosition = "startPosition"
        static let roamRange = "roamRange"
        static let petName = "petName"
        static let waterReminders = "waterReminders"
        static let waterGoal = "waterGoal"
        static let breakNudges = "breakNudges"
        static let breakIntervalMinutes = "breakIntervalMinutes"
        static let followCursor = "followCursor"
        static let talkativeness = "talkativeness"
        static let urgentBreaksQuiet = "urgentBreaksQuiet"
        static let favoriteCharacterIDs = "favoriteCharacterIDs"
        static let disabledCharacterIDs = "disabledCharacterIDs"
        static let companionMode = "companionMode"
        static let bedEnabled = "environment.bedEnabled"
    }

    /// How often the pet notices / follows the cursor.
    public var followCursor: FollowCursor {
        get { defaults.string(forKey: Key.followCursor).flatMap(FollowCursor.init) ?? .occasional }
        set { defaults.set(newValue.rawValue, forKey: Key.followCursor) }
    }

    /// How often the pet shares unprompted thoughts.
    public var talkativeness: Talkativeness {
        get { defaults.string(forKey: Key.talkativeness).flatMap(Talkativeness.init) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.talkativeness) }
    }

    /// Important, high-priority task deadlines may still come through during
    /// quiet hours (water and breaks never do).
    public var urgentBreaksQuiet: Bool {
        get { bool(Key.urgentBreaksQuiet, default: true) }
        set { defaults.set(newValue, forKey: Key.urgentBreaksQuiet) }
    }

    /// Minutes of work between gentle stretch-break suggestions.
    public var breakIntervalMinutes: Double {
        get { defaults.object(forKey: Key.breakIntervalMinutes) == nil ? 50 : max(5, defaults.double(forKey: Key.breakIntervalMinutes)) }
        set { defaults.set(newValue, forKey: Key.breakIntervalMinutes) }
    }

    // MARK: Productivity

    /// Gentle water nudge (a pet toast) after `waterIntervalMinutes` of
    /// active use without logging water. Never during focus/quiet hours.
    public var waterReminders: Bool {
        get { bool(Key.waterReminders, default: true) }
        set { defaults.set(newValue, forKey: Key.waterReminders) }
    }

    public var waterGoal: Int {
        get { defaults.object(forKey: Key.waterGoal) == nil ? 8 : max(1, defaults.integer(forKey: Key.waterGoal)) }
        set { defaults.set(newValue, forKey: Key.waterGoal) }
    }

    /// Pet suggests a break after long continuous active stretches.
    public var breakNudges: Bool {
        get { bool(Key.breakNudges, default: true) }
        set { defaults.set(newValue, forKey: Key.breakNudges) }
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    // MARK: Display / Spaces

    /// Show the pet on every Space, over full-screen apps, and on the bare
    /// desktop. ON by default -- the pet should never vanish when the user
    /// switches apps or Spaces.
    public var showPetEverywhere: Bool {
        get { bool(Key.showPetEverywhere, default: true) }
        set { defaults.set(newValue, forKey: Key.showPetEverywhere) }
    }

    /// Opt-in exceptions (all OFF by default = always visible).
    public var hideInFullscreen: Bool {
        get { bool(Key.hideInFullscreen, default: false) }
        set { defaults.set(newValue, forKey: Key.hideInFullscreen) }
    }

    public var hideInPresentations: Bool {
        get { bool(Key.hideInPresentations, default: false) }
        set { defaults.set(newValue, forKey: Key.hideInPresentations) }
    }

    public var hideInGames: Bool {
        get { bool(Key.hideInGames, default: false) }
        set { defaults.set(newValue, forKey: Key.hideInGames) }
    }

    public var keepAboveWindows: Bool {
        get { bool(Key.keepAboveWindows, default: true) }
        set { defaults.set(newValue, forKey: Key.keepAboveWindows) }
    }

    // MARK: Pet

    public var barkOnClick: Bool {
        get { bool(Key.barkOnClick, default: true) }
        set { defaults.set(newValue, forKey: Key.barkOnClick) }
    }

    public var speechBubbles: Bool {
        get { bool(Key.speechBubbles, default: true) }
        set { defaults.set(newValue, forKey: Key.speechBubbles) }
    }

    /// The name the user gave their pet, or nil to use the current
    /// character's own name (so a penguin isn't called "Biscuit").
    public var customPetName: String? {
        get {
            let name = defaults.string(forKey: Key.petName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
        set { defaults.set(newValue, forKey: Key.petName) }
    }

    // MARK: Position

    public var startPosition: StartPosition {
        get { defaults.string(forKey: Key.startPosition).flatMap(StartPosition.init) ?? .bottomLeft }
        set { defaults.set(newValue.rawValue, forKey: Key.startPosition) }
    }

    public var roamRange: RoamRange {
        get { defaults.string(forKey: Key.roamRange).flatMap(RoamRange.init) ?? .wholeScreen }
        set { defaults.set(newValue.rawValue, forKey: Key.roamRange) }
    }

    public var petSize: PetSize {
        get { defaults.string(forKey: Key.petSize).flatMap(PetSize.init) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.petSize) }
    }

    public var activityLevel: ActivityLevel {
        get { defaults.string(forKey: Key.activityLevel).flatMap(ActivityLevel.init) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.activityLevel) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var soundEnabled: Bool {
        get { defaults.object(forKey: Key.soundEnabled) == nil ? true : defaults.bool(forKey: Key.soundEnabled) }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    public var soundVolume: Double {
        get { defaults.object(forKey: Key.soundVolume) == nil ? 0.3 : defaults.double(forKey: Key.soundVolume) }
        set { defaults.set(newValue, forKey: Key.soundVolume) }
    }

    public var reducedMotion: Bool {
        get { defaults.bool(forKey: Key.reducedMotion) }
        set { defaults.set(newValue, forKey: Key.reducedMotion) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Character ids the user has starred in the library (Stage 8). Local
    /// only, no relation to ownership/entitlements.
    public var favoriteCharacterIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.favoriteCharacterIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.favoriteCharacterIDs) }
    }

    /// User-selected companion mode (Stage 9, Phase 10). `.normal` is the
    /// default and changes nothing about existing behavior.
    public var companionMode: PetMode {
        get { defaults.string(forKey: Key.companionMode).flatMap(PetMode.init) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.companionMode) }
    }

    /// Whether the bed environment object (Stage 10) is available for the
    /// pet to use. On by default; the only environment configuration that
    /// exists so far -- position isn't user-configurable yet, so there is
    /// nothing else to persist.
    public var bedEnabled: Bool {
        get { bool(Key.bedEnabled, default: true) }
        set { defaults.set(newValue, forKey: Key.bedEnabled) }
    }

    public func isFavorite(_ characterID: String) -> Bool { favoriteCharacterIDs.contains(characterID) }

    public func setFavorite(_ characterID: String, _ isFavorite: Bool) {
        var ids = favoriteCharacterIDs
        if isFavorite { ids.insert(characterID) } else { ids.remove(characterID) }
        favoriteCharacterIDs = ids
    }

    /// Character ids the user has explicitly turned off (Stage: pack
    /// lifecycle -- see `CharacterPackLifecycle`). A disabled pack stays
    /// installed on disk; it's just excluded from the picker and can't be
    /// selected. Local-only, never a purchase/entitlement signal.
    public var disabledCharacterIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledCharacterIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.disabledCharacterIDs) }
    }

    public func isCharacterDisabled(_ characterID: String) -> Bool { disabledCharacterIDs.contains(characterID) }

    public func setCharacterDisabled(_ characterID: String, _ disabled: Bool) {
        var ids = disabledCharacterIDs
        if disabled { ids.insert(characterID) } else { ids.remove(characterID) }
        disabledCharacterIDs = ids
    }

    public var waterIntervalMinutes: Double {
        get { defaults.object(forKey: Key.waterIntervalMinutes) == nil ? 60 : defaults.double(forKey: Key.waterIntervalMinutes) }
        set { defaults.set(newValue, forKey: Key.waterIntervalMinutes) }
    }

    public var quietHoursStart: Int {
        get { defaults.object(forKey: Key.quietHoursStart) == nil ? 22 : defaults.integer(forKey: Key.quietHoursStart) }
        set { defaults.set(newValue, forKey: Key.quietHoursStart) }
    }

    public var quietHoursEnd: Int {
        get { defaults.object(forKey: Key.quietHoursEnd) == nil ? 7 : defaults.integer(forKey: Key.quietHoursEnd) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnd) }
    }

    /// Mirror of the pet store's selection (the SQLite pet state is the
    /// source of truth); used only if that store can't be opened.
    public var selectedCharacterID: String? {
        get { defaults.string(forKey: Key.selectedCharacterID) }
        set { defaults.set(newValue, forKey: Key.selectedCharacterID) }
    }

    /// Remembers the character's last dragged-to position, tagged with the
    /// screen frame it was recorded on so a stale position from a monitor
    /// that's no longer connected is never trusted.
    public func rememberPosition(x: Double, y: Double, screenFrame: (x: Double, y: Double, width: Double, height: Double)) {
        defaults.set(x, forKey: Key.rememberedPositionX)
        defaults.set(y, forKey: Key.rememberedPositionY)
        let frameString = "\(screenFrame.x),\(screenFrame.y),\(screenFrame.width),\(screenFrame.height)"
        defaults.set(frameString, forKey: Key.rememberedScreenFrame)
    }

    public struct RememberedPosition {
        public let x: Double
        public let y: Double
        public let screenFrame: (x: Double, y: Double, width: Double, height: Double)
    }

    public func rememberedPosition() -> RememberedPosition? {
        guard
            defaults.object(forKey: Key.rememberedPositionX) != nil,
            let frameString = defaults.string(forKey: Key.rememberedScreenFrame)
        else { return nil }
        let parts = frameString.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return RememberedPosition(
            x: defaults.double(forKey: Key.rememberedPositionX),
            y: defaults.double(forKey: Key.rememberedPositionY),
            screenFrame: (parts[0], parts[1], parts[2], parts[3])
        )
    }

    public func clearRememberedPosition() {
        defaults.removeObject(forKey: Key.rememberedPositionX)
        defaults.removeObject(forKey: Key.rememberedPositionY)
        defaults.removeObject(forKey: Key.rememberedScreenFrame)
    }
}
