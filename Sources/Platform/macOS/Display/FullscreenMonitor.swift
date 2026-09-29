import AppKit

/// Decides whether the pet should step aside for what the user is doing,
/// according to their opt-in exceptions (all off by default = always
/// visible). Event-driven: re-evaluates only when the frontmost app changes,
/// the active Space changes (entering/leaving full screen switches Space),
/// or the screen configuration changes -- never on a timer.
///
/// The previous implementation called `CGWindowListCopyWindowInfo` once per
/// second forever (allocating a dictionary per on-screen window each time),
/// which profiling showed as the single largest app-level CPU cost at idle
/// -- even though the default behavior is "always visible" and the answer
/// was never used to hide anything.
///
/// Privacy: reads only the frontmost app's bundle identifier, its declared
/// App Store category (from its Info.plist), and its windows' bounds.
/// Nothing is stored or logged.
public final class FullscreenMonitor {
    public struct Policy: Equatable {
        public var hideInFullscreen = false
        public var hideInPresentations = false
        public var hideInGames = false
        public init(hideInFullscreen: Bool = false, hideInPresentations: Bool = false, hideInGames: Bool = false) {
            self.hideInFullscreen = hideInFullscreen
            self.hideInPresentations = hideInPresentations
            self.hideInGames = hideInGames
        }
        var isAlwaysVisible: Bool { !hideInFullscreen && !hideInPresentations && !hideInGames }
    }

    /// Called with `true` when the pet should hide, `false` when it may show.
    public var onShouldHideChanged: ((Bool) -> Void)?
    /// Called on every Space change (the pet window re-asserts itself).
    public var onActiveSpaceChanged: (() -> Void)?

    public var policy = Policy() {
        didSet { if policy != oldValue { evaluate() } }
    }

    private var lastDecision = false
    private var gameCategoryCache: [String: Bool] = [:]
    private var pendingRecheck: DispatchWorkItem?

    private static let presentationBundleIDs: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "com.google.Keynote",
        "com.apple.Keynote", "org.libreoffice.script",
    ]

    public init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appOrSpaceChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appOrSpaceChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func spaceChanged() {
        onActiveSpaceChanged?()
        appOrSpaceChanged()
    }

    @objc private func appOrSpaceChanged() {
        evaluate()
        // The window list lags the notification slightly during the
        // full-screen transition animation; check once more afterwards.
        pendingRecheck?.cancel()
        guard !policy.isAlwaysVisible else { return }
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pendingRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    public func evaluate() {
        let hide = policy.isAlwaysVisible ? false : shouldHide()
        guard hide != lastDecision else { return }
        lastDecision = hide
        onShouldHideChanged?(hide)
    }

    private func shouldHide() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        if policy.hideInGames, isGame(app) { return true }
        let fullscreen = (policy.hideInFullscreen || policy.hideInPresentations) && Self.hasFullscreenWindow(pid: app.processIdentifier)
        if policy.hideInFullscreen && fullscreen { return true }
        if policy.hideInPresentations && fullscreen, let id = app.bundleIdentifier, Self.presentationBundleIDs.contains(id) { return true }
        return false
    }

    private func isGame(_ app: NSRunningApplication) -> Bool {
        let key = app.bundleIdentifier ?? app.bundleURL?.path ?? ""
        if let cached = gameCategoryCache[key] { return cached }
        var result = false
        if let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary,
           let category = info["LSApplicationCategoryType"] as? String {
            result = category.lowercased().contains("games")
        }
        gameCategoryCache[key] = result
        return result
    }

    /// True if the app owns a normal-layer window covering an entire display.
    private static func hasFullscreenWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else { return false }
        let screenSizes = NSScreen.screens.map { $0.frame.size }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if screenSizes.contains(where: { size.width >= $0.width && size.height >= $0.height }) { return true }
        }
        return false
    }

    deinit {
        pendingRecheck?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
