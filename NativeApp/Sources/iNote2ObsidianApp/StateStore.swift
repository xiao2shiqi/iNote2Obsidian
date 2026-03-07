import Foundation
import SQLite3

final class StateStore: @unchecked Sendable {
    private var db: OpaquePointer?

    init(dbURL: URL) throws {
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw SyncError.db(Self.message(for: db))
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func fetchStates() throws -> [ManagedNoteState] {
        let sql = """
        SELECT apple_note_id, created_at, updated_at, source_folder_path, note_relative_path, asset_relative_dir,
               content_hash, asset_manifest_hash, last_seen_at, missing_scan_count, is_deleted
        FROM notes_state
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SyncError.db(Self.message(for: db))
        }
        defer { sqlite3_finalize(statement) }

        var result: [ManagedNoteState] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                ManagedNoteState(
                    appleNoteID: Self.columnText(statement, index: 0),
                    createdAt: Self.columnText(statement, index: 1),
                    updatedAt: Self.columnText(statement, index: 2),
                    sourceFolderPath: Self.columnText(statement, index: 3),
                    noteRelativePath: Self.columnText(statement, index: 4),
                    assetRelativeDir: Self.columnText(statement, index: 5),
                    contentHash: Self.columnText(statement, index: 6),
                    assetManifestHash: Self.columnText(statement, index: 7),
                    lastSeenAt: Self.columnText(statement, index: 8),
                    missingScanCount: Int(sqlite3_column_int(statement, 9)),
                    isDeleted: sqlite3_column_int(statement, 10) != 0
                )
            )
        }
        return result
    }

    func upsert(_ state: ManagedNoteState) throws {
        let sql = """
        INSERT INTO notes_state (
            apple_note_id, created_at, updated_at, source_folder_path, note_relative_path, asset_relative_dir,
            content_hash, asset_manifest_hash, last_seen_at, missing_scan_count, is_deleted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(apple_note_id) DO UPDATE SET
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            source_folder_path = excluded.source_folder_path,
            note_relative_path = excluded.note_relative_path,
            asset_relative_dir = excluded.asset_relative_dir,
            content_hash = excluded.content_hash,
            asset_manifest_hash = excluded.asset_manifest_hash,
            last_seen_at = excluded.last_seen_at,
            missing_scan_count = excluded.missing_scan_count,
            is_deleted = excluded.is_deleted
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SyncError.db(Self.message(for: db))
        }
        defer { sqlite3_finalize(statement) }

        Self.bindText(state.appleNoteID, to: statement, index: 1)
        Self.bindText(state.createdAt, to: statement, index: 2)
        Self.bindText(state.updatedAt, to: statement, index: 3)
        Self.bindText(state.sourceFolderPath, to: statement, index: 4)
        Self.bindText(state.noteRelativePath, to: statement, index: 5)
        Self.bindText(state.assetRelativeDir, to: statement, index: 6)
        Self.bindText(state.contentHash, to: statement, index: 7)
        Self.bindText(state.assetManifestHash, to: statement, index: 8)
        Self.bindText(state.lastSeenAt, to: statement, index: 9)
        sqlite3_bind_int(statement, 10, Int32(state.missingScanCount))
        sqlite3_bind_int(statement, 11, state.isDeleted ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SyncError.db(Self.message(for: db))
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS notes_state (
            apple_note_id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            source_folder_path TEXT NOT NULL,
            note_relative_path TEXT NOT NULL,
            asset_relative_dir TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            asset_manifest_hash TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            missing_scan_count INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SyncError.db(Self.message(for: db))
        }
    }

    private static func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func message(for db: OpaquePointer?) -> String {
        guard let db else { return "unknown sqlite error" }
        return String(cString: sqlite3_errmsg(db))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
