import UserNotifications

/// Optional macOS notification banners for reminders (off by default; the
/// permission is requested only when the user turns the setting on).
public final class NotificationScheduler {
    public init() {}

    public func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("[DesktopCompanion] Notification authorization error: %@", "\(error)") }
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func post(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error { NSLog("[DesktopCompanion] Failed to post notification: %@", "\(error)") }
        }
    }
}
