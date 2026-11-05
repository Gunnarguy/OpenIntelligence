//
//  AppTips.swift
//  OpenIntelligence
//
//  Created by OpenIntelligence on 2/18/26.
//
//  TipKit integration — contextual tips for first-time users.
//  Tips automatically dismiss after the associated action is performed.
//

import SwiftUI
import TipKit
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Tip Definitions

// `FirstQueryTip`, `IngestDocumentTip` and `ContainerTip` were here until 5.8. Nothing displayed them or donated their
// events, so none ever showed. The tour's composer, Add Document and New Library stops replace them (`TourTips.swift`).

/// Tip shown in Settings to highlight model configuration.
struct ModelConfigTip: Tip {
    static let settingsVisited = Event(id: "settingsVisited")

    var title: Text {
        Text("Configure Your AI")
    }

    var message: Text? {
        Text("Tune retrieval depth, temperature, and context window.")
    }

    var image: Image? {
        Image(systemName: "slider.horizontal.3")
    }

    var rules: [Rule] {
        [
            #Rule(Self.settingsVisited) { event in
                event.donations.count == 0
            }
        ]
    }
}

/// Tip for the Atlas visualization feature.
struct AtlasTip: Tip {
    static let atlasViewed = Event(id: "atlasViewed")

    var title: Text {
        Text("Explore Your Knowledge")
    }

    var message: Text? {
        Text("See which passages of your documents sit close together in meaning.")
    }

    var image: Image? {
        Image(systemName: "globe.americas")
    }

    var rules: [Rule] {
        [
            #Rule(Self.atlasViewed) { event in
                event.donations.count == 0
            }
        ]
    }
}

// MARK: - Compact Tip Style

/// A compact inline tip style that prevents text clipping and uses smaller fonts.
struct CompactTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.image?
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                configuration.title
                    .font(.subheadline.weight(.semibold))

                // The readable gray for every tip (5.7): `.secondary` here "failed" Apple's contrast audit in Settings.
                configuration.message?
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Inline Tip Wrapper

/// A reusable view that renders a tip inline at the top of content,
/// properly sized so text is never clipped.
struct InlineTipView<T: Tip>: View {
    let tip: T

    var body: some View {
        TipView(tip)
            .tipViewStyle(CompactTipViewStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: 420)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: - TipKit Configuration

/// Call once at app launch to configure TipKit.
enum AppTipConfiguration {
    static func configure() {
        #if DEBUG
            // Screenshots of the tour: every tip eligible at once (5.8). Development builds only.
            if ProcessInfo.processInfo.arguments.contains("-tourShowAll") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure([
            // Show tips immediately for new users; after reset, show tips again
            .displayFrequency(.immediate)
        ])
        #if DEBUG
            // One tour stop alone, by its step name (`-tourShowOnly technicalDetails`), so a UI test reaches a tip
            // that comes late in its screen's order (5.8, TourTipCloseUITests). Every stop is one `TourTip` type, so
            // `showTipsForTesting` can't pick one out, and `showAllTipsForTesting` ignores closed tips: with the
            // normal rules, the others are closed and the chosen one is shown again.
            let arguments = ProcessInfo.processInfo.arguments
            if let i = arguments.firstIndex(of: "-tourShowOnly"), i + 1 < arguments.count,
                let only = TourStep(rawValue: arguments[i + 1])
            {
                TourContext.welcomeClosed = true
                for step in TourStep.allCases where step != only { TourTip(step).invalidate(reason: .tipClosed) }
                Task { await TourTip(only).resetEligibility() }
            }
        #endif
        // The tour's facts that don't change while the app runs (5.8).
        #if os(macOS)
            TourContext.isMac = true
            TourContext.isLargeScreen = true
        #else
            TourContext.isMac = ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
            TourContext.isLargeScreen = UIDevice.current.userInterfaceIdiom != .phone
        #endif
        Task { await TourContext.appLaunched.donate() }
        Tour.recordStatusChanges()
    }
}
