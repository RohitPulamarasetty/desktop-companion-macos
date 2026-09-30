import AppKit
import Core

/// Per-character detail view: animated preview, name, description, personality
/// and credit, with a button to use the character.
public final class CharacterDetailWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let previewHost = LayerImageView()
    private var frames: [CGImage] = []

    public var onUse: ((String) -> Void)?
    public var onToggleFavorite: ((String) -> Void)?
    public var isFavorite: ((String) -> Bool)?
    private var currentID: String?
    private let favoriteButton = NSButton(image: NSImage(systemSymbolName: "star", accessibilityDescription: "Favorite") ?? NSImage(), target: nil, action: nil)

    public func show(character: CharacterDefinition, entry: CharacterCatalogEntry, isActive: Bool) {
        currentID = character.id
        let w = window ?? makeWindow()
        window = w
        populate(character: character, entry: entry, isActive: isActive)
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                         styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.isReleasedWhenClosed = false
        w.backgroundColor = PetTheme.paper
        w.delegate = self
        return w
    }

    private func populate(character: CharacterDefinition, entry: CharacterCatalogEntry, isActive: Bool) {
        guard let w = window else { return }
        w.title = character.displayName

        previewHost.translatesAutoresizingMaskIntoConstraints = false
        let pixelArt = character.pointsPerPixel >= 1
        previewHost.imageLayer.magnificationFilter = pixelArt ? .nearest : .linear
        previewHost.imageLayer.minificationFilter = pixelArt ? .nearest : .linear
        if let s = character.state("stand") ?? character.state("sit") {
            let a = s.animation
            frames = SpriteSheetLoader.loadFrames(fileURL: character.baseURL.appendingPathComponent(a.spriteSheet),
                                                  frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: a.frameCount)
                .compactMap { SpriteFrame(decoding: $0)?.image }
            if !frames.isEmpty {
                previewHost.imageLayer.contents = frames[0]
                if frames.count > 1 {
                    let anim = CAKeyframeAnimation(keyPath: "contents")
                    anim.values = frames
                    anim.calculationMode = .discrete
                    anim.duration = Double(frames.count) / max(a.framesPerSecond, 0.5)
                    anim.repeatCount = .infinity
                    previewHost.imageLayer.add(anim, forKey: "idle")
                }
            }
        }

        let name = PetTheme.label(character.displayName, size: 20, weight: .bold)
        name.alignment = .center

        favoriteButton.bezelStyle = .circular
        favoriteButton.isBordered = false
        favoriteButton.controlSize = .large
        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteTapped)
        favoriteButton.toolTip = "Favorite"
        updateFavoriteButton(character.id)
        let nameRow = PetTheme.hstack([name, favoriteButton], spacing: 6)

        let tagline = PetTheme.label(character.tagline, size: 12.5, color: PetTheme.accent)
        tagline.alignment = .center
        let description = PetTheme.wrapping(entry.description, size: 12, width: 300)
        description.alignment = .center

        var badges: [NSView] = []
        if let trait = character.manifest.personality?.trait {
            badges.append(pill("🐾 \(trait.capitalized)"))
        }
        let badgeRow = PetTheme.hstack(badges, spacing: 6)

        var extras: [NSView] = []
        let temperament = CharacterProfile.temperament(character.personality)
        if !temperament.isEmpty {
            extras.append(PetTheme.sectionHeader("Temperament"))
            for line in temperament { extras.append(PetTheme.wrapping("• " + line, size: 12, width: 290)) }
        }
        let abilities = CharacterProfile.abilities(clips: character.availableClipNames)
        if !abilities.isEmpty {
            extras.append(PetTheme.sectionHeader("Can do"))
            extras.append(PetTheme.wrapping(abilities.joined(separator: " · "), size: 12, width: 290))
        }

        let credit = entry.author.map { "Artwork by \($0)" } ?? ""
        let statusLine = PetTheme.label(isActive ? "Your current companion" : credit, size: 11, color: PetTheme.inkSoft)
        statusLine.alignment = .center

        let actionButton = PetButton(isActive ? "Current companion" : "Use this companion", style: .primary) { [weak self] in
            guard let self, let id = self.currentID else { return }
            self.onUse?(id)
            self.window?.close()
        }
        actionButton.isEnabled = !isActive
        let stack = PetTheme.vstack([previewHost, nameRow, tagline, badgeRow, description] + extras + [statusLine, actionButton], spacing: 8, alignment: .centerX)
        stack.setCustomSpacing(2, after: nameRow)
        stack.setCustomSpacing(10, after: badgeRow)
        stack.setCustomSpacing(14, after: description)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            previewHost.widthAnchor.constraint(equalToConstant: 180),
            previewHost.heightAnchor.constraint(equalToConstant: 160),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        content.layoutSubtreeIfNeeded()
        w.setContentSize(NSSize(width: 340, height: content.fittingSize.height))
    }

    @objc private func favoriteTapped() {
        guard let id = currentID else { return }
        onToggleFavorite?(id)
        updateFavoriteButton(id)
    }

    private func updateFavoriteButton(_ id: String) {
        let favorited = isFavorite?(id) ?? false
        favoriteButton.image = NSImage(systemSymbolName: favorited ? "star.fill" : "star", accessibilityDescription: "Favorite")
        favoriteButton.contentTintColor = favorited ? PetTheme.accent : PetTheme.inkSoft
    }

    private func pill(_ text: String) -> NSView {
        let label = PetTheme.label(text, size: 10.5, weight: .medium, color: PetTheme.inkSoft)
        label.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = PetTheme.accentSoft.cgColor
        host.layer?.cornerRadius = 8
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: host.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -3),
        ])
        return host
    }

    public func windowWillClose(_ notification: Notification) {
        previewHost.imageLayer.removeAnimation(forKey: "idle")
        frames = []
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
        }
    }
}
