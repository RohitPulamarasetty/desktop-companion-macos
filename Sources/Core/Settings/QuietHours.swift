import Foundation

/// A daily quiet-hours window (e.g. 22:00-07:00): during it the companion
/// doesn't bark, sprint or chat.
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
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour // wraps past midnight, e.g. 22 -> 7
    }
}
