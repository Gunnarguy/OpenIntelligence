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

import XCTest

#if canImport(FoundationModels)
    import FoundationModels
#endif

final class ModelEnvironmentProbeTests: XCTestCase {
    func testReportWhetherApplesModelCanAnswerHere() async throws {
        #if canImport(FoundationModels)
            let environment = ProcessInfo.processInfo.environment
            let place =
                environment["CI_XCODE_CLOUD"] != nil || environment["CI"] != nil
                ? "xcode-cloud" : (environment["SIMULATOR_MODEL_IDENTIFIER"] != nil ? "simulator" : "device-or-mac")
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
            var line = "[ModelProbe] place=\(place) model=\(environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "-") "
                + "availability=\(availability) waited=\(Int(Date().timeIntervalSince(waitStarted)))s"
            if case .available = availability {
                let started = Date()
                do {
                    let session = LanguageModelSession()
                    let reply = try await session.respond(to: "Reply with the single word OK.")
                    line += " respond=ok seconds=\(Int(Date().timeIntervalSince(started))) text=\(reply.content.prefix(20))"
                } catch {
                    line += " respond=error seconds=\(Int(Date().timeIntervalSince(started))) error=\(error)"
                }
            }
            print(line)
            let attachment = XCTAttachment(string: line)
            attachment.name = "ModelProbe"
            attachment.lifetime = .keepAlways
            add(attachment)
        #else
            print("[ModelProbe] FoundationModels not in this SDK")
        #endif
    }
}
