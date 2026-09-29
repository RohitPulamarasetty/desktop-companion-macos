import Foundation

public enum WellnessKind: String, Codable {
    case water
    /// A screen break (eyes/stretch), from the screen-time reminder or the
    /// Break button.
    case shortBreak
    case longBreak
    /// The break phase after a completed focus session.
    case focusBreak
}

public enum WellnessAction: String, Codable {
    case done
    case snoozed
    case skipped
}

public struct WellnessEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: WellnessKind
    public let action: WellnessAction
    public let timestamp: Date

    public init(id: UUID = UUID(), kind: WellnessKind, action: WellnessAction, timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.action = action
        self.timestamp = timestamp
    }
}

/// Shared history log for water and break reminders -- both are "did you do
/// the thing? done/snooze/skip, with a simple daily history" and don't
/// warrant separate stores. No health claims are made anywhere in this
/// project; this purely logs what the user told the reminder.
public final class WellnessStore {
    private let db: SQLiteDatabase
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS wellness_entries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                action TEXT NOT NULL,
                timestamp TEXT NOT NULL
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS wellness_by_time ON wellness_entries (kind, timestamp)")
    }

    private static func entry(_ row: SQLiteRow) -> WellnessEntry? {
        guard
            let idString = row.text(0), let id = UUID(uuidString: idString),
            let kindRaw = row.text(1), let kind = WellnessKind(rawValue: kindRaw),
            let actionRaw = row.text(2), let action = WellnessAction(rawValue: actionRaw),
            let timestampString = row.text(3), let timestamp = dateFormatter.date(from: timestampString)
        else { return nil }
        return WellnessEntry(id: id, kind: kind, action: action, timestamp: timestamp)
    }

    /// The most recent "done" of a kind (e.g. last glass of water).
    public func lastDone(kind: WellnessKind) throws -> Date? {
        var result: Date?
        try db.query("SELECT id, kind, action, timestamp FROM wellness_entries WHERE kind = ? AND action = 'done' ORDER BY timestamp DESC LIMIT 1",
                     bindings: [.text(kind.rawValue)]) { row in result = Self.entry(row)?.timestamp }
        return result
    }

    public func add(_ entry: WellnessEntry) throws {
        try db.execute(
            "INSERT INTO wellness_entries (id, kind, action, timestamp) VALUES (?, ?, ?, ?)",
            bindings: [
                .text(entry.id.uuidString),
                .text(entry.kind.rawValue),
                .text(entry.action.rawValue),
                .text(Self.dateFormatter.string(from: entry.timestamp)),
            ]
        )
    }

    public func all() throws -> [WellnessEntry] {
        var results: [WellnessEntry] = []
        try db.query("SELECT id, kind, action, timestamp FROM wellness_entries ORDER BY timestamp ASC") { row in
            guard
                let idString = row.text(0), let id = UUID(uuidString: idString),
                let kindRaw = row.text(1), let kind = WellnessKind(rawValue: kindRaw),
                let actionRaw = row.text(2), let action = WellnessAction(rawValue: actionRaw),
                let timestampString = row.text(3), let timestamp = Self.dateFormatter.date(from: timestampString)
            else { return }
            results.append(WellnessEntry(id: id, kind: kind, action: action, timestamp: timestamp))
        }
        return results
    }

    /// One day's entries of a kind, via the (kind, timestamp) index -- cost
    /// doesn't grow with history.
    public func today(kind: WellnessKind, referenceDate: Date = Date(), calendar: Calendar = .current) throws -> [WellnessEntry] {
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var results: [WellnessEntry] = []
        try db.query("SELECT id, kind, action, timestamp FROM wellness_entries WHERE kind = ? AND timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC",
                     bindings: [.text(kind.rawValue), .text(Self.dateFormatter.string(from: start)), .text(Self.dateFormatter.string(from: end))]) { row in
            if let e = Self.entry(row) { results.append(e) }
        }
        return results
    }

    public func todayDoneCount(kind: WellnessKind, referenceDate: Date = Date(), calendar: Calendar = .current) throws -> Int {
        try today(kind: kind, referenceDate: referenceDate, calendar: calendar).filter { $0.action == .done }.count
    }
}
