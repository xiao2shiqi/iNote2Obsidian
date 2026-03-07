import Foundation

struct ExistingNoteIndex {
    struct Entry {
        let relativePath: String
        let contentHash: String?
    }

    let bySourceID: [String: Entry]

    static func build(outputRoot: URL, logger: AppLogger) -> ExistingNoteIndex {
        var bestByID: [String: (entry: Entry, modifiedAt: Date)] = [:]
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
            guard let frontmatter = extractFrontmatter(from: fileURL) else { continue }

            let rel = relativePath(from: outputRoot, to: fileURL)
            let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = attrs?.contentModificationDate ?? Date.distantPast
            let entry = Entry(relativePath: rel, contentHash: frontmatter.contentHash)

            if let existing = bestByID[frontmatter.sourceID] {
                if modified > existing.modifiedAt {
                    bestByID[frontmatter.sourceID] = (entry, modified)
                    logger.info("duplicate source_note_id found, choose newer file: \(frontmatter.sourceID)")
                }
            } else {
                bestByID[frontmatter.sourceID] = (entry, modified)
            }
        }

        return ExistingNoteIndex(bySourceID: bestByID.mapValues { $0.entry })
    }

    private static func relativePath(from root: URL, to fileURL: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if fileURL.path.hasPrefix(rootPath) {
            return String(fileURL.path.dropFirst(rootPath.count))
        }
        return fileURL.lastPathComponent
    }

    private static func extractFrontmatter(from fileURL: URL) -> (sourceID: String, contentHash: String?)? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return extractFrontmatter(fromMarkdown: text)
    }

    static func extractSourceNoteID(fromMarkdown markdown: String) -> String? {
        extractFrontmatter(fromMarkdown: markdown)?.sourceID
    }

    static func extractSourceContentHash(fromMarkdown markdown: String) -> String? {
        extractFrontmatter(fromMarkdown: markdown)?.contentHash
    }

    private static func extractFrontmatter(fromMarkdown markdown: String) -> (sourceID: String, contentHash: String?)? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var sourceID: String?
        var contentHash: String?
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                break
            }
            if trimmed.hasPrefix("source_note_id:") {
                sourceID = extractValue(from: trimmed)
            }
            if trimmed.hasPrefix("source_content_hash:") {
                contentHash = extractValue(from: trimmed)
            }
        }
        guard let sourceID, !sourceID.isEmpty else { return nil }
        return (sourceID, contentHash)
    }

    private static func extractValue(from line: String) -> String? {
        line
            .split(separator: ":", maxSplits: 1)
            .dropFirst()
            .first?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
    }
}
