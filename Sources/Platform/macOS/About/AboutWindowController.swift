import AppKit

/// A small, calm About panel: name, author, version, copyright and the
/// artwork credit.
public final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    public func show() {
        let w = window ?? makeWindow()
        window = w
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                         styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.title = "About \(Self.productName)"
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let name = PetTheme.label(Self.productName, size: 17, weight: .bold)
        let publisher = PetTheme.label("by \(Self.publisherName)", size: 12.5, color: PetTheme.inkSoft)
        let version = PetTheme.label("Version \(Self.versionString)", size: 11.5, color: PetTheme.inkSoft)
        let copyright = PetTheme.label(Self.copyrightString, size: 10.5, color: PetTheme.inkSoft)
        let credit = PetTheme.label("Pixel art: Pixel Dogs by Benvictus", size: 10.5, color: PetTheme.inkSoft)

        let stack = PetTheme.vstack([icon, name, publisher, version, copyright, credit], spacing: 6, alignment: .centerX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(2, after: publisher)
        stack.setCustomSpacing(20, after: version)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        return w
    }

    public func windowWillClose(_ notification: Notification) { window = nil }

    // MARK: - Identity, read once from the bundle (single source of truth: Info.plist)

    public static var productName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Desktop Companion"
    }

    public static var publisherName: String { "Rohit Kumar Pulamarasetty" }

    public static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != short { return "\(short) (\(build))" }
        return short
    }

    public static var copyrightString: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Rohit Kumar Pulamarasetty. MIT License."
    }
}
