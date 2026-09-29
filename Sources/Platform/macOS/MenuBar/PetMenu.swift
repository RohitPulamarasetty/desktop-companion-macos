import AppKit
import Core

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = (modifiers.isEmpty && !key.isEmpty) ? .command : modifiers
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

/// What the menu shows. Built by the app layer from the live brain.
public struct PetMenuModel {
    public var petName: String
    public var petStatus: String
    public var isAsleep: Bool
    public var petHidden: Bool
    public var includeAppItems: Bool
    public var mode: PetMode
    public var currentActivity: Activity?
    public var tricks: [Trick]
    public var availability: (Activity) -> ActivityAvailability

    public init(petName: String, petStatus: String, isAsleep: Bool, petHidden: Bool, includeAppItems: Bool,
                mode: PetMode, currentActivity: Activity?, tricks: [Trick], availability: @escaping (Activity) -> ActivityAvailability) {
        self.petName = petName
        self.petStatus = petStatus
        self.isAsleep = isAsleep
        self.petHidden = petHidden
        self.includeAppItems = includeAppItems
        self.mode = mode
        self.currentActivity = currentActivity
        self.tricks = tricks
        self.availability = availability
    }
}

public struct PetMenuActions {
    public var startActivity: (Activity, Double?) -> Void = { _, _ in }
    public var stopActivity: () -> Void = {}
    public var openDashboard: () -> Void = {}
    public var doTrick: (Trick) -> Void = { _ in }
    public var chooseCharacter: () -> Void = {}
    public var openSettings: () -> Void = {}
    public var toggleSleep: () -> Void = {}
    public var toggleHidden: () -> Void = {}
    public var setMode: (PetMode) -> Void = { _ in }
    public var openAbout: () -> Void = {}
    public var quit: () -> Void = {}
    public init() {}
}

public enum PetMenu {
    /// Global shortcuts are the same combination with a different letter.
    public static let shortcutModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    public static func build(_ m: PetMenuModel, _ a: PetMenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(string: "\(m.petName) · \(m.petStatus)", attributes: [
            .font: PetTheme.font(12.5, .semibold), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Dashboard", key: "d", modifiers: shortcutModifiers) { a.openDashboard() })

        let activities = NSMenuItem(title: "Activities", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        func note(_ availability: ActivityAvailability) -> String {
            switch availability {
            case .cooldown(let s): return "  (in \(Int(s.rounded(.up)))s)"
            case .needsCursor: return "  (cursor not on this display)"
            default: return ""
            }
        }
        for activity in [Activity.followCursor, .comeHere, .play, .explore, .hideAndSeek] {
            let availability = m.availability(activity)
            let running = m.currentActivity == activity
            if activity == .followCursor {
                let title = running ? "Stop Following" : "Follow Cursor"
                sub.addItem(ClosureMenuItem(title, key: "f", modifiers: shortcutModifiers, enabled: running || availability == .available) {
                    running ? a.stopActivity() : a.startActivity(.followCursor, nil)
                })
                if !running {
                    sub.addItem(ClosureMenuItem("Follow for 2 Minutes", enabled: availability == .available) { a.startActivity(.followCursor, 120) })
                }
            } else {
                let key = activity == .comeHere ? "h" : ""
                sub.addItem(ClosureMenuItem(activity.displayName + (availability == .available ? "" : note(availability)),
                                            key: key, modifiers: key.isEmpty ? [] : shortcutModifiers,
                                            checked: running, enabled: availability == .available) {
                    a.startActivity(activity, nil)
                })
            }
        }
        let stayRunning = m.currentActivity == .stay
        sub.addItem(ClosureMenuItem(stayRunning ? "Stop Staying" : "Stay Here for 5 Minutes", checked: stayRunning) {
            stayRunning ? a.stopActivity() : a.startActivity(.stay, nil)
        })
        sub.addItem(.separator())
        sub.addItem(ClosureMenuItem("Stop Activity", key: "s", modifiers: shortcutModifiers, enabled: m.currentActivity != nil) { a.stopActivity() })
        activities.submenu = sub
        menu.addItem(activities)

        if !m.tricks.isEmpty {
            let tricks = NSMenuItem(title: "Tricks", action: nil, keyEquivalent: "")
            let tm = NSMenu()
            tm.autoenablesItems = false
            for t in m.tricks { tm.addItem(ClosureMenuItem(t.displayName) { a.doTrick(t) }) }
            tricks.submenu = tm
            menu.addItem(tricks)
        }

        let mode = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let mm = NSMenu()
        mm.autoenablesItems = false
        for option in PetMode.allCases {
            mm.addItem(ClosureMenuItem(option.displayName, checked: m.mode == option) { a.setMode(option) })
        }
        mode.submenu = mm
        menu.addItem(mode)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Choose Companion…") { a.chooseCharacter() })
        menu.addItem(ClosureMenuItem(m.isAsleep ? "Wake Up" : "Sleep") { a.toggleSleep() })
        menu.addItem(ClosureMenuItem(m.petHidden ? "Show Companion" : "Hide Companion", key: "p", modifiers: shortcutModifiers) { a.toggleHidden() })
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { a.openSettings() })

        menu.addItem(.separator())
        if m.includeAppItems {
            menu.addItem(ClosureMenuItem("About Desktop Companion") { a.openAbout() })
        }
        menu.addItem(ClosureMenuItem("Quit", key: "q") { a.quit() })
        return menu
    }
}
