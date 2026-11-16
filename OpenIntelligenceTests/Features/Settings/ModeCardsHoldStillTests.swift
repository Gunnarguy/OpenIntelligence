//
//  ModeCardsHoldStillTests.swift
//  OpenIntelligenceTests
//
//  Switching Intelligence Mode or Compute Profile must not move anything on screen (the owner, 2026-11-16: "The UI jumps
//  around bc of word wrapping and shit, I don't want it to jump around"; before that, 2026-11-10). Each card is laid out
//  in every mode at an iPhone's width and at a narrower one, and its height must be the same in all of them.
//

import SwiftUI
import XCTest

@testable import OpenIntelligence

@MainActor
final class ModeCardsHoldStillTests: XCTestCase {
    private func height(of view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func modeCard(_ mode: RAGQualityMode) -> some View {
        IntelligenceModeCard(
            mode: mode, windowTokens: 4_096, windowDescription: "4,096 tokens", modelName: "AFM 3 Core",
            cloudWindow: "32,768 tokens", deepThinkTarget: 95, maximumLimit: nil, privateCloudComputeCompiledIn: true,
            callout: { step in
                switch step.canonical {
                case .deepThink:
                    return
                        "Searches up to 5 phrasings and can build the answer in a chain of sessions, for comparisons and questions that need several passages."
                case .maximum:
                    return
                        "After its strongest searches, up to 50 sessions over the passages found, stopping when its findings settle. Usually the slowest."
                default:
                    return
                        "Checks the answer against your documents, and searches more when the first search is thin. The fastest."
                }
            },
            onSelect: { _ in })
    }

    private func profileCard(_ profile: GPUExecutionProfile) -> some View {
        ComputeProfileCard(
            profile: .constant(profile), chipName: "A18 Pro", backgroundGPUProfiles: [.performance, .maximum],
            systemOffersBackgroundGPU: true, deviceNoun: "iPhone", backgroundNote: { _ in "In the background." },
            concurrencyFor: { step in
                let more = step == .efficiency ? 1 : 2
                return ComputeProfileCard.Concurrency(
                    visionParsingPages: more, ocrPages: more, renderSlots: more, embeddingParallel: more)
            },
            onSelect: { _ in })
    }

    func testIntelligenceModeCardKeepsOneHeightInEveryMode() {
        for width in [370.0, 320.0] {
            let heights = IntelligenceModeCard.modes.map { height(of: modeCard($0), width: width) }
            XCTAssertEqual(Set(heights.map { Int($0.rounded()) }).count, 1, "width \(width): heights \(heights)")
        }
    }

    func testComputeProfileCardKeepsOneHeightInEveryProfile() {
        for width in [370.0, 320.0] {
            let heights = GPUExecutionProfile.allCases.map { height(of: profileCard($0), width: width) }
            XCTAssertEqual(Set(heights.map { Int($0.rounded()) }).count, 1, "width \(width): heights \(heights)")
        }
    }
}
