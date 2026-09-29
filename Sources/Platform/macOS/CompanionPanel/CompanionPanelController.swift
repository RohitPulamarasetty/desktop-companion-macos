import AppKit
import Core

/// Everything the home panel shows, computed by the app layer. Equatable so
/// the panel can skip rebuilding when nothing changed.
public struct HomeSnapshot: Equatable {
    public var petName = "Biscuit"
    public var petStatus = ""
    /// 0...1, the companion's rest level ("what does it need?").
    public var petEnergy = 1.0
    /// "What's next?" from the real schedules (focus, reminders, water, breaks).
    public var nextEvent = ""
    public var characterName = ""
    public var greeting = ""
    public var tasksDoneToday = 0
    public var focusSessionsToday = 0
    public var focusMinutesToday = 0
    public var waterToday = 0
    public var waterGoal = 8
    public var breaksToday = 0
    public var activeMinutesToday = 0
    public var tasks: [TaskItem] = []
    public var reminders: [ReminderItem] = []
    public var focusPhase: FocusPhase = .idle
    public var daysTogether = 1
    public var discoveredBehaviors = 0
    public var totalBehaviors = 0
    public var petClicksToday = 0
    public var petNapsToday = 0
    public var petMetersWalkedToday = 0
    public var milestones: [String] = []
    public var lockedMilestones: [String] = []
    public var mood = ""
    public var upcomingTasks: [TaskItem] = []
    public var focusBreaksToday = 0
    public var lastWater: Date?
    public var nextWater: Date?
    public var idleMinutesToday = 0
    public var continuousWorkMinutes = 0
    public init() {}
}

/// What the "New task" form produces.
public struct TaskDraft {
    public var title: String
    public var notes = ""
    public var dueDate: Date?
    public var hasDueTime = false
    public var remindBeforeMinutes: Int?
    public var repeatEveryMinutes: Int?
    public var priority: TaskPriority = .medium
}

/// The pet's "home": one compact, pet-themed panel that pops out of the pet
/// (double-click it, or pick an item from its right-click menu). Sections:
/// Today, Tasks, Focus, Wellness (water, breaks, reminders), Pet.
///
/// Performance: the window is created lazily on first open; while hidden it
/// does no work at all (the previous panel was rebuilt every 5 seconds
/// while invisible, which profiling showed as a top CPU cost). While
/// visible, a section is rebuilt only when its data actually changed; the
/// focus countdown updates a single label.
/// Display title for each section's segmented-control label. Kept here
/// (not in Core) since it's UI copy, not domain data -- `PetMenuSection`
/// itself stays copy-free so a Windows/Linux `PlatformTray` conformer can
/// supply its own localized strings instead of inheriting these.
extension PetMenuSection {
    var title: String {
        switch self {
        case .today: return "Today"
        case .tasks: return "Tasks"
        case .focus: return "Focus"
        case .wellness: return "Wellness"
        case .pet: return "Pet"
        }
    }
}

public final class CompanionPanelController: NSObject, NSTextFieldDelegate {
    /// `PetMenuSection` (Core, pure Swift) is the single definition now --
    /// this used to be its own nested enum, kept in sync by hand with
    /// `PetMenuActions.openHome`'s parameter type. See `docs/PLATFORM_PROTOCOLS.md`.
    public typealias Section = PetMenuSection

    public var onAddTask: ((TaskDraft) -> Void)?
    public var onToggleTask: ((UUID) -> Void)?
    public var onDeleteTask: ((UUID) -> Void)?
    public var onStartFocus: ((Double, Double) -> Void)?
    public var onPauseFocus: (() -> Void)?
    public var onResumeFocus: (() -> Void)?
    public var onSkipFocus: (() -> Void)?
    public var onCancelFocus: (() -> Void)?
    public var onLogWater: (() -> Void)?
    public var onTakeBreak: (() -> Void)?
    public var onAddReminder: ((String, Date) -> Void)?
    public var onDeleteReminder: ((UUID) -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onBringPetHome: (() -> Void)?
    public var onChooseCharacter: (() -> Void)?
    /// Asked for fresh data whenever the panel opens or switches section.
    public var snapshotProvider: (() -> HomeSnapshot)?
    public var avatarProvider: (() -> CGImage?)?
    /// Frames of the clip the pet is playing on the desktop right now, so the
    /// Home header shows the real, live pet (render-server animated).
    public var liveClipProvider: (() -> (frames: [CGImage], fps: Double, mirrored: Bool)?)?
    private var livePreview: LayerImageView?
    private var liveKey: ObjectIdentifier?

    private var panel: NSPanel?
    private var segmented: NSSegmentedControl?
    private lazy var body = NSStackView()
    private var root: NSStackView?
    private lazy var headerName = PetTheme.label("", size: 15, weight: .bold)
    private lazy var headerStatus = PetTheme.label("", size: 11.5, color: PetTheme.inkSoft)
    private var avatar: PetAvatarView?
    private var focusClock: NSTextField?
    private var section: Section = .today
    private var lastSnapshot: HomeSnapshot?
    private var lastSection: Section?
    private lazy var taskField = NSTextField()
    private lazy var taskNotes = NSTextField()
    private lazy var taskDue = NSPopUpButton()
    private lazy var taskDate = NSDatePicker()
    // Controls are created on first use: the Home panel is built only when
    // opened, and date pickers in particular pull in calendar/ICU data.
    private lazy var taskTimeToggle = NSButton(checkboxWithTitle: "at", target: nil, action: nil)
    private lazy var taskTime = NSDatePicker()
    private lazy var taskRemind = NSPopUpButton()
    private lazy var taskRepeat = NSPopUpButton()
    private lazy var taskPriority = NSPopUpButton()
    private lazy var focusCustom = NSPopUpButton()
    private lazy var reminderField = NSTextField()
    private lazy var reminderWhen = NSPopUpButton()
    private let width: CGFloat = 360

    public override init() { super.init() }

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var visibleSection: Section? { isVisible ? section : nil }

    // MARK: Window

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 480),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.backgroundColor = PetTheme.paper
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        let root = PetTheme.vstack(spacing: 12)
        self.root = root
        root.edgeInsets = NSEdgeInsets(top: 34, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let preview = LayerImageView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 60).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 60).isActive = true
        preview.imageLayer.contents = avatarProvider?()
        livePreview = preview
        let names = PetTheme.vstack([headerName, headerStatus], spacing: 1)
        let header = PetTheme.hstack([preview, names, PetTheme.spacer()], spacing: 10)
        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true

        let seg = NSSegmentedControl(labels: Section.allCases.map(\.title), trackingMode: .selectOne,
                                     target: self, action: #selector(sectionChanged(_:)))
        seg.segmentStyle = .rounded
        seg.font = PetTheme.font(12, .semibold)
        seg.selectedSegment = section.rawValue
        segmented = seg
        root.addArrangedSubview(seg)
        seg.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true

        body = PetTheme.vstack(spacing: 10)
        root.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.widthAnchor.constraint(equalToConstant: width),
        ])
        p.contentView = content

        taskField.placeholderString = "Add a task and press Return…"
        taskField.delegate = self
        taskField.font = PetTheme.font(13)
        taskField.focusRingType = .none
        reminderField.placeholderString = "Remind me to…"
        reminderField.delegate = self
        reminderField.font = PetTheme.font(13)
        reminderField.focusRingType = .none
        reminderWhen.addItems(withTitles: ["in 15 min", "in 30 min", "in 1 hour", "in 2 hours", "tomorrow 9:00"])
        reminderWhen.font = PetTheme.font(12)
        configureTaskForm()
        panel = p
        return p
    }

    public func show(section newSection: Section? = nil, near petFrame: NSRect? = nil) {
        let p = panel ?? makePanel()
        if let newSection { section = newSection }
        segmented?.selectedSegment = section.rawValue
        updateLivePreview(force: true)
        refresh(force: true)
        if !p.isVisible, let petFrame { position(p, near: petFrame) }
        // Non-activating: the app the user was in stays active; the panel
        // only takes keyboard focus when a text field is clicked.
        p.orderFrontRegardless()
    }

    public func toggle(near petFrame: NSRect? = nil) {
        if isVisible { panel?.orderOut(nil) } else { show(near: petFrame) }
    }

    public func hide() { panel?.orderOut(nil) }

    private func position(_ p: NSPanel, near petFrame: NSRect) {
        let size = p.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.screens.first
        var origin = NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 4)
        if let v = screen?.visibleFrame {
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        p.setFrameOrigin(origin)
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        section = Section(rawValue: sender.selectedSegment) ?? .today
        refresh(force: true)
    }

    // MARK: Refresh

    /// Pulls a fresh snapshot and rebuilds the visible section only if it
    /// changed. No-op while hidden.
    public func refresh(force: Bool = false) {
        guard let panel, force || panel.isVisible, let snap = snapshotProvider?() else { return }
        updateLivePreview(force: force)
        headerName.stringValue = snap.petName
        headerStatus.stringValue = snap.petStatus
        // The status line changes with every behavior; it only touches the
        // header label, never a rebuild of the section.
        var comparable = snap
        comparable.petStatus = ""
        if !force, comparable == lastSnapshot, lastSection == section { return }
        lastSnapshot = comparable
        lastSection = section
        rebuild(snap)
    }

    /// Plays the pet's current desktop clip in the header (CA keyframes; no
    /// timers here). Restarts only when the clip actually changed.
    private func updateLivePreview(force: Bool) {
        guard let preview = livePreview, let clip = liveClipProvider?(), let first = clip.frames.first else {
            if force { livePreview?.imageLayer.contents = avatarProvider?() }
            return
        }
        let key = ObjectIdentifier(first)
        guard force || key != liveKey else { return }
        liveKey = key
        let layer = preview.imageLayer
        layer.removeAnimation(forKey: "live")
        layer.contents = first
        layer.setAffineTransform(clip.mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        if clip.frames.count > 1 {
            let a = CAKeyframeAnimation(keyPath: "contents")
            a.values = clip.frames
            a.calculationMode = .discrete
            a.duration = Double(clip.frames.count) / max(clip.fps, 0.5)
            a.repeatCount = .infinity
            layer.add(a, forKey: "live")
        }
    }

    /// Cheap per-second update of just the focus countdown label.
    public func updateFocusClock(_ phase: FocusPhase) {
        guard isVisible, section == .focus || section == .today, let focusClock else { return }
        focusClock.stringValue = Self.focusText(phase)
    }

    private func rebuild(_ s: HomeSnapshot) {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        focusClock = nil
        let cards: [NSView]
        switch section {
        case .today: cards = todayCards(s)
        case .tasks: cards = taskCards(s)
        case .focus: cards = focusCards(s)
        case .wellness: cards = wellnessCards(s)
        case .pet: cards = petCards(s)
        }
        for c in cards {
            body.addArrangedSubview(c)
            c.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        if let p = panel, let root {
            root.layoutSubtreeIfNeeded()
            let size = NSSize(width: width, height: ceil(root.fittingSize.height))
            let top = p.isVisible ? p.frame.maxY : nil
            p.setContentSize(size)
            if let top { p.setFrameOrigin(NSPoint(x: p.frame.minX, y: top - p.frame.height)) }
        }
    }

    // MARK: Sections

    private func statTile(_ value: String, _ caption: String, _ color: NSColor) -> NSView {
        let v = PetTheme.label(value, size: 20, weight: .bold, color: color)
        let c = PetTheme.label(caption, size: 10.5, color: PetTheme.inkSoft)
        let s = PetTheme.vstack([v, c], spacing: 0, alignment: .centerX)
        return s
    }

    private static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private static func relative(_ d: Date, now: Date = Date()) -> String {
        let m = Int((d.timeIntervalSince(now) / 60).rounded())
        if abs(m) < 1 { return "now" }
        if m > 0 { return m < 60 ? "in \(m) min" : "in \(m / 60) h \(m % 60) min" }
        return -m < 60 ? "\(-m) min ago" : "\(-m / 60) h ago"
    }

    private func todayCards(_ s: HomeSnapshot) -> [NSView] {
        // Companion: how it's doing right now (all live pet state).
        let energyBar = NSLevelIndicator()
        energyBar.levelIndicatorStyle = .continuousCapacity
        energyBar.minValue = 0
        energyBar.maxValue = 1
        energyBar.doubleValue = s.petEnergy
        energyBar.fillColor = PetTheme.leaf
        energyBar.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let moodLine = PetTheme.hstack([PetTheme.label(s.mood, size: 12.5, weight: .semibold),
                                        PetTheme.label("· \(s.petStatus)", size: 12, color: PetTheme.inkSoft),
                                        PetTheme.spacer(), PetTheme.label("energy", size: 10.5, color: PetTheme.inkSoft), energyBar], spacing: 5)
        let companion = PetCardView([PetTheme.sectionHeader(s.greeting), moodLine], spacing: 6)
        moodLine.widthAnchor.constraint(equalTo: companion.stack.widthAnchor).isActive = true

        let tiles = NSStackView(views: [
            statTile("\(s.tasksDoneToday)", "tasks done", PetTheme.accent),
            statTile(Self.duration(s.focusMinutesToday), "focus", PetTheme.leaf),
            statTile("\(s.waterToday)/\(s.waterGoal)", "water", PetTheme.water),
            statTile(Self.duration(s.activeMinutesToday), "active", PetTheme.inkSoft),
            statTile("\(s.breaksToday + s.focusBreaksToday)", "breaks", PetTheme.inkSoft),
        ])
        tiles.distribution = .fillEqually
        let summary = PetCardView([PetTheme.sectionHeader("Today"), tiles], spacing: 8)
        tiles.widthAnchor.constraint(equalTo: summary.stack.widthAnchor).isActive = true

        let clock = PetTheme.label(Self.focusText(s.focusPhase), size: 12.5, weight: .medium, color: PetTheme.inkSoft)
        focusClock = clock
        var actionViews: [NSView] = [PetButton("+ Task") { [weak self] in self?.show(section: .tasks) }]
        if case .idle = s.focusPhase {
            actionViews.append(PetButton("Focus 25", style: .primary) { [weak self] in self?.onStartFocus?(25, 5) })
        }
        actionViews.append(PetButton("💧 Water") { [weak self] in self?.onLogWater?() })
        actionViews.append(PetButton("☕ Break") { [weak self] in self?.onTakeBreak?() })
        for case let b as PetButton in actionViews { b.horizontalPadding = 10 }
        let actions = PetTheme.hstack(actionViews, spacing: 5)
        actions.distribution = .fillEqually
        let quick = PetCardView([PetTheme.sectionHeader("Quick actions"), clock, actions])
        actions.widthAnchor.constraint(equalTo: quick.stack.widthAnchor).isActive = true

        var next: [NSView] = [PetTheme.sectionHeader("Next")]
        if !s.nextEvent.isEmpty, s.nextEvent != "Nothing scheduled" { next.append(PetTheme.label("⏱  \(s.nextEvent)", size: 13)) }
        let openTasks = s.tasks.filter { !$0.isCompleted }
        for t in openTasks.prefix(2) { next.append(taskLine(t, size: 13)) }
        if next.count == 1 { next.append(PetTheme.label("Nothing waiting. \(s.petName) approves. ✨", size: 12.5, color: PetTheme.inkSoft)) }
        return [companion, summary, quick, PetCardView(next, spacing: 5)]
    }

    /// "☐ Title · due today 5:00 PM · ⏰" (overdue in the accent colour).
    private func taskLine(_ t: TaskItem, size: CGFloat = 12.5) -> NSView {
        var detail = ""
        if let d = t.deadline() {
            let overdue = d < Date() && !t.isCompleted
            detail = overdue ? "overdue" : Self.dueText(d, hasTime: t.hasDueTime)
        }
        let mark = t.priority == .high ? "❗" : "☐"
        let title = PetTheme.label("\(mark)  \(t.title)", size: size)
        var views: [NSView] = [title]
        if !detail.isEmpty {
            let overdue = detail == "overdue"
            views.append(PetTheme.label("· \(detail)\(t.remindBeforeMinutes != nil || t.repeatEveryMinutes != nil ? " ⏰" : "")", size: size - 1.5,
                                        color: overdue ? PetTheme.accent : PetTheme.inkSoft))
        }
        return PetTheme.hstack(views, spacing: 4)
    }

    static func dueText(_ d: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        tf.dateStyle = .none
        let time = hasTime ? " \(tf.string(from: d))" : ""
        if cal.isDateInToday(d) { return "today\(time)" }
        if cal.isDateInTomorrow(d) { return "tomorrow\(time)" }
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        return df.string(from: d) + time
    }

    private func configureTaskForm() {
        taskNotes.placeholderString = "Notes (optional)"
        taskNotes.font = PetTheme.font(12)
        taskNotes.focusRingType = .none
        taskDue.addItems(withTitles: ["No due date", "Today", "Tomorrow", "Pick a date…"])
        taskDue.target = self
        taskDue.action = #selector(taskFormChanged)
        taskDate.datePickerElements = [.yearMonthDay]
        taskDate.datePickerStyle = .textFieldAndStepper
        taskDate.dateValue = Date()
        taskDate.minDate = Calendar.current.startOfDay(for: Date())
        taskTime.datePickerElements = [.hourMinute]
        taskTime.datePickerStyle = .textFieldAndStepper
        taskTime.dateValue = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
        taskTimeToggle.target = self
        taskTimeToggle.action = #selector(taskFormChanged)
        taskRemind.addItems(withTitles: ["No reminder", "30 min before", "45 min before", "1 hour before", "1 day before"])
        taskRepeat.addItems(withTitles: ["Don't nag", "Nudge every 30 min", "Nudge every 45 min", "Nudge every 60 min"])
        taskPriority.addItems(withTitles: ["Normal", "High", "Low"])
        for p in [taskDue, taskRemind, taskRepeat, taskPriority] { p.font = PetTheme.font(11.5); p.controlSize = .small }
        taskDate.font = PetTheme.font(11.5)
        taskTime.font = PetTheme.font(11.5)
        taskTimeToggle.font = PetTheme.font(11.5)
        focusCustom.addItems(withTitles: ["Custom…"] + [10, 20, 30, 40, 50, 75, 90, 120].map { "\($0) min" })
        focusCustom.font = PetTheme.font(12)
        focusCustom.target = self
        focusCustom.action = #selector(customFocusChosen)
        taskFormChanged()
    }

    @objc private func taskFormChanged() {
        let hasDate = taskDue.indexOfSelectedItem > 0
        taskDate.isHidden = taskDue.indexOfSelectedItem != 3
        taskTimeToggle.isHidden = !hasDate
        taskTime.isHidden = !hasDate || taskTimeToggle.state != .on
        taskRemind.isEnabled = hasDate
        if !hasDate { taskRemind.selectItem(at: 0) }
    }

    @objc private func customFocusChosen() {
        let i = focusCustom.indexOfSelectedItem
        guard i > 0 else { return }
        let minutes = [10, 20, 30, 40, 50, 75, 90, 120][i - 1]
        focusCustom.selectItem(at: 0)
        onStartFocus?(Double(minutes), Double(max(3, minutes / 5)))
    }

    private func taskCards(_ s: HomeSnapshot) -> [NSView] {
        taskField.stringValue = ""
        taskNotes.stringValue = ""
        let add = PetButton("Add", style: .primary) { [weak self] in self?.submitTask() }
        let input = PetTheme.hstack([taskField, add], spacing: 6)
        taskField.setContentHuggingPriority(.init(1), for: .horizontal)
        let dueRow = PetTheme.hstack([PetTheme.label("Due", size: 11.5, color: PetTheme.inkSoft), taskDue, taskDate, taskTimeToggle, taskTime, PetTheme.spacer()], spacing: 5)
        let remindRow = PetTheme.hstack([taskRemind, taskRepeat, PetTheme.spacer()], spacing: 5)
        let extraRow = PetTheme.hstack([taskPriority, taskNotes], spacing: 5)
        taskNotes.setContentHuggingPriority(.init(1), for: .horizontal)
        let note = PetTheme.label("Reminder: before the deadline · Nudge: until done", size: 10.5, color: PetTheme.inkSoft)
        let inputCard = PetCardView([PetTheme.sectionHeader("New task"), input, dueRow, remindRow, extraRow, note], spacing: 6)
        for r in [input, dueRow, remindRow, extraRow] { r.widthAnchor.constraint(equalTo: inputCard.stack.widthAnchor).isActive = true }
        taskFormChanged()

        var rows: [NSView] = [PetTheme.sectionHeader("Today (\(s.tasks.filter(\.isCompleted).count)/\(s.tasks.count) done)")]
        for task in s.tasks.prefix(10) {
            let box = NSButton(checkboxWithTitle: task.title, target: self, action: #selector(taskToggled(_:)))
            box.state = task.isCompleted ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(task.id.uuidString)
            box.attributedTitle = NSAttributedString(string: (task.priority == .high ? "❗ " : "") + task.title, attributes: [
                .font: PetTheme.font(13),
                .foregroundColor: task.isCompleted ? PetTheme.inkSoft : PetTheme.ink,
                .strikethroughStyle: task.isCompleted ? NSUnderlineStyle.single.rawValue : 0,
            ])
            var parts: [String] = []
            if let d = task.deadline(), !task.isCompleted {
                parts.append(d < Date() ? "overdue" : Self.dueText(d, hasTime: task.hasDueTime))
            }
            if let r = task.remindBeforeMinutes, !task.isCompleted { parts.append("⏰ \(r >= 1440 ? "1 day" : "\(r) min") before") }
            if let e = task.repeatEveryMinutes, !task.isCompleted { parts.append("↻ every \(e) min") }
            if !task.notes.isEmpty { parts.append(task.notes) }
            let id = task.id
            let del = PetButton("✕", style: .quiet) { [weak self] in self?.onDeleteTask?(id) }
            var left: [NSView] = [box]
            if !parts.isEmpty {
                let d = PetTheme.label(parts.joined(separator: " · "), size: 11, color: parts.first == "overdue" ? PetTheme.accent : PetTheme.inkSoft)
                left.append(d)
            }
            let col = PetTheme.vstack(left, spacing: 1)
            rows.append(PetTheme.hstack([col, PetTheme.spacer(), del], spacing: 6))
        }
        if s.tasks.count > 10 { rows.append(PetTheme.label("+\(s.tasks.count - 10) more", size: 11.5, color: PetTheme.inkSoft)) }
        if s.tasks.isEmpty { rows.append(PetTheme.label("No tasks yet. Add one above!", size: 12.5, color: PetTheme.inkSoft)) }
        let list = PetCardView(rows, spacing: 6)
        for r in rows.dropFirst() { r.widthAnchor.constraint(equalTo: list.stack.widthAnchor).isActive = true }
        var cards: [NSView] = [inputCard, list]
        if !s.upcomingTasks.isEmpty {
            var up: [NSView] = [PetTheme.sectionHeader("Coming up")]
            up += s.upcomingTasks.map { taskLine($0) }
            cards.append(PetCardView(up, spacing: 5))
        }
        return cards
    }

    private func focusCards(_ s: HomeSnapshot) -> [NSView] {
        let clock = PetTheme.label(Self.focusText(s.focusPhase), size: 22, weight: .bold)
        clock.font = PetTheme.mono(22)
        focusClock = clock
        var buttons: [NSView] = []
        switch s.focusPhase {
        case .idle:
            buttons = [PetButton("15") { [weak self] in self?.onStartFocus?(15, 3) },
                       PetButton("25", style: .primary) { [weak self] in self?.onStartFocus?(25, 5) },
                       PetButton("45") { [weak self] in self?.onStartFocus?(45, 10) },
                       PetButton("60") { [weak self] in self?.onStartFocus?(60, 10) },
                       focusCustom]
        case .focusing, .onBreak:
            buttons = [PetButton("Pause") { [weak self] in self?.onPauseFocus?() },
                       PetButton("Skip") { [weak self] in self?.onSkipFocus?() },
                       PetButton("Stop", style: .quiet) { [weak self] in self?.onCancelFocus?() }]
        case .paused:
            buttons = [PetButton("Resume", style: .primary) { [weak self] in self?.onResumeFocus?() },
                       PetButton("Stop", style: .quiet) { [weak self] in self?.onCancelFocus?() }]
        }
        let hint = PetTheme.wrapping("The timer sits on \(s.petName) while you focus. It settles down beside you and stays quiet until you're done.", width: width - 60)
        let main = PetCardView([PetTheme.sectionHeader("Focus session (minutes)"), clock, PetTheme.hstack(buttons, spacing: 6), hint], spacing: 10)
        let today = PetCardView([PetTheme.sectionHeader("Today"),
                                 PetTheme.label("\(Self.plural(s.focusSessionsToday, "session")) · \(Self.duration(s.focusMinutesToday)) focused · \(Self.plural(s.focusBreaksToday, "focus break"))", size: 13)])
        return [main, today]
    }

    private func wellnessCards(_ s: HomeSnapshot) -> [NSView] {
        let progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = Double(max(s.waterGoal, 1))
        progress.doubleValue = Double(min(s.waterToday, s.waterGoal))
        progress.controlSize = .small
        var waterInfo: [String] = []
        if let last = s.lastWater { waterInfo.append("last \(Self.relative(last))") }
        if let next = s.nextWater { waterInfo.append(next <= Date() ? "next check soon" : "next check \(Self.relative(next))") }
        let water = PetCardView([
            PetTheme.sectionHeader("Water"),
            PetTheme.label("\(s.waterToday) of \(s.waterGoal) glasses today", size: 13, weight: .semibold),
            progress,
            PetTheme.label(waterInfo.isEmpty ? "No water logged yet today" : waterInfo.joined(separator: " · "), size: 11.5, color: PetTheme.inkSoft),
            PetButton("💧 I drank water", style: .primary) { [weak self] in self?.onLogWater?() },
        ])
        progress.widthAnchor.constraint(equalTo: water.stack.widthAnchor).isActive = true

        let screen = PetCardView([
            PetTheme.sectionHeader("Screen time today"),
            PetTheme.label("Active \(Self.duration(s.activeMinutesToday)) · Idle \(Self.duration(s.idleMinutesToday))", size: 13, weight: .semibold),
            PetTheme.label("Working for \(Self.duration(s.continuousWorkMinutes)) since your last break", size: 11.5, color: PetTheme.inkSoft),
            PetTheme.label("\(Self.plural(s.breaksToday, "screen break")) · \(Self.plural(s.focusBreaksToday, "focus break"))", size: 11.5, color: PetTheme.inkSoft),
            PetButton("☕ Take a break now") { [weak self] in self?.onTakeBreak?() },
        ])

        reminderField.stringValue = ""
        let add = PetButton("Add", style: .primary) { [weak self] in self?.submitReminder() }
        let row = PetTheme.hstack([reminderWhen, PetTheme.spacer(), add], spacing: 6)
        var remViews: [NSView] = [PetTheme.sectionHeader("Reminders"), reminderField, row]
        for r in s.reminders.prefix(6) {
            let id = r.id
            let line = PetTheme.hstack([PetTheme.label("⏰ \(r.title)", size: 12.5),
                                        PetTheme.spacer(),
                                        PetTheme.label(Self.timeText(max(r.fireDate, r.snoozedUntil ?? r.fireDate)), size: 11.5, color: PetTheme.inkSoft),
                                        PetButton("✕", style: .quiet) { [weak self] in self?.onDeleteReminder?(id) }], spacing: 6)
            remViews.append(line)
        }
        if s.reminders.isEmpty { remViews.append(PetTheme.label("No upcoming reminders.", size: 12, color: PetTheme.inkSoft)) }
        let reminders = PetCardView(remViews)
        for v in remViews.dropFirst() { v.widthAnchor.constraint(equalTo: reminders.stack.widthAnchor).isActive = true }
        return [water, screen, reminders]
    }

    private func petCards(_ s: HomeSnapshot) -> [NSView] {
        let about = PetCardView([
            PetTheme.sectionHeader("About \(s.petName)"),
            PetTheme.label("Day \(s.daysTogether) together", size: 13, weight: .semibold),
            PetTheme.label("Behaviors discovered: \(s.discoveredBehaviors) of \(s.totalBehaviors)", size: 12.5),
            PetTheme.label("Today: \(s.petClicksToday) pats · \(s.petNapsToday) naps · \(s.petMetersWalkedToday) m walked", size: 12.5, color: PetTheme.inkSoft),
        ])
        var ms: [NSView] = [PetTheme.sectionHeader("Milestones")]
        ms += s.milestones.map { PetTheme.label("🏅 \($0)", size: 12.5) }
        ms += s.lockedMilestones.map { PetTheme.label("🔒 \($0)", size: 12.5, color: PetTheme.inkSoft) }
        let milestones = PetCardView(ms, spacing: 4)
        let buttons = PetTheme.hstack([
            PetButton("Change companion", style: .primary) { [weak self] in self?.onChooseCharacter?() },
            PetButton("Bring home") { [weak self] in self?.onBringPetHome?() },
            PetButton("Settings…", style: .quiet) { [weak self] in self?.onOpenSettings?() },
        ], spacing: 6)
        return [about, milestones, buttons]
    }

    // MARK: Actions

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 36 else { return }
        if (obj.object as? NSTextField) === taskField { submitTask() }
        if (obj.object as? NSTextField) === reminderField { submitReminder() }
    }

    private func submitTask() {
        let title = taskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let cal = Calendar.current
        var draft = TaskDraft(title: title)
        draft.notes = taskNotes.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let day: Date?
        switch taskDue.indexOfSelectedItem {
        case 1: day = cal.startOfDay(for: Date())
        case 2: day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
        case 3: day = cal.startOfDay(for: taskDate.dateValue)
        default: day = nil
        }
        if let day {
            if taskTimeToggle.state == .on {
                let t = cal.dateComponents([.hour, .minute], from: taskTime.dateValue)
                draft.dueDate = cal.date(bySettingHour: t.hour ?? 17, minute: t.minute ?? 0, second: 0, of: day)
                draft.hasDueTime = true
            } else {
                draft.dueDate = day
            }
            draft.remindBeforeMinutes = [nil, 30, 45, 60, 1440][taskRemind.indexOfSelectedItem]
        }
        draft.repeatEveryMinutes = [nil, 30, 45, 60][taskRepeat.indexOfSelectedItem]
        draft.priority = [.medium, .high, .low][taskPriority.indexOfSelectedItem]
        taskField.stringValue = ""
        taskNotes.stringValue = ""
        taskDue.selectItem(at: 0)
        taskRemind.selectItem(at: 0)
        taskRepeat.selectItem(at: 0)
        taskPriority.selectItem(at: 0)
        taskTimeToggle.state = .off
        onAddTask?(draft)
    }

    private func submitReminder() {
        let title = reminderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        reminderField.stringValue = ""
        let now = Date()
        let date: Date
        switch reminderWhen.indexOfSelectedItem {
        case 0: date = now.addingTimeInterval(15 * 60)
        case 1: date = now.addingTimeInterval(30 * 60)
        case 2: date = now.addingTimeInterval(3600)
        case 3: date = now.addingTimeInterval(7200)
        default:
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        onAddReminder?(title, date)
    }

    @objc private func taskToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        onToggleTask?(id)
    }

    // MARK: Formatting

    static func focusText(_ phase: FocusPhase) -> String {
        func t(_ s: TimeInterval) -> String { let v = max(0, Int(s)); return String(format: "%d:%02d", v / 60, v % 60) }
        switch phase {
        case .idle: return "Not focusing right now"
        case .focusing(let r): return "Focusing · \(t(r)) left"
        case .onBreak(let r): return "Break · \(t(r)) left"
        case .paused(let p, let r): return "\(p == .focusing ? "Focus" : "Break") paused · \(t(r))"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func timeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return timeFormatter.string(from: date) }
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }
}
