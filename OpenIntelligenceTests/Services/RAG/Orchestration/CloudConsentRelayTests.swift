//
//  CloudConsentRelayTests.swift
//  OpenIntelligenceTests
//
//  A Private Cloud Compute consent request from an engine the chat does not show, such as the one an
//  action builds for its question, reaches the app's root view through `CloudConsentRelay` (5.7).
//  Through the first 5.7 builds such a request waited on a sheet that nothing showed, so a question
//  from Siri or Shortcuts asked while the app was in front waited for good. These tests hold the
//  relay's rules (one window shows a request, a request nobody sees is given up, a newer one replaces
//  an older one) and the engine's side: a request goes through the relay, and one given up is not
//  remembered as Don't Allow. Not covered: an action bringing the app forward, which needs the
//  system's context and a device where Private Cloud Compute runs.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class CloudConsentRelayTests: XCTestCase {
    private static func record() -> CloudTransmissionRecord {
        CloudTransmissionRecord(
            provider: .applePCC,
            modelName: "Apple Private Cloud Compute",
            promptPreview: "How much is the deposit?",
            promptCharacterCount: 24,
            contextChunkCount: 2,
            contextHashes: [],
            estimatedBytes: 2_000)
    }

    func testARequestNoWindowShowsIsGivenUpAfterTheDeadline() async throws {
        let relay = CloudConsentRelay()
        relay.deadline = .milliseconds(50)
        var abandoned = 0
        var decided: CloudConsentDecision?
        relay.post(Self.record(), resolve: { decided = $0 }, abandon: { abandoned += 1 })

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(abandoned, 1)
        XCTAssertNil(decided)
        XCTAssertNil(relay.request)
    }

    func testOneWindowShowsTheRequestAndItWaitsForThePerson() async throws {
        let relay = CloudConsentRelay()
        relay.deadline = .milliseconds(50)
        var abandoned = 0
        var decided: CloudConsentDecision?
        let record = Self.record()
        relay.post(record, resolve: { decided = $0 }, abandon: { abandoned += 1 })

        let first = UUID()
        XCTAssertTrue(relay.claim(record.id, for: first))
        XCTAssertFalse(relay.claim(record.id, for: UUID()), "a second window would show it twice")
        XCTAssertTrue(relay.claim(record.id, for: first))
        relay.markShown(record.id)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(abandoned, 0, "a sheet on screen waits for the person")
        await relay.decide(record.id, .allowOnce)
        XCTAssertEqual(decided, .allowOnce)
        XCTAssertNil(relay.request)
    }

    func testANewRequestGivesUpTheOneBeforeIt() {
        let relay = CloudConsentRelay()
        var abandonedFirst = 0
        relay.post(Self.record(), resolve: { _ in }, abandon: { abandonedFirst += 1 })
        let second = Self.record()
        relay.post(second, resolve: { _ in }, abandon: {})

        XCTAssertEqual(abandonedFirst, 1)
        XCTAssertEqual(relay.request?.id, second.id)
    }

    /// An engine with no stored decision, put back as it was afterwards.
    private func engineThatHasNotBeenAsked() throws -> RAGService {
        let engine = RAGService()
        guard RAGService.activePresentedInstance !== engine else {
            throw XCTSkip("the test's engine is the one the chat shows in this host")
        }
        let before = engine.cloudConsent[.applePCC] ?? .notDetermined
        engine.setCloudConsentState(.notDetermined, for: .applePCC)
        addTeardownBlock { @MainActor in engine.setCloudConsentState(before, for: .applePCC) }
        return engine
    }

    func testAnEngineTheChatDoesNotShowAsksThroughTheRelay() async throws {
        let engine = try engineThatHasNotBeenAsked()
        let record = Self.record()
        let asking = Task { await engine.cloudConsentDecision(for: .applePCC, record: record) }

        let relay = CloudConsentRelay.shared
        for _ in 0..<100 where relay.request?.id != record.id {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(relay.request?.id, record.id, "the request did not reach the relay")
        await relay.decide(record.id, .allowOnce)

        let decision = await asking.value
        XCTAssertEqual(decision, .allowOnce)
        XCTAssertNil(engine.pendingCloudConsent)
        XCTAssertEqual(engine.cloudConsent[.applePCC] ?? .notDetermined, .notDetermined, "Allow Once is not remembered")
    }

    func testARequestGivenUpIsNotRememberedAsDontAllow() async throws {
        let engine = try engineThatHasNotBeenAsked()
        let record = Self.record()
        let asking = Task { await engine.cloudConsentDecision(for: .applePCC, record: record) }
        for _ in 0..<100 where engine.pendingCloudConsent?.id != record.id {
            try await Task.sleep(for: .milliseconds(20))
        }

        engine.abandonCloudConsentRequest(record.id)
        let decision = await asking.value
        XCTAssertEqual(decision, .deny, "the question goes on without Private Cloud Compute")
        XCTAssertEqual(
            engine.cloudConsent[.applePCC] ?? .notDetermined, .notDetermined,
            "a sheet nobody saw is not remembered as Don't Allow")
        XCTAssertNotEqual(CloudConsentRelay.shared.request?.id, record.id, "the relay still holds it")
    }
}
