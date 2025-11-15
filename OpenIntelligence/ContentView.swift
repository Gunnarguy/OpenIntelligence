//
//  ContentView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var containerService: ContainerService
    @StateObject private var ragService: RAGService
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var onboardingStore: OnboardingStateStore
    @StateObject private var entitlementStore: EntitlementStore
    @State private var selectedTab: Tab = .chat

    init() {
#if DEBUG
        StoreKitTestHarness.startIfNeeded()
#endif
        let containerSvc = ContainerService()
        let billingSvc = StoreKitBillingService()
        let entitlementStore = EntitlementStore(billingService: billingSvc)
        let ragSvc = RAGService(containerService: containerSvc, entitlementStore: entitlementStore)
        _containerService = StateObject(wrappedValue: containerSvc)
        _ragService = StateObject(wrappedValue: ragSvc)
        _settingsStore = StateObject(wrappedValue: SettingsStore(ragService: ragSvc))
        _onboardingStore = StateObject(wrappedValue: OnboardingStateStore())
        _entitlementStore = StateObject(wrappedValue: entitlementStore)
    }

    enum Tab {
        case chat, documents, visualizations, settings
    }

    private var shouldShowChecklistLauncher: Bool {
        onboardingStore.hasOutstandingSteps && !onboardingStore.isChecklistVisible
    }

    var body: some View {
        ZStack {
            tabViewContent

            if onboardingStore.isChecklistVisible {
                OnboardingChecklistView(
                    ragService: ragService,
                    onOpenSettings: { selectedTab = .settings },
                    onOpenChat: { selectedTab = .chat }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowChecklistLauncher {
                OnboardingChecklistLauncher(
                    completedSteps: onboardingStore.completedStepCount,
                    totalSteps: onboardingStore.totalStepCount,
                    action: onboardingStore.refreshChecklistVisibilityIfNeeded
                )
                .padding(.trailing, 24)
                .padding(.bottom, 28)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: onboardingStore.isChecklistVisible)
        .environmentObject(onboardingStore)
        .environmentObject(entitlementStore)
        .onReceive(settingsStore.$hasUserPrimaryOverride) { hasOverride in
            guard hasOverride else { return }
            onboardingStore.markModelSelectionAcknowledged()
        }
    }

    @ViewBuilder
    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                ChatScreen(ragService: ragService)
            }
            #if os(iOS)
                .navigationViewStyle(.stack)
            #endif
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(Tab.chat)

            NavigationView {
                DocumentLibraryView(
                    ragService: ragService,
                    containerService: containerService,
                    onViewVisualizations: { selectedTab = .visualizations }
                )
            }
            #if os(iOS)
                .navigationViewStyle(.stack)
            #endif
            .tabItem {
                Label("Documents", systemImage: "doc.text.magnifyingglass")
            }
            .tag(Tab.documents)

            NavigationView {
                VisualizationsView(onRequestAddDocuments: { selectedTab = .documents })
                    .environmentObject(ragService)
                    .environmentObject(containerService)
            }
            #if os(iOS)
                .navigationViewStyle(.stack)
            #endif
            .tabItem {
                Label("Visualizations", systemImage: "cube.transparent")
            }
            .tag(Tab.visualizations)

            NavigationView {
                SettingsView(ragService: ragService)
            }
            #if os(iOS)
                .navigationViewStyle(.stack)
            #endif
            .environmentObject(settingsStore)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
}
