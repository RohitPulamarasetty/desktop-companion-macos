import Foundation

public struct ReminderItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var fireDate: Date
    public var recurrence: RecurrenceRule
    public var isCompleted: Bool
    public var snoozedUntil: Date?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        fireDate: Date,
        recurrence: RecurrenceRule = .none,
        isCompleted: Bool = false,
        snoozedUntil: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.fireDate = fireDate
        self.recurrence = recurrence
        self.isCompleted = isCompleted
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
    }

    /// True if this reminder should fire right now: due, not completed, and
    /// not currently snoozed past `referenceDate`.
    public func isDue(referenceDate: Date = Date()) -> Bool {
        guard !isCompleted else { return false }
        if let snoozedUntil, snoozedUntil > referenceDate { return false }
        return fireDate <= referenceDate
    }
}

/// A simple daily quiet-hours window (e.g. 22:00-07:00). Reminders due
/// inside this window are held until it ends rather than firing/notifying.
public struct QuietHours: Equatable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        } else {
            // wraps past midnight, e.g. 22 -> 7
            return hour >= startHour || hour < endHour
        }
    }
}
