//
//  MacSettingsWindowRoot.swift
//  OpenIntelligence
//
//  The Mac's Settings window (5.8 Mac redesign). Built from `AppServices.shared`, the same services the main window
//  uses, so it changes the same settings and libraries rather than a copy of them.
//

#if os(macOS)
    import SwiftUI

    /// The person's accent colour, as the main window applies it (`ContentView.appAccentColor`).
    @MainActor
    private func macAccentColor(_ settings: SettingsStore) -> Color {
        if let hex = settings.appAccentColorHex, let color = Color(hex: hex) { return color }
        return .accentColor
    }

    struct MacSettingsWindowRoot: View {
        private let services = AppServices.shared
        @ObservedObject private var settingsStore = AppServices.shared.settingsStore
        /// The How This Works page reads the first-run steps; the store reads and writes the same defaults the main
        /// window's does.
        @StateObject private var onboardingStore = OnboardingStateStore()

        var body: some View {
            SettingsView(ragService: services.ragService)
                .environmentObject(services.ragService)
                .environmentObject(services.containerService)
                .environmentObject(services.settingsStore)
                .environmentObject(services.entitlementStore)
                .environmentObject(services.workspaceSyncService)
                .environmentObject(services.modelResolutionService)
                .environmentObject(onboardingStore)
                .frame(minWidth: 820, idealWidth: 960, minHeight: 560, idealHeight: 720)
                .tint(macAccentColor(settingsStore))
                .macWithoutFocusRings()
        }
    }

    /// The Semantic Atlas's map in a window of its own (5.8 Mac redesign), which the window's green button takes to
    /// full screen as any Mac window; it was a sheet over the main window with its own close button.
    struct MacAtlasWindowRoot: View {
        private let services = AppServices.shared
        @ObservedObject private var settingsStore = AppServices.shared.settingsStore

        var body: some View {
            Fullscreen3DAtlasView()
                .environmentObject(services.ragService)
                .environmentObject(services.containerService)
                .environmentObject(services.settingsStore)
                .frame(minWidth: 800, minHeight: 600)
                .tint(macAccentColor(settingsStore))
                .macWithoutFocusRings()
        }
    }

    extension MacAtlasWindowRoot {
        static let windowID = "semantic-atlas"
    }
#endif
