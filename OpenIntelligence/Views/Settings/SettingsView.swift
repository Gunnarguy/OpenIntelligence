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

    // Note: SystemStateMonitor moved to LiveSystemMonitorWrapper to avoid full-view redraws

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

                // Intelligence Mode (Standard vs Deep Think)
                retrievalCard

                // Generation Tuning (exposed hidden settings)
                generationTuningCard

                // Context & Performance
                contextWindowCard

                // More
                appearanceCard
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
                    active: true
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
.fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Automatic")
                        .font(.caption2.weight(.medium))
.foregroundColor(.green)
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

            // Private Cloud Compute Benefits (automatic routing, no picker needed)
            VStack(alignment: .leading, spacing: 10) {
                Text("Private Cloud Compute")
                    .font(.subheadline.weight(.medium))

                Text("OpenIntelligence automatically uses on-device processing when possible, and seamlessly escalates to Private Cloud Compute for complex queries or large documents.")
                    .font(.caption)
.foregroundColor(.secondary)

                // PCC Benefits
                VStack(alignment: .leading, spacing: 6) {
                    pccBenefitRow(icon: "checkmark.shield.fill", text: "End-to-end encrypted, no data retention", color: .green)
                    pccBenefitRow(icon: "eye.slash.fill", text: "Apple cannot see your prompts or responses", color: .green)
                    pccBenefitRow(icon: "doc.viewfinder", text: "Cryptographically verifiable by security researchers", color: .green)
                    pccBenefitRow(icon: "brain", text: "Handles complex reasoning tasks", color: .blue)
                }
                .padding(.leading, 4)
                    .padding(.top, 4)
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
        let deviceService = DeviceCapabilityService.shared

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Your Device")
                    .font(.headline)
                Spacer()

                // Device tier badge
                Text(deviceService.tier.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tierColor(for: deviceService.tier).opacity(0.15))
                    .foregroundColor(tierColor(for: deviceService.tier))
                    .clipShape(Capsule())
            }

            // Chip & Memory info (dynamic)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.caption)
.foregroundColor(.purple)
Text(deviceService.chipName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(String(format: "%.0f", deviceService.memoryGB)) GB RAM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Neural Engine: \(deviceService.npuTops) TOPS • \(deviceService.formFactor.hasActiveCooling ? "Active cooling" : "Passive cooling")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    deviceCapabilityPill(icon: "brain.head.profile", label: "Deep Think", value: "Up to \(deviceService.maxConcurrentAgenticSteps) steps")
                    deviceCapabilityPill(icon: "flame", label: "Thermal", value: deviceService.hasThermalHeadroom ? "High" : "Standard")
                }
            }
.padding(10)
.background(Color.purple.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()

            // Context Window
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Context Window")
                        .font(.subheadline.weight(.medium))
                }

                // Dynamic explanation based on mode
                if settings.ragQualityMode.canonical == .maximum {
                    Text("Maximum mode chains up to 50 reasoning sessions on your best-matched content. Each session reasons deeper on the same high-quality context until 98% confident.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text("Deep Think chains 4-8 reasoning sessions on your best-matched content. Each step reasons deeper, with cumulative insights building across sessions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Standard mode uses a single 4,096-token context window on-device. Private Cloud Compute handles queries exceeding this limit.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if settings.ragQualityMode.canonical == .maximum {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "flame.fill", label: "Total Budget", value: "200K+ tokens")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Effective", value: "32K+ tokens")
                    } else {
                        contextInfoPill(icon: deviceService.isMac ? "desktopcomputer" : (deviceService.isIPad ? "ipad" : "iphone"), label: "On-Device", value: "4K tokens")
                        contextInfoPill(icon: "cloud", label: "PCC", value: "Extended")
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.2), value: settings.ragQualityMode)

            Divider()

            // Silicon-Native RAG Engine
            siliconNativeRAGSection(deviceService: deviceService)

            Divider()

            // Live System Monitor
            LiveSystemMonitorWrapper()

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

                Text("Apple Intelligence supports English, Spanish, French, German, Italian, Japanese, Korean, Portuguese, and Chinese.")
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

    private func tierColor(for tier: DeviceCapabilityTier) -> Color {
        switch tier {
        case .unsupported: return .gray
        case .baseline: return .blue
        case .enhanced: return .green
        case .advanced: return .purple
        case .ultraAdvanced: return .orange
        }
    }

    @ViewBuilder
    private func deviceCapabilityPill(icon: String, label: String, value: String) -> some View {
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

    // MARK: - Silicon-Native RAG Engine Section

    @ViewBuilder
    private func siliconNativeRAGSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption)
                    .foregroundColor(.cyan)
                Text("Silicon-Native RAG Engine")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Accelerate")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text("Vector operations use Apple's Accelerate framework for Neural Engine acceleration. Batch sizes are tuned for your \(deviceService.chipName).")
                .font(.caption)
                .foregroundColor(.secondary)

            // Optimizations grid
            VStack(alignment: .leading, spacing: 6) {
                siliconFeatureRow(
                    icon: "function",
                    label: "vDSP Vector Math",
                    detail: "Hardware-accelerated similarity"
                )
                siliconFeatureRow(
                    icon: "square.grid.3x3.fill",
                    label: "Batch Matrix Ops",
                    detail: "Threshold: \(deviceService.batchMatrixMultiplyThreshold)+ chunks"
                )
                siliconFeatureRow(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Semantic Chunking",
                    detail: "Topic boundaries via embeddings"
                )
                siliconFeatureRow(
                    icon: "rectangle.stack.fill",
                    label: "Cross-Container Search",
                    detail: "Unified search with RRF fusion"
                )
            }

            // Batch size info
            HStack(spacing: 12) {
                siliconInfoPill(
                    icon: "square.stack.3d.up",
                    label: "Vector Batch",
                    value: "\(deviceService.vectorBatchSize)"
                )
                siliconInfoPill(
                    icon: "text.badge.checkmark",
                    label: "Embed Batch",
                    value: "\(deviceService.embeddingBatchSize)"
                )
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func siliconFeatureRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.cyan)
                .frame(width: 16)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func siliconInfoPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Generation Tuning Card

    @ViewBuilder
    private var generationTuningCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.below.square.filled.and.square")
                    .foregroundColor(.purple)
                Text("Generation Tuning")
                    .font(.headline)
                Spacer()
            }

            Text("Customize how the AI responds to your questions.")
                .font(.caption)
                .foregroundColor(.secondary)

            // System Prompt
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("System Prompt", systemImage: "text.quote")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    // Reset button inline
                    if settings.systemPrompt != "You are a helpful assistant." {
                        Button {
                            withAnimation {
                                settings.systemPrompt = "You are a helpful assistant."
                            }
                        } label: {
                            Text("Reset")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("You are a helpful assistant...", text: $settings.systemPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
                    .font(.caption)

                Text("Instructions given to the AI before each conversation.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Retrieval Card Helpers

    private var modeAccentColor: Color {
        switch settings.ragQualityMode.canonical {
        case .maximum: return .orange
        case .deepThink: return .purple
        default: return .green
        }
    }

    private var modeHeaderIcon: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "flame.fill"
        case .deepThink: return "brain.head.profile.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var modeHeaderTitle: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "Maximum Features"
        case .deepThink: return "Deep Think Features"
        default: return "Standard Features"
        }
    }

    // MARK: - Retrieval Card

    @ViewBuilder
    private var retrievalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundColor(.accentColor)
                Text("Intelligence Mode")
                    .font(.headline)
                Spacer()
            }

            Text("Choose how OpenIntelligence processes your questions.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Mode Picker - Standard vs Deep Think
            VStack(spacing: 12) {
                ForEach(RAGQualityMode.userVisibleCases, id: \.id) { mode in
                    intelligenceModeRow(mode: mode, isSelected: settings.ragQualityMode.canonical == mode)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                settings.ragQualityMode = mode
                            }
                            DSHaptics.selection()
                        }
                }
            }

            Divider()

            // Mode-specific features
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: modeHeaderIcon)
                        .foregroundColor(modeAccentColor)
                        .font(.caption)
                    Text(modeHeaderTitle)
                        .font(.caption.weight(.medium))
                }

                VStack(alignment: .leading, spacing: 6) {
                    // Common features for all modes
                    featureRow(icon: "sparkles", label: "HyDE Query Enhancement", description: "Generates hypothetical answer to improve embedding similarity", color: .green)
                    featureRow(icon: "text.redaction", label: "Contextual Compression", description: "LLM extracts only query-relevant sentences", color: .green)
                    featureRow(icon: "doc.on.doc", label: "Parent Document Retrieval", description: "Fetches surrounding chunks for full context", color: .green)
                    featureRow(icon: "lightbulb", label: "Query Understanding", description: "Resolves pronouns & clarifies ambiguous queries", color: .green)

                    // Deep Think and Maximum shared features
                    if settings.ragQualityMode.usesAgenticOrchestrator {
                        Divider()
                            .padding(.vertical, 4)
                        featureRow(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Iterative Retrieval", description: "Retrieve → assess → refine → retrieve more", color: .purple)
                        featureRow(icon: "brain.head.profile", label: "Agentic Orchestrator", description: "4-8 reasoning sessions (95% confidence)", color: .purple)
                        featureRow(icon: "hammer.fill", label: "12+ Tool Functions", description: "SearchDocs, GetFullDocument, ExpandContext, etc.", color: .purple)
                        featureRow(icon: "chart.bar.xaxis", label: "Confidence Tracking", description: "Stops when confident, escalates if uncertain", color: .purple)
                    }

                    // Maximum-exclusive features
                    if settings.ragQualityMode.isUnlimitedMode {
                        Divider()
                            .padding(.vertical, 4)
                        featureRow(icon: "infinity", label: "Unlimited Reasoning", description: "Up to 50 sessions until 98% confident", color: .orange)
                        featureRow(icon: "wand.and.stars", label: "Exhaustive Synthesis", description: "Final pass synthesizes all session insights", color: .orange)
                        featureRow(icon: "cpu", label: "200K+ Token Budget", description: "50 sessions × 4K = deep exploration", color: .orange)

                        // Warning for Maximum mode
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Can take several minutes. Use for complex research tasks.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    } else if !settings.ragQualityMode.usesAgenticOrchestrator {
                        featureRow(icon: "brain.head.profile", label: "Conversation Memory", description: "Remembers context across turns", color: .green)
                    }
                }
            }
            .padding(10)
            .background(modeAccentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.25), value: settings.ragQualityMode)
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func intelligenceModeRow(mode: RAGQualityMode, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? modeColor(for: mode).opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? modeColor(for: mode) : .secondary)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.subheadline.weight(.medium))
.foregroundColor(isSelected ? .primary : .secondary)
Text(mode.description)
    .font(.caption)
    .foregroundColor(.secondary)
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(modeColor(for: mode))
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
.padding(12)
    .background(isSelected ? modeColor(for: mode).opacity(0.08) : Color.secondary.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeColor(for mode: RAGQualityMode) -> Color {
        switch mode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .blue
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, label: String, description: String, color: Color = .green) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.medium))
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Appearance Card

    @ViewBuilder
    private var appearanceCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }

                Text("Appearance")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal)

            // Accent Color Row
            VStack(spacing: 0) {
                AccentColorSettingsRow(accentColorHex: $settings.appAccentColorHex)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
        }
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
                detail: "CoreML Neural Engine (384-dim)",
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
