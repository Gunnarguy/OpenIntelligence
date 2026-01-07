//
//  SettingsView.swift
//  OpenIntelligence
//
//  Comprehensive settings for the RAG pipeline and AI experience.
//  Optimized for Apple Intelligence with Private Cloud Compute.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore

    @State private var deviceCapabilities = DeviceCapabilities()
    @State private var pipelineStages: [ModelPipelineStage] = []
    @State private var showPlanSheet = false
    @State private var planEntryPoint: PlanUpgradeEntryPoint = .settings
    @State private var showAdvancedGeneration = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Hero & Core Experience
                heroCard
                modelSelectionCard

                // Privacy & Execution (combined)
                privacyExecutionCard

                // Subscription
                billingCard

                // Fine-Tuning
                generationCard
                retrievalCard

                // Context & Performance
                contextWindowCard

                // More
                developerCard
                aboutCard
            }
.padding()
        }
.background(
    LinearGradient(
        colors: [DSColors.background, DSColors.surface.opacity(0.3)],
        startPoint: .top,
        endPoint: .bottom
    )
    .ignoresSafeArea()
)
.navigationTitle("Settings")
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
        VStack(spacing: 16) {
            // Animated icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 4) {
                Text("OpenIntelligence")
                    .font(.title2.bold())

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Pipeline status pills
            HStack(spacing: 8) {
                statusPill(
                    icon: "checkmark.circle.fill",
                    text: "On-Device",
                    active: deviceCapabilities.supportsFoundationModels
                )
                statusPill(
                    icon: "cloud.fill",
                    text: "PCC",
                    active: settings.executionContext != .onDeviceOnly
                )
            }
        }
.frame(maxWidth: .infinity)
.padding(.vertical, 24)
    .background(DSColors.surface)
.clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func statusPill(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .foregroundColor(active ? .accentColor : .secondary)
        .clipShape(Capsule())
    }

    private var statusText: String {
        if deviceCapabilities.supportsFoundationModels {
            return "Apple Intelligence Ready"
        } else {
            return "Preparing AI Models..."
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
                Image(systemName: "apple.logo")
                    .foregroundColor(.accentColor)
                Text("Apple Intelligence")
                    .font(.headline)
                Spacer()

                // Availability indicator
                if deviceCapabilities.supportsAppleIntelligence {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Available")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.green)
                    }
                }
            }

            // Model info (not a button since there's only one option)
            HStack { 
                Image(systemName: "brain.head.profile.fill")
                    .font(.title2)
.foregroundStyle(
    LinearGradient(
        colors: [.accentColor, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
)
.frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("On-Device Foundation Model")
                        .font(.subheadline.weight(.medium))
                    Text("~3B parameters • 2-bit quantized • Neural Engine optimized")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
.background(Color.accentColor.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12))

            // Model capabilities
            HStack(spacing: 12) {
                modelCapabilityPill(icon: "text.bubble.fill", label: "Text Generation")
                modelCapabilityPill(icon: "wrench.and.screwdriver.fill", label: "Tool Calling")
                modelCapabilityPill(icon: "doc.text.fill", label: "RAG-Ready")
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func modelCapabilityPill(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Privacy & Execution Card (Combined)

    @ViewBuilder
    private var privacyExecutionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { 
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy & Execution")
                        .font(.headline)
                    Text("Apple Intelligence routing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.executionContext == .onDeviceOnly ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(settings.executionContext == .onDeviceOnly ? "Local Only" : "Full")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(settings.executionContext == .onDeviceOnly ? .orange : .green)
                }
            }

            // Automatic Routing Explanation
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("How Apple Routes Queries")
                        .font(.subheadline.weight(.medium))
                }

                Text("OpenIntelligence is reliability-first: for library queries it prefers Private Cloud Compute when allowed, then additionally uses Apple's routing (complexity, context length, thermals, battery, privacy).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Routing factors visualization
                HStack(spacing: 8) {
                    routingFactorPill(icon: "brain.head.profile", label: "Complexity")
                    routingFactorPill(icon: "thermometer.medium", label: "Thermals")
                    routingFactorPill(icon: "battery.100percent", label: "Battery")
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()

            // Execution Context Picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Execution Strategy")
                    .font(.subheadline.weight(.medium))

                Picker("Execution Strategy", selection: $settings.executionContext) {
                    Text("Automatic (Reliability-first)").tag(ExecutionContext.automatic)
                    Text("On-Device Only").tag(ExecutionContext.onDeviceOnly)
                    Text("Prefer Cloud").tag(ExecutionContext.preferCloud)
                    Text("Cloud Only").tag(ExecutionContext.cloudOnly)
                }
                .pickerStyle(.segmented)

                // Context Description
                Text(settings.executionPathDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.executionContext != .onDeviceOnly {
                    // PCC Benefits
                    VStack(alignment: .leading, spacing: 6) {
                        pccBenefitRow(icon: "checkmark.shield.fill", text: "End-to-end encrypted, no data retention", color: .green)
                        pccBenefitRow(icon: "eye.slash.fill", text: "Apple cannot see your prompts or responses", color: .green)
                        pccBenefitRow(icon: "doc.viewfinder", text: "Cryptographically verifiable by security researchers", color: .green)
                        pccBenefitRow(icon: "brain", text: "Long-context PT-MoE routing (~65K tokens)", color: .blue)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                } else {
                    // Limitations when PCC disabled
                    VStack(alignment: .leading, spacing: 6) {
                        pccBenefitRow(icon: "iphone", text: "All processing stays on your device", color: .orange)
                        pccBenefitRow(icon: "exclamationmark.triangle.fill", text: "Complex queries may fail or be truncated", color: .orange)
                        pccBenefitRow(icon: "ruler", text: "Limited to 4,096 token context window", color: .orange)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }
            }

            // Smart tip when PCC is unavailable
            if settings.executionContext == .onDeviceOnly {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Tip: PCC unlocks long-context coverage and reduces on-device truncation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func routingFactorPill(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func pccBenefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func processingModeCompare(icon: String, title: String, pros: String, cons: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(isActive ? .accentColor : .secondary)

            Text(pros)
                .font(.caption2)
                .foregroundColor(.green)
            Text(cons)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Context Window Card

    @ViewBuilder
    private var contextWindowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { 
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Context & Processing")
                    .font(.headline)
                Spacer()
            }

            // Context Window Limit explanation
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Context Window")
                        .font(.subheadline.weight(.medium))
                }

                Text("On-device context is capped at 4,096 tokens. When PCC is allowed, OpenIntelligence prefers long-context routing (~65K) for library queries to maximize coverage.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    contextInfoPill(icon: "iphone", label: "On-Device", value: "4K tokens")
                    contextInfoPill(icon: "cloud", label: "PCC Server", value: "65K tokens")
                }
            }
.padding(10)
    .background(Color.orange.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))

Divider()

// Neural Engine info
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 8) {
        Image(systemName: "cpu")
            .font(.caption)
            .foregroundColor(.purple)
        Text("Neural Engine Processing")
            .font(.subheadline.weight(.medium))
    }

                Text("Apple Intelligence uses the dedicated Neural Engine (16-core on A17+) for efficient inference. The system daemon modelmanagerd automatically routes queries based on complexity, thermal state, and battery level.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    neuralEngineInfoRow(icon: "thermometer.medium", label: "Thermal-aware")
                    neuralEngineInfoRow(icon: "battery.75percent", label: "Battery-aware")
                    neuralEngineInfoRow(icon: "bolt.badge.automatic", label: "Auto-routing")
                }
            }
.padding(10)
    .background(Color.purple.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))

Divider()

// Language Support
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 8) {
        Image(systemName: "globe")
            .font(.caption)
            .foregroundColor(.blue)
        Text("Language Support")
            .font(.subheadline.weight(.medium))
                }

                Text("Apple Intelligence supports English, Spanish, French, German, Italian, Japanese, Korean, Portuguese, and Chinese. Short single-word queries may require more context for accurate processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
.padding(10)
    .background(Color.blue.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func contextInfoPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func neuralEngineInfoRow(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }

    // MARK: - Generation Card

    @ViewBuilder
    private var generationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { 
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.accentColor)
                Text("Generation Style")
                    .font(.headline)
                Spacer()
            }

            // Temperature / Creativity
            // Map 0.0-1.0 temperature to 0-100% "Creativity" for better UX
            sliderRow(
                label: "Creativity",
                value: $settings.temperature,
                range: 0 ... 1.0,
                step: 0.1,
                valueString: "\(Int(settings.temperature * 100))%",
                description: settings.temperature < 0.3 ? "Precise & Deterministic" : settings.temperature > 0.7 ? "Creative & Diverse" : "Balanced"
            )

            Divider()

            // Auto-Context explanation
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Response length and context window are managed automatically by the Neural Engine based on query complexity and available compute.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueString: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(valueString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.accentColor)
            }
            Slider(value: value, in: range, step: step)
                .tint(.accentColor)
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Retrieval Card

    @ViewBuilder
    private var retrievalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Balanced Retrieval")
                    .font(.headline)
                Spacer()
            }

            Text("Balanced retrieval favors coverage and relevance without hard gating that blocks answers.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Developer Card

    @ViewBuilder
    private var developerCard: some View {
        NavigationLink {
            DeveloperDiagnosticsHubView(ragService: ragService)
        } label: { 
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer & Diagnostics")
.font(.subheadline.weight(.medium))
Text("RAG audit, diagnostics, advanced tuning")
    .font(.caption)
    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
.font(.caption.weight(.semibold))
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("About")
.font(.subheadline.weight(.medium))
Text("Version \(Bundle.main.appVersion)")
    .font(.caption)
    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
.font(.caption.weight(.semibold))
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
