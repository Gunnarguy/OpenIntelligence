//
//  JSONRecordExtractor.swift
//  OpenIntelligence
//

import Foundation

/// Reads JSON Lines (`.jsonl`, `.ndjson`) and JSON (`.json`) as records, so each record becomes
/// its own passage with its field names kept.
///
/// Through 5.6 a `.json` file was imported as raw text and cut wherever the chunker's word window
/// fell, and `.jsonl` and `.ndjson` came in as plain text the same way. A record here is one line
/// of a JSON Lines file or one element of a top-level array. A top-level object gives one record
/// for its plain values and one for each member that is an object or a list, and a list of objects
/// gives one record per element.
///
/// The file's own text is kept. Members are written in the order the file has them, a number is
/// written with the digits the file has ("12.50" stays "12.50"), and a member that is null or
/// empty is written as `null`, `""`, `[]` or `{}` so its name is not lost. A line that is not valid
/// JSON is kept as a record holding the line as written, and the count of such lines is reported.
/// A file that is not valid JSON at all returns nil, and the caller imports it as text, as before.
nonisolated enum JSONRecordExtractor {
    struct Extraction: Sendable, Equatable {
        /// One rendered record per element, each starting with its header line.
        let records: [String]
        /// Lines of a JSON Lines file that did not parse and were kept as written.
        let unparsedLineCount: Int

        /// The records joined for the document's stored text, with a blank line between them.
        var text: String { records.joined(separator: "\n\n") }
    }

    /// A JSON Lines file larger than this is imported as text. Its records are held in memory next
    /// to the file's own text; each line is parsed and released before the next.
    static let maxFileBytes = 64 * 1_048_576

    /// A `.json` file larger than this is imported as text. The whole file becomes one parsed tree,
    /// which for a file of many small values is several times the file's size. The figure is a
    /// guess at what a phone can hold; it has not been measured on one.
    static let maxWholeFileBytes = 16 * 1_048_576

    /// Lines of a multi-line value after the first are indented by this, so no line of a value can
    /// be mistaken for a record header, which always starts in the first column.
    static let continuationIndent = "  "

    // MARK: - Reading

    /// Records for a file's contents, or nil when the contents are not JSON records.
    /// - Parameter fileExtension: lowercased, without the dot.
    static func extract(from contents: String, fileExtension: String) -> Extraction? {
        // A byte-order mark (Windows and PowerShell exports write one) is not JSON and is not
        // whitespace to Foundation, so it is taken off here.
        var text = contents
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxFileBytes else { return nil }

        if isLineDelimited(fileExtension) {
            return extractLines(from: trimmed)
        }

        if trimmed.utf8.count <= maxWholeFileBytes, let value = JSONValue.parse(trimmed) {
            let entries = recordEntries(of: value)
            guard !entries.isEmpty else { return nil }
            let total = entries.count
            let records = entries.enumerated().map { offset, entry in
                render(entry.value, key: entry.key, index: offset + 1, total: total)
            }
            return Extraction(records: records, unparsedLineCount: 0)
        }

        // A file named .json that holds one object per line is JSON Lines under another name. It
        // counts only when every line parses, so ordinary broken JSON still goes the text route.
        if let lines = extractLines(from: trimmed), lines.records.count > 1, lines.unparsedLineCount == 0 {
            return lines
        }
        return nil
    }

    static func isLineDelimited(_ fileExtension: String) -> Bool {
        fileExtension == "jsonl" || fileExtension == "ndjson"
    }

    /// One record per non-blank line. Each line is parsed and written out before the next is read,
    /// so no parsed tree outlives its line.
    private static func extractLines(from contents: String) -> Extraction? {
        // Lines end at a line feed and nowhere else. JSON allows U+2028, U+2029 and U+0085 raw
        // inside a string, and Foundation's line enumeration would cut a record in two at them.
        // The split is on the line-feed scalar: "\r\n" is one Character to Swift, so a split on
        // the Character "\n" would not see the line ends of a Windows file.
        let lines = contents.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String(String.UnicodeScalarView($0)).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let total = lines.count
        var records: [String] = []
        records.reserveCapacity(total)
        var unparsed = 0
        for (offset, line) in lines.enumerated() {
            if let value = JSONValue.parse(line) {
                records.append(render(value, key: nil, index: offset + 1, total: total))
            } else {
                unparsed += 1
                records.append(header(index: offset + 1, total: total) + "\n" + line)
            }
        }
        guard unparsed < total else { return nil }
        return Extraction(records: records, unparsedLineCount: unparsed)
    }

    /// Splits a parsed file into records. An array gives one per element. An object gives one
    /// record holding its plain values, then one per member that is an object or a list; a list of
    /// objects gives one per element, named `key[n]`, since that is how an export wraps its list
    /// (`{"messages": [...]}`). Empty objects and lists stay with the plain values.
    private static func recordEntries(of value: JSONValue) -> [(key: String?, value: JSONValue)] {
        switch value {
        case .array(let elements):
            return elements.map { (nil, $0) }
        case .object(let members):
            var result: [(key: String?, value: JSONValue)] = []
            var plain: [(String, JSONValue)] = []
            for (key, member) in members {
                switch member {
                case .array(let list) where !list.isEmpty:
                    if list.allSatisfy(\.isObject) {
                        for (index, element) in list.enumerated() {
                            result.append(("\(key)[\(index + 1)]", element))
                        }
                    } else {
                        result.append((key, member))
                    }
                case .object(let nested) where !nested.isEmpty:
                    result.append((key, member))
                default:
                    plain.append((key, member))
                }
            }
            if !plain.isEmpty {
                result.insert((nil, .object(plain)), at: 0)
            }
            return result
        default:
            return [(nil, value)]
        }
    }

    // MARK: - Rendering

    static func header(index: Int, total: Int) -> String {
        "Record \(index) of \(total)"
    }

    private static func render(_ value: JSONValue, key: String?, index: Int, total: Int) -> String {
        var lines = [header(index: index, total: total)]
        flatten(value, path: key ?? "", into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Writes a value as `path: value` lines, in the file's order. Nested objects extend the path
    /// with a dot, a list of plain values shares one line, and a list that holds objects or lists
    /// is numbered from 1.
    private static func flatten(_ value: JSONValue, path: String, into lines: inout [String]) {
        switch value {
        case .object(let members):
            if members.isEmpty {
                lines.append(labelled(path, "{}"))
                return
            }
            for (key, member) in members {
                flatten(member, path: path.isEmpty ? key : "\(path).\(key)", into: &lines)
            }
        case .array(let elements):
            if elements.isEmpty {
                lines.append(labelled(path, "[]"))
            } else if elements.contains(where: { $0.isObject || $0.isArray }) {
                for (index, element) in elements.enumerated() {
                    flatten(element, path: "\(path)[\(index + 1)]", into: &lines)
                }
            } else {
                lines.append(labelled(path, elements.map(scalarText).joined(separator: ", ")))
            }
        default:
            lines.append(labelled(path, scalarText(value)))
        }
    }

    private static func labelled(_ path: String, _ text: String) -> String {
        path.isEmpty ? text : "\(path): \(text)"
    }

    private static func scalarText(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let digits): return digits
        case .string(let text):
            if text.isEmpty { return "\"\"" }
            // A value's line feeds are kept (a carriage return before one is dropped); its later
            // lines are indented so none can read as a record header. Other separators, such as
            // U+2028, stay in the text as they are.
            let parts = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            guard parts.count > 1 else { return text }
            return parts.enumerated()
                .map { $0.offset == 0 ? $0.element : continuationIndent + $0.element }
                .joined(separator: "\n")
        case .object, .array:
            return ""
        }
    }

    // MARK: - Splitting back into passages

    /// One passage per record, cut from the document's text after it has been through the import's
    /// cleanup. A header counts only in the first column and only as the next one due. Returns nil
    /// unless the text holds exactly `expectedCount` headers in order, so the caller can fall back
    /// to ordinary chunking and lose nothing.
    static func passages(in text: String, expectedCount: Int) -> [(range: Range<String.Index>, text: String)]? {
        guard expectedCount > 0 else { return nil }

        var starts: [String.Index] = []
        var next = 1
        var wanted = header(index: next, total: expectedCount)
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if next <= expectedCount, line.hasPrefix(wanted),
                line.dropFirst(wanted.count).allSatisfy({ $0 == " " || $0 == "\t" })
            {
                starts.append(lineStart)
                next += 1
                wanted = header(index: next, total: expectedCount)
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        guard starts.count == expectedCount,
            text[text.startIndex..<starts[0]].allSatisfy(\.isWhitespace)
        else {
            return nil
        }

        return starts.enumerated().map { offset, start in
            let end = offset + 1 < starts.count ? starts[offset + 1] : text.endIndex
            let passage = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            return (start..<end, passage)
        }
    }

    /// Cuts one record's passage into parts that each fit `maxTokens`, at line ends. A part after
    /// the first starts with the record's header and its part number, so every part still says
    /// which record it belongs to. A single line longer than a part is cut between words. No
    /// character is retyped: the parts, with their added header lines removed, hold the passage's
    /// own lines in order.
    static func parts(of passage: String, maxTokens: Int, countTokens: (String) -> Int) -> [String] {
        guard maxTokens > 0, countTokens(passage) > maxTokens else { return [passage] }

        var lines = passage.components(separatedBy: "\n")
        let headerLine = lines.isEmpty ? "" : lines.removeFirst()
        // Room for "Record N of T, part K" on every part.
        let budget = max(8, maxTokens - countTokens(headerLine + ", part 000") - 2)

        var bodies: [[String]] = []
        var current: [String] = []
        var used = 0
        func flush() {
            if !current.isEmpty { bodies.append(current) }
            current = []
            used = 0
        }
        for line in lines {
            let cost = countTokens(line) + 1
            if cost > budget {
                flush()
                for piece in wordPieces(of: line, budget: budget, countTokens: countTokens) {
                    bodies.append([piece])
                }
                continue
            }
            if used + cost > budget { flush() }
            current.append(line)
            used += cost
        }
        flush()

        guard bodies.count > 1 else { return [passage] }
        return bodies.enumerated().map { offset, body in
            "\(headerLine), part \(offset + 1) of \(bodies.count)\n" + body.joined(separator: "\n")
        }
    }

    private static func wordPieces(of line: String, budget: Int, countTokens: (String) -> Int) -> [String] {
        OversizedChunkSplitter.wordPieces(of: line, maxTokens: budget, countTokens: countTokens)
    }
}

// MARK: - Parser

/// A JSON value that keeps what `JSONSerialization` gives up: the order of an object's members,
/// members with the same name, and a number's digits as the file wrote them.
nonisolated indirect enum JSONValue: Sendable, Equatable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    /// Parses one complete JSON value. Returns nil for anything that is not valid JSON, including
    /// text left over after the value.
    static func parse(_ text: String) -> JSONValue? {
        var parser = JSONParser(Array(text.utf8))
        parser.skipWhitespace()
        guard let value = parser.parseValue(depth: 0) else { return nil }
        parser.skipWhitespace()
        return parser.isAtEnd ? value : nil
    }
}

/// A recursive-descent reader over UTF-8 bytes. Every failure returns nil; nothing is guessed.
private nonisolated struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    /// Deeper nesting than this is refused instead of risking the stack.
    private static let maxDepth = 200

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func parseValue(depth: Int) -> JSONValue? {
        guard depth <= Self.maxDepth, index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "{"): return parseObject(depth: depth)
        case UInt8(ascii: "["): return parseArray(depth: depth)
        case UInt8(ascii: "\""): return parseString().map(JSONValue.string)
        case UInt8(ascii: "t"): return consume("true") ? .bool(true) : nil
        case UInt8(ascii: "f"): return consume("false") ? .bool(false) : nil
        case UInt8(ascii: "n"): return consume("null") ? .null : nil
        default: return parseNumber()
        }
    }

    private mutating func consume(_ word: String) -> Bool {
        let wanted = Array(word.utf8)
        guard index + wanted.count <= bytes.count, Array(bytes[index..<index + wanted.count]) == wanted else {
            return false
        }
        index += wanted.count
        return true
    }

    private mutating func parseObject(depth: Int) -> JSONValue? {
        index += 1
        var members: [(String, JSONValue)] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = parseString() else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipWhitespace()
            guard let value = parseValue(depth: depth + 1) else { return nil }
            members.append((key, value))
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            } else {
                return nil
            }
        }
    }

    private mutating func parseArray(depth: Int) -> JSONValue? {
        index += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            guard let value = parseValue(depth: depth + 1) else { return nil }
            elements.append(value)
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(elements)
            } else {
                return nil
            }
        }
    }

    /// A number as written: optional minus, digits, optional fraction, optional exponent.
    private mutating func parseNumber() -> JSONValue? {
        let start = index
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { return nil }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { return nil }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else { return nil }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        return .number(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    /// A string with its escapes resolved. A control character written raw, a bad escape or a
    /// lone surrogate makes the whole value invalid.
    private mutating func parseString() -> String? {
        index += 1
        var scalars = String.UnicodeScalarView()
        var runStart = index

        func appendRun(_ end: Int, into view: inout String.UnicodeScalarView) -> Bool {
            guard end > runStart else { return true }
            guard let run = String(validating: bytes[runStart..<end], as: UTF8.self) else { return false }
            view.append(contentsOf: run.unicodeScalars)
            return true
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                guard appendRun(index, into: &scalars) else { return nil }
                index += 1
                return String(scalars)
            }
            if byte < 0x20 { return nil }
            if byte != UInt8(ascii: "\\") {
                index += 1
                continue
            }

            guard appendRun(index, into: &scalars), index + 1 < bytes.count else { return nil }
            let escape = bytes[index + 1]
            index += 2
            switch escape {
            case UInt8(ascii: "\""): scalars.append("\"")
            case UInt8(ascii: "\\"): scalars.append("\\")
            case UInt8(ascii: "/"): scalars.append("/")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "u"):
                guard let unit = hexUnit() else { return nil }
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                        bytes[index + 1] == UInt8(ascii: "u")
                    else { return nil }
                    index += 2
                    guard let low = hexUnit(), (0xDC00...0xDFFF).contains(low),
                        let scalar = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                    else { return nil }
                    scalars.append(scalar)
                } else {
                    guard let scalar = Unicode.Scalar(unit) else { return nil }
                    scalars.append(scalar)
                }
            default:
                return nil
            }
            runStart = index
        }
        return nil
    }

    private mutating func hexUnit() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        let digits = bytes[index..<index + 4]
        guard digits.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 | 0x20 >= 0x61 && $0 | 0x20 <= 0x66) }),
            let unit = UInt32(String(decoding: digits, as: UTF8.self), radix: 16)
        else { return nil }
        index += 4
        return unit
    }
}
