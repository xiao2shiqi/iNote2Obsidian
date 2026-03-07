import Foundation

final class AppSettingsStore {
    let appSupportDirectory: URL
    private let settingsURL: URL

    init() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        appSupportDirectory = base.appendingPathComponent("iNote2Obsidian", isDirectory: true)
        settingsURL = appSupportDirectory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .default
        }
        if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        if let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            return AppSettings(
                vaultPath: legacy.outputRootPath,
                attachmentsFolderName: "attachments",
                pollIntervalSeconds: legacy.syncInterval == "1s" ? 1 : 1,
                lastRunMode: legacy.lastRunMode == "running" ? .running : .stopped
            )
        }
        return .default
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    var stateDirectory: URL {
        appSupportDirectory.appendingPathComponent("State", isDirectory: true)
    }
}

private struct LegacySettings: Decodable {
    var outputRootPath: String
    var syncInterval: String
    var lastRunMode: String
}
