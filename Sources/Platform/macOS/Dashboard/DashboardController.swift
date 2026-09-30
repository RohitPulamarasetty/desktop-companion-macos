import AppKit
import Core

/// Everything the dashboard shows, computed by the app layer.
public struct DashboardSnapshot: Equatable {
    public var petName = ""
    public var characterName = ""
    public var mood = ""
    public var activity = ""
    public var mode = ""
    public var familiarityLabel = ""
    /// 0...1
    public var familiarity = 0.0
    public var daysTogether = 1
    public var petsToday = 0
    public var napsToday = 0
    public var screensCrossedToday = 0
    public var favoriteActivity = ""
    public var behaviorsSeen = 0
    public var behaviorsTotal = 0
    public var milestones: [String] = []
    public var lockedMilestones: [String] = []
    public var isFollowing = false
    public var tasksLine = ""
    public var focusLine = ""
    public var waterLine = ""
    public var weekLine = ""
    public var streakDays = 0
    public init() {}
}

/// The companion's home: a small, clean window with who it is, how it feels,
/// what it's doing, and how well you know each other. Built lazily; while
/// closed it does no work.
public final class DashboardController: NSObject, NSWindowDelegate {
    public var snapshotProvider: (() -> DashboardSnapshot)?
    public var avatarProvider: (() -> CGImage?)?
    public var onFollowToggle: (() -> Void)?
    public var onChooseCharacter: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenProductivity: (() -> Void)?

    private var window: NSWindow?
    private var refreshTimer: Timer?
    private var lastSnapshot: DashboardSnapshot?

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show() {
        let w = window ?? makeWindow()
        window = w
        refresh(force: true)
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        // A slow refresh only while the window is open (mood/activity change).
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh(force: false) }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                         styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.title = "Dashboard"
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.delegate = self
        return w
    }

    public func refresh(force: Bool) {
        guard let window, window.isVisible || force, let snap = snapshotProvider?() else { return }
        if !force, snap == lastSnapshot { return }
        lastSnapshot = snap
        window.title = "\(snap.petName) · Dashboard"
        build(snap, in: window)
    }

    private func row(_ title: String, _ value: String) -> NSView {
        let t = PetTheme.label(title, size: 12.5, color: PetTheme.inkSoft)
        let v = PetTheme.label(value, size: 12.5, weight: .semibold)
        v.alignment = .right
        let stack = PetTheme.hstack([t, PetTheme.spacer(), v], spacing: 8)
        return stack
    }

    private func build(_ s: DashboardSnapshot, in window: NSWindow) {
        let avatar = PetAvatarView(image: avatarProvider?(), size: 84)
        let name = PetTheme.label(s.petName, size: 20, weight: .bold)
        let sub = PetTheme.label(s.characterName == s.petName ? s.mood : "\(s.characterName) · \(s.mood)", size: 12.5, color: PetTheme.inkSoft)
        let header = PetTheme.hstack([avatar, PetTheme.vstack([name, sub], spacing: 2), PetTheme.spacer()], spacing: 12)

        let now = PetCardView([
            PetTheme.sectionHeader("Right now"),
            row("Mood", s.mood), row("Activity", s.activity), row("Mode", s.mode),
        ], spacing: 6)

        let bar = FamiliarityBar(value: s.familiarity)
        let together = PetCardView([
            PetTheme.sectionHeader("Together"),
            row("Familiarity", s.familiarityLabel), bar,
            row("Days together", "\(s.daysTogether)"),
            row("Favorite activity", s.favoriteActivity),
            row("Behaviors seen", "\(s.behaviorsSeen) of \(s.behaviorsTotal)"),
        ], spacing: 6)

        let productivity = PetCardView([
            PetTheme.sectionHeader("Productivity today"),
            row("Tasks", s.tasksLine), row("Focus", s.focusLine), row("Water", s.waterLine),
            row("Streak", s.streakDays > 0 ? "🔥 \(s.streakDays) day\(s.streakDays == 1 ? "" : "s")" : "–"),
            row("Last 7 days", s.weekLine),
        ], spacing: 6)

        let today = PetCardView([
            PetTheme.sectionHeader("Today"),
            row("Pats & clicks", "\(s.petsToday)"), row("Naps", "\(s.napsToday)"), row("Screens crossed", "\(s.screensCrossedToday)"),
        ], spacing: 6)

        var cards: [NSView] = [header, now, productivity, together, today]
        let unlocked = s.milestones.isEmpty ? "None yet" : s.milestones.joined(separator: " · ")
        let milestoneCard = PetCardView([PetTheme.sectionHeader("Milestones"), PetTheme.wrapping(unlocked, size: 12, color: PetTheme.ink, width: 320)], spacing: 6)
        cards.append(milestoneCard)

        let follow = PetButton(s.isFollowing ? "Stop following" : "Follow my cursor", style: .primary) { [weak self] in
            self?.onFollowToggle?()
            self?.refresh(force: true)
        }
        let choose = PetButton("Companions…") { [weak self] in self?.onChooseCharacter?() }
        let settings = PetButton("Settings…") { [weak self] in self?.onOpenSettings?() }
        let work = PetButton("Productivity…") { [weak self] in self?.onOpenProductivity?() }
        cards.append(PetTheme.hstack([follow, work], spacing: 8))
        cards.append(PetTheme.hstack([choose, settings], spacing: 8))

        let stack = PetTheme.vstack(cards, spacing: 10)
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            now.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            productivity.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            together.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            today.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            milestoneCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 380, height: stack.fittingSize.height))
    }

    public func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
            self?.lastSnapshot = nil
        }
    }
}

/// A thin rounded progress bar in the theme's accent colour.
private final class FamiliarityBar: NSView {
    private let fill = CALayer()

    init(value: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        fill.cornerRadius = 4
        layer?.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 8).isActive = true
        self.value = min(max(value, 0), 1)
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel("Familiarity")
        setAccessibilityValue("\(Int((self.value * 100).rounded())) percent")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var value = 0.0

    override func layout() {
        super.layout()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PetTheme.accentSoft.cgColor
            fill.backgroundColor = PetTheme.accent.cgColor
        }
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * value, height: bounds.height)
    }
}
