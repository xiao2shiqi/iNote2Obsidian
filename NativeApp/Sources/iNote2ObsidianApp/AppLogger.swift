import Foundation

final class AppLogger: @unchecked Sendable {
    private let logURL: URL
    private let queue = DispatchQueue(label: "AppLogger.queue")
    var onLog: (@Sendable (SyncLogEntry) -> Void)?

    init(logURL: URL) {
        self.logURL = logURL
    }

    func info(_ message: String) {
        append(message)
    }

    func error(_ message: String) {
        append("ERROR: \(message)")
    }

    func readRecentLines(limit: Int = 200) -> [String] {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            return []
        }
        return Array(content.split(separator: "\n").suffix(limit)).map(String.init)
    }

    private func append(_ message: String) {
        let entry = SyncLogEntry(timestamp: Date(), message: message)
        let line = "[\(Self.timestampFormatter.string(from: entry.timestamp))] \(entry.message)\n"
        let logURL = self.logURL
        let callback = self.onLog

        queue.async {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: Data(), attributes: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
            DispatchQueue.main.async {
                callback?(entry)
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
