import Foundation

/// SQLite-backed task persistence. All data stays local (see docs/PRIVACY.md
/// once written) -- no network calls anywhere in this type.
public final class TaskStore {
    private let db: SQLiteDatabase
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                priority INTEGER NOT NULL,
                dueDate TEXT,
                recurrence TEXT NOT NULL,
                isCompleted INTEGER NOT NULL,
                createdAt TEXT NOT NULL,
                completedAt TEXT
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS tasks_open ON tasks (isCompleted, completedAt)")
        // v2 columns (added in place; existing rows keep working).
        var existing = Set<String>()
        try db.query("PRAGMA table_info(tasks)") { row in if let n = row.text(1) { existing.insert(n) } }
        for (name, type) in [("notes", "TEXT NOT NULL DEFAULT ''"), ("hasDueTime", "INTEGER NOT NULL DEFAULT 0"),
                             ("remindBefore", "INTEGER"), ("repeatEvery", "INTEGER"),
                             ("reminderSnoozedUntil", "TEXT"), ("reminderHandledAt", "TEXT")] where !existing.contains(name) {
            try db.execute("ALTER TABLE tasks ADD COLUMN \(name) \(type)")
        }
    }

    static let columns = "id, title, priority, dueDate, recurrence, isCompleted, createdAt, completedAt, notes, hasDueTime, remindBefore, repeatEvery, reminderSnoozedUntil, reminderHandledAt"

    private static func date(_ d: Date?) -> SQLiteValue { d.map { .text(dateFormatter.string(from: $0)) } ?? .null }
    private static func int(_ i: Int?) -> SQLiteValue { i.map { .integer($0) } ?? .null }

    public func add(_ task: TaskItem) throws {
        try db.execute(
            """
            INSERT INTO tasks (\(Self.columns))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(task.id.uuidString),
                .text(task.title),
                .integer(task.priority.rawValue),
                task.dueDate.map { .text(Self.dateFormatter.string(from: $0)) } ?? .null,
                .text(task.recurrence.rawValue),
                .integer(task.isCompleted ? 1 : 0),
                .text(Self.dateFormatter.string(from: task.createdAt)),
                task.completedAt.map { .text(Self.dateFormatter.string(from: $0)) } ?? .null,
                .text(task.notes), .integer(task.hasDueTime ? 1 : 0),
                Self.int(task.remindBeforeMinutes), Self.int(task.repeatEveryMinutes),
                Self.date(task.reminderSnoozedUntil), Self.date(task.reminderHandledAt),
            ]
        )
    }

    public func complete(id: UUID, completedAt: Date = Date()) throws {
        try db.execute(
            "UPDATE tasks SET isCompleted = 1, completedAt = ? WHERE id = ?",
            bindings: [.text(Self.dateFormatter.string(from: completedAt)), .text(id.uuidString)]
        )
    }

    public func uncomplete(id: UUID) throws {
        try db.execute(
            "UPDATE tasks SET isCompleted = 0, completedAt = NULL WHERE id = ?",
            bindings: [.text(id.uuidString)]
        )
    }

    public func delete(id: UUID) throws {
        try db.execute("DELETE FROM tasks WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func update(_ task: TaskItem) throws {
        try db.execute(
            """
            UPDATE tasks SET title = ?, priority = ?, dueDate = ?, recurrence = ?, isCompleted = ?, completedAt = ?,
                notes = ?, hasDueTime = ?, remindBefore = ?, repeatEvery = ?, reminderSnoozedUntil = ?, reminderHandledAt = ?
            WHERE id = ?
            """,
            bindings: [
                .text(task.title),
                .integer(task.priority.rawValue),
                task.dueDate.map { .text(Self.dateFormatter.string(from: $0)) } ?? .null,
                .text(task.recurrence.rawValue),
                .integer(task.isCompleted ? 1 : 0),
                task.completedAt.map { .text(Self.dateFormatter.string(from: $0)) } ?? .null,
                .text(task.notes), .integer(task.hasDueTime ? 1 : 0),
                Self.int(task.remindBeforeMinutes), Self.int(task.repeatEveryMinutes),
                Self.date(task.reminderSnoozedUntil), Self.date(task.reminderHandledAt),
                .text(task.id.uuidString),
            ]
        )
    }

    public func all() throws -> [TaskItem] {
        var results: [TaskItem] = []
        try db.query("SELECT \(Self.columns) FROM tasks ORDER BY createdAt ASC") { row in
            guard let item = Self.taskItem(from: row) else { return }
            results.append(item)
        }
        return results
    }

    public func task(id: UUID) throws -> TaskItem? {
        var result: TaskItem?
        try db.query("SELECT \(Self.columns) FROM tasks WHERE id = ?", bindings: [.text(id.uuidString)]) { row in
            result = Self.taskItem(from: row)
        }
        return result
    }

    /// Open tasks that can produce reminders (have a deadline reminder or a
    /// repeating nudge) -- the only ones the reminder engine looks at.
    public func withReminders() throws -> [TaskItem] {
        var results: [TaskItem] = []
        try db.query("SELECT \(Self.columns) FROM tasks WHERE isCompleted = 0 AND ((dueDate IS NOT NULL AND remindBefore IS NOT NULL) OR repeatEvery IS NOT NULL)") { row in
            if let item = Self.taskItem(from: row) { results.append(item) }
        }
        return results
    }

    public func today(referenceDate: Date = Date()) throws -> [TaskItem] {
        try incomplete().filter { $0.isDueToday(referenceDate: referenceDate) }
    }

    /// Open tasks only (indexed), so cost doesn't grow with task history.
    public func incomplete() throws -> [TaskItem] {
        var results: [TaskItem] = []
        try db.query("SELECT \(Self.columns) FROM tasks WHERE isCompleted = 0 ORDER BY createdAt ASC") { row in
            guard let item = Self.taskItem(from: row) else { return }
            results.append(item)
        }
        return results
    }

    /// Tasks completed on the (local) calendar day containing `referenceDate`.
    /// Range query on the UTC ISO-8601 strings, which sort chronologically.
    public func completedOnDay(of referenceDate: Date = Date(), calendar: Calendar = .current) throws -> [TaskItem] {
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var results: [TaskItem] = []
        try db.query(
            "SELECT \(Self.columns) FROM tasks WHERE isCompleted = 1 AND completedAt >= ? AND completedAt < ? ORDER BY completedAt ASC",
            bindings: [.text(Self.dateFormatter.string(from: start)), .text(Self.dateFormatter.string(from: end))]
        ) { row in
            guard let item = Self.taskItem(from: row) else { return }
            results.append(item)
        }
        return results
    }

    public func completed() throws -> [TaskItem] {
        try all().filter(\.isCompleted)
    }

    /// For a completed recurring task, creates the next occurrence (daily/weekly)
    /// as a fresh incomplete task and returns it. Returns nil for non-recurring tasks.
    @discardableResult
    public func spawnNextOccurrenceIfRecurring(after task: TaskItem, calendar: Calendar = .current) throws -> TaskItem? {
        guard task.recurrence != .none else { return nil }
        let baseDate = task.dueDate ?? Date()
        let nextDueDate: Date?
        switch task.recurrence {
        case .none: return nil
        case .daily: nextDueDate = calendar.date(byAdding: .day, value: 1, to: baseDate)
        case .weekly: nextDueDate = calendar.date(byAdding: .day, value: 7, to: baseDate)
        }
        let next = TaskItem(
            title: task.title,
            priority: task.priority,
            dueDate: nextDueDate,
            recurrence: task.recurrence,
            notes: task.notes,
            hasDueTime: task.hasDueTime,
            remindBeforeMinutes: task.remindBeforeMinutes,
            repeatEveryMinutes: task.repeatEveryMinutes
        )
        try add(next)
        return next
    }

    private static func taskItem(from row: SQLiteRow) -> TaskItem? {
        guard
            let idString = row.text(0), let id = UUID(uuidString: idString),
            let title = row.text(1),
            let priority = TaskPriority(rawValue: row.integer(2)),
            let recurrenceRaw = row.text(4), let recurrence = RecurrenceRule(rawValue: recurrenceRaw),
            let createdAtString = row.text(6), let createdAt = dateFormatter.date(from: createdAtString)
        else { return nil }

        let dueDate = row.isNull(3) ? nil : row.text(3).flatMap { dateFormatter.date(from: $0) }
        let completedAt = row.isNull(7) ? nil : row.text(7).flatMap { dateFormatter.date(from: $0) }

        func optDate(_ i: Int32) -> Date? { row.isNull(i) ? nil : row.text(i).flatMap { dateFormatter.date(from: $0) } }
        return TaskItem(
            id: id, title: title, priority: priority, dueDate: dueDate, recurrence: recurrence,
            isCompleted: row.integer(5) == 1, createdAt: createdAt, completedAt: completedAt,
            notes: row.text(8) ?? "", hasDueTime: row.integer(9) == 1,
            remindBeforeMinutes: row.isNull(10) ? nil : row.integer(10),
            repeatEveryMinutes: row.isNull(11) ? nil : row.integer(11),
            reminderSnoozedUntil: optDate(12), reminderHandledAt: optDate(13)
        )
    }
}
