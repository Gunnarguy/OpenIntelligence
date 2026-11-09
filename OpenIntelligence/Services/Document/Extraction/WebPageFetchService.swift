//
//  WebPageFetchService.swift
//  OpenIntelligence
//

import Foundation

/// Downloads the page at a web address and turns it into a text file the import path can read.
///
/// Through 5.6 the "Ingest Webpage" action handed the web address to the import queue as if it
/// were a file on disk and answered "Extracting webpage in the background"; no code downloaded
/// anything. This is the download: a GET to the address the person gave (an `http` address is
/// asked for as `https`), following the site's own redirects (a `www` variant, a short link to its
/// target), on a session that keeps no cookies and no cache. The page's scripts are not run, so a page that draws its text with JavaScript yields
/// little or nothing, and `FetchError.noReadableText` says so.
nonisolated enum WebPageFetchService {
    /// What a fetch produced: a file name and the bytes to store under it.
    struct Fetched: Sendable, Equatable {
        let fileName: String
        let data: Data
        /// The page title, when the response was a web page.
        let title: String?
    }

    enum FetchError: LocalizedError, Equatable {
        case unsupportedAddress
        case httpStatus(Int)
        case tooLarge(bytes: Int)
        case unsupportedContent(String)
        case noReadableText

        var errorDescription: String? {
            switch self {
            case .unsupportedAddress:
                return "Only http and https addresses can be saved."
            case .httpStatus(let code):
                return "The site answered with status \(code)."
            case .tooLarge(let bytes):
                return
                    "That is \(bytes / 1_048_576) MB, over the limit (\(maxHTMLBytes / 1_048_576) MB for a web page, \(maxBytes / 1_048_576) MB for a file)."
            case .unsupportedContent(let type):
                return "The address returned \(type), which cannot be imported from a link."
            case .noReadableText:
                return "The page has no readable text without running its scripts."
            }
        }
    }

    static let maxBytes = 20 * 1_048_576

    /// A web page's markup is held to less than a file is. Its text is found with regular
    /// expressions over the whole page, and a page of unclosed tags makes those slow.
    static let maxHTMLBytes = 5 * 1_048_576

    /// A page with fewer characters of text than this is reported as unreadable.
    static let minimumReadableCharacters = 40

    // MARK: - Fetch

    /// The address that is requested for the one the person gave: the same, with `http` made
    /// `https`. The app's transport security refuses plain `http`, so asking for it would fail
    /// before reaching the site; a site that serves a page over `http` almost always serves it
    /// over `https` too.
    static func requestURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    static func fetch(_ url: URL, now: Date = Date()) async throws -> Fetched {
        guard let target = requestURL(for: url) else { throw FetchError.unsupportedAddress }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        // An action in the background has about 30 seconds in all.
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        // Whatever happens below, nothing is left downloading when this returns.
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: target)
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        // The status and the announced size are checked before the body is read, and the read stops
        // at the limit, so an error page or a very large file is refused without being downloaded.
        let (stream, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        if response.expectedContentLength > Int64(maxBytes) {
            throw FetchError.tooLarge(bytes: Int(clamping: response.expectedContentLength))
        }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(clamping: response.expectedContentLength))
        }
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)
        for try await byte in stream {
            buffer.append(byte)
            if buffer.count == 64 * 1024 {
                data.append(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if data.count > maxBytes { throw FetchError.tooLarge(bytes: data.count) }
            }
        }
        data.append(contentsOf: buffer)
        return try fetched(from: data, response: response, requestedURL: target, now: now)
    }

    /// Turns a response into a file. Separate from `fetch` so it can be tested without a network.
    static func fetched(from data: Data, response: URLResponse, requestedURL: URL, now: Date = Date()) throws -> Fetched
    {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        guard data.count <= maxBytes else { throw FetchError.tooLarge(bytes: data.count) }

        let finalURL = response.url ?? requestedURL
        let mime = (response.mimeType ?? "").lowercased()
        let pathExtension = finalURL.pathExtension.lowercased()

        let looksLikeHTML =
            mime == "text/html" || mime == "application/xhtml+xml"
            || (mime.isEmpty && (pathExtension.isEmpty || pathExtension == "html" || pathExtension == "htm"))
        if looksLikeHTML {
            guard data.count <= maxHTMLBytes else { throw FetchError.tooLarge(bytes: data.count) }
            let html = decode(data, encodingName: response.textEncodingName)
            let page = readableText(fromHTML: html)
            guard page.text.count >= minimumReadableCharacters else { throw FetchError.noReadableText }
            let title = page.title ?? finalURL.host ?? "Web page"
            let document = markdownDocument(title: title, text: page.text, source: finalURL, savedAt: now)
            return Fetched(fileName: fileName(title: title, extension: "md"), data: Data(document.utf8), title: title)
        }

        // A link straight to a file the import path already reads is saved as that file.
        if let fileExtension = importableExtension(mime: mime, pathExtension: pathExtension) {
            let stem = finalURL.deletingPathExtension().lastPathComponent
            return Fetched(
                fileName: fileName(
                    title: stem.isEmpty ? (finalURL.host ?? "Download") : stem, extension: fileExtension),
                data: data,
                title: nil)
        }
        throw FetchError.unsupportedContent(mime.isEmpty ? "an unknown type" : mime)
    }

    private static func importableExtension(mime: String, pathExtension: String) -> String? {
        switch mime {
        case "application/pdf": return "pdf"
        case "text/plain":
            return ["md", "markdown", "csv", "json", "jsonl", "ndjson"].contains(pathExtension) ? pathExtension : "txt"
        case "text/markdown": return "md"
        case "text/csv": return "csv"
        case "application/json": return pathExtension == "jsonl" || pathExtension == "ndjson" ? pathExtension : "json"
        case "application/x-ndjson", "application/jsonl", "application/x-jsonlines": return "jsonl"
        default: return nil
        }
    }

    /// Decodes a page with the character set the response names, or the one the page's own
    /// `<meta>` tag names, or UTF-8. Bytes that fit none of them are logged and replaced, never
    /// dropped without a word.
    static func decode(_ data: Data, encodingName: String?) -> String {
        for name in [encodingName, declaredCharset(in: data)].compactMap({ $0 }) {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { continue }
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            if let text = String(data: data, encoding: encoding) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) {
            Log.warning(
                "[WebPageFetch] The page named no usable character set and is not UTF-8; read as Windows-1252",
                category: .ingestion)
            return text
        }
        Log.warning(
            "[WebPageFetch] The page's bytes fit no character set tried; unreadable bytes are shown as replacement characters",
            category: .ingestion)
        return String(decoding: data, as: UTF8.self)
    }

    /// The character set a page names in its first 4 KB (`<meta charset="...">` or the older
    /// `content="text/html; charset=..."`).
    static func declaredCharset(in data: Data) -> String? {
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        return firstMatch(#"<meta[^>]*charset\s*=\s*["']?\s*([A-Za-z0-9_.:-]+)"#, in: head)
    }

    // MARK: - HTML to text

    /// A tag's attributes, with quoted values skipped, so a ">" inside one (`<a title="x > y">`) does not end
    /// the tag (5.8: the rest of the attribute was imported as page text).
    private static let attributes = #"(?:"[^"]*"|'[^']*'|[^'">])*"#

    /// Any start or end tag, comment-like declaration or processing instruction.
    private static let anyTag = "<[A-Za-z!?/]\(attributes)>"

    /// Tags that end a line of text. Inside a table cell they become " <br> ", inside a list item a space.
    private static let blockTags =
        "</?(?:p|div|section|article|main|header|aside|blockquote|figure|figcaption|dl|dt|dd|hr|form|summary|details|h[1-6]|address|fieldset|legend)\\b\(attributes)>"

    /// Elements that have no end tag.
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]

    /// Marks where a block rendered on its own (a table, a list, preformatted text) goes back into the text. The
    /// two characters are private-use code points, which a page's text does not contain.
    private static let blockToken = "\u{E000}([0-9]+)\u{E001}"

    /// The page's title and its text, with headings and list items marked the way Markdown marks
    /// them. Scripts, styles, navigation and footers are left out; nothing is executed.
    ///
    /// Tables, lists and preformatted text are rendered whole, innermost first, and put back where they were
    /// (5.8). Through 5.7 every tag was rewritten in turn over the whole page: a `<p>` inside a cell broke the
    /// row, an `<ol>` lost its numbers, a nested list lost its level, `<pre>` code lost its line breaks,
    /// "x<sup>2</sup>" read "x2", and a table had no header row.
    static func readableText(fromHTML html: String) -> (title: String?, text: String) {
        let title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html).map(decodeEntities).map(collapseWhitespace)

        var text = html
        text = replace(#"<!--.*?-->"#, in: text, with: " ")
        // A button's label and a <summary> are text a reader sees and are kept (5.8).
        for tag in ["script", "style", "noscript", "svg", "template", "iframe", "head", "nav", "footer", "select"] {
            // Nothing to scan for when the page has no such element.
            guard text.range(of: "<\(tag)", options: .caseInsensitive) != nil else { continue }
            // The self-closed form first ("<svg ... />"), or its opener would run to the next closer.
            text = replace("<\(tag)\\b\(attributes)/>", in: text, with: " ")
            text = replace("<\(tag)\\b\(attributes)>.*?</\(tag)\\s*>", in: text, with: " ")
        }
        text = removingHiddenElements(text)

        var blocks: [String] = []
        func token(_ block: String) -> String {
            blocks.append(block)
            return "\u{E000}\(blocks.count - 1)\u{E001}"
        }
        func expand(_ fragment: String) -> String {
            var result = fragment
            for _ in 0..<8 where result.contains("\u{E000}") {
                result = replaceEach(blockToken, in: result) { captures in
                    Int(captures[1]).flatMap { blocks.indices.contains($0) ? blocks[$0] : nil } ?? ""
                }
            }
            return result
        }

        // Preformatted text keeps its line breaks, fenced as code; it is set aside before the page's own line
        // breaks are collapsed.
        text = replaceEach("<pre\\b\(attributes)>(.*?)</pre\\s*>", in: text) { captures in
            var code = replace(#"<br\s*/?>"#, in: captures[1], with: "\n")
            code = decodeEntities(replace(anyTag, in: code, with: ""))
            code = code.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            // A line break right after <pre> is not part of its text (HTML standard, the pre element).
            if code.hasPrefix("\n") { code.removeFirst() }
            while code.last?.isWhitespace == true { code.removeLast() }
            guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return " " }
            return "<div>" + token("```\n" + code + "\n```") + "</div>"
        }

        // The page's own line breaks mean nothing in HTML; the tags decide where lines go.
        text = replace(#"\s+"#, in: text, with: " ")

        // Superscript and subscript are marked, so "10<sup>3</sup>" reads "10^3" and "H<sub>2</sub>O" "H_2O".
        text = replace("<sup\\b\(attributes)>", in: text, with: "^")
        text = replace("<sub\\b\(attributes)>", in: text, with: "_")
        text = replace(#"</su[pb]\s*>"#, in: text, with: "")

        // Tables and lists, innermost first: each round renders those with no table or list inside.
        let container = "<(ul|ol|table)\\b(\(attributes))>((?:(?!<(?:ul|ol|table)\\b).)*?)</\\1\\s*>"
        for _ in 0..<32 {
            var rendered = false
            text = replaceEach(container, in: text) { captures in
                rendered = true
                let content = captures[3]
                let block =
                    captures[1].lowercased() == "table"
                    ? tableText(content, expand: expand)
                    : listText(
                        content, ordered: captures[1].lowercased() == "ol", attributes: captures[2], expand: expand)
                return block.isEmpty ? " " : "<div>" + token(block) + "</div>"
            }
            if !rendered { break }
        }

        for level in 1...6 {
            text = replace(
                "<h\(level)\\b\(attributes)>", in: text, with: "\n\n" + String(repeating: "#", count: level) + " ")
        }
        text = replace(#"</h[1-6]\s*>"#, in: text, with: "\n\n")
        // A list item or cell outside any list or table that was closed.
        text = replace("<li\\b\(attributes)>", in: text, with: "\n- ")
        text = replace(#"<br\s*/?>"#, in: text, with: "\n")
        text = replace(#"</t[dh]\s*>"#, in: text, with: " ")
        text = replace(#"</tr\s*>"#, in: text, with: "\n")
        text = replace(
            "</?(?:p|div|section|article|main|header|aside|blockquote|pre|ul|ol|table|figure|figcaption|dl|dt|dd|hr|form|summary|details|address|fieldset|legend)\\b\(attributes)>",
            in: text, with: "\n\n")
        text = replace(anyTag, in: text, with: "")
        text = decodeEntities(text)

        let lines = text.components(separatedBy: "\n").map(collapseSpaces)
        var kept: [String] = []
        for content in lines {
            if content.isEmpty {
                if kept.last?.isEmpty == false { kept.append("") }
            } else if content != "-" && !content.allSatisfy({ $0 == "#" || $0 == " " }) {
                kept.append(content)
            }
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        return (title?.isEmpty == false ? title : nil, expand(kept.joined(separator: "\n")))
    }

    /// A fragment's text on one line: tags removed, entities decoded, white space collapsed. Block tokens stay.
    private static func inlineText(_ fragment: String) -> String {
        collapseWhitespace(decodeEntities(replace(anyTag, in: fragment, with: "")))
    }

    /// A cell's text as one pipe-table cell: "|" is written "\|" and a line break "<br>".
    private static func pipeCell(_ text: String) -> String {
        replace(#"[ \t]*(?:\r\n|\r|\n)[ \t]*"#, in: text.replacingOccurrences(of: "|", with: "\\|"), with: "<br>")
    }

    /// A `<table>`'s rows as a pipe table with a header separator after the first row, its caption on the line
    /// before. A cell's paragraphs and line breaks are joined with " <br> " so the row stays one line, and a cell
    /// spanning columns (`colspan`) is repeated in each, so the cells after it stay under their headers.
    private static func tableText(_ content: String, expand: (String) -> String) -> String {
        var lines: [String] = []
        if let caption = firstMatch("<caption\\b\(attributes)>(.*?)</caption\\s*>", in: content) {
            let text = expand(inlineText(caption))
            if !text.isEmpty { lines.append(collapseWhitespace(text)) }
        }
        let body = replace("<caption\\b\(attributes)>.*?</caption\\s*>", in: content, with: " ")
        var rows: [[String]] = []
        let rowPattern = "<tr\\b\(attributes)>(.*?)(?:</tr\\s*>|(?=<tr\\b)|(?=</t(?:body|head|foot)\\b)|$)"
        let cellPattern = "<(td|th)\\b(\(attributes))>(.*?)(?:</t[dh]\\s*>|(?=<t[dh]\\b)|$)"
        for row in allMatches(rowPattern, in: body) {
            var cells: [String] = []
            for cell in allMatches(cellPattern, in: row[1]) {
                var inner = replace(#"<br\s*/?>"#, in: cell[3], with: "\n")
                inner = replace(blockTags, in: inner, with: "\n")
                let text = inner.components(separatedBy: "\n").map(inlineText).filter { !$0.isEmpty }
                    .map { pipeCell(expand($0)) }
                    .joined(separator: " <br> ")
                let span = firstMatch(#"(?:^|\s)colspan\s*=\s*["']?\s*([0-9]+)"#, in: cell[2]).flatMap { Int($0) } ?? 1
                cells.append(contentsOf: Array(repeating: text, count: min(max(span, 1), 50)))
            }
            if cells.contains(where: { !$0.isEmpty }) { rows.append(cells) }
        }
        let columns = rows.map(\.count).max() ?? 0
        for (index, row) in rows.enumerated() {
            let cells = row + Array(repeating: "", count: columns - row.count)
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 && rows.count > 1 {
                lines.append("|" + Array(repeating: " --- ", count: columns).joined(separator: "|") + "|")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A `<ul>` or `<ol>` as Markdown list lines: "- " for an unordered item, "3. " for an ordered one counting
    /// from its `start` (and an item's own `value`). Block tags inside an item are read as spaces; a list nested
    /// in an item follows it, indented under its text.
    private static func listText(
        _ content: String, ordered: Bool, attributes listAttributes: String, expand: (String) -> String
    ) -> String {
        func number(_ name: String, in attributes: String) -> Int? {
            firstMatch("(?:^|\\s)\(name)\\s*=\\s*[\"']?\\s*(-?[0-9]+)", in: attributes).flatMap { Int($0) }
        }
        var next = ordered ? number("start", in: listAttributes) ?? 1 : 0
        var lines: [String] = []
        let source = content as NSString
        let openers =
            regex("<li\\b(\(attributes))>")?
            .matches(in: content, range: NSRange(location: 0, length: source.length)) ?? []
        func nestedLines(_ fragment: String, indent: String) -> [String] {
            allMatches(blockToken, in: fragment).flatMap { captures in
                expand(captures[0]).components(separatedBy: "\n").map { $0.isEmpty ? $0 : indent + $0 }
            }
        }
        // Anything before the first item (a nested list written straight inside the list) keeps its place.
        let lead = source.substring(to: openers.first?.range.location ?? source.length)
        lines += nestedLines(lead, indent: "")
        for (index, opener) in openers.enumerated() {
            let start = NSMaxRange(opener.range)
            let end = index + 1 < openers.count ? openers[index + 1].range.location : source.length
            var item = source.substring(with: NSRange(location: start, length: end - start))
            item = replace(#"</li\s*>"#, in: item, with: " ")
            item = replace(blockTags, in: item, with: " ")
            item = replace(#"<br\s*/?>"#, in: item, with: " ")
            if ordered, let value = number("value", in: source.substring(with: opener.range(at: 1))) { next = value }
            let marker = ordered ? "\(next). " : "- "
            if ordered { next += 1 }
            let text = collapseWhitespace(replace(blockToken, in: inlineText(item), with: " "))
            if !text.isEmpty { lines.append(marker + text) }
            lines += nestedLines(item, indent: String(repeating: " ", count: marker.count))
        }
        return lines.joined(separator: "\n")
    }

    /// Elements a reader does not see are left out with everything inside them (5.8): one marked `hidden`,
    /// `aria-hidden="true"` or `style="display: none"`. A page's collapsed menus, screen-reader duplicates and
    /// icon glyphs were imported as text.
    private static func removingHiddenElements(_ html: String) -> String {
        guard
            html.range(of: "hidden", options: .caseInsensitive) != nil
                || html.range(of: "display", options: .caseInsensitive) != nil,
            let opener = regex("<([A-Za-z][A-Za-z0-9-]*)(\\s\(attributes))>")
        else { return html }
        let source = html as NSString
        var result = ""
        var cursor = 0
        for match in opener.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            // Inside an element already left out.
            guard match.range.location >= cursor else { continue }
            let tagAttributes = source.substring(with: match.range(at: 2))
            guard isHidden(tagAttributes) else { continue }
            let name = source.substring(with: match.range(at: 1)).lowercased()
            var end = NSMaxRange(match.range)
            if !tagAttributes.hasSuffix("/") && !voidElements.contains(name),
                let close = closingTagEnd(of: name, in: source, from: end)
            {
                end = close
            }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + " "
            cursor = end
        }
        return result + source.substring(from: cursor)
    }

    private static func isHidden(_ tagAttributes: String) -> Bool {
        let lowered = tagAttributes.lowercased()
        guard lowered.contains("hidden") || lowered.contains("display") else { return false }
        // The bare attribute, by its name: `type="hidden"` and `class="hidden-xs"` are values, not the attribute.
        let names = lowered.replacingOccurrences(of: #""[^"]*"|'[^']*'"#, with: "\"\"", options: .regularExpression)
        if names.range(of: #"(?:^|\s)hidden(?=[\s=/]|$)"#, options: .regularExpression) != nil { return true }
        if lowered.range(of: #"(?:^|\s)aria-hidden\s*=\s*["']?\s*true"#, options: .regularExpression) != nil {
            return true
        }
        return lowered.range(of: #"(?:^|\s)style\s*=\s*["'][^"']*display\s*:\s*none"#, options: .regularExpression)
            != nil
    }

    /// Where the element opened just before `start` ends: after its matching end tag, counting nested elements
    /// of the same name. Nil when it is never closed.
    private static func closingTagEnd(of name: String, in source: NSString, from start: Int) -> Int? {
        guard let tag = regex("<(/?)\(NSRegularExpression.escapedPattern(for: name))\\b\(attributes)>") else {
            return nil
        }
        var depth = 1
        var end: Int?
        tag.enumerateMatches(in: source as String, range: NSRange(location: start, length: source.length - start)) {
            match, _, stop in
            guard let match else { return }
            if match.range(at: 1).length > 0 {
                depth -= 1
                if depth == 0 {
                    end = NSMaxRange(match.range)
                    stop.pointee = true
                }
            } else if !source.substring(with: match.range).hasSuffix("/>") {
                depth += 1
            }
        }
        return end
    }

    static func markdownDocument(title: String, text: String, source: URL, savedAt: Date) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        var body = text
        // A page whose first heading repeats its title would show the title twice.
        let heading = "# \(title)"
        if body.hasPrefix(heading + "\n") || body == heading {
            body = String(body.dropFirst(heading.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "# \(title)\n\nSource: \(source.absoluteString)\nSaved: \(day.string(from: savedAt))\n\n\(body)\n"
    }

    static func fileName(title: String, extension fileExtension: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let safe = title.components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
        let stem = String((safe.isEmpty ? "Web page" : safe).prefix(80)).trimmingCharacters(in: .whitespaces)
        return "\(stem).\(fileExtension)"
    }

    // MARK: - Helpers

    /// Patterns compiled once per process, case-insensitive and with "." matching line ends. A page's tables and
    /// lists are read cell by cell, so the same few patterns are used thousands of times on one page.
    /// `NSCache` and `NSRegularExpression` are both safe to use from any thread (Apple's documentation for each).
    nonisolated(unsafe) private static let compiledPatterns = NSCache<NSString, NSRegularExpression>()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = compiledPatterns.object(forKey: pattern as NSString) { return cached }
        guard
            let compiled = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        compiledPatterns.setObject(compiled, forKey: pattern as NSString)
        return compiled
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = Self.regex(pattern) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }

    /// `text` with each match of `pattern` replaced by what `transform` returns for its captures, in order.
    private static func replaceEach(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let regex = Self.regex(pattern) else {
            return text
        }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(captures(of: match, in: source))
            cursor = NSMaxRange(match.range)
        }
        return result + source.substring(from: cursor)
    }

    /// Every match of `pattern`, each as its captures (an empty string for a group that took no part).
    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = Self.regex(pattern) else {
            return []
        }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            captures(of: $0, in: source)
        }
    }

    private static func captures(of match: NSTextCheckingResult, in source: NSString) -> [String] {
        (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = Self.regex(pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" || $0 == "\r" }).joined(separator: " ")
    }

    /// The named entities this decodes: the markup five, punctuation, currency, common symbols,
    /// the Latin-1 letters and a few Greek ones. HTML defines about 2,200; the rest stay as written.
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "lsquo": "\u{2018}",
        "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "sbquo": "\u{201A}", "bdquo": "\u{201E}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}", "times": "\u{00D7}",
        "divide": "\u{00F7}", "plusmn": "\u{00B1}", "micro": "\u{00B5}", "para": "\u{00B6}", "sect": "\u{00A7}",
        "frac12": "\u{00BD}", "frac14": "\u{00BC}", "frac34": "\u{00BE}", "sup1": "\u{00B9}", "sup2": "\u{00B2}",
        "sup3": "\u{00B3}", "euro": "\u{20AC}", "pound": "\u{00A3}", "yen": "\u{00A5}", "cent": "\u{00A2}",
        "bull": "\u{2022}", "middot": "\u{00B7}", "laquo": "\u{00AB}", "raquo": "\u{00BB}", "lsaquo": "\u{2039}",
        "rsaquo": "\u{203A}", "iexcl": "\u{00A1}", "iquest": "\u{00BF}", "dagger": "\u{2020}", "Dagger": "\u{2021}",
        "le": "\u{2264}", "ge": "\u{2265}", "ne": "\u{2260}", "asymp": "\u{2248}", "minus": "\u{2212}",
        "infin": "\u{221E}", "larr": "\u{2190}", "rarr": "\u{2192}", "uarr": "\u{2191}", "darr": "\u{2193}",
        "harr": "\u{2194}", "prime": "\u{2032}", "Prime": "\u{2033}", "permil": "\u{2030}", "ensp": " ",
        "emsp": " ", "thinsp": " ", "shy": "", "Agrave": "\u{00C0}", "Aacute": "\u{00C1}",
        "Acirc": "\u{00C2}", "Atilde": "\u{00C3}", "Auml": "\u{00C4}", "Aring": "\u{00C5}", "AElig": "\u{00C6}",
        "Ccedil": "\u{00C7}", "Egrave": "\u{00C8}", "Eacute": "\u{00C9}", "Ecirc": "\u{00CA}", "Euml": "\u{00CB}",
        "Igrave": "\u{00CC}", "Iacute": "\u{00CD}", "Icirc": "\u{00CE}", "Iuml": "\u{00CF}", "Ntilde": "\u{00D1}",
        "Ograve": "\u{00D2}", "Oacute": "\u{00D3}", "Ocirc": "\u{00D4}", "Otilde": "\u{00D5}", "Ouml": "\u{00D6}",
        "Oslash": "\u{00D8}", "Ugrave": "\u{00D9}", "Uacute": "\u{00DA}", "Ucirc": "\u{00DB}", "Uuml": "\u{00DC}",
        "Yacute": "\u{00DD}", "szlig": "\u{00DF}", "agrave": "\u{00E0}", "aacute": "\u{00E1}", "acirc": "\u{00E2}",
        "atilde": "\u{00E3}", "auml": "\u{00E4}", "aring": "\u{00E5}", "aelig": "\u{00E6}", "ccedil": "\u{00E7}",
        "egrave": "\u{00E8}", "eacute": "\u{00E9}", "ecirc": "\u{00EA}", "euml": "\u{00EB}", "igrave": "\u{00EC}",
        "iacute": "\u{00ED}", "icirc": "\u{00EE}", "iuml": "\u{00EF}", "ntilde": "\u{00F1}", "ograve": "\u{00F2}",
        "oacute": "\u{00F3}", "ocirc": "\u{00F4}", "otilde": "\u{00F5}", "ouml": "\u{00F6}", "oslash": "\u{00F8}",
        "ugrave": "\u{00F9}", "uacute": "\u{00FA}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}", "yacute": "\u{00FD}",
        "yuml": "\u{00FF}", "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}", "delta": "\u{03B4}",
        "mu": "\u{03BC}", "pi": "\u{03C0}", "sigma": "\u{03C3}", "omega": "\u{03C9}", "Omega": "\u{03A9}",
        "Delta": "\u{0394}",
    ]

    /// A numeric reference from 128 to 159 is read as the Windows-1252 character with that byte, as the HTML
    /// standard's numeric character reference end state does (5.8): "&#150;" is an en dash and "&#128;" a euro
    /// sign, not C1 control codes. The five bytes Windows-1252 leaves undefined are read as their own code point.
    private static let windows1252Remap: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
        0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
        0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    /// Decodes `&amp;`, `&#8217;` and `&#x2019;`. An entity this does not know is left as written.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"),
            let regex = try? NSRegularExpression(
                pattern: #"&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,10});"#)
        else {
            return text
        }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            let name = source.substring(with: match.range(at: 1))
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).map { windows1252Remap[$0] ?? $0 }
                    .flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst(1), radix: 10).map { windows1252Remap[$0] ?? $0 }
                    .flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = namedEntities[name]
            }
            result += decoded ?? source.substring(with: match.range)
        }
        result += source.substring(from: cursor)
        return result
    }
}
