import UserNotifications
import Core

/// Thin wrapper over UNUserNotificationCenter. Requires the app to run from
/// a proper .app bundle with a CFBundleIdentifier (see scripts/package_app.sh)
/// -- a bare Mach-O binary cannot request notification authorization.
public final class NotificationScheduler: PlatformNotifications {
    public init() {}

    public func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("[DesktopCompanion] Notification authorization error: %@", "\(error)")
            }
            completion(granted)
        }
    }

    /// `PlatformNotifications` conformance: posts a native banner for a
    /// due reminder. The pet-bubble presentation path (the *other* way a
    /// `DueReminder` can reach the user) stays in `Sources/App/AppDelegate.swift`
    /// -- this protocol only prescribes presenting one, not which idiom.
    public func present(_ reminder: DueReminder) {
        postNow(identifier: reminder.id, title: reminder.title, body: reminder.kind.rawValue)
    }

    public func postNow(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[DesktopCompanion] Failed to post notification: %@", "\(error)")
            }
        }
    }
}
