//
//  ModelEnvironmentProbeTests.swift
//  OpenIntelligenceTests
//
//  Where can Apple's on-device model answer? (2026-11-11.) The owner asked which places can run answer benchmarks:
//  this Mac's Simulator, Xcode Cloud, his iPhone. An Xcode Cloud run on 2026-11-08 (#495) failed a question test with
//  `ModelManagerError error 1019`, which suggests the model is absent there but does not say why. This probe records the
//  model's own availability and, when it says available, asks for one short answer, and always passes: it reports, it
//  does not judge. Read its line ("[ModelProbe]") in the run's log or result bundle.
//
//  Version 2 (2026-11-25; the owner asked whether 1019 only reflects how v1 tried). v1 called respond() once and stopped
//  at the first error, where on this Mac's Simulator the model answers only after about a minute of failures. v2 warms
//  the session and retries every 15 s for up to 9 minutes, logging every attempt with its elapsed time and the whole
//  error (domain, code, userInfo, underlying errors), since 1019 is undocumented; and it probes the Private Cloud Compute
//  model on its own line ("[ModelProbe-PCC]"), a different model that tells what the place can reach, not a stand-in
//  for the on-device one.
//

import XCTest

#if canImport(FoundationModels)
    import FoundationModels
#endif

final class ModelEnvironmentProbeTests: XCTestCase {
    /// The whole error, including the chain of underlying errors, as one line.
    static func describe(_ error: Error) -> String {
        var parts: [String] = []
        var current: NSError? = error as NSError
        var depth = 0
        while let ns = current, depth < 5 {
            let info = ns.userInfo.filter { $0.key != NSUnderlyingErrorKey }.map { "\($0.key)=\($0.value)" }.sorted()
            parts.append("[\(depth)] domain=\(ns.domain) code=\(ns.code) info={\(info.joined(separator: "; "))}")
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return "\(String(reflecting: error)) | " + parts.joined(separator: " <- ")
    }

    private func report(_ line: String, name: String) {
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReportWhetherApplesModelCanAnswerHere() async throws {
        #if canImport(FoundationModels)
            let environment = ProcessInfo.processInfo.environment
            let place =
                environment["CI_XCODE_CLOUD"] != nil || environment["CI"] != nil
                ? "xcode-cloud" : (environment["SIMULATOR_MODEL_IDENTIFIER"] != nil ? "simulator" : "device-or-mac")
            let model = environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "-"
            // A freshly booted Simulator reports modelNotReady for about a minute before the model answers (measured on
            // this Mac, 2026-10), so wait up to three minutes before reporting.
            let waitStarted = Date()
            var availability = SystemLanguageModel.default.availability
            while Date().timeIntervalSince(waitStarted) < 180 {
                if case .available = availability { break }
                if case .unavailable(.deviceNotEligible) = availability { break }
                try await Task.sleep(for: .seconds(5))
                availability = SystemLanguageModel.default.availability
            }
            report(
                "[ModelProbe] place=\(place) model=\(model) version=2 availability=\(availability) "
                    + "waited=\(Int(Date().timeIntervalSince(waitStarted)))s",
                name: "ModelProbe")
            // Ask whatever the flag says: v1 found the flag `available` while every answer failed.
            let started = Date()
            var attempt = 0
            var answered = false
            while !answered && Date().timeIntervalSince(started) < 540 {
                attempt += 1
                let session = LanguageModelSession()
                session.prewarm()
                let t0 = Date()
                do {
                    let reply = try await session.respond(to: "Reply with the single word OK.")
                    answered = true
                    report(
                        "[ModelProbe] attempt=\(attempt) elapsed=\(Int(Date().timeIntervalSince(started)))s respond=ok "
                            + "seconds=\(Int(Date().timeIntervalSince(t0))) text=\(reply.content.prefix(20)) "
                            + "availability=\(SystemLanguageModel.default.availability)",
                        name: "ModelProbe attempt \(attempt)")
                } catch {
                    report(
                        "[ModelProbe] attempt=\(attempt) elapsed=\(Int(Date().timeIntervalSince(started)))s respond=error "
                            + "availability=\(SystemLanguageModel.default.availability) error=\(Self.describe(error))",
                        name: "ModelProbe attempt \(attempt)")
                    try await Task.sleep(for: .seconds(15))
                }
            }
            report(
                "[ModelProbe] summary place=\(place) model=\(model) attempts=\(attempt) answered=\(answered) "
                    + "seconds=\(Int(Date().timeIntervalSince(started)))",
                name: "ModelProbe summary")

            #if compiler(>=6.4)
                if #available(iOS 27.0, macOS 27.0, *) {
                    let pcc = FoundationModels.PrivateCloudComputeLanguageModel()
                    var line =
                        "[ModelProbe-PCC] place=\(place) model=\(model) isAvailable=\(pcc.isAvailable) "
                        + "quotaLimitReached=\(pcc.quotaUsage.isLimitReached)"
                    if pcc.isAvailable {
                        for pccAttempt in 1...3 {
                            let t0 = Date()
                            do {
                                let reply = try await LanguageModelSession(model: pcc).respond(
                                    to: "Reply with the single word OK.")
                                line +=
                                    " attempt\(pccAttempt)=ok seconds=\(Int(Date().timeIntervalSince(t0))) "
                                    + "text=\(reply.content.prefix(20))"
                                break
                            } catch {
                                line += " attempt\(pccAttempt)=error \(Self.describe(error))"
                                try await Task.sleep(for: .seconds(15))
                            }
                        }
                    }
                    report(line, name: "ModelProbe-PCC")
                } else {
                    report("[ModelProbe-PCC] place=\(place) not on iOS or macOS 27", name: "ModelProbe-PCC")
                }
            #endif
        #else
            print("[ModelProbe] FoundationModels not in this SDK")
        #endif
    }
}
