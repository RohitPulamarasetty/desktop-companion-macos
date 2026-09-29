import AppKit
import Core

/// The menu-bar paw: always-available control surface (even when the pet
/// is hidden). Its menu is rebuilt on open from the same `PetMenu` the pet's
/// own right-click menu uses. No Dock icon (the app is an accessory).
public final class MenuBarController: NSObject, NSMenuDelegate, PlatformTray {
    private var statusItem: NSStatusItem?
    private let placeholder = NSMenu()
    /// Supplies a freshly built menu each time the user opens it.
    public var menuProvider: (() -> NSMenu)?
    /// `PlatformTray` conformance: an AppKit-free alternative to
    /// `menuProvider` -- supplies a `PetMenuModel`/`PetMenuActions` pair
    /// instead of a ready-made `NSMenu`, so a caller (or a test) that only
    /// knows about `Core` types can still drive this tray. When set, it
    /// takes priority over `menuProvider`; both exist so existing callers
    /// (`AppDelegate`, which already builds its own `NSMenu` via
    /// `PetMenu.build`) don't have to change.
    public var menuContentProvider: (() -> (PetMenuModel, PetMenuActions))? {
        didSet {
            if let contentProvider = menuContentProvider {
                menuProvider = {
                    let (model, actions) = contentProvider()
                    return PetMenu.build(model, actions)
                }
            }
        }
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Desktop Companion")
        icon?.isTemplate = true // adapts to light/dark menu bar and selection highlight, like a real menu-bar icon
        item.button?.image = icon
        placeholder.delegate = self
        placeholder.autoenablesItems = false
        item.menu = placeholder
        statusItem = item
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard let fresh = menuProvider?() else { return }
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}
