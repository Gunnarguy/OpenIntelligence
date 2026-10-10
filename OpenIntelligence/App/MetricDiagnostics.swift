//
//  MetricDiagnostics.swift
//  OpenIntelligence
//
//  Subscribes to MetricKit's async sequences for metric and diagnostic reports,
//  logging summaries and persisting on-device reports without network transmission.
//

import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Records on-device MetricKit diagnostic and performance metric reports.
///
/// Marked `nonisolated` because `default-isolation=MainActor` is enabled, and metric
/// consumption runs on detached background tasks.
nonisolated enum MetricDiagnostics {
    private static let startLock = NSLock()
    private static var isStarted = false
    private static let fileLock = NSLock()

    /// Starts observing MetricKit diagnostic and metric report streams.
    ///
    /// Skips initialization when running under XCTest or when MetricKit's iOS 27 Swift API
    /// is unavailable on the current platform/version.
    static func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        #if canImport(MetricKit)
        if #available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *) {
            startLock.lock()
            defer { startLock.unlock() }
            guard !isStarted else { return }
            isStarted = true

            let manager = MetricKit.MetricManager()

            Task.detached(priority: .utility) {
                for await report in manager.diagnosticReports {
                    recordDiagnosticReport(report)
                }
            }

            Task.detached(priority: .utility) {
                for await report in manager.metricReports {
                    recordMetricReport(report)
                }
            }
        }
        #endif
    }

    // MARK: - Logging & Persistence

    #if canImport(MetricKit)
    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func recordDiagnosticReport(_ report: MetricKit.DiagnosticReport) {
        let line = diagnosticLogLine(for: report)
        Log.info(line, category: .pipeline)

        if let jsonString = compactJSON(report) {
            try? appendAndTrim(line: jsonString, fileURL: reportsFileURL())
        }
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func recordMetricReport(_ report: MetricKit.MetricReport) {
        logMetricReport(report)

        if let jsonString = compactJSON(report) {
            try? appendAndTrim(line: jsonString, fileURL: reportsFileURL())
        }
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func diagnosticLogLine(for report: MetricKit.DiagnosticReport) -> String {
        switch report.result {
        case .hang(let hang):
            let duration = hang.hangDuration.converted(to: .seconds).value
            let frames = extractTopFrames(from: hang.callStackTree)
            return formatDiagnosticLine(kind: "hang", duration: duration, frames: frames)

        case .cpuException(let cpu):
            let duration = cpu.totalCPUTime.converted(to: .seconds).value
            let frames = extractTopFrames(from: cpu.callStackTree)
            return formatDiagnosticLine(kind: "CPU exception", duration: duration, frames: frames)

        case .diskWriteException(let disk):
            let bytes = Int64(disk.totalBytesWritten.converted(to: .bytes).value)
            let frames = extractTopFrames(from: disk.callStackTree)
            return formatDiagnosticLine(kind: "disk write exception", byteCount: bytes, frames: frames)

        case .crash(let crash):
            let frames = extractTopFrames(from: crash.callStackTree)
            return formatDiagnosticLine(kind: "crash", frames: frames)

        case .appLaunch(let launch):
            let duration = launch.launchDuration.converted(to: .seconds).value
            let frames = extractTopFrames(from: launch.callStackTree)
            return formatDiagnosticLine(kind: "app launch", duration: duration, frames: frames)

        #if os(iOS) && !targetEnvironment(macCatalyst)
        case .memoryException(let memory):
            let frames = extractTopFrames(from: memory.callStackTree)
            return formatDiagnosticLine(kind: "memory", frames: frames)
        #endif

        @unknown default:
            return "[MetricKit] Diagnostic: unknown"
        }
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func logMetricReport(_ report: MetricKit.MetricReport) {
        var allResults: [MetricKit.MetricResult] = []
        for entry in report.intervalEntries {
            allResults.append(contentsOf: entry.values)
        }
        for entry in report.stateEntries {
            allResults.append(contentsOf: entry.values)
        }

        // 1. Launch time
        var loggedLaunchTime = false
        for result in allResults where !loggedLaunchTime {
            switch result {
            case .timeToFirstDraw(let m):
                if let d = duration(from: m.histogram) {
                    Log.info(formatLaunchTimeLine(duration: d), category: .pipeline)
                    loggedLaunchTime = true
                }
            case .optimizedTimeToFirstDraw(let m):
                if let d = duration(from: m.histogram) {
                    Log.info(formatLaunchTimeLine(duration: d), category: .pipeline)
                    loggedLaunchTime = true
                }
            case .extendedLaunch(let m):
                if let d = duration(from: m.histogram) {
                    Log.info(formatLaunchTimeLine(duration: d), category: .pipeline)
                    loggedLaunchTime = true
                }
            default:
                break
            }
        }

        // 2. Hang time
        var loggedHangTime = false
        for result in allResults where !loggedHangTime {
            if case .hangTime(let m) = result, let d = totalDuration(from: m.histogram) {
                Log.info(formatHangTimeLine(duration: d), category: .pipeline)
                loggedHangTime = true
            }
        }

        // 3. Hitch ratio
        var loggedHitchRatio = false
        for result in allResults where !loggedHitchRatio {
            if case .hitchTime(let m) = result {
                Log.info(formatHitchRatioLine(ratio: m.ratio.value), category: .pipeline)
                loggedHitchRatio = true
            }
        }

        // 4. Peak memory
        #if os(iOS) && !targetEnvironment(macCatalyst)
        var loggedPeakMemory = false
        for result in allResults where !loggedPeakMemory {
            if case .peakMemory(let m) = result {
                let bytes = Int64(m.value.converted(to: .bytes).value)
                Log.info(formatPeakMemoryLine(byteCount: bytes), category: .pipeline)
                loggedPeakMemory = true
            }
        }
        #endif

        // 5. Background terminations by cause
        var loggedBackgroundTerminations = false
        for result in allResults where !loggedBackgroundTerminations {
            if case .backgroundTermination(let m) = result {
                let causes: [(cause: String, count: Int)] = [
                    ("normal", m.normalTerminationCount),
                    ("memoryLimit", m.memoryLimitTerminationCount),
                    ("highCPU", m.highCPUTerminationCount),
                    ("systemPressure", m.systemPressureTerminationCount),
                    ("badAccess", m.badAccessTerminationCount),
                    ("abnormal", m.abnormalTerminationCount),
                    ("illegalInstruction", m.illegalInstructionTerminationCount),
                    ("watchdog", m.watchdogTerminationCount),
                    ("fileLock", m.fileLockTerminationCount),
                    ("taskTimeout", m.taskTimeoutTerminationCount)
                ]
                Log.info(formatBackgroundTerminationsLine(causes: causes), category: .pipeline)
                loggedBackgroundTerminations = true
            }
        }
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func extractTopFrames(from tree: MetricKit.CallStackTree, limit: Int = 3) -> [String] {
        guard let thread = tree.callStackThreads.first(where: { $0.threadAttributed == true }) ?? tree.callStackThreads.first else {
            return []
        }

        if thread.rootFrames.count > 1 && thread.rootFrames.allSatisfy({ $0.subFrames.isEmpty }) {
            return thread.rootFrames.prefix(limit).compactMap { frame in
                formatFrame(binary: frame.binaryName(from: tree), offset: frame.offsetIntoBinaryTextSegment)
            }
        }

        var path: [MetricKit.CallStackFrame] = []
        var current = thread.rootFrames.first
        while let frame = current {
            path.append(frame)
            current = frame.subFrames.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }) ?? frame.subFrames.first
        }

        let topFrames = path.reversed().prefix(limit)
        return topFrames.compactMap { frame in
            formatFrame(binary: frame.binaryName(from: tree), offset: frame.offsetIntoBinaryTextSegment)
        }
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func duration(from histogram: MetricKit.Histogram<UnitDuration>) -> TimeInterval? {
        var totalWeightedSeconds: Double = 0
        var totalCount: Int = 0
        for bucket in histogram.buckets {
            guard bucket.count > 0 else { continue }
            let lower = bucket.lowerBound.converted(to: .seconds).value
            let upper = bucket.upperBound.converted(to: .seconds).value
            let midpoint = (lower + upper) / 2.0
            totalWeightedSeconds += midpoint * Double(bucket.count)
            totalCount += bucket.count
        }
        guard totalCount > 0 else { return nil }
        return totalWeightedSeconds / Double(totalCount)
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func totalDuration(from histogram: MetricKit.Histogram<UnitDuration>) -> TimeInterval? {
        var totalSeconds: Double = 0
        var totalCount: Int = 0
        for bucket in histogram.buckets {
            guard bucket.count > 0 else { continue }
            let lower = bucket.lowerBound.converted(to: .seconds).value
            let upper = bucket.upperBound.converted(to: .seconds).value
            let midpoint = (lower + upper) / 2.0
            totalSeconds += midpoint * Double(bucket.count)
            totalCount += bucket.count
        }
        guard totalCount > 0 else { return nil }
        return totalSeconds
    }

    @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
    static func compactJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        guard var jsonString = String(data: data, encoding: .utf8) else { return nil }
        jsonString = jsonString.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return jsonString
    }
    #endif

    // MARK: - Pure Formatting Functions (Plain Values)

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }

    nonisolated static func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    nonisolated static func formatFrame(binary: String?, offset: UInt64?) -> String? {
        switch (binary, offset) {
        case let (b?, o?):
            return "\(b) + \(o)"
        case let (b?, nil):
            return b
        case let (nil, o?):
            return "+ \(o)"
        case (nil, nil):
            return nil
        }
    }

    nonisolated static func formatDiagnosticLine(
        kind: String,
        duration: TimeInterval? = nil,
        byteCount: Int64? = nil,
        frames: [String] = []
    ) -> String {
        var details: [String] = []
        if let duration {
            details.append("duration: \(formatDuration(duration))")
        }
        if let byteCount {
            details.append("size: \(formatByteCount(byteCount))")
        }
        if !frames.isEmpty {
            let topThree = frames.prefix(3).joined(separator: ", ")
            details.append("call stack: [\(topThree)]")
        }

        if details.isEmpty {
            return "[MetricKit] Diagnostic: \(kind)"
        } else {
            return "[MetricKit] Diagnostic: \(kind), \(details.joined(separator: ", "))"
        }
    }

    nonisolated static func formatLaunchTimeLine(duration: TimeInterval) -> String {
        "[MetricKit] Launch time: \(formatDuration(duration))"
    }

    nonisolated static func formatHangTimeLine(duration: TimeInterval) -> String {
        "[MetricKit] Hang time: \(formatDuration(duration))"
    }

    nonisolated static func formatHitchRatioLine(ratio: Double) -> String {
        "[MetricKit] Hitch ratio: \(String(format: "%.2f ms/s", ratio))"
    }

    nonisolated static func formatPeakMemoryLine(byteCount: Int64) -> String {
        "[MetricKit] Peak memory: \(formatByteCount(byteCount))"
    }

    nonisolated static func formatBackgroundTerminationsLine(causes: [(cause: String, count: Int)]) -> String {
        let nonZero = causes.filter { $0.count > 0 }
        if nonZero.isEmpty {
            return "[MetricKit] Background terminations: none"
        }
        let details = nonZero.map { "\($0.cause): \($0.count)" }.joined(separator: ", ")
        return "[MetricKit] Background terminations: \(details)"
    }

    // MARK: - File Management

    nonisolated static func reportsFileURL() -> URL {
        AppSupportPaths.localCacheDir().appendingPathComponent("metric_reports.jsonl")
    }

    nonisolated static func trimLines(_ lines: [String], maxLines: Int = 200) -> [String] {
        guard lines.count > maxLines else { return lines }
        return Array(lines.suffix(maxLines))
    }

    nonisolated static func appendAndTrim(
        line: String,
        fileURL: URL,
        maxLines: Int = 200
    ) throws {
        fileLock.lock()
        defer { fileLock.unlock() }

        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }

        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        var lines: [String] = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        lines.append(trimmedLine)
        lines = trimLines(lines, maxLines: maxLines)

        let output = lines.joined(separator: "\n") + "\n"
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
