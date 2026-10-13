//
//  PassageFileIndex.swift
//  OpenIntelligence
//
//  Finds where each passage sits in the vector store's metadata file, and reads the few facts
//  callers ask for without a passage's text, so the store does not have to decode every passage
//  to open a library.
//
//  The file is what it has been since the binary format: one JSON array of `DocumentChunk`
//  objects, written by `JSONEncoder`. Nothing here changes it. Through 5.6 a load decoded the
//  whole array, which for 144,247 passages was 159 MB of JSON, 3.0 to 3.2 s on an iPhone 16 Pro
//  Max and every passage's text held in memory from then on. A load now walks the bytes once,
//  noting each object's range and five of its values, and a passage is decoded when it is asked
//  for.
//
//  The walk is deliberately small: it understands strings, nesting and whole numbers, and
//  nothing else of JSON. Whenever an object is not shaped the way the encoder writes it (any
//  key with an escape in it, one of the keys it reads appearing twice, an id that is not a
//  plain UUID string, a number with a fraction), the object's values are read by `JSONDecoder`
//  instead, so the walk is only ever trusted where it is certain. A file it cannot follow
//  returns nil and the store falls back to decoding the whole array, as before: brackets that
//  do not match, a value nested more than 64 deep, or a member of a passage or of its metadata
//  whose value is a bare word other than a number, true, false or null. Inside a value it
//  skips, the walk follows only the strings and the brackets.
//
//  What the walk does not do is check a passage the way decoding it does. A passage whose JSON
//  is sound and whose values `DocumentChunk` rejects (a value from a newer version of the app,
//  a missing field) gets a slot here and fails when it is decoded. The store then leaves it
//  out of a search or a read of one document, and refuses to hand over every passage at once
//  (`BNNSVectorDatabase.everyChunk`).
//

import Foundation

/// The facts about one stored passage that callers ask for without reading its text.
nonisolated struct PassageRecord: Sendable, Equatable {
    let id: UUID
    let documentId: UUID
    /// The passage's number within its document (`ChunkMetadata.chunkIndex`).
    let chunkIndex: Int
    let pageNumber: Int?
    let abstractionLevel: ChunkAbstractionLevel
}

/// One passage of the store: its record, and where its JSON object is in the metadata file.
/// Seventy-two bytes, so a library of 144,247 passages is 10 MB of these.
nonisolated struct PassageSlot: Sendable {
    var id: UUID
    var documentId: UUID
    /// Byte offset of the passage's JSON object from the start of the mapped metadata file, or
    /// `PassageSlot.inMemory` when the passage has not been written to the file yet.
    var offset: Int
    var length: Int
    var chunkIndex: Int
    var pageNumberValue: Int
    var hasPageNumber: Bool
    var abstractionLevelRaw: UInt8

    static let inMemory = -1

    var isInFile: Bool { offset >= 0 }

    var record: PassageRecord {
        PassageRecord(
            id: id,
            documentId: documentId,
            chunkIndex: chunkIndex,
            pageNumber: hasPageNumber ? pageNumberValue : nil,
            abstractionLevel: ChunkAbstractionLevel(rawValue: Int(abstractionLevelRaw)) ?? .detail
        )
    }

    /// The slot of a passage held in memory.
    init(inMemory chunk: DocumentChunk) {
        self.id = chunk.id
        self.documentId = chunk.documentId
        self.offset = Self.inMemory
        self.length = 0
        self.chunkIndex = chunk.metadata.chunkIndex
        self.pageNumberValue = chunk.metadata.pageNumber ?? 0
        self.hasPageNumber = chunk.metadata.pageNumber != nil
        self.abstractionLevelRaw = UInt8(clamping: chunk.metadata.abstractionLevel.rawValue)
    }

    fileprivate init(
        id: UUID, documentId: UUID, offset: Int, length: Int, chunkIndex: Int, pageNumber: Int?,
        abstractionLevelRaw: UInt8
    ) {
        self.id = id
        self.documentId = documentId
        self.offset = offset
        self.length = length
        self.chunkIndex = chunkIndex
        self.pageNumberValue = pageNumber ?? 0
        self.hasPageNumber = pageNumber != nil
        self.abstractionLevelRaw = abstractionLevelRaw
    }
}

nonisolated enum PassageFileIndex {
    /// A file smaller than this is walked on one thread.
    static let parallelThresholdBytes = 8 * 1_048_576

    /// The slots of a metadata file, in the file's order, or nil when the bytes are not a JSON
    /// array of passage objects this walk can follow.
    ///
    /// A large file is walked in several stretches at once. A stretch has to start where an
    /// element starts, and the only way to know where elements start is to have walked there,
    /// so the starts are guesses: the bytes `},{"` are what the encoder writes where one passage
    /// ends and the next begins. They can turn up elsewhere (a text that ends in `},{` is
    /// followed by its closing quote), so a guess is never trusted. Each stretch has to end
    /// exactly on the next
    /// stretch's start, having walked whole elements to get there, and the first stretch starts
    /// at the array's real first element, so one wrong guess makes a stretch miss its end and
    /// the whole file is walked again on one thread.
    static func scan(_ data: Data, threads: Int = ProcessInfo.processInfo.activeProcessorCount) -> [PassageSlot]? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [PassageSlot]? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            if threads > 1, raw.count >= parallelThresholdBytes,
                let slots = scanInStretches(base: base, end: raw.count, threads: threads)
            {
                return slots
            }
            var walker = Walker(base: base, end: raw.count)
            return walker.array()
        }
    }

    private static func scanInStretches(base: UnsafePointer<UInt8>, end: Int, threads: Int) -> [PassageSlot]? {
        var opening = Walker(base: base, end: end)
        guard let first = opening.firstElementStart() else { return nil }
        let stretches = max(1, min(threads, (end - first) / (parallelThresholdBytes / 4)))
        guard stretches > 1 else { return nil }
        var starts = [first]
        let boundary: [UInt8] = [0x7D, 0x2C, 0x7B, 0x22]  // },{"
        for stretch in 1..<stretches {
            let target = first + (end - first) / stretches * stretch
            guard target > (starts.last ?? first), target < end,
                let hit = boundary.withUnsafeBytes({ memmem(base + target, end - target, $0.baseAddress, 4) })
            else { continue }
            let start = base.distance(to: hit.assumingMemoryBound(to: UInt8.self)) + 2
            if start > (starts.last ?? first) { starts.append(start) }
        }
        guard starts.count > 1 else { return nil }

        let results = StretchResults(count: starts.count)
        let startsCopy = starts
        let address = UInt(bitPattern: base)
        DispatchQueue.concurrentPerform(iterations: startsCopy.count) { index in
            guard let pointer = UnsafePointer<UInt8>(bitPattern: address) else { return }
            var walker = Walker(base: pointer, end: end)
            let until = index + 1 < startsCopy.count ? startsCopy[index + 1] : nil
            results.set(walker.stretch(from: startsCopy[index], until: until), at: index)
        }
        let parts = results.all()
        var slots: [PassageSlot] = []
        slots.reserveCapacity(parts.reduce(0) { $0 + ($1?.count ?? 0) })
        for part in parts {
            guard let part else { return nil }
            slots.append(contentsOf: part)
        }
        return slots
    }

    /// Where the stretches put what they found. Each writes its own place once.
    private final class StretchResults: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [[PassageSlot]?]

        init(count: Int) { parts = Array(repeating: nil, count: count) }

        func set(_ part: [PassageSlot]?, at index: Int) {
            lock.lock()
            parts[index] = part
            lock.unlock()
        }

        func all() -> [[PassageSlot]?] {
            lock.lock()
            defer { lock.unlock() }
            return parts
        }
    }

    /// What `JSONDecoder` reads from one object when the walk could not. It asks for the same
    /// keys the walk does, with the same defaults `ChunkMetadata.init(from:)` applies.
    private struct DecodedRecord: Decodable {
        struct Metadata: Decodable {
            let chunkIndex: Int
            let pageNumber: Int?
            let abstractionLevel: ChunkAbstractionLevel?
        }
        let id: UUID
        let documentId: UUID
        let metadata: Metadata
    }

    /// Holds two addresses and a position and nothing reference-counted. Several of these walk
    /// one file at once, and in an unoptimised build a walker that carried the `Data` retained
    /// and released it on every call, which made eleven threads slower than one.
    private struct Walker {
        let base: UnsafePointer<UInt8>
        let end: Int
        var position = 0

        private static let quote = UInt8(ascii: "\"")
        private static let backslash = UInt8(ascii: "\\")
        private static let comma = UInt8(ascii: ",")
        private static let colon = UInt8(ascii: ":")
        private static let openBrace = UInt8(ascii: "{")
        private static let closeBrace = UInt8(ascii: "}")
        private static let openBracket = UInt8(ascii: "[")
        private static let closeBracket = UInt8(ascii: "]")

        init(base: UnsafePointer<UInt8>, end: Int) {
            self.base = base
            self.end = end
        }

        @inline(__always)
        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
        }

        private mutating func skipWhitespace() {
            while position < end, Self.isWhitespace(base[position]) { position += 1 }
        }

        /// At an opening quote. Moves past the closing quote and returns the range of the bytes
        /// between the two. `memchr` does the looking, because a passage's text is most of the
        /// file and a byte loop over it is what would make an unoptimised build slow.
        private mutating func string() -> Range<Int>? {
            guard position < end, base[position] == Self.quote else { return nil }
            let start = position + 1
            var search = start
            while search < end {
                guard let hit = memchr(base + search, Int32(Self.quote), end - search) else { return nil }
                let found = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                // A quote after an odd number of backslashes is part of the text.
                var backslashes = 0
                var before = found - 1
                while before >= start, base[before] == Self.backslash {
                    backslashes += 1
                    before -= 1
                }
                if backslashes % 2 == 0 {
                    position = found + 1
                    return start..<found
                }
                search = found + 1
            }
            return nil
        }

        /// A number as JSON writes one: an optional minus, digits with no leading zero, an
        /// optional fraction, an optional exponent. Written as plain loops: this runs for every
        /// number in the file, and in an unoptimised build a helper closure here cost a third
        /// of the whole walk.
        private func isNumber(_ range: Range<Int>) -> Bool {
            var cursor = range.lowerBound
            let stop = range.upperBound
            if cursor < stop, base[cursor] == 0x2D { cursor += 1 }  // -
            guard cursor < stop else { return false }
            if base[cursor] == 0x30 {
                cursor += 1
            } else {
                let start = cursor
                while cursor < stop, base[cursor] >= 0x30, base[cursor] <= 0x39 { cursor += 1 }
                guard cursor > start else { return false }
            }
            if cursor < stop, base[cursor] == 0x2E {  // .
                cursor += 1
                let start = cursor
                while cursor < stop, base[cursor] >= 0x30, base[cursor] <= 0x39 { cursor += 1 }
                guard cursor > start else { return false }
            }
            if cursor < stop, base[cursor] == 0x65 || base[cursor] == 0x45 {  // e E
                cursor += 1
                if cursor < stop, base[cursor] == 0x2B || base[cursor] == 0x2D { cursor += 1 }  // + -
                let start = cursor
                while cursor < stop, base[cursor] >= 0x30, base[cursor] <= 0x39 { cursor += 1 }
                guard cursor > start else { return false }
            }
            return cursor == stop
        }

        /// At the first byte of any value. Moves past it. False when the value is not one JSON
        /// allows as far as this walk looks: a bare word has to be a number, true, false or
        /// null, and every bracket has to be closed by its own kind.
        private mutating func skipValue() -> Bool {
            guard position < end else { return false }
            switch base[position] {
            case Self.quote:
                return string() != nil
            case Self.openBrace, Self.openBracket:
                // One bit for each open container, set for an array. Sixty-four deep is far
                // past anything a passage holds, and deeper goes to the decoder.
                var kinds: UInt64 = 0
                var depth = 0
                while position < end {
                    let byte = base[position]
                    if byte == Self.quote {
                        guard string() != nil else { return false }
                        continue
                    }
                    if byte == Self.openBrace || byte == Self.openBracket {
                        guard depth < 64 else { return false }
                        if byte == Self.openBracket {
                            kinds |= 1 << UInt64(depth)
                        } else {
                            kinds &= ~(1 << UInt64(depth))
                        }
                        depth += 1
                    } else if byte == Self.closeBrace || byte == Self.closeBracket {
                        guard depth > 0 else { return false }
                        depth -= 1
                        let openedAsArray = kinds & (1 << UInt64(depth)) != 0
                        guard openedAsArray == (byte == Self.closeBracket) else { return false }
                        if depth == 0 {
                            position += 1
                            return true
                        }
                    }
                    position += 1
                }
                return false
            default:
                // A number, true, false or null: it ends at the next comma, bracket or space.
                let start = position
                while position < end {
                    let byte = base[position]
                    if byte == Self.comma || byte == Self.closeBrace || byte == Self.closeBracket
                        || Self.isWhitespace(byte)
                    {
                        break
                    }
                    position += 1
                }
                let word = start..<position
                guard start < position else { return false }
                switch base[start] {
                case 0x74: return matches(word, "true")
                case 0x66: return matches(word, "false")
                case 0x6E: return matches(word, "null")
                default: return isNumber(word)
                }
            }
        }

        private func matches(_ range: Range<Int>, _ name: StaticString) -> Bool {
            guard range.count == name.utf8CodeUnitCount else { return false }
            return memcmp(base + range.lowerBound, name.utf8Start, range.count) == 0
        }

        @inline(__always)
        private static func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: return byte - 0x30
            case 0x41...0x46: return byte - 0x41 + 10
            case 0x61...0x66: return byte - 0x61 + 10
            default: return nil
            }
        }

        /// A UUID written the way `UUID.uuidString` writes it, 8-4-4-4-12 in either case.
        private func uuid(_ range: Range<Int>) -> UUID? {
            guard range.count == 36 else { return nil }
            let start = range.lowerBound
            let dash = UInt8(ascii: "-")
            guard base[start + 8] == dash, base[start + 13] == dash, base[start + 18] == dash,
                base[start + 23] == dash
            else { return nil }
            var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            var parsed = true
            withUnsafeMutableBytes(of: &bytes) { out in
                var cursor = start
                for index in 0..<16 {
                    if cursor == start + 8 || cursor == start + 13 || cursor == start + 18 || cursor == start + 23 {
                        cursor += 1
                    }
                    guard let high = Self.hexValue(base[cursor]), let low = Self.hexValue(base[cursor + 1]) else {
                        parsed = false
                        return
                    }
                    out[index] = high << 4 | low
                    cursor += 2
                }
            }
            return parsed ? UUID(uuid: bytes) : nil
        }

        /// The value at the cursor as a UUID string. Moves past the value either way.
        private mutating func uuidValue() -> UUID?? {
            guard position < end else { return nil }
            if base[position] == Self.quote {
                guard let body = string() else { return nil }
                return .some(uuid(body))
            }
            return skipValue() ? .some(nil) : nil
        }

        private enum Whole {
            case number(Int)
            case null
            /// A value of another kind, or a number the walk does not read (a fraction, an
            /// exponent, more digits than an `Int` holds).
            case other
        }

        /// The value at the cursor as a whole number or null. Moves past the value. Nil when
        /// the value cannot be skipped at all.
        private mutating func wholeValue() -> Whole? {
            let start = position
            guard skipValue() else { return nil }
            let stop = position
            var cursor = start
            var negative = false
            if cursor < stop, base[cursor] == UInt8(ascii: "-") {
                negative = true
                cursor += 1
            }
            let digitsStart = cursor
            var value = 0
            while cursor < stop, base[cursor] >= 0x30, base[cursor] <= 0x39 {
                guard cursor - digitsStart < 18 else { return .other }
                value = value * 10 + Int(base[cursor] - 0x30)
                cursor += 1
            }
            if cursor == stop, cursor > digitsStart {
                return .number(negative ? -value : value)
            }
            if stop - start == 4, memcmp(base + start, "null", 4) == 0 { return .null }
            return .other
        }

        private struct Found {
            var id: UUID?
            var documentId: UUID?
            var chunkIndex: Int?
            var pageNumber: Int?
            var abstractionLevel: Int?
            /// Something was not written the way the encoder writes it. `JSONDecoder` reads
            /// this object instead.
            var unsure = false
            /// The keys the walk reads that it has met in this object, one bit each. A second
            /// meeting makes the object the decoder's: which of two values counts is its rule.
            var seen: UInt8 = 0

            @inline(__always)
            mutating func meet(_ bit: UInt8) {
                if seen & bit != 0 { unsure = true }
                seen |= bit
            }
        }

        /// A key written with an escape could be any key, one of the keys the walk reads among
        /// them, so an object that has one is read by the decoder.
        @inline(__always)
        private func hasEscape(_ range: Range<Int>) -> Bool {
            range.lowerBound < range.upperBound
                && memchr(base + range.lowerBound, 0x5C, range.upperBound - range.lowerBound) != nil
        }

        /// At the opening brace of the metadata object. Moves past its closing brace.
        private mutating func metadata(into found: inout Found) -> Bool {
            guard position < end, base[position] == Self.openBrace else { return false }
            position += 1
            skipWhitespace()
            if position < end, base[position] == Self.closeBrace {
                position += 1
                return true
            }
            while true {
                skipWhitespace()
                guard let key = string() else { return false }
                skipWhitespace()
                guard position < end, base[position] == Self.colon else { return false }
                position += 1
                skipWhitespace()
                if hasEscape(key) { found.unsure = true }
                if matches(key, "chunkIndex") {
                    found.meet(0x08)
                    guard let value = wholeValue() else { return false }
                    if case .number(let number) = value { found.chunkIndex = number } else { found.unsure = true }
                } else if matches(key, "pageNumber") {
                    found.meet(0x10)
                    guard let value = wholeValue() else { return false }
                    switch value {
                    case .number(let number): found.pageNumber = number
                    case .null: found.pageNumber = nil
                    case .other: found.unsure = true
                    }
                } else if matches(key, "abstractionLevel") {
                    found.meet(0x20)
                    guard let value = wholeValue() else { return false }
                    switch value {
                    case .number(let number): found.abstractionLevel = number
                    case .null: found.abstractionLevel = nil
                    case .other: found.unsure = true
                    }
                } else {
                    guard skipValue() else { return false }
                }
                skipWhitespace()
                guard position < end else { return false }
                if base[position] == Self.comma {
                    position += 1
                    continue
                }
                if base[position] == Self.closeBrace {
                    position += 1
                    return true
                }
                return false
            }
        }

        /// At the opening brace of one passage. Moves past its closing brace and returns its slot.
        private mutating func passage() -> PassageSlot? {
            let start = position
            guard position < end, base[position] == Self.openBrace else { return nil }
            position += 1
            var found = Found()
            skipWhitespace()
            if position < end, base[position] == Self.closeBrace {
                position += 1
            } else {
                members: while true {
                    skipWhitespace()
                    guard let key = string() else { return nil }
                    skipWhitespace()
                    guard position < end, base[position] == Self.colon else { return nil }
                    position += 1
                    skipWhitespace()
                    if hasEscape(key) { found.unsure = true }
                    if matches(key, "id") {
                        found.meet(0x01)
                        guard let value = uuidValue() else { return nil }
                        if let id = value { found.id = id } else { found.unsure = true }
                    } else if matches(key, "documentId") {
                        found.meet(0x02)
                        guard let value = uuidValue() else { return nil }
                        if let id = value { found.documentId = id } else { found.unsure = true }
                    } else if matches(key, "metadata") {
                        found.meet(0x04)
                        if position < end, base[position] == Self.openBrace {
                            guard metadata(into: &found) else { return nil }
                        } else {
                            found.unsure = true
                            guard skipValue() else { return nil }
                        }
                    } else {
                        guard skipValue() else { return nil }
                    }
                    skipWhitespace()
                    guard position < end else { return nil }
                    if base[position] == Self.comma {
                        position += 1
                        continue
                    }
                    if base[position] == Self.closeBrace {
                        position += 1
                        break members
                    }
                    return nil
                }
            }
            let length = position - start

            var id = found.id
            var documentId = found.documentId
            var chunkIndex = found.chunkIndex
            var pageNumber = found.pageNumber
            var level = found.abstractionLevel
            if found.unsure || id == nil || documentId == nil || chunkIndex == nil {
                // Read by the decoder, which is the authority on anything unusual. The bytes are
                // lent to it for the length of the call and not copied.
                let slice = Data(
                    bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start), count: length,
                    deallocator: .none)
                guard let decoded = try? JSONDecoder().decode(DecodedRecord.self, from: slice) else {
                    return nil
                }
                id = decoded.id
                documentId = decoded.documentId
                chunkIndex = decoded.metadata.chunkIndex
                pageNumber = decoded.metadata.pageNumber
                level = decoded.metadata.abstractionLevel?.rawValue
            }
            guard let id, let documentId, let chunkIndex else { return nil }
            let levelRaw = level ?? ChunkAbstractionLevel.detail.rawValue
            // A level the app does not know is an error for the decoder, so it is one here.
            guard ChunkAbstractionLevel(rawValue: levelRaw) != nil, let fittedLevel = UInt8(exactly: levelRaw) else {
                return nil
            }
            return PassageSlot(
                id: id, documentId: documentId, offset: start, length: length, chunkIndex: chunkIndex,
                pageNumber: pageNumber, abstractionLevelRaw: fittedLevel)
        }

        /// The offset of the array's first element, or nil when the array is empty or the bytes
        /// do not open as an array of objects.
        mutating func firstElementStart() -> Int? {
            skipWhitespace()
            guard position < end, base[position] == Self.openBracket else { return nil }
            position += 1
            skipWhitespace()
            guard position < end, base[position] == Self.openBrace else { return nil }
            return position
        }

        /// Walks whole elements from `start`, which must be where an element starts. With
        /// `until`, the walk has to arrive exactly there after a comma. Without it, the walk
        /// has to reach the array's closing bracket and the end of the bytes. Anything else is
        /// nil.
        mutating func stretch(from start: Int, until: Int?) -> [PassageSlot]? {
            position = start
            var slots: [PassageSlot] = []
            while true {
                guard let slot = passage() else { return nil }
                slots.append(slot)
                if slots.count == Self.sizingSample {
                    // Room for the rest in one allocation, sized from the passages so far. An
                    // array that grows by doubling reallocates megabytes at a time, and several
                    // threads doing that at once wait on each other.
                    let average = max(1, (position - start) / Self.sizingSample)
                    slots.reserveCapacity(((until ?? end) - start) / average * 21 / 20 + Self.sizingSample)
                }
                skipWhitespace()
                guard position < end else { return nil }
                if base[position] == Self.comma {
                    position += 1
                    skipWhitespace()
                    if let until {
                        if position == until { return slots }
                        if position > until { return nil }
                    }
                    continue
                }
                if base[position] == Self.closeBracket {
                    guard until == nil else { return nil }
                    position += 1
                    skipWhitespace()
                    return position == end ? slots : nil
                }
                return nil
            }
        }

        /// How many passages are walked before the rest of an array is sized from them.
        private static let sizingSample = 32

        mutating func array() -> [PassageSlot]? {
            skipWhitespace()
            guard position < end, base[position] == Self.openBracket else { return nil }
            position += 1
            let arrayStart = position
            var slots: [PassageSlot] = []
            skipWhitespace()
            if position < end, base[position] == Self.closeBracket {
                position += 1
            } else {
                while true {
                    skipWhitespace()
                    guard let slot = passage() else { return nil }
                    slots.append(slot)
                    if slots.count == Self.sizingSample {
                        let average = max(1, (position - arrayStart) / Self.sizingSample)
                        slots.reserveCapacity((end - arrayStart) / average * 21 / 20 + Self.sizingSample)
                    }
                    skipWhitespace()
                    guard position < end else { return nil }
                    if base[position] == Self.comma {
                        position += 1
                        continue
                    }
                    if base[position] == Self.closeBracket {
                        position += 1
                        break
                    }
                    return nil
                }
            }
            skipWhitespace()
            return position == end ? slots : nil
        }
    }
}
