//
//  GoldenRecording.swift
//  OpenIntelligenceTests
//
//  Shared by the before-and-after recorders of the 2026-11-06 decomposition (`StructuredParsingGoldenTests`,
//  `ImportGoldenTests`, `StandardPipelineGoldenTests`). Each recorder runs its work twice in one run, fails if the two
//  passes differ, and writes the first pass to `results-<label>.json`; `scripts/golden_compare.py` then compares two
//  such files byte for byte. Breaking `RAGService.queryInternal`, `RAGService.addDocument` and the structured PDF
//  parser into steps must change nothing these files record.
//
//  What "the same" means here: ids minted per run (`UUID()`) are replaced by the order in which they first appear,
//  long strings and long number arrays by a SHA-256 digest with their length, and keys a recorder names as volatile
//  (clock times, durations) are dropped. Everything else, every score bit and every word, is kept.
//

import CryptoKit
import Foundation
import XCTest

enum GoldenRecording {
    /// The folder and label a recorder writes to, from `TEST_RUNNER_OI_GOLDEN_DIR` and `TEST_RUNNER_OI_GOLDEN_LABEL`.
    /// Without the folder the recorder skips, so the full suite never runs it by accident.
    static func destination() throws -> (dir: URL, label: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["OI_GOLDEN_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_OI_GOLDEN_DIR to record a golden run")
        }
        return (URL(fileURLWithPath: folder), environment["OI_GOLDEN_LABEL"] ?? "run")
    }

    /// The first 12 hex characters of the SHA-256 of `text`, with its length: enough to tell two texts apart, short
    /// enough to keep a results file readable.
    static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(hash)/\(text.utf8.count)"
    }

    /// Ids minted per run, numbered by first appearance so the same structure gets the same numbers on every run.
    final class Ids {
        private var seen: [String: Int] = [:]
        func token(_ uuid: String) -> String {
            if let n = seen[uuid] { return "id#\(n)" }
            seen[uuid] = seen.count
            return "id#\(seen.count - 1)"
        }
    }

    /// A key is a clock time or a duration when its name says so: `addedAt`, `createdAt`, `extractionTimeSeconds`,
    /// `retrievalMs`. Measured 2026-11-06: these were the only keys that differed between two reads of the same PDFs
    /// apart from `keywords` (below).
    static func isVolatile(_ key: String, _ dropping: Set<String>) -> Bool {
        dropping.contains(key) || key.hasSuffix("At") || key.hasSuffix("Seconds") || key.hasSuffix("Ms")
            || key.hasSuffix("Time") || key.hasPrefix("timeTo") || key == "timestamp" || key == "lastUpdated"
    }

    /// Lists compared as sets. Empty: the recorders run with `SWIFT_DETERMINISTIC_HASHING=1`, so lists the app builds
    /// from a `Set` come out in the same order on every run and their order is checked too. Without it a passage's
    /// `keywords` came out in two orders in one run on 2026-11-06 (the Sportage manual, passage 5), because
    /// `extractKeywordsFromStructuredElement` returns `Array(Set(keywords)).prefix(20)`.
    static let unorderedKeys: Set<String> = []

    /// Lists of human-readable step lines that carry a duration in their text ("Answer composed — 32 tokens in 0.29s");
    /// the duration is replaced by `#s` and the rest of the line is kept.
    static let timedTextKeys: Set<String> = ["reasoningTrace"]
    private static let duration = try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\s?(?:ms|s)\b"#)
    static func withoutDurations(_ any: Any) -> Any {
        if let s = any as? String {
            return duration.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "#s")
        }
        if let list = any as? [Any] { return list.map(withoutDurations) }
        return any
    }

    private static let embeddedUUID = try! NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// `text` with every id in it replaced by `<id>`, and nothing else changed: for reading a long text in full.
    static func idsReplaced(_ text: String) -> String {
        embeddedUUID.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "<id>")
    }

    private static let uuidPattern = try! NSRegularExpression(
        pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

    /// `value` encoded to JSON and normalized (see the file header). `dropping` names keys removed wherever they
    /// appear; each recorder lists them with the reason.
    static func normalized<T: Encodable>(_ value: T, dropping: Set<String>, ids: Ids) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return normalize(object, dropping: dropping, ids: ids)
    }

    static func normalize(_ any: Any, dropping: Set<String>, ids: Ids) -> Any {
        if let dictionary = any as? [String: Any] {
            var out: [String: Any] = [:]
            // Sorted, so ids are numbered in the same order on every run.
            for key in dictionary.keys.sorted() where !isVolatile(key, dropping) {
                // A file's URL names the run's temporary folder; the file name is what identifies it.
                if key == "fileURL", let s = dictionary[key] as? String {
                    out[key] = URL(string: s)?.lastPathComponent ?? s
                    continue
                }
                var value = normalize(dictionary[key]!, dropping: dropping, ids: ids)
                if unorderedKeys.contains(key), let list = value as? [Any] { value = list.sorted { "\($0)" < "\($1)" } }
                out[key] = value
            }
            return out
        }
        if let array = any as? [Any] {
            if array.count > 32, array.allSatisfy({ $0 is NSNumber }) {
                let text = array.map { "\(($0 as! NSNumber).doubleValue.bitPattern)" }.joined(separator: ",")
                return "numbers:\(array.count):\(digest(text))"
            }
            return array.map { normalize($0, dropping: dropping, ids: ids) }
        }
        if let string = any as? String {
            let range = NSRange(string.startIndex..., in: string)
            if uuidPattern.firstMatch(in: string, range: range) != nil { return ids.token(string.uppercased()) }
            // An id inside a longer string ("summary-<UUID>", a sibling group's name) is numbered the same way.
            var text = string
            for match in embeddedUUID.matches(in: string, range: range).reversed() {
                guard let r = Range(match.range, in: text) else { continue }
                text.replaceSubrange(r, with: ids.token(String(text[r]).uppercased()))
            }
            if text != string { return text.utf8.count > 160 ? "text:\(digest(text))" : text }
            return string.utf8.count > 160 ? "text:\(digest(string))" : string
        }
        if let number = any as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            // The bit pattern of the double, so a score that moves in its last bit still shows.
            return "\(number.doubleValue)|\(number.doubleValue.bitPattern)"
        }
        return any
    }

    /// Any value, read field by field with `Mirror`, for the types that are not `Codable` (`RAGResponse`,
    /// `RAGAuditSnapshot`, a retrieval trace). Dates are left out (they are clock times); ids are numbered as in
    /// `normalize`; floating-point numbers keep their bit pattern; long number arrays (vectors) become a digest.
    /// A class instance is read once; a second reference to it is written as its type name.
    static func reflect(_ value: Any, dropping: Set<String>, ids: Ids) -> Any {
        var visited = Set<ObjectIdentifier>()
        func number(_ any: Any) -> Double? {
            switch any {
            case let d as Double: return d
            case let f as Float: return Double(f)
            case let c as CGFloat: return Double(c)
            default: return nil
            }
        }
        // `timed`: inside a list of step lines that carry durations (`timedTextKeys`), stripped before any digest.
        func walk(_ value: Any, _ depth: Int, _ timed: Bool = false) -> Any {
            if depth > 24 { return "deeper than 24" }
            switch value {
            case let s as String: return normalize(timed ? withoutDurations(s) as! String : s, dropping: dropping, ids: ids)
            case let u as UUID: return ids.token(u.uuidString.uppercased())
            case is Date: return "date"
            case let b as Bool: return b
            case let i as Int: return i
            case let d as Double: return "\(d)|\(d.bitPattern)"
            case let f as Float: return "\(f)|\(f.bitPattern)"
            case let c as CGFloat: return "\(Double(c))|\(Double(c).bitPattern)"
            case let data as Data: return "data:\(data.count):\(digest(data.base64EncodedString()))"
            case let url as URL: return "url:\(url.lastPathComponent)"
            default: break
            }
            let mirror = Mirror(reflecting: value)
            switch mirror.displayStyle {
            case .optional:
                guard let wrapped = mirror.children.first?.value else { return NSNull() }
                return walk(wrapped, depth + 1, timed)
            case .collection, .set:
                let items = mirror.children.map(\.value)
                if items.count > 32, items.allSatisfy({ number($0) != nil }) {
                    let text = items.map { "\(number($0)!.bitPattern)" }.joined(separator: ",")
                    return "numbers:\(items.count):\(digest(text))"
                }
                let walked = items.map { walk($0, depth + 1, timed) }
                if mirror.displayStyle == .set {
                    return walked.sorted { "\($0)" < "\($1)" }
                }
                return walked
            case .dictionary:
                var out: [String: Any] = [:]
                for child in mirror.children {
                    let pair = Mirror(reflecting: child.value).children.map(\.value)
                    guard pair.count == 2 else { continue }
                    let key = "\(walk(pair[0], depth + 1, timed))"
                    if isVolatile(key, dropping) { continue }
                    out[key] = walk(pair[1], depth + 1, timed)
                }
                return out
            case .enum:
                guard let payload = mirror.children.first else { return "\(value)" }
                return ["case": payload.label ?? "\(value)", "value": walk(payload.value, depth + 1, timed)]
            case .class:
                let id = ObjectIdentifier(value as AnyObject)
                if visited.contains(id) { return "ref:\(type(of: value))" }
                visited.insert(id)
                fallthrough
            default:
                if mirror.children.isEmpty { return "\(value)" }
                var out: [String: Any] = [:]
                var index = 0
                for child in mirror.children {
                    let key = child.label ?? ".\(index)"
                    index += 1
                    if isVolatile(key, dropping) { continue }
                    var walked = walk(child.value, depth + 1, timed || timedTextKeys.contains(key))
                    if unorderedKeys.contains(key), let list = walked as? [Any] { walked = list.sorted { "\($0)" < "\($1)" } }
                    out[key] = walked
                }
                return out
            }
        }
        return walk(value, 0)
    }

    /// Where two normalized trees differ, as key paths (at most `limit`), so a failure names the field that moved.
    static func differences(_ a: Any?, _ b: Any?, path: String = "$", limit: Int = 40) -> [String] {
        var out: [String] = []
        func walk(_ a: Any?, _ b: Any?, _ path: String) {
            guard out.count < limit else { return }
            switch (a, b) {
            case (let x as [String: Any], let y as [String: Any]):
                for key in Set(x.keys).union(y.keys).sorted() { walk(x[key], y[key], "\(path).\(key)") }
            case (let x as [Any], let y as [Any]):
                if x.count != y.count { out.append("\(path): \(x.count) items vs \(y.count)") }
                for i in 0..<min(x.count, y.count) { walk(x[i], y[i], "\(path)[\(i)]") }
            default:
                let left = a.map { "\($0)" } ?? "missing"
                let right = b.map { "\($0)" } ?? "missing"
                if left != right { out.append("\(path): \(left.prefix(80)) vs \(right.prefix(80))") }
            }
        }
        walk(a, b, path)
        return out
    }

    /// Writes `object` as pretty, key-sorted JSON.
    static func write(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
