//
//  DeveloperDiagnosticsHubView.swift
//  OpenIntelligence
//
//  Streamlined developer tools and diagnostics hub
//

import SwiftUI

struct DeveloperDiagnosticsHubView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("loggingLevel") private var loggingLevelRaw: Int = LoggingConfiguration.Level.info.rawValue
    @AppStorage("enablePipelineLogs") private var enablePipelineLogs: Bool = true
    @AppStorage("enablePerformanceLogs") private var enablePerformanceLogs: Bool = true
    @AppStorage("enableLLMLogs") private var enableLLMLogs: Bool = true
    @AppStorage("enableStreamingLogs") private var enableStreamingLogs: Bool = false
    @AppStorage("enableVectorDBLogs") private var enableVectorDBLogs: Bool = true
    @State private var pccCapability: FoundationModelCapabilitySnapshot?

    var body: some View {
        List {
            // Quick Status
            Section {
                systemStatusRow
            } header: {
                Text("System Status")
            }

            // Pipeline Debugging
            Section {
                Toggle(isOn: $settings.enablePipelineTrace) {
                    Label("Pipeline Trace", systemImage: "list.bullet.clipboard")
                }
                Toggle(isOn: $settings.forceReasoningChain) {
                    Label("Force Reasoning Chain", systemImage: "brain")
                }
            } header: {
                Text("Pipeline Debugging")
            } footer: {
                Text("Pipeline Trace shows chunk flow through RAG stages. Force Reasoning uses multi-session even when not needed.")
            }

            // Private Cloud Compute Diagnostics
            Section {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    if let capability = pccCapability {
                        LabeledContent("PCC Entitlement", value: capability.hasPCCEntitlement ? "Present" : "Missing")
                        LabeledContent("PCC Availability", value: capability.pccAvailable ? "Available" : "Unavailable")
                        LabeledContent(
                            "Context Size",
                            value: capability.pccContextSize.map { "\($0) tokens" } ?? "Not reported"
                        )
                        LabeledContent("Quota Status", value: capability.pccQuota.rawValue)
                        LabeledContent("Limit Reached", value: capability.pccQuota == .limitReached ? "Yes" : "No")
                        if let reason = capability.unavailabilityReason, !capability.pccAvailable {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        let policyRoute = FoundationModelRoutePolicy.determineRoute(
                            queryType: .maximum,
                            estimatedContextTokens: 1000,
                            config: InferenceConfig(
                                maxTokens: 0,
                                temperature: 0.7,
                                topP: 0.0,
                                topK: 0,
                                systemPrompt: nil,
                                contextLength: 32768,
                                executionContext: .automatic,
                                allowPrivateCloudCompute: true,
                                disableTools: false
                            )
                        )
                        
                        switch policyRoute {
                        case .privateCloudCompute(let reasoning):
                            LabeledContent("Maximum Reasoning", value: String(describing: reasoning).capitalized)
                        default:
                            LabeledContent("Maximum Reasoning", value: "N/A")
                        }
                    } else {
                        ProgressView("Reading PCC capability…")
                    }
                } else {
                    Text("Requires iOS 26+")
                }
                #endif
            } header: {
                Text("Private Cloud Compute")
            }

            // Console Logging
            Section {
                Picker("Log Level", selection: $loggingLevelRaw) {
                    Text("Silent").tag(LoggingConfiguration.Level.silent.rawValue)
                    Text("Error").tag(LoggingConfiguration.Level.error.rawValue)
                    Text("Info").tag(LoggingConfiguration.Level.info.rawValue)
                    Text("Debug").tag(LoggingConfiguration.Level.debug.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: loggingLevelRaw) { _, _ in applyLoggingSettings() }
            } header: {
                Text("Console Logging")
            }

            // Log Categories (collapsed by default)
            Section {
                DisclosureGroup("Log Categories") {
                    Toggle("RAG Pipeline", isOn: $enablePipelineLogs)
                        .onChange(of: enablePipelineLogs) { _, _ in applyLoggingSettings() }
                    Toggle("Performance", isOn: $enablePerformanceLogs)
                        .onChange(of: enablePerformanceLogs) { _, _ in applyLoggingSettings() }
                    Toggle("LLM Generation", isOn: $enableLLMLogs)
                        .onChange(of: enableLLMLogs) { _, _ in applyLoggingSettings() }
                    Toggle("Token Streaming", isOn: $enableStreamingLogs)
                        .onChange(of: enableStreamingLogs) { _, _ in applyLoggingSettings() }
                    Toggle("Vector Database", isOn: $enableVectorDBLogs)
                        .onChange(of: enableVectorDBLogs) { _, _ in applyLoggingSettings() }
                }
            }

            // Quick Presets
            Section {
                HStack(spacing: 12) {
                    Button("Production") { applyProductionPreset() }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    Button("Dev") { applyDevelopmentPreset() }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    Button("Debug") { applyDebugPreset() }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("Presets")
            }

            // Diagnostic Tools
            Section {
                NavigationLink {
                    RAGAccuracyView(ragService: ragService)
                } label: {
                    Label("RAG Accuracy", systemImage: "checkmark.seal.fill")
                }
                #if DEBUG
                NavigationLink {
                    ValidationDashboardView(ragService: ragService, settingsStore: SettingsStore(ragService: ragService))
                } label: {
                    Label("Validation Benchmark", systemImage: "gauge.with.dots.needle.bottom.100percent")
                }
                #endif
                NavigationLink {
                    ChunkInspectorView(ragService: ragService)
                        .environmentObject(ragService.containerService)
                } label: {
                    Label("Chunk Inspector", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    CoreValidationView(ragService: ragService)
                } label: {
                    Label("Core Validation", systemImage: "checkmark.circle")
                }
                NavigationLink {
                    BackendHealthDiagnosticsView(ragService: ragService)
                } label: {
                    Label("Backend Health", systemImage: "server.rack")
                }
                NavigationLink {
                    RAGPipelineAuditView(ragService: ragService)
                } label: {
                    Label("Pipeline Audit", systemImage: "list.bullet.clipboard")
                }
                NavigationLink {
                    TelemetryDashboardView()
                } label: {
                    Label("Telemetry", systemImage: "chart.bar")
                }
            } header: {
                Text("Diagnostics")
            }

            // Visualization
            Section {
                NavigationLink {
                    AdaptiveVisualizationsView()
                        .environmentObject(ragService)
                        .environmentObject(ragService.containerService)
                } label: {
                    Label("Knowledge Atlas", systemImage: "globe.americas")
                }
            } header: {
                Text("Visualization")
            }
        }
        .navigationTitle("Developer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear { applyLoggingSettings() }
        .task { await refreshPCCCapability() }
    }

    private func refreshPCCCapability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            pccCapability = await LiveFoundationModelCapabilityProvider().snapshot()
        }
        #endif
    }

    // MARK: - System Status Row

    @ViewBuilder
    private var systemStatusRow: some View {
        let caps = RAGService.checkDeviceCapabilities()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(caps.supportsAppleIntelligence ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(caps.supportsAppleIntelligence ? "Apple Intelligence Ready" : "On-Device Only")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(settings.ragQualityMode.canonical.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                statusItem("Docs", value: "\(ragService.documents.count)")
                statusItem("Mode", value: settings.ragQualityMode.canonical.displayName)
                statusItem("Model", value: settings.selectedModel.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Logging

    private func applyLoggingSettings() {
        let level = LoggingConfiguration.Level(rawValue: loggingLevelRaw) ?? .info
        LoggingConfiguration.currentLevel = level

        var categories = Set<LoggingConfiguration.Category>()
        if enablePipelineLogs { categories.insert(.pipeline) }
        if enablePerformanceLogs { categories.insert(.performance) }
        if enableLLMLogs { categories.insert(.llm) }
        if enableStreamingLogs { categories.insert(.streaming) }
        if enableVectorDBLogs { categories.insert(.vectorDB) }
        LoggingConfiguration.enabledCategories = categories
    }

    private func applyProductionPreset() {
        loggingLevelRaw = LoggingConfiguration.Level.silent.rawValue
        enablePipelineLogs = false
        enablePerformanceLogs = false
        enableLLMLogs = false
        enableStreamingLogs = false
        enableVectorDBLogs = false
        applyLoggingSettings()
    }

    private func applyDevelopmentPreset() {
        loggingLevelRaw = LoggingConfiguration.Level.info.rawValue
        enablePipelineLogs = true
        enablePerformanceLogs = true
        enableLLMLogs = true
        enableStreamingLogs = false
        enableVectorDBLogs = true
        applyLoggingSettings()
    }

    private func applyDebugPreset() {
        loggingLevelRaw = LoggingConfiguration.Level.debug.rawValue
        enablePipelineLogs = true
        enablePerformanceLogs = true
        enableLLMLogs = true
        enableStreamingLogs = true
        enableVectorDBLogs = true
        applyLoggingSettings()
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
