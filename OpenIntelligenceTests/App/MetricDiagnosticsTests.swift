//
//  MetricDiagnosticsTests.swift
//  OpenIntelligenceTests
//
//  Tests for MetricDiagnostics pure formatting helpers and log trimming logic.
//

import XCTest
@testable import OpenIntelligence

final class MetricDiagnosticsTests: XCTestCase {

    func testFormatDuration() {
        XCTAssertEqual(MetricDiagnostics.formatDuration(0.0), "0.00s")
        XCTAssertEqual(MetricDiagnostics.formatDuration(1.25), "1.25s")
        XCTAssertEqual(MetricDiagnostics.formatDuration(15.5), "15.50s")
    }

    func testFormatByteCount() {
        let formattedZero = MetricDiagnostics.formatByteCount(0)
        XCTAssertTrue(formattedZero.contains("Zero") || formattedZero.contains("0"))

        let formattedMega = MetricDiagnostics.formatByteCount(10_485_760)
        XCTAssertTrue(formattedMega.contains("MB") || formattedMega.contains("10"))
    }

    func testFormatFrame() {
        XCTAssertEqual(
            MetricDiagnostics.formatFrame(binary: "OpenIntelligence", offset: 1024),
            "OpenIntelligence + 1024"
        )
        XCTAssertEqual(
            MetricDiagnostics.formatFrame(binary: "libsystem_kernel.dylib", offset: nil),
            "libsystem_kernel.dylib"
        )
        XCTAssertEqual(
            MetricDiagnostics.formatFrame(binary: nil, offset: 4096),
            "+ 4096"
        )
        XCTAssertNil(MetricDiagnostics.formatFrame(binary: nil, offset: nil))
    }

    func testFormatDiagnosticLine_hang() {
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "hang",
            duration: 2.5,
            frames: ["OpenIntelligence + 104", "libsystem.dylib + 208"]
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("hang"))
        XCTAssertTrue(line.contains("2.50s"))
        XCTAssertTrue(line.contains("OpenIntelligence + 104"))
        XCTAssertTrue(line.contains("libsystem.dylib + 208"))
    }

    func testFormatDiagnosticLine_cpuException() {
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "CPU exception",
            duration: 12.34,
            frames: ["OpenIntelligence + 55"]
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("CPU exception"))
        XCTAssertTrue(line.contains("12.34s"))
        XCTAssertTrue(line.contains("OpenIntelligence + 55"))
    }

    func testFormatDiagnosticLine_diskWriteException() {
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "disk write exception",
            byteCount: 10_485_760,
            frames: ["OpenIntelligence + 12"]
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("disk write exception"))
        XCTAssertTrue(line.contains("size:"))
        XCTAssertTrue(line.contains("OpenIntelligence + 12"))
    }

    func testFormatDiagnosticLine_crash() {
        let frames = ["Frame0 + 0", "Frame1 + 1", "Frame2 + 2", "Frame3 + 3"]
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "crash",
            frames: frames
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("crash"))
        XCTAssertTrue(line.contains("Frame0 + 0"))
        XCTAssertTrue(line.contains("Frame1 + 1"))
        XCTAssertTrue(line.contains("Frame2 + 2"))
        XCTAssertFalse(line.contains("Frame3 + 3"), "Diagnostic line should only show the top three frames")
    }

    func testFormatDiagnosticLine_appLaunch() {
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "app launch",
            duration: 0.85,
            frames: ["OpenIntelligence + 1"]
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("app launch"))
        XCTAssertTrue(line.contains("0.85s"))
    }

    func testFormatDiagnosticLine_memory() {
        let line = MetricDiagnostics.formatDiagnosticLine(
            kind: "memory",
            frames: ["OpenIntelligence + 100"]
        )
        XCTAssertTrue(line.hasPrefix("[MetricKit]"))
        XCTAssertTrue(line.contains("memory"))
        XCTAssertTrue(line.contains("OpenIntelligence + 100"))
    }

    func testFormatLaunchTimeLine() {
        let line = MetricDiagnostics.formatLaunchTimeLine(duration: 1.2)
        XCTAssertEqual(line, "[MetricKit] Launch time: 1.20s")
    }

    func testFormatHangTimeLine() {
        let line = MetricDiagnostics.formatHangTimeLine(duration: 0.45)
        XCTAssertEqual(line, "[MetricKit] Hang time: 0.45s")
    }

    func testFormatHitchRatioLine() {
        let line = MetricDiagnostics.formatHitchRatioLine(ratio: 4.56)
        XCTAssertEqual(line, "[MetricKit] Hitch ratio: 4.56 ms/s")
    }

    func testFormatPeakMemoryLine() {
        let line = MetricDiagnostics.formatPeakMemoryLine(byteCount: 50_000_000)
        XCTAssertTrue(line.hasPrefix("[MetricKit] Peak memory:"))
    }

    func testFormatBackgroundTerminationsLine_withCauses() {
        let causes = [
            ("normal", 0),
            ("memoryLimit", 2),
            ("highCPU", 1),
            ("watchdog", 0)
        ]
        let line = MetricDiagnostics.formatBackgroundTerminationsLine(causes: causes)
        XCTAssertEqual(line, "[MetricKit] Background terminations: memoryLimit: 2, highCPU: 1")
    }

    func testFormatBackgroundTerminationsLine_allZero() {
        let causes = [
            ("normal", 0),
            ("memoryLimit", 0)
        ]
        let line = MetricDiagnostics.formatBackgroundTerminationsLine(causes: causes)
        XCTAssertEqual(line, "[MetricKit] Background terminations: none")
    }

    func testTrimLines() {
        let lines = (1...250).map { "Line \($0)" }
        let trimmed = MetricDiagnostics.trimLines(lines, maxLines: 200)
        XCTAssertEqual(trimmed.count, 200)
        XCTAssertEqual(trimmed.first, "Line 51")
        XCTAssertEqual(trimmed.last, "Line 250")

        let shortLines = ["Line 1", "Line 2"]
        XCTAssertEqual(MetricDiagnostics.trimLines(shortLines, maxLines: 200), shortLines)
    }

    func testAppendAndTrimTemporaryFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let testFileURL = tempDirectory.appendingPathComponent("metric_reports_test_\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: testFileURL)
        }

        for i in 1...250 {
            let json = "{\"report_index\": \(i)}"
            try MetricDiagnostics.appendAndTrim(line: json, fileURL: testFileURL, maxLines: 200)
        }

        let content = try String(contentsOf: testFileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(lines.first, "{\"report_index\": 51}")
        XCTAssertEqual(lines.last, "{\"report_index\": 250}")
    }
}
