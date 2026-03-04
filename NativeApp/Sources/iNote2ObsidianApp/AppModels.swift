import Foundation

enum SyncStatus: String, Codable {
    case idle
    case syncing
    case success
    case failedPermission
    case failedRuntime
}

enum SyncInterval: String, CaseIterable, Identifiable, Codable {
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case sixtyMinutes = "60m"
    case oneEightyMinutes = "180m"
    case off = "off"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: return "Every 5 minutes"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .sixtyMinutes: return "Every 60 minutes"
        case .oneEightyMinutes: return "Every 180 minutes"
        case .off: return "Off"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .sixtyMinutes: return 3600
        case .oneEightyMinutes: return 10800
        case .off: return nil
        }
    }
}

struct SyncRunStats: Codable, Equatable {
    var startedAt: Date
    var endedAt: Date
    var added: Int
    var updated: Int
    var skipped: Int
    var deleted: Int
    var errors: Int
    var status: SyncStatus
}

struct SourceAttachment {
    var mimeType: String
    var data: Data
}

struct SourceNote {
    var noteID: String
    var title: String
    var folderPath: String
    var createdAt: Date
    var updatedAt: Date
    var bodyPlain: String
    var bodyHTML: String
    var inlineAttachments: [SourceAttachment]
}

struct RenderedNote {
    var markdown: String
    var folderPath: String
    var preferredMarkdownFilename: String
    var sourceNoteID: String
    var attachments: [RenderedAttachment]
}

struct RenderedAttachment {
    var relativePath: String
    var data: Data
}

struct AppSettings: Codable, Equatable {
    var outputRootPath: String
    var syncInterval: SyncInterval
    var excludeRecentlyDeleted: Bool
    var autoStartAtLogin: Bool

    static var `default`: AppSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultOutput = home.appendingPathComponent("Documents/iNote").path
        return AppSettings(
            outputRootPath: defaultOutput,
            syncInterval: .fiveMinutes,
            excludeRecentlyDeleted: true,
            autoStartAtLogin: true
        )
    }
}

enum SyncError: Error {
    case permissionDenied(String)
    case bridgeFailed(String)
    case invalidPayload(String)
    case io(String)
    case db(String)
}
