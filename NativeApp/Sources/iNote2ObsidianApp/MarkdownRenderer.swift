import Foundation

struct MarkdownRenderer {
    func render(
        note: SourceNote,
        stableBaseName: String,
        noteRelativePath: String,
        assetRelativeDir: String
    ) -> RenderedNote {
        let extracted = extractImages(from: note.htmlBody, stableBaseName: stableBaseName)
        let relativeAssetsPath = relativePath(from: noteRelativePath, to: assetRelativeDir)

        var lines: [String] = [
            "---",
            "source: apple-notes",
            "apple_note_id: \(yamlString(note.appleNoteID))",
            "created_at: \(yamlString(Self.isoString(note.createdAt)))",
            "updated_at: \(yamlString(Self.isoString(note.updatedAt)))",
            "source_folder: \(yamlString(note.folderPath))",
            "synced_at: \(yamlString(Self.isoString(Date())))",
            "---",
            ""
        ]

        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            lines.append("# \(trimmedTitle)")
            lines.append("")
        }

        let trimmedBody = effectivePlainText(for: note).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            lines.append(trimmedBody)
        }

        for asset in extracted.assets {
            lines.append("")
            lines.append("![](\(relativeAssetsPath)/\(asset.filename))")
        }

        let assetManifestHash = hashStrings(extracted.assets.map(\.filename))
        let assets = extracted.assets.map { asset in
            RenderedAsset(
                relativePath: "\(assetRelativeDir)/\(asset.filename)",
                data: asset.data
            )
        }
        let markdown = lines.joined(separator: "\n") + "\n"

        return RenderedNote(
            markdown: markdown,
            contentHash: hashStrings([note.title, effectivePlainText(for: note), note.htmlBody]),
            assetManifestHash: assetManifestHash,
            assets: assets,
            warnings: extracted.warnings
        )
    }

    private func effectivePlainText(for note: SourceNote) -> String {
        let text = note.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        return stripHTML(note.htmlBody)
    }

    private func relativePath(from noteRelativePath: String, to assetRelativeDir: String) -> String {
        let folder = (noteRelativePath as NSString).deletingLastPathComponent
        let depth = folder.isEmpty ? 0 : folder.split(separator: "/").count
        let prefix = Array(repeating: "..", count: depth).joined(separator: "/")
        return prefix.isEmpty ? assetRelativeDir : "\(prefix)/\(assetRelativeDir)"
    }

    private func extractImages(from html: String, stableBaseName: String) -> (assets: [(filename: String, data: Data)], warnings: [String]) {
        guard !html.isEmpty else {
            return ([], [])
        }

        let pattern = #"(?i)<img[^>]+src=\"([^\"]+)\"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ([], ["Failed to prepare HTML image parser."])
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var assets: [(filename: String, data: Data)] = []
        var warnings: [String] = []

        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges > 1 else { continue }
            let src = nsHTML.substring(with: match.range(at: 1))
            if let parsed = decodeImageSource(src: src, stableBaseName: stableBaseName, index: index + 1) {
                assets.append(parsed)
            } else {
                warnings.append("Skipped unsupported image source: \(src.prefix(80))")
            }
        }

        return (assets, warnings)
    }

    private func decodeImageSource(src: String, stableBaseName: String, index: Int) -> (filename: String, data: Data)? {
        if src.hasPrefix("data:image/"), let comma = src.firstIndex(of: ",") {
            let header = String(src[..<comma])
            let payload = String(src[src.index(after: comma)...])
            let mime = header
                .replacingOccurrences(of: "data:", with: "")
                .components(separatedBy: ";")
                .first ?? "image/png"
            guard let data = Data(base64Encoded: payload) else { return nil }
            return ("\(stableBaseName)-\(index).\(fileExtension(for: mime))", data)
        }

        if src.hasPrefix("file://"), let url = URL(string: src), let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.isEmpty ? "bin" : sanitizePathComponent(url.pathExtension)
            return ("\(stableBaseName)-\(index).\(ext)", data)
        }

        return nil
    }

    private func fileExtension(for mime: String) -> String {
        switch mime.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        default: return "bin"
        }
    }

    private func yamlString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func hashStrings(_ strings: [String]) -> String {
        var hash: UInt64 = 1469598103934665603
        for string in strings {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            hash ^= 10
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func sanitizePathComponent(_ string: String) -> String {
        string.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
