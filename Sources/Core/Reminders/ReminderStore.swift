import Foundation

public final class ReminderStore {
    private let db: SQLiteDatabase
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS reminders (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                fireDate TEXT NOT NULL,
                recurrence TEXT NOT NULL,
                isCompleted INTEGER NOT NULL,
                snoozedUntil TEXT,
                createdAt TEXT NOT NULL
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS reminders_pending ON reminders (isCompleted, fireDate)")
    }

    public func add(_ reminder: ReminderItem) throws {
        try db.execute(
            """
            INSERT INTO reminders (id, title, fireDate, recurrence, isCompleted, snoozedUntil, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(reminder.id.uuidString),
                .text(reminder.title),
                .text(Self.dateFormatter.string(from: reminder.fireDate)),
                .text(reminder.recurrence.rawValue),
                .integer(reminder.isCompleted ? 1 : 0),
                reminder.snoozedUntil.map { .text(Self.dateFormatter.string(from: $0)) } ?? .null,
                .text(Self.dateFormatter.string(from: reminder.createdAt)),
            ]
        )
    }

    public func snooze(id: UUID, until: Date) throws {
        try db.execute(
            "UPDATE reminders SET snoozedUntil = ? WHERE id = ?",
            bindings: [.text(Self.dateFormatter.string(from: until)), .text(id.uuidString)]
        )
    }

    public func dismiss(id: UUID) throws {
        try db.execute("UPDATE reminders SET isCompleted = 1 WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func delete(id: UUID) throws {
        try db.execute("DELETE FROM reminders WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func all() throws -> [ReminderItem] {
        var results: [ReminderItem] = []
        try db.query("SELECT id, title, fireDate, recurrence, isCompleted, snoozedUntil, createdAt FROM reminders ORDER BY fireDate ASC") { row in
            guard let item = Self.reminderItem(from: row) else { return }
            results.append(item)
        }
        return results
    }

    /// Only not-yet-completed reminders, via the index -- the cost of this
    /// no longer grows with every reminder ever created (the per-second
    /// due check used to load and date-parse the entire history).
    public func pending() throws -> [ReminderItem] {
        var results: [ReminderItem] = []
        try db.query("SELECT id, title, fireDate, recurrence, isCompleted, snoozedUntil, createdAt FROM reminders WHERE isCompleted = 0 ORDER BY fireDate ASC") { row in
            guard let item = Self.reminderItem(from: row) else { return }
            results.append(item)
        }
        return results
    }

    /// The earliest moment any pending reminder could become due (its fire
    /// date, or its snooze end), or nil if none are pending. Lets the app
    /// skip the due check entirely until then.
    public func nextDueDate() throws -> Date? {
        try pending().map { max($0.fireDate, $0.snoozedUntil ?? $0.fireDate) }.min()
    }

    /// Reminders that are due right now and not suppressed by quiet hours.
    public func due(referenceDate: Date = Date(), quietHours: QuietHours? = nil) throws -> [ReminderItem] {
        let candidates = try pending().filter { $0.isDue(referenceDate: referenceDate) }
        guard let quietHours else { return candidates }
        return candidates.filter { _ in !quietHours.contains(referenceDate) }
    }

    @discardableResult
    public func spawnNextOccurrenceIfRecurring(after reminder: ReminderItem, calendar: Calendar = .current) throws -> ReminderItem? {
        guard reminder.recurrence != .none else { return nil }
        let nextFireDate = reminder.recurrence.next(after: reminder.fireDate, calendar: calendar)
        guard let nextFireDate else { return nil }
        let next = ReminderItem(title: reminder.title, fireDate: nextFireDate, recurrence: reminder.recurrence)
        try add(next)
        return next
    }

    private static func reminderItem(from row: SQLiteRow) -> ReminderItem? {
        guard
            let idString = row.text(0), let id = UUID(uuidString: idString),
            let title = row.text(1),
            let fireDateString = row.text(2), let fireDate = dateFormatter.date(from: fireDateString),
            let recurrenceRaw = row.text(3), let recurrence = RecurrenceRule(rawValue: recurrenceRaw),
            let createdAtString = row.text(6), let createdAt = dateFormatter.date(from: createdAtString)
        else { return nil }

        let snoozedUntil = row.isNull(5) ? nil : row.text(5).flatMap { dateFormatter.date(from: $0) }

        return ReminderItem(
            id: id, title: title, fireDate: fireDate, recurrence: recurrence,
            isCompleted: row.integer(4) == 1, snoozedUntil: snoozedUntil, createdAt: createdAt
        )
    }
}
