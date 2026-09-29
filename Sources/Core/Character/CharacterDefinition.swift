import Foundation

/// How a clip's artwork is oriented.
public enum ClipFacing: String {
    case left, right, front

    init(_ raw: String?) { self = ClipFacing(rawValue: raw?.lowercased() ?? "") ?? .right }
}

/// A resolved, renderable clip: which manifest state to play and whether
/// to mirror it horizontally.
public struct ResolvedClip: Equatable {
    public let state: StateDefinition
    public let mirrored: Bool
    public init(state: StateDefinition, mirrored: Bool) {
        self.state = state
        self.mirrored = mirrored
    }
}

/// The engine's animation vocabulary and how missing clips degrade.
///
/// The pet brain only ever asks for these role names ("walk", "sleep",
/// "happy", ...). Each character package provides whichever it has art
/// for; anything missing falls back along these chains, so a character
/// with no "celebrate" art celebrates with "happy", one with no "sleep"
/// sleeps lying down, and nothing ever crashes or renders blank.
///
/// Art-specific extras ("think", "look", "sad", "play", "stretch", ...)
/// deliberately have NO fallback: behaviors that need them are simply not
/// scheduled for characters that lack the art (no fake placeholder poses).
public enum ClipVocabulary {
    public static let fallbacks: [String: [String]] = [
        "stand": ["sit"],
        "sit": ["stand"],
        "lie": ["sit"],
        "yawn": ["lie", "sit"],
        "sleep": ["lie", "sit"],
        "walk": ["run", "stand"],
        "run": ["walk"],
        "gallop": ["run", "walk"],
        "walk_bark": ["walk"],
        "beg": ["happy", "celebrate", "stand"],
        "happy": ["beg", "stand"],
        "celebrate": ["beg", "happy", "stand"],
        "stand_bark": ["happy", "beg", "stand"],
        "sit_bark": ["happy", "sit"],
        "beg_bark": ["beg"],
        "dragged": ["fall", "stand"],
        "fall": ["dragged", "stand"],
        "land": ["stand"],
    ]

    /// Clip names the brain may request (the union of fallback keys and
    /// art-only extras it knows about).
    public static let artOnly: Set<String> = ["think", "look", "sad", "play", "stretch", "play_bow", "scratch", "shake", "chase_tail", "dig", "sniff"]
}

/// A loaded, validated character: its manifest plus where its assets live.
/// Pure data + lookup logic (no AppKit), so switching characters and every
/// fallback rule is unit tested.
public struct CharacterDefinition: Equatable {
    public let manifest: CharacterManifest
    public let baseURL: URL
    private let statesByID: [String: StateDefinition]

    public init(manifest: CharacterManifest, baseURL: URL) {
        self.manifest = manifest
        self.baseURL = baseURL
        self.statesByID = Dictionary(manifest.states.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public static func == (a: CharacterDefinition, b: CharacterDefinition) -> Bool {
        a.manifest == b.manifest && a.baseURL == b.baseURL
    }

    public var id: String { manifest.id }
    public var displayName: String { manifest.displayName }
    public var tagline: String { manifest.tagline ?? manifest.description ?? "" }
    /// Points per source pixel at the Normal size (legacy v1 packs: 2.5,
    /// the value Biscuit was tuned for).
    public var pointsPerPixel: Double { manifest.pointsPerPixel ?? 2.5 }
    public var gait: Double { manifest.gait ?? 1 }

    /// Temperament for the shared brain, clamped to a subtle range so no
    /// character ever feels like a different engine.
    public var personality: Personality {
        var p = Personality()
        guard let d = manifest.personality else { return p }
        func c(_ v: Double?) -> Double { min(max(v ?? 1, 0.6), 1.5) }
        p.restfulness = c(d.restfulness)
        p.roaming = c(d.roaming)
        p.reactivity = c(d.reactivity)
        p.chattiness = c(d.chattiness)
        p.curiosity = c(d.curiosity)
        p.affection = c(d.affection)
        p.playfulness = c(d.playfulness)
        p.trait = d.trait ?? "friendly"
        return p
    }

    /// Every state shares one frame size (the pipeline guarantees it; for
    /// hand-made packs we use the initial state's). Manifests are expected to
    /// be pre-validated (ManifestValidator requires a non-empty `states`), but
    /// this initializer is public, so we fall back to a zero size rather than
    /// crash if that invariant is ever bypassed.
    public var frameSize: (width: Int, height: Int) {
        guard let s = statesByID[manifest.initialState] ?? manifest.states.first else { return (0, 0) }
        return (s.animation.frameWidth, s.animation.frameHeight)
    }

    public func state(_ id: String) -> StateDefinition? { statesByID[id] }

    /// Does the character have art for `name` itself (directly, or as a
    /// left/right directional pair) -- without fallbacks?
    public func hasExact(_ name: String) -> Bool {
        statesByID[name] != nil || statesByID[name + "_left"] != nil || statesByID[name + "_right"] != nil
    }

    /// Names the brain can use: everything with exact art plus everything
    /// reachable through the fallback chains.
    public var availableClipNames: Set<String> {
        var names = Set<String>()
        for s in manifest.states {
            names.insert(s.id)
            for suffix in ["_left", "_right"] where s.id.hasSuffix(suffix) {
                names.insert(String(s.id.dropLast(suffix.count)))
            }
        }
        for key in ClipVocabulary.fallbacks.keys where resolveName(key) != nil { names.insert(key) }
        return names
    }

    /// The fallback chain for a name, breadth-first, cycle-safe.
    public func resolveName(_ name: String) -> String? {
        var queue = [name]
        var seen = Set<String>()
        while !queue.isEmpty {
            let n = queue.removeFirst()
            guard seen.insert(n).inserted else { continue }
            if hasExact(n) { return n }
            queue += ClipVocabulary.fallbacks[n] ?? []
        }
        return nil
    }

    /// The state to render for a brain clip + facing, and whether to mirror
    /// it. Prefers a dedicated directional variant (`walk_left`), then a
    /// single clip (mirrored only if it is drawn facing the other way; front
    /// art is never mirrored), then the opposite variant mirrored.
    public func resolve(_ name: String, facing: Facing) -> ResolvedClip? {
        guard let n = resolveName(name) else { return nil }
        let want = facing == .left ? "left" : "right"
        let other = facing == .left ? "right" : "left"
        if let s = statesByID[n + "_" + want] { return ResolvedClip(state: s, mirrored: false) }
        if let s = statesByID[n] {
            let drawn = ClipFacing(s.facing ?? manifest.nativeFacing)
            let mirrored = drawn != .front && drawn.rawValue != want
            return ResolvedClip(state: s, mirrored: mirrored)
        }
        if let s = statesByID[n + "_" + other] { return ResolvedClip(state: s, mirrored: true) }
        return nil
    }
}

/// Finds every character package in a directory (`<dir>/<id>/manifest.json`),
/// validating each; invalid packages are skipped and reported, never fatal.
public struct CharacterRepository {
    public let characters: [CharacterDefinition]
    public let failures: [(id: String, error: CharacterPackageError)]

    public init(directory: URL, fileManager: FileManager = .default) {
        self.init(directories: [directory], fileManager: fileManager)
    }

    /// Scans several directories in order (e.g. the app bundle's read-only
    /// `Characters/`, then the user's installed-characters directory under
    /// Application Support -- see `CharacterPackageInstaller`), merging the
    /// results. If two directories both contain a package with the same id,
    /// the FIRST one found wins and the later one is skipped -- in practice
    /// this means a built-in id always shadows an installed package that
    /// happens to share it, since built-in directories are listed first.
    public init(directories: [URL], fileManager: FileManager = .default) {
        var loaded: [CharacterDefinition] = []
        var failed: [(String, CharacterPackageError)] = []
        var seenIDs = Set<String>()
        for directory in directories {
            let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let manifestURL = dir.appendingPathComponent("manifest.json")
                guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
                switch CharacterPackageLoader.load(manifestURL: manifestURL) {
                case .success(let m):
                    guard seenIDs.insert(m.id).inserted else { continue }
                    loaded.append(CharacterDefinition(manifest: m, baseURL: dir))
                case .failure(let e):
                    failed.append((dir.lastPathComponent, e))
                }
            }
        }
        characters = loaded
        failures = failed
    }

    public init(characters: [CharacterDefinition]) {
        self.characters = characters
        self.failures = []
    }

    public func character(id: String) -> CharacterDefinition? { characters.first { $0.id == id } }

    /// The preferred id if installed; else the default; else the first
    /// valid package; else the built-in safe default (never nil).
    public func resolveSelection(_ preferred: String?, defaultID: String = CharacterRepository.defaultCharacterID) -> CharacterDefinition {
        if let preferred, let c = character(id: preferred) { return c }
        if let c = character(id: defaultID) { return c }
        if let c = characters.first { return c }
        return CharacterDefinition(manifest: SafeDefaultCharacter.manifest, baseURL: URL(fileURLWithPath: "/"))
    }

    public static let defaultCharacterID = "biscuit-proto"
}
