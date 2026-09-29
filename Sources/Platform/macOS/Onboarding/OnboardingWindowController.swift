import AppKit
import Core

/// First-run flow in the pet's own visual language: welcome, choose your
/// companion (live -- the pet on the desktop changes as you pick), how to
/// interact, gentle help, privacy. Shown once (gated by
/// `AppSettings.hasCompletedOnboarding`); the app releases it afterwards.
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let progress: OnboardingProgress
    private let characters: [CharacterDefinition]
    private var selectedID: String
    private var step = 0
    private var grid: CharacterGridView?
    public var onFinished: (() -> Void)?
    public var onSelectCharacter: ((String) -> Void)?
    /// Portrait of the currently selected character.
    public var avatarProvider: (() -> CGImage?)?
    public var nameProvider: (() -> String)?

    public init(settings: AppSettings, characters: [CharacterDefinition], selectedID: String) {
        self.progress = OnboardingProgress(settings: settings)
        self.characters = characters
        self.selectedID = selectedID
        super.init()
    }

    public func show() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.isMovableByWindowBackground = true
        w.delegate = self // closing the window (the titlebar button) counts as a skip, never a dead window
        window = w
        render()
        w.center()
        NSApp.activate(ignoringOtherApps: true) // first-run welcome is a deliberate foreground moment
        w.makeKeyAndOrderFront(nil)
    }

    /// The window is never app-modal (the pet and its menu stay live behind
    /// it), so nothing about it can "block" the app -- but closing it via
    /// the titlebar button should still count as dismissing the tour,
    /// exactly like the visible Skip control, rather than leaving it stuck
    /// half-finished until the user finds Settings -> Advanced.
    public func windowWillClose(_ notification: Notification) {
        guard window != nil else { return } // already torn down by skip()/finish() themselves
        skip()
    }

    private var pageCount: Int { 5 }

    private func render() {
        guard let window else { return }
        grid?.setActive(false)
        grid = nil
        let name = nameProvider?() ?? "your pet"
        var views: [NSView] = []
        let button: PetButton

        func title(_ t: String) -> NSTextField {
            let l = PetTheme.label(t, size: 21, weight: .bold)
            l.alignment = .center
            return l
        }
        func body(_ t: String) -> NSTextField {
            let l = PetTheme.wrapping(t, size: 13, width: 420)
            l.alignment = .center
            return l
        }

        switch step {
        case 0:
            views = [PetAvatarView(image: avatarProvider?(), size: 120), title("A little companion for your desktop"),
                     body("It lives along the bottom of your screen: wandering, sitting, napping, and quietly keeping you company while you work.")]
            button = PetButton("Choose my companion", style: .primary) { [weak self] in self?.advance() }
        case 1:
            let g = CharacterGridView(characters: characters, selectedID: selectedID)
            g.onSelect = { [weak self] id in
                self?.selectedID = id
                self?.onSelectCharacter?(id)
            }
            grid = g
            views = [title("Choose your companion"), body("Pick anyone -- you can switch any time from its menu. Each has its own temperament; everything else stays the same."), g]
            button = PetButton("This one!", style: .primary) { [weak self] in self?.advance() }
        case 2:
            views = [PetAvatarView(image: avatarProvider?(), size: 110), title("Say hello to \(name)"),
                     body("Click \(name) to get its attention, even while it naps. Double-click to pet it and open its dashboard. Drag it anywhere, even to another display. Click too much and it gets annoyed -- give it a moment.")]
            button = PetButton("Got it", style: .primary) { [weak self] in self?.advance() }
        case 3:
            views = [PetAvatarView(image: avatarProvider?(), size: 110), title("Tell \(name) what to do"),
                     body("Right-click \(name), or click the paw in your menu bar. Activities: Follow Cursor, Come Here, Play, Explore, Hide & Seek, Stay. Stop ends whatever it's doing. You can also press ⌃⌥⌘F to follow your cursor, ⌃⌥⌘S to stop, and ⌃⌥⌘H to call it over. Settings and character choices are in the same menu.")]
            button = PetButton("Continue", style: .primary) { [weak self] in self?.advance() }
        default:
            views = [PetAvatarView(image: avatarProvider?(), size: 110), title("Private by design"),
                     body("Everything stays on this Mac: no account, no cloud, no permissions to grant. Settings → Privacy lists exactly what's stored. You can replay this tour from Settings → System.")]
            button = PetButton("Let's go", style: .primary) { [weak self] in self?.advance() }
        }
        button.keyEquivalent = "\r"
        var dots = ""
        for i in 0..<pageCount { dots += i == step ? "● " : "○ " }
        views.append(PetTheme.label(dots, size: 11, color: PetTheme.inkSoft))
        views.append(button)
        if step < pageCount - 1 {
            views.append(PetButton("Skip", style: .quiet) { [weak self] in self?.skip() })
        }

        let stack = PetTheme.vstack(views, spacing: 14, alignment: .centerX)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        grid?.setActive(true)
        if let grid { window.makeFirstResponder(grid) }
    }

    private func advance() {
        step += 1
        if step >= pageCount {
            finish()
            return
        }
        render()
    }

    /// Ends the tour early, exactly like completing it normally -- the
    /// character chosen so far (if any) is kept, and it never shows again
    /// unless the user replays it from Settings.
    private func skip() { close(progress.skip) }

    private func finish() { close(progress.complete) }

    private func close(_ markDone: () -> Void) {
        grid?.setActive(false)
        markDone()
        window?.orderOut(nil)
        window = nil
        onFinished?()
    }
}
