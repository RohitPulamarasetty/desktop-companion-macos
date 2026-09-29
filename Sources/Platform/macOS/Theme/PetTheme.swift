import AppKit

/// The single visual language shared by every piece of pet UI (home panel,
/// toasts, speech bubbles, settings, onboarding, menus): warm cream paper,
/// cocoa text, a caramel accent taken from the dog's own palette, rounded
/// type, soft rounded cards. Adapts to Dark Mode (cocoa paper, cream text).
public enum PetTheme {
    // MARK: Colors (dynamic: light / dark)

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    public static let paper = dynamic(NSColor(srgbRed: 0.992, green: 0.965, blue: 0.918, alpha: 1),
                                      NSColor(srgbRed: 0.165, green: 0.133, blue: 0.114, alpha: 1))
    public static let card = dynamic(NSColor(srgbRed: 1.0, green: 0.988, blue: 0.965, alpha: 1),
                                     NSColor(srgbRed: 0.224, green: 0.184, blue: 0.157, alpha: 1))
    public static let cardBorder = dynamic(NSColor(srgbRed: 0.902, green: 0.851, blue: 0.776, alpha: 1),
                                           NSColor(srgbRed: 0.318, green: 0.267, blue: 0.227, alpha: 1))
    public static let ink = dynamic(NSColor(srgbRed: 0.259, green: 0.188, blue: 0.141, alpha: 1),
                                    NSColor(srgbRed: 0.965, green: 0.925, blue: 0.867, alpha: 1))
    public static let inkSoft = dynamic(NSColor(srgbRed: 0.525, green: 0.451, blue: 0.392, alpha: 1),
                                        NSColor(srgbRed: 0.745, green: 0.690, blue: 0.627, alpha: 1))
    public static let accent = NSColor(srgbRed: 0.851, green: 0.502, blue: 0.259, alpha: 1)       // caramel
    public static let accentSoft = dynamic(NSColor(srgbRed: 0.980, green: 0.886, blue: 0.788, alpha: 1),
                                           NSColor(srgbRed: 0.380, green: 0.255, blue: 0.165, alpha: 1))
    public static let leaf = NSColor(srgbRed: 0.380, green: 0.647, blue: 0.451, alpha: 1)
    public static let water = NSColor(srgbRed: 0.341, green: 0.604, blue: 0.839, alpha: 1)
    public static let bubble = NSColor(srgbRed: 0.290, green: 0.208, blue: 0.157, alpha: 0.95)

    // MARK: Type

    public static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: rounded, size: size) ?? base
        }
        return base
    }

    public static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Factories

    public static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = PetTheme.ink) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font(size, weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    public static func wrapping(_ text: String, size: CGFloat = 12, color: NSColor = PetTheme.inkSoft, width: CGFloat = 300) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = font(size)
        l.textColor = color
        l.preferredMaxLayoutWidth = width
        return l
    }

    public static func sectionHeader(_ text: String) -> NSTextField {
        let l = label(text.uppercased(), size: 10.5, weight: .bold, color: inkSoft)
        return l
    }

    public static func vstack(_ views: [NSView] = [], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = alignment
        s.spacing = spacing
        return s
    }

    public static func hstack(_ views: [NSView] = [], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = spacing
        return s
    }

    public static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }
}

/// A rounded "card" container with the theme's paper/border colors.
public final class PetCardView: NSView {
    public let stack: NSStackView

    public init(_ views: [NSView] = [], spacing: CGFloat = 8, padding: CGFloat = 12) {
        stack = PetTheme.vstack(views, spacing: spacing)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
        updateColors()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = PetTheme.card.cgColor
            layer?.borderColor = PetTheme.cardBorder.cgColor
        }
    }
}

/// A soft, rounded, pill-shaped button in the theme's colors. `primary`
/// uses the caramel accent; secondary is a tinted outline.
public final class PetButton: NSButton {
    public enum Style { case primary, secondary, quiet }
    private let style: Style
    private var handler: (() -> Void)?
    /// Extra width around the title (smaller for rows of compact buttons).
    public var horizontalPadding: CGFloat = 22 { didSet { invalidateIntrinsicContentSize() } }

    public init(_ title: String, style: Style = .secondary, action: @escaping () -> Void) {
        self.style = style
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 9
        font = PetTheme.font(12.5, .semibold)
        target = self
        self.action = #selector(fire)
        setButtonType(.momentaryChange)
        focusRingType = .none
        updateColors()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler?() }

    public override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + horizontalPadding, height: max(26, base.height + 8))
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    public override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.45 } }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fg: NSColor
            switch style {
            case .primary:
                layer?.backgroundColor = PetTheme.accent.cgColor
                layer?.borderWidth = 0
                fg = .white
            case .secondary:
                layer?.backgroundColor = PetTheme.accentSoft.cgColor
                layer?.borderWidth = 0
                fg = PetTheme.ink
            case .quiet:
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 1
                layer?.borderColor = PetTheme.cardBorder.cgColor
                fg = PetTheme.inkSoft
            }
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: fg, .font: PetTheme.font(12.5, .semibold),
            ])
        }
    }
}

/// Small rendered portrait of the pet from its own sprite art (never a
/// stock icon), used as the "face" of the home panel and toasts.
public final class PetAvatarView: NSView {
    public init(image: CGImage?, size: CGFloat = 44, mirrored: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size * 0.75))
        layer = CALayer()
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .nearest
        if mirrored { layer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1)) }
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size * 0.75).isActive = true
    }

    public func setImage(_ image: CGImage?) { layer?.contents = image }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }
}
