import Foundation

/// The sections of the companion panel a menu item can jump to. Lives in
/// Core (not `Sources/Platform/macOS`) purely because `PetMenuActions`
/// (below) needs a platform-neutral type for `openHome` -- the panel itself
/// (`CompanionPanelController`) is still 100% AppKit and stays in
/// `Sources/Platform/macOS`; its nested `Section` type is now a typealias
/// to this one so there's exactly one definition, not two kept in sync by
/// hand.
public enum PetMenuSection: Int, CaseIterable {
    case today, tasks, focus, wellness, pet
}

/// The pet's menu (right-click the pet, or the menu-bar paw): short and
/// about the pet. Size, Spaces and other preferences live in Settings.
///
/// This is pure data -- no `NSMenu`, no AppKit anywhere. It used to live in
/// `Sources/Platform/macOS/MenuBar/PetMenu.swift` next to the AppKit code
/// that renders it (`PetMenu.build(_:_:)`, still there); it moved to Core
/// so a second shell's `PlatformTray` conformer (see `PlatformProtocols.swift`)
/// can build its own native tray menu from the same model/actions without
/// depending on AppKit at all. See `docs/PLATFORM_PROTOCOLS.md`.
public struct PetMenuModel {
    public var petName: String
    public var petStatus: String
    public var focusPhase: FocusPhase
    public var isAsleep: Bool
    public var petHidden: Bool
    public var includeAppItems: Bool
    public var companionMode: PetMode
    public init(petName: String, petStatus: String, focusPhase: FocusPhase, isAsleep: Bool, petHidden: Bool, includeAppItems: Bool, companionMode: PetMode = .normal) {
        self.petName = petName
        self.petStatus = petStatus
        self.focusPhase = focusPhase
        self.isAsleep = isAsleep
        self.petHidden = petHidden
        self.includeAppItems = includeAppItems
        self.companionMode = companionMode
    }
}

public struct PetMenuActions {
    public var openHome: (PetMenuSection) -> Void = { _ in }
    public var startFocus: (Double, Double) -> Void = { _, _ in }
    public var pauseFocus: () -> Void = {}
    public var resumeFocus: () -> Void = {}
    public var stopFocus: () -> Void = {}
    public var chooseCharacter: () -> Void = {}
    public var toggleSleep: () -> Void = {}
    public var toggleHidden: () -> Void = {}
    public var setMode: (PetMode) -> Void = { _ in }
    public var openSettings: () -> Void = {}
    public var openDiagnostics: () -> Void = {}
    public var openAbout: () -> Void = {}
    public var quit: () -> Void = {}
    public init() {}
}
