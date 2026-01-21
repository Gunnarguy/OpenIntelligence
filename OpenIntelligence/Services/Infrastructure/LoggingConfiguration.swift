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

        print("🔹 \(stepBox) \(titlePad) \(timePad) │ \(detailStr)")
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
        print("\n\(separator)")
        print("🚀 PIPELINE TRACE: \(mode.uppercased()) MODE")

        let summaryStatus = raptorSummaries ? "✅ ON" : "❌ OFF"
        let routingStatus = raptorRouting ? "✅ ON" : "❌ OFF"
        print("   RAPTOR-lite: Summaries=\(summaryStatus) │ QueryRouting=\(routingStatus)")

        if let qType = queryType {
            print("   Query Type: \(qType)")
        }
        print(separator)
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

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ PIPELINE COMPLETE: \(String(format: "%.0fms", totalDuration * 1000)) │ \(summary)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    /// Check if logging is enabled for a given level
    static func isEnabled(_ level: Level) -> Bool {
        return level <= currentLevel
    }

    /// Check if logging is enabled for a category
    static func isEnabled(_ category: Category) -> Bool {
        return enabledCategories.contains(category)
    }

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

        print("\(prefix) \(message)")
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
        print("\n\(separator)")
        print("  \(title)")
        print("\(separator)")
    }

    /// Print a boxed message (respects level and category)
    static func box(_ title: String, level: Level = .info, category: Category? = nil, content: [String] = []) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        let width = 62
        print("\n╔" + String(repeating: "═", count: width) + "╗")
        print("║ \(title.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
        if !content.isEmpty {
            print("╠" + String(repeating: "═", count: width) + "╣")
            for line in content {
                print("║ \(line.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
            }
        }
        print("╚" + String(repeating: "═", count: width) + "╝")
    }
}

/// Convenience typealias for shorter code
typealias Log = LoggingConfiguration
