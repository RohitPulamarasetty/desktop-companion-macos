import AppKit
import Core

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

// `PetMenuModel` and `PetMenuActions` used to be defined here. They moved to
// `Sources/Core/Platform/PlatformMenu.swift` (pure Swift, no AppKit) so a
// `PlatformTray` conformer on another platform can build its own native
// menu from the same model/actions without depending on AppKit -- see
// `docs/PLATFORM_PROTOCOLS.md`. Only the AppKit `NSMenu` builder stays here.

public enum PetMenu {
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

        menu.addItem(ClosureMenuItem("Open Companion", key: "o") { a.openHome(.today) })
        menu.addItem(ClosureMenuItem("Tasks") { a.openHome(.tasks) })

        let focus = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
        let fm = NSMenu()
        fm.autoenablesItems = false
        switch m.focusPhase {
        case .idle:
            fm.addItem(ClosureMenuItem("Focus 25 min") { a.startFocus(25, 5) })
            fm.addItem(ClosureMenuItem("Focus 50 min") { a.startFocus(50, 10) })
        case .focusing, .onBreak:
            fm.addItem(ClosureMenuItem(CompanionPanelController.focusText(m.focusPhase), enabled: false) {})
            fm.addItem(ClosureMenuItem("Pause") { a.pauseFocus() })
            fm.addItem(ClosureMenuItem("Stop") { a.stopFocus() })
        case .paused:
            fm.addItem(ClosureMenuItem("Resume") { a.resumeFocus() })
            fm.addItem(ClosureMenuItem("Stop") { a.stopFocus() })
        }
        focus.submenu = fm
        menu.addItem(focus)
        menu.addItem(ClosureMenuItem("Wellness") { a.openHome(.wellness) })
        menu.addItem(.separator())

        let mode = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let mm = NSMenu()
        mm.autoenablesItems = false
        for option in PetMode.allCases {
            mm.addItem(ClosureMenuItem(option.displayName, checked: m.companionMode == option) { a.setMode(option) })
        }
        mode.submenu = mm
        menu.addItem(mode)

        menu.addItem(ClosureMenuItem("Choose Companion…") { a.chooseCharacter() })
        menu.addItem(ClosureMenuItem("Pet Settings…", key: ",") { a.openSettings() })
        menu.addItem(ClosureMenuItem(m.isAsleep ? "Wake Up" : "Sleep") { a.toggleSleep() })
        menu.addItem(ClosureMenuItem(m.petHidden ? "Show Pet" : "Hide Pet") { a.toggleHidden() })

        menu.addItem(.separator())
        if m.includeAppItems {
            menu.addItem(ClosureMenuItem("About \(AboutWindowController.productName)") { a.openAbout() })
            menu.addItem(ClosureMenuItem("Diagnostics…") { a.openDiagnostics() })
        }
        menu.addItem(ClosureMenuItem("Quit", key: "q") { a.quit() })
        return menu
    }
}
