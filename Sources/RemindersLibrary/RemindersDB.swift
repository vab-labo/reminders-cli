import Foundation
import SQLite3

/// Reads extra fields from the Reminders.app SQLite DB that EventKit doesn't expose.
/// Read-only — writing would break CloudKit sync.
///
/// Lookup uses listName + title as composite key because EventKit identifiers
/// and SQLite identifiers use completely different ID schemes with no mapping.
/// This means duplicate titles within the same list cannot be distinguished.
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
            queryRows(dbPath: dbPath, sql: """
                SELECT r.ZTITLE, l.ZNAME
                FROM ZREMCDREMINDER r
                JOIN ZREMCDBASELIST l ON r.ZLIST = l.Z_PK
                WHERE r.ZFLAGGED = 1 AND r.ZMARKEDFORDELETION = 0
                """) { stmt in
                guard let titlePtr = sqlite3_column_text(stmt, 0),
                      let listPtr = sqlite3_column_text(stmt, 1) else { return }
                result.insert(lookupKey(listName: String(cString: listPtr), title: String(cString: titlePtr)))
            }
        }
        return result
    }

    /// Returns a mapping of "listName\0title" → [tag names] for all tagged reminders.
    static func getTagMap() -> [String: [String]] {
        var result = [String: [String]]()
        for dbPath in findDatabases() {
            queryRows(dbPath: dbPath, sql: """
                SELECT r.ZTITLE, l.ZNAME, h.ZNAME
                FROM ZREMCDOBJECT o
                JOIN ZREMCDHASHTAGLABEL h ON o.ZHASHTAGLABEL = h.Z_PK
                JOIN ZREMCDREMINDER r ON o.ZREMINDER3 = r.Z_PK
                JOIN ZREMCDBASELIST l ON r.ZLIST = l.Z_PK
                WHERE o.ZMARKEDFORDELETION = 0 AND r.ZMARKEDFORDELETION = 0
                """) { stmt in
                guard let titlePtr = sqlite3_column_text(stmt, 0),
                      let listPtr = sqlite3_column_text(stmt, 1),
                      let tagPtr = sqlite3_column_text(stmt, 2) else { return }
                let key = lookupKey(listName: String(cString: listPtr), title: String(cString: titlePtr))
                result[key, default: []].append(String(cString: tagPtr))
            }
        }
        return result
    }

    /// Returns a mapping of "listName\0title" → section display name.
    /// Requires parsing JSON membership blobs from ZREMCDBASELIST because
    /// there is no direct FK between reminders and sections.
    static func getSectionMap() -> [String: String] {
        var result = [String: String]()
        for dbPath in findDatabases() {
            // 1. Section CK identifiers → display names
            var sectionNames = [String: String]()
            queryRows(dbPath: dbPath, sql: """
                SELECT ZCKIDENTIFIER, ZDISPLAYNAME FROM ZREMCDBASESECTION
                WHERE ZMARKEDFORDELETION = 0 AND ZDISPLAYNAME IS NOT NULL
                """) { stmt in
                guard let ckidPtr = sqlite3_column_text(stmt, 0),
                      let namePtr = sqlite3_column_text(stmt, 1) else { return }
                sectionNames[String(cString: ckidPtr)] = String(cString: namePtr)
            }
            guard !sectionNames.isEmpty else { continue }

            // 2. Reminder CK identifiers → lookup keys
            var reminderKeysByCkid = [String: String]()
            queryRows(dbPath: dbPath, sql: """
                SELECT r.ZCKIDENTIFIER, r.ZTITLE, l.ZNAME
                FROM ZREMCDREMINDER r
                JOIN ZREMCDBASELIST l ON r.ZLIST = l.Z_PK
                WHERE r.ZMARKEDFORDELETION = 0
                """) { stmt in
                guard let ckidPtr = sqlite3_column_text(stmt, 0),
                      let titlePtr = sqlite3_column_text(stmt, 1),
                      let listPtr = sqlite3_column_text(stmt, 2) else { return }
                reminderKeysByCkid[String(cString: ckidPtr)] =
                    lookupKey(listName: String(cString: listPtr), title: String(cString: titlePtr))
            }

            // 3. Parse membership JSON blobs to map reminders → sections
            queryRows(dbPath: dbPath, sql: """
                SELECT ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA
                FROM ZREMCDBASELIST
                WHERE ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA IS NOT NULL
                """) { stmt in
                guard let blobPtr = sqlite3_column_blob(stmt, 0) else { return }
                let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                let data = Data(bytes: blobPtr, count: blobSize)

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let memberships = json["memberships"] as? [[String: Any]] else { return }

                for membership in memberships {
                    guard let memberID = membership["memberID"] as? String,
                          let groupID = membership["groupID"] as? String,
                          let lookupKey = reminderKeysByCkid[memberID],
                          let sectionName = sectionNames[groupID] else { continue }
                    result[lookupKey] = sectionName
                }
            }
        }
        return result
    }

    // MARK: - Private

    private static func queryRows(dbPath: String, sql: String, row: (OpaquePointer) -> Void) {
        guard let db = openReadOnly(dbPath) else { return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt)
        }
    }

    private static let containerPath =
        NSHomeDirectory() + "/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"

    private static func findDatabases() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: containerPath) else { return [] }
        return files
            .filter { $0.hasPrefix("Data-") && $0.hasSuffix(".sqlite") && $0 != "Data-local.sqlite" } // Data-local.sqlite has a different schema (no ZREMCDREMINDER table)
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
