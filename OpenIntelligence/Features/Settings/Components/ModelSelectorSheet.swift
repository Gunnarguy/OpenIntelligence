//
//  ModelSelectorSheet.swift
//  OpenIntelligence
//
//  Simplified model selection: Apple Intelligence + On-Device Analysis only.
//

import SwiftUI

struct ModelSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @State private var previewModel: LLMModelType?
    @State private var deviceCapabilities = DeviceCapabilities()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    headerSection
                    modelCards
                }
                .padding()
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $previewModel) { modelType in
                modelPreviewSheet(for: modelType)
            }
            .onAppear {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("Choose Your AI Engine")
                .font(.title2.bold())
            Text("Select the model that powers your knowledge queries")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
.padding(.vertical, 20)
    }

    @ViewBuilder
    private var modelCards: some View {
        VStack(spacing: 16) {
            // Apple Intelligence
            sectionHeader(title: "Apple Intelligence", icon: "sparkles")
            appleIntelligenceCard

            // On-Device Analysis
            sectionHeader(title: "Fallback Options", icon: "arrow.triangle.2.circlepath")
            onDeviceAnalysisCard
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var appleIntelligenceCard: some View {
        let isActive = settings.selectedModel == .appleIntelligence
        Button { activateModel(.appleIntelligence) } label: { 
            HStack(spacing: 16) { 
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
.fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Intelligence").font(.headline)
                    Text(deviceCapabilities.supportsFoundationModels ? "On-device + Private Cloud Compute" : "Preparing...")
                        .font(.caption).foregroundColor(.secondary)
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2)
                            Text("Active").font(.caption2.weight(.semibold))
                        } .foregroundColor(.blue)
                    }
                }
                Spacer()
                if !deviceCapabilities.supportsFoundationModels { 
                    Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundColor(.orange)
                }
                Button { previewModel = .appleIntelligence } label: {
                    Image(systemName: "info.circle").font(.title3).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.blue.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
.overlay(RoundedRectangle(cornerRadius: 16).stroke(isActive ? Color.blue.opacity(0.3) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!deviceCapabilities.supportsFoundationModels)
    }

    @ViewBuilder
    private var onDeviceAnalysisCard: some View {
        let isActive = settings.selectedModel == .onDeviceAnalysis
        Button { activateModel(.onDeviceAnalysis) } label: { 
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("On-Device Analysis").font(.headline)
                    Text("Extractive QA, no generative AI").font(.caption).foregroundColor(.secondary)
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2)
                            Text("Active").font(.caption2.weight(.semibold))
                        } .foregroundColor(.orange)
                    }
                }
                Spacer()
                Button { previewModel = .onDeviceAnalysis } label: {
                    Image(systemName: "info.circle").font(.title3).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.orange.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
.overlay(RoundedRectangle(cornerRadius: 16).stroke(isActive ? Color.orange.opacity(0.3) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modelPreviewSheet(for modelType: LLMModelType) -> some View { 
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { 
                    VStack(spacing: 12) {
                        Image(systemName: modelType.iconName).font(.system(size: 56)).foregroundColor(.accentColor)
                        Text(modelType.displayName).font(.title.bold())
                        Text(modelType.description).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
.frame(maxWidth: .infinity).padding(.vertical, 32)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Specifications").font(.headline)
                        specRow("Type", modelType.category)
                        specRow("Privacy", modelType.privacyLevel)
                        specRow("Network", modelType.requiresNetwork ? "Required" : "Optional")
                        specRow("Context", modelType.contextDescription)
                    } .padding(20).background(DSColors.surface).clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Capabilities").font(.headline)
                        ForEach(modelType.capabilities, id: \.self) { cap in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(cap).font(.subheadline)
                                Spacer()
                            }
                        }
                    } .padding(20).background(DSColors.surface).clipShape(RoundedRectangle(cornerRadius: 16))

                    Button { activateModel(modelType); previewModel = nil } label: { 
                        Label("Activate This Model", systemImage: "arrow.right.circle.fill")
.font(.headline).frame(maxWidth: .infinity).padding()
                    } .buttonStyle(.borderedProminent).controlSize(.large)
                } .padding()
            }
            .background(DSColors.background.ignoresSafeArea())
.navigationTitle("Model Details").navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { previewModel = nil } } }
        }
    }

    @ViewBuilder
    private func specRow(_ label: String, _ value: String) -> some View { 
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func activateModel(_ type: LLMModelType) {
        settings.selectedModel = type
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { DSHaptics.success(); dismiss() }
        }
    }
}

#Preview {
    let ragService = RAGService()
    ModelSelectorSheet(ragService: ragService)
        .environmentObject(SettingsStore(ragService: ragService))
        .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
}
