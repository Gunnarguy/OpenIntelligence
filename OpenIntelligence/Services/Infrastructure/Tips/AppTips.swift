//
//  AppTips.swift
//  OpenIntelligence
//
//  Created by OpenIntelligence on 2/18/26.
//
//  TipKit's setup. The tips themselves are the tour's (`TourTips.swift`).
//

import SwiftUI
import TipKit
#if canImport(UIKit)
    import UIKit
#endif

// `FirstQueryTip`, `IngestDocumentTip` and `ContainerTip` were here until 5.8. Nothing displayed them or donated their
// events, so none ever showed. `ModelConfigTip` (Settings) and `AtlasTip` (the Atlas) went with the tour's rebuild on
// 2026-11-13: neither taught something the screen doesn't show, and Settings › How This Works › Where Things Are now
// describes both screens.

// MARK: - TipKit Configuration

/// Call once at app launch to configure TipKit.
enum AppTipConfiguration {
    static func configure() {
        #if DEBUG
            // Screenshots of the tour: every tip eligible at once (5.8). Development builds only.
            if ProcessInfo.processInfo.arguments.contains("-tourShowAll") { Tips.showAllTipsForTesting() }
        #endif
        // The tour paces itself with a rule (`Tour.claimTurn`, one new tip every few minutes, none in the first minute
        // after launch), because TipKit's display frequency goes no lower than hourly. Each tip gives up after three
        // showings or a minute on screen, TipKit's floor (`TourTip.options`).
        try? Tips.configure([
            .displayFrequency(.immediate)
        ])
        #if DEBUG
            // One tour tip alone, by its step name (`-tourShowOnly privateCloud`), so a UI test or a screenshot reaches
            // a tip without waiting for the pacing or the tips before it in its screen's order (5.8,
            // TourTipCloseUITests). Every tip is one `TourTip` type, so `showTipsForTesting` can't pick one out, and
            // `showAllTipsForTesting` ignores closed tips: with the normal rules, the others are closed and the chosen
            // one is shown again.
            let arguments = ProcessInfo.processInfo.arguments
            if let i = arguments.firstIndex(of: "-tourShowOnly"), i + 1 < arguments.count,
                let only = TourStep(rawValue: arguments[i + 1])
            {
                TourContext.welcomeClosed = true
                TourContext.pace = "open"
                for step in TourStep.allCases where step != only { TourTip(step).invalidate(reason: .tipClosed) }
                Task { await TourTip(only).resetEligibility() }
            }
            if arguments.contains("-tourShowAll") { TourContext.pace = "open" }
        #endif
        // The tour's facts that don't change while the app runs (5.8).
        #if os(macOS)
            TourContext.isMac = true
            TourContext.isLargeScreen = true
        #else
            TourContext.isMac = ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
            TourContext.isLargeScreen = UIDevice.current.userInterfaceIdiom != .phone
            TourContext.xrayDrawsHere = DeviceComponentLayout.current.socPlacement != nil
        #endif
        Task { await TourContext.appLaunched.donate() }
        Tour.startPacing()
        Tour.recordStatusChanges()
    }
}
