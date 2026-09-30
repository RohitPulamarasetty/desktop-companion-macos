import AppKit
import Core
import QuartzCore

/// One pre-decoded animation frame plus its alpha mask. Decoded once per
/// clip into Core Animation's native BGRA format; the alpha mask makes
/// per-pixel hit testing a plain array read.
public struct SpriteFrame {
    public let image: CGImage
    let alpha: [UInt8]
    let width: Int
    let height: Int
    /// Fraction of the frame height (from the top) where the art begins --
    /// used to put speech bubbles just above the pet's head.
    let contentTop: CGFloat

    public init?(decoding source: CGImage) {
        let w = source.width, h = source.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let decoded = ctx.makeImage(), let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var mask = [UInt8](repeating: 0, count: w * h)
        var top = h
        for i in 0..<(w * h) {
            let a = bytes[i * 4 + 3] // BGRA: alpha is byte 3; row 0 = top
            mask[i] = a
            if a > 24 && i / w < top { top = i / w }
        }
        image = decoded
        alpha = mask
        width = w
        height = h
        contentTop = CGFloat(min(top, h)) / CGFloat(h)
    }

    /// `u`,`v` in 0...1 with v = 0 at the TOP of the image.
    func isOpaque(u: CGFloat, v: CGFloat) -> Bool {
        let px = Int(u * CGFloat(width)), py = Int(v * CGFloat(height))
        guard px >= 0, px < width, py >= 0, py < height else { return false }
        return alpha[py * width + px] > 24
    }
}

/// The pet's stage: a transparent view covering its display's usable
/// area. Layer tree (all motion is render-server Core Animation, so this
/// process only wakes to make decisions):
///
///   root
///    └─ anchor   position = the pet's bottom-left; movement legs animate it
///        ├─ body   feedback: bounce, lift, settle, turn, breathing
///        │   └─ sprite  frames (contents keyframes) + facing flip
///        ├─ zzz    sleep indicator
///        └─ bubble thought / speech bubble (follows the pet for free)
public final class CharacterView: NSView {
    private let anchor = CALayer()
    private let body = CALayer()
    private let sprite = CALayer()
    private let zzz = CALayer()
    private var bubble: BubbleLayer?
    private var bubbleAbove = true
    private var badge: CALayer?
    private var badgeText: CATextLayer?
    private var badgeKind = ""
    private var frames: [SpriteFrame] = []
    private var fps: Double = 1
    private var loops = true
    private var animationStart: CFTimeInterval = 0
    public private(set) var isMirrored = false
    public private(set) var petSize: CGSize

    public var onMouseDown: ((NSPoint, Int) -> Void)?
    public var onMouseDragged: ((NSPoint) -> Void)?
    public var onMouseUp: ((NSPoint) -> Void)?
    public var onContextMenu: ((NSEvent) -> Void)?
    public var onMouseMoved: (() -> Void)?
    private var tracking: NSTrackingArea?

    public init(frame frameRect: NSRect, petSize: CGSize) {
        self.petSize = petSize
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = false
        anchor.anchorPoint = .zero
        body.anchorPoint = CGPoint(x: 0.5, y: 0) // squash/bounce/breathe from the feet
        body.addSublayer(sprite)
        anchor.addSublayer(body)
        anchor.addSublayer(zzz)
        layer?.addSublayer(anchor)
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        zzz.isHidden = true
        setPetSize(petSize)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    public override var isFlipped: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { sprite.contentsScale = scale }
    }

    private func noAnim(_ block: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        block()
        CATransaction.commit()
    }

    // MARK: Geometry

    public func setPetSize(_ size: CGSize) {
        petSize = size
        noAnim {
            anchor.bounds = CGRect(origin: .zero, size: size)
            body.bounds = CGRect(origin: .zero, size: size)
            body.position = CGPoint(x: size.width / 2, y: 0)
            sprite.bounds = CGRect(origin: .zero, size: size)
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            layoutZzz()
        }
    }

    /// The pet's bottom-left corner in view coordinates, as currently on screen.
    public var presentedPetOrigin: CGPoint { anchor.presentation()?.position ?? anchor.position }
    public var presentedPetRect: CGRect { CGRect(origin: presentedPetOrigin, size: petSize) }
    public var isGliding: Bool { anchor.animation(forKey: "glide") != nil }

    /// Re-bases the stage: the window moved by `delta` (screen points), so
    /// everything inside shifts the other way and nothing moves on screen.
    /// In-flight glides are re-targeted in the new coordinates.
    public func shiftContent(by delta: CGPoint) {
        guard delta != .zero else { return }
        let glide = anchor.animation(forKey: "glide") as? CABasicAnimation
        let presented = presentedPetOrigin
        noAnim { anchor.position = CGPoint(x: anchor.position.x - delta.x, y: anchor.position.y - delta.y) }
        if let glide, let to = (glide.toValue as? NSValue)?.pointValue {
            let elapsed = CACurrentMediaTime() - glide.beginTime
            let remaining = max(0.05, glide.duration - (glide.beginTime > 0 ? elapsed : 0))
            anchor.removeAnimation(forKey: "glide")
            let a = CABasicAnimation(keyPath: "position")
            a.fromValue = NSValue(point: CGPoint(x: presented.x - delta.x, y: presented.y - delta.y))
            a.toValue = NSValue(point: CGPoint(x: to.x - delta.x, y: to.y - delta.y))
            a.duration = remaining
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            anchor.add(a, forKey: "glide")
        }
    }

    /// Jumps (no animation) -- only for drags, placement and relocation.
    public func setPetOrigin(_ p: CGPoint) {
        anchor.removeAnimation(forKey: "glide")
        noAnim { anchor.position = CGPoint(x: p.x.rounded(), y: p.y.rounded()) }
    }

    /// Glides from where the pet is right now to `p` with the brain's easing
    /// curve (accelerate -> cruise -> decelerate), entirely in the render server.
    public func glide(to p: CGPoint, duration: CFTimeInterval, eased: Bool, braking: Bool = false) {
        let from = presentedPetOrigin
        let target = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = NSValue(point: from)
        anim.toValue = NSValue(point: target)
        anim.duration = max(duration, 0.05)
        // Ease-out quadratic is exactly the cubic bezier (1/3, 2/3, 2/3, 1); it matches MovementLeg.brake.
        let cp = braking ? (Float(1) / 3, Float(2) / 3, Float(2) / 3, Float(1)) : (eased ? MovementEasing.controlPoints : (Float(0), Float(0), Float(1), Float(1)))
        anim.timingFunction = CAMediaTimingFunction(controlPoints: cp.0, cp.1, cp.2, cp.3)
        noAnim { anchor.position = target }
        anchor.add(anim, forKey: "glide")
    }

    public func setIntegerScale(_ integer: Bool) {
        sprite.magnificationFilter = integer ? .nearest : .linear
        sprite.minificationFilter = integer ? .nearest : .linear
    }

    // MARK: Clip playback (render-server driven)

    public func play(_ newFrames: [SpriteFrame], fps newFPS: Double, loop: Bool, mirrored: Bool, startFrame: Int = 0) {
        guard !newFrames.isEmpty else { return }
        frames = newFrames
        fps = max(newFPS, 0.1)
        loops = loop
        noAnim {
            sprite.removeAnimation(forKey: "frames")
            sprite.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
            isMirrored = mirrored
            let start = min(max(startFrame, 0), newFrames.count - 1)
            if newFrames.count == 1 {
                sprite.contents = newFrames[0].image
            } else {
                let ordered = Array(newFrames[start...] + newFrames[..<start])
                let anim = CAKeyframeAnimation(keyPath: "contents")
                anim.values = ordered.map(\.image)
                anim.calculationMode = .discrete
                anim.duration = Double(ordered.count) / fps
                anim.repeatCount = loop ? .infinity : 1
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false
                sprite.contents = loop ? ordered[0].image : newFrames[newFrames.count - 1].image
                sprite.add(anim, forKey: "frames")
            }
            animationStart = CACurrentMediaTime() - Double(start) / fps
        }
    }

    public func setMirrored(_ mirrored: Bool) {
        guard mirrored != isMirrored else { return }
        noAnim { sprite.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity }
        isMirrored = mirrored
    }

    public var currentFrameIndex: Int {
        guard frames.count > 1 else { return 0 }
        let n = Int(max(0, CACurrentMediaTime() - animationStart) * fps)
        return loops ? n % frames.count : min(n, frames.count - 1)
    }

    public var currentImage: CGImage? { frames.isEmpty ? nil : frames[currentFrameIndex].image }

    /// Height above the pet's feet where its art (head) begins.
    public var headHeight: CGFloat {
        guard let f = frames.first else { return petSize.height }
        return petSize.height * (1 - f.contentTop)
    }

    // MARK: Physical feedback (subtle, render server)

    private func bodyKeyframes(_ key: String, _ path: String, _ values: [CGFloat], _ duration: CFTimeInterval) {
        let a = CAKeyframeAnimation(keyPath: path)
        a.values = values
        a.duration = duration
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(values.count - 1, 1))
        body.add(a, forKey: key)
    }

    /// Click: a tiny squash-and-stretch hop.
    public func bounce() {
        bodyKeyframes("bounceY", "transform.scale.y", [1, 0.94, 1.05, 1], 0.28)
        bodyKeyframes("bounceX", "transform.scale.x", [1, 1.05, 0.97, 1], 0.28)
    }

    /// A little symbol (a heart when petted) floats up from the pet and fades.
    public func floatSymbol(_ symbol: String = "❤️") {
        let layer = CATextLayer()
        layer.string = symbol
        layer.fontSize = max(14, petSize.height * 0.22)
        layer.alignmentMode = .center
        layer.contentsScale = 2
        layer.bounds = CGRect(x: 0, y: 0, width: 40, height: 30)
        let x = petSize.width * CGFloat.random(in: 0.35...0.65)
        layer.position = CGPoint(x: x, y: petSize.height + 4)
        anchor.addSublayer(layer)
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = petSize.height + 4
        rise.toValue = petSize.height + 44
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 1.2
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.opacity = 0
        layer.add(group, forKey: "float")
        CATransaction.commit()
    }

    /// Arriving somewhere: a small settle.
    public func settle() {
        bodyKeyframes("settle", "transform.scale.y", [1, 0.97, 1.01, 1], 0.3)
    }

    /// Turning around: a quick horizontal pinch that reads as a turn.
    public func turn() {
        bodyKeyframes("turn", "transform.scale.x", [1, 0.82, 1], 0.2)
    }

    /// Picked up: lifted slightly (scale + soft shadow) while dragged.
    public func setLifted(_ lifted: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        body.transform = lifted ? CATransform3DMakeScale(1.06, 1.06, 1) : CATransform3DIdentity
        body.shadowColor = NSColor.black.cgColor
        body.shadowOpacity = lifted ? 0.25 : 0
        body.shadowRadius = 6
        body.shadowOffset = CGSize(width: 0, height: -4)
        CATransaction.commit()
        if !lifted {
            bodyKeyframes("drop", "transform.scale.y", [1.06, 0.93, 1.03, 1], 0.35)
        }
    }

    /// Switching character: the old look shrinks away, the new one pops in.
    public func swapOut(then: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setCompletionBlock(then)
        body.opacity = 0
        body.transform = CATransform3DMakeScale(0.7, 0.7, 1)
        CATransaction.commit()
    }

    public func swapIn() {
        noAnim {
            body.opacity = 1
            body.transform = CATransform3DIdentity
        }
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.6
        s.toValue = 1
        s.damping = 11
        s.stiffness = 220
        s.duration = s.settlingDuration
        body.add(s, forKey: "popIn")
        let f = CABasicAnimation(keyPath: "opacity")
        f.fromValue = 0
        f.toValue = 1
        f.duration = 0.15
        body.add(f, forKey: "fadeIn")
    }

    public func setBreathing(_ on: Bool) {
        let key = "breathe"
        if on {
            guard body.animation(forKey: key) == nil else { return }
            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = 1.0
            anim.toValue = 1.035
            anim.duration = 1.9
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            body.add(anim, forKey: key)
        } else if body.animation(forKey: key) != nil {
            body.removeAnimation(forKey: key)
        }
    }

    public func playTwitch() {
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        let x = sprite.position.x
        anim.values = [x, x + 1.5, x - 1.0, x + 0.5, x]
        anim.keyTimes = [0, 0.2, 0.45, 0.7, 1]
        anim.duration = 0.4
        sprite.add(anim, forKey: "twitch")
    }

    public func playEarFlick() {
        let anim = CAKeyframeAnimation(keyPath: "position.y")
        let y = sprite.position.y
        anim.values = [y, y + 1.2, y, y + 0.8, y]
        anim.duration = 0.35
        sprite.add(anim, forKey: "earFlick")
    }

    // MARK: Sleep indicator (💤)

    private func layoutZzz() {
        zzz.frame = CGRect(x: petSize.width * 0.62, y: headHeight * 0.85, width: 30, height: 40)
    }

    public func setSleepIndicator(_ on: Bool) {
        guard on == zzz.isHidden else { return }
        noAnim {
            zzz.isHidden = !on
            zzz.sublayers?.forEach { $0.removeFromSuperlayer() }
            layoutZzz()
        }
        guard on else { return }
        let scale = window?.backingScaleFactor ?? 2
        for i in 0..<3 {
            let z = CATextLayer()
            z.string = "z"
            z.font = PetTheme.font(12, .bold)
            z.fontSize = CGFloat(10 + i * 3)
            z.foregroundColor = NSColor(srgbRed: 0.55, green: 0.62, blue: 0.85, alpha: 1).cgColor
            z.contentsScale = scale
            z.alignmentMode = .center
            z.frame = CGRect(x: 0, y: 0, width: 16, height: 18)
            z.opacity = 0
            zzz.addSublayer(z)
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: CGPoint(x: 6, y: 4))
            rise.toValue = NSValue(point: CGPoint(x: 18, y: 34))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0.9, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 2.7
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.9
            z.add(group, forKey: "float")
        }
    }

    // MARK: Bubbles

    /// Shows a bubble above (or, near the top of the screen, below) the pet.
    /// It is a child of the pet's anchor, so it follows the pet exactly.
    /// Area (view coordinates) bubbles must stay inside -- the display's
    /// usable area, which can extend beyond this (small) stage view.
    public var bubbleLimits: CGRect?

    public func showBubble(_ content: BubbleLayer.Content) {
        hideBubble(animated: false)
        let b = BubbleLayer(content: content, scale: window?.backingScaleFactor ?? 2, appearance: effectiveAppearance)
        let size = b.bounds.size
        let petOrigin = presentedPetOrigin
        // Horizontal: centred on the pet, kept inside the stage.
        var localX = (petSize.width - size.width) / 2
        let limits = bubbleLimits ?? bounds
        let minLocal = limits.minX - petOrigin.x + 6, maxLocal = limits.maxX - petOrigin.x - size.width - 6
        localX = min(max(localX, minLocal), max(minLocal, maxLocal))
        // Vertical: above the head if it fits, otherwise below the feet.
        let above = petOrigin.y + headHeight + 4 + size.height <= limits.maxY
        bubbleAbove = above
        let localY = above ? headHeight + 4 : -size.height - 4
        b.setTail(pointingDown: above, atX: petSize.width / 2 - localX)
        noAnim {
            b.anchorPoint = CGPoint(x: (petSize.width / 2 - localX) / size.width, y: above ? 0 : 1)
            b.position = CGPoint(x: petSize.width / 2, y: above ? localY : localY + size.height)
        }
        anchor.addSublayer(b)
        bubble = b
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.55
        spring.toValue = 1
        spring.damping = 13
        spring.stiffness = 260
        spring.duration = spring.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        b.add(spring, forKey: "in")
        b.add(fade, forKey: "fade")
    }

    public func hideBubble(animated: Bool) {
        guard let b = bubble else { return }
        bubble = nil
        guard animated else { b.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setCompletionBlock { b.removeFromSuperlayer() }
        b.opacity = 0
        b.transform = CATransform3DMakeScale(0.9, 0.9, 1)
        CATransaction.commit()
    }

    public var hasBubble: Bool { bubble != nil }

    /// Keeps a visible bubble on screen for where the pet is heading (and
    /// where it is now): shifts it horizontally, tail still on the pet.
    public func reclampBubble(forPetOriginsAt origins: [CGPoint]) {
        guard let b = bubble else { return }
        let limits = bubbleLimits ?? bounds
        let w = b.bounds.width
        var lo = -CGFloat.greatestFiniteMagnitude, hi = CGFloat.greatestFiniteMagnitude
        for o in origins {
            lo = max(lo, limits.minX - o.x + 6)
            hi = min(hi, limits.maxX - o.x - w - 6)
        }
        let preferred = (petSize.width - w) / 2
        let localX = lo <= hi ? min(max(preferred, lo), hi) : lo
        let tailX = petSize.width / 2 - localX
        b.setTail(pointingDown: bubbleAbove, atX: tailX, reshift: false)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        b.anchorPoint = CGPoint(x: tailX / w, y: b.anchorPoint.y)
        CATransaction.commit()
    }

    // MARK: Status badge (e.g. "Following")

    /// A small pill beside the pet (e.g. "⏱ 24:37"), attached to it so it
    /// follows every move. `nil` hides it. Text updates don't re-animate.
    public func setBadge(_ text: String?, kind: String = "", emphasis: Bool = false) {
        guard let text else {
            guard let b = badge else { return }
            badge = nil
            badgeText = nil
            badgeKind = ""
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setCompletionBlock { b.removeFromSuperlayer() }
            b.opacity = 0
            b.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            CATransaction.commit()
            return
        }
        let font = PetTheme.mono(11.5, .semibold)
        let width = ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) + 16
        let isNew = badge == nil
        let pill = badge ?? CALayer()
        let label = badgeText ?? CATextLayer()
        var fill = CGColor.black, ink = CGColor.white, border = CGColor.black
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = (emphasis ? PetTheme.accent : PetTheme.card).cgColor
            ink = (emphasis ? NSColor.white : PetTheme.ink).cgColor
            border = PetTheme.cardBorder.cgColor
        }
        noAnim {
            pill.bounds = CGRect(x: 0, y: 0, width: width, height: 20)
            pill.cornerRadius = 10
            pill.backgroundColor = fill
            pill.borderWidth = emphasis ? 0 : 1
            pill.borderColor = border
            pill.shadowColor = NSColor.black.cgColor
            pill.shadowOpacity = 0.15
            pill.shadowRadius = 3
            pill.shadowOffset = CGSize(width: 0, height: -1)
            label.string = text
            label.font = font
            label.fontSize = font.pointSize
            label.foregroundColor = ink
            label.alignmentMode = .center
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.frame = CGRect(x: 0, y: 2, width: width, height: 16)
            // Beside the pet at chest height; on the left if near the right edge.
            let o = presentedPetOrigin
            let limits = bubbleLimits ?? bounds
            let rightX = petSize.width * 0.92 + width / 2
            let onRight = o.x + rightX + width / 2 < limits.maxX - 4
            pill.position = CGPoint(x: onRight ? rightX : petSize.width * 0.08 - width / 2, y: headHeight * 0.45)
        }
        if isNew {
            pill.addSublayer(label)
            anchor.addSublayer(pill)
            badge = pill
            badgeText = label
            let s = CASpringAnimation(keyPath: "transform.scale")
            s.fromValue = 0.5
            s.toValue = 1
            s.damping = 12
            s.stiffness = 240
            s.duration = s.settlingDuration
            pill.add(s, forKey: "in")
        }
        if kind != badgeKind || emphasis {
            badgeKind = kind
            if emphasis && !isNew {
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [1, 1.25, 0.95, 1]
                pop.duration = 0.4
                pill.add(pop, forKey: "pop")
            }
        }
    }

    public var hasBadge: Bool { badge != nil }

    /// Re-picks the badge's side for where the pet is heading.
    public func repositionBadge(forPetOrigin o: CGPoint) {
        guard let pill = badge else { return }
        let width = pill.bounds.width
        let limits = bubbleLimits ?? bounds
        let rightX = petSize.width * 0.92 + width / 2
        let onRight = o.x + rightX + width / 2 < limits.maxX - 4
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        pill.position = CGPoint(x: onRight ? rightX : petSize.width * 0.08 - width / 2, y: headHeight * 0.45)
        CATransaction.commit()
    }
    public var bubbleHasActions: Bool { bubble?.hasActions ?? false }

    // MARK: Accessibility

    /// The companion is exposed as one labelled group. (The reminder bubble's buttons are drawn, not controls, and are
    /// not yet exposed to VoiceOver: a known gap, listed in the release notes.)
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .group }
    public override func accessibilityLabel() -> String? { "Desktop Companion" }

    /// Which bubble action (if any) is under a point in view coordinates;
    /// -1 = inside the bubble but not on a button.
    public func bubbleAction(at point: NSPoint) -> Int? {
        guard let b = bubble else { return nil }
        let p = b.convert(point, from: layer)
        guard b.bounds.contains(p) else { return nil }
        return b.action(at: p) ?? -1
    }

    // MARK: Hit testing

    /// Alpha-based hit test against the pet as currently on screen
    /// (position, frame, flip).
    public func isOpaque(atLocalPoint point: NSPoint) -> Bool {
        guard !frames.isEmpty else { return false }
        let o = presentedPetOrigin
        let local = CGPoint(x: point.x - o.x, y: point.y - o.y)
        guard local.x >= 0, local.x < petSize.width, local.y >= 0, local.y < petSize.height else { return false }
        var u = local.x / petSize.width
        if isMirrored { u = 1 - u }
        let v = 1 - local.y / petSize.height
        return frames[currentFrameIndex].isOpaque(u: u, v: v)
    }

    // MARK: Events

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    public override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    public override func mouseExited(with event: NSEvent) { onMouseMoved?() }

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onContextMenu?(event); return }
        onMouseDown?(NSEvent.mouseLocation, event.clickCount)
    }

    public override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
    public override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }
    public override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }
}

/// A thought (💭) or speech (💬) bubble drawn with layers: a rounded card
/// with a tail pointing at the pet, text, and optional pill buttons.
public final class BubbleLayer: CALayer {
    public enum Style { case speech, thought, celebration }

    public struct Content {
        public var text: String
        public var style: Style
        public var actions: [(title: String, primary: Bool)]
        public init(text: String, style: Style = .speech, actions: [(title: String, primary: Bool)] = []) {
            self.text = text
            self.style = style
            self.actions = actions
        }
    }

    private let shape = CAShapeLayer()
    private var buttonFrames: [CGRect] = []
    private let bubbleStyle: Style
    private let fill: CGColor
    private let stroke: CGColor
    public var hasActions: Bool { !buttonFrames.isEmpty }
    static let tail: CGFloat = 9

    public init(content: Content, scale: CGFloat, appearance: NSAppearance) {
        bubbleStyle = content.style
        var fillColor = CGColor.white, strokeColor = CGColor.black, ink = CGColor.black, soft = CGColor.black, accent = CGColor.black, accentSoft = CGColor.black
        let celebrate = content.style == .celebration
        appearance.performAsCurrentDrawingAppearance {
            fillColor = (celebrate ? PetTheme.accent : PetTheme.card).cgColor
            strokeColor = (celebrate ? PetTheme.accent : PetTheme.cardBorder).cgColor
            ink = (celebrate ? NSColor.white : PetTheme.ink).cgColor
            soft = PetTheme.inkSoft.cgColor
            accent = PetTheme.accent.cgColor
            accentSoft = PetTheme.accentSoft.cgColor
        }
        fill = fillColor
        stroke = strokeColor
        super.init()
        _ = soft

        let maxText: CGFloat = 200
        let pad: CGFloat = 11
        let font = PetTheme.font(12.5, .semibold)
        let attributed = NSAttributedString(string: content.text, attributes: [.font: font])
        let textSize = attributed.boundingRect(with: CGSize(width: maxText, height: 400), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let textW = ceil(textSize.width), textH = ceil(textSize.height)

        // Buttons
        let buttonFont = PetTheme.font(11.5, .semibold)
        let buttonH: CGFloat = 22
        var buttonWidths: [CGFloat] = []
        for a in content.actions {
            let w = ceil(NSAttributedString(string: a.title, attributes: [.font: buttonFont]).size().width) + 20
            buttonWidths.append(w)
        }
        let buttonsW = buttonWidths.reduce(0, +) + CGFloat(max(0, buttonWidths.count - 1)) * 6
        let contentW = max(textW, buttonsW)
        let width = contentW + pad * 2
        let height = textH + pad * 2 + (content.actions.isEmpty ? 0 : buttonH + 8)
        let tail = BubbleLayer.tail
        bounds = CGRect(x: 0, y: 0, width: width, height: height + tail)

        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = 1
        shape.shadowColor = CGColor(gray: 0, alpha: 1)
        shape.shadowOpacity = 0.18
        shape.shadowRadius = 5
        shape.shadowOffset = CGSize(width: 0, height: -1.5)
        addSublayer(shape)

        let text = CATextLayer()
        text.string = attributed.string
        text.font = font
        text.fontSize = font.pointSize
        text.foregroundColor = ink
        text.isWrapped = true
        text.alignmentMode = content.actions.isEmpty ? .center : .left
        text.contentsScale = scale
        text.frame = CGRect(x: pad, y: tail + height - pad - textH, width: contentW, height: textH)
        addSublayer(text)

        var bx = pad
        for (i, a) in content.actions.enumerated() {
            let r = CGRect(x: bx, y: tail + pad, width: buttonWidths[i], height: buttonH)
            let pill = CALayer()
            pill.frame = r
            pill.cornerRadius = buttonH / 2
            // On the caramel celebration card the primary pill is white.
            pill.backgroundColor = celebrate ? (a.primary ? CGColor.white : CGColor(gray: 1, alpha: 0.22)) : (a.primary ? accent : accentSoft)
            let label = CATextLayer()
            label.string = a.title
            label.font = buttonFont
            label.fontSize = buttonFont.pointSize
            label.foregroundColor = celebrate ? (a.primary ? accent : CGColor.white) : (a.primary ? CGColor.white : ink)
            label.alignmentMode = .center
            label.contentsScale = scale
            label.frame = CGRect(x: 0, y: (buttonH - 15) / 2 - 1, width: r.width, height: 16)
            pill.addSublayer(label)
            addSublayer(pill)
            buttonFrames.append(r)
            bx += buttonWidths[i] + 6
        }
        setTail(pointingDown: true, atX: width / 2)
    }

    public override init(layer: Any) {
        let other = layer as? BubbleLayer
        bubbleStyle = other?.bubbleStyle ?? .speech
        fill = other?.fill ?? .white
        stroke = other?.stroke ?? .black
        super.init(layer: layer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Redraws the outline with the tail at `tailX` (bubble coordinates),
    /// on the bottom (bubble above the pet) or top (bubble below).
    private var shiftedForUpTail = false

    func setTail(pointingDown: Bool, atX tailX: CGFloat, reshift: Bool = true) {
        let tail = BubbleLayer.tail
        let w = bounds.width, h = bounds.height - tail
        let bodyRect = CGRect(x: 0, y: pointingDown ? tail : 0, width: w, height: h)
        let path = CGMutablePath()
        path.addRoundedRect(in: bodyRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 12, cornerHeight: 12)
        let tx = min(max(tailX, 14), w - 14)
        switch bubbleStyle {
        case .speech, .celebration:
            if pointingDown {
                path.move(to: CGPoint(x: tx - 7, y: tail + 1))
                path.addLine(to: CGPoint(x: tx, y: 0))
                path.addLine(to: CGPoint(x: tx + 7, y: tail + 1))
            } else {
                path.move(to: CGPoint(x: tx - 7, y: h - 1))
                path.addLine(to: CGPoint(x: tx, y: h + tail))
                path.addLine(to: CGPoint(x: tx + 7, y: h - 1))
            }
        case .thought:
            let y1 = pointingDown ? tail * 0.45 : h + tail * 0.55
            let y2 = pointingDown ? tail * 0.05 : h + tail * 0.95
            path.addEllipse(in: CGRect(x: tx - 4, y: y1 - 3, width: 7, height: 6))
            path.addEllipse(in: CGRect(x: tx - 1.5, y: y2 - 2, width: 4, height: 4))
        }
        shape.path = path
        shape.frame = bounds
        // Content sits above the tail when pointing down; shift it when up (once).
        if !pointingDown && reshift && !shiftedForUpTail {
            shiftedForUpTail = true
            for l in sublayers ?? [] where l !== shape { l.frame.origin.y -= tail }
            buttonFrames = buttonFrames.map { $0.offsetBy(dx: 0, dy: -tail) }
        }
    }

    func action(at p: CGPoint) -> Int? {
        buttonFrames.firstIndex { $0.insetBy(dx: -3, dy: -3).contains(p) }
    }
}

