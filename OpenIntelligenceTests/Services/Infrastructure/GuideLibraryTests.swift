//
//  GuideLibraryTests.swift
//  OpenIntelligenceTests
//
//  The guide library (5.8): the app's guides in a library of their own, outside both of the plan's limits, and the
//  person's own files kept out of it.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class GuideLibraryTests: XCTestCase {
    private var service: ContainerService!
    private var savedGuideId: String?

    override func setUp() async throws {
        savedGuideId = UserDefaults.standard.string(forKey: ContainerService.guideLibraryIdKey)
        UserDefaults.standard.removeObject(forKey: ContainerService.guideLibraryIdKey)
        service = ContainerService()
    }

    override func tearDown() async throws {
        if let id = service.guideLibraryId { service.deleteContainer(id: id) }
        if let savedGuideId {
            UserDefaults.standard.set(savedGuideId, forKey: ContainerService.guideLibraryIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ContainerService.guideLibraryIdKey)
        }
    }

    func testTheGuideLibraryIsMadeOnceAndDoesNotCountAsALibrary() {
        let before = service.countedLibraryCount
        let guide = service.ensureGuideLibrary()
        XCTAssertEqual(service.ensureGuideLibrary(), guide)
        XCTAssertTrue(service.isGuideLibrary(guide))
        XCTAssertEqual(service.countedLibraryCount, before)
        XCTAssertEqual(service.containers.filter { $0.id == guide }.first?.syncMode, .localOnly)
    }

    func testOwnFilesAddedInTheGuideLibraryGoToTheFirstOwnLibrary() {
        let guide = service.ensureGuideLibrary()
        let own = service.containers.first { $0.id != guide }?.id
        XCTAssertNotNil(own)
        XCTAssertEqual(service.libraryForOwnFiles(requested: guide), own)
        XCTAssertEqual(service.libraryForOwnFiles(requested: own), own)
    }

    /// Synced, another device would count it as an ordinary library and hold a second copy of the guides.
    func testTheGuideLibraryStaysOnTheDevice() {
        let guide = service.ensureGuideLibrary()
        guard var library = service.containers.first(where: { $0.id == guide }) else { return XCTFail("no guide library") }
        library.syncMode = .iCloudShared
        service.updateContainer(library)
        XCTAssertEqual(service.containers.first { $0.id == guide }?.syncMode, .localOnly)
    }

    /// The person's last own library can't be deleted while only the guide library would be left.
    func testTheLastOwnLibraryStays() {
        _ = service.ensureGuideLibrary()
        guard service.countedLibraryCount == 1, let own = service.containers.first(where: { !service.isGuideLibrary($0.id) })
        else { return }
        service.deleteContainer(id: own.id)
        XCTAssertTrue(service.containers.contains { $0.id == own.id })
    }
}
