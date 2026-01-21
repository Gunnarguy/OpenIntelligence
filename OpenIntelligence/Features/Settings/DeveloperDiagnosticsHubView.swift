//
//  DeveloperDiagnosticsHubView.swift
//  OpenIntelligence
//
//  Consolidated hub for developer tools and diagnostics
//

import SwiftUI

struct DeveloperDiagnosticsHubView: View {
    @ObservedObject var ragService: RAGService

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Diagnostics
                    SurfaceCard {
                        SectionHeader(icon: "wrench.and.screwdriver", title: "Diagnostics")
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink {
                                CoreValidationView(ragService: ragService)
                            } label: {
                                Label("Core Validation", systemImage: "checkmark.circle")
                            }

                            NavigationLink {
                                TelemetryDashboardView()
                            } label: {
                                Label("Telemetry Dashboard", systemImage: "waveform.path.ecg")
                            }

                            NavigationLink {
                                ContainerScopingSelfTestsView(ragService: ragService)
                            } label: {
                                Label("Container Scoping Self-Tests", systemImage: "magnifyingglass.circle")
                            }

                            NavigationLink {
                                BackendHealthDiagnosticsView(ragService: ragService)
                            } label: {
                                Label("Backend Health", systemImage: "server.rack")
                            }

                            NavigationLink {
                                RAGPipelineAuditView(ragService: ragService)
                            } label: {
                                Label("RAG Audit", systemImage: "waveform.path.ecg")
                            }

                            NavigationLink {
                                NLChunkingDiagnosticsView()
                            } label: {
                                Label("NL Chunking Diagnostics", systemImage: "text.magnifyingglass")
                            }
                        }
                    }

                    // Developer Tools
                    SurfaceCard {
                        SectionHeader(icon: "hammer.fill", title: "Developer Tools")
                        VStack(alignment: .leading, spacing: 8) { 
                            NavigationLink {
                                VisualizationsView()
                                    .environmentObject(ragService)
                            } label: {
                                Label("Legacy Visualizations", systemImage: "chart.xyaxis.line")
                            }

                            NavigationLink {
                                AdaptiveVisualizationsView()
                                    .environmentObject(ragService)
                            } label: {
                                Label("Knowledge Atlas (Adaptive)", systemImage: "globe.americas")
                            }

                            NavigationLink {
                                DeveloperSettingsView()
                            } label: {
                                Label("Developer Settings", systemImage: "hammer.fill")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Developer & Diagnostics")
    }
}

#Preview {
    NavigationView {
        DeveloperDiagnosticsHubView(ragService: RAGService())
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
}
