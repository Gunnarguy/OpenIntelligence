//
//  DeletedLibraryTests.swift
//  OpenIntelligenceTests
//
//  A deleted library stays deleted (5.7). Two windows on the Mac each hold their own library list,
//  and the one that did not do the delete wrote the library back with its next save; a reload right
//  after a delete could also read the list from before it. `ContainerService` now keeps the ids of
//  deleted libraries and waits for queued writes before it reads. These tests use two
//  `ContainerService` objects for two windows, in the app the suite runs in, on a paid plan for the
//  length of the test (the free plan allows one library). Not covered: two devices.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class DeletedLibraryTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    func testALibraryDeletedInOneWindowIsNotWrittenBackByAnother() throws {
        let deleting = ContainerService()
        let library = try deleting.createContainer(name: "Deleted library test \(UUID().uuidString.prefix(8))")
        let otherWindow = ContainerService()
        XCTAssertTrue(otherWindow.containers.contains { $0.id == library.id }, "the other window read the list with it")

        deleting.deleteContainer(id: library.id)
        // The other window still holds the library, and saves its list.
        let kept = try XCTUnwrap(otherWindow.containers.first { $0.id != library.id })
        otherWindow.updateContainer(kept)

        XCTAssertFalse(ContainerService().containers.contains { $0.id == library.id })
        XCTAssertTrue(ContainerService.deletedContainerIds().contains(library.id))
    }

    func testAReloadRightAfterADeleteDoesNotBringItBack() throws {
        let libraries = ContainerService()
        let library = try libraries.createContainer(name: "Reload test \(UUID().uuidString.prefix(8))")
        libraries.deleteContainer(id: library.id)
        libraries.reloadFromDisk()
        XCTAssertFalse(libraries.containers.contains { $0.id == library.id })
    }
}
