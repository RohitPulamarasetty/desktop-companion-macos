import AppKit

/// The pet's window. Requirements it has to satisfy, and how:
///
/// - never steals focus / never becomes key or main: `.nonactivatingPanel`
///   + `canBecomeKey/Main == false`; the app itself is an accessory
///   (LSUIElement), so it never appears in Cmd+Tab or the Dock.
/// - visible on every Space, over full-screen apps, and on the bare
///   desktop, surviving app and Space switches: `.canJoinAllSpaces` (one
///   window shared by all Spaces), `.fullScreenAuxiliary` (allowed onto a
///   full-screen app's Space), `.stationary` (Mission Control / Exposé and
///   "show desktop" leave it in place instead of flinging it away with the
///   app windows), `.ignoresCycle` (not in Cmd+` window cycling),
///   `hidesOnDeactivate = false`.
/// - floats above ordinary windows (`.floating`) unless the user turns
///   "Keep pet above windows" off, in which case it sits at normal level
///   (visible on the desktop, behind app windows).
/// - transparent everywhere except the pet's own pixels (click-through is
///   handled by the controller toggling `ignoresMouseEvents`).
public final class TransparentPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        applyPlacementPolicy(showEverywhere: true, aboveWindows: true)
    }

    public func applyPlacementPolicy(showEverywhere: Bool, aboveWindows: Bool) {
        level = aboveWindows ? .floating : .normal
        if showEverywhere {
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        } else {
            // Lives on the Space it was shown on, like a normal window,
            // but still never in the window cycle.
            collectionBehavior = [.managed, .ignoresCycle, .fullScreenNone]
        }
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
