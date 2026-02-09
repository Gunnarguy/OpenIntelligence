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
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
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

            // Motherboard HUD - Full-screen X-ray overlay
            // Shows glowing borders at the ACTUAL physical locations where
            // the Neural Engine, GPU, and CPU sit behind the screen
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false) // Don't block touches
                    .transition(.opacity)
            }
        }
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
                    Text("Maximum mode chains up to 50 reasoning sessions with verification gates (anti-hallucination), graph-based context packing, and calibrated confidence until 98% confident.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text("Deep Think chains 4-8 reasoning sessions with intent routing, extractive summarization for summaries, and verification gates. Stops when 85% confident.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Standard mode uses verification gates, graph context packing, and extractive QA. Activates multi-session reasoning for complex queries.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if settings.ragQualityMode.canonical == .maximum {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "flame.fill", label: "Total Budget", value: "200K+ tokens")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Effective", value: "16-32K tokens")
                    } else {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Chain Mode", value: "12K+ tokens")
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

            // GPU Acceleration Controls
            gpuAccelerationSection(deviceService: deviceService)

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

    // MARK: - GPU Acceleration Section

    @State private var gpuLevel: Double = DeviceCapabilityService.shared.gpuAccelerationLevel

    // Computed concurrency values that react to gpuLevel changes
    private var currentVisionConcurrency: Int {
        let gpuBoost = gpuLevel > 0.7
        let tier = DeviceCapabilityService.shared.tier
        switch tier {
        case .unsupported: return 2
        case .baseline: return gpuBoost ? 5 : 3
        case .enhanced: return gpuBoost ? 8 : 5
        case .advanced: return gpuBoost ? 10 : 6
        case .ultraAdvanced: return gpuBoost ? 12 : 8
        }
    }

    private var currentEmbeddingConcurrency: Int {
        let gpuBoost = gpuLevel > 0.7
        let tier = DeviceCapabilityService.shared.tier
        switch tier {
        case .unsupported: return 2
        case .baseline: return gpuBoost ? 10 : 6
        case .enhanced: return gpuBoost ? 14 : 8
        case .advanced: return gpuBoost ? 16 : 10
        case .ultraAdvanced: return gpuBoost ? 20 : 12
        }
    }

    private var currentOCRConcurrency: Int {
        let gpuBoost = gpuLevel > 0.7
        let tier = DeviceCapabilityService.shared.tier
        switch tier {
        case .unsupported: return 2
        case .baseline: return gpuBoost ? 6 : 4
        case .enhanced: return gpuBoost ? 10 : 6
        case .advanced: return gpuBoost ? 12 : 8
        case .ultraAdvanced: return gpuBoost ? 16 : 10
        }
    }
    private func gpuAccelerationSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("GPU Acceleration")
                    .font(.subheadline.weight(.medium))
                Spacer()

                // Mode badge
                Text(gpuModeName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(gpuModeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(gpuModeColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text("Higher GPU usage accelerates document ingestion but generates more heat. Neural Engine (ANE) is more efficient for ML inference.")
                .font(.caption)
                .foregroundColor(.secondary)

            // GPU Level Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GPU Level")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int(gpuLevel * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(gpuModeColor)
                        .contentTransition(.numericText())
                }

                Slider(value: $gpuLevel, in: 0...1, step: 0.1)
                    .accentColor(gpuModeColor)
                    .onChange(of: gpuLevel) { _, newValue in
                        // Save immediately for real-time updates
                        DeviceCapabilityService.shared.gpuAccelerationLevel = newValue
                    }

                // Mode descriptions
                HStack {
                    Text("🔋 Efficient")
                        .font(.caption2)
                        .foregroundColor(gpuLevel < 0.3 ? .green : .secondary)
                    Spacer()
                    Text("🔥 Maximum")
                        .font(.caption2)
                        .foregroundColor(gpuLevel >= 0.9 ? .red : .secondary)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.15), value: gpuLevel)

            // Current settings based on level - LIVE UPDATING
            VStack(alignment: .leading, spacing: 6) {
                gpuSettingRow(
                    icon: "cpu",
                    label: "CoreML Compute",
                    value: gpuLevel >= 0.9 ? "GPU + CPU" : (gpuLevel >= 0.6 ? "All (Auto)" : "Neural Engine")
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "PDF Processing",
                    value: gpuLevel >= 0.3 ? "GPU-Accelerated" : "CPU"
                )
                gpuSettingRow(
                    icon: "arrow.triangle.branch",
                    label: "Vision Concurrency",
                    value: gpuLevel > 0.7 ? "\(currentVisionConcurrency) pages ⚡" : "\(currentVisionConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "waveform",
                    label: "OCR Concurrency",
                    value: gpuLevel > 0.7 ? "\(currentOCRConcurrency) pages ⚡" : "\(currentOCRConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding Concurrency",
                    value: gpuLevel > 0.7 ? "\(currentEmbeddingConcurrency) parallel ⚡" : "\(currentEmbeddingConcurrency) parallel"
                )
                gpuSettingRow(
                    icon: "thermometer.medium",
                    label: "Thermal Impact",
                    value: gpuLevel >= 0.9 ? "🔥 High" : (gpuLevel >= 0.6 ? "⚠️ Moderate" : "✅ Low")
                )
            }
            .animation(.easeInOut(duration: 0.2), value: gpuLevel)

            // Speed estimate for 400-page PDF
            VStack(alignment: .leading, spacing: 4) {
                Text("📄 400-Page PDF Estimate")
                    .font(.caption.weight(.medium))
                let batches = 400 / currentVisionConcurrency
                let estimatedSeconds = batches * 2  // ~2s per batch average
                let minutes = estimatedSeconds / 60
                let seconds = estimatedSeconds % 60
                Text("~\(minutes)m \(seconds)s extraction • \(batches) batches")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Warning for high GPU mode
            if gpuLevel >= 0.9 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Maximum GPU mode may cause device heating during large document ingestion.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            gpuLevel = DeviceCapabilityService.shared.gpuAccelerationLevel
        }
    }

    private var gpuModeName: String {
        if gpuLevel >= 0.9 { return "Maximum" }
        if gpuLevel >= 0.6 { return "Performance" }
        if gpuLevel >= 0.3 { return "Balanced" }
        return "Efficient"
    }

    private var gpuModeColor: Color {
        if gpuLevel >= 0.9 { return .red }
        if gpuLevel >= 0.6 { return .orange }
        if gpuLevel >= 0.3 { return .green }
        return .blue
    }

    @ViewBuilder
    private func gpuSettingRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.green)
                .frame(width: 16)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
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
                            let previousMode = settings.ragQualityMode.canonical
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                settings.ragQualityMode = mode
                            }
                            DSHaptics.selection()

                            // Reset Deep Think/Maximum metrics when switching modes
                            // to avoid stale confidence/step counts appearing in the UI
                            if previousMode != mode {
                                ragService.resetDeepThinkLiveMetrics()
                            }
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
                    // Common features for all modes (Ingestion & Retrieval)
                    featureRow(icon: "doc.badge.gearshape", label: "Contextual Embeddings", description: "Document title + section baked into every vector", color: .green)
                    featureRow(icon: "tablecells", label: "Smart Table Extraction", description: "iOS 26 Vision API preserves tables with captions", color: .green)
                    featureRow(icon: "link", label: "Cross-Document Entity Linking", description: "Global entity index finds related info across library", color: .green)
                    featureRow(icon: "doc.on.doc", label: "Parent Document Retrieval", description: "Expands chunk window ±5 for full paragraph context", color: .green)
                    featureRow(icon: "lightbulb", label: "Query Understanding", description: "NLTagger resolves pronouns, NER extracts key entities", color: .green)
                    featureRow(icon: "arrow.triangle.merge", label: "Hybrid Search + RRF", description: "Vector + BM25 keyword search with Reciprocal Rank Fusion", color: .green)
                    featureRow(icon: "arrow.up.arrow.down", label: "Cross-Encoder Reranking", description: "TinyBERT reranker scores query-document relevance", color: .green)
                    featureRow(icon: "shuffle", label: "MMR Diversification", description: "Maximal Marginal Relevance for diverse results", color: .green)
                    featureRow(icon: "arrow.left.arrow.right", label: "Lost-in-Middle Mitigation", description: "Best evidence at start AND end of context window", color: .green)
                    featureRow(icon: "tree", label: "RAPTOR-lite Summaries", description: "Document-level summaries route overview queries", color: .green)

                    // Standard mode only features
                    if !settings.ragQualityMode.usesAgenticOrchestrator {
                        Divider()
                            .padding(.vertical, 4)
                        featureRow(icon: "sparkles", label: "HyDE Query Expansion", description: "LLM generates hypothetical doc, embedded for cosine retrieval", color: .blue)
                        featureRow(icon: "text.redaction", label: "Contextual Compression", description: "LLM extracts query-relevant sentences from chunks", color: .blue)
                    }

                    // Deep Think and Maximum shared features
                    if settings.ragQualityMode.usesAgenticOrchestrator {
                        Divider()
                            .padding(.vertical, 4)
                        featureRow(icon: "signpost.right.and.left", label: "Intent Routing", description: "Classifies query as lookup/procedure/compare/summarize", color: .purple)
                        featureRow(icon: "magnifyingglass.circle.fill", label: "Multi-Query Decomposition", description: "LLM generates 4-5 sub-queries for faceted retrieval", color: .purple)
                        featureRow(icon: "point.3.connected.trianglepath.dotted", label: "2-Hop Graph Expansion", description: "Entity-based traversal finds related chunks", color: .purple)
                        featureRow(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Recursive Research Loop", description: "Autonomous [SEARCH:]/[ANSWER] protocol until confident", color: .purple)
                        featureRow(icon: "checkmark.seal.fill", label: "Verification Gates A-D", description: "4-stage anti-hallucination checks before answering", color: .purple)
                        featureRow(icon: "function", label: "Confidence Calibration", description: "Platt-scaled scores from rerank + margin + coverage", color: .purple)
                        featureRow(icon: "text.line.first.and.arrowtriangle.forward", label: "Extractive Summarization", description: "Sentence selection via bi-encoder for summarize intent", color: .purple)
                        featureRow(icon: "rectangle.compress.vertical", label: "Graph Context Packing", description: "Optimal token budget allocation across evidence", color: .purple)
                        featureRow(icon: "brain.head.profile", label: "Agentic Orchestrator", description: "4-8 dynamic sessions targeting 85% confidence", color: .purple)
                        featureRow(icon: "hammer.fill", label: "8 @Tool Functions", description: "SearchDocs, ListDocs, GetSummary, CountPattern, ExactSearch, Stats, Related, Compare", color: .purple)
                        featureRow(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Iterative Retrieval", description: "Retrieve → assess gaps → refine query → retrieve more", color: .purple)
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

                Divider()
                    .padding(.horizontal)

                // Silicon HUD Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silicon HUD")
                            .font(.subheadline.weight(.medium))
                        Text("X-ray view of \(DeviceComponentLayout.current.chipName) activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.showSiliconHUD)
                        .labelsHidden()
                        .tint(.purple)
                        .onChange(of: settings.showSiliconHUD) { _, _ in
                            DSHaptics.toggle()
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                // HUD Customization (only show when HUD is enabled)
                if settings.showSiliconHUD {
                    Divider()
                        .padding(.horizontal)

                    // Glow Intensity Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Glow Intensity")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(settings.hudGlowIntensity * 100))%")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundColor(.purple)
                        }
                        Slider(value: $settings.hudGlowIntensity, in: 0.1...1.0, step: 0.1)
                            .tint(.purple)
                            .onChange(of: settings.hudGlowIntensity) { _, _ in
                                DSHaptics.tick()
                            }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal)

                    // Show Metrics Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Metrics")
                                .font(.caption.weight(.medium))
                            Text("Show ops count and latency in legend")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.hudShowMetrics)
                            .labelsHidden()
                            .tint(.cyan)
                            .onChange(of: settings.hudShowMetrics) { _, _ in
                                DSHaptics.toggle()
                            }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal)

                    // Show Taptic Engine Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taptic Engine")
                                .font(.caption.weight(.medium))
                            Text("Show haptic motor activity on HUD")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.hudShowTaptic)
                            .labelsHidden()
                            .tint(.pink)
                            .onChange(of: settings.hudShowTaptic) { _, _ in
                                DSHaptics.toggle()
                            }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
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
