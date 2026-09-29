import Foundation

public struct FocusSessionRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let plannedFocusMinutes: Double
    public let completedFully: Bool

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, plannedFocusMinutes: Double, completedFully: Bool) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedFocusMinutes = plannedFocusMinutes
        self.completedFully = completedFully
    }
}

public final class FocusHistoryStore {
    private let db: SQLiteDatabase
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS focus_sessions (
                id TEXT PRIMARY KEY,
                startedAt TEXT NOT NULL,
                endedAt TEXT NOT NULL,
                plannedFocusMinutes REAL NOT NULL,
                completedFully INTEGER NOT NULL
            )
            """)
    }

    public func add(_ record: FocusSessionRecord) throws {
        try db.execute(
            "INSERT INTO focus_sessions (id, startedAt, endedAt, plannedFocusMinutes, completedFully) VALUES (?, ?, ?, ?, ?)",
            bindings: [
                .text(record.id.uuidString),
                .text(Self.dateFormatter.string(from: record.startedAt)),
                .text(Self.dateFormatter.string(from: record.endedAt)),
                .double(record.plannedFocusMinutes),
                .integer(record.completedFully ? 1 : 0),
            ]
        )
    }

    public func all() throws -> [FocusSessionRecord] {
        var results: [FocusSessionRecord] = []
        try db.query("SELECT id, startedAt, endedAt, plannedFocusMinutes, completedFully FROM focus_sessions ORDER BY startedAt ASC") { row in
            guard
                let idString = row.text(0), let id = UUID(uuidString: idString),
                let startedAtString = row.text(1), let startedAt = Self.dateFormatter.date(from: startedAtString),
                let endedAtString = row.text(2), let endedAt = Self.dateFormatter.date(from: endedAtString)
            else { return }
            results.append(FocusSessionRecord(
                id: id, startedAt: startedAt, endedAt: endedAt,
                plannedFocusMinutes: row.double(3), completedFully: row.integer(4) == 1
            ))
        }
        return results
    }

    public func todayTotalFocusMinutes(referenceDate: Date = Date(), calendar: Calendar = .current) throws -> Double {
        try all()
            .filter { calendar.isDate($0.startedAt, inSameDayAs: referenceDate) && $0.completedFully }
            .reduce(0) { $0 + $1.plannedFocusMinutes }
    }

    public func todayCompletedSessionCount(referenceDate: Date = Date(), calendar: Calendar = .current) throws -> Int {
        try all().filter { calendar.isDate($0.startedAt, inSameDayAs: referenceDate) && $0.completedFully }.count
    }

    /// Minutes focused on a day, counting stopped-early sessions by the time actually spent.
    public func focusMinutes(on day: Date, calendar: Calendar = .current) throws -> Double {
        try all().filter { calendar.isDate($0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.plannedFocusMinutes }
    }
}
