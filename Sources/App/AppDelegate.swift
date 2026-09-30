import AppKit
import Core
import PlatformMac

/// Wiring only. The pet (CharacterWindowController + PetBrain) does the
/// living; this connects it to the menu, settings, shortcuts and storage.
/// Nothing polls faster than a 30-second housekeeping tick.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: CharacterWindowController!
    private var characters = CharacterRepository(characters: [])
    private var picker: CharacterPickerController?
    private var menuBar: MenuBarController!
    private var screenTracker: ScreenTracker!
    private var sleepWakeMonitor: SleepWakeMonitor!
    private var fullscreenMonitor: FullscreenMonitor!
    private let hotKeys = GlobalHotKeys()
    private var dashboard: DashboardController!
    var settingsWindow: SettingsWindowController!
    private let aboutWindow = AboutWindowController()
    private var onboardingWindow: OnboardingWindowController?

    var petState: PetStateStore?
    let appSettings = AppSettings()
    lazy var onboardingProgress = OnboardingProgress(settings: appSettings)
    let progressionStore = ProgressionStore()
    private let messages = PetMessageBook(rng: SeededRandom(seed: UInt64(Date().timeIntervalSince1970)))
    lazy var productivity = ProductivityController(app: self)
    private var activity: ActivityTracker { productivity.activity }

    private var quietHours: QuietHours {
        QuietHours(startHour: appSettings.quietHoursStart, endHour: appSettings.quietHoursEnd)
    }

    private var housekeeping: Timer?
    private var housekeepingCount = 0
    private var lastHousekeeping = Date()
    var cachedContext = PetContext()
    private var lastGreetingBucket: String?
    private var lastPersistedStats = PetStats()
    private var lastInteractionAt = Date()
    private var wasAway = false
    private var cachedPortrait: CGImage?

    // MARK: - Launch / quit

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, not in Cmd+Tab
        setUpStores()

        characters = CharacterRepository(directories: [Self.charactersDirectory()])
        for failure in characters.failures {
            NSLog("[DesktopCompanion] Skipping character '%@': %@", failure.id, "\(failure.error)")
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

        setUpDashboard()
        setUpSettingsWindow()
        productivity.start()
        setUpMenuBar()
        setUpShortcuts()
        setUpScreenTracking()
        setUpSleepWake()
        setUpFullscreenMonitoring()
        startHousekeeping()

        if !onboardingProgress.hasCompleted {
            showOnboarding()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.say(.welcome) }
        }

        // QA hook: open a surface at launch so it can be screenshotted.
        if let qa = ProcessInfo.processInfo.environment["DC_QA_OPEN"] {
            for (i, step) in qa.split(separator: ",").enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.5 * Double(i)) { [weak self] in self?.openForQA(String(step)) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeeping?.invalidate()
        hotKeys.unregister()
        productivity.flushScreenTime()
        persistPetState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func openForQA(_ what: String) {
        switch what {
        case "picker": showPicker()
        case "settings": settingsWindow.show()
        case "about": aboutWindow.show()
        case "onboarding": showOnboarding()
        case "dashboard": dashboard.show()
        case "follow": pet.perform(.follow(duration: nil))
        case "sleep": pet.perform(.sleep)
        case "today": productivity.show(.today)
        case "tasks": productivity.show(.tasks)
        case "focus": productivity.show(.focus)
        case "wellness": productivity.show(.wellness)
        case "stats": productivity.show(.stats)
        case "pomodoro": productivity.startPomodoro(PomodoroPlan(workMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 2, sessionsBeforeLongBreak: 2))
        case "remind": productivity.quickAdd("Submit the quarterly report in 1 min !high")
        case "complete": productivity.qaCompleteFirstTask()
        case "water": productivity.logWater(fromPet: false)
        case "quicktask": productivity.quickAdd("QA sample task tomorrow 5pm !high remind 30m before")
        case "comehere": pet.perform(.comeHere)
        case "play": pet.perform(.play)
        case "explore": pet.perform(.explore)
        case "hide": pet.perform(.hideAndSeek)
        case "stay": pet.perform(.stay(duration: nil))
        case "watch": pet.perform(.watch)
        case "nap": pet.perform(.nap)
        case "pat": pet.floatSymbol(); say(.pet, style: .speech)
        case "menu": buildPetMenu(includeAppItems: true).popUp(positioning: nil, at: NSPoint(x: 300, y: 700), in: nil)
        case "click-walk": // walk, then click the pet 3 s later (regression check for sliding while sitting)
            pet.perform(.explore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in _ = self?.pet.send(.click) }
        case "cycle": // switches through every character 60 times (performance checks)
            let ids = characters.characters.map(\.id)
            for i in 0..<60 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) { [weak self] in self?.selectCharacter(ids[i % ids.count]) } }
        case "login-on": LoginItemManager.setEnabled(true); NSLog("[QA] login item enabled=%d", LoginItemManager.isEnabled() ? 1 : 0)
        case "login-off": LoginItemManager.setEnabled(false); NSLog("[QA] login item enabled=%d", LoginItemManager.isEnabled() ? 1 : 0)
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

    static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCompanion", isDirectory: true)
    }

    // MARK: - Setup

    private func setUpStores() {
        do {
            petState = try PetStateStore(fileURL: Self.applicationSupportDirectory().appendingPathComponent("pet_state.sqlite"))
            try? petState?.prune()
        } catch {
            NSLog("[DesktopCompanion] Couldn't open pet state (%@) -- it won't persist this session.", "\(error)")
        }
    }

    private func wirePet() {
        pet.onClick = { [weak self] outcome in
            guard let self else { return }
            self.noteInteraction()
            if outcome.woke {
                self.say(.wake)
            } else if self.pet.brain.isAnnoyed {
                self.say(.annoyed, style: .speech)
            } else if outcome.barked && self.pet.character.hasExact("stand_bark") {
                self.sayLine(["Woof! 🐾", "Bark!", "Ruff ruff!", "Arf!"].randomElement()!, style: .speech)
            } else {
                self.say(.click, style: Bool.random() ? .speech : .thought)
            }
        }
        pet.onDropped = { [weak self] in
            guard let self else { return }
            self.noteInteraction()
            try? self.petState?.savePosition(self.pet.savedPosition())
            self.say(.landed, style: .thought)
        }
        pet.onPickedUp = { [weak self] in self?.say(.grabbed, style: .speech) }
        pet.onCursorApproached = { [weak self] in self?.say(.notice, style: .thought) }
        pet.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.noteInteraction()
            self.pet.floatSymbol()
            self.say(.pet, style: .speech)
        }
        pet.onContextMenu = { [weak self] _ in
            guard let self else { return }
            self.noteInteraction()
            self.buildPetMenu(includeAppItems: false).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        pet.onBehaviorChange = { [weak self] behavior in
            guard let self else { return }
            self.petState?.recordDiscovered(behavior.rawValue)
            if behavior == .sleep { self.say(.sleep, style: .thought) }
            if behavior == .hideWait { self.say(.hide, style: .thought) }
        }
        pet.brain.onActivityStarted = { [weak self] activity in
            self?.petState?.recordActivityStarted(activity)
            self?.noteInteraction()
        }
        pet.onActivityChanged = { [weak self] activity in self?.activityChanged(activity) }
    }

    private var napsSeen = 0

    private func activityChanged(_ activity: Activity?) {
        if activity == nil, pet.brain.napsCompleted > napsSeen { say(.napDone, style: .speech) }
        napsSeen = pet.brain.napsCompleted
        switch activity {
        case .followCursor: pet.setBadge("👀 Following", kind: "activity"); say(.follow, style: .speech)
        case .play: pet.setBadge("🎾 Playing", kind: "activity"); say(.play, style: .speech)
        case .stay: pet.setBadge("⏸ Staying", kind: "activity"); say(.stay, style: .speech)
        case .hideAndSeek: pet.setBadge(nil)
        case .watch: pet.setBadge("👀 Watching", kind: "activity"); say(.watch, style: .speech)
        case .nap: pet.setBadge("💤 Napping", kind: "activity"); say(.nap, style: .thought)
        case .comeHere: pet.setBadge(nil); say(.comeHere, style: .speech)
        case .explore: pet.setBadge(nil); say(.explore, style: .thought)
        case nil: pet.setBadge(nil)
        }
        if dashboard.isVisible { dashboard.refresh(force: true) }
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
        refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        let model = PetMenuModel(petName: petName, petStatus: petStatusText(), isAsleep: pet.brain.isAsleep,
                                 petHidden: pet.isHiddenByUser, includeAppItems: includeAppItems,
                                 mode: appSettings.companionMode, currentActivity: pet.brain.currentActivity,
                                 tricks: pet.brain.availableTricks, focusPhase: productivity.focusTimer.phase,
                                 availability: { [weak self] a in
                                     guard let self else { return .unsupported }
                                     return self.pet.brain.availability(of: a, context: self.cachedContext)
                                 })
        var a = PetMenuActions()
        a.startActivity = { [weak self] activity, duration in self?.start(activity, duration: duration) }
        a.stopActivity = { [weak self] in self?.stopActivity() }
        a.openDashboard = { [weak self] in self?.dashboard.show() }
        a.openProductivity = { [weak self] section in self?.productivity.show(section) }
        a.newTask = { [weak self] in self?.productivity.promptQuickTask() }
        a.toggleFocus = { [weak self] in self?.productivity.toggleFocus() }
        a.logWater = { [weak self] in self?.productivity.logWater(fromPet: false) }
        a.takeBreak = { [weak self] in self?.productivity.takeBreak(fromPet: false) }
        a.doTrick = { [weak self] trick in
            guard let self else { return }
            if self.pet.perform(.trick(trick)) == .handled { self.say(.trick, style: .speech) }
        }
        a.chooseCharacter = { [weak self] in self?.showPicker() }
        a.toggleSleep = { [weak self] in self?.toggleSleep() }
        a.toggleHidden = { [weak self] in self?.pet.toggleVisibility() }
        a.setMode = { [weak self] mode in
            guard let self else { return }
            self.appSettings.companionMode = mode
            self.refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        }
        a.openSettings = { [weak self] in self?.settingsWindow.show() }
        a.openAbout = { [weak self] in self?.aboutWindow.show() }
        a.quit = { NSApp.terminate(nil) }
        return PetMenu.build(model, a)
    }

    // MARK: - Commands (menu and shortcuts share these)

    private func start(_ activity: Activity, duration: Double?) {
        if pet.isHiddenByUser { pet.toggleVisibility() }
        let command: PetCommand
        switch activity {
        case .followCursor: command = .follow(duration: duration)
        case .stay: command = .stay(duration: duration)
        case .comeHere: command = .comeHere
        case .play: command = .play
        case .explore: command = .explore
        case .hideAndSeek: command = .hideAndSeek
        case .watch: command = .watch
        case .nap: command = .nap
        }
        refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        pet.perform(command)
    }

    private func stopActivity() {
        guard pet.brain.currentActivity != nil else { return }
        pet.perform(.stop)
        say(.stop, style: .thought)
    }

    private func toggleFollow() {
        if pet.brain.currentActivity == .followCursor { stopActivity() } else { start(.followCursor, duration: nil) }
    }

    private func toggleSleep() {
        if pet.brain.isAsleep { pet.perform(.wake); say(.wake) } else { pet.perform(.sleep) }
    }

    private func setUpShortcuts() {
        guard appSettings.globalShortcuts else { hotKeys.unregister(); return }
        hotKeys.register([
            .init(keyCode: 3) { [weak self] in self?.toggleFollow() },              // F
            .init(keyCode: 4) { [weak self] in self?.start(.comeHere, duration: nil) }, // H
            .init(keyCode: 1) { [weak self] in self?.stopActivity() },              // S
            .init(keyCode: 2) { [weak self] in self?.dashboard.show() },            // D
            .init(keyCode: 35) { [weak self] in self?.pet.toggleVisibility() },     // P
            .init(keyCode: 17) { [weak self] in self?.productivity.promptQuickTask() }, // T
            .init(keyCode: 14) { [weak self] in self?.productivity.toggleFocus() },     // E
            .init(keyCode: 13) { [weak self] in self?.productivity.logWater(fromPet: false) }, // W
        ])
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

    private func setUpDashboard() {
        dashboard = DashboardController()
        dashboard.snapshotProvider = { [weak self] in self?.makeSnapshot() ?? DashboardSnapshot() }
        dashboard.avatarProvider = { [weak self] in self?.avatarImage() }
        dashboard.onFollowToggle = { [weak self] in self?.toggleFollow() }
        dashboard.onChooseCharacter = { [weak self] in self?.showPicker() }
        dashboard.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        dashboard.onOpenProductivity = { [weak self] in self?.productivity.show() }
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
        settingsWindow.onEnvironmentSettingsChanged = { [weak self] in
            self?.refreshCachedContext(now: Date(), idleSeconds: IdleTimeReader.secondsSinceLastInput())
        }
        settingsWindow.onProductivityChanged = { [weak self] in self?.productivity.settingsChanged() }
        settingsWindow.onShortcutsChanged = { [weak self] in self?.setUpShortcuts() }
        settingsWindow.onResetPosition = { [weak self] in self?.pet.resetToHome() }
        settingsWindow.characterNameProvider = { [weak self] in self?.pet.character.displayName ?? "" }
        settingsWindow.onChooseCharacter = { [weak self] in self?.showPicker() }
        settingsWindow.onReplayOnboarding = { [weak self] in
            guard let self else { return }
            self.onboardingProgress.reset()
            self.showOnboarding()
        }
        settingsWindow.onPetRenamed = { [weak self] in self?.dashboard.refresh(force: true) }
        settingsWindow.onResetSettings = { [weak self] in self?.resetSettings() }
        settingsWindow.onResetEverything = { [weak self] in self?.resetEverything() }
        settingsWindow.onExportData = { [weak self] url in self?.exportData(to: url) }
        settingsWindow.onImportData = { [weak self] url in self?.importData(from: url) }
    }

    // MARK: - Data export/import

    private func exportData(to url: URL) {
        do {
            let data = try DataPortability.exportJSON(settings: appSettings, progression: progressionStore)
            try data.write(to: url, options: .atomic)
            sayLine("Data exported. 🐾", style: .thought)
        } catch {
            presentAlert(title: "Couldn't export data", message: "\(error)")
        }
    }

    /// On any validation failure settings and progression are left untouched
    /// (see `DataPortability.importJSON`).
    private func importData(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            presentAlert(title: "Couldn't import data", message: "This file couldn't be read.")
            return
        }
        switch DataPortability.importJSON(data, into: appSettings, progression: progressionStore) {
        case .success:
            applyPersonalitySettings()
            pet.applyPlacementSettings()
            applyVisibilityPolicy()
            setUpShortcuts()
            settingsWindow.characterChanged()
            if let id = appSettings.selectedCharacterID, let character = characters.character(id: id), character.id != pet.character.id {
                pet.setCharacter(character)
                cachedPortrait = nil
            }
            sayLine("Data imported. Some changes may need a relaunch. 🐾", style: .thought)
        case .failure(let error):
            presentAlert(title: "Couldn't import data", message: error.description)
        }
    }

    private func presentAlert(title: String, message: String) {
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

    /// Changes only the pet's look: energy, stats, position and memory are untouched.
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
            self.dashboard.refresh(force: true)
            self.sayLine("Hi! I'm \(self.petName) 🐾")
        }
    }

    // MARK: - Reset

    /// Preferences only (UserDefaults); the companion's memory is kept.
    private func resetSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        sayLine("Fresh settings. Some changes need a relaunch. 🐾", style: .thought)
    }

    /// Settings + the companion's stored state. A relaunch makes it fully clean
    /// (the running store stays live in memory for this session).
    private func resetEverything() {
        let dir = Self.applicationSupportDirectory()
        let fm = FileManager.default
        for name in ["pet_state", "tasks", "reminders", "focus_history", "wellness", "screen_time"].flatMap({ ["\($0).sqlite", "\($0).sqlite-wal", "\($0).sqlite-shm"] }) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
        resetSettings()
    }

    var petName: String { appSettings.customPetName ?? pet.character.displayName }

    private func avatarImage() -> CGImage? {
        if let cachedPortrait { return cachedPortrait }
        cachedPortrait = pet.portrait()
        return cachedPortrait
    }

    // MARK: - Voice

    func dashboardNeedsRefresh() { if dashboard.isVisible { dashboard.refresh(force: true) } }

    func line(_ c: MessageCategory, force: Bool = false) -> String? {
        messages.line(c, name: petName, trait: pet.character.personality.trait, now: Date(), force: force, familiarity: cachedContext.familiarity)
    }

    private func say(_ c: MessageCategory, style: BubbleLayer.Style = .speech) {
        guard let l = line(c) else { return }
        sayLine(l, style: style)
    }

    func sayLine(_ text: String, style: BubbleLayer.Style = .speech, duration: TimeInterval = 3.5) {
        guard appSettings.speechBubbles, pet.isVisible else { return }
        pet.say(text, style: style, duration: duration)
    }

    func petStatusText() -> String {
        guard let brain = pet.brain else { return "" }
        if let a = brain.currentActivity {
            return brain.isHidden ? "Hiding 🤫" : a.displayName
        }
        switch brain.behavior {
        case .sleep, .grumpyWake: return "Sleeping 💤"
        case .doze, .lateNightDrowsy: return "Getting sleepy"
        case .wakeUp, .naturalWake, .morningStretch: return "Waking up"
        case .dragged, .falling, .landing: return "Being carried"
        case .askUser: return "Watching you"
        case .sit, .settle, .sitLookAround, .watchCursor, .eveningWindDown, .ponder: return "Sitting quietly"
        case .lie, .restAlert: return "Resting"
        case .lookAround: return "Looking around"
        case .checkIn, .greetReturn: return "Coming to say hi"
        case .play, .zoomies, .spin, .excited: return "Playing ✨"
        default: return brain.isMoving ? "Exploring" : "Hanging around"
        }
    }

    // MARK: - Dashboard

    private func makeSnapshot() -> DashboardSnapshot {
        var s = DashboardSnapshot()
        let brain = pet.brain!
        s.petName = petName
        s.characterName = pet.character.displayName
        s.mood = brain.mood(cachedContext).label
        s.activity = petStatusText()
        s.mode = appSettings.companionMode.displayName
        s.familiarity = cachedContext.familiarity
        s.familiarityLabel = ProgressionStore.familiarityLabel(cachedContext.familiarity)
        s.daysTogether = progressionStore.daysTogether()
        let today = petState?.daily() ?? PetStateStore.DailyStats()
        let live = unsavedStatsDelta()
        s.petsToday = today.clicks + live.clicks
        s.napsToday = today.naps + live.naps
        let screenWidth = max(Double(NSScreen.main?.frame.width ?? 1440), 1)
        s.screensCrossedToday = Int(((today.walkedPoints + live.walkedPoints) / screenWidth).rounded())
        s.favoriteActivity = petState?.favoriteActivity()?.displayName ?? "None yet"
        let mine = Set(brain.availableBehaviors.map(\.rawValue))
        s.behaviorsTotal = mine.count
        s.behaviorsSeen = (petState?.discoveredBehaviors ?? []).intersection(mine).count
        let milestones = progressionStore.milestones()
        s.milestones = milestones.filter(\.isUnlocked).map(\.title)
        s.lockedMilestones = milestones.filter { !$0.isUnlocked }.map(\.title)
        s.isFollowing = brain.currentActivity == .followCursor
        let lines = productivity.summaryLines()
        s.tasksLine = lines.tasks
        s.focusLine = lines.focus
        s.waterLine = lines.water
        s.streakDays = productivity.streak()
        return s
    }

    // MARK: - Housekeeping (every 30 s: context, presence, persistence)

    private func startHousekeeping() {
        lastHousekeeping = Date()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.housekeepingTick() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        housekeeping = t
    }

    func refreshCachedContext(now: Date, idleSeconds: Double) {
        var c = PetContext()
        c.hour = Calendar.current.component(.hour, from: now)
        c.userIdleSeconds = idleSeconds
        c.quietHours = quietHours.contains(now)
        c.focusActive = productivity.isFocusing
        c.activityMultiplier = appSettings.activityLevel.movementWeightMultiplier
        c.reducedMotion = appSettings.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        c.mode = appSettings.companionMode
        if let battery = BatteryReader.read(), let level = battery.level {
            c.batteryLow = level < 0.15 && !battery.isCharging
        }
        c.continuousActiveMinutes = activity.continuousActive / 60
        c.familiarity = ProgressionStore.familiarity(
            daysTogether: progressionStore.daysTogether(referenceDate: now),
            activeDayCount: progressionStore.activeDayCount
        )
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
        productivity.housekeeping(dt: dt, sample: sample, idle: idle, now: now)

        checkTimeOfDay(now: now)
        commentOnFrontApp()
        checkPresence(idle: idle)
        maybeSpontaneousMoment(active: activity.isUserActive(secondsSinceLastInput: idle), now: now)
        if housekeepingCount % 2 == 0 { productivity.flushScreenTime() }
        if housekeepingCount % 4 == 0 { persistPetState() }
        if dashboard.isVisible { dashboard.refresh(force: false) }
    }

    private var lastCommentedCategory: AppCategory?

    /// Optional: a comment when the user switches to a different kind of app (frontmost app's name only, never stored).
    private func commentOnFrontApp() {
        guard appSettings.appAwareChatter, appSettings.speechBubbles, !productivity.isFocusing, !cachedContext.quietHours,
              !pet.brain.isAsleep, pet.brain.currentActivity == nil,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              let category = AppCategory.category(forBundleID: id), category != lastCommentedCategory else { return }
        lastCommentedCategory = category
        if let l = line(category.messageCategory) { sayLine(l, style: .thought) }
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
        guard !isFirst, onboardingProgress.hasCompleted, !pet.brain.isAsleep else { return }
        switch bucket {
        case "morning": pet.send(.morningGreeting); say(.morning)
        case "afternoon": say(.afternoon, style: .thought)
        case "evening": say(.evening, style: .thought)
        default: break
        }
    }

    private func checkPresence(idle: Double) {
        if idle >= 300 {
            wasAway = true
        } else if wasAway && idle < 60 {
            wasAway = false
            pet.send(.userReturned(awaySeconds: 300))
            say(.returned)
            productivity.userReturned()
        }
    }

    /// Most of the time the pet just quietly exists. Rarely, when the user is
    /// around: a check-in visit after a long stretch without interaction, a
    /// late-night note, or an idle thought.
    private func maybeSpontaneousMoment(active: Bool, now: Date) {
        guard active, appSettings.speechBubbles, !cachedContext.quietHours,
              !pet.brain.isAsleep, !productivity.isFocusing, pet.brain.currentActivity == nil, pet.brain.behavior != .dragged else { return }
        let chatty = pet.character.personality.chattiness * appSettings.talkativeness.multiplier
        if now.timeIntervalSince(lastInteractionAt) > 30 * 60, !pet.brain.isMoving, Double.random(in: 0..<1) < 0.25 * chatty, let l = line(.checkIn) {
            pet.send(.checkIn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.sayLine(l, style: .speech) }
            lastInteractionAt = now // don't check in again right away
            return
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 23 || hour < 4, Double.random(in: 0..<1) < 0.06, let l = line(.lateNight) {
            sayLine(l, style: .thought)
            return
        }
        guard Double.random(in: 0..<1) < 0.3 * chatty else { return }
        let mood = pet.brain.mood(cachedContext)
        let category: MessageCategory
        switch Int.random(in: 0..<10) {
        case 0..<4:
            switch mood {
            case .happy: category = .moodHappy
            case .calm: category = .moodCalm
            case .curious: category = .moodCurious
            case .sleepy: category = .moodSleepy
            case .playful: category = .moodPlayful
            case .excited: category = .moodExcited
            case .annoyed: category = .annoyed
            case .focused: category = .idle
            }
        case 4..<6: category = pet.brain.boredom > 0.5 ? .bored : .idle
        case 6: category = .play
        default: category = .idle
        }
        if let l = line(category) ?? line(.idle) { sayLine(l, style: .thought) }
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
}
