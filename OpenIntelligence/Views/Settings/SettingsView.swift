//
//  SettingsView.swift
//  OpenIntelligence
//
//  Simplified settings view. Only Apple Intelligence and On-Device Analysis are supported.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore

    @State private var deviceCapabilities = DeviceCapabilities()
    @State private var pipelineStages: [ModelPipelineStage] = []
    @State private var showModelSelector = false
    @State private var showPlanSheet = false
    @State private var planEntryPoint: PlanUpgradeEntryPoint = .settings

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                heroCard
                billingCard
                modelSelectionCard
                executionCard
                cloudConsentCard
                fallbackCard
                generationCard
                retrievalCard
                developerCard
                aboutCard
            }
.padding()
        }
.background(DSColors.background.ignoresSafeArea())
    .navigationTitle("Settings")
.sheet(isPresented: $showModelSelector) {
    ModelSelectorSheet(ragService: ragService)
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanUpgradeSheet(entryPoint: planEntryPoint)
        }
.onAppear {
    deviceCapabilities = RAGService.checkDeviceCapabilities()
    updatePipelineStages()
}
.onChange(of: settings.selectedModel) { _, _ in
    updatePipelineStages()
}
    }

    // MARK: - Hero Card

    @ViewBuilder
    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: settings.selectedModel.iconName)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text(settings.selectedModel.displayName)
                .font(.title2.bold())
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
.frame(maxWidth: .infinity)
.padding(.vertical, 24)
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusText: String {
        switch settings.selectedModel {
        case .appleIntelligence:
            return deviceCapabilities.supportsFoundationModels
                ? "Ready • On-device + PCC"
                : "Preparing..."
        case .onDeviceAnalysis:
            return "Ready • Extractive QA"
        }
    }

    // MARK: - Billing Card

    @ViewBuilder
    private var billingCard: some View {
        VStack(alignment: .leading, spacing: 12) { 
            // Header with tier badge
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription")
                        .font(.headline)
                    Text(subscriptionStatusText)
                        .font(.caption)
.foregroundColor(.secondary)
                }
                Spacer()
                tierBadge
            }

            Divider()

            // Always show a button to access subscription management
            Button { 
                planEntryPoint = .settings
                showPlanSheet = true
            } label: { 
                HStack {
                    Image(systemName: entitlementStore.activeTier == .free ? "arrow.up.circle" : "gearshape")
                    Text(entitlementStore.activeTier == .free ? "Upgrade Plan" : "Manage Subscription")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
.font(.subheadline.weight(.medium))
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(entitlementStore.activeTier == .free ? Color.accentColor : Color.accentColor.opacity(0.1))
    .foregroundColor(entitlementStore.activeTier == .free ? .white : .accentColor)
    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Show quota info
            HStack(spacing: 16) {
                quotaItem(
                    icon: "doc.text",
                    value: "\(entitlementStore.documentLimit)",
                    label: "Documents"
                )
                quotaItem(
                    icon: "folder",
                    value: "\(entitlementStore.libraryLimit)",
                    label: "Libraries"
                )
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var subscriptionStatusText: String {
        switch entitlementStore.activeTier {
        case .free:
            return "Free tier • Limited features"
        case .starter:
            return "Starter plan • Active"
        case .pro:
            return "Pro plan • Active"
        case .lifetime:
            return "Lifetime • Unlimited"
        }
    }

    @ViewBuilder
    private var tierBadge: some View {
        Text(entitlementStore.activeTier.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tierBadgeColor.opacity(0.15))
            .foregroundColor(tierBadgeColor)
            .clipShape(Capsule())
    }

    private var tierBadgeColor: Color {
        switch entitlementStore.activeTier {
        case .free: return .gray
        case .starter: return .blue
        case .pro: return .purple
        case .lifetime: return .orange
        }
    }

    @ViewBuilder
    private func quotaItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
.font(.subheadline.weight(.semibold))
Text(label)
    .font(.caption)
    .foregroundColor(.secondary)
        }
    }

    // MARK: - Model Selection Card

    @ViewBuilder
    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
                Text("AI Model")
                    .font(.headline)
                Spacer()
            }

            Button {
                showModelSelector = true
            } label: {
                HStack {
                    Image(systemName: settings.selectedModel.iconName)
                        .font(.title2)
                        .foregroundColor(.accentColor)
.frame(width: 40)
VStack(alignment: .leading, spacing: 2) { 
                        Text(settings.selectedModel.displayName)
.font(.body)
Text(settings.selectedModel.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
.lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
.padding(12)
    .background(Color.accentColor.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
.buttonStyle(.plain)
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Execution Card

    @ViewBuilder
    private var executionCard: some View { 
        VStack(alignment: .leading, spacing: 12) { 
            HStack { 
                Image(systemName: "gearshape.2")
                    .foregroundColor(.accentColor)
                Text("Execution")
                    .font(.headline)
                Spacer()
            }

            Picker("Run on", selection: Binding(
                get: { settings.executionContext },
                set: { settings.executionContext = $0 }
            )) {
                Text("Auto").tag(ExecutionContext.automatic)
                Text("On-Device").tag(ExecutionContext.onDeviceOnly)
                Text("Prefer Cloud").tag(ExecutionContext.preferCloud)
                Text("Cloud Only").tag(ExecutionContext.cloudOnly)
            }
.pickerStyle(.segmented)
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Cloud Consent Card

    @ViewBuilder
    private var cloudConsentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { 
                Image(systemName: "lock.shield")
                    .foregroundColor(.accentColor)
                Text("Privacy")
                    .font(.headline)
                Spacer()
            }

            Toggle("Allow Private Cloud Compute", isOn: $settings.allowPrivateCloudCompute)

            if settings.allowPrivateCloudCompute {
                Text("Apple's PCC provides cryptographic privacy guarantees. Your data is never retained.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Fallback Card

    @ViewBuilder
    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
                Text("Fallbacks")
                    .font(.headline)
                Spacer()
            }

            Toggle("Enable Fallback", isOn: $settings.enableFirstFallback)

            if settings.enableFirstFallback {
                Picker("Fallback Model", selection: $settings.firstFallback) {
                    ForEach(settings.fallbackOptions(excluding: [settings.selectedModel]), id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
.pickerStyle(.menu)
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Generation Card

    @ViewBuilder
    private var generationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { 
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                Text("Generation")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) { 
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.temperature, in: 0 ... 2, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 8) { 
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(settings.maxTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.maxTokens) },
                    set: { settings.maxTokens = Int($0) }
                ), in: 100 ... 4000, step: 100)
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Retrieval Card

    @ViewBuilder
    private var retrievalCard: some View {
        VStack(alignment: .leading, spacing: 12) { 
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Retrieval")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top K")
                    Spacer()
                    Text("\(settings.topK)")
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.topK) },
                    set: { settings.topK = Int($0) }
                ), in: 1 ... 20, step: 1)
            }

        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Developer Card

    @ViewBuilder
    private var developerCard: some View {
        NavigationLink {
            DeveloperSettingsView()
        } label: { 
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.accentColor)
                Text("Developer & Diagnostics")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
        }
.buttonStyle(.plain)
    }

    // MARK: - About Card

    @ViewBuilder
    private var aboutCard: some View {
        NavigationLink {
            AboutView()
        } label: { 
            HStack { 
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text("About")
                    .font(.headline)
                Spacer()
                Text(Bundle.main.appVersion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
        }
.buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func updatePipelineStages() {
        pipelineStages = [
            ModelPipelineStage(
                name: "Embedding",
                role: .primary,
                detail: "NLEmbedding (512-dim)",
                status: .active, 
                icon: "rectangle.3.group"
            ),
            ModelPipelineStage(
                name: "Retrieval",
                role: .primary,
                detail: "Hybrid Vector + BM25",
                status: .active,
                icon: "magnifyingglass"
            ),
            ModelPipelineStage(
                    name: "Generation",
                    role: .primary,
                    detail: settings.selectedModel.displayName,
                    status: deviceCapabilities.supportsFoundationModels ? .active : .unavailable(reason: "Not available"),
                    icon: "text.bubble"
                )
        ]
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        "\(infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}

#Preview {
    NavigationStack { 
        SettingsView(ragService: RAGService())
            .environmentObject(SettingsStore(ragService: RAGService()))
            .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
    }
}
