//
//  LibraryFocusFilterTests.swift
//  OpenIntelligenceTests
//
//  A Focus filter limits the library pickers to the libraries it names (5.7).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class LibraryFocusFilterTests: XCTestCase {
    private let home = KnowledgeContainer(name: "Home")
    private let work = KnowledgeContainer(name: "Work")
    private let school = KnowledgeContainer(name: "School")
    private var all: [KnowledgeContainer] { [home, work, school] }

    func testNoFilterListsEveryLibrary() {
        XCTAssertEqual(ContainerService.pickable(all, allowed: nil, active: home.id).map(\.id), all.map(\.id))
    }

    func testFilterListsItsLibrariesInOrderAndKeepsTheOpenOne() {
        // The open library stays listed, so the picker never hides what is on screen.
        let shown = ContainerService.pickable(all, allowed: [school.id], active: home.id)
        XCTAssertEqual(shown.map(\.id), [home.id, school.id])
        XCTAssertEqual(ContainerService.pickable(all, allowed: [work.id], active: work.id).map(\.id), [work.id])
    }

    func testAFilterNamingNoLibraryThatExistsHidesNothing() {
        // A library deleted after the filter was set.
        XCTAssertEqual(ContainerService.pickable(all, allowed: [UUID()], active: home.id).map(\.id), all.map(\.id))
    }

    func testTheFilterTileNamesItsLibraries() {
        let intent = LibraryFocusFilterIntent()
        XCTAssertEqual(String(localized: intent.displayRepresentation.title), "All libraries")
        intent.libraries = [OILibraryEntityQuery.entity(for: work), OILibraryEntityQuery.entity(for: school)]
        XCTAssertEqual(String(localized: intent.displayRepresentation.title), "Work, School")
    }
}
