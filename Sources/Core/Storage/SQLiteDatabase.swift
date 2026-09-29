import Foundation
import SQLite3

/// A minimal, dependency-free SQLite wrapper (uses the `sqlite3` C library
/// that ships with macOS -- no external package). Every store in this app
/// (tasks, reminders, focus sessions, ...) is built on top of this instead
/// of each hand-rolling its own C-API bridging.
public final class SQLiteDatabase {
    public enum SQLiteError: Error, CustomStringConvertible {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case bindFailed(String)

        public var description: String {
            switch self {
            case .openFailed(let m): return "SQLite open failed: \(m)"
            case .prepareFailed(let m): return "SQLite prepare failed: \(m)"
            case .stepFailed(let m): return "SQLite step failed: \(m)"
            case .bindFailed(let m): return "SQLite bind failed: \(m)"
            }
        }
    }

    private var handle: OpaquePointer?

    public init(fileURL: URL) throws {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(fileURL.path, &handle) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(message)
        }
        // Default rollback-journal mode fsyncs on every single commit, which
        // is a real, measured CPU/IO cost for a store written to once per
        // second (screen-time accumulation). WAL + synchronous=NORMAL is the
        // standard fix: writes go to a log instead of syncing the whole
        // database file each time, at a well-understood, safe durability
        // tradeoff (SQLite's own docs recommend this combination).
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs a statement with no result rows expected (CREATE TABLE, INSERT, UPDATE, DELETE).
    @discardableResult
    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.stepFailed(lastErrorMessage())
        }
        return sqlite3_changes(handle)
    }

    /// Runs a SELECT, calling `rowHandler` once per result row.
    public func query(_ sql: String, bindings: [SQLiteValue] = [], rowHandler: (SQLiteRow) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            rowHandler(SQLiteRow(statement: statement))
        }
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, position, Int64(integer))
            case .double(let double):
                result = sqlite3_bind_double(statement, position, double)
            case .null:
                result = sqlite3_bind_null(statement, position)
            }
            guard result == SQLITE_OK else {
                throw SQLiteError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteValue {
    case text(String)
    case integer(Int)
    case double(Double)
    case null
}

/// A read-only view over the current row of a `query` callback.
public struct SQLiteRow {
    fileprivate let statement: OpaquePointer?

    public func text(_ columnIndex: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, columnIndex) else { return nil }
        return String(cString: cString)
    }

    public func integer(_ columnIndex: Int32) -> Int {
        Int(sqlite3_column_int64(statement, columnIndex))
    }

    public func double(_ columnIndex: Int32) -> Double {
        sqlite3_column_double(statement, columnIndex)
    }

    public func isNull(_ columnIndex: Int32) -> Bool {
        sqlite3_column_type(statement, columnIndex) == SQLITE_NULL
    }
}
