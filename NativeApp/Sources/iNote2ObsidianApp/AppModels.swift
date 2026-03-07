import Foundation

enum SyncRunMode: String, Codable {
    case stopped
    case running
}

enum SyncHealth: String, Codable {
    case ok
    case warning
}

enum SyncLampState: String {
    case red
    case green
    case yellow
}

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

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
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

enum SyncProgressStage {
    case fetching
    case queueReady
    case noteProcessed
    case completed
}

enum SyncNoteEventType {
    case added
    case updated
    case skipped
    case failed
}

struct SyncProgress {
    var stage: SyncProgressStage
    var total: Int
    var totalKnown: Bool
    var scanned: Int
    var synced: Int
    var pending: Int
    var currentNote: String?
    var eventType: SyncNoteEventType?
    var outputFile: String?
    var message: String?
    var queuePreview: [String]
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
    static let managedOutputDirectoryName = "apple-Notes"

    var outputRootPath: String
    var syncInterval: SyncInterval
    var excludeRecentlyDeleted: Bool
    var autoStartAtLogin: Bool
    var language: AppLanguage
    var lastRunMode: SyncRunMode
    var totalSyncRounds: Int

    private enum CodingKeys: String, CodingKey {
        case outputRootPath
        case syncInterval
        case excludeRecentlyDeleted
        case autoStartAtLogin
        case language
        case lastRunMode
        case totalSyncRounds
    }

    init(
        outputRootPath: String,
        syncInterval: SyncInterval,
        excludeRecentlyDeleted: Bool,
        autoStartAtLogin: Bool,
        language: AppLanguage,
        lastRunMode: SyncRunMode,
        totalSyncRounds: Int
    ) {
        self.outputRootPath = outputRootPath
        self.syncInterval = syncInterval
        self.excludeRecentlyDeleted = excludeRecentlyDeleted
        self.autoStartAtLogin = autoStartAtLogin
        self.language = language
        self.lastRunMode = lastRunMode
        self.totalSyncRounds = totalSyncRounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputRootPath = try container.decode(String.self, forKey: .outputRootPath)
        syncInterval = try container.decode(SyncInterval.self, forKey: .syncInterval)
        excludeRecentlyDeleted = try container.decode(Bool.self, forKey: .excludeRecentlyDeleted)
        autoStartAtLogin = try container.decode(Bool.self, forKey: .autoStartAtLogin)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        lastRunMode = try container.decode(SyncRunMode.self, forKey: .lastRunMode)
        totalSyncRounds = try container.decode(Int.self, forKey: .totalSyncRounds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputRootPath, forKey: .outputRootPath)
        try container.encode(syncInterval, forKey: .syncInterval)
        try container.encode(excludeRecentlyDeleted, forKey: .excludeRecentlyDeleted)
        try container.encode(autoStartAtLogin, forKey: .autoStartAtLogin)
        try container.encode(language, forKey: .language)
        try container.encode(lastRunMode, forKey: .lastRunMode)
        try container.encode(totalSyncRounds, forKey: .totalSyncRounds)
    }

    static var `default`: AppSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultOutput = home.appendingPathComponent("Documents/iNote").path
        return AppSettings(
            outputRootPath: defaultOutput,
            syncInterval: .fiveMinutes,
            excludeRecentlyDeleted: true,
            autoStartAtLogin: true,
            language: .english,
            lastRunMode: .stopped,
            totalSyncRounds: 0
        )
    }

    var managedOutputRootPath: String {
        URL(fileURLWithPath: outputRootPath, isDirectory: true)
            .appendingPathComponent(Self.managedOutputDirectoryName, isDirectory: true)
            .path
    }
}

enum SyncError: Error {
    case permissionDenied(String)
    case bridgeFailed(String)
    case invalidPayload(String)
    case io(String)
    case db(String)
    case cancelled
}

final class SyncCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
