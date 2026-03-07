import Foundation

enum SyncRunMode: String, Codable {
    case stopped
    case running
}

enum AppStatus: String, Codable {
    case idle
    case syncing
    case healthy
    case warning
    case error
}

struct AppSettings: Codable, Equatable {
    var vaultPath: String
    var attachmentsFolderName: String
    var pollIntervalSeconds: TimeInterval
    var lastRunMode: SyncRunMode

    static var `default`: AppSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppSettings(
            vaultPath: home.appendingPathComponent("Documents/Obsidian").path,
            attachmentsFolderName: "attachments",
            pollIntervalSeconds: 1,
            lastRunMode: .stopped
        )
    }
}

struct SourceImage: Equatable {
    var suggestedFilename: String?
    var mimeType: String
    var data: Data
}

struct SourceNote: Equatable {
    var appleNoteID: String
    var title: String
    var folderPath: String
    var createdAt: Date
    var updatedAt: Date
    var plainText: String
    var htmlBody: String
}

struct RenderedAsset: Equatable {
    var relativePath: String
    var data: Data
}

struct RenderedNote: Equatable {
    var markdown: String
    var contentHash: String
    var assetManifestHash: String
    var assets: [RenderedAsset]
    var warnings: [String]
}

struct ManagedNoteState: Equatable {
    var appleNoteID: String
    var createdAt: String
    var updatedAt: String
    var sourceFolderPath: String
    var noteRelativePath: String
    var assetRelativeDir: String
    var contentHash: String
    var assetManifestHash: String
    var lastSeenAt: String
    var missingScanCount: Int
    var isDeleted: Bool
}

enum SyncAction: Equatable {
    case create(PlannedNote)
    case update(PlannedNote, previous: ManagedNoteState)
    case move(PlannedNote, previous: ManagedNoteState)
    case delete(ManagedNoteState)
    case markMissing(ManagedNoteState, nextMissingCount: Int)
    case noop(PlannedNote, previous: ManagedNoteState)
}

struct PlannedNote: Equatable {
    var note: SourceNote
    var stableBaseName: String
    var noteRelativePath: String
    var assetRelativeDir: String
}

struct SyncRunSummary: Equatable {
    var scannedCount: Int
    var createdCount: Int
    var updatedCount: Int
    var movedCount: Int
    var deletedCount: Int
    var warningCount: Int
    var errorCount: Int
    var duration: TimeInterval
}

enum SyncError: Error, LocalizedError {
    case permissionDenied
    case bridgeFailed(String)
    case invalidVaultPath
    case io(String)
    case db(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Apple Notes automation permission is required."
        case .bridgeFailed(let detail):
            return "Apple Notes bridge failed: \(detail)"
        case .invalidVaultPath:
            return "Choose an Obsidian vault directory before starting sync."
        case .io(let detail):
            return "I/O error: \(detail)"
        case .db(let detail):
            return "Database error: \(detail)"
        }
    }
}

struct SyncLogEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var message: String
}
