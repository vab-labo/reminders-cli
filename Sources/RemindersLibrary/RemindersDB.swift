import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

/// Reads extra fields from the Reminders.app SQLite DB that EventKit doesn't expose.
/// Read-only — writing would break CloudKit sync.
enum RemindersDB {

    /// Key for looking up flagged status: "listName\0title"
    static func lookupKey(listName: String, title: String) -> String {
        "\(listName)\0\(title)"
    }

    /// Returns a set of "listName\0title" keys for flagged reminders.
    /// Scans all Data-*.sqlite files in the Reminders container.
    static func getFlaggedKeys() -> Set<String> {
        var result = Set<String>()
        for dbPath in findDatabases() {
            guard let db = openReadOnly(dbPath) else { continue }
            defer { sqlite3_close(db) }

            let sql = """
                SELECT r.ZTITLE, l.ZNAME
                FROM ZREMCDREMINDER r
                JOIN ZREMCDBASELIST l ON r.ZLIST = l.Z_PK
                WHERE r.ZFLAGGED = 1 AND r.ZMARKEDFORDELETION = 0
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let titlePtr = sqlite3_column_text(stmt, 0),
                      let listPtr = sqlite3_column_text(stmt, 1) else { continue }
                let title = String(cString: titlePtr)
                let listName = String(cString: listPtr)
                result.insert(lookupKey(listName: listName, title: title))
            }
        }
        return result
    }

    // MARK: - Private

    private static let containerPath: String = {
        let home = NSHomeDirectory()
        return home + "/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
    }()

    private static func findDatabases() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: containerPath) else { return [] }
        return files
            .filter { $0.hasPrefix("Data-") && $0.hasSuffix(".sqlite") && $0 != "Data-local.sqlite" }
            .map { containerPath + "/" + $0 }
    }

    private static func openReadOnly(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }
}
