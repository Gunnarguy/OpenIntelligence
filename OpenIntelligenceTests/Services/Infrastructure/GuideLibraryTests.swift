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
        // The guide library can't be deleted (5.8, 2026-11-18), so the test's one stops being the guide first and goes as
        // an own library.
        if let id = service.guideLibraryId {
            UserDefaults.standard.removeObject(forKey: ContainerService.guideLibraryIdKey)
            service.deleteContainer(id: id)
        }
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

    /// The guide library is permanent (5.8, 2026-11-18): the person can't delete it, even with own libraries beside it.
    func testTheGuideLibraryCannotBeDeleted() {
        XCTAssertFalse(ContainerService.mayDelete(listed: true, libraries: 3, isGuide: true, ownLibraries: 2))
        // An own library still may, while another own library stays.
        XCTAssertTrue(ContainerService.mayDelete(listed: true, libraries: 3, isGuide: false, ownLibraries: 2))
    }

    /// Where the guides go back in when something is missing (5.8, 2026-11-18).
    func testGuideRestoreTarget() {
        let guide = UUID()
        // All present: nothing to do, wherever they are.
        XCTAssertNil(SampleDocumentManager.guideRestoreTarget(guideLibrary: guide, guidesPresent: 3, guideCount: 3))
        XCTAssertNil(SampleDocumentManager.guideRestoreTarget(guideLibrary: nil, guidesPresent: 3, guideCount: 3))
        // The library is there and a guide is missing: back into it.
        XCTAssertEqual(
            SampleDocumentManager.guideRestoreTarget(guideLibrary: guide, guidesPresent: 2, guideCount: 3), .into(guide))
        // The library is gone and no guide is anywhere: a new guide library.
        XCTAssertEqual(
            SampleDocumentManager.guideRestoreTarget(guideLibrary: nil, guidesPresent: 0, guideCount: 3), .makeLibrary)
        // The library is gone but some guides sit in an own library from before 5.8: left as they are.
        XCTAssertNil(SampleDocumentManager.guideRestoreTarget(guideLibrary: nil, guidesPresent: 2, guideCount: 3))
    }

    /// "General" reads "Library 1" on every copy (5.8, 2026-11-18), once, and never over a library already called that.
    func testGeneralIsRenamedLibraryOne() {
        func library(_ name: String, _ description: String? = nil) -> KnowledgeContainer {
            KnowledgeContainer(
                name: name, icon: "folder.fill", colorHex: "#4F46E5", description: description, embeddingProviderId: "x",
                embeddingDim: 384)
        }
        let old = ContainerService.oldDefaultDescription
        let renamed = ContainerService.withFirstLibraryRenamed([library("General", old), library("Library 2")])
        XCTAssertEqual(renamed.map(\.name), ["Library 1", "Library 2"])
        XCTAssertEqual(renamed.first?.description, ContainerService.firstLibraryDescription)
        // Renamed back to General by the person afterwards, it stays General: the description no longer marks it.
        var renamedBack = renamed
        renamedBack[0].name = "General"
        XCTAssertEqual(ContainerService.withFirstLibraryRenamed(renamedBack).map(\.name), ["General", "Library 2"])
        // A library the person made and called General stays General.
        XCTAssertEqual(ContainerService.withFirstLibraryRenamed([library("General")]).map(\.name), ["General"])
        // Applying it again changes nothing, so a sync pass has nothing to write.
        XCTAssertEqual(ContainerService.withFirstLibraryRenamed(renamed).map(\.name), ["Library 1", "Library 2"])
        // A library already named Library 1 keeps the other's name as it is.
        XCTAssertEqual(
            ContainerService.withFirstLibraryRenamed([library("General", old), library("library 1")]).map(\.name),
            ["General", "library 1"])
        // A name the person chose stays.
        XCTAssertEqual(ContainerService.withFirstLibraryRenamed([library("Work")]).map(\.name), ["Work"])
    }
}
