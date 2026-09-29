import AppKit
import Core

/// The seam between the platform-independent `PetBrain` and AppKit.
///
/// **Stage.** The pet lives on a transparent, click-through window covering
/// the usable area (menu bar and Dock excluded) of one display. The pet is a
/// layer on that stage and can be anywhere on it -- top, bottom, corners,
/// centre. Nothing ever pulls it back to the bottom.
///
/// **Rendering.** Each movement leg the brain plans (from -> to, duration,
/// ease-in-out) becomes one render-server animation with the *same* easing
/// curve; clip frames cycle as render-server keyframes; all feedback
/// (bounce, lift, turn, settle, breathing, 💤, bubbles) is Core Animation.
/// This process wakes only when the brain has a decision to make
/// (`brain.nextEventIn`) or to check the cursor for click-through:
/// ~2.5 Hz normally, 10 Hz with the cursor near the pet, 1 Hz while asleep.
///
/// **Truth.** The render server is the truth for where the pet visually is.
/// Before any interaction the brain is synced to the on-screen position, so
/// nothing ever jumps.
///
/// **Displays.** The pet belongs to one display (by CGDirectDisplayID). It
/// changes display only when dragged there; if its display disappears it
/// moves to the primary display, keeping its relative position.
public final class CharacterWindowController {
    // MARK: Public surface

    public var contextProvider: (() -> PetContext)?
    public var onClick: ((PetEventOutcome) -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onContextMenu: ((NSEvent) -> Void)?
    public var onBehaviorChange: ((PetBehavior) -> Void)?
    /// Fired when an activity starts or ends (including by its own timer).
    public var onActivityChanged: ((Activity?) -> Void)?
    private var lastReportedActivity: Activity?
    /// Kept for API compatibility; bubbles are attached to the pet now.
    public var onMoved: ((NSRect) -> Void)?
    /// The user finished dragging the pet somewhere (worth saving now).
    public var onDropped: (() -> Void)?

    public private(set) var brain: PetBrain!
    public private(set) var character: CharacterDefinition
    public var currentStateID: String { "\(brain.behavior.rawValue)/\(brain.clip)@\(Int(brain.x)),\(Int(brain.y))" }
    public var currentAnimationFPS: Double { (renderedState?.animation.framesPerSecond ?? 0) * renderedRate }
    public var isVisible: Bool { panel.isVisible }
    public var displayName: String { character.displayName }
    public var tickInterval: TimeInterval { currentInterval }
    public var isHiddenByUser: Bool { hiddenReasons.contains(.user) }

    /// The pet's own rect in screen coordinates, as currently on screen.
    public var currentFrame: NSRect {
        let r = view.presentedPetRect
        return NSRect(x: panel.frame.minX + r.minX, y: panel.frame.minY + r.minY, width: r.width, height: r.height)
    }

    public enum HiddenReason: Hashable { case user, policy, systemSleep, displaysAsleep }

    // MARK: Internals

    private let panel: TransparentPanel
    private let view: CharacterView
    private let settings: AppSettings
    private var petSize: NSSize

    private var frameCache: [String: [SpriteFrame]] = [:]
    private var cacheOrder: [String] = []
    private let maxCachedStates = 6
    private var renderedState: StateDefinition?
    private var renderedClip = ""
    private var renderedMirror = false
    private var renderedFacing: Facing?
    private var renderedRate: Double = 1
    private var lastVisualRevision = -1
    private var lastLegRevision = -1
    private var wasMoving = false

    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private var lastTick = Date()
    private var hiddenReasons: Set<HiddenReason> = []

    private var assignedDisplayID: CGDirectDisplayID = 0
    private var ignoresMouse = true
    private var cursorWasNear = false

    private var mouseDownPoint: NSPoint?
    private var dragging = false
    private var dragOffset = NSPoint.zero

    // Bubbles
    private var bubbleDismissWork: DispatchWorkItem?

    private var mouseMonitor: Any?
    /// Cached screen rect of the pet (+ bubble), refreshed each tick, so the
    /// global mouse monitor does one rect test per event and nothing else.
    private var hotRect = NSRect.zero

    public init(character: CharacterDefinition, settings: AppSettings, savedPosition: PetStateStore.SavedPosition?, savedEnergy: Double?) {
        self.character = character
        self.settings = settings
        petSize = Self.petSize(for: character, settings: settings)
        let screen = Self.initialScreen(settings: settings, saved: savedPosition)
        let stage = screen.visibleFrame
        panel = TransparentPanel(contentRect: stage)
        view = CharacterView(frame: NSRect(origin: .zero, size: stage.size), petSize: petSize)
        panel.contentView = view
        panel.setFrame(stage, display: false)
        panel.applyPlacementPolicy(showEverywhere: settings.showPetEverywhere, aboveWindows: settings.keepAboveWindows)
        assignedDisplayID = screen.displayID

        let area = Self.area(on: screen, petSize: petSize, settings: settings)
        var start = (area.minX, area.minY)
        switch settings.startPosition {
        case .bottomLeft: start = (area.minX, area.minY)
        case .bottomRight: start = (area.maxX, area.minY)
        case .lastPosition:
            if let s = savedPosition, s.displayID == screen.displayID {
                start = (area.minX + (area.maxX - area.minX) * s.fraction, area.minY + (area.maxY - area.minY) * s.fractionY)
            }
        }
        var config = PetBrain.Config(pointsPerPixel: Self.speedUnit(character: character, width: petSize.width),
                                     petWidth: Double(petSize.width), petHeight: Double(petSize.height),
                                     availableClips: character.availableClipNames)
        config.homeOnLeft = settings.startPosition != .bottomRight
        config.barkProbability = settings.barkOnClick ? 0.35 : 0
        config.personality = character.personality
        let energy = max(0.5, min(savedEnergy ?? 0.55, 0.8))
        brain = PetBrain(config: config, x: start.0, y: start.1, minX: area.minX, maxX: area.maxX, minY: area.minY, maxY: area.maxY,
                         facing: start.0 > (area.minX + area.maxX) / 2 ? .left : .right,
                         energy: energy, intro: true,
                         rng: SeededRandom(seed: UInt64(Date().timeIntervalSince1970 * 1000)))
        brain.onBehaviorChange = { [weak self] _, new in self?.onBehaviorChange?(new) }

        view.onMouseDown = { [weak self] p, count in self?.mouseDown(at: p, clickCount: count) }
        view.onMouseDragged = { [weak self] p in self?.mouseDragged(to: p) }
        view.onMouseUp = { [weak self] p in self?.mouseUp(at: p) }
        view.onContextMenu = { [weak self] e in self?.contextMenu(e) }
        view.onMouseMoved = { [weak self] in self?.updateClickThrough(mouse: NSEvent.mouseLocation) }

        view.setPetOrigin(localPoint(brain.x, brain.y))
        fitStage()
        updateFilter()
        syncVisuals(force: true)
    }

    // MARK: Lifecycle

    public func show() {
        hiddenReasons.remove(.user)
        applyVisibility()
    }

    public func toggleVisibility() {
        if hiddenReasons.contains(.user) { hiddenReasons.remove(.user) } else { hiddenReasons.insert(.user) }
        applyVisibility()
    }

    public func setHidden(_ hidden: Bool, reason: HiddenReason) {
        if hidden { hiddenReasons.insert(reason) } else { hiddenReasons.remove(reason) }
        applyVisibility()
    }

    private func applyVisibility() {
        if hiddenReasons.isEmpty {
            startMouseMonitor()
            if !panel.isVisible || !panel.isOnActiveSpace { panel.orderFrontRegardless() }
            if timer == nil {
                lastTick = Date()
                syncVisuals(force: true)
                scheduleNextTick()
            }
        } else {
            syncBrainToVisual()
            stopMouseMonitor()
            timer?.invalidate()
            timer = nil
            currentInterval = 0
            view.setPetOrigin(localPoint(brain.x, brain.y))
            if panel.isVisible { panel.orderOut(nil) }
            view.setBreathing(false)
        }
    }

    public func ensureOnActiveSpace() {
        guard hiddenReasons.isEmpty else { return }
        if !panel.isVisible || !panel.isOnActiveSpace { panel.orderFrontRegardless() }
    }

    public func applyPlacementSettings() {
        panel.applyPlacementPolicy(showEverywhere: settings.showPetEverywhere, aboveWindows: settings.keepAboveWindows)
        brain.setBarkProbability(settings.barkOnClick ? 0.35 : 0)
        ensureOnActiveSpace()
    }

    /// Sends an event to the brain (after syncing it to the on-screen
    /// position) and renders the result.
    @discardableResult
    public func send(_ event: PetEvent) -> PetEventOutcome {
        syncBrainToVisual()
        let outcome = brain.handle(event, context: makeContext())
        render()
        return outcome
    }

    /// Runs a user command (menu, shortcut) on the brain and renders it.
    @discardableResult
    public func perform(_ command: PetCommand) -> PetCommandResult {
        syncBrainToVisual()
        let result = brain.perform(command, context: makeContext())
        render()
        reportActivityChange()
        scheduleNextTick()
        return result
    }

    private func reportActivityChange() {
        guard brain.currentActivity != lastReportedActivity else { return }
        lastReportedActivity = brain.currentActivity
        onActivityChanged?(lastReportedActivity)
    }

    // MARK: Size & character

    private static func scale(for character: CharacterDefinition, settings: AppSettings) -> CGFloat {
        CGFloat(character.pointsPerPixel * settings.petSize.scaleMultiplier)
    }

    private static func petSize(for character: CharacterDefinition, settings: AppSettings) -> NSSize {
        let s = scale(for: character, settings: settings)
        let (w, h) = character.frameSize
        return NSSize(width: (CGFloat(w) * s).rounded(), height: (CGFloat(h) * s).rounded())
    }

    private static func speedUnit(character: CharacterDefinition, width: CGFloat) -> Double {
        Double(width) / 64 * character.gait
    }

    private func applyGeometry() {
        syncBrainToVisual()
        let center = (brain.x + Double(petSize.width) / 2, brain.y)
        petSize = Self.petSize(for: character, settings: settings)
        view.setPetSize(petSize)
        brain.setScale(pointsPerPixel: Self.speedUnit(character: character, width: petSize.width),
                       petWidth: Double(petSize.width), petHeight: Double(petSize.height))
        refreshBounds()
        brain.place(x: center.0 - Double(petSize.width) / 2, y: center.1)
        view.setPetOrigin(localPoint(brain.x, brain.y))
        updateFilter()
    }

    public func applyPetSize() {
        guard Self.petSize(for: character, settings: settings) != petSize else { return }
        applyGeometry()
        syncVisuals(force: true)
    }

    /// Swaps the look with a small shrink-out / pop-in. Only visuals change:
    /// the brain (energy, behavior, position, stats, memory) is untouched.
    public func setCharacter(_ newCharacter: CharacterDefinition) {
        guard newCharacter != character else { return }
        view.swapOut { [weak self] in
            guard let self else { return }
            self.character = newCharacter
            self.frameCache.removeAll()
            self.cacheOrder.removeAll()
            self.renderedState = nil
            self.renderedClip = ""
            self.brain.setAvailableClips(newCharacter.availableClipNames, context: self.makeContext())
            self.brain.setPersonality(newCharacter.personality)
            self.applyGeometry()
            self.syncVisuals(force: true)
            self.view.swapIn()
            self.send(.doubleClick) // a happy hello in the new look
            self.scheduleNextTick()
        }
    }

    private func updateFilter() {
        let backing = panel.backingScaleFactor > 0 ? panel.backingScaleFactor : 2
        let devicePerSource = Self.scale(for: character, settings: settings) * backing
        view.setIntegerScale(abs(devicePerSource - devicePerSource.rounded()) < 0.01 && devicePerSource >= 1)
    }

    // MARK: Displays & coordinates

    private static func initialScreen(settings: AppSettings, saved: PetStateStore.SavedPosition?) -> NSScreen {
        if settings.startPosition == .lastPosition, let saved,
           let screen = NSScreen.screens.first(where: { $0.displayID == saved.displayID }) {
            return screen
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private static func area(on screen: NSScreen, petSize: NSSize, settings: AppSettings) -> PetPlacement.Area {
        PetPlacement.area(on: screen.placementDisplay, petWidth: Double(petSize.width), petHeight: Double(petSize.height),
                          roamRange: settings.roamRange, homeOnLeft: settings.startPosition != .bottomRight)
    }

    private var assignedScreen: NSScreen? { NSScreen.screens.first(where: { $0.displayID == assignedDisplayID }) }

    /// Screen point -> stage-local point.
    private func localPoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) - panel.frame.minX, y: CGFloat(y) - panel.frame.minY)
    }

    private func refreshBounds() {
        guard let screen = assignedScreen else { return }
        let a = Self.area(on: screen, petSize: petSize, settings: settings)
        brain.setBounds(minX: a.minX, maxX: a.maxX, minY: a.minY, maxY: a.maxY)
    }

    /// Covers `screen`'s usable area with the stage (used while dragging),
    /// keeping the pet where it is on screen.
    private func moveStage(to screen: NSScreen) {
        assignedDisplayID = screen.displayID
        setStage(screen.visibleFrame)
        updateFilter()
    }

    /// Moves/resizes the stage window without anything visibly moving: the
    /// content is shifted by the same amount in the same screen update.
    private func setStage(_ rect: NSRect) {
        let r = rect.integral
        guard r != panel.frame, r.width > 0, r.height > 0 else { return }
        let old = panel.frame.origin
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(r, display: false)
        view.frame = NSRect(origin: .zero, size: r.size)
        view.shiftContent(by: CGPoint(x: r.minX - old.x, y: r.minY - old.y))
        if let v = assignedScreen?.visibleFrame {
            view.bubbleLimits = CGRect(x: v.minX - r.minX, y: v.minY - r.minY, width: v.width, height: v.height)
        }
    }

    /// The stage covers the display's usable area. A stage fitted to just
    /// the pet + its current leg would save WindowServer a display-sized
    /// transparent surface, but that sizing logic was removed as an
    /// unverified optimization (it could never be click-tested on a live,
    /// unlocked session) rather than shipped disabled-but-present -- see
    /// docs/PERFORMANCE.md. `setStage` keeps the content still either way,
    /// so re-adding a fitted stage later is a localized change here, not an
    /// architectural one.
    private func fitStage() {
        guard !dragging, let screen = assignedScreen else { return }
        setStage(screen.visibleFrame)
    }

    /// Where the render server shows the pet -> the brain. Called before
    /// every interaction so a mid-walk click never makes the pet jump.
    private func syncBrainToVisual() {
        guard !dragging else { return }
        let f = currentFrame.origin
        if abs(Double(f.x) - brain.x) > 0.5 || abs(Double(f.y) - brain.y) > 0.5 {
            brain.place(x: Double(f.x), y: Double(f.y))
        }
    }

    /// Display configuration changed (connect/disconnect, resolution,
    /// arrangement, Dock/menu bar). Keeps the pet's relative position;
    /// never sends it "home".
    public func screensChanged() {
        syncBrainToVisual()
        let old = currentFrame.origin
        // Where the pet was, as a fraction of its old usable area.
        let sx = brain.maxX - brain.minX, sy = brain.maxY - brain.minY
        let fx = sx > 0 ? (brain.x - brain.minX) / sx : 0
        let fy = sy > 0 ? (brain.y - brain.minY) / sy : 0
        let screen: NSScreen
        if let s = assignedScreen {
            screen = s
        } else if let fallback = PetPlacement.resolveDisplay(assigned: assignedDisplayID, available: NSScreen.screens.map(\.placementDisplay)),
                  let s = NSScreen.screens.first(where: { $0.displayID == fallback.id }) {
            screen = s
        } else { return }
        let sameDisplay = screen.displayID == assignedDisplayID
        assignedDisplayID = screen.displayID
        refreshBounds()
        if sameDisplay {
            brain.place(x: Double(old.x), y: Double(old.y)) // clamps into the new area in place
        } else {
            brain.place(x: brain.minX + fx * (brain.maxX - brain.minX), y: brain.minY + fy * (brain.maxY - brain.minY))
        }
        setStage(NSRect(x: brain.x, y: brain.y, width: Double(petSize.width), height: Double(petSize.height)))
        view.setPetOrigin(localPoint(brain.x, brain.y))
        fitStage()
        lastLegRevision = brain.legRevision
        render()
        updateFilter()
    }

    /// "Bring home": walks there -- never slides a sitting pet across the
    /// screen. (Only a pet on another display is carried over first.)
    public func resetToHome() {
        if let primary = NSScreen.screens.first, primary.displayID != assignedDisplayID {
            moveStage(to: primary)
            refreshBounds()
            brain.place(x: brain.homeX + Double(petSize.width) * 3, y: brain.homeY)
            view.setPetOrigin(localPoint(brain.x, brain.y))
        }
        send(.goHome)
        scheduleNextTick()
    }

    public func savedPosition() -> PetStateStore.SavedPosition {
        let sx = brain.maxX - brain.minX, sy = brain.maxY - brain.minY
        return .init(displayID: assignedDisplayID,
                     fraction: sx > 0 ? (brain.x - brain.minX) / sx : 0,
                     fractionY: sy > 0 ? (brain.y - brain.minY) / sy : 0)
    }

    // MARK: Tick (event-scheduled, not polled)

    /// Click-through is event-driven now (global mouse monitor), so ticks
    /// are only for the brain; the cursor check just refreshes "near" state.
    private func pollInterval() -> TimeInterval {
        if dragging { return 1 }
        if cursorWasNear { return 0.25 }
        return brain.isAsleep ? 2.0 : 1.0
    }

    /// One-shot timer at the brain's next decision or the cursor check,
    /// whichever comes first.
    private func scheduleNextTick() {
        guard hiddenReasons.isEmpty else { return }
        timer?.invalidate()
        let wait = min(brain.nextEventIn + 0.005, pollInterval())
        currentInterval = wait
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = min(0.05, wait * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func makeContext() -> PetContext {
        var ctx = contextProvider?() ?? PetContext()
        let mouse = NSEvent.mouseLocation
        if let screen = assignedScreen, screen.frame.contains(mouse) {
            ctx.cursorX = Double(mouse.x)
            ctx.cursorY = Double(mouse.y)
        }
        ctx.cursorNearPet = cursorWasNear
        return ctx
    }

    private func tick() {
        timer = nil
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 30)
        lastTick = now
        let mouse = NSEvent.mouseLocation
        let near = currentFrame.insetBy(dx: -160, dy: -120).contains(mouse)

        if !dragging {
            let ctx = makeContext()
            if near && !cursorWasNear { brain.handle(.cursorApproached, context: ctx) }
            brain.update(dt: dt, context: ctx)
        }
        cursorWasNear = near

        if let micro = brain.takeMicroAnimation() {
            switch micro {
            case .twitch: view.playTwitch()
            case .earFlick: view.playEarFlick()
            }
        }
        render()
        reportActivityChange()
        refreshHotRect()
        updateClickThrough(mouse: mouse)
        scheduleNextTick()
    }

    /// Applies the brain's current state to the stage: movement legs,
    /// clip/facing, feedback.
    private func render() {
        guard !dragging else { syncVisuals(force: false); return }
        if brain.legRevision != lastLegRevision {
            lastLegRevision = brain.legRevision
            if let leg = brain.leg {
                fitStage()
                let to = localPoint(leg.toX, leg.toY)
                if view.hasBubble { view.reclampBubble(forPetOriginsAt: [view.presentedPetOrigin, to]) }
                if view.hasBadge { view.repositionBadge(forPetOrigin: to) }
                view.glide(to: to, duration: leg.remaining, eased: !leg.linear && leg.elapsed < 0.05)
            } else {
                let target = localPoint(brain.x, brain.y)
                let shown = view.presentedPetOrigin
                if hypot(shown.x - target.x, shown.y - target.y) > 1.5 && (!view.isGliding || brain.isTurning) {
                    // Only a bounds clamp (Dock/resolution change) moves the
                    // pet without a leg: correct in place, never slide a
                    // non-walking pose across the screen.
                    view.setPetOrigin(target)
                }
            }
        }
        if wasMoving && !brain.isMoving {
            view.settle()
            fitStage()
        }
        wasMoving = brain.isMoving
        syncVisuals(force: false)
        refreshHotRect()
    }

    // MARK: Rendering

    private func syncVisuals(force: Bool) {
        guard let resolved = character.resolve(brain.clip, facing: brain.facing) else { return }
        let stateChanged = resolved.state.id != renderedState?.id
        let rate = brain.isMoving ? brain.playbackRate : 1
        let rateChanged = abs(rate - renderedRate) > max(0.2 * renderedRate, 0.05)
        guard force || stateChanged || rateChanged || brain.visualRevision != lastVisualRevision else { return }
        lastVisualRevision = brain.visualRevision

        if let prev = renderedFacing, prev != brain.facing, !stateChanged || renderedClip == brain.clip { view.turn() }
        renderedFacing = brain.facing

        if force || stateChanged || rateChanged {
            loadFrames(resolved.state)
            guard let frames = frameCache[resolved.state.id], !frames.isEmpty else { return }
            let sameGait = renderedClip == brain.clip && renderedState?.animation.frameCount == resolved.state.animation.frameCount
            let phase = sameGait ? view.currentFrameIndex : 0
            view.play(frames, fps: resolved.state.animation.framesPerSecond * rate,
                      loop: resolved.state.animation.loop, mirrored: resolved.mirrored, startFrame: phase)
            if stateChanged {
                let asleep = brain.clip == "sleep"
                view.setBreathing(asleep && !settings.reducedMotion)
                view.setSleepIndicator(asleep)
            }
            renderedState = resolved.state
            renderedRate = rate
        } else {
            view.setMirrored(resolved.mirrored)
        }
        renderedClip = brain.clip
        renderedMirror = resolved.mirrored
    }

    private func touchCache(_ id: String) {
        if cacheOrder.last != id {
            cacheOrder.removeAll { $0 == id }
            cacheOrder.append(id)
        }
    }

    private func loadFrames(_ state: StateDefinition) {
        guard frameCache[state.id] == nil else { touchCache(state.id); return }
        let a = state.animation
        let raw = SpriteSheetLoader.loadFramesOrSafeDefault(
            fileURL: character.baseURL.appendingPathComponent(a.spriteSheet),
            frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: a.frameCount,
            isSafeDefault: a.spriteSheet == SafeDefaultCharacter.spriteSheetName)
        frameCache[state.id] = raw.compactMap(SpriteFrame.init(decoding:))
        touchCache(state.id)
        while cacheOrder.count > maxCachedStates {
            frameCache[cacheOrder.removeFirst()] = nil
        }
    }

    public func portrait() -> CGImage? { Self.portrait(of: character) }

    public static func portrait(of character: CharacterDefinition) -> CGImage? {
        guard let s = character.state("sit") ?? character.state("stand") ?? character.manifest.states.first else { return nil }
        let a = s.animation
        return SpriteSheetLoader.loadFrames(fileURL: character.baseURL.appendingPathComponent(a.spriteSheet),
                                            frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: 1)
            .first.flatMap { SpriteFrame(decoding: $0)?.image }
    }

    /// Decoded frames of the clip the pet is showing right now, and their
    /// fps (for live previews elsewhere, e.g. the Home panel).
    public func liveClip() -> (frames: [CGImage], fps: Double, mirrored: Bool)? {
        guard let s = renderedState, let frames = frameCache[s.id] else { return nil }
        return (frames.map(\.image), s.animation.framesPerSecond, renderedMirror)
    }

    // MARK: Bubbles

    /// Pet speech (💬) or thought (💭): attached to the pet, springs in,
    /// fades out after `duration`. Replaces any current non-question bubble.
    public func say(_ text: String, style: BubbleLayer.Style = .speech, duration: TimeInterval = 3.5) {
        showBubble(.init(text: text, style: style), duration: duration)
    }

    /// Status pill attached to the pet (e.g. "Following").
    public func setBadge(_ text: String?, kind: String = "", emphasis: Bool = false) {
        guard hiddenReasons.isEmpty || text == nil else { return }
        view.setBadge(text, kind: kind, emphasis: emphasis)
    }

    private func showBubble(_ content: BubbleLayer.Content, duration: TimeInterval) {
        guard hiddenReasons.isEmpty else { return }
        fitStage()
        view.showBubble(content)
        bubbleDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissBubble() }
        bubbleDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismissBubble() {
        bubbleDismissWork?.cancel()
        bubbleDismissWork = nil
        view.hideBubble(animated: true)
    }

    // MARK: Click-through

    /// Mouse moves elsewhere on screen reach us only through a global
    /// monitor (the window ignores events until the cursor is on the pet).
    /// Without it a quick move-and-click could land on the app underneath.
    /// The handler is one rect test; the pixel test runs only near the pet.
    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard let self else { return }
            let m = NSEvent.mouseLocation
            if self.hotRect.contains(m) || !self.ignoresMouse { self.updateClickThrough(mouse: m) }
        }
    }

    private func stopMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
    }

    private func refreshHotRect() {
        var r = currentFrame
        if brain.isMoving, let leg = brain.leg {
            // While gliding, cover the whole leg so a click mid-walk works.
            let a = NSRect(x: leg.fromX, y: leg.fromY, width: Double(petSize.width), height: Double(petSize.height))
            let b = NSRect(x: leg.toX, y: leg.toY, width: Double(petSize.width), height: Double(petSize.height))
            r = r.union(a).union(b)
        }
        if view.hasBubble { r = r.insetBy(dx: -130, dy: -90) }
        hotRect = r.insetBy(dx: -8, dy: -8)
    }

    private func updateClickThrough(mouse: NSPoint) {
        var ignore = true
        if dragging {
            ignore = false
        } else {
            let local = view.convert(panel.convertPoint(fromScreen: mouse), from: nil)
            if currentFrame.contains(mouse) && view.isOpaque(atLocalPoint: local) {
                ignore = false
            }
        }
        if ignore != ignoresMouse {
            ignoresMouse = ignore
            panel.ignoresMouseEvents = ignore
        }
    }

    // MARK: Mouse

    private func mouseDown(at point: NSPoint, clickCount: Int) {
        mouseDownPoint = point
        let rect = currentFrame
        dragOffset = NSPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        if clickCount == 2 {
            mouseDownPoint = nil
            view.bounce()
            send(.doubleClick)
            onDoubleClick?()
        }
    }

    private func mouseDragged(to point: NSPoint) {
        guard let start = mouseDownPoint else { return }
        if !dragging {
            guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
            syncBrainToVisual()
            dragging = true
            view.setPetOrigin(view.presentedPetOrigin) // freeze any glide where it is
            if let screen = assignedScreen { setStage(screen.visibleFrame) } // free movement while carried
            brain.handle(.dragBegan, context: makeContext())
            view.setLifted(true)
            syncVisuals(force: false)
        }
        // Follow the cursor across displays: the stage hops to whichever
        // display the cursor is on; the pet stays fully inside it.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }), screen.displayID != assignedDisplayID {
            moveStage(to: screen)
        }
        guard let screen = assignedScreen else { return }
        let a = Self.area(on: screen, petSize: petSize, settings: settings)
        let x = min(max(Double(point.x - dragOffset.x), a.minX), a.maxX)
        let y = min(max(Double(point.y - dragOffset.y), a.minY), a.maxY)
        view.setPetOrigin(localPoint(x, y))
    }

    private func mouseUp(at point: NSPoint) {
        defer { mouseDownPoint = nil }
        if dragging {
            dragging = false
            refreshBounds()
            let f = currentFrame.origin
            brain.place(x: Double(f.x), y: Double(f.y))
            view.setLifted(false)
            brain.handle(.dropped, context: makeContext())
            onDropped?()
            fitStage()
            lastLegRevision = brain.legRevision
            syncVisuals(force: false)
            scheduleNextTick()
            return
        }
        guard mouseDownPoint != nil else { return }
        view.bounce()
        let outcome = send(.click)
        onClick?(outcome)
        scheduleNextTick()
    }

    /// Right-click: the pet pauses and looks at you while its menu is open.
    private func contextMenu(_ event: NSEvent) {
        send(.askUser)
        onContextMenu?(event)
        send(.resume)
        scheduleNextTick()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var placementDisplay: PetPlacement.Display {
        let v = visibleFrame
        return .init(id: displayID, visibleMinX: Double(v.minX), visibleMinY: Double(v.minY), visibleMaxX: Double(v.maxX), visibleMaxY: Double(v.maxY))
    }
}
