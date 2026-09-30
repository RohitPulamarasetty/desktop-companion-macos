import AppKit

/// The menu-bar pup glyph: always-available control surface (even when the pet is
/// hidden). Its menu is rebuilt from the live state each time it opens. No
/// Dock icon (the app is an accessory).
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let placeholder = NSMenu()
    /// Supplies a freshly built menu each time the user opens it.
    public var menuProvider: (() -> NSMenu)?

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = Self.brandGlyph() ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Desktop Companion")
        icon?.isTemplate = true // adapts to light/dark menu bar and selection highlight
        item.button?.image = icon
        item.button?.setAccessibilityLabel("Desktop Companion")
        placeholder.delegate = self
        placeholder.autoenablesItems = false
        item.menu = placeholder
        statusItem = item
    }

    /// The pup-head glyph shipped in the app bundle (Resources/MenuBarIcon.png + @2x). Nil when running
    /// unbundled (`swift run`), where the system paw is used instead.
    private static func brandGlyph() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        if let retina = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
           let data = try? Data(contentsOf: retina), let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        image.size = NSSize(width: 18, height: 18)
        return image
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
