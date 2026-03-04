import Foundation

struct MarkdownTransformer {
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f
    }()

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func render(note: SourceNote, outputRoot: URL, runDate: Date) -> RenderedNote {
        let folderPath = sanitizeFolderPath(note.folderPath)
        let baseName = timestampFormatter.string(from: note.createdAt)
        let preferredMarkdownFilename = baseName + ".md"

        var bodyLines: [String] = []
        bodyLines.append("---")
        bodyLines.append("source: apple_notes")
        bodyLines.append("source_note_id: \"\(note.noteID)\"")
        bodyLines.append("source_folder: \"\(folderPath)\"")
        bodyLines.append("source_created_at: \"\(isoFormatter.string(from: note.createdAt))\"")
        bodyLines.append("source_updated_at: \"\(isoFormatter.string(from: note.updatedAt))\"")
        bodyLines.append("synced_at: \"\(isoFormatter.string(from: runDate))\"")
        bodyLines.append("is_deleted_in_source: false")
        bodyLines.append("---")
        bodyLines.append("")

        let trimmedPlain = note.bodyPlain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlain.isEmpty {
            bodyLines.append(trimmedPlain)
        }

        let attachmentFolder = "attachments"
        var attachments: [RenderedAttachment] = []
        for (idx, att) in note.inlineAttachments.enumerated() {
            let ext = fileExtension(for: att.mimeType)
            let ts = timestampFormatter.string(from: runDate)
            let filename = "\(ts)-\(idx + 1).\(ext)"
            let relPath = attachmentFolder + "/" + filename
            attachments.append(RenderedAttachment(relativePath: relPath, data: att.data))
            bodyLines.append("")
            let mdPath = relativePath(from: folderPath, to: relPath)
            bodyLines.append("![](" + mdPath + ")")
        }

        let markdown = bodyLines.joined(separator: "\n") + "\n"
        return RenderedNote(
            markdown: markdown,
            folderPath: folderPath,
            preferredMarkdownFilename: preferredMarkdownFilename,
            sourceNoteID: note.noteID,
            attachments: attachments
        )
    }

    func sanitizeFolderPath(_ path: String) -> String {
        let invalid = CharacterSet(charactersIn: "<>:\\|?*\0")
        return path
            .split(separator: "/")
            .map { segment in
                var s = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
                s = s.components(separatedBy: invalid).joined(separator: "-")
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                return s.isEmpty ? "UntitledFolder" : s
            }
            .joined(separator: "/")
    }

    private func fileExtension(for mime: String) -> String {
        switch mime.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        default: return "bin"
        }
    }

    private func relativePath(from folderPath: String, to target: String) -> String {
        let depth = folderPath.isEmpty ? 0 : folderPath.split(separator: "/").count
        let prefix = Array(repeating: "..", count: depth).joined(separator: "/")
        return prefix.isEmpty ? target : prefix + "/" + target
    }
}
