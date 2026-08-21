import XCTest

@testable import OpenIntelligenceEngine

/// Covers the in-memory log buffer that makes an untethered device trace readable.
///
/// Before 2026-08-21 the in-app "share trace" was assembled entirely from the UI's
/// `capturedThinkingEvents`, so it carried **no `Log` output at all** — no retrieval internals, no
/// LLM detail, and no ingestion, since ingestion happens at import time and belongs to no message.
/// Reading a device trace therefore meant reading the Xcode console, which meant being plugged into
/// a Mac. This buffer is the thing that removes that requirement, so its bounds are worth pinning:
/// an unbounded version would grow without limit during ingestion, which emits thousands of lines
/// per document (5,245 measured in one session).
final class LogShareBufferTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LoggingConfiguration.clearRecentLogLines()
    }

    override func tearDown() {
        LoggingConfiguration.clearRecentLogLines()
        super.tearDown()
    }

    // MARK: - It captures at all

    func testLoggedLinesAreAvailableToTheShare() {
        LoggingConfiguration.error("first marker", category: .ingestion)
        LoggingConfiguration.error("second marker", category: .ingestion)

        let lines = LoggingConfiguration.recentLogLines()
        XCTAssertTrue(lines.contains { $0.contains("first marker") })
        XCTAssertTrue(lines.contains { $0.contains("second marker") })
    }

    /// Ingestion is the case the buffer exists for, and it is the one the old export could never
    /// reach. `.error` is used throughout these tests because it is the only level that passes the
    /// gate in every build configuration, so the suite behaves the same in Debug and Release.
    func testIngestionCategoryIsCaptured() {
        LoggingConfiguration.error("[DocumentProcessor] page 3 spatial extraction ok", category: .ingestion)
        XCTAssertTrue(
            LoggingConfiguration.recentLogLines().contains { $0.contains("spatial extraction ok") },
            "Ingestion lines are the reason this buffer exists; they must reach the share."
        )
    }

    func testOrderIsOldestFirst() {
        for i in 1...5 {
            LoggingConfiguration.error("ordered-\(i)", category: .ingestion)
        }
        let captured = LoggingConfiguration.recentLogLines().filter { $0.contains("ordered-") }
        let indices = captured.compactMap { line -> Int? in
            line.split(separator: "-").last.flatMap { Int($0) }
        }
        XCTAssertEqual(indices, [1, 2, 3, 4, 5], "The share reads chronologically; order is load-bearing.")
    }

    // MARK: - The bounds

    /// The line cap must hold under a volume comparable to a real ingestion.
    func testLineCountStaysBoundedUnderIngestionVolume() {
        for i in 1...6000 {
            LoggingConfiguration.error("bulk line \(i)", category: .ingestion)
        }
        let count = LoggingConfiguration.recentLogLines().count
        XCTAssertLessThanOrEqual(count, 4000, "Line cap exceeded; the buffer would grow unbounded.")
        XCTAssertGreaterThan(count, 0)
    }

    /// A line cap alone is not enough: 4,000 long lines is still an unbounded share. Both caps have
    /// to hold at once, which is why this asserts bytes rather than lines.
    func testByteFootprintStaysBoundedWithLongLines() {
        let long = String(repeating: "x", count: 2000)
        for i in 1...600 {
            LoggingConfiguration.error("\(i) \(long)", category: .ingestion)
        }
        let bytes = LoggingConfiguration.recentLogLines().reduce(0) { $0 + $1.utf8.count }
        XCTAssertLessThanOrEqual(
            bytes, 512_000 + 8192,
            "Byte cap exceeded. 600 x 2KB is 1.2MB of lines; the buffer must evict, not accumulate."
        )
    }

    /// Eviction drops the oldest, so the most recent activity, which is what someone is sharing a
    /// trace about, always survives.
    func testEvictionKeepsTheMostRecentLines() {
        for i in 1...6000 {
            LoggingConfiguration.error("seq \(i)", category: .ingestion)
        }
        let lines = LoggingConfiguration.recentLogLines()
        XCTAssertTrue(lines.contains { $0.contains("seq 6000") }, "The newest line must survive eviction.")
        XCTAssertFalse(lines.contains { $0.contains("seq 1 ") }, "The oldest line should have been evicted.")
    }

    // MARK: - Housekeeping

    func testLimitReturnsTheTail() {
        for i in 1...50 {
            LoggingConfiguration.error("tail \(i)", category: .ingestion)
        }
        let tail = LoggingConfiguration.recentLogLines(limit: 5)
        XCTAssertEqual(tail.count, 5)
        XCTAssertTrue(tail.last?.contains("tail 50") == true)
    }

    func testClearEmptiesTheBuffer() {
        LoggingConfiguration.error("to be cleared", category: .ingestion)
        XCTAssertFalse(LoggingConfiguration.recentLogLines().isEmpty)
        LoggingConfiguration.clearRecentLogLines()
        XCTAssertTrue(LoggingConfiguration.recentLogLines().isEmpty)
    }

    /// The buffer is written from whatever thread logged, and read on the main thread when the user
    /// taps share. A data race here would corrupt the array rather than merely reorder it.
    func testConcurrentLoggingDoesNotCorruptTheBuffer() {
        let iterations = 500
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            LoggingConfiguration.error("concurrent \(i)", category: .ingestion)
        }
        let lines = LoggingConfiguration.recentLogLines()
        XCTAssertLessThanOrEqual(lines.count, 4000)
        XCTAssertGreaterThan(lines.count, 0)
        // Every surviving line must be intact — a torn write would leave a line that does not
        // match the shape every writer produced.
        XCTAssertTrue(
            lines.allSatisfy { $0.contains("concurrent ") },
            "A line was torn or interleaved, which means the buffer is not correctly guarded."
        )
    }
}
