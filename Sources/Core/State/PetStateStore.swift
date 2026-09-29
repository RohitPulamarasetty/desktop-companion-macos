import Foundation

/// SQLite-backed persistence for the pet itself (as opposed to the user's
/// productivity data): where it was, how rested it is, when the user last
/// interacted with it, which behaviors the user has discovered, and small
/// per-day stats.
///
/// Write discipline (performance budget): callers batch -- the app flushes
/// daily-stat deltas and position at most once a minute, plus on
/// significant events (drop, quit). Discovered behaviors are written only
/// the first time each one is seen (the in-memory set filters repeats).
/// Growth is bounded: daily rows older than `retentionDays` are pruned, and
/// discovered behaviors are capped by the size of the behavior catalog.
public final class PetStateStore {
    private let db: SQLiteDatabase
    private var discoveredCache: Set<String> = []
    public static let retentionDays = 400

    public init(fileURL: URL) throws {
        db = try SQLiteDatabase(fileURL: fileURL)
        try db.execute("CREATE TABLE IF NOT EXISTS pet_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS pet_daily (
                day TEXT PRIMARY KEY,
                clicks INTEGER NOT NULL DEFAULT 0,
                barks INTEGER NOT NULL DEFAULT 0,
                naps INTEGER NOT NULL DEFAULT 0,
                sleep_seconds REAL NOT NULL DEFAULT 0,
                walked_points REAL NOT NULL DEFAULT 0,
                celebrations INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.execute("CREATE TABLE IF NOT EXISTS discovered_behaviors (behavior TEXT PRIMARY KEY, first_seen REAL NOT NULL)")
        try db.query("SELECT behavior FROM discovered_behaviors") { row in
            if let b = row.text(0) { discoveredCache.insert(b) }
        }
    }

    // MARK: Key-value

    public func set(_ value: String, for key: String) throws {
        try db.execute("INSERT INTO pet_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       bindings: [.text(key), .text(value)])
    }

    public func value(for key: String) -> String? {
        var result: String?
        try? db.query("SELECT value FROM pet_state WHERE key = ?", bindings: [.text(key)]) { result = $0.text(0) }
        return result
    }

    public func double(for key: String) -> Double? { value(for: key).flatMap(Double.init) }

    // MARK: Position

    public struct SavedPosition: Equatable {
        public let displayID: UInt32
        /// Pet's left edge, as a fraction (0...1) of the display's usable
        /// horizontal range -- survives resolution/Dock changes without
        /// ever pointing off-screen.
        public let fraction: Double
        /// Same, vertically (0 = bottom of the usable area, 1 = top).
        public let fractionY: Double
        public init(displayID: UInt32, fraction: Double, fractionY: Double = 0) {
            self.displayID = displayID
            self.fraction = fraction
            self.fractionY = fractionY
        }
    }

    public func savePosition(_ position: SavedPosition) throws {
        let fx = min(max(position.fraction, 0), 1), fy = min(max(position.fractionY, 0), 1)
        try set("\(position.displayID),\(fx),\(fy)", for: "position")
    }

    public func savedPosition() -> SavedPosition? {
        guard let raw = value(for: "position") else { return nil }
        let parts = raw.split(separator: ",")
        guard parts.count >= 2, let id = UInt32(parts[0]), let f = Double(parts[1]), f.isFinite else { return nil }
        let fy = parts.count >= 3 ? (Double(parts[2]).flatMap { $0.isFinite ? $0 : nil } ?? 0) : 0 // v1 rows had no y
        return SavedPosition(displayID: id, fraction: min(max(f, 0), 1), fractionY: min(max(fy, 0), 1))
    }

    // MARK: Character selection (pet data: which look the pet wears)

    public func setSelectedCharacterID(_ id: String) throws { try set(id, for: "selectedCharacterID") }
    public func selectedCharacterID() -> String? { value(for: "selectedCharacterID") }

    // MARK: Pet vitals

    public func saveEnergy(_ energy: Double) throws { try set(String(min(max(energy, 0), 1)), for: "energy") }
    public func energy() -> Double? { double(for: "energy").map { min(max($0, 0), 1) } }

    public func saveLastInteraction(_ date: Date) throws { try set(String(date.timeIntervalSince1970), for: "lastInteraction") }
    public func lastInteraction() -> Date? { double(for: "lastInteraction").map(Date.init(timeIntervalSince1970:)) }

    // MARK: Discovered behaviors ("unlocked animations")

    public var discoveredBehaviors: Set<String> { discoveredCache }

    /// Returns true the first time a behavior is seen (and persists it).
    @discardableResult
    public func recordDiscovered(_ behavior: String, at date: Date = Date()) -> Bool {
        guard !discoveredCache.contains(behavior) else { return false }
        discoveredCache.insert(behavior)
        try? db.execute("INSERT OR IGNORE INTO discovered_behaviors (behavior, first_seen) VALUES (?, ?)",
                        bindings: [.text(behavior), .double(date.timeIntervalSince1970)])
        return true
    }

    // MARK: Activity usage (dashboard: favorite activity)

    public func recordActivityStarted(_ activity: Activity) {
        let key = "activity." + activity.rawValue
        try? set(String((value(for: key).flatMap(Int.init) ?? 0) + 1), for: key)
    }

    public func activityCount(_ activity: Activity) -> Int {
        max(0, value(for: "activity." + activity.rawValue).flatMap(Int.init) ?? 0)
    }

    /// The most-used activity, or nil before any was started (ties resolve
    /// in `Activity.allCases` order, so the answer is deterministic).
    public func favoriteActivity() -> Activity? {
        var best: (Activity, Int)?
        for a in Activity.allCases {
            let n = activityCount(a)
            if n > 0, n > (best?.1 ?? 0) { best = (a, n) }
        }
        return best?.0
    }

    // MARK: Daily stats

    public struct DailyStats: Equatable {
        public var clicks = 0
        public var barks = 0
        public var naps = 0
        public var sleepSeconds: Double = 0
        public var walkedPoints: Double = 0
        public var celebrations = 0
        public init() {}
    }

    private static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Adds a delta to the given day's row (upsert).
    public func addDaily(_ delta: DailyStats, on date: Date = Date()) throws {
        guard delta != DailyStats() else { return }
        try db.execute("""
            INSERT INTO pet_daily (day, clicks, barks, naps, sleep_seconds, walked_points, celebrations)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                clicks = clicks + excluded.clicks,
                barks = barks + excluded.barks,
                naps = naps + excluded.naps,
                sleep_seconds = sleep_seconds + excluded.sleep_seconds,
                walked_points = walked_points + excluded.walked_points,
                celebrations = celebrations + excluded.celebrations
            """,
            bindings: [.text(Self.dayKey(date)), .integer(delta.clicks), .integer(delta.barks), .integer(delta.naps),
                       .double(delta.sleepSeconds), .double(delta.walkedPoints), .integer(delta.celebrations)])
    }

    public func daily(on date: Date = Date()) -> DailyStats {
        var stats = DailyStats()
        try? db.query("SELECT clicks, barks, naps, sleep_seconds, walked_points, celebrations FROM pet_daily WHERE day = ?",
                      bindings: [.text(Self.dayKey(date))]) { row in
            stats.clicks = row.integer(0)
            stats.barks = row.integer(1)
            stats.naps = row.integer(2)
            stats.sleepSeconds = row.double(3)
            stats.walkedPoints = row.double(4)
            stats.celebrations = row.integer(5)
        }
        return stats
    }

    public func dailyRowCount() -> Int {
        var n = 0
        try? db.query("SELECT COUNT(*) FROM pet_daily") { n = $0.integer(0) }
        return n
    }

    /// Deletes daily rows older than `retentionDays` before `now`.
    public func prune(now: Date = Date(), calendar: Calendar = .current) throws {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        try db.execute("DELETE FROM pet_daily WHERE day < ?", bindings: [.text(Self.dayKey(cutoff))])
    }
}
