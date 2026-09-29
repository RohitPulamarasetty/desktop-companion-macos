import AppKit
import Core
import PlatformMac
import Diagnostics

/// Wiring only. The pet (CharacterWindowController + PetBrain) does the
/// living; this connects it to the user's data. Everything on a clock is
/// scheduled at its own next due time -- nothing polls every second
/// (the one exception, the focus timer on the pet, ticks each second only
/// while a session is running).
final class AppDelegate: NSObject, NSApplicationDelegate, PlatformPaths {
    private var pet: CharacterWindowController!
    private var characters = CharacterRepository(characters: [])
    private var picker: CharacterPickerController?
    private var menuBar: MenuBarController!
    private var screenTracker: ScreenTracker!
    private var sleepWakeMonitor: SleepWakeMonitor!
    private var fullscreenMonitor: FullscreenMonitor!
    private var diagnosticsOverlay: DiagnosticsOverlayWindow?
    private var diagnosticsLogger: DiagnosticsLogger!
    private var sampler: PerformanceSampler!
    private var notificationScheduler: NotificationScheduler?
    private var home: CompanionPanelController!
    private var settingsWindow: SettingsWindowController!
    private let aboutWindow = AboutWindowController()
    private var onboardingWindow: OnboardingWindowController?

    // Local stores -- SQLite / UserDefaults, no network.
    private var taskStore: TaskStore?
    private var reminderStore: ReminderStore?
    private var focusHistoryStore: FocusHistoryStore?
    private var wellnessStore: WellnessStore?
    private var screenTimeStore: ScreenTimeStore?
    private var petState: PetStateStore?
    private let focusTimer = FocusTimer()
    private var focusStartedAt: Date?
    private var focusPlannedMinutes: Double = 25
    private var focusLastSync = Date()

    private let appSettings = AppSettings()
    private lazy var onboardingProgress = OnboardingProgress(settings: appSettings)
    private let progressionStore = ProgressionStore()
    private let messages = PetMessageBook(rng: SeededRandom(seed: UInt64(Date().timeIntervalSince1970)))

    // The one reminder engine + the policies that feed it.
    private let reminders = ReminderQueue()
    private var water: NudgeSchedule!
    private let activity = ActivityTracker()
    /// Screen-break reminder can't come back before this (snooze / skip).
    private var screenBreakNotBefore: Date?

    private var quietHours: QuietHours {
        QuietHours(startHour: appSettings.quietHoursStart, endHour: appSettings.quietHoursEnd)
    }

    // Timers: 30 s housekeeping + one-shot timers at real due times.
    private var housekeeping: Timer?
    private var housekeepingCount = 0
    private var lastHousekeeping = Date()
    private var focusPhaseTimer: Timer?
    private var reminderTimer: Timer?
    private var focusTicker: Timer?

    private var pendingActiveSeconds: Double = 0
    private var pendingIdleSeconds: Double = 0
    private var pendingFocusSeconds: Double = 0

    private var cachedContext = PetContext()
    private var lastGreetingBucket: String?
    private var lastPersistedStats = PetStats()
    private var lastInteractionAt = Date()
    private var recentTaskCompletions: [Date] = []

    // MARK: - Launch / quit

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, not in Cmd+Tab

        setUpStores()

        characters = CharacterRepository(directories: [Self.charactersDirectory(), Self.installedCharactersDirectory()])
        for failure in characters.failures {
            NSLog("[DesktopCompanion] Skipping character package '%@': %@", failure.id, "\(failure.error)")
        }
        let selected = characters.resolveSelection(petState?.selectedCharacterID() ?? appSettings.selectedCharacterID)

        pet = CharacterWindowController(
            character: selected,
            settings: appSettings,
            savedPosition: petState?.savedPosition(),
            savedEnergy: petState?.energy()
        )
        refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        pet.contextProvider = { [weak self] in self?.cachedContext ?? PetContext() }
        applyPersonalitySettings()
        wirePet()
        pet.show()

        setUpHome()
        setUpSettingsWindow()
        setUpMenuBar()
        setUpScreenTracking()
        setUpSleepWake()
        setUpFullscreenMonitoring()
        setUpDiagnostics()
        setUpNotifications()
        setUpWellness()
        startHousekeeping()
        refreshReminders()

        if !onboardingProgress.hasCompleted {
            showOnboarding()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.say(.welcome) }
        }

        // QA hook (docs/ARCHITECTURE.md "Testing"): open a surface at launch
        // so it can be screenshotted / clicked without writing any data.
        if let qa = ProcessInfo.processInfo.environment["DC_QA_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.openForQA(qa) }
        }

        NSLog("[DesktopCompanion] %d characters installed; wearing '%@'", characters.characters.count, selected.displayName)
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeeping?.invalidate()
        flushScreenTime()
        persistPetState()
        diagnosticsLogger.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func openForQA(_ what: String) {
        switch what {
        case "picker": showPicker()
        case "settings": settingsWindow.show()
        case "about": aboutWindow.show()
        case "onboarding": showOnboarding()
        case "tasks": showHome(.tasks)
        case "focus": showHome(.focus)
        case "wellness": showHome(.wellness)
        case "pet": showHome(.pet)
        case "home": showHome(.today)
        case "water": present(DueReminder(id: "water", kind: .water, dueAt: Date(), title: "Water"))
        case "break": present(DueReminder(id: "screenBreak", kind: .screenBreak, dueAt: Date(), title: "Screen break"))
        case "say": pet.say("Hm, what's over there?", style: .thought, duration: 60)
        case "sleep": pet.send(.tuckIn)
        default: break
        }
    }

    // MARK: - Locations

    private static func charactersDirectory() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Characters"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Characters")
    }

    /// Not `private` (only widened from it) so it can also serve as the
    /// `PlatformPaths` witness just below -- nothing outside this file
    /// calls it directly either way.
    static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCompanion", isDirectory: true)
    }

    /// `PlatformPaths` conformance: the seam a Windows/Linux shell's own
    /// equivalent (`%APPDATA%\DesktopCompanion\`, `$XDG_DATA_HOME/DesktopCompanion/`)
    /// would implement instead. See `Sources/Core/Platform/PlatformProtocols.swift`.
    static func dataDirectory() -> URL { applicationSupportDirectory() }

    /// Where `CharacterPackageInstaller` puts user-installed characters --
    /// distinct from the app bundle's read-only `Characters/`, so a bundled
    /// character is never mistaken for one the user installed (or vice
    /// versa) and an app update can never silently delete an install.
    private static func installedCharactersDirectory() -> URL {
        applicationSupportDirectory().appendingPathComponent("Characters", isDirectory: true)
    }

    // MARK: - Setup

    private func setUpStores() {
        let dir = Self.applicationSupportDirectory()
        func open<T>(_ name: String, _ make: (URL) throws -> T) -> T? {
            do { return try make(dir.appendingPathComponent(name)) } catch {
                NSLog("[DesktopCompanion] Failed to open %@: %@ -- that feature won't persist this session.", name, "\(error)")
                return nil
            }
        }
        taskStore = open("tasks.sqlite", TaskStore.init)
        reminderStore = open("reminders.sqlite", ReminderStore.init)
        focusHistoryStore = open("focus_history.sqlite", FocusHistoryStore.init)
        wellnessStore = open("wellness.sqlite", WellnessStore.init)
        screenTimeStore = open("screen_time.sqlite", ScreenTimeStore.init)
        petState = open("pet_state.sqlite", PetStateStore.init)
        try? petState?.prune()
    }

    private func wirePet() {
        pet.onClick = { [weak self] outcome in
            guard let self else { return }
            self.noteInteraction()
            if outcome.woke {
                self.say(.wake)
            } else if outcome.barked {
                self.sayLine(self.pet.character.hasExact("stand_bark") ? "Woof! 🐾" : (self.line(.click) ?? "Hi! 👋"), style: .speech)
            } else if Int.random(in: 0..<3) == 0, let l = self.line(.click) {
                self.sayLine(l, style: .thought)
            }
        }
        pet.onDropped = { [weak self] in
            guard let self else { return }
            self.noteInteraction()
            try? self.petState?.savePosition(self.pet.savedPosition())
        }
        pet.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.noteInteraction()
            self.showHome(.today)
        }
        pet.onContextMenu = { [weak self] _ in
            guard let self else { return }
            self.noteInteraction()
            self.buildPetMenu(includeAppItems: false).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        pet.onBehaviorChange = { [weak self] behavior in
            guard let self else { return }
            self.petState?.recordDiscovered(behavior.rawValue)
            if behavior == .sleep, !self.pet.isAsking { self.say(.sleep, style: .thought) }
        }
    }

    private func noteInteraction() {
        lastInteractionAt = Date()
        progressionStore.recordInteraction()
        progressionStore.recordActiveDay(now: lastInteractionAt)
        try? petState?.saveLastInteraction(lastInteractionAt)
    }

    private func applyPersonalitySettings() {
        messages.chattiness = pet.character.personality.chattiness * appSettings.talkativeness.multiplier
        pet.brain.setCursorInterest(appSettings.followCursor.interest)
    }

    private func setUpMenuBar() {
        menuBar = MenuBarController()
        menuBar.menuProvider = { [weak self] in self?.buildPetMenu(includeAppItems: true) ?? NSMenu() }
        menuBar.install()
    }

    private func buildPetMenu(includeAppItems: Bool) -> NSMenu {
        let model = PetMenuModel(petName: petName, petStatus: petStatusText(), focusPhase: focusTimer.phase,
                                 isAsleep: pet.brain.isAsleep, petHidden: pet.isHiddenByUser, includeAppItems: includeAppItems,
                                 companionMode: appSettings.companionMode)
        var a = PetMenuActions()
        a.openHome = { [weak self] section in self?.showHome(section) }
        a.startFocus = { [weak self] f, b in self?.startFocus(f, b) }
        a.pauseFocus = { [weak self] in self?.pauseFocus() }
        a.resumeFocus = { [weak self] in self?.resumeFocus() }
        a.stopFocus = { [weak self] in self?.cancelFocus() }
        a.chooseCharacter = { [weak self] in self?.showPicker() }
        a.toggleSleep = { [weak self] in
            guard let self else { return }
            if self.pet.brain.isAsleep { self.pet.send(.wakeRequest); self.say(.wake) } else { self.pet.send(.tuckIn) }
        }
        a.toggleHidden = { [weak self] in self?.pet.toggleVisibility() }
        a.setMode = { [weak self] mode in
            guard let self else { return }
            self.appSettings.companionMode = mode
            self.refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        }
        a.openSettings = { [weak self] in self?.settingsWindow.show() }
        a.openDiagnostics = { [weak self] in self?.toggleDiagnosticsOverlay() }
        a.openAbout = { [weak self] in self?.aboutWindow.show() }
        a.quit = { NSApp.terminate(nil) }
        return PetMenu.build(model, a)
    }

    private func setUpScreenTracking() {
        screenTracker = ScreenTracker()
        screenTracker.onScreensChanged = { [weak self] in self?.pet.screensChanged() }
    }

    private func setUpSleepWake() {
        sleepWakeMonitor = SleepWakeMonitor()
        sleepWakeMonitor.onSleep = { [weak self] in self?.pet.setHidden(true, reason: .systemSleep) }
        sleepWakeMonitor.onWake = { [weak self] in
            guard let self else { return }
            self.pet.setHidden(false, reason: .systemSleep)
            self.lastHousekeeping = Date()
            self.syncFocus()
            self.refreshReminders()
        }
        sleepWakeMonitor.onDisplaysSleep = { [weak self] in self?.pet.setHidden(true, reason: .displaysAsleep) }
        sleepWakeMonitor.onDisplaysWake = { [weak self] in self?.pet.setHidden(false, reason: .displaysAsleep) }
    }

    private func setUpFullscreenMonitoring() {
        fullscreenMonitor = FullscreenMonitor()
        fullscreenMonitor.onShouldHideChanged = { [weak self] hide in self?.pet.setHidden(hide, reason: .policy) }
        fullscreenMonitor.onActiveSpaceChanged = { [weak self] in self?.pet.ensureOnActiveSpace() }
        applyVisibilityPolicy()
    }

    private func applyVisibilityPolicy() {
        fullscreenMonitor.policy = .init(hideInFullscreen: appSettings.hideInFullscreen,
                                         hideInPresentations: appSettings.hideInPresentations,
                                         hideInGames: appSettings.hideInGames)
    }

    private func setUpDiagnostics() {
        let logURL = Self.applicationSupportDirectory().appendingPathComponent("diagnostics.log")
        diagnosticsLogger = DiagnosticsLogger(fileURL: logURL)
        sampler = PerformanceSampler()
    }

    private func setUpNotifications() {
        // UNUserNotificationCenter throws for a process without a bundle
        // identifier (e.g. `swift run`); the pet's own bubble covers that case.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let scheduler = NotificationScheduler()
        scheduler.requestAuthorization()
        notificationScheduler = scheduler
    }

    private func setUpSettingsWindow() {
        settingsWindow = SettingsWindowController(settings: appSettings)
        settingsWindow.dataDirectory = Self.applicationSupportDirectory()
        settingsWindow.onPetSizeChanged = { [weak self] in self?.pet.applyPetSize() }
        settingsWindow.onPlacementChanged = { [weak self] in
            self?.pet.applyPlacementSettings()
            self?.pet.screensChanged()
        }
        settingsWindow.onVisibilityPolicyChanged = { [weak self] in self?.applyVisibilityPolicy() }
        settingsWindow.onBehaviorSettingsChanged = { [weak self] in
            guard let self else { return }
            self.refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
            self.pet.applyPlacementSettings()
            self.applyPersonalitySettings()
        }
        settingsWindow.onNudgeSettingsChanged = { [weak self] in self?.applyWellnessSettings() }
        settingsWindow.onEnvironmentSettingsChanged = { [weak self] in
            guard let self else { return }
            self.refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        }
        settingsWindow.onResetPosition = { [weak self] in self?.pet.resetToHome() }
        settingsWindow.characterNameProvider = { [weak self] in self?.pet.character.displayName ?? "" }
        settingsWindow.onChooseCharacter = { [weak self] in self?.showPicker() }
        settingsWindow.onShowDiagnostics = { [weak self] in self?.toggleDiagnosticsOverlay() }
        settingsWindow.onReplayOnboarding = { [weak self] in
            guard let self else { return }
            self.onboardingProgress.reset() // so quitting mid-tour still shows it again next launch, not just this once
            self.showOnboarding()
        }
        settingsWindow.onResetSettings = { [weak self] in self?.resetSettings() }
        settingsWindow.onDeleteInstalledCharacters = { [weak self] in self?.deleteInstalledCharacters() }
        settingsWindow.onResetEverything = { [weak self] in self?.resetEverything() }
        settingsWindow.onExportData = { [weak self] url in self?.exportData(to: url) }
        settingsWindow.onImportData = { [weak self] url in self?.importData(from: url) }
    }

    // MARK: - Data export/import
    //
    // The window only chooses a file (`NSSavePanel`/`NSOpenPanel`); all
    // serialize/validate/apply logic is Core's `DataPortability` (see
    // Sources/Core/DataPortability/DataPortability.swift), unit tested
    // there. This is just the AppKit-level wiring: write the bytes / read
    // the bytes and report the result back to the user.

    private func exportData(to url: URL) {
        do {
            let data = try DataPortability.exportJSON(settings: appSettings, progression: progressionStore)
            try data.write(to: url, options: .atomic)
            sayLine("Data exported. 🐾", style: .thought)
        } catch {
            presentDataPortabilityAlert(title: "Couldn't export data", message: "\(error)")
        }
    }

    /// Reads and imports `url`. On any validation failure, `AppSettings`
    /// and `ProgressionStore` are left completely untouched (see
    /// `DataPortability.importJSON`'s contract) -- this only reports what
    /// went wrong, it never partially applies anything.
    private func importData(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            presentDataPortabilityAlert(title: "Couldn't import data", message: "This file couldn't be read.")
            return
        }
        switch DataPortability.importJSON(data, into: appSettings, progression: progressionStore) {
        case .success:
            applyPersonalitySettings()
            pet.applyPlacementSettings()
            applyVisibilityPolicy()
            applyWellnessSettings()
            settingsWindow.characterChanged()
            if let id = appSettings.selectedCharacterID, let character = characters.character(id: id), character.id != pet.character.id {
                pet.setCharacter(character)
                cachedPortrait = nil
            }
            sayLine("Data imported. Some changes may need a relaunch to fully take effect. 🐾", style: .thought)
        case .failure(let error):
            presentDataPortabilityAlert(title: "Couldn't import data", message: error.description)
        }
    }

    private func presentDataPortabilityAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showOnboarding() {
        let window = OnboardingWindowController(settings: appSettings, characters: characters.characters, selectedID: pet.character.id)
        window.avatarProvider = { [weak self] in self?.avatarImage() }
        window.nameProvider = { [weak self] in self?.petName ?? "" }
        window.onSelectCharacter = { [weak self] id in self?.selectCharacter(id) }
        window.onFinished = { [weak self] in
            guard let self else { return }
            self.sayLine("Hi! I'm \(self.petName) 🐾")
            self.onboardingWindow = nil
        }
        onboardingWindow = window
        window.show()
    }

    // MARK: - Characters

    private func showPicker() {
        let p = picker ?? CharacterPickerController(characters: characters.characters, selectedID: pet.character.id, settings: appSettings)
        p.onSelect = { [weak self] id in self?.selectCharacter(id) }
        picker = p
        p.show()
    }

    /// Changes only the pet's look: the selection is pet data; tasks, focus,
    /// wellness, energy, stats, position and memory are untouched.
    private func selectCharacter(_ id: String) {
        guard let character = characters.character(id: id), character.id != pet.character.id else { return }
        pet.setCharacter(character)
        try? petState?.setSelectedCharacterID(id)
        appSettings.selectedCharacterID = id
        cachedPortrait = nil
        picker?.selectedID = id
        settingsWindow.characterChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.applyPersonalitySettings()
            self.home.refresh(force: true)
            self.sayLine("Hi! I'm \(self.petName) 🐾")
        }
    }

    // MARK: - Reset / recovery
    //
    // Three distinct, separately confirmed actions (confirmation itself
    // lives in SettingsWindowController, right where the button is) --
    // never one destructive catch-all, and built-in characters are never
    // touched by any of them.

    /// Preferences only (UserDefaults). Tasks, focus history, wellness,
    /// screen time and installed characters are untouched.
    private func resetSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        sayLine("Fresh settings. Some changes need a relaunch to fully take effect. 🐾", style: .thought)
    }

    /// Removes every user-installed character (never a built-in one -- they
    /// live in a different, read-only directory, see
    /// `Self.charactersDirectory()` vs `Self.installedCharactersDirectory()`).
    /// If the active character was removed, falls back exactly the way
    /// startup does.
    private func deleteInstalledCharacters() {
        let dir = Self.installedCharactersDirectory()
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: entry)
        }
        characters = CharacterRepository(directories: [Self.charactersDirectory(), Self.installedCharactersDirectory()])
        if characters.character(id: pet.character.id) == nil {
            let fallback = characters.resolveSelection(nil)
            selectCharacter(fallback.id)
        }
        sayLine("Installed characters cleared. Built-in companions are always safe. 🐾", style: .thought)
    }

    /// Preferences + all local productivity/wellness/screen-time/pet-state
    /// data + installed characters. Requires a relaunch to be fully clean
    /// (the running stores/timers stay live in memory for this session) --
    /// the confirmation dialog says so; this never pretends to be a live
    /// in-place wipe of everything currently in memory.
    private func resetEverything() {
        deleteInstalledCharacters()
        let dir = Self.applicationSupportDirectory()
        let fm = FileManager.default
        for name in ["tasks.sqlite", "reminders.sqlite", "focus_history.sqlite", "wellness.sqlite", "screen_time.sqlite", "pet_state.sqlite"] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
            try? fm.removeItem(at: dir.appendingPathComponent(name + "-wal"))
            try? fm.removeItem(at: dir.appendingPathComponent(name + "-shm"))
        }
        resetSettings()
    }

    private var petName: String { appSettings.customPetName ?? pet.character.displayName }

    private var cachedPortrait: CGImage?

    private func avatarImage() -> CGImage? {
        if let cachedPortrait { return cachedPortrait }
        cachedPortrait = pet.portrait()
        return cachedPortrait
    }

    // MARK: - Voice

    private func line(_ c: MessageCategory, force: Bool = false) -> String? {
        messages.line(c, name: petName, trait: pet.character.personality.trait, now: Date(), force: force, familiarity: cachedContext.familiarity)
    }

    private func say(_ c: MessageCategory, style: BubbleLayer.Style = .speech) {
        guard let l = line(c) else { return }
        sayLine(l, style: style)
    }

    private func sayLine(_ text: String, style: BubbleLayer.Style = .speech) {
        guard appSettings.speechBubbles, pet.isVisible else { return }
        pet.say(text, style: style)
    }

    private func petStatusText() -> String {
        guard let brain = pet.brain else { return "" }
        switch brain.behavior {
        case .sleep, .grumpyWake: return "Sleeping 💤"
        case .doze, .lateNightDrowsy: return "Getting sleepy"
        case .wakeUp, .naturalWake, .morningStretch: return "Waking up"
        case .focusCompanion: return "Focusing with you 🎯"
        case .dragged, .falling, .landing: return "Being carried"
        case .askUser, .comeTell: return "Wants to tell you something"
        case .celebrateTask, .celebrateAllDone, .celebrateFocus: return "Celebrating 🎉"
        case .sit, .settle, .sitLookAround, .watchCursor, .eveningWindDown, .ponder: return "Sitting quietly"
        case .lie, .restAlert: return "Resting"
        case .lookAround: return "Looking around"
        case .checkIn, .greetReturn: return "Coming to say hi"
        case .play, .zoomies, .spin, .excited: return "Playing ✨"
        default: return brain.isMoving ? "Exploring" : "Hanging around"
        }
    }

    // MARK: - Home panel

    private func showHome(_ section: CompanionPanelController.Section) {
        home.show(section: section, near: pet.currentFrame)
        startFocusTicker()
    }

    private func setUpHome() {
        home = CompanionPanelController()
        home.snapshotProvider = { [weak self] in self?.makeSnapshot() ?? HomeSnapshot() }
        home.avatarProvider = { [weak self] in self?.avatarImage() }
        home.liveClipProvider = { [weak self] in self?.pet.liveClip() }
        home.onAddTask = { [weak self] draft in self?.addTask(draft) }
        home.onToggleTask = { [weak self] id in self?.toggleTask(id) }
        home.onDeleteTask = { [weak self] id in
            try? self?.taskStore?.delete(id: id)
            self?.refreshReminders()
            self?.home.refresh()
        }
        home.onStartFocus = { [weak self] f, b in self?.startFocus(f, b) }
        home.onPauseFocus = { [weak self] in self?.pauseFocus() }
        home.onResumeFocus = { [weak self] in self?.resumeFocus() }
        home.onSkipFocus = { [weak self] in
            guard let self else { return }
            self.syncFocus()
            self.handleFocusEvent(self.focusTimer.skip())
            self.scheduleFocusPhaseEnd()
        }
        home.onCancelFocus = { [weak self] in self?.cancelFocus() }
        home.onLogWater = { [weak self] in self?.logWater(fromPet: false) }
        home.onTakeBreak = { [weak self] in self?.takeBreak(fromPet: false) }
        home.onAddReminder = { [weak self] title, date in
            guard let self else { return }
            try? self.reminderStore?.add(ReminderItem(title: title, fireDate: date))
            self.sayLine("I'll remind you! ⏰", style: .thought)
            self.refreshReminders()
            self.home.refresh()
        }
        home.onDeleteReminder = { [weak self] id in
            try? self?.reminderStore?.delete(id: id)
            self?.refreshReminders()
            self?.home.refresh()
        }
        home.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        home.onBringPetHome = { [weak self] in self?.pet.resetToHome() }
        home.onChooseCharacter = { [weak self] in self?.showPicker() }
    }

    private func makeSnapshot() -> HomeSnapshot {
        syncFocus()
        let now = Date()
        var s = HomeSnapshot()
        s.petName = petName
        s.petStatus = petStatusText()
        s.mood = pet.brain.mood(cachedContext).label
        s.characterName = pet.character.displayName
        s.greeting = Self.greeting()
        s.petEnergy = (pet.brain.energy * 10).rounded() / 10
        s.nextEvent = nextEventText(now: now)
        let open = (try? taskStore?.today()) ?? []
        let doneToday = (try? taskStore?.completedOnDay()) ?? []
        s.tasks = open + doneToday
        s.upcomingTasks = Array(((try? taskStore?.incomplete()) ?? []).filter { !$0.isDueToday() }.prefix(4))
        s.tasksDoneToday = doneToday.count
        s.focusSessionsToday = (try? focusHistoryStore?.todayCompletedSessionCount()) ?? 0
        s.focusMinutesToday = Int((try? focusHistoryStore?.todayTotalFocusMinutes()) ?? 0)
        s.waterToday = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
        s.waterGoal = appSettings.waterGoal
        s.breaksToday = (try? wellnessStore?.todayDoneCount(kind: .shortBreak)) ?? 0
        s.focusBreaksToday = (try? wellnessStore?.todayDoneCount(kind: .focusBreak)) ?? 0
        s.lastWater = (try? wellnessStore?.lastDone(kind: .water)) ?? nil
        s.nextWater = water.enabled ? water.nextDue : nil
        let totals = (try? screenTimeStore?.totals()) ?? nil
        s.activeMinutesToday = Int(((totals?.activeSeconds ?? 0) + pendingActiveSeconds) / 60)
        s.idleMinutesToday = Int(((totals?.idleSeconds ?? 0) + pendingIdleSeconds) / 60)
        s.continuousWorkMinutes = Int(activity.continuousActive / 60)
        s.reminders = Array(((try? reminderStore?.pending()) ?? []).prefix(6))
        s.focusPhase = focusTimer.phase
        s.daysTogether = progressionStore.daysTogether()
        s.discoveredBehaviors = petState?.discoveredBehaviors.count ?? 0
        s.totalBehaviors = pet.brain.availableBehaviors.count
        let daily = petState?.daily() ?? PetStateStore.DailyStats()
        let unsaved = unsavedStatsDelta()
        s.petClicksToday = daily.clicks + unsaved.clicks
        s.petNapsToday = daily.naps + unsaved.naps
        let points = daily.walkedPoints + unsaved.walkedPoints
        s.petMetersWalkedToday = Int(points / max(pet.currentFrame.width, 1) * 0.5) // ~half a metre per body length
        let milestones = progressionStore.milestones()
        s.milestones = milestones.filter(\.isUnlocked).map(\.title)
        s.lockedMilestones = milestones.filter { !$0.isUnlocked }.map(\.title)
        return s
    }

    /// "What's next?" from the real schedules (focus, then the reminder engine).
    private func nextEventText(now: Date) -> String {
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
        case .task: label = "“\(next.title)”"
        case .custom: label = "Reminder: \(next.title)"
        case .focus: label = "Focus"
        }
        return next.dueAt <= now ? "\(label) soon" : "\(label) in \(mins(next.dueAt))"
    }

    private static func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Good morning ☀️"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Getting late 🌙"
        }
    }

    // MARK: - Tasks

    private func addTask(_ d: TaskDraft) {
        guard let taskStore else { return }
        let task = TaskItem(title: d.title, priority: d.priority, dueDate: d.dueDate, notes: d.notes, hasDueTime: d.hasDueTime,
                            remindBeforeMinutes: d.dueDate == nil ? nil : d.remindBeforeMinutes, repeatEveryMinutes: d.repeatEveryMinutes)
        try? taskStore.add(task)
        refreshReminders()
        home.refresh()
    }

    private func toggleTask(_ id: UUID) {
        guard let taskStore, let task = try? taskStore.task(id: id) else { return }
        if task.isCompleted {
            try? taskStore.uncomplete(id: id)
        } else {
            completeTask(task)
        }
        refreshReminders()
        home.refresh()
    }

    private func completeTask(_ task: TaskItem) {
        guard let taskStore else { return }
        try? taskStore.complete(id: task.id)
        _ = try? taskStore.spawnNextOccurrenceIfRecurring(after: task)
        progressionStore.recordTaskCompleted()
        let now = Date()
        recentTaskCompletions = recentTaskCompletions.filter { now.timeIntervalSince($0) < 7200 } + [now]
        pet.flashBadge("✓")
        let remaining = ((try? taskStore.today()) ?? []).count
        if remaining == 0 {
            pet.send(.allTasksDone)
            if let l = line(.allTasks, force: true) { sayLine(l, style: .celebration) }
        } else {
            pet.send(.taskCompleted)
            // Occasionally (not every time) a streak comment.
            if recentTaskCompletions.count >= 3, Bool.random(), let l = line(.streak) {
                sayLine(l, style: .celebration)
            } else if let l = line(.task, force: true) {
                sayLine(l)
            }
        }
    }

    // MARK: - Focus (phase-end timer; the pet's badge ticks only during a session)

    private func startFocus(_ minutes: Double, _ breakMinutes: Double) {
        focusTimer.start(focusMinutes: minutes, breakMinutes: breakMinutes)
        focusStartedAt = Date()
        focusLastSync = Date()
        focusPlannedMinutes = minutes
        refreshCachedContext(now: Date(), idleSeconds: 0)
        pet.send(.focusStarted)
        if let l = line(.focusStart, force: true) { sayLine(l) }
        scheduleFocusPhaseEnd()
        startFocusTicker()
        home.refresh()
    }

    private func pauseFocus() {
        syncFocus()
        focusTimer.pause()
        focusPhaseTimer?.invalidate()
        refreshCachedContext(now: Date(), idleSeconds: 0)
        updateFocusBadge()
        home.refresh()
    }

    private func resumeFocus() {
        focusTimer.resume()
        focusLastSync = Date()
        refreshCachedContext(now: Date(), idleSeconds: 0)
        scheduleFocusPhaseEnd()
        startFocusTicker()
        home.refresh()
    }

    private func cancelFocus() {
        focusTimer.cancel()
        focusPhaseTimer?.invalidate()
        focusStartedAt = nil
        refreshCachedContext(now: Date(), idleSeconds: 0)
        pet.send(.focusStopped)
        updateFocusBadge()
        home.refresh()
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
            self.home.refresh()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        focusPhaseTimer = t
    }

    /// Ticks the focus timer on the pet (and Home's countdown) every second
    /// while a session exists; stops itself when it ends.
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
            if self.home.isVisible { self.home.updateFocusClock(self.focusTimer.phase) }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        focusTicker = t
    }

    private var focusCelebrating = false

    private func updateFocusBadge() {
        guard !focusCelebrating else { return }
        func t(_ s: TimeInterval) -> String { let v = max(0, Int(s.rounded(.up))); return String(format: "%d:%02d", v / 60, v % 60) }
        switch focusTimer.phase {
        case .focusing(let r): pet.setBadge("⏱ \(t(r))", kind: "focus")
        case .onBreak(let r): pet.setBadge("☕ \(t(r))", kind: "break")
        case .paused(_, let r): pet.setBadge("⏸ \(t(r))", kind: "paused")
        case .idle: pet.setBadge(nil)
        }
    }

    private func handleFocusEvent(_ event: FocusEvent?) {
        guard let event else { home.refresh(); return }
        switch event {
        case .focusCompleted:
            try? focusHistoryStore?.add(FocusSessionRecord(
                startedAt: focusStartedAt ?? Date().addingTimeInterval(-focusPlannedMinutes * 60),
                endedAt: Date(), plannedFocusMinutes: focusPlannedMinutes, completedFully: true))
            progressionStore.recordFocusSessionCompleted()
            refreshCachedContext(now: Date(), idleSeconds: 0)
            activity.breakTaken() // the focus break covers the screen break
            // Celebrate on the timer itself, then ask what's next.
            focusCelebrating = true
            pet.setBadge("🎉 Done!", kind: "done", emphasis: true)
            pet.send(.focusCompleted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.focusCelebrating = false
                self?.updateFocusBadge()
            }
            reminders.set("focus", DueReminder(id: "focus", kind: .focus, dueAt: Date(), title: "Focus done", urgency: .important))
            presentNextReminder()
        case .breakCompleted:
            focusStartedAt = nil
            try? wellnessStore?.add(WellnessEntry(kind: .focusBreak, action: .done))
            refreshCachedContext(now: Date(), idleSeconds: 0)
            updateFocusBadge()
            pet.say("Break's over! 🌿", style: .thought)
        }
        home.refresh()
    }

    // MARK: - Wellness policies (feed the reminder engine)

    private func setUpWellness() {
        let now = Date()
        let interval = appSettings.waterIntervalMinutes * 60
        let lastDrink = (try? wellnessStore?.lastDone(kind: .water)) ?? nil
        let saved = petState?.double(for: "water.anchor").map(Date.init(timeIntervalSince1970:))
        // Never nag right at launch: at least 10 minutes in.
        let anchor = max(saved ?? lastDrink ?? now, now.addingTimeInterval(-interval + 600))
        water = NudgeSchedule(enabled: appSettings.waterReminders, interval: interval, anchor: anchor)
    }

    private func applyWellnessSettings() {
        water.enabled = appSettings.waterReminders
        water.interval = max(60, appSettings.waterIntervalMinutes * 60)
        refreshReminders()
        home.refresh()
    }

    // MARK: - The reminder engine: schedule, present one at a time

    /// Rebuilds everything the engine knows about (cheap: indexed queries
    /// for open tasks with reminders and pending custom reminders) and
    /// sleeps until the earliest due time.
    private func refreshReminders(now: Date = Date()) {
        reminders.set("water", water.enabled ? water.nextDue.map {
            DueReminder(id: "water", kind: .water, dueAt: $0, title: "Water", urgency: .gentle)
        } : nil)
        if appSettings.breakNudges {
            let remaining = max(0, appSettings.breakIntervalMinutes * 60 - activity.continuousActive)
            var due = now.addingTimeInterval(remaining)
            if let nb = screenBreakNotBefore, nb > due { due = nb }
            reminders.set("screenBreak", DueReminder(id: "screenBreak", kind: .screenBreak, dueAt: due, title: "Screen break", urgency: .gentle))
        } else {
            reminders.set("screenBreak", nil)
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

    private func presentNextReminder() {
        let now = Date()
        guard !pet.isAsking, pet.isVisible, pet.brain.behavior != .dragged else {
            // Busy (another question, hidden, being carried): look again shortly.
            retryReminders(in: 20)
            return
        }
        var c = ReminderQueue.Conditions()
        c.quietHours = quietHours.contains(now)
        c.focusActive = cachedContext.focusActive
        c.userAway = !activity.isUserActive(secondsSinceLastInput: IdleTimeReader.secondsSinceLastInput())
        c.allowUrgentInQuietHours = appSettings.urgentBreaksQuiet
        guard let r = reminders.next(now: now, conditions: c) else {
            // Something due but not allowed right now (away / quiet / focus):
            // check again in a minute rather than spinning.
            if let wake = reminders.nextWakeDate, wake <= now { retryReminders(in: 60) } else { scheduleReminderWake(now: now) }
            return
        }
        present(r)
    }

    private func retryReminders(in seconds: TimeInterval) {
        reminderTimer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.presentNextReminder() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        reminderTimer = t
    }

    /// Called when the current reminder has been answered.
    private func reminderFinished() {
        reminders.finishPresenting()
        refreshReminders()
        home.refresh()
        // A short breath before anything else that's queued.
        retryReminders(in: 3)
    }

    /// The pet brings one reminder to the user. Important ones: it walks a
    /// few steps toward them first.
    private func present(_ r: DueReminder) {
        switch r.kind {
        case .water: presentWater()
        case .screenBreak: presentScreenBreak()
        case .task: presentTask(r)
        case .custom: presentCustom(r)
        case .focus: presentFocusDone()
        }
    }

    /// Two-step snooze: [Snooze] -> [10 min] [20 min] [30 min].
    private func snoozeChoices(for kind: ReminderKind, apply: @escaping (TimeInterval?) -> Void) {
        let options = kind.snoozeOptions.map { opt -> (title: String, primary: Bool, handler: () -> Void) in
            (opt.label, false, { apply(opt.seconds) })
        }
        pet.replaceQuestion("Remind you in…", actions: options, timeout: 25, onTimeout: { apply(600) })
    }

    private func presentWater() {
        water.beginAsking()
        pet.ask(line(.water, force: true) ?? "Water break? 💧", actions: [
            ("I drank 💧", true, { [weak self] in
                self?.logWater(fromPet: true)
                self?.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: .water) { seconds in
                    guard let self else { return }
                    self.water.snooze(now: Date(), seconds: seconds ?? 600)
                    try? self.wellnessStore?.add(WellnessEntry(kind: .water, action: .snoozed))
                    if let l = self.line(.snoozed, force: true) { self.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Skip", false, { [weak self] in
                guard let self else { return }
                self.water.skip(now: Date())
                try? self.wellnessStore?.add(WellnessEntry(kind: .water, action: .skipped))
                try? self.petState?.set(String(Date().timeIntervalSince1970), for: "water.anchor")
                if let l = self.line(.waterSkipped, force: true) { self.sayLine(l, style: .thought) }
                self.reminderFinished()
            }),
        ], timeout: 45, approach: true, onTimeout: { [weak self] in
            self?.water.timedOut(now: Date())
            self?.reminderFinished()
        })
    }

    private func presentScreenBreak() {
        pet.ask(line(.screenTime, force: true) ?? "Your eyes need a break 👀", actions: [
            ("Take a break", true, { [weak self] in
                self?.takeBreak(fromPet: true)
                self?.reminderFinished()
            }),
            ("Snooze", false, { [weak self] in
                self?.snoozeChoices(for: .screenBreak) { seconds in
                    guard let self else { return }
                    self.screenBreakNotBefore = Date().addingTimeInterval(seconds ?? 600)
                    try? self.wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .snoozed))
                    if let l = self.line(.snoozed, force: true) { self.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Skip", false, { [weak self] in
                guard let self else { return }
                // No nagging: not again for at least 20 min / a full interval.
                self.screenBreakNotBefore = Date().addingTimeInterval(max(20 * 60, self.appSettings.breakIntervalMinutes * 60 / 2))
                try? self.wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .skipped))
                if let l = self.line(.breakSkipped, force: true) { self.sayLine(l, style: .thought) }
                self.reminderFinished()
            }),
        ], timeout: 45, approach: true, onTimeout: { [weak self] in
            self?.screenBreakNotBefore = Date().addingTimeInterval(15 * 60)
            self?.reminderFinished()
        })
    }

    private func presentTask(_ r: DueReminder) {
        guard let id = r.taskID, let task = try? taskStore?.task(id: id) else { reminderFinished(); return }
        let intro: String
        switch r.urgency {
        case .gentle: intro = line(.taskTomorrow, force: true) ?? "Heads-up:"
        case .noticeable: intro = line(.taskSoon, force: true) ?? "Hey! You have something coming up."
        case .important: intro = line(.taskNow, force: true) ?? "This is due now!"
        }
        let when = task.deadline().map { Self.dueText($0, hasTime: task.hasDueTime) } ?? ""
        let text = "\(intro)\n“\(task.title)”" + (when.isEmpty ? "" : " · \(when)")
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
                    if let l = self.line(.snoozed, force: true) { self.sayLine(l, style: .thought) }
                    self.reminderFinished()
                }
            }),
            ("Dismiss", false, { [weak self] in
                update { $0.reminderHandledAt = max(Date(), r.dueAt); $0.reminderSnoozedUntil = nil }
                self?.reminderFinished()
            }),
        ], timeout: r.urgency == .important ? 90 : 60, approach: true,
           style: r.urgency == .important ? .speech : .thought, onTimeout: { [weak self] in
            update { $0.reminderSnoozedUntil = Date().addingTimeInterval(15 * 60) }
            self?.reminderFinished()
        })
    }

    private static func dueText(_ d: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = hasTime ? "h:mm a" : ""
        let time = hasTime ? " \(f.string(from: d))" : ""
        if cal.isDateInToday(d) { return hasTime ? "today\(time)" : "today" }
        if cal.isDateInTomorrow(d) { return "tomorrow\(time)" }
        let day = DateFormatter()
        day.dateFormat = "EEE d MMM"
        return "\(day.string(from: d))\(time)"
    }

    private func presentCustom(_ r: DueReminder) {
        guard let reminderStore, let idString = r.id.split(separator: ":").last, let id = UUID(uuidString: String(idString)),
              let item = (try? reminderStore.pending())?.first(where: { $0.id == id }) else { reminderFinished(); return }
        notificationScheduler?.postNow(identifier: item.id.uuidString, title: petName, body: item.title)
        pet.send(.reminderDue)
        pet.ask("⏰ \(item.title)", actions: [
            ("Done ✓", true, { [weak self] in
                try? reminderStore.dismiss(id: id)
                _ = try? reminderStore.spawnNextOccurrenceIfRecurring(after: item)
                self?.sayLine("Nice! ✓", style: .thought)
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

    private func presentFocusDone() {
        pet.ask(line(.focusDone, force: true) ?? "Nice work! ✨", actions: [
            ("Start another", true, { [weak self] in
                guard let self else { return }
                self.focusTimer.cancel() // skip the break, straight into another session
                self.startFocus(self.focusPlannedMinutes, max(3, self.focusPlannedMinutes / 5))
                self.reminderFinished()
            }),
            ("Take a break", false, { [weak self] in
                self?.pet.send(.breakStarted)
                self?.sayLine("Enjoy the break! 🌿", style: .thought)
                self?.reminderFinished()
            }),
        ], timeout: 40, style: .celebration, onTimeout: { [weak self] in self?.reminderFinished() })
    }

    /// Records a drink (from the pet's question, the Home panel or the menu).
    private func logWater(fromPet: Bool) {
        let now = Date()
        try? wellnessStore?.add(WellnessEntry(kind: .water, action: .done))
        water.confirm(now: now)
        try? petState?.set(String(now.timeIntervalSince1970), for: "water.anchor")
        pet.send(.waterLogged)
        pet.flashBadge("💧")
        let count = (try? wellnessStore?.todayDoneCount(kind: .water)) ?? 0
        sayLine(count >= appSettings.waterGoal ? "Water goal reached! 💧🎉" : (line(.waterThanks, force: true) ?? "Good job! 💧"),
                style: count >= appSettings.waterGoal ? .celebration : .speech)
        if !fromPet { refreshReminders() }
        home.refresh()
    }

    private func takeBreak(fromPet: Bool) {
        try? wellnessStore?.add(WellnessEntry(kind: .shortBreak, action: .done))
        activity.breakTaken()
        screenBreakNotBefore = nil
        pet.send(.breakStarted)
        if let l = line(.breakThanks, force: true) { sayLine(l) }
        if !fromPet { refreshReminders() }
        home.refresh()
    }

    // MARK: - Housekeeping (every 30 s: screen time, context, persistence)

    private func startHousekeeping() {
        lastHousekeeping = Date()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.housekeepingTick() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        housekeeping = t
    }

    private func refreshCachedContext(now: Date, idleSeconds: Double) {
        var c = PetContext()
        c.hour = Calendar.current.component(.hour, from: now)
        c.userIdleSeconds = idleSeconds
        if case .focusing = focusTimer.phase { c.focusActive = true }
        c.quietHours = quietHours.contains(now)
        c.activityMultiplier = appSettings.activityLevel.movementWeightMultiplier
        c.reducedMotion = appSettings.reducedMotion
        c.mode = appSettings.companionMode
        if let battery = BatteryReader.read(), let level = battery.level {
            c.batteryLow = level < 0.15 && !battery.isCharging
        }
        c.continuousActiveMinutes = activity.continuousActive / 60
        // Gradually reaches full familiarity (1.0) over the companion's
        // first ~2 weeks, with a small (farming-resistant) bonus for
        // actually being used across multiple days -- never a number
        // shown to the user, only a gentle scale on a few behaviors.
        c.familiarity = ProgressionStore.familiarity(
            daysTogether: progressionStore.daysTogether(referenceDate: now),
            activeDayCount: progressionStore.activeDayCount
        )
        // Stage 10.4: the one environment object shipped so far is a bed
        // at the pet's own home corner -- no placement UI yet (Stage 10.8
        // is explicitly deferred), so this is the simplest thing that
        // makes the feature live rather than dead architecture.
        if appSettings.bedEnabled {
            c.bedX = pet.brain.homeX
            c.bedY = pet.brain.homeY
        }
        cachedContext = c
    }

    private func housekeepingTick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastHousekeeping), 60) // after system sleep, don't count the gap
        lastHousekeeping = now
        housekeepingCount += 1

        let idle = IdleTimeReader.secondsSinceLastInput()
        refreshCachedContext(now: now, idleSeconds: idle)
        let sample = activity.record(dt: dt, secondsSinceLastInput: idle)
        pendingActiveSeconds += sample.active
        pendingIdleSeconds += sample.idle
        if case .focusing = focusTimer.phase { pendingFocusSeconds += sample.active }

        checkTimeOfDay(now: now)
        checkPresence(sample: sample, idle: idle, now: now)
        maybeSpontaneousMoment(active: activity.isUserActive(secondsSinceLastInput: idle), now: now)

        // The screen-break due time moves with real activity.
        if housekeepingCount % 2 == 0 { refreshReminders(now: now) }
        if housekeepingCount % 2 == 0 { flushScreenTime() }
        if housekeepingCount % 4 == 0 { persistPetState() }
        logDiagnostics()
        if home.isVisible { home.refresh() }
    }

    private func checkTimeOfDay(now: Date) {
        let hour = Calendar.current.component(.hour, from: now)
        let bucket: String
        switch hour {
        case 5..<12: bucket = "morning"
        case 12..<17: bucket = "afternoon"
        case 17..<22: bucket = "evening"
        default: bucket = "night"
        }
        guard bucket != lastGreetingBucket else { return }
        let isFirst = lastGreetingBucket == nil
        lastGreetingBucket = bucket
        if !isFirst && bucket == "morning" && onboardingProgress.hasCompleted { pet.send(.morningGreeting) }
    }

    private var wasAway = false

    /// User away / back.
    private func checkPresence(sample: ActivityTracker.Sample, idle: Double, now: Date) {
        if idle >= 300 {
            wasAway = true
        } else if wasAway && idle < 60 {
            wasAway = false
            pet.send(.userReturned(awaySeconds: 300))
            say(.returned)
            refreshReminders(now: now)
        }
    }

    /// Most of the time the pet just quietly exists. Rarely, when the user
    /// is around and nothing else is going on: a check-in visit after a long
    /// stretch without interaction, a late-night note, or an idle thought.
    private func maybeSpontaneousMoment(active: Bool, now: Date) {
        guard active, appSettings.speechBubbles, !pet.isAsking, !cachedContext.focusActive, !cachedContext.quietHours,
              !pet.brain.isAsleep, !pet.brain.isMoving else { return }
        let chatty = pet.character.personality.chattiness * appSettings.talkativeness.multiplier
        if now.timeIntervalSince(lastInteractionAt) > 45 * 60, Double.random(in: 0..<1) < 0.1 * chatty, let l = line(.checkIn) {
            pet.send(.checkIn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.sayLine(l, style: .speech) }
            lastInteractionAt = now // don't check in again right away
            return
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 23 || hour < 4, Double.random(in: 0..<1) < 0.05, let l = line(.lateNight) {
            sayLine(l, style: .thought)
            return
        }
        guard Double.random(in: 0..<1) < 0.08 * chatty else { return }
        let category: MessageCategory = pet.brain.boredom > 0.6 ? .bored : (pet.brain.mood(cachedContext) == .playful ? .play : .idle)
        if let l = line(category) { sayLine(l, style: .thought) }
    }

    private func flushScreenTime() {
        guard let screenTimeStore else { return }
        if pendingActiveSeconds > 0 { try? screenTimeStore.addActiveSeconds(pendingActiveSeconds) }
        if pendingIdleSeconds > 0 { try? screenTimeStore.addIdleSeconds(pendingIdleSeconds) }
        if pendingFocusSeconds > 0 { try? screenTimeStore.addFocusSeconds(pendingFocusSeconds) }
        pendingActiveSeconds = 0
        pendingIdleSeconds = 0
        pendingFocusSeconds = 0
    }

    // MARK: - Persistence

    private func unsavedStatsDelta() -> PetStateStore.DailyStats {
        let now = pet.brain.stats
        var d = PetStateStore.DailyStats()
        d.clicks = now.clicks - lastPersistedStats.clicks
        d.barks = now.barks - lastPersistedStats.barks
        d.naps = now.naps - lastPersistedStats.naps
        d.sleepSeconds = now.sleepSeconds - lastPersistedStats.sleepSeconds
        d.walkedPoints = now.walkedPoints - lastPersistedStats.walkedPoints
        d.celebrations = now.celebrations - lastPersistedStats.celebrations
        return d
    }

    private func persistPetState() {
        guard let petState, let brain = pet.brain else { return }
        try? petState.addDaily(unsavedStatsDelta())
        lastPersistedStats = brain.stats
        try? petState.savePosition(pet.savedPosition())
        try? petState.saveEnergy(brain.energy)
    }

    // MARK: - Diagnostics

    private func logDiagnostics() {
        let sample = sampler.sample(currentState: pet.currentStateID, currentAnimationFPS: pet.currentAnimationFPS)
        diagnosticsLogger.log(sample)
        if let overlay = diagnosticsOverlay, overlay.isVisible { overlay.update(with: sample) }
    }

    private func toggleDiagnosticsOverlay() {
        let overlay = diagnosticsOverlay ?? DiagnosticsOverlayWindow()
        diagnosticsOverlay = overlay
        if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() }
    }
}
