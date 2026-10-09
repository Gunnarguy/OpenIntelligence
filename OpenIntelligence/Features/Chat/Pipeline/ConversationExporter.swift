//
//  ConversationExporter.swift
//  OpenIntelligence
//

import Foundation

/// Writes a whole conversation to a file: Markdown for reading, JSON Lines for other tools.
///
/// Through 5.6 the only export was the diagnostic trace of one answer. Each answer here carries the
/// same source list a shared answer does (`AnswerShareFormatter`). Messages the person hid, and
/// system messages, are left out.
nonisolated enum ConversationExporter {
    enum Format: String, CaseIterable, Sendable {
        case markdown
        case jsonLines

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .jsonLines: return "jsonl"
            }
        }

        var menuTitle: String {
            switch self {
            case .markdown: return "Markdown"
            case .jsonLines: return "JSON Lines"
            }
        }
    }

    static let defaultTitle = "Conversation"
    static let maxTitleLength = 80

    /// The messages an export contains, in order.
    static func exportable(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .system && !$0.isHidden }
    }

    // MARK: - Markdown

    static func markdown(
        messages: [ChatMessage],
        title: String? = nil,
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current,
        appLink: URL = OpenIntelligenceLinks.sharedAppStoreURL
    ) -> String {
        let kept = exportable(messages)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = timeZone
        stamp.dateFormat = "yyyy-MM-dd HH:mm"

        var blocks: [String] = []
        blocks.append("# \(cleanTitle(title))")
        blocks.append(
            "Exported from OpenIntelligence on \(stamp.string(from: exportedAt)). "
                + "\(kept.count) message\(kept.count == 1 ? "" : "s").")

        for message in kept {
            let speaker = message.role == .user ? "You" : "OpenIntelligence"
            var block = "## \(speaker), \(stamp.string(from: message.timestamp))\n\n"
            block += message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.role == .assistant {
                let sources = sources(of: message)
                if !sources.isEmpty {
                    block += "\n\nSources:\n" + sources.map(AnswerShareFormatter.line(for:)).joined(separator: "\n")
                }
            }
            blocks.append(block)
        }

        blocks.append("---\n\n\(appLink.absoluteString)")
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - JSON Lines

    /// One JSON object per line: `role`, `content`, `timestamp` (ISO 8601, UTC) and, on an answer,
    /// `sources` and `model`. Keys are sorted, so the same conversation always gives the same bytes.
    static func jsonLines(messages: [ChatMessage]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: "UTC")

        var lines: [String] = []
        for message in exportable(messages) {
            var record: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content,
                "timestamp": iso.string(from: message.timestamp),
            ]
            if message.role == .assistant {
                let sources = sources(of: message)
                if !sources.isEmpty {
                    record["sources"] = sources.map { source -> [String: Any] in
                        var entry: [String: Any] = ["document": source.document, "pages": source.pages]
                        if let label = source.label { entry["label"] = label }
                        return entry
                    }
                }
                if let model = message.metadata?.modelUsed, !model.isEmpty {
                    record["model"] = model
                }
            }
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]),
                let line = String(data: data, encoding: .utf8)
            else {
                continue
            }
            lines.append(line)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Files

    static func fileName(title: String?, format: Format, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"

        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let safe = cleanTitle(title)
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
        let base = String((safe.isEmpty ? defaultTitle : safe).prefix(60))
        return "\(base) \(day.string(from: date)).\(format.fileExtension)"
    }

    /// Writes the export under the temporary directory and returns its address, for the share sheet.
    static func writeTemporaryFile(
        messages: [ChatMessage],
        title: String?,
        format: Format,
        date: Date = Date()
    ) throws -> URL {
        let text: String
        switch format {
        case .markdown: text = markdown(messages: messages, title: title, exportedAt: date)
        case .jsonLines: text = jsonLines(messages: messages)
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(title: title, format: format, date: date))
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

    private static func sources(of message: ChatMessage) -> [AnswerShareFormatter.Source] {
        AnswerShareFormatter.sources(
            answer: message.content,
            evidence: message.structuredAnswer?.evidence ?? [],
            retrievedChunks: message.retrievedChunks ?? []
        )
    }

    /// A title on one line, at most `maxTitleLength` characters. The chat screen passes the first
    /// question, which can run to a paragraph.
    private static func cleanTitle(_ title: String?) -> String {
        let oneLine = (title ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !oneLine.isEmpty else { return defaultTitle }
        guard oneLine.count > maxTitleLength else { return oneLine }
        return String(oneLine.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces) + "..."
    }
}

/// An exported file, identified so a sheet can be presented on it.
struct ConversationExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
