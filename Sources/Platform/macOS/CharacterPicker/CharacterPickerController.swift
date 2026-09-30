import AppKit
import Core

/// One character card: portrait (animated when selected or hovered/focused),
/// name, one-line personality, temperament.
final class CharacterCardView: NSView {
    let character: CharacterDefinition
    var onSelect: ((String) -> Void)?
    var onHover: ((CharacterCardView, Bool) -> Void)?
    var onInfo: ((String) -> Void)?

    var isSelected = false { didSet { if isSelected != oldValue { refresh() } } }
    var isHighlighted = false { didSet { if isHighlighted != oldValue { refresh() } } }
    var wantsAnimation: Bool { isSelected || isHighlighted }

    private let previewHost = LayerImageView()
    private var previewLayer: CALayer { previewHost.imageLayer }
    private let badge = PetTheme.label("✓ Your pet", size: 10.5, weight: .bold, color: .white)
    private var frames: [CGImage] = []
    private var still: CGImage?
    private var tracking: NSTrackingArea?
    static let size = NSSize(width: 148, height: 184)

    init(character: CharacterDefinition) {
        self.character = character
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true

        previewHost.translatesAutoresizingMaskIntoConstraints = false
        let pixelArt = character.pointsPerPixel >= 1
        previewLayer.magnificationFilter = pixelArt ? .nearest : .linear
        previewLayer.minificationFilter = pixelArt ? .nearest : .linear

        let name = PetTheme.label(character.displayName, size: 13.5, weight: .bold)
        name.alignment = .center
        let tagline = PetTheme.label(character.tagline, size: 11, color: PetTheme.inkSoft)
        tagline.alignment = .center
        tagline.lineBreakMode = .byTruncatingTail
        energy.alignment = .center

        badge.wantsLayer = true
        badge.drawsBackground = false
        badge.alignment = .center
        let badgeHost = NSView()
        badgeHost.wantsLayer = true
        badgeHost.layer?.cornerRadius = 8
        badgeHost.layer?.backgroundColor = PetTheme.accent.cgColor
        badgeHost.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeHost.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: badgeHost.leadingAnchor, constant: 7),
            badge.trailingAnchor.constraint(equalTo: badgeHost.trailingAnchor, constant: -7),
            badge.topAnchor.constraint(equalTo: badgeHost.topAnchor, constant: 2),
            badge.bottomAnchor.constraint(equalTo: badgeHost.bottomAnchor, constant: -2),
        ])
        self.badgeHost = badgeHost

        let stack = PetTheme.vstack([previewHost, name, tagline, energy], spacing: 3, alignment: .centerX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(badgeHost)
        infoButton.bezelStyle = .circular
        infoButton.controlSize = .small
        infoButton.isBordered = false
        infoButton.font = PetTheme.font(13, .medium)
        infoButton.contentTintColor = PetTheme.inkSoft
        infoButton.toolTip = "About \(character.displayName)"
        infoButton.target = self
        infoButton.action = #selector(infoTapped)
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoButton)
        NSLayoutConstraint.activate([
            infoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            infoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            infoButton.widthAnchor.constraint(equalToConstant: 22),
            infoButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        NSLayoutConstraint.activate([
            previewHost.widthAnchor.constraint(equalToConstant: 128),
            previewHost.heightAnchor.constraint(equalToConstant: 112),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tagline.widthAnchor.constraint(lessThanOrEqualToConstant: Self.size.width - 16),
            badgeHost.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            badgeHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(character.displayName). \(character.tagline)")
        refresh()
    }

    private var badgeHost: NSView?
    private let energy = PetTheme.label("", size: 10.5, weight: .medium, color: PetTheme.inkSoft)
    private let infoButton = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About this character") ?? NSImage(), target: nil, action: nil)

    @objc private func infoTapped() { onInfo?(character.id) }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    static func traitText(_ trait: String?) -> String {
        guard let trait, !trait.isEmpty else { return "" }
        return "🐾 " + trait.capitalized
    }

    /// Loads the idle clip and plays it as a render-server keyframe
    /// animation -- the same runtime the desktop pet uses. Hovered/selected
    /// cards play at full speed; the rest idle gently at half speed.
    func startAnimating() {
        isActive = true
        applyAnimation()
    }

    private var fps: Double = 4
    private var isActive = false

    /// Only the highlighted or selected card keeps its whole idle clip in memory; every other card shows one
    /// decoded still frame. (Decoding all 36 clips at once cost ~65 MB while the picker was open.)
    private func loadClip(all: Bool) {
        guard let s = character.state("stand") ?? character.state("sit") else { return }
        let a = s.animation
        fps = a.framesPerSecond
        if all, frames.count <= 1 {
            frames = SpriteSheetLoader.loadFrames(fileURL: character.baseURL.appendingPathComponent(a.spriteSheet),
                                                  frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: a.frameCount)
                .compactMap { SpriteFrame(decoding: $0)?.image }
            if still == nil { still = frames.first }
        } else if !all, still == nil {
            still = SpriteSheetLoader.loadFrames(fileURL: character.baseURL.appendingPathComponent(a.spriteSheet),
                                                 frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: 1)
                .first.flatMap { SpriteFrame(decoding: $0)?.image }
        }
    }

    private func applyAnimation() {
        guard isActive else { return }
        previewLayer.removeAnimation(forKey: "idle")
        guard wantsAnimation else {
            loadClip(all: false)
            frames = []
            previewLayer.contents = still
            return
        }
        loadClip(all: true)
        guard !frames.isEmpty else { return }
        previewLayer.contents = frames[0]
        guard frames.count > 1 else { return }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames
        a.calculationMode = .discrete
        a.duration = Double(frames.count) / max(fps, 0.5) * (wantsAnimation ? 1 : 2)
        a.repeatCount = .infinity
        previewLayer.add(a, forKey: "idle")
    }

    func releaseAnimationFrames() {
        isActive = false
        previewLayer.removeAnimation(forKey: "idle")
        previewLayer.contents = nil
        frames = []
        still = nil
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PetTheme.card.cgColor
            layer?.borderColor = (isSelected ? PetTheme.accent : (isHighlighted ? PetTheme.accent.withAlphaComponent(0.45) : PetTheme.cardBorder)).cgColor
            layer?.borderWidth = isSelected ? 2.5 : 1.5
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isHighlighted ? 0.12 : 0
            layer?.shadowRadius = 8
            layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
        badgeHost?.isHidden = true
        energy.stringValue = isSelected ? "✓ Your companion" : Self.traitText(character.manifest.personality?.trait)
        energy.textColor = isSelected ? PetTheme.accent : PetTheme.inkSoft
        energy.font = PetTheme.font(10.5, isSelected ? .bold : .medium)
        applyAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .activeAlways], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(self, true) }
    override func mouseExited(with event: NSEvent) { onHover?(self, false) }
    override func mouseDown(with event: NSEvent) { onSelect?(character.id) }
    override func accessibilityPerformPress() -> Bool { onSelect?(character.id); return true }
}

/// A view whose own (hosted) layer shows an image, scaled to fit.
final class LayerImageView: NSView {
    let imageLayer = CALayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = imageLayer
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

/// A grid of character cards with keyboard navigation. Reused by the picker
/// window and onboarding.
public final class CharacterGridView: NSView {
    public var onSelect: ((String) -> Void)?
    public var onInfo: ((String) -> Void)?
    public var selectedID: String { didSet { cards.forEach { $0.isSelected = $0.character.id == selectedID } } }
    private var cards: [CharacterCardView] = []
    private var focusIndex: Int?
    private let columns: Int

    public init(characters: [CharacterDefinition], selectedID: String, columns: Int = 4) {
        self.selectedID = selectedID
        self.columns = columns
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let rows = PetTheme.vstack(spacing: 12, alignment: .leading)
        var row: NSStackView?
        for (i, c) in characters.enumerated() {
            if i % columns == 0 {
                row = PetTheme.hstack(spacing: 12)
                rows.addArrangedSubview(row!)
            }
            let card = CharacterCardView(character: c)
            card.isSelected = c.id == selectedID
            card.onSelect = { [weak self] id in self?.choose(id) }
            card.onInfo = { [weak self] id in self?.onInfo?(id) }
            card.onHover = { [weak self] card, inside in
                guard let self else { return }
                self.cards.forEach { $0.isHighlighted = ($0 === card) && inside }
                self.focusIndex = inside ? self.cards.firstIndex(where: { $0 === card }) : nil
            }
            row?.addArrangedSubview(card)
            cards.append(card)
        }
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Companions")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func choose(_ id: String) {
        selectedID = id
        onSelect?(id)
    }

    /// Starts/stops the previews (render-server animation: no timers here).
    public func setActive(_ active: Bool) {
        if active { cards.forEach { $0.startAnimating() } } else { cards.forEach { $0.releaseAnimationFrames() } }
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        let current = focusIndex ?? cards.firstIndex(where: { $0.isSelected }) ?? 0
        var next = current
        switch event.keyCode {
        case 123: next = max(0, current - 1)                       // ←
        case 124: next = min(cards.count - 1, current + 1)         // →
        case 125: next = min(cards.count - 1, current + columns)   // ↓
        case 126: next = max(0, current - columns)                 // ↑
        case 36, 49, 76: choose(cards[current].character.id); return // Return / Space / Enter
        default: super.keyDown(with: event); return
        }
        focusIndex = next
        cards.enumerated().forEach { $0.element.isHighlighted = $0.offset == next }
        NSAccessibility.post(element: cards[next], notification: .focusedUIElementChanged)
    }
}

/// "Choose your companion" window.
public final class CharacterPickerController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var grid: CharacterGridView?
    private var scrollView: NSScrollView?
    private var scrollHeightConstraint: NSLayoutConstraint?
    private let characters: [CharacterDefinition]
    private let catalogEntries: [CharacterCatalogEntry]
    private var section: CharacterLibrarySection = .all
    private let detailWindow = CharacterDetailWindowController()
    private let settings: AppSettings?
    public var onSelect: ((String) -> Void)?
    public var selectedID: String { didSet { grid?.selectedID = selectedID } }

    /// `catalogEntries` defaults to a fresh built-in-only catalog if not
    /// supplied, so existing call sites (onboarding's live picker, which
    /// doesn't need the Free/Owned/Store distinction) don't need to change.
    /// `settings` is optional for the same reason -- onboarding's picker
    /// doesn't need favorites; when nil, the Favorites section is simply
    /// always empty rather than crashing or faking persistence.
    public init(characters: [CharacterDefinition], selectedID: String, catalogEntries: [CharacterCatalogEntry]? = nil, settings: AppSettings? = nil) {
        self.characters = characters
        self.selectedID = selectedID
        self.catalogEntries = catalogEntries ?? CharacterCatalog.entries(characters)
        self.settings = settings
        super.init()
        detailWindow.onUse = { [weak self] id in
            self?.selectedID = id
            self?.onSelect?(id)
        }
        detailWindow.onToggleFavorite = { [weak self] id in
            guard let self, let settings = self.settings else { return }
            settings.setFavorite(id, !settings.isFavorite(id))
            if self.section == .favorites { self.rebuildGrid() }
        }
        detailWindow.isFavorite = { [weak self] id in self?.settings?.isFavorite(id) ?? false }
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show() {
        let w = window ?? makeWindow()
        w.center()
        grid?.setActive(true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(grid)
    }

    private func makeWindow() -> NSPanel {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                        styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.isMovableByWindowBackground = true
        w.hidesOnDeactivate = false
        w.delegate = self
        w.title = "Choose your companion"
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true

        let title = PetTheme.label("Choose your companion", size: 17, weight: .bold)
        let subtitle = PetTheme.label("Each has its own temperament. Your stats, memories and settings stay exactly as they are.", size: 12, color: PetTheme.inkSoft)

        let sections = NSSegmentedControl(labels: CharacterLibrarySection.allCases.map(\.rawValue),
                                          trackingMode: .selectOne, target: self, action: #selector(sectionChanged(_:)))
        sections.selectedSegment = 0
        sections.segmentStyle = .rounded

        let gridWidth = CGFloat(4) * CharacterCardView.size.width + 3 * 12
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: gridWidth).isActive = true
        let heightConstraint = scroll.heightAnchor.constraint(equalToConstant: 480)
        heightConstraint.isActive = true
        self.scrollHeightConstraint = heightConstraint
        self.scrollView = scroll
        rebuildGrid()

        let done = PetButton("Done", style: .primary) { [weak self] in self?.window?.close() }
        done.keyEquivalent = "\u{1b}"
        let footer = PetTheme.hstack([PetTheme.label("Tip: use the arrow keys and Return.", size: 11, color: PetTheme.inkSoft), PetTheme.spacer(), done])

        let stack = PetTheme.vstack([title, subtitle, sections, scroll, footer], spacing: 12)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(14, after: sections)
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: gridWidth + 48),
        ])
        w.contentView = content
        content.layoutSubtreeIfNeeded()
        w.setContentSize(NSSize(width: gridWidth + 48, height: content.fittingSize.height))
        window = w
        return w
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        section = CharacterLibrarySection.allCases[sender.selectedSegment]
        rebuildGrid()
    }

    /// Rebuilds the grid's contents for the current section. Simpler and
    /// safer than teaching `CharacterGridView` to re-filter in place, at
    /// the cost of losing card animation state across a section switch --
    /// an acceptable trade for how rarely this control is touched.
    private func rebuildGrid() {
        guard let scroll = scrollView else { return }
        grid?.setActive(false)
        let filteredEntries = CharacterLibrary.filter(catalogEntries, section: section, favorites: settings?.favoriteCharacterIDs ?? [])
        let filteredIDs = Set(filteredEntries.map(\.id))
        let visible = characters.filter { filteredIDs.contains($0.id) }
        let newGrid = CharacterGridView(characters: visible, selectedID: selectedID)
        newGrid.onSelect = { [weak self] id in
            self?.selectedID = id
            self?.onSelect?(id)
        }
        newGrid.onInfo = { [weak self] id in self?.showDetail(id) }
        scroll.documentView = newGrid
        NSLayoutConstraint.activate([
            newGrid.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            newGrid.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            newGrid.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        grid = newGrid
        if window?.isVisible == true { newGrid.setActive(true) }

        // NSScrollView + Auto Layout needs an explicit height on the scroll
        // view itself; the document view's own intrinsic height isn't
        // enough to drive it. Measure the grid's natural height for however
        // many characters this section actually has, then cap it -- so a
        // short section (e.g. Owned, today always empty) doesn't leave a
        // tall empty gap, and a long one (All, 30+ characters) scrolls
        // instead of pushing the window off-screen.
        newGrid.layoutSubtreeIfNeeded()
        let natural = newGrid.fittingSize.height
        scrollHeightConstraint?.constant = max(1, min(natural, 480))
        window?.layoutIfNeeded()
        if let content = window?.contentView {
            content.layoutSubtreeIfNeeded()
            window?.setContentSize(NSSize(width: content.frame.width, height: content.fittingSize.height))
        }
    }

    private func showDetail(_ id: String) {
        guard let character = characters.first(where: { $0.id == id }),
              let entry = catalogEntries.first(where: { $0.id == id }) else { return }
        detailWindow.show(character: character, entry: entry, isActive: id == selectedID)
    }

    public func windowWillClose(_ notification: Notification) {
        grid?.setActive(false)
        // Release the whole window (cards, stills) -- it's rarely reopened.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
            self?.grid = nil
        }
    }
}
