//
//  CloudConsentRelayTests.swift
//  OpenIntelligenceTests
//
//  A Private Cloud Compute consent request from an engine the chat does not show, such as the one an
//  action builds for its question, reaches the app's root view through `CloudConsentRelay` (5.7).
//  Through the first 5.7 builds such a request waited on a sheet that nothing showed, so a question
//  from Siri or Shortcuts asked while the app was in front waited for good. These tests hold the
//  relay's rules (one window shows a request, a request nobody sees is given up, a newer one replaces
//  an older one, a sheet on screen is never taken away) and the engine's side: an action's engine asks
//  through the relay and the chat's own engine does not, and a request given up is not remembered as
//  Don't Allow. A refuting review on 2026-10-14 found that no window could claim a request, because
//  `@Published` announces a value before storing it and the claim read the stored one; the first test
//  claims from inside the announcement, as `ContentView` does. Not covered: an action bringing the app
//  forward, which needs the system's context and a device where Private Cloud Compute runs.
//

import Combine
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

    func testAWindowCanClaimARequestFromInsideItsAnnouncement() {
        let relay = CloudConsentRelay()
        let window = UUID()
        var claimed = false
        let subscription = relay.$request.dropFirst().sink { request in
            if let request { claimed = relay.claim(request.id, for: window) }
        }
        relay.post(Self.record(), resolve: { _ in }, abandon: {})
        XCTAssertTrue(claimed, "the window is told before the value is stored, and has to be able to claim it then")
        subscription.cancel()
    }

    func testASheetOnScreenIsNotTakenAwayByANewerRequest() {
        let relay = CloudConsentRelay()
        let first = Self.record()
        var abandonedFirst = 0
        var abandonedSecond = 0
        relay.post(first, resolve: { _ in }, abandon: { abandonedFirst += 1 })
        XCTAssertTrue(relay.claim(first.id, for: UUID()))
        relay.markShown(first.id)

        relay.post(Self.record(), resolve: { _ in }, abandon: { abandonedSecond += 1 })
        XCTAssertEqual(abandonedFirst, 0, "the person is answering the first one")
        XCTAssertEqual(abandonedSecond, 1, "the second goes on without Private Cloud Compute")
        XCTAssertEqual(relay.request?.id, first.id)
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

    /// An engine with no stored decision, put back as it was afterwards. `throughRelay` makes it an
    /// action's engine, as `AskActionRunner.ask` does.
    private func engineThatHasNotBeenAsked(throughRelay: Bool = true) throws -> RAGService {
        let engine = RAGService()
        engine.asksThroughRelay = throughRelay
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

    func testTheChatsOwnEngineDoesNotAskThroughTheRelay() async throws {
        let engine = try engineThatHasNotBeenAsked(throughRelay: false)
        let record = Self.record()
        let asking = Task { await engine.cloudConsentDecision(for: .applePCC, record: record) }
        for _ in 0..<100 where engine.pendingCloudConsent?.id != record.id {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.pendingCloudConsent?.id, record.id, "the chat's sheet shows this")
        XCTAssertNotEqual(CloudConsentRelay.shared.request?.id, record.id, "and the relay does not, too")
        await engine.resolveCloudConsent(decision: .allowOnce)
        let decision = await asking.value
        XCTAssertEqual(decision, .allowOnce)
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
