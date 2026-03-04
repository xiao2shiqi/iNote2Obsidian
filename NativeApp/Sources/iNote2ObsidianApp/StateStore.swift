import Foundation
import SQLite3

final class StateStore {
    private let dbURL: URL
    private var db: OpaquePointer?

    init(dbURL: URL) throws {
        self.dbURL = dbURL
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    struct NoteState {
        let noteID: String
        let contentHash: String
        let markdownRelativePath: String
        let isDeleted: Bool
    }

    func getNoteState(noteID: String) throws -> NoteState? {
        let sql = "SELECT note_id, content_hash, markdown_rel_path, is_deleted FROM notes_state WHERE note_id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncError.db(message())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return NoteState(
            noteID: String(cString: sqlite3_column_text(stmt, 0)),
            contentHash: String(cString: sqlite3_column_text(stmt, 1)),
            markdownRelativePath: String(cString: sqlite3_column_text(stmt, 2)),
            isDeleted: sqlite3_column_int(stmt, 3) != 0
        )
    }

    func upsertNoteState(noteID: String, folderPath: String, contentHash: String, markdownRelativePath: String, isDeleted: Bool) throws {
        let sql = """
        INSERT INTO notes_state (note_id, folder_path, content_hash, markdown_rel_path, is_deleted, last_synced_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(note_id) DO UPDATE SET
          folder_path = excluded.folder_path,
          content_hash = excluded.content_hash,
          markdown_rel_path = excluded.markdown_rel_path,
          is_deleted = excluded.is_deleted,
          last_synced_at = excluded.last_synced_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncError.db(message())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, folderPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, markdownRelativePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, isDeleted ? 1 : 0)
        sqlite3_bind_text(stmt, 6, isoNow(), -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SyncError.db(message()) }
    }

    func existingNoteIDs() throws -> [String] {
        let sql = "SELECT note_id FROM notes_state"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncError.db(message())
        }
        defer { sqlite3_finalize(stmt) }

        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return ids
    }

    func markDeleted(noteID: String) throws {
        let sql = "UPDATE notes_state SET is_deleted = 1, last_synced_at = ? WHERE note_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SyncError.db(message())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, isoNow(), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SyncError.db(message()) }
    }

    private func open() throws {
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw SyncError.db(message())
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS notes_state (
          note_id TEXT PRIMARY KEY,
          folder_path TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          markdown_rel_path TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          last_synced_at TEXT NOT NULL
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SyncError.db(message())
        }
    }

    private func message() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
