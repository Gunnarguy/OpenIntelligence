//
//  LoggingConfiguration.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/19/25.
//

import Foundation

/// Global logging configuration for OpenIntelligence
/// Controls verbosity of console output across all services
///
/// Note: This enum and its nested types are explicitly nonisolated to allow
/// logging from any actor context (RAGEngine, App Intents, background tasks).
nonisolated enum LoggingConfiguration {
    // The project is compiled with `-default-isolation=MainActor` (Swift 6 mode), which
    // means *unannotated* declarations become MainActor-isolated by default.
    //
    // Logging must be callable from background actors/tasks (e.g., `RAGEngine`, App Intents),
    // so we explicitly opt the logging API out of isolation and guard shared state with a lock.
    private static let stateLock = NSLock()

    /// Logging level for the application
    enum Level: Int, Comparable, Sendable {
        case silent = 0 // No logs (production)
        case error = 1 // Only errors
        case warning = 2 // Errors + warnings
        case info = 3 // Errors + warnings + info
        case debug = 4 // All logs including debug
        case verbose = 5 // Maximum verbosity (development)

        static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// Backing store for `currentLevel`. Access via the lock-guarded computed property.
    private static var _currentLevel: Level = {
        #if DEBUG
            return .verbose // Maximum logging in debug builds
        #else
            return .error // Only errors in release builds
        #endif
    }()

    /// Current logging level (can be changed at runtime)
    static var currentLevel: Level {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _currentLevel
        }
        set {
            stateLock.lock()
            _currentLevel = newValue
            stateLock.unlock()
        }
    }

    /// Enable/disable specific logging categories
    private static var _enabledCategories: Set<Category> = {
        #if DEBUG
            return Set(Category.allCases) // All categories in debug builds
        #else
            return [] // Minimal logging in release
        #endif
    }()

    /// Enable/disable specific logging categories
    static var enabledCategories: Set<Category> {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _enabledCategories
        }
        set {
            stateLock.lock()
            _enabledCategories = newValue
            stateLock.unlock()
        }
    }

    /// Logging categories for fine-grained control
    enum Category: Hashable, Sendable, CaseIterable {
        case initialization // App/service startup
        case ingestion // Document processing
        case embedding // Embedding generation
        case vectorDB // Vector database operations
        case retrieval // Search/retrieval
        case llm // LLM generation
        case pipeline // RAG pipeline steps
        case performance // Performance metrics
        case streaming // Token streaming
        case telemetry // Telemetry events
        case ui // UI updates
        case billing // StoreKit and entitlement flows
        case pipelineTrace // Smart pipeline trace (condensed mode awareness)
    }

    // MARK: - Pipeline Trace Mode

    /// Backing store for pipeline trace mode
    private static var _pipelineTraceEnabled: Bool = false

    /// Enable condensed pipeline trace logging (shows mode-aware steps without overwhelming output)
    static var pipelineTraceEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _pipelineTraceEnabled
        }
        set {
            stateLock.lock()
            _pipelineTraceEnabled = newValue
            stateLock.unlock()
        }
    }

    /// Log a pipeline trace step with timing (only when trace mode is enabled)
    /// - Parameters:
    ///   - step: Step number/name (e.g., "1", "1.5", "RAPTOR")
    ///   - title: Brief title of the step
    ///   - details: Key-value pairs for important metrics (condensed)
    ///   - duration: Optional duration in seconds
    static func pipelineStep(
        _ step: String,
        title: String,
        details: [(String, String)] = [],
        duration: TimeInterval? = nil
    ) {
        guard pipelineTraceEnabled else { return }

        let timeStr = duration.map { String(format: "%.0fms", $0 * 1000) } ?? ""
        let detailStr = details.map { "\($0.0): \($0.1)" }.joined(separator: " │ ")

        let stepBox = "[\(step)]".padding(toLength: 8, withPad: " ", startingAt: 0)
        let titlePad = title.padding(toLength: 28, withPad: " ", startingAt: 0)
        let timePad = timeStr.padding(toLength: 8, withPad: " ", startingAt: 0)

        captureForShare("🔹 \(stepBox) \(titlePad) \(timePad) │ \(detailStr)")
        #if DEBUG
        print("🔹 \(stepBox) \(titlePad) \(timePad) │ \(detailStr)")
        #endif
    }

    /// Log pipeline mode header (quality mode, RAPTOR-lite status)
    static func pipelineHeader(
        mode: String,
        raptorSummaries: Bool,
        raptorRouting: Bool,
        queryType: String? = nil
    ) {
        guard pipelineTraceEnabled else { return }

        let separator = String(repeating: "═", count: 70)
        #if DEBUG
        print("\n\(separator)")
        print("🚀 PIPELINE TRACE: \(mode.uppercased()) MODE")

        let summaryStatus = raptorSummaries ? "✅ ON" : "❌ OFF"
        let routingStatus = raptorRouting ? "✅ ON" : "❌ OFF"
        print("   RAPTOR-lite: Summaries=\(summaryStatus) │ QueryRouting=\(routingStatus)")

        if let qType = queryType {
            print("   Query Type: \(qType)")
        }
        print(separator)
        #endif
    }

    /// Log pipeline completion summary
    static func pipelineComplete(
        totalDuration: TimeInterval,
        chunksRetrieved: Int,
        tokensUsed: Int? = nil,
        confidence: Double? = nil
    ) {
        guard pipelineTraceEnabled else { return }

        var summary = "Retrieved \(chunksRetrieved) chunks"
        if let tokens = tokensUsed {
            summary += " │ \(tokens) tokens"
        }
        if let conf = confidence {
            summary += " │ confidence: \(String(format: "%.0f%%", conf * 100))"
        }

        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ PIPELINE COMPLETE: \(String(format: "%.0fms", totalDuration * 1000)) │ \(summary)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        #endif
    }

    /// Check if logging is enabled for a given level
    static func isEnabled(_ level: Level) -> Bool {
        return level <= currentLevel
    }

    /// Check if logging is enabled for a category
    static func isEnabled(_ category: Category) -> Bool {
        return enabledCategories.contains(category)
    }

    // MARK: - File-Based Trace Logger
    //
    // Captures pipeline/llm/retrieval/ingestion/embedding logs to a rolling file
    // in the app's Documents directory. This file can be pulled from the device
    // to the Mac for debugging without copy-pasting console output.
    //
    // Usage:
    //   1. App writes to Documents/pipeline_trace.log automatically
    //   2. Run: scripts/pull_trace.sh  (pulls from connected iPhone to Xrays/)
    //   3. Read Xrays/pipeline_trace.log
    //
    // The file is capped at ~500KB and auto-rotates. Only debug builds log to file.

    /// Categories that get written to the trace file (pipeline-relevant only)
    private static let fileLogCategories: Set<Category> = [
        .pipeline, .llm, .retrieval, .ingestion, .embedding, .pipelineTrace
    ]

    /// Backing store for file logger state
    private static var _fileLogEnabled: Bool = {
        #if DEBUG
            return true  // Auto-enable in debug builds
        #else
            return false
        #endif
    }()

    /// Whether file logging is enabled
    static var fileLogEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _fileLogEnabled
        }
        set {
            stateLock.lock()
            _fileLogEnabled = newValue
            stateLock.unlock()
        }
    }

    // MARK: - In-memory ring buffer, so the in-app share carries real logs

    /// Recent log lines held in memory for `PipelineTraceExporter`.
    ///
    /// Why this exists: the in-app "share trace" was built entirely from the UI's own
    /// `capturedThinkingEvents` (`ChatScreen.swift`), so it contained **no `Log` output of any
    /// kind** — no retrieval detail, no LLM detail, and no ingestion at all, since ingestion
    /// happens at import time and is attached to no message. Every request for device evidence
    /// therefore really meant "sit tethered to Xcode and copy the console", which defeats testing
    /// on a phone. This buffer is what makes a phone-only trace worth reading.
    ///
    /// Bounded on **both** line count and bytes. Ingestion alone emits thousands of lines per
    /// document — 5,245 in one measured session — so a line cap without a byte cap still allows an
    /// unbounded share, and a byte cap without a line cap allows unbounded array growth.
    ///
    /// Guarded by its own lock rather than `stateLock`, deliberately: `writeToFile` holds
    /// `stateLock` across the file write, and reusing it here would put a lock acquisition inside
    /// that critical section the first time someone moved a call.
    private static let ringLock = NSLock()
    private static let ringMaxLines = 4000
    private static let ringMaxBytes = 512_000
    private static var _ring: [String] = []
    private static var _ringBytes = 0

    /// Record a line for the in-app share. Cheap and non-throwing; never on the caller's hot path
    /// for more than an append.
    private static func captureForShare(_ line: String) {
        ringLock.lock()
        defer { ringLock.unlock() }
        _ring.append(line)
        _ringBytes += line.utf8.count
        guard _ring.count > ringMaxLines || _ringBytes > ringMaxBytes else { return }
        // Evict in a batch. `removeFirst()` per line is O(n) each time and this runs on every log
        // call once the buffer is warm; dropping a quarter at once makes it amortised O(1).
        let drop = max(1, _ring.count / 4)
        for line in _ring.prefix(drop) { _ringBytes -= line.utf8.count }
        _ring.removeFirst(drop)
    }

    /// The recent log lines, oldest first. Empty when nothing has been logged.
    ///
    /// Subject to the same level and category gates as everything else. In a Release build that
    /// means **nothing** by default, not "errors only": `_enabledCategories` is empty in Release and
    /// the category guard in `log()` runs after the level guard, so an `.error` carrying a category
    /// is dropped too. What *does* open it is Settings -> Developer, which ships in Release and sets
    /// `currentLevel` and `enabledCategories` at runtime — so this buffer fills on TestFlight once a
    /// user turns logging on. This changes what a share *contains*, never what the app *logs*.
    static func recentLogLines(limit: Int? = nil) -> [String] {
        ringLock.lock()
        defer { ringLock.unlock() }
        if let limit, limit > 0, limit < _ring.count { return Array(_ring.suffix(limit)) }
        return _ring
    }

    /// Drop the buffered lines. Used by the harness between cases so one case cannot inherit
    /// another's tail.
    static func clearRecentLogLines() {
        ringLock.lock()
        defer { ringLock.unlock() }
        _ring.removeAll(keepingCapacity: true)
        _ringBytes = 0
    }

    /// Maximum file size before rotation (~500KB)
    private static let maxFileSize: UInt64 = 500_000

    /// File handle for the trace log (lazy-initialized)
    private static var _fileHandle: FileHandle?
    private static var _fileURL: URL?

    /// Get or create the trace log file handle
    /// Bytes written by this process since the handle was opened, so rotation can be evaluated
    /// without a `stat` on every line. Seeded from the file's size when the handle is opened.
    private static var _bytesOnDisk: UInt64 = 0

    private static func traceFileHandle() -> FileHandle? {
        if let handle = _fileHandle {
            // Rotation used to live below the early return, which meant the size check ran exactly
            // once per launch — on the first log line — and never again. Within a session the file
            // grew without limit, and the check then fired on the *next* launch. That is the worst
            // possible timing: relaunching the app to go and share the trace is what rotated the
            // session you wanted out into `pipeline_trace.prev.log`, leaving a nearly empty live
            // file. Observed directly on 2026-08-21, a 569 KB `.prev.log` beside a 145 KB live one.
            //
            // Counting bytes in-process keeps this cheap: no `stat` per line.
            if _bytesOnDisk > maxFileSize {
                rotateLocked()
                return _fileHandle
            }
            return handle
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docsDir = docs else { return nil }

        let fileURL = docsDir.appendingPathComponent("pipeline_trace.log")
        _fileURL = fileURL

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "═══ OpenIntelligence Pipeline Trace ═══\nStarted: \(ISO8601DateFormatter().string(from: Date()))\n\n"
            FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8))
        }

        let existing = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))
            .flatMap { $0[.size] as? UInt64 } ?? 0
        if existing > maxFileSize {
            _bytesOnDisk = existing
            rotateLocked()
            return _fileHandle
        }

        _bytesOnDisk = existing
        _fileHandle = openAppending(fileURL)
        return _fileHandle
    }

    /// Open the trace for writing in **append mode**.
    ///
    /// `FileHandle(forWritingTo:)` plus `seekToEndOfFile()` keeps a per-handle offset, so two
    /// handles over the same path — a second app process, an extension, a relaunch overlapping a
    /// process that has not exited — each believe they own the end of the file and write over one
    /// another. The symptom is a line with a second timestamp spliced into its middle and the first
    /// entry truncated mid-word. Measured at ~0.2% of lines (14 of ~6,900) in a real simulator
    /// trace on 2026-08-21, which is rare enough to look like a formatting quirk and is in fact
    /// destroyed data.
    ///
    /// `O_APPEND` moves the offset-to-end and the write into one atomic kernel operation, so
    /// concurrent writers interleave between lines instead of inside them. This does not require
    /// knowing which writer was responsible, which is the point: the guarantee holds for all of them.
    private static func openAppending(_ url: URL) -> FileHandle? {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Move the live trace aside and start a fresh one. Caller must hold `stateLock`.
    private static func rotateLocked() {
        guard let fileURL = _fileURL else { return }
        let docsDir = fileURL.deletingLastPathComponent()
        try? _fileHandle?.close()
        _fileHandle = nil

        let backupURL = docsDir.appendingPathComponent("pipeline_trace.prev.log")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        let header = "═══ OpenIntelligence Pipeline Trace (rotated) ═══\nStarted: \(ISO8601DateFormatter().string(from: Date()))\nPrevious session: pipeline_trace.prev.log\n\n"
        FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8))
        _bytesOnDisk = UInt64(header.utf8.count)
        _fileHandle = openAppending(fileURL)
    }

    /// Write a line to the trace log file (non-blocking, fire-and-forget)
    private static func writeToFile(_ message: String, category: Category?) {
        guard _fileLogEnabled else { return }
        guard let cat = category, fileLogCategories.contains(cat) else { return }

        // Format: [HH:mm:ss.SSS] [CATEGORY] message
        let timestamp = fileTimestampFormatter.string(from: Date())
        let catName = String(describing: cat).uppercased().padding(toLength: 12, withPad: " ", startingAt: 0)
        let line = "[\(timestamp)] [\(catName)] \(message)\n"

        guard let data = line.data(using: .utf8) else { return }

        stateLock.lock()
        let handle = traceFileHandle()
        handle?.write(data)
        _bytesOnDisk += UInt64(data.count)
        stateLock.unlock()
    }

    /// Mark a new query in the trace log with a clear separator
    static func traceQueryStart(_ query: String) {
        guard _fileLogEnabled else { return }
        let separator = String(repeating: "━", count: 72)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let header = "\n\(separator)\n▶ QUERY: \(query)\n  TIME: \(timestamp)\n\(separator)\n"
        guard let data = header.data(using: .utf8) else { return }
        stateLock.lock()
        let handle = traceFileHandle()
        handle?.write(data)
        stateLock.unlock()
    }

    /// Mark query completion in the trace log
    static func traceQueryEnd(responseLength: Int, duration: TimeInterval) {
        guard _fileLogEnabled else { return }
        let footer = "◀ QUERY COMPLETE: \(responseLength) chars in \(String(format: "%.1fs", duration))\n\n"
        guard let data = footer.data(using: .utf8) else { return }
        stateLock.lock()
        let handle = traceFileHandle()
        handle?.write(data)
        stateLock.unlock()
    }

    /// Flush the file handle (call on app background/terminate)
    static func flushTraceLog() {
        stateLock.lock()
        _fileHandle?.synchronizeFile()
        stateLock.unlock()
    }

    /// Timestamp formatter for file log entries
    private static let fileTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Log message with level check
    static func log(_ level: Level, category: Category? = nil, _ message: String) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }

        let prefix: String
        switch level {
        case .silent: return
        case .error: prefix = "❌"
        case .warning: prefix = "⚠️ "
        case .info: prefix = "ℹ️ "
        case .debug: prefix = "🔍"
        case .verbose: prefix = "📝"
        }

        #if DEBUG
        print("\(prefix) \(message)")
        #endif

        // Captured for the in-app share regardless of `#if DEBUG`, because the console does not
        // exist on a phone that is not plugged into Xcode and this buffer is the only thing that
        // makes an untethered trace readable. The level and category gates above still apply, so
        // a Release build contributes only what `.error` admits.
        captureForShare("[\(fileTimestampFormatter.string(from: Date()))] \(prefix) \(message)")

        // Also write to trace file for pipeline-relevant categories
        writeToFile(message, category: category)
    }

    /// Convenience methods for common log levels
    static func error(_ message: String, category: Category? = nil) {
        log(.error, category: category, message)
    }

    static func warning(_ message: String, category: Category? = nil) {
        log(.warning, category: category, message)
    }

    static func info(_ message: String, category: Category? = nil) {
        log(.info, category: category, message)
    }

    static func debug(_ message: String, category: Category? = nil) {
        log(.debug, category: category, message)
    }

    static func verbose(_ message: String, category: Category? = nil) {
        log(.verbose, category: category, message)
    }

    /// Print a section header (respects level and category)
    static func section(_ title: String, level: Level = .info, category: Category? = nil) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        let separator = String(repeating: "━", count: 60)
        #if DEBUG
        print("\n\(separator)")
        print("  \(title)")
        print("\(separator)")
        #endif
    }

    /// Print a boxed message (respects level and category)
    static func box(_ title: String, level: Level = .info, category: Category? = nil, content: [String] = []) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        let width = 62
        #if DEBUG
        print("\n╔" + String(repeating: "═", count: width) + "╗")
        print("║ \(title.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
        if !content.isEmpty {
            print("╠" + String(repeating: "═", count: width) + "╣")
            for line in content {
                print("║ \(line.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
            }
        }
        print("╚" + String(repeating: "═", count: width) + "╝")
        #endif
    }
}

/// Convenience typealias for shorter code
typealias Log = LoggingConfiguration
