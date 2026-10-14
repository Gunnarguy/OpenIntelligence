//
//  AppActivityTests.swift
//  OpenIntelligenceTests
//
//  Handoff (5.7). Through 5.6 the chat and the Documents screen advertised activities that no
//  device could continue: the types were not declared and nothing received them. These pin the
//  declared types, what an activity carries, and where each continued activity lands, including one
//  from a device still on 5.6, which sends its library as a UUID.
//

import XCTest

@testable import OpenIntelligenceEngine

final class AppActivityTests: XCTestCase {
    private let library = UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!
    private let document = UUID(uuidString: "1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F809")!

    func testWhatAnActivityCarriesIsAPropertyList() throws {
        let info = AppActivity.userInfo(library: library, document: document)
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0))
        XCTAssertEqual(info[AppActivity.libraryKey] as? String, library.uuidString)
        XCTAssertEqual(info[AppActivity.documentKey] as? String, document.uuidString)
        XCTAssertTrue(AppActivity.userInfo(library: nil).isEmpty)
    }

    func testAnActivityFromADeviceStillOn56LandsInItsLibrary() {
        // 5.6 wrote the library as a UUID, which NSUserActivity allows.
        XCTAssertEqual(
            AppActivity.destinations(type: AppActivity.chat, userInfo: [AppActivity.libraryKey: library]),
            [.library(library), .chat])
    }

    func testEachActivityLandsWhereItWasLeft() {
        let withLibrary = AppActivity.userInfo(library: library)
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.chat, userInfo: withLibrary), [.library(library), .chat])
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.chat, userInfo: nil), [.chat])
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.documents, userInfo: withLibrary), [.library(library)])
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.documents, userInfo: [:]), [.documents])
        XCTAssertEqual(
            AppActivity.destinations(
                type: AppActivity.viewingDocument, userInfo: AppActivity.userInfo(library: nil, document: document)),
            [.document(document)])
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.viewingDocument, userInfo: nil), [.documents])
        XCTAssertEqual(AppActivity.destinations(type: "com.example.other", userInfo: withLibrary), [])
        // A value of the wrong kind is ignored rather than trusted.
        XCTAssertEqual(AppActivity.destinations(type: AppActivity.documents, userInfo: [AppActivity.libraryKey: 42]), [.documents])
    }

    /// Another device offers an activity only when the receiving app declares its type. The test
    /// host is the app, so this reads the Info.plist that was built into it.
    func testEveryTypeIsDeclaredInInfoPlist() throws {
        let declared = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])
        XCTAssertEqual(Set(declared), Set(AppActivity.all))
    }
}
