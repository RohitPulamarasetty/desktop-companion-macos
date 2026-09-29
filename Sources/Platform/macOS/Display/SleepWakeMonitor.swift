import AppKit

/// Pauses everything that ticks while the Mac sleeps, the displays sleep,
/// or the user session is switched away (fast user switching / login
/// window) -- zero wakeups while nobody can see the pet.
public final class SleepWakeMonitor {
    public var onSleep: (() -> Void)?
    public var onWake: (() -> Void)?
    public var onDisplaysSleep: (() -> Void)?
    public var onDisplaysWake: (() -> Void)?

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDisplaysSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDisplaysWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDisplaysSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDisplaysWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func handleSleep() { onSleep?() }
    @objc private func handleWake() { onWake?() }
    @objc private func handleDisplaysSleep() { onDisplaysSleep?() }
    @objc private func handleDisplaysWake() { onDisplaysWake?() }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
