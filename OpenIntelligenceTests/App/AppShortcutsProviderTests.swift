//
//  AppShortcutsProviderTests.swift
//  OpenIntelligenceTests
//
//  Apple allows an app ten App Shortcuts. An eleventh does not fail the build: the whole set stops
//  registering, with no error. This is the only thing that says so before a release does.
//

import AppIntents
import XCTest

@testable import OpenIntelligence

@MainActor
final class AppShortcutsProviderTests: XCTestCase {
    func testTheAppOffersAtMostTenAppShortcuts() {
        let count = RAGAppShortcutsProvider.appShortcuts.count
        XCTAssertLessThanOrEqual(count, 10, "Apple's limit is ten; \(count) would stop all of them registering")
        XCTAssertEqual(count, 10, "update the docs that say how many slots are used when this changes")
    }
}
