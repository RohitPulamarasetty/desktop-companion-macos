import AppKit

/// The menu-bar paw: always-available control surface (even when the pet is
/// hidden). Its menu is rebuilt from the live state each time it opens. No
/// Dock icon (the app is an accessory).
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let placeholder = NSMenu()
    /// Supplies a freshly built menu each time the user opens it.
    public var menuProvider: (() -> NSMenu)?

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Desktop Companion")
        icon?.isTemplate = true // adapts to light/dark menu bar and selection highlight
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
