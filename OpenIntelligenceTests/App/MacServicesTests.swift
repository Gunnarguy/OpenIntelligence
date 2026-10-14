//
//  MacServicesTests.swift
//  OpenIntelligenceTests
//
//  The Mac's Services menu (5.7). One Info.plist serves both platforms, but the iPhone build leaves
//  `NSServices` out of the Info.plist it builds, so the declarations are read from the source file;
//  the methods they name exist only in the Mac build.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class MacServicesTests: XCTestCase {
    /// The repository's Info.plist, read where the tests were built from. Skipped where that copy
    /// is not reachable (a run on a device).
    private func sourceInfoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Info.plist is not reachable here")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: 0, format: nil) as? [String: Any])
    }

    private func services() throws -> [[String: Any]] {
        try XCTUnwrap(sourceInfoPlist()["NSServices"] as? [[String: Any]])
    }

    func testThreeServicesAreDeclaredAndShownWithoutBeingSwitchedOn() throws {
        let services = try services()
        let messages = services.compactMap { $0["NSMessage"] as? String }
        XCTAssertEqual(messages, ["askAboutSelection", "addSelectionToLibrary", "addFilesToLibrary"])
        for service in services {
            // Without NSRequiredContext the system registers a service but leaves it out of the menu.
            XCTAssertNotNil(service["NSRequiredContext"] as? [String: Any], "\(service)")
            XCTAssertEqual(service["NSPortName"] as? String, "OpenIntelligence")
            let menu = try XCTUnwrap(service["NSMenuItem"] as? [String: String])
            XCTAssertFalse(menu["default", default: ""].isEmpty)
        }
    }

    /// Finder offers the file service for the same types the app opens.
    func testFileServiceTakesTheTypesTheAppOpens() throws {
        let fileService = try XCTUnwrap(try services().first { $0["NSMessage"] as? String == "addFilesToLibrary" })
        let sendFileTypes = try XCTUnwrap(fileService["NSSendFileTypes"] as? [String])
        let documentTypes = try XCTUnwrap(sourceInfoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let opened = documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(sendFileTypes), Set(opened))
    }

    func testAskLandsInTheChatAndCarriesNoText() {
        // The text never goes into an address. (Posting it here would hand it to the chat screen
        // of the app the tests run in, which takes it at once.)
        XCTAssertEqual(AppLink.url(for: .ask("What does clause 4 say about notice?")).absoluteString, "openintelligence://chat")
    }

    func testAComposerDraftIsNewEachTime() {
        XCTAssertNotEqual(ComposerDraft(text: "same"), ComposerDraft(text: "same"))
    }

    #if os(macOS)
        func testEveryDeclaredMessageHasItsMethod() throws {
            for message in try services().compactMap({ $0["NSMessage"] as? String }) {
                XCTAssertTrue(
                    MacServicesProvider.instancesRespond(to: NSSelectorFromString("\(message):userData:error:")),
                    message)
            }
        }

        func testSelectedTextIsTrimmedAndEmptyIsNothing() {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacServicesTests"))
            pasteboard.clearContents()
            pasteboard.setString("  a sentence \n", forType: .string)
            XCTAssertEqual(MacServicesProvider.selectedText(on: pasteboard), "a sentence")
            pasteboard.clearContents()
            pasteboard.setString(" \n ", forType: .string)
            XCTAssertNil(MacServicesProvider.selectedText(on: pasteboard))
        }
    #endif
}
