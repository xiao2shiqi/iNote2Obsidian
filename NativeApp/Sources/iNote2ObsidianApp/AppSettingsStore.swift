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
        guard
            let data = try? Data(contentsOf: settingsURL),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    var stateDirectory: URL {
        appSupportDirectory.appendingPathComponent("State", isDirectory: true)
    }
}
