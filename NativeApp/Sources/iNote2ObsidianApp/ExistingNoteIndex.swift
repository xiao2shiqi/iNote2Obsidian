import Foundation

struct ExistingNoteIndex {
    let bySourceID: [String: String]

    static func build(outputRoot: URL, logger: AppLogger) -> ExistingNoteIndex {
        var bestByID: [String: (relativePath: String, modifiedAt: Date)] = [:]
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: outputRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ExistingNoteIndex(bySourceID: [:])
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let sourceID = extractSourceNoteID(from: fileURL) else { continue }

            let rel = relativePath(from: outputRoot, to: fileURL)
            let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = attrs?.contentModificationDate ?? Date.distantPast

            if let existing = bestByID[sourceID] {
                if modified > existing.modifiedAt {
                    bestByID[sourceID] = (rel, modified)
                    logger.info("duplicate source_note_id found, choose newer file: \(sourceID)")
                }
            } else {
                bestByID[sourceID] = (rel, modified)
            }
        }

        return ExistingNoteIndex(bySourceID: bestByID.mapValues { $0.relativePath })
    }

    private static func relativePath(from root: URL, to fileURL: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if fileURL.path.hasPrefix(rootPath) {
            return String(fileURL.path.dropFirst(rootPath.count))
        }
        return fileURL.lastPathComponent
    }

    private static func extractSourceNoteID(from fileURL: URL) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return extractSourceNoteID(fromMarkdown: text)
    }

    static func extractSourceNoteID(fromMarkdown markdown: String) -> String? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                break
            }
            if trimmed.hasPrefix("source_note_id:") {
                let value = trimmed
                    .split(separator: ":", maxSplits: 1)
                    .dropFirst()
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                if let value, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }
}
