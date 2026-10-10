//
//  TextPieceReader.swift
//  OpenIntelligence
//

import Foundation

/// Cuts a large text file into pieces of whole lines without reading the file into memory.
///
/// Through 5.6, and in the first builds of 5.7, a text or JSON Lines file was read whole, cleaned
/// whole and chunked whole. An 88 MB JSON Lines file on an iPhone (2026-10-09) became one string
/// of 93 million characters, held 2.8 GB while it was cleaned, and the app was ended for memory
/// before the file was a fifth chunked. From 5.7 a file over `DocumentProcessor.piecewiseTextBytes`
/// is imported a piece at a time (`RAGService.importLargeTextStreamed`), the way a large PDF is
/// imported a batch of pages at a time.
///
/// The file is memory-mapped, so a piece costs the pages it touches. A piece ends just after a
/// line feed, which keeps every line, and so every JSON Lines record, whole.
nonisolated struct TextPieceReader: Sendable {
    /// Bytes a piece aims for. A piece is cleaned, cut into passages and embedded as one unit
    /// and is what a checkpoint saves, so this is also the most work an interruption can cost.
    static let pieceBytes = 2 * 1_048_576

    /// A single line longer than this is cut anyway, at a character boundary. Without a ceiling
    /// one file with no line feeds would be one piece the size of the file.
    static let longestLineBytes = 16 * 1_048_576

    private static let lineFeed: UInt8 = 0x0A

    let data: Data

    var count: Int { data.count }

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
    }

    init(data: Data) {
        // Re-based so that offsets are from zero whatever slice was passed in.
        self.data = Data(data)
    }

    /// False for a file whose line feeds cannot be found a byte at a time: UTF-16 and UTF-32,
    /// by their byte-order mark or by the zero bytes those encodings put in ordinary text. Such a
    /// file is imported in one go, as before.
    var canBeCutAtLineFeeds: Bool {
        guard count > 0 else { return false }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            if bytes.count >= 2 {
                let first = bytes[0]
                let second = bytes[1]
                if (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF) { return false }
            }
            let probe = min(bytes.count, 4_096)
            for index in 0..<probe where bytes[index] == 0 { return false }
            return true
        }
    }

    /// Where the piece that starts at `start` ends: just past the last line feed within
    /// `targetBytes`, or past the first one after that when the line is longer, or the end of the
    /// file. A line longer than `longestLine` is cut at a UTF-8 character boundary.
    func pieceEnd(
        from start: Int, targetBytes: Int = TextPieceReader.pieceBytes,
        longestLine: Int = TextPieceReader.longestLineBytes
    ) -> Int {
        let total = count
        guard start < total else { return total }
        let target = max(1, targetBytes)
        let limit = min(start + target, total)
        if limit == total { return total }

        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            let bytes = raw.bindMemory(to: UInt8.self)

            var index = limit - 1
            while index >= start {
                if bytes[index] == Self.lineFeed { return index + 1 }
                index -= 1
            }

            let cap = min(start + max(target, longestLine), total)
            index = limit
            while index < cap {
                if bytes[index] == Self.lineFeed { return index + 1 }
                index += 1
            }
            if cap == total { return total }

            // Bytes of the form 10xxxxxx continue a character; the cut goes before its first byte.
            var cut = cap
            while cut > start + 1, bytes[cut] & 0xC0 == 0x80 { cut -= 1 }
            return cut
        }
    }

    /// Every piece of the file, in order. The ranges touch and cover the file.
    func pieceRanges(
        targetBytes: Int = TextPieceReader.pieceBytes, longestLine: Int = TextPieceReader.longestLineBytes
    ) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while start < count {
            let end = pieceEnd(from: start, targetBytes: targetBytes, longestLine: longestLine)
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// Lines in `range` that hold something other than spaces, tabs and carriage returns. That
    /// is what `JSONRecordExtractor` counts as a record of a JSON Lines file, so this gives a
    /// piece's records, and the whole file's, without decoding either.
    func nonBlankLineCount(in range: Range<Int>) -> Int {
        let lower = max(0, range.lowerBound)
        let upper = min(count, range.upperBound)
        guard lower < upper else { return 0 }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lines = 0
            var lineHoldsText = false
            for index in lower..<upper {
                let byte = bytes[index]
                if byte == Self.lineFeed {
                    if lineHoldsText { lines += 1 }
                    lineHoldsText = false
                } else if byte != 0x20, byte != 0x09, byte != 0x0D {
                    lineHoldsText = true
                }
            }
            if lineHoldsText { lines += 1 }
            return lines
        }
    }

    /// A copy of the bytes of one piece.
    func bytes(in range: Range<Int>) -> Data {
        let lower = max(0, range.lowerBound)
        let upper = min(count, range.upperBound)
        guard lower < upper else { return Data() }
        return data.subdata(in: lower..<upper)
    }
}
