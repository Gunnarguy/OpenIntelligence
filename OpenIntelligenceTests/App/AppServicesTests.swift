//
//  AppServicesTests.swift
//  OpenIntelligenceTests
//
//  Every window shares one engine and one sync (5.8, `AppServices`). Through the first 5.8 builds each `ContentView.init`
//  built its own, and each set started its launch work as it was built: on the owner's Mac two windows started two
//  rebuilds of the same library 29 ms apart (2026-11-03).
//

import SwiftUI
import XCTest

@testable import OpenIntelligence

@MainActor
final class AppServicesTests: XCTestCase {
    func testBuildingTheWindowAgainReusesTheAppsEngine() {
        let services = AppServices.shared
        _ = ContentView()
        _ = ContentView()
        _ = ContentView()
        XCTAssertTrue(
            RAGService.activePresentedInstance === services.ragService,
            "a window's view built again leaves the app's one engine in place, not a new one")
        XCTAssertTrue(AppServices.shared === services)
        XCTAssertTrue(services.ragService.containerService === services.containerService)
    }
}
