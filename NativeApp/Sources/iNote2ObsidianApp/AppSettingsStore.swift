import Foundation

final class AppSettingsStore {
    private let settingsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("iNote2Obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.settingsURL = root.appendingPathComponent("settings.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .default
        }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? .default
    }

    func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    var stateDirectory: URL {
        settingsURL.deletingLastPathComponent()
    }
}
