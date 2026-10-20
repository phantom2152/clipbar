import Foundation
import SQLite3

enum Bind {
    case int(Int64)
    case real(Double)
    case text(String)
    case null
}

/// Thin wrapper over the system SQLite (no packages needed).
@MainActor
final class Database {
    private var handle: OpaquePointer?

    init?(path: String) {
        var raw: OpaquePointer?
        guard sqlite3_open(path, &raw) == SQLITE_OK, let opened = raw else {
            sqlite3_close(raw)
            return nil
        }
        handle = opened
        sqlite3_busy_timeout(opened, 1000)
    }

    /// Rows touched by the last INSERT/UPDATE/DELETE.
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// Runs one or more statements without parameters.
    @discardableResult
    func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            print("ClipBar SQL error:", err.map { String(cString: $0) } ?? "?")
            sqlite3_free(err)
        }
        return rc == SQLITE_OK
    }

    /// Runs one statement. `row` is called for every result row.
    @discardableResult
    func run(_ sql: String, _ binds: [Bind] = [], row: (OpaquePointer) -> Void = { _ in }) -> Bool {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("ClipBar SQL prepare error:", String(cString: sqlite3_errmsg(handle)))
            return false
        }
        defer { sqlite3_finalize(stmt) }

        for (i, bind) in binds.enumerated() {
            let index = Int32(i + 1)
            switch bind {
            case .int(let v): sqlite3_bind_int64(stmt, index, v)
            case .real(let v): sqlite3_bind_double(stmt, index, v)
            case .text(let v): sqlite3_bind_text(stmt, index, v, -1, transient)
            case .null: sqlite3_bind_null(stmt, index)
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW, let stmt { row(stmt); continue }
            return rc == SQLITE_DONE
        }
    }

    // MARK: Column readers

    nonisolated static func int(_ s: OpaquePointer, _ i: Int32) -> Int64 { sqlite3_column_int64(s, i) }
    nonisolated static func real(_ s: OpaquePointer, _ i: Int32) -> Double { sqlite3_column_double(s, i) }
    nonisolated static func text(_ s: OpaquePointer, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(s, i) else { return "" }
        return String(cString: c)
    }
}
