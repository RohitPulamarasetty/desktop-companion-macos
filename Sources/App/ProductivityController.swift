import AppKit
import Core
import PlatformMac

/// Tasks, reminders, Pomodoro focus, water/break/eye/stretch/bedtime nudges,
/// screen time, briefs and stats. It owns the local stores and every timer
/// (each scheduled at its own next due time, nothing polls), and talks to the
/// companion only through `app` (speech, questions, celebrations).
final class ProductivityController {
    private unowned let app: AppDelegate
    private var pet: CharacterWindowController { app.pet }
    private var settings: AppSettings { app.appSettings }

    let window = ProductivityWindowController()
    private let notifications = NotificationScheduler()

    // Local stores (SQLite files under Application Support -- no network).
    private var taskStore: TaskStore?
    private var reminderStore: ReminderStore?
    private var focusHistoryStore: FocusHistoryStore?
    private var wellnessStore: WellnessStore?
    private var screenTimeStore: ScreenTimeStore?

    // Focus / Pomodoro
    let focusTimer = FocusTimer()
    private var plan = PomodoroPlan.classic
    private var pomodoroCompleted = 0
    private var lastPomodoroAt: Date?
    private var focusStartedAt: Date?
    private var focusPlannedMinutes: Double = 25
    private var focusLastSync = Date()
    private var halfwaySaid = false
    private var focusCelebrating = false
    private var focusPhaseTimer: Timer?
    private var focusTicker: Timer?

    // Reminders
    private let reminders = ReminderQueue()
    private var water = NudgeSchedule(enabled: false, interval: 3600, anchor: Date())
    private var eye = NudgeSchedule(enabled: false, interval: 1200, anchor: Date())
    private var stretch = NudgeSchedule(enabled: false, interval: 3600, anchor: Date())
    private var screenBreakNotBefore: Date?
    private var reminderTimer: Timer?

    // Screen time
    let activity = ActivityTracker()
    private var pendingActive: Double = 0
    private var pendingIdle: Double = 0
    private var pendingFocus: Double = 0
    private var recentCompletions: [Date] = []

    var isFocusing: Bool { if case .focusing = focusTimer.phase { return true }; return false }
    private var quietHours: QuietHours { QuietHours(startHour: settings.quietHoursStart, endHour: settings.quietHoursEnd) }

    init(app: AppDelegate) { self.app = app }

    // MARK: Setup

    func start() {
        let dir = AppDelegate.applicationSupportDirectory()
        func open<T>(_ name: String, _ make: (URL) throws -> T) -> T? {
            do { return try make(dir.appendingPathComponent(name)) } catch {
                NSLog("[DesktopCompanion] Failed to open %@: %@", name, "\(error)")
                return nil
            }
        }
        taskStore = open("tasks.sqlite", TaskStore.init)
        reminderStore = open("reminders.sqlite", ReminderStore.init)
        focusHistoryStore = open("focus_history.sqlite", FocusHistoryStore.init)
        wellnessStore = open("wellness.sqlite", WellnessStore.init)
        screenTimeStore = open("screen_time.sqlite", ScreenTimeStore.init)
        plan = settings.pomodoroPlan
        wireWindow()
        setUpNudges()
        refreshReminders()
        if settings.systemNotifications { notifications.requestAuthorization() }
    }

    private func wireWindow() {
        window.snapshotProvider = { [weak self] in self?.makeSnapshot() ?? ProductivitySnapshot() }
        window.onQuickAdd = { [weak self] text in self?.quickAdd(text) }
        window.onAddTask = { [weak self] d in self?.addTask(d) }
        window.onToggleTask = { [weak self] id in self?.toggleTask(id) }
        window.onDeleteTask = { [weak self] id in
            try? self?.taskStore?.delete(id: id)
            self?.changed()
        }
        window.onSnoozeTask = { [weak self] id, until in
            guard let self, var t = try? self.taskStore?.task(id: id) else { return }
            // Moves the task itself: a task with a due date gets a new due date, otherwise just its reminder.
            if let due = t.dueDate {
                let cal = Calendar.current
                let time = cal.dateComponents([.hour, .minute], from: due)
                t.dueDate = t.hasDueTime ? until : cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: cal.startOfDay(for: until))
                t.reminderHandledAt = nil
            }
            t.reminderSnoozedUntil = until
            try? self.taskStore?.update(t)
            self.app.sayLine("Moved to \(ProductivityWindowController.dueText(until, hasTime: true)). 📅", style: .thought)
            self.changed()
        }
        window.onCyclePriority = { [weak self] id in
            guard let self, var t = try? self.taskStore?.task(id: id) else { return }
            t.priority = t.priority == .medium ? .high : (t.priority == .high ? .low : .medium)
            try? self.taskStore?.update(t)
            self.changed()
        }
        window.onStartPomodoro = { [weak self] plan in self?.startPomodoro(plan) }
        window.onPauseFocus = { [weak self] in self?.pauseFocus() }
        window.onResumeFocus = { [weak self] in self?.resumeFocus() }
        window.onSkipFocus = { [weak self] in
            guard let self else { return }
            self.syncFocus()
            self.handleFocusEvent(self.focusTimer.skip())
            self.scheduleFocusPhaseEnd()
        }
        window.onCancelFocus = { [weak self] in self?.cancelFocus() }
        window.onLogWater = { [weak self] in self?.logWater(fromPet: false) }
        window.onTakeBreak = { [weak self] in self?.takeBreak(fromPet: false) }
        window.onAddReminder = { [weak self] title, date, rule in
            guard let self else { return }
            try? self.reminderStore?.add(ReminderItem(title: title, fireDate: date, recurrence: rule))
            self.app.sayLine("I'll remind you \(ProductivityWindowController.dueText(date, hasTime: true))! ⏰", style: .thought)
            self.changed()
        }
        window.onDeleteReminder = { [weak self] id in
            try? self?.reminderStore?.delete(id: id)
            self?.changed()
        }
        window.onOpenSettings = { [weak self] in self?.app.settingsWindow.show() }
    }

    /// Something changed: rebuild schedules and refresh the window.
    private func changed() {
        refreshReminders()
        window.refresh()
        app.dashboardNeedsRefresh()
    }

    func show(_ section: ProductivityWindowController.Section = .today) { window.show(section: section); startFocusTicker() }

    // MARK: Quick capture

    /// A small input dialog for the global "new task" shortcut.
    func promptQuickTask() {
        let alert = NSAlert()
        alert.messageText = "New task"
        alert.informativeText = "Try: “call mom tomorrow 5pm !high” · “water plants every day 8am” · “in 30 min stretch”"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "What needs doing?"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { quickAdd(field.stringValue) }
    }

    func quickAdd(_ text: String) {
        let p = QuickAddParser.parse(text)
        guard !p.title.isEmpty else { return }
        var draft = TaskDraft(title: p.title)
        draft.dueDate = p.dueDate
        draft.hasDueTime = p.hasDueTime
        draft.priority = p.priority
        draft.recurrence = p.recurrence
        draft.remindBeforeMinutes = p.remindBeforeMinutes
        addTask(draft, announce: p)
    }

    // MARK: Tasks

    func addTask(_ d: TaskDraft, announce: ParsedTask? = nil) {
        guard let taskStore else { return }
        var remind = d.dueDate == nil ? nil : d.remindBeforeMinutes
        if remind == nil, d.dueDate != nil, d.hasDueTime, settings.defaultTaskRemindMinutes > 0 { remind = settings.defaultTaskRemindMinutes }
        let task = TaskItem(title: d.title, priority: d.priority, dueDate: d.dueDate, recurrence: d.recurrence, notes: d.notes,
                            hasDueTime: d.hasDueTime, remindBeforeMinutes: remind, repeatEveryMinutes: d.repeatEveryMinutes)
        try? taskStore.add(task)
        var text = app.line(.taskAdded, force: true) ?? "Added!"
        if let due = d.dueDate { text += " \(ProductivityWindowController.dueText(due, hasTime: d.hasDueTime))" }
        app.sayLine(text, style: .thought)
        changed()
    }

    private func toggleTask(_ id: UUID) {
        guard let taskStore, let task = try? taskStore.task(id: id) else { return }
        if task.isCompleted { try? taskStore.uncomplete(id: id) } else { completeTask(task) }
        changed()
    }

    func completeTask(_ task: TaskItem) {
        guard let taskStore else { return }
        try? taskStore.complete(id: task.id)
        _ = try? taskStore.spawnNextOccurrenceIfRecurring(after: task)
        app.progressionStore.recordTaskCompleted()
        let now = Date()
        recentCompletions = recentCompletions.filter { now.timeIntervalSince($0) < 7200 } + [now]
        pet.flashBadge("✓")
        let remaining = ((try? taskStore.today()) ?? []).count
        if remaining == 0 {
            pet.send(.allTasksDone)
            pet.floatSymbol("🎉")
            if let l = app.line(.allTasks, force: true) { app.sayLine(l, style: .celebration) }
        } else {
            pet.send(.taskCompleted)
            pet.floatSymbol("✨")
            if recentCompletions.count >= 3, Bool.random(), let l = app.line(.streak) {
                app.sayLine(l, style: .celebration)
            } else if let l = app.line(.task, force: true) {
                app.sayLine(l)
            }
        }
    }

    /// QA only (DC_QA_OPEN=complete): completes the first open task as the checkbox would.
    func qaCompleteFirstTask() {
        if let t = ((try? taskStore?.today()) ?? []).first(where: { !$0.isCompleted }) ?? ((try? taskStore?.incomplete()) ?? []).first { toggleTask(t.id) }
    }

    // MARK: Focus (Pomodoro)

    func startPomodoro(_ newPlan: PomodoroPlan) {
        plan = newPlan
        // A new cycle after a long pause.
        if let last = lastPomodoroAt, Date().timeIntervalSince(last) > 2 * 3600 { pomodoroCompleted = 0 }
        let breakMinutes = plan.breakMinutes(afterCompleted: pomodoroCompleted + 1)
        focusTimer.start(focusMinutes: plan.workMinutes, breakMinutes: breakMinutes)
        focusStartedAt = Date()
        focusLastSync = Date()
        focusPlannedMinutes = plan.workMinutes
        halfwaySaid = false
        app.refreshCachedContext(now: Date(), idleSeconds: 0)
        pet.send(.focusStarted)
        if let l = app.line(.focusStart, force: true) { app.sayLine(l) }
        scheduleFocusPhaseEnd()
        startFocusTicker()
        changed()
    }

    /// Toggle from the menu/shortcut: start the user's Pomodoro plan or stop the running session.
    func toggleFocus() {
        if focusTimer.isActive { cancelFocus() } else { startPomodoro(settings.pomodoroPlan) }
    }

    private func pauseFocus() {
        syncFocus()
        focusTimer.pause()
        focusPhaseTimer?.invalidate()
        app.refreshCachedContext(now: Date(), idleSeconds: 0)
        updateFocusBadge()
        window.refresh()
    }

    private func resumeFocus() {
        focusTimer.resume()
        focusLastSync = Date()
        app.refreshCachedContext(now: Date(), idleSeconds: 0)
        scheduleFocusPhaseEnd()
        startFocusTicker()
        window.refresh()
    }

    func cancelFocus() {
        let wasFocusing = isFocusing
        if wasFocusing, let started = focusStartedAt {
            // Stopped early: the time actually spent still counts toward today's focus.
            let minutes = Date().timeIntervalSince(started) / 60
            if minutes >= 3 {
                try? focusHistoryStore?.add(FocusSessionRecord(startedAt: started, endedAt: Date(), plannedFocusMinutes: minutes.rounded(), completedFully: false))
            }
        }
        focusTimer.cancel()
        focusPhaseTimer?.invalidate()
        focusStartedAt = nil
        app.refreshCachedContext(now: Date(), idleSeconds: 0)
        pet.send(.focusStopped)
        if wasFocusing, let l = app.line(.focusStopped, force: true) { app.sayLine(l, style: .thought) }
        updateFocusBadge()
        changed()
    }

    private func syncFocus() {
        let now = Date()
        defer { focusLastSync = now }
        guard focusTimer.isActive else { return }
        if let event = focusTimer.tick(deltaTime: now.timeIntervalSince(focusLastSync)) {
            focusLastSync = now
            handleFocusEvent(event)
        }
    }

    private func scheduleFocusPhaseEnd() {
        focusPhaseTimer?.invalidate()
        let remaining: TimeInterval
        switch focusTimer.phase {
        case .focusing(let r), .onBreak(let r): remaining = r
        default: return
        }
        let t = Timer(timeInterval: remaining + 0.05, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.syncFocus()
            self.scheduleFocusPhaseEnd()
            self.window.refresh()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        focusPhaseTimer = t
    }

    /// Ticks the focus timer on the pet (and the window's countdown) every
    /// second while a session exists; stops itself when it ends.
    private func startFocusTicker() {
        updateFocusBadge()
        guard focusTicker == nil, focusTimer.isActive else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard self.focusTimer.isActive else {
                timer.invalidate()
                self.focusTicker = nil
                return
            }
            self.syncFocus()
            self.updateFocusBadge()
            self.checkHalfway()
            if self.window.isVisible { self.window.updateFocusClock(self.focusTimer.phase) }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        focusTicker = t
    }

    private func checkHalfway() {
        guard !halfwaySaid, case .focusing(let r) = focusTimer.phase, focusPlannedMinutes >= 20, r <= focusPlannedMinutes * 30 else { return }
        halfwaySaid = true
        if let l = app.line(.focusHalf, force: true) { app.sayLine(l, style: .thought) }
    }

    private func updateFocusBadge() {
        guard !focusCelebrating else { return }
        func t(_ s: TimeInterval) -> String { let v = max(0, Int(s.rounded(.up))); return String(format: "%d:%02d", v / 60, v % 60) }
        switch focusTimer.phase {
        case .focusing(let r): pet.setBadge("⏱ \(t(r))", kind: "focus")
        case .onBreak(let r): pet.setBadge("☕ \(t(r))", kind: "break")
        case .paused(_, let r): pet.setBadge("⏸ \(t(r))", kind: "paused")
        case .idle: if app.pet.brain.currentActivity == nil { pet.setBadge(nil) }
        }
    }

    private func handleFocusEvent(_ event: FocusEvent?) {
        guard let event else { window.refresh(); return }
        switch event {
        case .focusCompleted:
            let started = focusStartedAt ?? Date().addingTimeInterval(-focusPlannedMinutes * 60)
            try? focusHistoryStore?.add(FocusSessionRecord(startedAt: started, endedAt: Date(), plannedFocusMinutes: focusPlannedMinutes, completedFully: true))
            app.progressionStore.recordFocusSessionCompleted()
            pomodoroCompleted += 1
            lastPomodoroAt = Date()
            app.refreshCachedContext(now: Date(), idleSeconds: 0)
            activity.breakTaken() // the focus break covers the screen break
            focusCelebrating = true
            pet.setBadge("🎉 Done!", kind: "done", emphasis: true)
            pet.send(.focusCompleted)
            pet.floatSymbol("🍅")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.focusCelebrating = false
                self?.updateFocusBadge()
            }
            notify("Focus session complete", "\(Int(focusPlannedMinutes)) minutes done.")
            reminders.set("focus", DueReminder(id: "focus", kind: .focus, dueAt: Date(), title: "Focus done", urgency: .important))
            presentNextReminder()
        case .breakCompleted:
            focusStartedAt = nil
            try? wellnessStore?.add(WellnessEntry(kind: .focusBreak, action: .done))
            app.refreshCachedContext(now: Date(), idleSeconds: 0)
            updateFocusBadge()
            if plan.autoStartNext {
                app.sayLine("Break's over — next session starts now! 🍅", style: .speech)
                startPomodoro(plan)
            } else {
                askNextSession()
            }
        }
        changed()
    }

    private func askNextSession() {
        notify("Break's over", "Ready for the next session?")
        pet.ask("Break's over! Ready for the next session? 🍅", actions: [
            ("Start", true, { [weak self] in
                guard let self else { return }
                self.startPomodoro(self.plan)
            }),
            ("Later", false, { [weak self] in self?.app.sayLine("Just say when. 🐾", style: .thought) }),
        ], timeout: 40, onTimeout: {})
    }

    private func presentFocusDone() {
        let long = plan.isLongBreak(afterCompleted: pomodoroCompleted)
        let intro = long ? (app.line(.focusLongBreak, force: true) ?? "Long break earned!") : (app.line(.focusDone, force: true) ?? "Nice work! ✨")
        let minutes = Int(plan.breakMinutes(afterCompleted: pomodoroCompleted))
        pet.ask("\(intro)\nSession \(pomodoroCompleted) done · \(minutes) min break", actions: [
            ("Start break", true, { [weak self] in
                self?.pet.send(.breakStarted)
                self?.reminderFinished()
            }),
            ("Skip break", false, { [weak self] in
                guard let self else { return }
                self.focusTimer.cancel()
                self.startPomodoro(self.plan)
                self.reminderFinished()
            }),
        ], timeout: 40, style: .celebration, onTimeout: { [weak self] in self?.reminderFinished() })
    }

    // MARK: Water, breaks, eye and stretch nudges

    private func setUpNudges() {
        let now = Date()
        func anchor(_ key: String, interval: TimeInterval, last: Date?) -> Date {
            let saved = app.petState?.double(for: key).map(Date.init(timeIntervalSince1970:))
            // Never nag right at launch: at least 10 minutes in.
            return max(saved ?? last ?? now, now.addingTimeInterval(-interval + 600))
        }
        let waterInterval = settings.waterIntervalMinutes * 60
        let lastDrink = (try? wellnessStore?.lastDone(kind: .water)) ?? nil
        water = NudgeSchedule(enabled: settings.waterReminders, interval: waterInterval, anchor: anchor("water.anchor", interval: waterInterval, last: lastDrink))
        let eyeInterval = settings.eyeBreakIntervalMinutes * 60
        eye = NudgeSchedule(enabled: settings.eyeBreaks, interval: eyeInterval, anchor: anchor("eye.anchor", interval: eyeInterval, last: nil))
        let stretchInterval = settings.stretchIntervalMinutes * 60
        stretch = NudgeSchedule(enabled: settings.stretchNudges, interval: stretchInterval, anchor: anchor("stretch.anchor", interval: stretchInterval, last: nil))
    }

    /// Settings changed: re-read the nudge intervals and schedules.
    func settingsChanged() {
        water.enabled = settings.waterReminders
        water.interval = max(60, settings.waterIntervalMinutes * 60)
        eye.enabled = settings.eyeBreaks
        eye.interval = max(60, settings.eyeBreakIntervalMinutes * 60)
        stretch.enabled = settings.stretchNudges
        stretch.interval = max(60, settings.stretchIntervalMinutes * 60)
        plan = settings.pomodoroPlan
        if settings.systemNotifications { notifications.requestAuthorization() }
        changed()
    }

    func logWater(fromPet: Bool) {
        let now = Date()
        try? wellnessStore?.add(WellnessEntry(kind: .water, action: .done))
        water.confirm(now: now)
        try? app.petState?.set(String(now.timeIntervalSince1970), for: "water.anchor")
        pet.send(.waterLogged)
        pet.flashBadge("💧")
        let count = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
        if count == settings.waterGoal {
            pet.floatSymbol("💧")
            app.sayLine(app.line(.waterGoal, force: true) ?? "Water goal reached! 💧🎉", style: .celebration)
        } else {
            app.sayLine(app.line(.waterThanks, force: true) ?? "Good job! 💧")
        }
        if !fromPet { refreshReminders() }
        window.refresh()
        app.dashboardNeedsRefresh()
    }

    func takeBreak(fromPet: Bool) {
        try? wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .done))
        activity.breakTaken()
        screenBreakNotBefore = nil
        pet.send(.breakStarted)
        if let l = app.line(.breakThanks, force: true) { app.sayLine(l) }
        if !fromPet { refreshReminders() }
        window.refresh()
    }

    // MARK: Reminder engine

    /// Rebuilds everything the engine knows about and sleeps until the earliest due time.
    func refreshReminders(now: Date = Date()) {
        reminders.set("water", water.enabled ? water.nextDue.map { DueReminder(id: "water", kind: .water, dueAt: $0, title: "Water", urgency: .gentle) } : nil)
        reminders.set("eye", eye.enabled ? eye.nextDue.map { DueReminder(id: "eye", kind: .eyeBreak, dueAt: $0, title: "Eye break", urgency: .gentle) } : nil)
        reminders.set("stretch", stretch.enabled ? stretch.nextDue.map { DueReminder(id: "stretch", kind: .stretch, dueAt: $0, title: "Stretch", urgency: .gentle) } : nil)
        if settings.breakNudges {
            let remaining = max(0, settings.breakIntervalMinutes * 60 - activity.continuousActive)
            var due = now.addingTimeInterval(remaining)
            if let nb = screenBreakNotBefore, nb > due { due = nb }
            reminders.set("screenBreak", DueReminder(id: "screenBreak", kind: .screenBreak, dueAt: due, title: "Screen break", urgency: .gentle))
        } else {
            reminders.set("screenBreak", nil)
        }
        // Bedtime: once each evening.
        let cal = Calendar.current
        if settings.bedtimeReminder, app.petState?.value(for: "bedtime.day") != Self.dayKey(now),
           var at = cal.date(bySettingHour: settings.bedtimeHour, minute: 0, second: 0, of: now) {
            // An after-midnight bedtime (say 01:00) seen in the evening means tonight's, not the one that already passed.
            if at < now.addingTimeInterval(-2 * 3600), let next = cal.date(byAdding: .day, value: 1, to: at) { at = next }
            reminders.set("bedtime", DueReminder(id: "bedtime", kind: .bedtime, dueAt: at, title: "Bedtime", urgency: .noticeable, breaksQuietHours: true))
        } else {
            reminders.set("bedtime", nil)
        }
        let taskReminders = ((try? taskStore?.withReminders()) ?? []).compactMap { TaskReminderPlanner.next(for: $0, now: now) }
        reminders.replaceAll(of: .task, with: taskReminders)
        let custom = ((try? reminderStore?.pending()) ?? []).map {
            DueReminder(id: "custom:\($0.id.uuidString)", kind: .custom, dueAt: max($0.fireDate, $0.snoozedUntil ?? $0.fireDate), title: $0.title)
        }
        reminders.replaceAll(of: .custom, with: custom)
        scheduleReminderWake(now: now)
    }

    private func scheduleReminderWake(now: Date = Date()) {
        reminderTimer?.invalidate()
        guard let next = reminders.nextWakeDate else { return }
        let t = Timer(timeInterval: max(1, next.timeIntervalSince(now)), repeats: false) { [weak self] _ in self?.presentNextReminder() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        reminderTimer = t
    }

    private func retryReminders(in seconds: TimeInterval) {
        reminderTimer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.presentNextReminder() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        reminderTimer = t
    }

    private func presentNextReminder() {
        let now = Date()
        guard !pet.isAsking, pet.isVisible, pet.brain.behavior != .dragged else { retryReminders(in: 20); return }
        var c = ReminderQueue.Conditions()
        c.quietHours = quietHours.contains(now)
        c.focusActive = isFocusing
        c.userAway = !activity.isUserActive(secondsSinceLastInput: IdleTimeReader.secondsSinceLastInput()) && ProcessInfo.processInfo.environment["DC_QA_PRESENT"] == nil
        c.allowUrgentInQuietHours = settings.urgentBreaksQuiet
        guard let r = reminders.next(now: now, conditions: c) else {
            if let wake = reminders.nextWakeDate, wake <= now { retryReminders(in: 60) } else { scheduleReminderWake(now: now) }
            return
        }
        present(r)
    }

    private func reminderFinished() {
        reminders.finishPresenting()
        refreshReminders()
        window.refresh()
        retryReminders(in: 3) // a short breath before the next queued thing
    }

    private func present(_ r: DueReminder) {
        switch r.kind {
        case .water: presentNudge(.water, key: "water.anchor", kind: .water, category: .water, thanks: .waterThanks, skipped: .waterSkipped)
        case .eyeBreak: presentNudge(.eyeBreak, key: "eye.anchor", kind: .eyeBreak, category: .eyeBreak, thanks: .breakThanks, skipped: .breakSkipped)
        case .stretch: presentNudge(.stretch, key: "stretch.anchor", kind: .stretch, category: .stretch, thanks: .breakThanks, skipped: .breakSkipped)
        case .screenBreak: presentScreenBreak()
        case .task: presentTask(r)
        case .custom: presentCustom(r)
        case .focus: presentFocusDone()
        case .bedtime: presentBedtime()
        }
    }

    private func snoozeChoices(for kind: ReminderKind, apply: @escaping (TimeInterval?) -> Void) {
        let options = kind.snoozeOptions.map { opt -> (title: String, primary: Bool, handler: () -> Void) in (opt.label, false, { apply(opt.seconds) }) }
        pet.replaceQuestion("Remind you in…", actions: options, timeout: 25, onTimeout: { apply(600) })
    }

    /// Water / eye break / stretch share one shape: [Done] [Snooze] [Skip] on a NudgeSchedule.
    private func presentNudge(_ rk: ReminderKind, key: String, kind: WellnessKind,
                              category: MessageCategory, thanks: MessageCategory, skipped: MessageCategory) {
        func sched() -> NudgeSchedule { rk == .water ? water : (rk == .eyeBreak ? eye : stretch) }
        sched().beginAsking()
        let doneTitle = rk == .water ? "I drank 💧" : (rk == .eyeBreak ? "Done 👀" : "Done 🧘")
        notify(rk == .water ? "Water break" : (rk == .eyeBreak ? "Eye break" : "Stretch"), app.line(category, force: true) ?? "")
        pet.ask(app.line(category, force: true) ?? "Time for a break!", actions: [
            (doneTitle, true, { [weak self] in
                guard let self else { return }
                if rk == .water { self.logWater(fromPet: true) } else {
                    let s = sched(); s.confirm(now: Date())
                    try? self.wellnessStore?.add(WellnessEntry(kind: kind, action: .done))
                    try? self.app.petState?.set(String(Date().timeIntervalSince1970), for: key)
                    self.pet.send(.breakStarted)
                    if let l = self.app.line(thanks, force: true) { self.app.sayLine(l) }
                    self.activity.breakTaken()
                }
                self.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: rk) { seconds in
                    guard let self else { return }
                    sched().snooze(now: Date(), seconds: seconds ?? 600)
                    try? self.wellnessStore?.add(WellnessEntry(kind: kind, action: .snoozed))
                    if let l = self.app.line(.snoozed, force: true) { self.app.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Skip", false, { [weak self] in
                guard let self else { return }
                sched().skip(now: Date())
                try? self.wellnessStore?.add(WellnessEntry(kind: kind, action: .skipped))
                try? self.app.petState?.set(String(Date().timeIntervalSince1970), for: key)
                if let l = self.app.line(skipped, force: true) { self.app.sayLine(l, style: .thought) }
                self.reminderFinished()
            }),
        ], timeout: 45, approach: true, onTimeout: { [weak self] in
            sched().timedOut(now: Date())
            self?.reminderFinished()
        })
    }

    private func presentScreenBreak() {
        pet.ask(app.line(.breakAsk, force: true) ?? "Your eyes need a break 👀", actions: [
            ("Take a break", true, { [weak self] in
                self?.takeBreak(fromPet: true)
                self?.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: .screenBreak) { seconds in
                    guard let self else { return }
                    self.screenBreakNotBefore = Date().addingTimeInterval(seconds ?? 600)
                    try? self.wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .snoozed))
                    if let l = self.app.line(.snoozed, force: true) { self.app.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Skip", false, { [weak self] in
                guard let self else { return }
                self.screenBreakNotBefore = Date().addingTimeInterval(max(20 * 60, self.settings.breakIntervalMinutes * 60 / 2))
                try? self.wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .skipped))
                if let l = self.app.line(.breakSkipped, force: true) { self.app.sayLine(l, style: .thought) }
                self.reminderFinished()
            }),
        ], timeout: 45, approach: true, onTimeout: { [weak self] in
            self?.screenBreakNotBefore = Date().addingTimeInterval(15 * 60)
            self?.reminderFinished()
        })
    }

    private func presentBedtime() {
        try? app.petState?.set(Self.dayKey(Date()), for: "bedtime.day")
        let open = ((try? taskStore?.today()) ?? []).count
        var text = app.line(.bedtime, force: true) ?? "Time to wind down? 🌙"
        if open > 0 { text += "\n\(open) task\(open == 1 ? "" : "s") still open — move them to tomorrow?" }
        notify("Bedtime", text)
        var actions: [(title: String, primary: Bool, handler: () -> Void)] = [("Good night 🌙", true, { [weak self] in self?.reminderFinished() })]
        if open > 0 {
            actions.insert(("Move to tomorrow", true, { [weak self] in
                self?.moveOpenTasksToTomorrow()
                self?.reminderFinished()
            }), at: 0)
        }
        actions.append(("30 min", false, { [weak self] in
            guard let self else { return }
            self.reminders.set("bedtime", DueReminder(id: "bedtime", kind: .bedtime, dueAt: Date().addingTimeInterval(1800), title: "Bedtime", breaksQuietHours: true))
            try? self.app.petState?.set("", for: "bedtime.day")
            self.reminders.finishPresenting()
            self.scheduleReminderWake()
        }))
        pet.ask(text, actions: actions, timeout: 60, approach: true, onTimeout: { [weak self] in self?.reminderFinished() })
    }

    private func moveOpenTasksToTomorrow() {
        guard let taskStore else { return }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        for var t in (try? taskStore.today()) ?? [] where !t.isCompleted {
            if let due = t.dueDate {
                let parts = cal.dateComponents([.hour, .minute], from: due)
                t.dueDate = t.hasDueTime ? cal.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: tomorrow) : tomorrow
            } else {
                t.dueDate = tomorrow
            }
            t.reminderHandledAt = nil
            t.reminderSnoozedUntil = nil
            try? taskStore.update(t)
        }
        app.sayLine("All moved to tomorrow. Rest well! 🌙", style: .thought)
        changed()
    }

    private func presentTask(_ r: DueReminder) {
        guard let id = r.taskID, let task = try? taskStore?.task(id: id) else { reminderFinished(); return }
        let overdue = (task.deadline() ?? .distantFuture) < Date().addingTimeInterval(-300)
        let intro: String
        switch r.urgency {
        case .gentle: intro = overdue ? (app.line(.overdue, force: true) ?? "Overdue:") : (app.line(.taskTomorrow, force: true) ?? "Heads-up:")
        case .noticeable: intro = app.line(.taskSoon, force: true) ?? "Hey! You have something coming up."
        case .important: intro = app.line(.taskNow, force: true) ?? "This is due now!"
        }
        let when = task.deadline().map { ProductivityWindowController.dueText($0, hasTime: task.hasDueTime) } ?? ""
        let text = "\(intro)\n“\(task.title)”" + (when.isEmpty ? "" : " · \(when)")
        notify(task.title, when.isEmpty ? intro : when)
        pet.send(.reminderDue)
        func update(_ change: (inout TaskItem) -> Void) {
            guard var t = try? taskStore?.task(id: id) else { return }
            change(&t)
            try? taskStore?.update(t)
        }
        pet.ask(text, actions: [
            ("Done ✓", true, { [weak self] in
                guard let self, let t = try? self.taskStore?.task(id: id) else { return }
                self.completeTask(t)
                self.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: .task) { seconds in
                    guard let self else { return }
                    let until: Date
                    if let seconds { until = Date().addingTimeInterval(seconds) } else {
                        let cal = Calendar.current
                        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
                        until = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                    }
                    update { $0.reminderSnoozedUntil = until }
                    if let l = self.app.line(.snoozed, force: true) { self.app.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Dismiss", false, { [weak self] in
                update { $0.reminderHandledAt = max(Date(), r.dueAt); $0.reminderSnoozedUntil = nil }
                self?.reminderFinished()
            }),
        ], timeout: r.urgency == .important ? 90 : 60, approach: true, style: r.urgency == .important ? .speech : .thought, onTimeout: { [weak self] in
            update { $0.reminderSnoozedUntil = Date().addingTimeInterval(15 * 60) }
            self?.reminderFinished()
        })
    }

    private func presentCustom(_ r: DueReminder) {
        guard let reminderStore, let idString = r.id.split(separator: ":").last, let id = UUID(uuidString: String(idString)),
              let item = (try? reminderStore.pending())?.first(where: { $0.id == id }) else { reminderFinished(); return }
        notify(app.petName, item.title)
        pet.send(.reminderDue)
        pet.ask("⏰ \(item.title)", actions: [
            ("Done ✓", true, { [weak self] in
                try? reminderStore.dismiss(id: id)
                _ = try? reminderStore.spawnNextOccurrenceIfRecurring(after: item)
                self?.app.sayLine("Nice! ✓", style: .thought)
                self?.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: .custom) { seconds in
                    try? reminderStore.snooze(id: id, until: Date().addingTimeInterval(seconds ?? 600))
                    self?.reminderFinished()
                }
            }),
            ("Dismiss", false, { [weak self] in
                try? reminderStore.dismiss(id: id)
                _ = try? reminderStore.spawnNextOccurrenceIfRecurring(after: item)
                self?.reminderFinished()
            }),
        ], timeout: 60, approach: true, onTimeout: { [weak self] in
            try? reminderStore.snooze(id: id, until: Date().addingTimeInterval(15 * 60))
            self?.reminderFinished()
        })
    }

    private func notify(_ title: String, _ body: String) {
        guard settings.systemNotifications, Bundle.main.bundleIdentifier != nil else { return }
        notifications.post(identifier: UUID().uuidString, title: title, body: body)
    }

    // MARK: Housekeeping (called every 30 s)

    func housekeeping(dt: Double, sample: ActivityTracker.Sample, idle: Double, now: Date) {
        pendingActive += sample.active
        pendingIdle += sample.idle
        if isFocusing { pendingFocus += sample.active }
        checkBriefs(idle: idle, now: now)
        refreshReminders(now: now) // the screen-break due time moves with real activity
    }

    func flushScreenTime() {
        guard let screenTimeStore else { return }
        if pendingActive > 0 { try? screenTimeStore.addActiveSeconds(pendingActive) }
        if pendingIdle > 0 { try? screenTimeStore.addIdleSeconds(pendingIdle) }
        if pendingFocus > 0 { try? screenTimeStore.addFocusSeconds(pendingFocus) }
        pendingActive = 0
        pendingIdle = 0
        pendingFocus = 0
    }

    func userReturned() { refreshReminders() }

    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The morning brief (first time you're around) and the daily recap (at the chosen hour), once each per day.
    private func checkBriefs(idle: Double, now: Date) {
        guard app.onboardingProgress.hasCompleted, idle < 120, settings.speechBubbles, !isFocusing, !pet.isAsking, !pet.brain.isAsleep else { return }
        let hour = Calendar.current.component(.hour, from: now)
        let today = Self.dayKey(now)
        if settings.morningBrief, (5..<12).contains(hour), app.petState?.value(for: "brief.day") != today {
            try? app.petState?.set(today, for: "brief.day")
            let open = (try? taskStore?.today()) ?? []
            let overdue = open.filter { ($0.deadline() ?? .distantFuture) < now }
            var text = "Good morning! "
            if open.isEmpty { text += "Your day is clear. ☀️" }
            else {
                text += "\(open.count) task\(open.count == 1 ? "" : "s") today"
                if !overdue.isEmpty { text += ", \(overdue.count) overdue" }
                text += "."
                if let first = open.first(where: { $0.hasDueTime && ($0.deadline() ?? .distantPast) > now }) ?? open.first {
                    text += "\nFirst: “\(first.title)”"
                }
            }
            app.sayLine(text, style: .speech, duration: 8)
        } else if settings.dailyRecap, hour >= settings.recapHour, app.petState?.value(for: "recap.day") != today {
            try? app.petState?.set(today, for: "recap.day")
            let tasks = (try? taskStore?.completedOnDay(of: now))?.count ?? 0
            let focus = Int((try? focusHistoryStore?.focusMinutes(on: now)) ?? 0)
            let water = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
            guard tasks + focus + water > 0 else { return }
            var parts: [String] = []
            if tasks > 0 { parts.append("\(tasks) task\(tasks == 1 ? "" : "s") done") }
            if focus > 0 { parts.append("\(focus) min focused") }
            if water > 0 { parts.append("\(water) glass\(water == 1 ? "" : "es") of water") }
            app.sayLine("Today: \(parts.joined(separator: " · ")). \(app.line(.recap, force: true) ?? "")", style: .celebration, duration: 9)
        }
    }

    // MARK: Snapshots

    func nextEventText(now: Date = Date()) -> String {
        func mins(_ d: Date) -> String {
            let m = max(1, Int(d.timeIntervalSince(now) / 60 + 0.5))
            return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
        }
        switch focusTimer.phase {
        case .focusing(let r): return "Focus ends in \(mins(now.addingTimeInterval(r)))"
        case .onBreak(let r): return "Break ends in \(mins(now.addingTimeInterval(r)))"
        default: break
        }
        guard let next = reminders.items.values.min(by: { $0.dueAt < $1.dueAt }) else { return "Nothing scheduled" }
        let label: String
        switch next.kind {
        case .water: label = "Water check"
        case .screenBreak: label = "Screen break"
        case .eyeBreak: label = "Eye break"
        case .stretch: label = "Stretch"
        case .bedtime: label = "Bedtime"
        case .task: label = "“\(next.title)”"
        case .custom: label = "Reminder: \(next.title)"
        case .focus: label = "Focus"
        }
        return next.dueAt <= now ? "\(label) soon" : "\(label) in \(mins(next.dueAt))"
    }

    func makeSnapshot() -> ProductivitySnapshot {
        syncFocus()
        let now = Date()
        let cal = Calendar.current
        var s = ProductivitySnapshot()
        s.petName = app.petName
        s.petStatus = app.petStatusText()
        s.mood = pet.brain.mood(app.cachedContext).label
        s.greeting = Self.greeting()
        s.nextEvent = nextEventText(now: now)
        let open = (try? taskStore?.today()) ?? []
        let doneToday = (try? taskStore?.completedOnDay()) ?? []
        s.overdue = open.filter { !$0.isCompleted && ($0.deadline() ?? .distantFuture) < now }
        s.todayTasks = (open.filter { t in !s.overdue.contains(where: { $0.id == t.id }) }) + doneToday
        s.upcoming = Array(((try? taskStore?.incomplete()) ?? []).filter { !$0.isDueToday() }.prefix(40))
        s.doneRecently = Array(((try? taskStore?.completed()) ?? []).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(30))
        s.tasksDoneToday = doneToday.count
        s.focusPhase = focusTimer.phase
        s.focusSessionsToday = (try? focusHistoryStore?.todayCompletedSessionCount()) ?? 0
        s.focusMinutesToday = Int((try? focusHistoryStore?.focusMinutes(on: now)) ?? 0)
        s.focusGoalMinutes = settings.focusGoalMinutes
        s.pomodoroPlan = settings.pomodoroPlan
        s.pomodoroCompleted = lastPomodoroAt.map { now.timeIntervalSince($0) < 2 * 3600 ? pomodoroCompleted : 0 } ?? 0
        s.waterToday = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
        s.waterGoal = settings.waterGoal
        s.lastWater = (try? wellnessStore?.lastDone(kind: .water)) ?? nil
        s.nextWater = water.enabled ? water.nextDue : nil
        s.breaksToday = (try? wellnessStore?.todayDoneCount(kind: .shortBreak)) ?? 0
        s.focusBreaksToday = (try? wellnessStore?.todayDoneCount(kind: .focusBreak)) ?? 0
        let totals = (try? screenTimeStore?.totals()) ?? nil
        s.activeMinutesToday = Int(((totals?.activeSeconds ?? 0) + pendingActive) / 60)
        s.idleMinutesToday = Int(((totals?.idleSeconds ?? 0) + pendingIdle) / 60)
        s.continuousWorkMinutes = Int(activity.continuousActive / 60)
        s.reminders = Array(((try? reminderStore?.pending()) ?? []).prefix(8))
        s.eyeBreaksOn = settings.eyeBreaks
        s.stretchOn = settings.stretchNudges
        s.bedtimeOn = settings.bedtimeReminder
        s.streakDays = streak(now: now)
        s.week = week(now: now, calendar: cal)
        return s
    }

    private func activeDays() -> [Date] {
        let tasks = ((try? taskStore?.completed()) ?? []).compactMap(\.completedAt)
        let sessions = ((try? focusHistoryStore?.all()) ?? []).filter(\.completedFully).map(\.startedAt)
        return tasks + sessions
    }

    func streak(now: Date = Date()) -> Int { StreakCalculator.streak(activeDays: activeDays(), today: now) }

    private func week(now: Date, calendar cal: Calendar) -> [DayStat] {
        let completed = ((try? taskStore?.completed()) ?? []).compactMap(\.completedAt)
        let sessions = (try? focusHistoryStore?.all()) ?? []
        let waters = ((try? wellnessStore?.all()) ?? []).filter { $0.kind == .water && $0.action == .done }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: now) ?? now
            var stat = DayStat(label: back == 0 ? "Today" : f.string(from: day))
            stat.tasks = completed.filter { cal.isDate($0, inSameDayAs: day) }.count
            stat.focusMinutes = Int(sessions.filter { cal.isDate($0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.plannedFocusMinutes })
            stat.water = waters.filter { cal.isDate($0.timestamp, inSameDayAs: day) }.count
            let totals = (try? screenTimeStore?.totals(date: day)) ?? nil
            stat.activeMinutes = Int(((totals?.activeSeconds ?? 0) + (back == 0 ? pendingActive : 0)) / 60)
            return stat
        }
    }

    /// One-line productivity summary for the dashboard.
    func summaryLines() -> (tasks: String, focus: String, water: String) {
        let done = (try? taskStore?.completedOnDay())?.count ?? 0
        let open = ((try? taskStore?.today()) ?? []).count
        let focus = Int((try? focusHistoryStore?.focusMinutes(on: Date())) ?? 0)
        let water = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
        return ("\(done) done · \(open) open", "\(focus) of \(settings.focusGoalMinutes) min", "\(water) of \(settings.waterGoal)")
    }

    private static func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Good morning ☀️"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Getting late 🌙"
        }
    }
}
