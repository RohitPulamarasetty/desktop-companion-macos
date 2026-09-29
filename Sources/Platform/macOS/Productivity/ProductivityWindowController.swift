import AppKit
import Core

/// The productivity window: Today · Tasks · Focus · Wellness · Stats.
/// Built lazily on first open; while closed it does no work. While open a
/// section is rebuilt only when its data actually changed; the focus
/// countdown updates a single label.
public final class ProductivityWindowController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    public enum Section: Int, CaseIterable {
        case today, tasks, focus, wellness, stats
        var title: String {
            switch self {
            case .today: return "Today"
            case .tasks: return "Tasks"
            case .focus: return "Focus"
            case .wellness: return "Wellness"
            case .stats: return "Stats"
            }
        }
    }

    private enum TaskFilter: Int, CaseIterable {
        case open, overdue, upcoming, done
        var title: String { ["Open", "Overdue", "Upcoming", "Done"][rawValue] }
    }

    // Callbacks into the app layer.
    public var snapshotProvider: (() -> ProductivitySnapshot)?
    public var onAddTask: ((TaskDraft) -> Void)?
    public var onQuickAdd: ((String) -> Void)?
    public var onToggleTask: ((UUID) -> Void)?
    public var onDeleteTask: ((UUID) -> Void)?
    public var onSnoozeTask: ((UUID, Date) -> Void)?
    public var onCyclePriority: ((UUID) -> Void)?
    public var onStartPomodoro: ((PomodoroPlan) -> Void)?
    public var onPauseFocus: (() -> Void)?
    public var onResumeFocus: (() -> Void)?
    public var onSkipFocus: (() -> Void)?
    public var onCancelFocus: (() -> Void)?
    public var onLogWater: (() -> Void)?
    public var onTakeBreak: (() -> Void)?
    public var onAddReminder: ((String, Date, RecurrenceRule) -> Void)?
    public var onDeleteReminder: ((UUID) -> Void)?
    public var onOpenSettings: (() -> Void)?

    private var window: NSWindow?
    private var segmented: NSSegmentedControl?
    private let body = FlippedStack()
    private var scroll: NSScrollView?
    private var section: Section = .today
    private var taskFilter: TaskFilter = .open
    private var lastSnapshot: ProductivitySnapshot?
    private var lastKey: String?
    private var focusClock: NSTextField?
    private let contentWidth: CGFloat = 470

    // Form controls (created on first use, like the window).
    private lazy var quickField = NSTextField()
    private lazy var quickPreview = PetTheme.label("", size: 11, color: PetTheme.inkSoft)
    private lazy var taskField = NSTextField()
    private lazy var taskNotes = NSTextField()
    private lazy var taskDue = NSPopUpButton()
    private lazy var taskDate = NSDatePicker()
    private lazy var taskTimeToggle = NSButton(checkboxWithTitle: "at", target: nil, action: nil)
    private lazy var taskTime = NSDatePicker()
    private lazy var taskRemind = NSPopUpButton()
    private lazy var taskRepeat = NSPopUpButton()
    private lazy var taskNudge = NSPopUpButton()
    private lazy var taskPriority = NSPopUpButton()
    private lazy var reminderField = NSTextField()
    private lazy var reminderWhen = NSPopUpButton()
    private lazy var reminderRepeat = NSPopUpButton()
    private lazy var reminderDate = NSDatePicker()
    private var advancedOpen = false

    public override init() { super.init() }

    public var isVisible: Bool { window?.isVisible ?? false }
    public var visibleSection: Section? { isVisible ? section : nil }

    // MARK: Window

    public func show(section newSection: Section? = nil) {
        let w = window ?? makeWindow()
        window = w
        if let newSection { section = newSection }
        segmented?.selectedSegment = section.rawValue
        refresh(force: true)
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    public func hide() { window?.orderOut(nil) }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth + 40, height: 640),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        w.title = "Desktop Companion"
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.minSize = NSSize(width: contentWidth + 40, height: 420)
        w.delegate = self
        w.setFrameAutosaveName("ProductivityWindow")

        let seg = NSSegmentedControl(labels: Section.allCases.map(\.title), trackingMode: .selectOne, target: self, action: #selector(sectionChanged(_:)))
        seg.segmentStyle = .rounded
        seg.font = PetTheme.font(12, .semibold)
        seg.selectedSegment = section.rawValue
        seg.translatesAutoresizingMaskIntoConstraints = false
        segmented = seg

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.edgeInsets = NSEdgeInsets(top: 4, left: 20, bottom: 20, right: 20)
        body.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(body)
        scroll.documentView = doc
        self.scroll = scroll

        let content = NSView()
        content.addSubview(seg)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            seg.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            seg.widthAnchor.constraint(equalToConstant: contentWidth),
            scroll.topAnchor.constraint(equalTo: seg.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.topAnchor.constraint(equalTo: doc.topAnchor),
            body.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        w.contentView = content
        configureControls()
        return w
    }

    public func windowWillClose(_ notification: Notification) {
        // Rarely reopened: drop the view tree.
        DispatchQueue.main.async { [weak self] in
            self?.body.arrangedSubviews.forEach { $0.removeFromSuperview() }
            self?.window?.contentView = nil
            self?.window = nil
            self?.lastKey = nil
            self?.lastSnapshot = nil
        }
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        section = Section(rawValue: sender.selectedSegment) ?? .today
        refresh(force: true)
    }

    // MARK: Refresh

    public func refresh(force: Bool = false) {
        guard let window, force || window.isVisible, let snap = snapshotProvider?() else { return }
        window.title = "\(snap.petName) · \(section.title)"
        let key = "\(section.rawValue)/\(taskFilter.rawValue)/\(advancedOpen)"
        if !force, snap == lastSnapshot, key == lastKey { return }
        lastSnapshot = snap
        lastKey = key
        rebuild(snap)
    }

    /// Cheap per-second update of just the countdown label(s).
    public func updateFocusClock(_ phase: FocusPhase) {
        guard isVisible, let focusClock else { return }
        focusClock.stringValue = Self.focusText(phase)
    }

    private func rebuild(_ s: ProductivitySnapshot) {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        focusClock = nil
        let cards: [NSView]
        switch section {
        case .today: cards = todayCards(s)
        case .tasks: cards = taskCards(s)
        case .focus: cards = focusCards(s)
        case .wellness: cards = wellnessCards(s)
        case .stats: cards = statsCards(s)
        }
        for c in cards {
            body.addArrangedSubview(c)
            c.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        }
        if let doc = scroll?.documentView { doc.layoutSubtreeIfNeeded() }
    }

    // MARK: Small helpers

    private static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    private static func duration(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m" }

    private static func relative(_ d: Date, now: Date = Date()) -> String {
        let m = Int((d.timeIntervalSince(now) / 60).rounded())
        if abs(m) < 1 { return "now" }
        if m > 0 { return m < 60 ? "in \(m) min" : "in \(m / 60) h \(m % 60) min" }
        return -m < 60 ? "\(-m) min ago" : "\(-m / 60) h ago"
    }

    public static func dueText(_ d: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        tf.dateStyle = .none
        let time = hasTime ? " \(tf.string(from: d))" : ""
        if cal.isDateInToday(d) { return "today\(time)" }
        if cal.isDateInTomorrow(d) { return "tomorrow\(time)" }
        let df = DateFormatter()
        df.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy"
        return df.string(from: d) + time
    }

    public static func focusText(_ phase: FocusPhase) -> String {
        func t(_ s: TimeInterval) -> String { let v = max(0, Int(s.rounded(.up))); return String(format: "%d:%02d", v / 60, v % 60) }
        switch phase {
        case .idle: return "Not focusing right now"
        case .focusing(let r): return "Focusing · \(t(r)) left"
        case .onBreak(let r): return "Break · \(t(r)) left"
        case .paused(let p, let r): return "\(p == .focusing ? "Focus" : "Break") paused · \(t(r))"
        }
    }

    private func progressBar(_ value: Double, color: NSColor) -> NSView {
        let bar = ProgressBarView(value: value, color: color)
        return bar
    }

    private func statTile(_ value: String, _ caption: String, _ color: NSColor) -> NSView {
        PetTheme.vstack([PetTheme.label(value, size: 20, weight: .bold, color: color), PetTheme.label(caption, size: 10.5, color: PetTheme.inkSoft)],
                        spacing: 0, alignment: .centerX)
    }

    private func full(_ card: PetCardView, _ rows: [NSView]) {
        for r in rows { r.widthAnchor.constraint(equalTo: card.stack.widthAnchor).isActive = true }
    }

    // MARK: Today

    private func todayCards(_ s: ProductivitySnapshot) -> [NSView] {
        let header = PetCardView([
            PetTheme.sectionHeader(s.greeting),
            PetTheme.hstack([PetTheme.label(s.mood, size: 12.5, weight: .semibold), PetTheme.label("· \(s.petStatus)", size: 12, color: PetTheme.inkSoft)], spacing: 5),
            PetTheme.label(s.nextEvent.isEmpty ? "Nothing scheduled" : "⏱  \(s.nextEvent)", size: 12.5, color: PetTheme.inkSoft),
        ], spacing: 5)

        let tiles = NSStackView(views: [
            statTile("\(s.tasksDoneToday)", "tasks done", PetTheme.accent),
            statTile(Self.duration(s.focusMinutesToday), "focus", PetTheme.leaf),
            statTile("\(s.waterToday)/\(s.waterGoal)", "water", PetTheme.water),
            statTile(Self.duration(s.activeMinutesToday), "active", PetTheme.inkSoft),
            statTile(s.streakDays > 0 ? "🔥\(s.streakDays)" : "–", "day streak", PetTheme.accent),
        ])
        tiles.distribution = .fillEqually
        let goals: [NSView] = [
            goalRow("Focus", s.focusMinutesToday, s.focusGoalMinutes, "min", PetTheme.leaf),
            goalRow("Water", s.waterToday, s.waterGoal, "glasses", PetTheme.water),
        ]
        let summary = PetCardView([PetTheme.sectionHeader("Today"), tiles] + goals, spacing: 8)
        full(summary, [tiles] + goals)

        let clock = PetTheme.label(Self.focusText(s.focusPhase), size: 12.5, weight: .medium, color: PetTheme.inkSoft)
        focusClock = clock
        var buttons: [NSView] = [PetButton("+ Task") { [weak self] in self?.show(section: .tasks) }]
        if case .idle = s.focusPhase { buttons.append(PetButton("Focus \(Int(s.pomodoroPlan.workMinutes))", style: .primary) { [weak self] in self?.onStartPomodoro?(s.pomodoroPlan) }) }
        buttons.append(PetButton("💧 Water") { [weak self] in self?.onLogWater?() })
        buttons.append(PetButton("☕ Break") { [weak self] in self?.onTakeBreak?() })
        for case let b as PetButton in buttons { b.horizontalPadding = 10 }
        let actions = PetTheme.hstack(buttons, spacing: 5)
        actions.distribution = .fillEqually
        let quick = PetCardView([PetTheme.sectionHeader("Quick actions"), clock, actions])
        full(quick, [actions])

        var listViews: [NSView] = [PetTheme.sectionHeader("Tasks for today (\(s.tasksDoneToday) done)")]
        let items = s.overdue + s.todayTasks
        for t in items.prefix(8) { listViews.append(taskRow(t)) }
        if items.isEmpty { listViews.append(PetTheme.label("Nothing waiting. \(s.petName) approves. ✨", size: 12.5, color: PetTheme.inkSoft)) }
        if items.count > 8 { listViews.append(PetTheme.label("+\(items.count - 8) more in Tasks", size: 11.5, color: PetTheme.inkSoft)) }
        let list = PetCardView(listViews, spacing: 6)
        full(list, Array(listViews.dropFirst()))
        return [header, summary, quick, list]
    }

    private func goalRow(_ name: String, _ value: Int, _ goal: Int, _ unit: String, _ color: NSColor) -> NSView {
        let label = PetTheme.label("\(name)  \(value)/\(goal) \(unit)", size: 11.5, color: PetTheme.inkSoft)
        let bar = progressBar(goal > 0 ? Double(value) / Double(goal) : 0, color: color)
        return PetTheme.vstack([label, bar], spacing: 3)
    }

    // MARK: Tasks

    private func configureControls() {
        quickField.placeholderString = "Quick add: call mom tomorrow 5pm !high every week"
        quickField.font = PetTheme.font(13)
        quickField.focusRingType = .none
        quickField.delegate = self
        taskField.placeholderString = "Task title"
        taskField.font = PetTheme.font(13)
        taskField.focusRingType = .none
        taskNotes.placeholderString = "Notes (optional)"
        taskNotes.font = PetTheme.font(12)
        taskNotes.focusRingType = .none
        taskDue.addItems(withTitles: ["No due date", "Today", "Tomorrow", "Pick a date…"])
        taskDue.target = self
        taskDue.action = #selector(taskFormChanged)
        taskDate.datePickerElements = [.yearMonthDay]
        taskDate.datePickerStyle = .textFieldAndStepper
        taskDate.dateValue = Date()
        taskTime.datePickerElements = [.hourMinute]
        taskTime.datePickerStyle = .textFieldAndStepper
        taskTime.dateValue = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
        taskTimeToggle.target = self
        taskTimeToggle.action = #selector(taskFormChanged)
        taskRemind.addItems(withTitles: ["No reminder", "10 min before", "30 min before", "1 hour before", "1 day before"])
        taskRepeat.addItems(withTitles: RecurrenceRule.allCases.map(\.displayName))
        taskNudge.addItems(withTitles: ["Don't nag", "Nudge every 30 min", "Nudge every 45 min", "Nudge every 60 min"])
        taskPriority.addItems(withTitles: ["Normal", "High", "Low"])
        for p in [taskDue, taskRemind, taskRepeat, taskNudge, taskPriority] { p.font = PetTheme.font(11.5); p.controlSize = .small }
        for c in [taskDate, taskTime] { c.font = PetTheme.font(11.5) }
        taskTimeToggle.font = PetTheme.font(11.5)
        reminderField.placeholderString = "Remind me to…"
        reminderField.font = PetTheme.font(13)
        reminderField.focusRingType = .none
        reminderField.delegate = self
        reminderWhen.addItems(withTitles: ["in 15 min", "in 30 min", "in 1 hour", "in 2 hours", "tomorrow 9:00", "Pick date & time…"])
        reminderWhen.font = PetTheme.font(12)
        reminderWhen.target = self
        reminderWhen.action = #selector(reminderWhenChanged)
        reminderRepeat.addItems(withTitles: RecurrenceRule.allCases.map(\.displayName))
        reminderRepeat.font = PetTheme.font(12)
        reminderDate.datePickerElements = [.yearMonthDay, .hourMinute]
        reminderDate.datePickerStyle = .textFieldAndStepper
        reminderDate.dateValue = Date().addingTimeInterval(3600)
        reminderDate.font = PetTheme.font(11.5)
        taskFormChanged()
        reminderWhenChanged()
    }

    @objc private func reminderWhenChanged() { reminderDate.isHidden = reminderWhen.indexOfSelectedItem != 5 }

    @objc private func taskFormChanged() {
        let hasDate = taskDue.indexOfSelectedItem > 0
        taskDate.isHidden = taskDue.indexOfSelectedItem != 3
        taskTimeToggle.isHidden = !hasDate
        taskTime.isHidden = !hasDate || taskTimeToggle.state != .on
        taskRemind.isEnabled = hasDate
        if !hasDate { taskRemind.selectItem(at: 0) }
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === quickField else { return }
        quickPreview.stringValue = Self.previewText(quickField.stringValue)
    }

    static func previewText(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Try: “submit report friday 3pm !high”, “water plants every day 8am”, “in 30 min call Sam”" }
        let p = QuickAddParser.parse(trimmed)
        var parts = ["“\(p.title.isEmpty ? "…" : p.title)”"]
        if let d = p.dueDate { parts.append(dueText(d, hasTime: p.hasDueTime)) }
        if p.priority == .high { parts.append("❗ high") } else if p.priority == .low { parts.append("low") }
        if p.recurrence != .none { parts.append("↻ \(p.recurrence.displayName.lowercased())") }
        if let r = p.remindBeforeMinutes { parts.append("⏰ \(r >= 1440 ? "\(r / 1440) day" : (r >= 60 ? "\(r / 60) h" : "\(r) min")) before") }
        return "→ " + parts.joined(separator: " · ")
    }

    private func taskRow(_ t: TaskItem) -> NSView {
        let box = NSButton(checkboxWithTitle: t.title, target: self, action: #selector(taskToggled(_:)))
        box.state = t.isCompleted ? .on : .off
        box.identifier = NSUserInterfaceItemIdentifier(t.id.uuidString)
        let prefix = t.priority == .high ? "❗ " : (t.priority == .low ? "↓ " : "")
        box.attributedTitle = NSAttributedString(string: prefix + t.title, attributes: [
            .font: PetTheme.font(13),
            .foregroundColor: t.isCompleted ? PetTheme.inkSoft : PetTheme.ink,
            .strikethroughStyle: t.isCompleted ? NSUnderlineStyle.single.rawValue : 0,
        ])
        var parts: [String] = []
        var overdue = false
        if let d = t.deadline(), !t.isCompleted {
            overdue = d < Date()
            parts.append(overdue ? "overdue · \(Self.dueText(d, hasTime: t.hasDueTime))" : Self.dueText(d, hasTime: t.hasDueTime))
        }
        if t.recurrence != .none { parts.append("↻ \(t.recurrence.displayName.lowercased())") }
        if let r = t.remindBeforeMinutes, !t.isCompleted { parts.append("⏰ \(r >= 1440 ? "1 day" : (r >= 60 ? "\(r / 60) h" : "\(r) min")) before") }
        if let e = t.repeatEveryMinutes, !t.isCompleted { parts.append("nudge every \(e) min") }
        if !t.notes.isEmpty { parts.append(t.notes) }
        var left: [NSView] = [box]
        if !parts.isEmpty { left.append(PetTheme.label(parts.joined(separator: " · "), size: 11, color: overdue ? PetTheme.accent : PetTheme.inkSoft)) }
        let more = PetButton("⋯", style: .quiet) { }
        more.horizontalPadding = 6
        let id = t.id
        more.setAction { [weak self, weak more] in
            guard let self, let more else { return }
            self.popTaskMenu(for: t, from: more, id: id)
        }
        return PetTheme.hstack([PetTheme.vstack(left, spacing: 1), PetTheme.spacer(), more], spacing: 6)
    }

    private func popTaskMenu(for t: TaskItem, from view: NSView, id: UUID) {
        let cal = Calendar.current
        let menu = NSMenu()
        menu.autoenablesItems = false
        if !t.isCompleted {
            menu.addItem(ClosureMenuItem("Snooze 1 hour") { [weak self] in self?.onSnoozeTask?(id, Date().addingTimeInterval(3600)) })
            menu.addItem(ClosureMenuItem("This evening (6 pm)") { [weak self] in
                let d = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date().addingTimeInterval(7200)
                self?.onSnoozeTask?(id, d > Date() ? d : Date().addingTimeInterval(3600))
            })
            menu.addItem(ClosureMenuItem("Tomorrow morning") { [weak self] in
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
                self?.onSnoozeTask?(id, cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
            })
            menu.addItem(ClosureMenuItem("Next week") { [weak self] in
                let d = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: Date())) ?? Date()
                self?.onSnoozeTask?(id, cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d)
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Priority: \(t.priority == .high ? "High → Low" : (t.priority == .low ? "Low → Normal" : "Normal → High"))") { [weak self] in self?.onCyclePriority?(id) })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Delete") { [weak self] in self?.onDeleteTask?(id) })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
    }

    private func taskCards(_ s: ProductivitySnapshot) -> [NSView] {
        quickField.stringValue = ""
        quickPreview.stringValue = Self.previewText("")
        quickPreview.lineBreakMode = .byTruncatingTail
        let add = PetButton("Add", style: .primary) { [weak self] in self?.submitQuick() }
        let input = PetTheme.hstack([quickField, add], spacing: 6)
        quickField.setContentHuggingPriority(.init(1), for: .horizontal)
        let toggle = PetButton(advancedOpen ? "Hide options ▴" : "More options ▾", style: .quiet) { [weak self] in
            guard let self else { return }
            self.advancedOpen.toggle()
            self.refresh(force: true)
        }
        var quickViews: [NSView] = [PetTheme.sectionHeader("New task"), input, quickPreview, toggle]
        if advancedOpen { quickViews += advancedForm() }
        let quick = PetCardView(quickViews, spacing: 6)
        full(quick, [input, quickPreview] + Array(quickViews.dropFirst(4)))

        let seg = NSSegmentedControl(labels: TaskFilter.allCases.map { filter in
            let n = count(for: filter, s)
            return n > 0 && filter != .done ? "\(filter.title) (\(n))" : filter.title
        }, trackingMode: .selectOne, target: self, action: #selector(filterChanged(_:)))
        seg.segmentStyle = .rounded
        seg.font = PetTheme.font(11.5, .medium)
        seg.selectedSegment = taskFilter.rawValue
        let items = tasks(for: taskFilter, s)
        var rows: [NSView] = [seg]
        for t in items.prefix(30) { rows.append(taskRow(t)) }
        if items.count > 30 { rows.append(PetTheme.label("+\(items.count - 30) more", size: 11.5, color: PetTheme.inkSoft)) }
        if items.isEmpty { rows.append(PetTheme.label(emptyText(taskFilter), size: 12.5, color: PetTheme.inkSoft)) }
        let list = PetCardView(rows, spacing: 6)
        full(list, rows)
        return [quick, list]
    }

    private func count(for f: TaskFilter, _ s: ProductivitySnapshot) -> Int { tasks(for: f, s).count }

    private func tasks(for f: TaskFilter, _ s: ProductivitySnapshot) -> [TaskItem] {
        switch f {
        case .open: return s.overdue + s.todayTasks.filter { !$0.isCompleted }
        case .overdue: return s.overdue
        case .upcoming: return s.upcoming
        case .done: return s.doneRecently
        }
    }

    private func emptyText(_ f: TaskFilter) -> String {
        switch f {
        case .open: return "Nothing open for today. Nice! Add something above."
        case .overdue: return "Nothing overdue. 🎉"
        case .upcoming: return "Nothing scheduled ahead."
        case .done: return "Nothing completed yet."
        }
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        taskFilter = TaskFilter(rawValue: sender.selectedSegment) ?? .open
        refresh(force: true)
    }

    private func advancedForm() -> [NSView] {
        taskField.stringValue = ""
        taskNotes.stringValue = ""
        let title = PetTheme.hstack([taskField], spacing: 6)
        let dueRow = PetTheme.hstack([PetTheme.label("Due", size: 11.5, color: PetTheme.inkSoft), taskDue, taskDate, taskTimeToggle, taskTime, PetTheme.spacer()], spacing: 5)
        let remindRow = PetTheme.hstack([taskRemind, taskRepeat, PetTheme.spacer()], spacing: 5)
        let nudgeRow = PetTheme.hstack([taskNudge, taskPriority, PetTheme.spacer()], spacing: 5)
        let notesRow = PetTheme.hstack([taskNotes], spacing: 5)
        let add = PetButton("Add task", style: .primary) { [weak self] in self?.submitTask() }
        let note = PetTheme.label("Reminder: before the deadline · Nudge: keeps asking until done", size: 10.5, color: PetTheme.inkSoft)
        taskFormChanged()
        return [title, dueRow, remindRow, nudgeRow, notesRow, add, note]
    }

    // MARK: Focus

    private func focusCards(_ s: ProductivitySnapshot) -> [NSView] {
        let clock = PetTheme.label(Self.focusText(s.focusPhase), size: 22, weight: .bold)
        clock.font = PetTheme.mono(22)
        focusClock = clock
        let dots = PetTheme.label(s.pomodoroPlan.cycleDots(completed: s.pomodoroCompleted), size: 16)
        var buttons: [NSView] = []
        switch s.focusPhase {
        case .idle:
            let p = s.pomodoroPlan
            buttons = [PetButton("Classic 25·5", style: .primary) { [weak self] in self?.onStartPomodoro?(PomodoroPlan(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, sessionsBeforeLongBreak: 4, autoStartNext: p.autoStartNext)) },
                       PetButton("Deep 50·10") { [weak self] in self?.onStartPomodoro?(PomodoroPlan(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, sessionsBeforeLongBreak: 3, autoStartNext: p.autoStartNext)) },
                       PetButton("Quick 15·3") { [weak self] in self?.onStartPomodoro?(PomodoroPlan(workMinutes: 15, shortBreakMinutes: 3, longBreakMinutes: 10, sessionsBeforeLongBreak: 4, autoStartNext: p.autoStartNext)) },
                       PetButton("Mine \(Int(p.workMinutes))·\(Int(p.shortBreakMinutes))") { [weak self] in self?.onStartPomodoro?(p) }]
        case .focusing, .onBreak:
            buttons = [PetButton("Pause") { [weak self] in self?.onPauseFocus?() },
                       PetButton("Skip") { [weak self] in self?.onSkipFocus?() },
                       PetButton("Stop", style: .quiet) { [weak self] in self?.onCancelFocus?() }]
        case .paused:
            buttons = [PetButton("Resume", style: .primary) { [weak self] in self?.onResumeFocus?() },
                       PetButton("Stop", style: .quiet) { [weak self] in self?.onCancelFocus?() }]
        }
        let row = PetTheme.hstack(buttons, spacing: 6)
        let hint = PetTheme.wrapping("After each session comes a short break — a long one after every \(s.pomodoroPlan.sessionsBeforeLongBreak). \(s.petName) sits beside you and stays quiet while you work. Your own plan lives in Settings → Productivity.", width: contentWidth - 40)
        let main = PetCardView([PetTheme.sectionHeader("Pomodoro"), clock, dots, row, hint], spacing: 10)
        full(main, [hint])
        let goal = Double(s.focusMinutesToday) / Double(max(s.focusGoalMinutes, 1))
        let bar = progressBar(goal, color: PetTheme.leaf)
        let today = PetCardView([PetTheme.sectionHeader("Today"),
                                 PetTheme.label("\(Self.plural(s.focusSessionsToday, "session")) · \(Self.duration(s.focusMinutesToday)) of \(Self.duration(s.focusGoalMinutes)) goal", size: 13),
                                 bar,
                                 PetTheme.label("\(Self.plural(s.focusBreaksToday, "focus break")) taken", size: 11.5, color: PetTheme.inkSoft)])
        full(today, [bar])
        return [main, today]
    }

    // MARK: Wellness

    private func wellnessCards(_ s: ProductivitySnapshot) -> [NSView] {
        var waterInfo: [String] = []
        if let last = s.lastWater { waterInfo.append("last \(Self.relative(last))") }
        if let next = s.nextWater { waterInfo.append(next <= Date() ? "next check soon" : "next check \(Self.relative(next))") }
        let waterBar = progressBar(Double(s.waterToday) / Double(max(s.waterGoal, 1)), color: PetTheme.water)
        let water = PetCardView([
            PetTheme.sectionHeader("Water"),
            PetTheme.label("\(s.waterToday) of \(s.waterGoal) glasses today", size: 13, weight: .semibold),
            waterBar,
            PetTheme.label(waterInfo.isEmpty ? "No water logged yet today" : waterInfo.joined(separator: " · "), size: 11.5, color: PetTheme.inkSoft),
            PetButton("💧 I drank water", style: .primary) { [weak self] in self?.onLogWater?() },
        ])
        full(water, [waterBar])

        var habits: [String] = []
        habits.append(s.eyeBreaksOn ? "👀 20-20-20 eye breaks: on" : "👀 20-20-20 eye breaks: off")
        habits.append(s.stretchOn ? "🧘 Stretch nudges: on" : "🧘 Stretch nudges: off")
        habits.append(s.bedtimeOn ? "🌙 Bedtime reminder: on" : "🌙 Bedtime reminder: off")
        let screen = PetCardView([
            PetTheme.sectionHeader("Screen time today"),
            PetTheme.label("Active \(Self.duration(s.activeMinutesToday)) · Idle \(Self.duration(s.idleMinutesToday))", size: 13, weight: .semibold),
            PetTheme.label("Working for \(Self.duration(s.continuousWorkMinutes)) since your last break", size: 11.5, color: PetTheme.inkSoft),
            PetTheme.label("\(Self.plural(s.breaksToday, "screen break")) · \(Self.plural(s.focusBreaksToday, "focus break"))", size: 11.5, color: PetTheme.inkSoft),
            PetTheme.label(habits.joined(separator: "   "), size: 11, color: PetTheme.inkSoft),
            PetTheme.hstack([PetButton("☕ Take a break now") { [weak self] in self?.onTakeBreak?() },
                             PetButton("Nudge settings…", style: .quiet) { [weak self] in self?.onOpenSettings?() }], spacing: 6),
        ])

        reminderField.stringValue = ""
        let add = PetButton("Add", style: .primary) { [weak self] in self?.submitReminder() }
        let whenRow = PetTheme.hstack([reminderWhen, reminderDate, PetTheme.spacer()], spacing: 6)
        let repeatRow = PetTheme.hstack([reminderRepeat, PetTheme.spacer(), add], spacing: 6)
        var remViews: [NSView] = [PetTheme.sectionHeader("Reminders"), reminderField, whenRow, repeatRow]
        for r in s.reminders.prefix(8) {
            let id = r.id
            let repeatMark = r.recurrence == .none ? "" : " ↻"
            let when = Self.dueText(max(r.fireDate, r.snoozedUntil ?? r.fireDate), hasTime: true)
            let line = PetTheme.hstack([PetTheme.label("⏰ \(r.title)\(repeatMark)", size: 12.5), PetTheme.spacer(),
                                        PetTheme.label(when, size: 11.5, color: PetTheme.inkSoft),
                                        PetButton("✕", style: .quiet) { [weak self] in self?.onDeleteReminder?(id) }], spacing: 6)
            remViews.append(line)
        }
        if s.reminders.isEmpty { remViews.append(PetTheme.label("No upcoming reminders.", size: 12, color: PetTheme.inkSoft)) }
        let reminders = PetCardView(remViews)
        full(reminders, Array(remViews.dropFirst()))
        return [water, screen, reminders]
    }

    // MARK: Stats

    private func statsCards(_ s: ProductivitySnapshot) -> [NSView] {
        let week = s.week
        let totalTasks = week.map(\.tasks).reduce(0, +)
        let totalFocus = week.map(\.focusMinutes).reduce(0, +)
        let totalWater = week.map(\.water).reduce(0, +)
        let totalActive = week.map(\.activeMinutes).reduce(0, +)
        let summary = PetCardView([
            PetTheme.sectionHeader("Last 7 days"),
            PetTheme.label("✅ \(Self.plural(totalTasks, "task")) done · 🎯 \(Self.duration(totalFocus)) focused", size: 13, weight: .semibold),
            PetTheme.label("💧 \(totalWater) glasses · 🖥 \(Self.duration(totalActive)) active", size: 12.5, color: PetTheme.inkSoft),
            PetTheme.label(s.streakDays > 0 ? "🔥 \(Self.plural(s.streakDays, "day")) in a row with something done" : "Finish a task or a focus session today to start a streak.", size: 12, color: PetTheme.inkSoft),
        ], spacing: 5)
        return [summary,
                chartCard("Tasks done", week.map { ($0.label, Double($0.tasks)) }, PetTheme.accent) { "\(Int($0))" },
                chartCard("Focus minutes", week.map { ($0.label, Double($0.focusMinutes)) }, PetTheme.leaf) { "\(Int($0))" },
                chartCard("Water (glasses)", week.map { ($0.label, Double($0.water)) }, PetTheme.water) { "\(Int($0))" },
                chartCard("Active screen time (hours)", week.map { ($0.label, Double($0.activeMinutes) / 60) }, PetTheme.inkSoft) { String(format: "%.1f", $0) }]
    }

    private func chartCard(_ title: String, _ values: [(String, Double)], _ color: NSColor, format: @escaping (Double) -> String) -> NSView {
        let chart = BarChartView(values: values, color: color, format: format)
        let card = PetCardView([PetTheme.sectionHeader(title), chart], spacing: 6)
        chart.widthAnchor.constraint(equalTo: card.stack.widthAnchor).isActive = true
        return card
    }

    // MARK: Actions

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 36 else { return }
        let field = obj.object as? NSTextField
        if field === quickField { submitQuick() }
        if field === reminderField { submitReminder() }
        if field === taskField { submitTask() }
    }

    private func submitQuick() {
        let text = quickField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quickField.stringValue = ""
        quickPreview.stringValue = Self.previewText("")
        onQuickAdd?(text)
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
            draft.remindBeforeMinutes = [nil, 10, 30, 60, 1440][taskRemind.indexOfSelectedItem]
        }
        draft.recurrence = RecurrenceRule.allCases[taskRepeat.indexOfSelectedItem]
        draft.repeatEveryMinutes = [nil, 30, 45, 60][taskNudge.indexOfSelectedItem]
        draft.priority = [.medium, .high, .low][taskPriority.indexOfSelectedItem]
        for p in [taskDue, taskRemind, taskRepeat, taskNudge, taskPriority] { p.selectItem(at: 0) }
        taskTimeToggle.state = .off
        onAddTask?(draft)
    }

    private func submitReminder() {
        let title = reminderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        reminderField.stringValue = ""
        let now = Date()
        let cal = Calendar.current
        let date: Date
        switch reminderWhen.indexOfSelectedItem {
        case 0: date = now.addingTimeInterval(15 * 60)
        case 1: date = now.addingTimeInterval(30 * 60)
        case 2: date = now.addingTimeInterval(3600)
        case 3: date = now.addingTimeInterval(7200)
        case 4:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        default: date = max(reminderDate.dateValue, now.addingTimeInterval(30))
        }
        let repeatRule = RecurrenceRule.allCases[reminderRepeat.indexOfSelectedItem]
        reminderRepeat.selectItem(at: 0)
        onAddReminder?(title, date, repeatRule)
    }

    @objc private func taskToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        onToggleTask?(id)
    }
}

// MARK: - Small views

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
private final class FlippedStack: NSStackView { override var isFlipped: Bool { true } }

/// A thin rounded progress bar in a theme colour.
private final class ProgressBarView: NSView {
    private let fill = CALayer()
    private let value: Double
    private let color: NSColor

    init(value: Double, color: NSColor) {
        self.value = min(max(value, 0), 1)
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        fill.cornerRadius = 4
        layer?.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 8).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PetTheme.accentSoft.cgColor
            fill.backgroundColor = color.cgColor
        }
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * value, height: bounds.height)
    }
}

/// A 7-column bar chart (value on top, label below).
private final class BarChartView: NSView {
    init(values: [(String, Double)], color: NSColor, format: (Double) -> String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let maxValue = max(values.map(\.1).max() ?? 0, 0.0001)
        let columns = values.map { (label, v) -> NSView in
            let bar = BarView(color: color)
            let barHeight = max(v > 0 ? 3 : 1, CGFloat(v / maxValue) * 46)
            bar.heightAnchor.constraint(equalToConstant: barHeight).isActive = true
            bar.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let top = PetTheme.label(v > 0 ? format(v) : "", size: 10, color: PetTheme.inkSoft)
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: 46 - barHeight).isActive = true
            let col = PetTheme.vstack([top, spacer, bar, PetTheme.label(label, size: 10, color: PetTheme.inkSoft)], spacing: 2, alignment: .centerX)
            return col
        }
        let row = NSStackView(views: columns)
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

private final class BarView: NSView {
    private let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
        translatesAutoresizingMaskIntoConstraints = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); layer?.backgroundColor = color.cgColor }
    override func layout() { super.layout(); layer?.backgroundColor = color.cgColor }
}
