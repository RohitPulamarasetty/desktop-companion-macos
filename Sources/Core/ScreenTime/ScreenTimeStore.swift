import Foundation

/// Local-only daily totals: active seconds, idle seconds, and focus seconds.
/// Never stores app names, window titles, URLs, keystrokes, or any content
/// -- only accumulated durations the platform layer reports (see
/// docs/PRIVACY.md). One row per calendar day.
public final class ScreenTimeStore {
    private let db: SQLiteDatabase
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS screen_time_daily (
                day TEXT PRIMARY KEY,
                activeSeconds REAL NOT NULL DEFAULT 0,
                idleSeconds REAL NOT NULL DEFAULT 0,
                focusSeconds REAL NOT NULL DEFAULT 0
            )
            """)
    }

    private func ensureRow(day: String) throws {
        try db.execute("INSERT OR IGNORE INTO screen_time_daily (day, activeSeconds, idleSeconds, focusSeconds) VALUES (?, 0, 0, 0)", bindings: [.text(day)])
    }

    public func addActiveSeconds(_ seconds: Double, date: Date = Date()) throws {
        let day = Self.dayFormatter.string(from: date)
        try ensureRow(day: day)
        try db.execute("UPDATE screen_time_daily SET activeSeconds = activeSeconds + ? WHERE day = ?", bindings: [.double(seconds), .text(day)])
    }

    public func addIdleSeconds(_ seconds: Double, date: Date = Date()) throws {
        let day = Self.dayFormatter.string(from: date)
        try ensureRow(day: day)
        try db.execute("UPDATE screen_time_daily SET idleSeconds = idleSeconds + ? WHERE day = ?", bindings: [.double(seconds), .text(day)])
    }

    public func addFocusSeconds(_ seconds: Double, date: Date = Date()) throws {
        let day = Self.dayFormatter.string(from: date)
        try ensureRow(day: day)
        try db.execute("UPDATE screen_time_daily SET focusSeconds = focusSeconds + ? WHERE day = ?", bindings: [.double(seconds), .text(day)])
    }

    public struct DailyTotals: Equatable {
        public let activeSeconds: Double
        public let idleSeconds: Double
        public let focusSeconds: Double

        public init(activeSeconds: Double, idleSeconds: Double, focusSeconds: Double) {
            self.activeSeconds = activeSeconds
            self.idleSeconds = idleSeconds
            self.focusSeconds = focusSeconds
        }
    }

    public func totals(date: Date = Date()) throws -> DailyTotals {
        let day = Self.dayFormatter.string(from: date)
        var result = DailyTotals(activeSeconds: 0, idleSeconds: 0, focusSeconds: 0)
        try db.query("SELECT activeSeconds, idleSeconds, focusSeconds FROM screen_time_daily WHERE day = ?", bindings: [.text(day)]) { row in
            result = DailyTotals(activeSeconds: row.double(0), idleSeconds: row.double(1), focusSeconds: row.double(2))
        }
        return result
    }
}

/// Pure classification logic: given seconds-since-last-input (from the
/// platform layer's idle-time reading) decide active vs idle. No AppKit.
public enum ActivityClassifier {
    public static func isActive(secondsSinceLastInput: Double, idleThresholdSeconds: Double = 90) -> Bool {
        secondsSinceLastInput < idleThresholdSeconds
    }
}
