import Foundation

// MARK: - Platform protocol seams
//
// Everything in this file is the *interface* between `Core` (this target,
// zero AppKit/Win32/GTK dependencies -- see `docs/CROSS_PLATFORM_ARCHITECTURE.md`
// for the proof) and a platform shell. `Sources/Platform/macOS` conforms to
// all of these today; a future Windows or Linux shell would conform its own
// window/tray/notification/startup/battery/paths code the same way, without
// Core changing at all. Full contract-by-contract documentation, including
// "who implements this today" and "what a new shell needs to do", lives in
// `docs/PLATFORM_PROTOCOLS.md` -- this file intentionally keeps only brief,
// per-requirement doc comments so the two don't drift out of sync in
// different directions.
//
// None of these protocols change any existing behavior by themselves --
// they're a name put on a seam that (per the Stage 5 cross-platform audit)
// already existed informally. Conforming existing macOS types to them is a
// refactor, not new functionality.

/// A window's position/size in screen coordinates, expressed without any
/// platform type (`NSRect`, `RECT`, ...) so this protocol file stays
/// dependency-free.
public struct PlatformRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The pet's own on-screen window: transparent everywhere but the pet's
/// pixels, click-through except over the pet, always-on-top (or not, per
/// user setting), spanning one display's usable area. Owns nothing about
/// rendering or animation -- only presence, position and visibility.
///
/// Implemented today by `PlatformMac`'s `CharacterWindowController`
/// (backed by `TransparentPanel`, an `NSPanel` subclass). A Windows/Linux
/// shell implements this with its own transparent, topmost, click-through
/// window (a Win32 layered window, or GTK/X11 equivalent on Linux).
public protocol PlatformWindow: AnyObject {
    /// Whether the window is currently on screen. `false` while hidden by
    /// the user, a power policy, system sleep, or the display sleeping.
    var isVisible: Bool { get }
    /// The pet's own rect, in screen coordinates, as currently rendered.
    var frame: PlatformRect { get }
    /// Shows the window (clears the user-hidden reason).
    func show()
    /// Hides the window (sets the user-hidden reason).
    func hide()
    /// Moves the window to a new origin, in screen coordinates.
    func move(toX x: Double, y: Double)
    /// Resizes the window's stage.
    func resize(toWidth width: Double, height: Double)
}

/// The *producer* contract for semantic input: something that translates a
/// platform's raw input (mouse, touch, global input hooks) into one of
/// Core's own `PetEvent` cases and hands it off. This is not a redesign of
/// `PetEvent` -- Core already defines the full event vocabulary
/// (`PetBrain.swift`: `.click`, `.doubleClick`, `.dragBegan`, `.dropped`,
/// `.cursorApproached`, ...) and `PetBrain.handle(_:context:)` already
/// consumes it. `PlatformInputSource` is only the seam that says "a
/// conforming type is *a* source of those events," so a second shell's
/// input-translation code (Win32 window messages, GTK/X11 events) has a
/// named contract to implement instead of being informally understood.
///
/// Implemented today by `PlatformMac`'s `CharacterWindowController`, which
/// both produces events (from its `NSEvent`-driven mouse handling) and owns
/// the `PetBrain` they're delivered to; `onPetEvent` is available for any
/// other observer (e.g. a test, or a future analytics hook) that wants to
/// see the same events without owning the brain.
public protocol PlatformInputSource: AnyObject {
    /// Fired every time raw platform input is classified into a `PetEvent`.
    var onPetEvent: ((PetEvent) -> Void)? { get set }
    /// Starts listening for raw input (a global mouse monitor on macOS;
    /// window messages, or a raw input hook, on Windows/Linux).
    func startMonitoring()
    /// Stops listening.
    func stopMonitoring()
}

/// Presents a `DueReminder` (Core's real type -- `Sources/Core/Reminders/ReminderEngine.swift`)
/// to the user, as a native OS notification, an in-app pet speech bubble,
/// or whatever the platform's idiom is. Core's `ReminderEngine`/`ReminderQueue`
/// decide *what* is due and *when*; this protocol is only the seam that
/// *presents* one, once decided.
///
/// Implemented today by `PlatformMac`'s `NotificationScheduler` (a thin
/// `UNUserNotificationCenter` wrapper) for the native-banner path; the
/// pet-bubble presentation path lives in `Sources/App/AppDelegate.swift`
/// and is intentionally app-shell code, not something this protocol
/// prescribes the shape of (a shell is free to present entirely as bubbles,
/// entirely as native notifications, or a mix, same as macOS does today).
public protocol PlatformNotifications {
    /// Asks the OS for permission to show native notifications, if the
    /// platform requires it (a no-op returning `true` on a platform that
    /// doesn't gate this).
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    /// Presents one due reminder right now.
    func present(_ reminder: DueReminder)
}

/// Enables, disables, and queries "launch at login" / "start on boot".
///
/// Implemented today by `PlatformMac`'s `LoginItemManager`, wrapping
/// `SMAppService` (macOS 13+). A Windows shell would implement this with a
/// registry `Run` key, a Startup-folder shortcut, or Task Scheduler; a
/// Linux shell with an XDG autostart `.desktop` entry.
public protocol PlatformStartup {
    static func setEnabled(_ enabled: Bool)
    static func isEnabled() -> Bool
}

/// Shows a menu-bar/tray icon with a menu built from `PetMenuModel`/
/// `PetMenuActions` (`Sources/Core/Platform/PlatformMenu.swift` -- pure
/// Swift, no AppKit, moved there from `Sources/Platform/macOS/MenuBar` for
/// exactly this protocol). The *rendering* of that model into a real native
/// menu (`NSMenu`, a Win32 popup menu, a GTK menu) stays fully
/// platform-specific; this protocol only says "give me a model and actions,
/// I'll show a menu."
///
/// Implemented today by `PlatformMac`'s `MenuBarController` (wrapping
/// `NSStatusItem`) together with `PetMenu.build(_:_:)` (the AppKit
/// `NSMenu` builder, unchanged, still in `Sources/Platform/macOS/MenuBar`).
public protocol PlatformTray: AnyObject {
    /// Installs the tray/menu-bar icon. Called once at startup.
    func install()
    /// Supplies fresh menu content (model + actions) each time the tray
    /// menu is about to open, so it always reflects current pet/focus/mode
    /// state without the shell having to rebuild and re-push a menu proactively.
    var menuContentProvider: (() -> (PetMenuModel, PetMenuActions))? { get set }
}

/// A single, cheap read of the system's battery/power state. Mirrors the
/// contract `BatteryReader` (macOS) already had informally: no polling
/// loop of its own, read once per existing housekeeping tick, `nil` on a
/// desktop machine with no battery.
public struct PlatformBatteryState: Equatable {
    /// 0...1, or `nil` if the platform didn't report a percentage this read.
    public let level: Double?
    public let isCharging: Bool
    public init(level: Double?, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

public protocol PlatformBattery {
    static func read() -> PlatformBatteryState?
}

/// Computes the directory the app stores its data in (SQLite stores,
/// installed character packages, diagnostics log, ...). Mirrors
/// `AppDelegate.applicationSupportDirectory()`'s existing contract exactly
/// -- Core itself never chooses or hardcodes a path (see
/// `docs/CROSS_PLATFORM_ARCHITECTURE.md`'s "Filesystem" section); every
/// Core store takes a `fileURL: URL` constructor argument and the platform
/// shell computes where that URL points.
///
/// Implemented today by `Sources/App/AppDelegate.swift`
/// (`~/Library/Application Support/DesktopCompanion/`). A Windows shell's
/// equivalent is `%APPDATA%\DesktopCompanion\`; a Linux shell's is
/// `$XDG_DATA_HOME/DesktopCompanion/` (or `~/.local/share/DesktopCompanion/`).
public protocol PlatformPaths {
    static func dataDirectory() -> URL
}

// MARK: - PlatformPersistence: deliberately not defined
//
// The brief asked for a `PlatformPersistence` seam and explicitly allowed
// saying "not needed" if platform state doesn't need its own contract
// beyond what already exists. It doesn't: `AppSettings` (`Sources/Core/Settings/AppSettings.swift`)
// already wraps `UserDefaults`, which is part of `Foundation`/corelibs-foundation
// and is itself portable (proven in the Stage 5 Linux build), and Core's
// five SQLite stores already take a `fileURL: URL` -- there is no
// "platform state" (window frame, permission state, ...) that needs saving
// *outside* what `AppSettings`/`UserDefaults` already provides. Window
// frame today isn't persisted at all beyond `PetStateStore.SavedPosition`
// (a Core SQLite table, keyed by display + fractional position, already
// platform-neutral); permission state (notification authorization) is
// re-queried from the OS each run rather than cached. Inventing a new
// protocol here would be a seam with no real conformer and no real second
// implementation to prove it against -- so it's intentionally absent. If a
// real need for platform-only persisted state appears later (e.g. a
// Windows-specific registry cache), it should get its own protocol then,
// scoped to what actually needs saving.
