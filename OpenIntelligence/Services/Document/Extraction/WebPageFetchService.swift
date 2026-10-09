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
                return "That is \(bytes / 1_048_576) MB, over the limit (\(maxHTMLBytes / 1_048_576) MB for a web page, \(maxBytes / 1_048_576) MB for a file)."
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

    /// The page's title and its text, with headings and list items marked the way Markdown marks
    /// them. Scripts, styles, navigation and footers are left out; nothing is executed.
    static func readableText(fromHTML html: String) -> (title: String?, text: String) {
        let title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html).map(decodeEntities).map(collapseWhitespace)

        var text = html
        text = replace(#"<!--.*?-->"#, in: text, with: " ")
        for tag in [
            "script", "style", "noscript", "svg", "template", "iframe", "head", "nav", "footer", "button", "select",
        ] {
            // Nothing to scan for when the page has no such element.
            guard text.range(of: "<\(tag)", options: .caseInsensitive) != nil else { continue }
            // The self-closed form first ("<svg ... />"), or its opener would run to the next closer.
            text = replace("<\(tag)\\b[^>]*/>", in: text, with: " ")
            text = replace("<\(tag)\\b[^>]*>.*?</\(tag)\\s*>", in: text, with: " ")
        }
        // The page's own line breaks mean nothing in HTML; the tags decide where lines go.
        text = replace(#"\s+"#, in: text, with: " ")

        for level in 1...6 {
            text = replace("<h\(level)\\b[^>]*>", in: text, with: "\n\n" + String(repeating: "#", count: level) + " ")
        }
        text = replace(#"</h[1-6]\s*>"#, in: text, with: "\n\n")
        text = replace(#"<li\b[^>]*>"#, in: text, with: "\n- ")
        text = replace(#"<br\s*/?>"#, in: text, with: "\n")
        text = replace(#"</t[dh]\s*>"#, in: text, with: " | ")
        text = replace(#"</tr\s*>"#, in: text, with: "\n")
        text = replace(
            #"</?(p|div|section|article|main|header|aside|blockquote|pre|ul|ol|table|figure|figcaption|dl|dt|dd|hr|form)\b[^>]*>"#,
            in: text, with: "\n\n")
        text = replace(#"</?[A-Za-z!?][^>]*>"#, in: text, with: "")
        text = decodeEntities(text)

        let lines = text.components(separatedBy: "\n").map(collapseSpaces)
        var kept: [String] = []
        for line in lines {
            let content = line.hasSuffix(" |") ? String(line.dropLast(2)) : line
            if content.isEmpty {
                if kept.last?.isEmpty == false { kept.append("") }
            } else if content != "-" && !content.allSatisfy({ $0 == "#" || $0 == " " }) {
                kept.append(content)
            }
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        return (title?.isEmpty == false ? title : nil, kept.joined(separator: "\n"))
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

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
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
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst(1), radix: 10).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = namedEntities[name]
            }
            result += decoded ?? source.substring(with: match.range)
        }
        result += source.substring(from: cursor)
        return result
    }
}
