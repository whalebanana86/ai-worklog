import Foundation
import SQLite3

/// 얇은 SQLite 감싸개.
/// - 읽기 전용: 다른 프로그램(Codex)이 쓰고 있는 DB 를 건드리지 않고 읽는다.
/// - 읽기·쓰기: 이 앱의 보관함 DB.
final class SQLiteReader {
    private var db: OpaquePointer?

    /// 다른 프로그램의 DB 를 읽기 전용으로 연다. 파일이 없으면 nil.
    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let base = URL(fileURLWithPath: path).absoluteString
        guard Self.open(base + "?mode=ro", &db) else { return nil }
        // WAL 방식 DB 는 쓰던 프로그램이 닫히면서 -shm 을 지우는데, 읽기 전용으로는 그걸 다시 만들 수 없어 열리지 않는다.
        // 그때는 모든 내용이 본 파일에 들어가 있으니 "바뀌지 않는 파일"로 열어 읽는다.
        if sqlite3_exec(db, "SELECT 1 FROM sqlite_master LIMIT 1", nil, nil, nil) == SQLITE_CANTOPEN {
            sqlite3_close(db)
            db = nil
            guard Self.open(base + "?mode=ro&immutable=1", &db) else { return nil }
        }
    }

    private static func open(_ uri: String, _ db: inout OpaquePointer?) -> Bool {
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return false
        }
        sqlite3_busy_timeout(db, 2_000)
        return true
    }

    /// 읽기·쓰기로 연다. 없으면 만든다.
    init(writablePath path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? L("열 수 없음")
            sqlite3_close(db)
            throw QueryError(description: message)
        }
        sqlite3_busy_timeout(db, 5_000)
    }

    deinit { sqlite3_close(db) }

    struct Row {
        fileprivate let stmt: OpaquePointer?

        func string(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }

        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }

        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }

        func optionalInt(_ i: Int32) -> Int? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : int(i)
        }

        func optionalDouble(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : double(i)
        }

        func data(_ i: Int32) -> Data? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let p = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    struct QueryError: Error, CustomStringConvertible {
        var description: String
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func prepare(_ sql: String, _ values: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QueryError(description: String(cString: sqlite3_errmsg(db)))
        }
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(stmt, i)
            case let v as Int: sqlite3_bind_int64(stmt, i, Int64(v))
            case let v as Bool: sqlite3_bind_int64(stmt, i, v ? 1 : 0)
            case let v as Double: sqlite3_bind_double(stmt, i, v)
            case let v as Date: sqlite3_bind_double(stmt, i, v.timeIntervalSince1970)
            case let v as String: sqlite3_bind_text(stmt, i, v, -1, Self.transient)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(v.count), Self.transient) }
            default: sqlite3_bind_null(stmt, i)
            }
        }
        return stmt
    }

    func query(_ sql: String, _ values: [Any?] = [], _ each: (Row) -> Void) throws {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { each(Row(stmt: stmt)); continue }
            if rc == SQLITE_DONE { break }
            throw QueryError(description: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 결과를 돌려주지 않는 문장 하나.
    func run(_ sql: String, _ values: [Any?] = []) throws {
        try query(sql, values) { _ in }
    }

    /// 세미콜론으로 이은 여러 문장 (스키마 만들기 등).
    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? L("실행 실패")
            sqlite3_free(error)
            throw QueryError(description: message)
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    func hasColumn(_ table: String, _ column: String) -> Bool {
        var found = false
        try? query("PRAGMA table_info(\(table))") { row in
            if row.string(1) == column { found = true }
        }
        return found
    }
}
