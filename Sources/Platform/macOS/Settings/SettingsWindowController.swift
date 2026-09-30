import AppKit
import Core
import ServiceManagement

/// Settings: Companion · Display · Interaction · Environment · Privacy · System. Every control writes
/// straight through to `AppSettings` and takes effect immediately (size,
/// Spaces behavior and visibility exceptions apply live -- no relaunch).
/// The window is built lazily on first open.
public final class SettingsWindowController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings

    public var onPetSizeChanged: (() -> Void)?
    public var onPlacementChanged: (() -> Void)?
    public var onVisibilityPolicyChanged: (() -> Void)?
    public var onBehaviorSettingsChanged: (() -> Void)?
    public var onEnvironmentSettingsChanged: (() -> Void)?
    public var onResetPosition: (() -> Void)?
    public var onPetRenamed: (() -> Void)?
    public var dataDirectory: URL?

    private let nameField = NSTextField()
    private let lookLabel = PetTheme.label("", size: 13, weight: .semibold)
    public var onShowDiagnostics: (() -> Void)?
    public var onShortcutsChanged: (() -> Void)?
    /// Set when another app already owns one of the global shortcuts.
    public var shortcutProblem: (() -> String?)?
    public var onProductivityChanged: (() -> Void)?
    public var onReplayOnboarding: (() -> Void)?
    public var onResetSettings: (() -> Void)?
    public var onResetEverything: (() -> Void)?
    /// Local data export/import (Core's `DataPortability`, see
    /// Settings → Privacy). This window only presents the buttons and an
    /// `NSSavePanel`/`NSOpenPanel`; all serialize/validate/apply logic
    /// lives in Core and is unit tested there.
    public var onExportData: ((URL) -> Void)?
    public var onImportData: ((URL) -> Void)?

    /// Call after the companion changes so the window reflects it.
    public func characterChanged() {
        lookLabel.stringValue = characterNameProvider?() ?? ""
        nameField.placeholderString = characterNameProvider?() ?? "Name"
        window?.title = "\(displayName) Settings"
    }
    /// The current character's own name (used when no custom name is set).
    public var characterNameProvider: (() -> String)?
    public var onChooseCharacter: (() -> Void)?
    private var displayName: String { settings.customPetName ?? characterNameProvider?() ?? "Pet" }

    public init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    public func show() {
        let w = window ?? makeWindow()
        w.center()
        NSApp.activate(ignoringOtherApps: true) // a settings window is a deliberate, user-opened app window
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.title = "\(displayName) Settings"
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.delegate = self
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 540, height: 560))
        tabs.font = PetTheme.font(12, .medium)
        for (title, views) in [
            ("Companion", companionTab()), ("Productivity", productivityTab()), ("Display", displayTab()), ("Interaction", interactionTab()),
            ("Environment", environmentTab()), ("Privacy", privacyTab()), ("System", systemTab()),
        ] {
            let item = NSTabViewItem()
            item.label = title
            item.view = page(views)
            tabs.addTabViewItem(item)
        }
        w.contentView = tabs
        w.setContentSize(NSSize(width: 540, height: 560))
        window = w
        return w
    }

    // MARK: Layout helpers

    private func page(_ views: [NSView]) -> NSView {
        let stack = PetTheme.vstack(views, spacing: 10)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedDoc()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 480))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        return scroll
    }

    private func note(_ text: String) -> NSTextField { PetTheme.wrapping(text, size: 11, width: 440) }

    private func checkbox(_ title: String, _ on: Bool, _ change: @escaping (Bool) -> Void) -> NSButton {
        let b = ActionCheckbox(title: title, handler: change)
        b.state = on ? .on : .off
        b.font = PetTheme.font(13)
        return b
    }

    private func popup<T>(_ label: String, _ options: [T], _ selected: T, title: (T) -> String, _ change: @escaping (T) -> Void) -> NSView where T: Equatable {
        let p = ActionPopUp(handler: { index in change(options[index]) })
        p.addItems(withTitles: options.map(title))
        if let i = options.firstIndex(of: selected) { p.selectItem(at: i) }
        p.font = PetTheme.font(12.5)
        return PetTheme.hstack([PetTheme.label(label, size: 13), p], spacing: 8)
    }

    // MARK: Tabs

    private func companionTab() -> [NSView] {
        nameField.stringValue = settings.customPetName ?? ""
        nameField.placeholderString = characterNameProvider?() ?? "Name"
        nameField.delegate = self
        nameField.font = PetTheme.font(13)
        nameField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        lookLabel.stringValue = characterNameProvider?() ?? ""
        return [
            PetTheme.sectionHeader("Your companion"),
            PetTheme.hstack([PetTheme.label("Look", size: 13), lookLabel,
                             PetButton("Choose companion…") { [weak self] in self?.onChooseCharacter?() }], spacing: 8),
            PetTheme.hstack([PetTheme.label("Name", size: 13), nameField], spacing: 8),
            note("Leave the name empty to use the companion's own name. Switching companions keeps your stats, energy and everything else."),
            popup("Size", PetSize.allCases, settings.petSize, title: \.displayName) { [weak self] v in
                self?.settings.petSize = v
                self?.onPetSizeChanged?()
            },
            popup("Energy", ActivityLevel.allCases, settings.activityLevel, title: { $0.rawValue.capitalized }) { [weak self] v in
                self?.settings.activityLevel = v
                self?.onBehaviorSettingsChanged?()
            },
            note("Every companion follows the same natural rhythm: roam, sit, lie down, nap for 2-3 minutes, wake up. Calm companions roam less; energetic ones explore more."),
            popup("Interest in your cursor", FollowCursor.allCases, settings.followCursor, title: \.displayName) { [weak self] v in
                self?.settings.followCursor = v
                self?.onBehaviorSettingsChanged?()
            },
            popup("Talkativeness", Talkativeness.allCases, settings.talkativeness, title: \.displayName) { [weak self] v in
                self?.settings.talkativeness = v
                self?.onBehaviorSettingsChanged?()
            },
            checkbox("React with a bark or cheer sometimes when clicked", settings.barkOnClick) { [weak self] v in
                self?.settings.barkOnClick = v
                self?.onBehaviorSettingsChanged?()
            },
            checkbox("Speech bubbles", settings.speechBubbles) { [weak self] v in self?.settings.speechBubbles = v },
            checkbox("Reduced motion (no running, zoomies or breathing animation)", settings.reducedMotion) { [weak self] v in
                self?.settings.reducedMotion = v
                self?.onBehaviorSettingsChanged?()
            },
        ]
    }

    private func displayTab() -> [NSView] {
        [
            PetTheme.sectionHeader("Where it lives"),
            popup("When the app starts", StartPosition.allCases, settings.startPosition, title: \.displayName) { [weak self] v in
                self?.settings.startPosition = v
            },
            popup("Wandering range", RoamRange.allCases, settings.roamRange, title: \.displayName) { [weak self] v in
                self?.settings.roamRange = v
                self?.onPlacementChanged?()
            },
            checkbox("Show everywhere (all Spaces, full-screen apps, the desktop)", settings.showPetEverywhere) { [weak self] v in
                self?.settings.showPetEverywhere = v
                self?.onPlacementChanged?()
            },
            checkbox("Keep above other windows", settings.keepAboveWindows) { [weak self] v in
                self?.settings.keepAboveWindows = v
                self?.onPlacementChanged?()
            },
            PetTheme.sectionHeader("Step aside when…  (all off = always visible)"),
            checkbox("an app is in full screen", settings.hideInFullscreen) { [weak self] v in
                self?.settings.hideInFullscreen = v
                self?.onVisibilityPolicyChanged?()
            },
            checkbox("presenting (Keynote / PowerPoint slideshows)", settings.hideInPresentations) { [weak self] v in
                self?.settings.hideInPresentations = v
                self?.onVisibilityPolicyChanged?()
            },
            checkbox("playing a game", settings.hideInGames) { [weak self] v in
                self?.settings.hideInGames = v
                self?.onVisibilityPolicyChanged?()
            },
            note("The companion stays fully inside its display's visible area (above the Dock, below the menu bar). Drag it to another display to move it; if that display disconnects it returns to the main one."),
        ]
    }

    /// Standard choices, plus the current value if it isn't one of them.
    private static func options<T: Comparable>(_ base: [T], including current: T) -> [T] { base.contains(current) ? base : (base + [current]).sorted() }

    private func productivityTab() -> [NSView] {
        func changed() { onProductivityChanged?() }
        func minutes(_ v: Double) -> String { "\(Int(v)) min" }
        func hour(_ h: Int) -> String { String(format: "%02d:00", h) }
        let plan = settings.pomodoroPlan
        func setPlan(_ edit: (inout PomodoroPlan) -> Void) {
            var p = settings.pomodoroPlan
            edit(&p)
            settings.pomodoroPlan = p
            changed()
        }
        return [
            PetTheme.sectionHeader("Water"),
            checkbox("Ask me to drink water", settings.waterReminders) { [weak self] v in self?.settings.waterReminders = v; changed() },
            popup("Every", Self.options([30, 45, 60, 90, 120], including: settings.waterIntervalMinutes), settings.waterIntervalMinutes, title: minutes) { [weak self] v in self?.settings.waterIntervalMinutes = v; changed() },
            popup("Daily goal", Self.options(Array(4...12), including: settings.waterGoal), settings.waterGoal, title: { "\($0) glasses" }) { [weak self] v in self?.settings.waterGoal = v; changed() },
            PetTheme.sectionHeader("Breaks"),
            checkbox("Suggest a screen break after long stretches of work", settings.breakNudges) { [weak self] v in self?.settings.breakNudges = v; changed() },
            popup("After", Self.options([25, 40, 50, 60, 90], including: settings.breakIntervalMinutes), settings.breakIntervalMinutes, title: { "\(Int($0)) min of work" }) { [weak self] v in self?.settings.breakIntervalMinutes = v; changed() },
            checkbox("20-20-20 eye breaks (look 20 feet away for 20 seconds)", settings.eyeBreaks) { [weak self] v in self?.settings.eyeBreaks = v; changed() },
            popup("Eye break every", Self.options([20, 30, 45], including: settings.eyeBreakIntervalMinutes), settings.eyeBreakIntervalMinutes, title: minutes) { [weak self] v in self?.settings.eyeBreakIntervalMinutes = v; changed() },
            checkbox("Stretch and posture nudges", settings.stretchNudges) { [weak self] v in self?.settings.stretchNudges = v; changed() },
            popup("Stretch every", Self.options([30, 45, 60, 90], including: settings.stretchIntervalMinutes), settings.stretchIntervalMinutes, title: minutes) { [weak self] v in self?.settings.stretchIntervalMinutes = v; changed() },
            PetTheme.sectionHeader("Pomodoro"),
            popup("Work", Self.options([15, 20, 25, 30, 45, 50, 60, 90], including: plan.workMinutes), plan.workMinutes, title: minutes) { v in setPlan { $0.workMinutes = v } },
            popup("Short break", Self.options([3, 5, 10], including: plan.shortBreakMinutes), plan.shortBreakMinutes, title: minutes) { v in setPlan { $0.shortBreakMinutes = v } },
            popup("Long break", Self.options([10, 15, 20, 30], including: plan.longBreakMinutes), plan.longBreakMinutes, title: minutes) { v in setPlan { $0.longBreakMinutes = v } },
            popup("Long break after", Array(2...6), plan.sessionsBeforeLongBreak, title: { "\($0) sessions" }) { v in setPlan { $0.sessionsBeforeLongBreak = v } },
            checkbox("Start the next session automatically after a break", plan.autoStartNext) { v in setPlan { $0.autoStartNext = v } },
            popup("Daily focus goal", Self.options([30, 60, 90, 120, 180, 240, 360], including: settings.focusGoalMinutes), settings.focusGoalMinutes, title: { "\($0) min" }) { [weak self] v in self?.settings.focusGoalMinutes = v; changed() },
            PetTheme.sectionHeader("Tasks and reminders"),
            popup("New timed tasks remind me", Self.options([0, 5, 10, 15, 30, 60], including: settings.defaultTaskRemindMinutes), settings.defaultTaskRemindMinutes, title: { $0 == 0 ? "at the time" : "\($0) min before" }) { [weak self] v in self?.settings.defaultTaskRemindMinutes = v },
            checkbox("Let urgent task deadlines through quiet hours", settings.urgentBreaksQuiet) { [weak self] v in self?.settings.urgentBreaksQuiet = v; changed() },
            checkbox("Also show macOS notifications for reminders", settings.systemNotifications) { [weak self] v in self?.settings.systemNotifications = v; changed() },
            note("macOS will ask for notification permission the first time you turn this on. Reminders always appear from your companion either way."),
            PetTheme.sectionHeader("Briefs"),
            checkbox("Morning brief: today's tasks, the first time I'm around", settings.morningBrief) { [weak self] v in self?.settings.morningBrief = v; changed() },
            checkbox("Daily recap of what got done", settings.dailyRecap) { [weak self] v in self?.settings.dailyRecap = v; changed() },
            popup("Recap at", Array(15...22), settings.recapHour, title: hour) { [weak self] v in self?.settings.recapHour = v },
            checkbox("Bedtime reminder (offers to move open tasks to tomorrow)", settings.bedtimeReminder) { [weak self] v in self?.settings.bedtimeReminder = v; changed() },
            popup("Bedtime at", Array(20...23) + Array(0...2), settings.bedtimeHour, title: hour) { [weak self] v in self?.settings.bedtimeHour = v; changed() },
        ]
    }

    private func interactionTab() -> [NSView] {
        let mod = "⌃⌥⌘"
        return [
            PetTheme.sectionHeader("Keyboard shortcuts"),
            checkbox("Enable global shortcuts", settings.globalShortcuts) { [weak self] v in
                self?.settings.globalShortcuts = v
                self?.onShortcutsChanged?()
            },
            note("\(mod)F  Follow cursor on/off\n\(mod)H  Come here\n\(mod)S  Stop the current activity\n\(mod)D  Open the dashboard\n\(mod)P  Show or hide the companion\n\(mod)T  New task (quick add)\n\(mod)E  Start or stop a focus session\n\(mod)W  Log a glass of water\n\nThese use Control-Option-Command so they never clash with standard Mac shortcuts, and they need no special permission."),
            note(shortcutProblem?().map { "⚠︎ \($0)" } ?? ""),
            PetTheme.sectionHeader("Mouse"),
            note("Click to get its attention (it wakes if it's napping). Double-click to pet it (hearts!). The dashboard is in its menu or on ⌃⌥⌘D. Right-click for its menu. Drag it anywhere, even to another display. Click it while it's hiding to win Hide & Seek. Click it too many times and it gets annoyed for a while."),
            PetTheme.sectionHeader("Quiet hours"),
            PetTheme.hstack([
                popupView(Array(0...23), settings.quietHoursStart, title: { String(format: "%02d:00", $0) }) { [weak self] v in self?.settings.quietHoursStart = v; self?.onBehaviorSettingsChanged?() },
                PetTheme.label("to", size: 13),
                popupView(Array(0...23), settings.quietHoursEnd, title: { String(format: "%02d:00", $0) }) { [weak self] v in self?.settings.quietHoursEnd = v; self?.onBehaviorSettingsChanged?() },
            ], spacing: 8),
            note("During quiet hours the companion doesn't bark, sprint or chat."),
        ]
    }

    private func popupView<T: Equatable>(_ options: [T], _ selected: T, title: (T) -> String, _ change: @escaping (T) -> Void) -> NSPopUpButton {
        let p = ActionPopUp(handler: { index in change(options[index]) })
        p.addItems(withTitles: options.map(title))
        if let i = options.firstIndex(of: selected) { p.selectItem(at: i) }
        return p
    }

    /// The environment is deliberately small: one object, the bed, at the
    /// companion's home corner. Objects with no artwork are never listed.
    private func environmentTab() -> [NSView] {
        [
            PetTheme.sectionHeader("Environment"),
            note("Objects your companion can use. It decides on its own when to visit them -- this only controls what's available."),
            checkbox("Bed (at the companion's home corner)", settings.bedEnabled) { [weak self] v in
                self?.settings.bedEnabled = v
                self?.onEnvironmentSettingsChanged?()
            },
            PetButton("Reset environment") { [weak self] in
                self?.settings.bedEnabled = true
                self?.onEnvironmentSettingsChanged?()
            },
        ]
    }

    private func systemTab() -> [NSView] {
        let loginBox = checkbox("Launch at login", LoginItemManager.isEnabled()) { v in
            LoginItemManager.setEnabled(v)
        }
        loginBox.identifier = NSUserInterfaceItemIdentifier("launchAtLogin")
        var views: [NSView] = [
            PetTheme.sectionHeader("System"),
            loginBox,
            note(LoginItemManager.statusNote()),
            PetButton("Bring companion back to its corner") { [weak self] in self?.onResetPosition?() },
            PetButton("Show the welcome tour again") { [weak self] in self?.onReplayOnboarding?() },
        ]
        if dataDirectory != nil {
            views.append(PetButton("Show data folder in Finder") { [weak self] in
                if let dir = self?.dataDirectory { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
            })
        }
        views.append(PetTheme.sectionHeader("Your data"))
        views.append(note("Export your settings, character selection, favorites and how long you\'ve been together to a JSON file you keep -- or import one back in. Your task list and history stay on this Mac and are never exported."))
        views.append(PetTheme.hstack([
            PetButton("Export data…") { [weak self] in self?.exportData() },
            PetButton("Import data…") { [weak self] in self?.importData() },
        ], spacing: 10))
        views.append(PetTheme.sectionHeader("Reset"))
        views.append(note("Each action below asks you to confirm and only does what it says."))
        views.append(PetButton("Reset settings…") { [weak self] in
            self?.confirmDestructive(
                title: "Reset settings?",
                message: "Puts every preference back to its default. Your companion\'s memory and progress are kept.",
                confirmTitle: "Reset Settings",
                action: { self?.onResetSettings?() }
            )
        })
        views.append(PetButton("Reset everything…") { [weak self] in
            self?.confirmDestructive(
                title: "Reset everything?",
                message: "Deletes your companion\'s memory and progress, all tasks, reminders and productivity history, and resets all settings. Quit and reopen the app afterward for a fully clean start.",
                confirmTitle: "Reset Everything",
                action: { self?.onResetEverything?() }
            )
        })
        return views
    }

    /// Presents a save panel for a JSON export, then hands the chosen URL
    /// to `onExportData` (which calls Core's `DataPortability.exportJSON`
    /// and writes it) -- this window never touches `AppSettings`/
    /// `ProgressionStore` fields directly for this, and never builds the
    /// JSON itself.
    private func exportData() {
        let panel = NSSavePanel()
        panel.title = "Export Data"
        panel.nameFieldStringValue = "DesktopCompanion-export.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.onExportData?(url)
        }
    }

    /// Presents an open panel for a previously-exported JSON file, then
    /// hands the chosen URL to `onImportData`. Validation/failure handling
    /// (malformed JSON, wrong schema version, out-of-range values) all
    /// happens in Core and is surfaced back to the user by the caller
    /// (`AppDelegate`), never assumed to have succeeded here.
    private func importData() {
        let panel = NSOpenPanel()
        panel.title = "Import Data"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.onImportData?(url)
        }
    }

    /// One shared confirmation path for every destructive Settings action --
    /// no one-click destructive button anywhere in this window.
    private func confirmDestructive(title: String, message: String, confirmTitle: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { action() }
        }
    }

    private func privacyTab() -> [NSView] {
        [
            PetTheme.sectionHeader("Stored locally on this Mac"),
            note("Your settings, your tasks and reminders, focus and water history, screen-time totals (minutes only), and your companion's state (position, energy, behaviors seen, daily pats and naps, favorite activity). Nothing leaves this Mac."),
            PetTheme.sectionHeader("Never collected"),
            note("Screen contents, keystrokes (only the time since your last input is read, to know if you're around), clipboard, camera, microphone, URLs, window titles. There is no network code and no AI service -- behavior is local, rule-based and deterministic."),
            PetTheme.sectionHeader("Optional: notice which app is in front"),
            checkbox("Comment when I switch kinds of app (off by default)", settings.appAwareChatter) { [weak self] v in self?.settings.appAwareChatter = v },
            note("For example \"Ship it!\" when you switch to Xcode. Every 30 seconds it reads only which app is in front (its identifier, not its windows, documents or pages), sorts it into a broad kind, and forgets it. Nothing is stored or sent anywhere."),
            PetTheme.sectionHeader("Permissions"),
            note("None are required. The app never asks for accessibility, screen recording, camera, microphone or file access. macOS notification banners are optional (Productivity tab) — the permission is asked only if you turn them on. The frontmost app's name is read only if you turn on a \"step aside\" option (Display) or \"comment on what I'm doing\" (Interaction)."),
        ]
    }

    /// Settings is opened rarely; don't keep its view tree alive.
    public func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
        }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === nameField else { return }
        settings.customPetName = nameField.stringValue
        window?.title = "\(displayName) Settings"
        onPetRenamed?()
    }
}

// MARK: - Closure-backed controls

final class ActionCheckbox: NSButton {
    private let handler: (Bool) -> Void
    init(title: String, handler: @escaping (Bool) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        target = self
        action = #selector(changed)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func changed() { handler(state == .on) }
}

final class ActionPopUp: NSPopUpButton {
    private let handler: (Int) -> Void
    init(handler: @escaping (Int) -> Void) {
        self.handler = handler
        super.init(frame: .zero, pullsDown: false)
        target = self
        action = #selector(changed)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func changed() { handler(indexOfSelectedItem) }
}

final class ActionSlider: NSSlider {
    private let handler: (Double) -> Void
    init(value: Double, handler: @escaping (Double) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        minValue = 0
        maxValue = 1
        doubleValue = value
        target = self
        action = #selector(changed)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func changed() { handler(doubleValue) }
}

/// Wraps SMAppService (macOS 13+) for "Launch at Login". The checkbox always
/// reflects the system's real state, and a failed change is reported instead
/// of silently ignored.
public enum LoginItemManager {
    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[DesktopCompanion] Launch-at-login change failed: %@", "\(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "macOS refused the change (\(error.localizedDescription)). Make sure Desktop Companion is in your Applications folder, or add it in System Settings → General → Login Items."
            alert.runModal()
        }
    }

    public static func isEnabled() -> Bool { SMAppService.mainApp.status == .enabled }

    static func statusNote() -> String {
        switch SMAppService.mainApp.status {
        case .requiresApproval: return "macOS needs your approval: System Settings → General → Login Items."
        case .notFound: return "Move Desktop Companion to your Applications folder to use this."
        default: return "Starts the companion when you log in."
        }
    }
}

private final class FlippedDoc: NSView { override var isFlipped: Bool { true } }
