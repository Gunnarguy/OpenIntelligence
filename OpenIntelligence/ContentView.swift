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
    @State private var selectedTab: Tab = .chat

    init() {
        let containerSvc = ContainerService()
        let ragSvc = RAGService(containerService: containerSvc)
        _containerService = StateObject(wrappedValue: containerSvc)
        _ragService = StateObject(wrappedValue: ragSvc)
        _settingsStore = StateObject(wrappedValue: SettingsStore(ragService: ragSvc))
    }

    enum Tab {
        case chat, documents, visualizations, settings
    }

    var body: some View {
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
