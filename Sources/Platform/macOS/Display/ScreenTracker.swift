import AppKit

/// Reports display configuration changes (connect/disconnect, resolution,
/// arrangement, Dock/menu bar). The placement rules live in
/// `Core/Behavior/PetPlacement.swift` and `CharacterWindowController`.
public final class ScreenTracker {
    public var onScreensChanged: (() -> Void)?

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreensChanged() {
        onScreensChanged?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
