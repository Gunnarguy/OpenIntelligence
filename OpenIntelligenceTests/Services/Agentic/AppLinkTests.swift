//
//  AppLinkTests.swift
//  OpenIntelligenceTests
//
//  One form of link for every surface. These pin that each destination's link reads back as the
//  same destination, that the three addresses 5.6 understood still mean what they did, and that a
//  Spotlight result names the item that was tapped.
//

import Combine
import XCTest

@testable import OpenIntelligenceEngine

final class AppLinkTests: XCTestCase {
    private let id = UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!

    func testEveryDestinationRoundTripsThroughItsLink() {
        let destinations: [AppDestination] = [
            .chat, .documents, .importQueue, .addDocument, .scanDocument,
            .newConversation(libraryId: nil), .newConversation(libraryId: id),
            .library(id), .document(id),
        ]
        for destination in destinations {
            let url = AppLink.url(for: destination)
            XCTAssertEqual(url.scheme, "openintelligence")
            XCTAssertEqual(AppLink.destination(for: url), destination, url.absoluteString)
        }
    }

    func testTheAddressesOlderBuildsUsedStillWork() {
        XCTAssertEqual(AppLink.destination(for: URL(string: "openintelligence://documents")!), .documents)
        XCTAssertEqual(AppLink.destination(for: URL(string: "openintelligence://documents/ingestion")!), .importQueue)
        XCTAssertEqual(AppLink.destination(for: URL(string: "openintelligence://chat")!), .chat)
        XCTAssertEqual(AppLink.url(for: .importQueue).absoluteString, "openintelligence://documents/ingestion")
    }

    func testFilesHandedOverHaveNoLinkOfTheirOwn() {
        let files = AppDestination.importFiles([URL(fileURLWithPath: "/tmp/Lease.pdf")])
        XCTAssertEqual(AppLink.destination(for: AppLink.url(for: files)), .documents)
    }

    func testOtherAddressesAreNotLinks() {
        XCTAssertNil(AppLink.destination(for: URL(string: "https://example.com/documents")!))
        XCTAssertNil(AppLink.destination(for: URL(string: "openintelligence://settings")!))
        XCTAssertNil(AppLink.destination(for: URL(string: "openintelligence://document/not-an-id")!))
        XCTAssertNil(AppLink.destination(for: URL(fileURLWithPath: "/tmp/Lease.pdf")))
    }

    func testASpotlightResultNamesItsItem() {
        XCTAssertEqual(AppLink.destination(forSpotlightIdentifier: "document-\(id.uuidString)"), .document(id))
        XCTAssertEqual(AppLink.destination(forSpotlightIdentifier: "container-\(id.uuidString)"), .library(id))
        XCTAssertNil(AppLink.destination(forSpotlightIdentifier: "chunk-\(id.uuidString)"), "a passage has no screen of its own")
        XCTAssertNil(AppLink.destination(forSpotlightIdentifier: "nonsense"))
    }

    @MainActor
    func testARequestIsTakenOnceAndOnlyByTheScreenThatShowsIt() {
        _ = AppNavigationRequest.shared.takeAll { _ in true }
        AppNavigationRequest.post(.addDocument)
        XCTAssertNil(AppNavigationRequest.shared.take { $0 == .scanDocument }, "the chat must not take the picker's request")
        XCTAssertEqual(AppNavigationRequest.shared.take { $0 == .addDocument }, .addDocument)
        XCTAssertNil(AppNavigationRequest.shared.take { $0 == .addDocument }, "a request is used up once taken")
    }

    /// Three files sent together arrive as three requests. Through the first version of this, the
    /// request held one slot and only the last file was imported.
    @MainActor
    func testSeveralFilesSentTogetherAllWait() {
        _ = AppNavigationRequest.shared.takeAll { _ in true }
        let files = ["a.pdf", "b.pdf", "c.pdf"].map { URL(fileURLWithPath: "/tmp/" + $0) }
        for file in files { AppNavigationRequest.post(.importFiles([file])) }
        AppNavigationRequest.post(.addDocument)

        let taken = AppNavigationRequest.shared.takeAll { destination in
            if case .importFiles = destination { return true }
            return false
        }
        XCTAssertEqual(taken, files.map { .importFiles([$0]) })
        XCTAssertEqual(AppNavigationRequest.shared.waiting, [.addDocument], "what another screen shows is left waiting")
        _ = AppNavigationRequest.shared.takeAll { _ in true }
    }

    /// A subscriber is handed the queue as it stands after the change, never the one before it.
    @MainActor
    func testASubscriberSeesTheQueueAfterTheChange() {
        _ = AppNavigationRequest.shared.takeAll { _ in true }
        var seen: [[AppDestination]] = []
        let subscription = AppNavigationRequest.shared.changes.sink { seen.append($0) }
        AppNavigationRequest.post(.chat)
        _ = AppNavigationRequest.shared.take { $0 == .chat }
        subscription.cancel()
        XCTAssertEqual(seen, [[], [.chat], []])
    }
}
