//
//  ConversationExporter.swift
//  OpenIntelligence
//

import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

/// Writes a whole conversation to a file: Markdown for reading, JSON Lines for other tools, and
/// PDF for printing or sending to someone without the app (5.7).
///
/// Through 5.6 the only export was the diagnostic trace of one answer. Each answer here carries the
/// same source list a shared answer does (`AnswerShareFormatter`). Messages the person hid, and
/// system messages, are left out.
nonisolated enum ConversationExporter {
    enum Format: String, CaseIterable, Sendable {
        case markdown
        case jsonLines
        case pdf

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .jsonLines: return "jsonl"
            case .pdf: return "pdf"
            }
        }

        var menuTitle: String {
            switch self {
            case .markdown: return "Markdown"
            case .jsonLines: return "JSON Lines"
            case .pdf: return "PDF"
            }
        }

        /// The file's type, for a shortcut that passes the file on. The system knows `md` and `pdf`;
        /// a type it does not know for `jsonl` is plain text.
        var contentType: UTType {
            switch self {
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            case .jsonLines: return UTType(filenameExtension: "jsonl") ?? .plainText
            case .pdf: return .pdf
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

    /// The export's bytes in one format.
    static func data(messages: [ChatMessage], title: String?, format: Format, date: Date = Date()) -> Data {
        switch format {
        case .markdown: return Data(markdown(messages: messages, title: title, exportedAt: date).utf8)
        case .jsonLines: return Data(jsonLines(messages: messages).utf8)
        case .pdf: return pdf(messages: messages, title: title, exportedAt: date)
        }
    }

    /// Writes the export under the temporary directory and returns its address, for the share sheet.
    static func writeTemporaryFile(
        messages: [ChatMessage],
        title: String?,
        format: Format,
        date: Date = Date()
    ) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(title: title, format: format, date: date))
        try data(messages: messages, title: title, format: format, date: date).write(to: url, options: .atomic)
        return url
    }

    // MARK: - PDF

    /// US Letter where the system measures in US units, A4 elsewhere, in points.
    static var pdfPageSize: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
    }

    /// The same content as the Markdown export, set as text: the title, when it was exported, then
    /// each message with who wrote it and when, and an answer's sources under it. Markdown marks are
    /// taken out of the messages. Pages break where the text no longer fits (Core Text), so the
    /// same code runs on iPhone, iPad and Mac.
    static func pdf(
        messages: [ChatMessage],
        title: String? = nil,
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current,
        pageSize: CGSize = pdfPageSize,
        appLink: URL = OpenIntelligenceLinks.sharedAppStoreURL
    ) -> Data {
        let kept = exportable(messages)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = timeZone
        stamp.dateFormat = "yyyy-MM-dd HH:mm"

        let text = NSMutableAttributedString()
        func add(_ string: String, size: CGFloat, bold: Bool = false, secondary: Bool = false, after: CGFloat = 4) {
            let font =
                CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            var spacing = after
            let paragraph = withUnsafePointer(to: &spacing) { pointer in
                var settings = [
                    CTParagraphStyleSetting(
                        spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: pointer)
                ]
                return CTParagraphStyleCreate(&settings, settings.count)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: secondary ? 0.4 : 0, alpha: 1),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ]
            text.append(NSAttributedString(string: string + "\n", attributes: attributes))
        }

        add(cleanTitle(title), size: 20, bold: true, after: 6)
        add(
            "Exported from OpenIntelligence on \(stamp.string(from: exportedAt)). "
                + "\(kept.count) message\(kept.count == 1 ? "" : "s").", size: 10, secondary: true, after: 18)
        for message in kept {
            let speaker = message.role == .user ? "You" : "OpenIntelligence"
            add("\(speaker), \(stamp.string(from: message.timestamp))", size: 12, bold: true, after: 4)
            add(plain(message.content), size: 11, after: 8)
            if message.role == .assistant {
                let sources = sources(of: message)
                if !sources.isEmpty {
                    add(
                        "Sources:\n" + sources.map(AnswerShareFormatter.line(for:)).joined(separator: "\n"),
                        size: 9.5, secondary: true, after: 8)
                }
            }
            add("", size: 6, after: 6)
        }
        add(appLink.absoluteString, size: 9, secondary: true)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info = [kCGPDFContextTitle as String: cleanTitle(title), kCGPDFContextCreator as String: "OpenIntelligence"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: mediaBox.insetBy(dx: 54, dy: 54), transform: nil)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let shown = CTFrameGetVisibleStringRange(frame).length
            // A page that took nothing would be followed by the same page forever.
            guard shown > 0 else { break }
            location += shown
        } while location < text.length
        context.closePDF()
        return data as Data
    }

    /// A message as the chat shows it, without its Markdown marks. A heading's "#" marks and a
    /// list's "*", "-" or "+" at the start of a line are taken off (a list item gets "•"); the rest
    /// is read by the parser the chat's own text uses (`MarkdownText`), so emphasis and code marks
    /// go where the chat reads them as marks and stay where it does not ("2 * 3 = 6",
    /// "snake_case_name").
    static func plain(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            var line = line
            if let heading = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                line.removeSubrange(heading)
            } else if let bullet = line.range(of: #"^(\s*)[*+-]\s+"#, options: .regularExpression) {
                let indent = line[bullet].prefix { $0 == " " || $0 == "\t" }
                line.replaceSubrange(bullet, with: indent + "• ")
            }
            return line
        }
        let text = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let read = (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text
        return read.trimmingCharacters(in: .whitespacesAndNewlines)
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
