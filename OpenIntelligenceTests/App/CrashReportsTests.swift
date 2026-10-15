//
//  CrashReportsTests.swift
//  OpenIntelligenceTests
//
//  Crash reports the person can send (5.7): a report is saved as a file of its own, offered once
//  however many windows ask, a crash delivered twice is kept once, the newest ten are kept, and the
//  email goes to the given address with the report's summary in it.
//  Not covered: MetricKit handing the app a crash diagnostic, which happens only on a device at the
//  launch after a crash.
//

import XCTest

@testable import OpenIntelligence

final class CrashReportsTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashReportsTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "CrashReportsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testASavedReportIsOfferedOnceWithItsSummary() throws {
        let report = try CrashReports.save(
            ["summary": "OpenIntelligence 5.7 (486) on iOS 27.0.", "app": "OpenIntelligence 5.7 (486)"],
            endedAt: Date(timeIntervalSince1970: 1_790_000_000), in: folder, defaults: defaults)

        XCTAssertEqual(CrashReports.pending(in: folder, defaults: defaults), report)
        XCTAssertEqual(CrashReports.summary(of: report), "OpenIntelligence 5.7 (486) on iOS 27.0.")
        CrashReports.markOffered(defaults: defaults)
        XCTAssertNil(CrashReports.pending(in: folder, defaults: defaults), "a report is offered once")
        XCTAssertEqual(CrashReports.all(in: folder), [report], "an offered report stays in Settings, About")
    }

    func testTheSameCrashDeliveredTwiceIsKeptAndOfferedOnce() throws {
        let fields: [String: Any] = ["summary": "It ended with: badAccess, signal 11.", "app": "OpenIntelligence 5.7 (486)"]
        let first = try CrashReports.save(
            fields, endedAt: Date(timeIntervalSince1970: 1_790_000_000), in: folder, defaults: defaults)
        XCTAssertEqual(CrashReports.takePending(in: folder, defaults: defaults), first)
        XCTAssertNil(CrashReports.takePending(in: folder, defaults: defaults), "a second window gets nothing")

        let again = try CrashReports.save(
            fields, endedAt: Date(timeIntervalSince1970: 1_790_000_000), in: folder, defaults: defaults)
        XCTAssertEqual(again, first)
        XCTAssertEqual(CrashReports.all(in: folder).count, 1)
        XCTAssertNil(CrashReports.pending(in: folder, defaults: defaults), "the same crash is not offered again")
    }

    func testOnlyTheNewestTenAreKept() throws {
        var saved: [URL] = []
        for minute in 0..<12 {
            saved.append(
                try CrashReports.save(
                    ["summary": "report \(minute)"], endedAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60),
                    in: folder, defaults: defaults))
        }
        let kept = CrashReports.all(in: folder)
        XCTAssertEqual(kept.count, 10)
        XCTAssertEqual(kept.first, saved.last, "newest first")
        XCTAssertFalse(kept.contains(saved[0]))
        XCTAssertFalse(kept.contains(saved[1]))
        XCTAssertEqual(CrashReports.pending(in: folder, defaults: defaults), saved.last)
    }

    func testTheEmailGoesToTheGivenAddressWithTheSummary() throws {
        let report = try CrashReports.save(
            ["summary": "It ended with: badAccess, signal 11."], endedAt: Date(timeIntervalSince1970: 1_790_000_000),
            in: folder, defaults: defaults)
        let mail = CrashReports.mailURL(for: report, to: "support@example.com")
        let components = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "support@example.com")
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasPrefix("It ended with: badAccess, signal 11."), body)
        let subject = try XCTUnwrap(components.queryItems?.first { $0.name == "subject" }?.value)
        XCTAssertTrue(subject.contains(report.deletingPathExtension().lastPathComponent), subject)
    }
}
