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
    @EnvironmentObject private var containerService: ContainerService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @EnvironmentObject private var workspaceSyncService: WorkspaceSyncService
    @Environment(\.openURL) private var openURL

    // Note: SystemStateMonitor moved to LiveSystemMonitorWrapper to avoid full-view redraws

    @State private var deviceCapabilities = DeviceCapabilities()
    @State private var pipelineStages: [ModelPipelineStage] = []
    @State private var showPlanSheet = false
    @State private var planEntryPoint: PlanUpgradeEntryPoint = .settings
    @State private var showAdvancedGeneration = false
    @State private var isRefreshingSharedWorkspace = false
    @State private var sharedWorkspaceRefreshMessage: String?

    private static let sharedWorkspaceRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var iCloudLibraryCount: Int {
        containerService.containers.filter { $0.syncMode == .iCloudShared }.count
    }

    private var hasConfiguredICloudLibraries: Bool {
        iCloudLibraryCount > 0
    }

    private var localOnlyLibraryCount: Int {
        max(containerService.containers.count - iCloudLibraryCount, 0)
    }

    private var activeLibrary: KnowledgeContainer? {
        containerService.activeContainer
    }

    private var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Hero & Core Experience
                    heroCard
                    modelSelectionCard

                    // Privacy & Execution (combined)
                    privacyExecutionCard

                    // Shared Workspace Sync
                    sharedWorkspaceCard

                    // Subscription
                    billingCard

                    // Intelligence Mode (Standard vs Deep Think)
                    retrievalCard

                    // Apple Intelligence Features
                    appleIntelligenceFeaturesCard

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
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .navigationBarTitleDisplayMode(.inline)
.sheet(isPresented: $showPlanSheet) {
            PlanUpgradeSheet(entryPoint: planEntryPoint)
        }
.onAppear {
    deviceCapabilities = RAGService.checkDeviceCapabilities()
    entitlementStore.refreshTransientState()
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
                    text: "On-Device First",
                    active: deviceCapabilities.supportsFoundationModels
                )
                statusPill(
                    icon: "cloud.fill",
                    text: "PCC Available",
                    active: deviceCapabilities.supportsPrivateCloudCompute && settings.applePCCConsent != .denied
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
                    Image(systemName: entitlementStore.effectiveTier == .free ? "arrow.up.circle" : "gearshape")
                    Text(entitlementStore.effectiveTier == .free ? "Upgrade Plan" : "View Plans")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
.font(.subheadline.weight(.medium))
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(entitlementStore.effectiveTier == .free ? Color.accentColor : Color.accentColor.opacity(0.1))
    .foregroundColor(entitlementStore.effectiveTier == .free ? .white : .accentColor)
    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Show quota info
            HStack(spacing: 16) {
                quotaItem(
                    icon: "doc.text",
                    value: entitlementStore.documentLimitDisplayText,
                    label: "Documents"
                )
                quotaItem(
                    icon: "folder",
                    value: "\(entitlementStore.libraryLimit)",
                    label: "Libraries"
                )
            }

            if entitlementStore.activeTier == .free, entitlementStore.isLegacyPaidProtected {
                Text("Previous paid purchases on this Apple ID now unlock Lifetime access on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entitlementStore.effectiveTier == .lifetime {
                lifetimeSupporterBanner
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var subscriptionStatusText: String {
        switch entitlementStore.effectiveTier {
        case .free:
            return "Free tier • Maximum \(QuotaPolicy.freeMaximumModeDailyLimit)/day"
        case .pro:
            return "Pro plan • Unlimited Maximum"
        case .lifetime:
            if entitlementStore.activeTier == .free, entitlementStore.isLegacyPaidProtected {
                return "Lifetime access • Grandfathered from prior purchase"
            }
            return "Lifetime • Everything unlocked"
        }
    }

    @ViewBuilder
    private var tierBadge: some View {
        Text(entitlementStore.effectiveTier.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tierBadgeColor.opacity(0.15))
            .foregroundColor(tierBadgeColor)
            .clipShape(Capsule())
    }

    private var tierBadgeColor: Color {
        switch entitlementStore.effectiveTier {
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

    @ViewBuilder
    private var lifetimeSupporterBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.orange)
                Text("Lifetime Cohort")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Forever unlocked")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.16))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }

            Text("Thanks for backing OpenIntelligence early. Lifetime keeps unlimited documents and 20 libraries unlocked with no recurring subscription.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "Settings Screen"))
                } label: {
                    Label("Send Feedback", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openURL(OpenIntelligenceLinks.appStoreURL)
                } label: {
                    Label("App Store", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Text("~3B parameters • 2-bit QAT • Apple Silicon optimized")
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
                    Text("Primarily on-device processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
.fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("On-Device")
                        .font(.caption2.weight(.medium))
.foregroundColor(.green)
                }
            }

            // On-Device Execution Explanation
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.gen3")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("On-Device First Execution")
                        .font(.subheadline.weight(.medium))
                }

                Text("All AI inference runs on your device using Apple's ~3B Foundation Model via the Neural Engine, GPU, and CPU. Apple's FoundationModels framework may automatically route to Private Cloud Compute if context exceeds on-device capacity, but that routing is handled by Apple — OpenIntelligence does not run its own servers.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // On-device benefits
                VStack(alignment: .leading, spacing: 6) {
                    pccBenefitRow(icon: "checkmark.shield.fill", text: "Works fully offline — no OpenIntelligence backend", color: .green)
                    pccBenefitRow(icon: "eye.slash.fill", text: "No data sent to OpenIntelligence or any developer-operated service", color: .green)
                    pccBenefitRow(icon: "bolt.fill", text: "Low latency — primarily on-device inference", color: .blue)
                    pccBenefitRow(icon: "cpu", text: "Neural Engine + GPU + CPU (Apple Silicon)", color: .purple)
                    pccBenefitRow(icon: "icloud.and.arrow.up", text: "Apple may route to PCC for complex queries (encrypted, zero retention)", color: .secondary)
                }
                .padding(.leading, 4)
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()

            // Private Cloud Compute context
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("About Private Cloud Compute")
                        .font(.subheadline.weight(.medium))
                }

                Text("Apple's Private Cloud Compute (PCC) is Apple's secure cloud extension for Apple Intelligence. When you allow it and a request benefits from additional capacity, Apple may route eligible processing there. OpenIntelligence does not operate its own servers.")
                    .font(.caption)
.foregroundColor(.secondary)

                // PCC info (what it is and when Apple may use it)
                VStack(alignment: .leading, spacing: 6) {
                    pccBenefitRow(icon: "lock.shield.fill", text: "PCC: Apple-operated, end-to-end encrypted, zero retention", color: .secondary)
                    pccBenefitRow(icon: "doc.viewfinder", text: "Cryptographically verifiable by security researchers", color: .secondary)
                    pccBenefitRow(icon: "info.circle", text: "Used only for eligible requests when Apple Intelligence and your consent allow it", color: .accentColor)
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
    private var sharedWorkspaceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Libraries")
                        .font(.headline)
                    Text("Each library chooses Local Only or iCloud Drive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Text(sharedWorkspaceModeLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(sharedWorkspaceModeColor.opacity(0.15))
                    .foregroundColor(sharedWorkspaceModeColor)
                    .clipShape(Capsule())
            }

            Text(sharedWorkspaceSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let compatibilityMessage = workspaceSyncService.syncCompatibilityMessage,
               hasConfiguredICloudLibraries {
                Text(compatibilityMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
               hasConfiguredICloudLibraries {
                VStack(alignment: .leading, spacing: 10) {
                        Text("Review iCloud library changes")
                        .font(.subheadline.weight(.semibold))

                        Text("Only libraries marked iCloud Drive are involved here. This device currently has \(bootstrapConflict.localLibraryCount) libraries marked iCloud Drive / \(bootstrapConflict.localDocumentCount) documents, and iCloud already has \(bootstrapConflict.sharedLibraryCount) shared librar\(bootstrapConflict.sharedLibraryCount == 1 ? "y" : "ies") / \(bootstrapConflict.sharedDocumentCount) documents.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !bootstrapConflict.localOnlyLibraryNames.isEmpty {
                        Text("Only on this device: \(bootstrapConflict.localOnlyLibraryNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if !bootstrapConflict.sharedOnlyLibraryNames.isEmpty {
                        Text("Only in iCloud: \(bootstrapConflict.sharedOnlyLibraryNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text("Share Device Libraries to iCloud")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text("Add iCloud Libraries Here")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }

                        VStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text("Share Device Libraries to iCloud")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text("Add iCloud Libraries Here")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }
                    }

                    Text("Share Device Libraries to iCloud publishes the libraries listed as only on this device. Add iCloud Libraries Here pulls in the libraries listed as only in iCloud, while any unmatched iCloud-marked libraries on this device are kept as Local Only so they are not deleted.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !workspaceSyncService.requiresBootstrapDecision {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openURL(OpenIntelligenceDeepLink.documentsURL)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.caption.weight(.semibold))
                            Text("Manage in Documents")
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Change Local Only or iCloud Drive per library, and refresh shared libraries, from the Documents screen.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let syncActivitySummary {
                Text(syncActivitySummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(workspaceSyncService.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            if let sharedWorkspaceRefreshMessage {
                Text(sharedWorkspaceRefreshMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let rootDescription = workspaceSyncService.workspaceRootDescription, workspaceSyncService.isUsingSharedWorkspace {
                Text(rootDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                    .textSelection(.enabled)
            }

            if let lastErrorMessage = workspaceSyncService.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var syncActivitySummary: String? {
        if let lastSuccessfulSyncAt = workspaceSyncService.lastSuccessfulSyncAt {
            let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
                for: lastSuccessfulSyncAt,
                relativeTo: Date()
            )
            return "Last synced \(relativeDescription)."
        }

          guard hasConfiguredICloudLibraries,
              let lastSyncAttemptAt = workspaceSyncService.lastSyncAttemptAt
        else {
            return nil
        }

        let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
            for: lastSyncAttemptAt,
            relativeTo: Date()
        )
        return "Last checked \(relativeDescription)."
    }

    private var sharedWorkspaceModeLabel: String {
        if workspaceSyncService.isUsingSharedWorkspace {
            return "iCloud Drive"
        }

        if !hasConfiguredICloudLibraries {
            return "Local Only"
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return "Choose"
        }

        if workspaceSyncService.syncCompatibilityMessage != nil {
            return "Unsupported"
        }

        if workspaceSyncService.lastErrorMessage != nil {
            return "Unavailable"
        }

        return "Preparing"
    }

    private var sharedWorkspaceModeColor: Color {
        if workspaceSyncService.isUsingSharedWorkspace {
            return .green
        }

        if !hasConfiguredICloudLibraries {
            return .secondary
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return .accentColor
        }

        if workspaceSyncService.syncCompatibilityMessage != nil || workspaceSyncService.lastErrorMessage != nil {
            return .orange
        }

        return .accentColor
    }

    private var sharedWorkspaceSummary: String {
        if !hasICloudSyncAccess {
            return "iCloud library sync is available on Pro and Lifetime. Local Only keeps each library device-specific."
        }

        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local. Libraries marked iCloud Drive use iCloud as the shared copy. Local Only libraries stay on just this device."
        }

        return "All libraries are Local Only right now. Turn iCloud Drive on per library when you want it on another device."
    }

    @MainActor
    private func resolvePendingBootstrap(_ choice: WorkspaceSyncService.BootstrapChoice) {
        guard hasICloudSyncAccess else {
            planEntryPoint = .iCloudSync
            showPlanSheet = true
            return
        }

        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        sharedWorkspaceRefreshMessage = nil

        Task { @MainActor in
            defer { isRefreshingSharedWorkspace = false }

            _ = await workspaceSyncService.resolvePendingBootstrap(using: choice)

            guard workspaceSyncService.isUsingSharedWorkspace else {
                sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
                return
            }

            containerService.reloadFromDisk()
            ragService.reloadWorkspaceData()
            sharedWorkspaceRefreshMessage = choice == .mergeLibraries
                ? "This device's iCloud-marked libraries were shared to iCloud, and iCloud libraries were pulled in here."
                : "Libraries already in iCloud were added here. Any unmatched iCloud-marked libraries on this device were kept as Local Only."
        }
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
                    deviceCapabilityPill(icon: "brain.head.profile", label: "Deep Think", value: "\(deviceService.optimizedAgenticConfig().maxSteps) max sessions")
                    deviceCapabilityPill(icon: "flame", label: "Thermal", value: deviceService.hasThermalHeadroom ? "High" : "Standard")
                }
            }
.padding(10)
.background(Color.purple.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()

            hardwareEnvelopeSection(deviceService: deviceService)

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
                let agenticConfig = DeviceCapabilityService.shared.optimizedAgenticConfig()
                if settings.ragQualityMode.canonical == .maximum {
                    Text("Maximum mode chains up to 50 serial reasoning sessions, each with a 4K-token Apple FM window. Compressed insights pass between sessions via Self-RAG 2.0 enrichment. Stops at 98% confidence. Minimum 8 sessions before early stop.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text("Deep Think chains \(max(4, agenticConfig.maxSteps - 2))–\(agenticConfig.maxSteps) serial reasoning sessions (device-optimized for your \(DeviceCapabilityService.shared.chipName)). Each session gets a fresh 4K-token window with compressed prior insights. Stops at \(Int(agenticConfig.confidenceThreshold * 100))% confidence.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Standard mode runs a single 4K-token LLM pass with verification gates and graph context packing. It stays single-pass by default; use Deep Think or Maximum when you want multi-session reasoning.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if settings.ragQualityMode.canonical == .maximum {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "flame.fill", label: "Sessions", value: "Up to 50")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        let maxSessions = agenticConfig.maxSteps
                        let effectiveTokens = maxSessions * 4096
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Sessions", value: "\(max(4, maxSessions - 2))–\(maxSessions) (\(effectiveTokens / 1000)K effective)")
                    } else {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Single Pass", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "If Complex", value: "3 sessions (12K)")
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

                Text("Apple Intelligence supports multiple languages for text generation. OCR and document processing support additional languages via Vision and NaturalLanguage frameworks.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Language list — verified Apple Intelligence languages as of iOS 18.4+
                Text("English, Spanish, French, German, Italian, Japanese, Korean, Portuguese, Chinese, Hindi, Vietnamese, Indonesian, Thai, Dutch, Arabic, Turkish, Polish, Romanian, Swedish")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))

                Text("On-device Foundation Model language support may vary. Apple routes automatically.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
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
            private func hardwareEnvelopeSection(deviceService: DeviceCapabilityService) -> some View {
                let envelope = deviceService.hardwareExecutionEnvelope
                let minImageBudgetMB = envelope.pdfPageMemory360MB * envelope.pdfRenderSlots
                let maxImageBudgetMB = envelope.pdfPageMemory432MB * envelope.pdfRenderSlots
                let imageBudgetText = "\(envelope.pdfRenderSlots) pages • ~\(minImageBudgetMB)-\(maxImageBudgetMB) MB @ adaptive 360-432 DPI"
                let gpuCeilingText: String = {
                    if envelope.activeGPUAccelerationLevel < envelope.requestedGPUAccelerationLevel {
                        return "\(Int(envelope.activeGPUAccelerationLevel * 100))% active of \(Int(envelope.requestedGPUAccelerationLevel * 100))% requested"
                    }
                    return "Up to \(Int(envelope.maxSafeGPUAccelerationLevel * 100))% safe on this device"
                }()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .font(.caption)
                            .foregroundColor(.indigo)
                        Text("Hardware Envelope")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Core ML + Metal")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text("These ceilings come from public hardware signals the app can inspect safely: device ID, chip mapping, RAM, Metal working-set budget, threadgroup limits, and crash-tested Vision/Core ML guardrails. Apple does not expose live Neural Engine occupancy.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        hardwareLimitRow(icon: "number", label: "Device ID", value: envelope.deviceIdentifier)
                        hardwareLimitRow(icon: "memorychip", label: "Metal Device", value: envelope.metal.deviceName)
                        hardwareLimitRow(icon: "square.stack.3d.up", label: "Unified Memory", value: "\(envelope.metal.hasUnifiedMemory ? "Yes" : "No") • \(envelope.metal.workingSetDescription) working set")
                        hardwareLimitRow(icon: "square.grid.3x3.fill", label: "Threadgroup Ceiling", value: "\(envelope.metal.maxThreadsPerThreadgroup) threads • \(envelope.metal.maxThreadgroupMemoryKB) KB shared")
                        hardwareLimitRow(icon: "gauge.with.needle", label: "GPU Ceiling", value: gpuCeilingText)
                        hardwareLimitRow(icon: "cpu", label: "CoreML Route", value: envelope.coreMLRoute)
                        hardwareLimitRow(icon: "text.badge.checkmark", label: "Embedding Route", value: envelope.embeddingRoute)
                        hardwareLimitRow(icon: "eye.fill", label: "Vision OCR Ceiling", value: "\(envelope.visionOperationConcurrency) ops • \(envelope.visionCooldownMilliseconds) ms cooldown")
                        hardwareLimitRow(icon: "photo.stack", label: "Adaptive PDF Budget", value: imageBudgetText)
                        hardwareLimitRow(icon: "function", label: "Vector Search Ceiling", value: "\(envelope.vectorBatchSize) batch • matrix @ \(envelope.batchMatrixMultiplyThreshold)+")
                    }
                }
                .padding(12)
                .background(Color.indigo.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            @ViewBuilder
            private func hardwareLimitRow(icon: String, label: String, value: String) -> some View {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundColor(.indigo)
                        .frame(width: 16)
                    Text(label)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(value)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
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

            Text("Vector math uses Apple's Accelerate framework (vDSP/BLAS) for CPU SIMD acceleration. Metal shaders handle bulk cosine similarity and MMR diversity when GPU level ≥ 60%. Batch sizes are tuned for your \(deviceService.chipName).")
                .font(.caption)
                .foregroundColor(.secondary)

            // Optimizations grid
            VStack(alignment: .leading, spacing: 6) {
                siliconFeatureRow(
                    icon: "function",
                    label: "vDSP Vector Math",
                    detail: "CPU SIMD-accelerated similarity"
                )
                siliconFeatureRow(
                    icon: "square.grid.3x3.fill",
                    label: "Metal GPU Shaders",
                    detail: "3-tier: threadgroup/SIMD4/scalar"
                )
                siliconFeatureRow(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Semantic Chunking",
                    detail: "Topic boundaries via embeddings"
                )
                siliconFeatureRow(
                    icon: "lock.fill",
                    label: "Library Isolation",
                    detail: "Queries stay scoped to the active library"
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
                siliconInfoPill(
                    icon: "square.grid.3x3.fill",
                    label: "Matrix @",
                    value: "\(deviceService.batchMatrixMultiplyThreshold)+"
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

    // GPU concurrency from DeviceCapabilityService (reflects actual pipeline values)
    private var currentGPUConcurrency: Int {
        DeviceCapabilityService.shared.gpuConcurrency
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

            if deviceService.activeGPUAccelerationLevel < gpuLevel {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\(deviceService.chipName) is holding active GPU to \(Int(deviceService.activeGPUAccelerationLevel * 100))% even though \(Int(gpuLevel * 100))% was requested. This ceiling is deliberate to avoid unstable sustained loads.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // GPU Level Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GPU Level")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(gpuLevelSummary(deviceService: deviceService))
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

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Adaptive Visual Ingestion")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("Automatic")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text("PDFs and images now use one automatic source-preservation strategy. The engine raises OCR detail, structure recovery, and visual analysis when pages are garbled, table-heavy, columnar, image-heavy, or small-text risky, and stays lighter on clean text-native pages.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Current settings based on level - LIVE UPDATING
            VStack(alignment: .leading, spacing: 6) {
                gpuSettingRow(
                    icon: "cpu",
                    label: "CoreML Compute",
                    value: deviceService.preferredComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "PDF Rendering",
                    value: gpuLevel >= 0.3 ? "Metal CIContext (GPU)" : "CPU CIContext"
                )
                gpuSettingRow(
                    icon: "function",
                    label: "Metal Vector Ops",
                    value: gpuLevel >= 0.6 ? "Active (cosine/MMR/normalize)" : "Off (Accelerate CPU)"
                )
                gpuSettingRow(
                    icon: "square.stack.3d.up",
                    label: "GPU Op Concurrency",
                    value: "\(currentGPUConcurrency) concurrent"
                )
                gpuSettingRow(
                    icon: "thermometer.medium",
                    label: "Thermal Impact",
                    value: gpuLevel >= 0.9 ? "🔥 High" : (gpuLevel >= 0.6 ? "⚠️ Moderate" : "✅ Low")
                )
            }
            .animation(.easeInOut(duration: 0.2), value: gpuLevel)

            Divider()
                .padding(.vertical, 2)

            // Pipeline concurrency (tier-based, not GPU-slider dependent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipeline Concurrency")
                    .font(.caption.weight(.medium))
                Text("Set by device tier, not GPU slider. Optimized for your \(deviceService.chipName).")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Vision Parsing",
                    value: "\(deviceService.visionParsingConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "waveform",
                    label: "OCR Extraction",
                    value: "\(deviceService.ocrExtractionConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "photo.stack",
                    label: "PDF Render Slots",
                    value: "\(deviceService.pdfRenderingConcurrency) concurrent (adaptive 360/432 DPI)"
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding",
                    value: "\(deviceService.embeddingConcurrency) parallel"
                )
            }
            .animation(.easeInOut(duration: 0.2), value: gpuLevel)

            // Speed estimate for 400-page PDF
            VStack(alignment: .leading, spacing: 4) {
                Text("📄 400-Page PDF Estimate")
                    .font(.caption.weight(.medium))
                let renderSlots = deviceService.pdfRenderingConcurrency
                let batches = 400 / renderSlots
                let fastestSeconds = batches * 3
                let slowestSeconds = batches * 5
                let fastMinutes = fastestSeconds / 60
                let fastRemainder = fastestSeconds % 60
                let slowMinutes = slowestSeconds / 60
                let slowRemainder = slowestSeconds % 60
                Text("~\(fastMinutes)m \(fastRemainder)s to \(slowMinutes)m \(slowRemainder)s extraction • \(batches) batches of \(renderSlots) pages • adaptive visual ingestion")
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

    private func gpuLevelSummary(deviceService: DeviceCapabilityService) -> String {
        let requested = Int(gpuLevel * 100)
        let active = Int(deviceService.activeGPUAccelerationLevel * 100)
        if active < requested {
            return "\(requested)% req / \(active)% act"
        }
        return "\(requested)%"
    }

    private var gpuModeName: String {
        let level = DeviceCapabilityService.shared.activeGPUAccelerationLevel
        if level >= 0.9 { return "Maximum" }
        if level >= 0.6 { return "Performance" }
        if level >= 0.3 { return "Balanced" }
        return "Efficient"
    }

    private var gpuModeColor: Color {
        let level = DeviceCapabilityService.shared.activeGPUAccelerationLevel
        if level >= 0.9 { return .red }
        if level >= 0.6 { return .orange }
        if level >= 0.3 { return .green }
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
        modeColor(for: settings.ragQualityMode.canonical)
    }

    private var modeHeaderIcon: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "flame.fill"
        case .deepThink: return "brain.head.profile.fill"
        default: return "bolt.circle.fill"
        }
    }

    private var modeHeaderTitle: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "Maximum Highlights"
        case .deepThink: return "Deep Think Highlights"
        default: return "Standard Highlights"
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
                            guard canSelectMode(mode) else { return }
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

                // Data-driven feature list — avoids stack overflow from
                // 25+ inline featureRow calls generating a massive generic type.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(currentModeFeatures) { feature in
                        if feature.isDivider {
                            Divider()
                                .padding(.vertical, 4)
                        } else if feature.isWarning {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(feature.label)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        } else {
                            featureRow(icon: feature.icon, label: feature.label, description: feature.desc, color: feature.color)
                        }
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

    // MARK: - Feature List Data Model

    /// Lightweight value type for data-driven feature rows.
    /// Using ForEach with Identifiable items instead of 25+ inline @ViewBuilder
    /// calls prevents the compiler from generating a massive nested generic
    /// type, which was causing a stack overflow (___chkstk_darwin crash).
    private struct FeatureItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let desc: String
        let color: Color
        var isDivider: Bool = false
        var isWarning: Bool = false

        static func divider(id: String) -> FeatureItem {
            FeatureItem(id: id, icon: "", label: "", desc: "", color: .clear, isDivider: true)
        }

        static func warning(id: String, text: String) -> FeatureItem {
            FeatureItem(id: id, icon: "exclamationmark.triangle.fill", label: text, desc: "", color: .orange, isWarning: true)
        }
    }

    /// Build the feature list as data, not views.
    private var currentModeFeatures: [FeatureItem] {
        var items: [FeatureItem] = []

        // Common features (all modes)
        items.append(.init(id: "contextual-embed", icon: "doc.badge.gearshape", label: "Contextual Embeddings", desc: "Document title + section baked into every vector", color: .green))
        items.append(.init(id: "table-extract", icon: "tablecells", label: "Smart Table Extraction", desc: "iOS 26 Vision API preserves tables with captions", color: .green))
        items.append(.init(id: "entity-link", icon: "link", label: "Cross-Document Entity Linking", desc: "Global entity index finds related info across library", color: .green))
        items.append(.init(id: "parent-doc", icon: "doc.on.doc", label: "Parent Document Retrieval", desc: "Expands chunk window ±5 for full paragraph context", color: .green))
        items.append(.init(id: "query-understand", icon: "lightbulb", label: "Query Understanding", desc: "NLTagger resolves pronouns, NER extracts key entities", color: .green))
        items.append(.init(id: "hybrid-rrf", icon: "arrow.triangle.merge", label: "Hybrid Search + RRF", desc: "Vector + BM25 keyword search with Reciprocal Rank Fusion", color: .green))
        items.append(.init(id: "cross-encoder", icon: "arrow.up.arrow.down", label: "Cross-Encoder Reranking", desc: "TinyBERT reranker scores query-document relevance", color: .green))
        items.append(.init(id: "mmr", icon: "shuffle", label: "MMR Diversification", desc: "Maximal Marginal Relevance for diverse results", color: .green))
        items.append(.init(id: "lost-middle", icon: "arrow.left.arrow.right", label: "Lost-in-Middle Mitigation", desc: "Best evidence at start AND end of context window", color: .green))
        items.append(.init(id: "raptor", icon: "tree", label: "RAPTOR-lite Summaries", desc: "Document-level summaries route overview queries", color: .green))
        items.append(.init(id: "hyde", icon: "sparkles", label: "HyDE Query Expansion", desc: "LLM generates hypothetical doc, embedded for cosine retrieval", color: .green))

        // Standard + Deep Think (disabled in Maximum which keeps full context)
        if !settings.ragQualityMode.isUnlimitedMode {
            items.append(.init(id: "compression", icon: "text.redaction", label: "Contextual Compression", desc: "LLM extracts query-relevant sentences from chunks", color: settings.ragQualityMode.usesAgenticOrchestrator ? .purple : .blue))
        }

        // Deep Think + Maximum shared
        if settings.ragQualityMode.usesAgenticOrchestrator {
            items.append(.divider(id: "div-agentic"))
            items.append(.init(id: "intent-route", icon: "signpost.right.and.left", label: "Intent Routing", desc: "Classifies query as lookup/procedure/compare/summarize", color: .purple))
            items.append(.init(id: "multi-query", icon: "magnifyingglass.circle.fill", label: "Multi-Query Expansion", desc: "LLM generates diverse search queries for broader retrieval", color: .purple))
            items.append(.init(id: "graph-expand", icon: "point.3.connected.trianglepath.dotted", label: "2-Hop Graph Expansion", desc: "Entity-based traversal finds related chunks", color: .purple))
            items.append(.init(id: "recursive-loop", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Recursive Research Loop", desc: "Autonomous [SEARCH:]/[ANSWER] protocol until confident", color: .purple))
            items.append(.init(id: "verify-gates", icon: "checkmark.seal.fill", label: "Verification Gates A–G", desc: "7-stage anti-hallucination checks before answering", color: .purple))
            items.append(.init(id: "confidence-cal", icon: "function", label: "Confidence Calibration", desc: "Sigmoid-calibrated scores from rerank + margin + evidence count", color: .purple))
            items.append(.init(id: "extract-summary", icon: "text.line.first.and.arrowtriangle.forward", label: "Extractive Summarization", desc: "Sentence selection via bi-encoder for summarize intent", color: .purple))
            items.append(.init(id: "graph-pack", icon: "rectangle.compress.vertical", label: "Graph Context Packing", desc: "Optimal token budget allocation across evidence", color: .purple))
            items.append(.init(id: "orchestrator", icon: "brain.head.profile", label: "Agentic Orchestrator", desc: "\(max(4, DeviceCapabilityService.shared.optimizedAgenticConfig().maxSteps - 2))–\(DeviceCapabilityService.shared.optimizedAgenticConfig().maxSteps) sessions targeting \(Int(DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold * 100))% confidence", color: .purple))
            items.append(.init(id: "tool-funcs", icon: "hammer.fill", label: "8 Tool Functions", desc: "SearchDocs, ListDocs, GetSummary, CountPattern, ExactSearch, Stats, Related, Compare", color: .purple))
            items.append(.init(id: "iterative-ret", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Iterative Retrieval", desc: "Retrieve → assess gaps → refine query → retrieve more", color: .purple))
        }

        // Maximum-exclusive
        if settings.ragQualityMode.isUnlimitedMode {
            items.append(.divider(id: "div-maximum"))
            if entitlementStore.hasUnlimitedMaximumMode {
                items.append(.init(id: "maximum-access", icon: "infinity", label: "Unlimited Maximum", desc: "No daily cap on your current plan", color: .orange))
            } else {
                items.append(.init(id: "maximum-access", icon: "calendar", label: "Maximum on Free", desc: "\(entitlementStore.maximumModeRemainingUses) of \(QuotaPolicy.freeMaximumModeDailyLimit) uses left today", color: .orange))
            }
            items.append(.init(id: "exhaustive", icon: "wand.and.stars", label: "Exhaustive Synthesis", desc: "Final pass synthesizes all session insights", color: .orange))
            items.append(.init(id: "token-budget", icon: "cpu", label: "200K+ Token Budget", desc: "50 sessions × 4K = deep exploration", color: .orange))
            items.append(.warning(id: "max-warning", text: "Can take several minutes. Use for complex research tasks."))
        } else if !settings.ragQualityMode.usesAgenticOrchestrator {
            items.append(.init(id: "conv-memory", icon: "brain.head.profile", label: "Conversation Memory", desc: "Remembers context across turns", color: .green))
        }

        return items
    }

    @ViewBuilder
    private func intelligenceModeRow(mode: RAGQualityMode, isSelected: Bool) -> some View {
        let accent = modeColor(for: mode)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 42, height: 42)
                    Image(systemName: mode.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? accent : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isSelected ? .primary : .secondary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accent)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }

            Text(modeCallout(for: mode))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(modeBadges(for: mode), id: \.self) { badge in
                    modeBadge(text: badge, color: accent)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? accent.opacity(0.08) : Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? accent.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func modeColor(for mode: RAGQualityMode) -> Color {
        switch mode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .blue
        }
    }

    private func modeCallout(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard:
            return "Fastest daily mode with the full safety stack and cleaner single-pass results."
        case .deepThink:
            return "Iterative reasoning for nuanced questions, comparisons, and multi-step analysis."
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return "Highest-effort mode with no daily cap on your plan."
            }
            return "Highest-effort mode for stubborn questions. Free users get \(QuotaPolicy.freeMaximumModeDailyLimit) runs per day; \(entitlementStore.maximumModeRemainingUses) left today."
        default:
            return mode.description
        }
    }

    private func modeBadges(for mode: RAGQualityMode) -> [String] {
        switch mode.canonical {
        case .standard:
            return ["Fastest", "Single pass", "All safety gates"]
        case .deepThink:
            return ["Iterative", "Confidence build", "Best for analysis"]
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return ["Unlimited", "98% target", "Research grade"]
            }
            return ["\(QuotaPolicy.freeMaximumModeDailyLimit)/day", "\(entitlementStore.maximumModeRemainingUses) left", "Research grade"]
        default:
            return []
        }
    }

    private func canSelectMode(_ mode: RAGQualityMode) -> Bool {
        guard mode.canonical == .maximum else { return true }
        guard !entitlementStore.canUseMaximumModeNow else { return true }
        planEntryPoint = .maximumModeLimit
        showPlanSheet = true
        return false
    }

    @ViewBuilder
    private func modeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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

    // MARK: - Apple Intelligence Features Card

    /// Count of currently enabled Apple Intelligence features.
    private var activeAIFeatureCount: Int {
        [
            settings.enableSmartReplies,
            settings.enableContentTagging,
            settings.enableSpotlightIndexing,
            settings.enableBackgroundMaintenance,
            settings.enableWritingTools,
            settings.enableSpeechAnalysis,
        ].filter { $0 }.count
    }

    @ViewBuilder
    private var appleIntelligenceFeaturesCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                Text("Apple Intelligence")
                    .font(.headline)
                Spacer()
                Text("\(activeAIFeatureCount)/6")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(activeAIFeatureCount == 6 ? Color.green : Color.orange)
                    .clipShape(Capsule())
            }
            .padding()

            Divider().padding(.horizontal)

            VStack(spacing: 2) {
                // Toggleable features
                aiFeatureToggleRow(
                    icon: "text.bubble.fill",
                    color: .blue,
                    title: "Smart Replies",
                    subtitle: "Conversational follow-up suggestions",
                    isOn: $settings.enableSmartReplies
                )

                aiFeatureToggleRow(
                    icon: "tag.fill",
                    color: .orange,
                    title: "Content Tagging",
                    subtitle: "LLM-powered topic, action & object tagging",
                    isOn: $settings.enableContentTagging
                )

                aiFeatureToggleRow(
                    icon: "magnifyingglass",
                    color: .pink,
                    title: "Spotlight Indexing",
                    subtitle: "System-wide search integration",
                    isOn: $settings.enableSpotlightIndexing
                )

                aiFeatureToggleRow(
                    icon: "arrow.clockwise.circle.fill",
                    color: .teal,
                    title: "Background Maintenance",
                    subtitle: "Scheduled index health checks & Spotlight refresh",
                    isOn: $settings.enableBackgroundMaintenance
                )

                aiFeatureToggleRow(
                    icon: "pencil.and.outline",
                    color: .indigo,
                    title: "Writing Tools",
                    subtitle: "Summarize, rewrite, proofread",
                    isOn: $settings.enableWritingTools
                )

                aiFeatureToggleRow(
                    icon: "waveform",
                    color: .green,
                    title: "Speech Analysis",
                    subtitle: "Audio transcription & voice input",
                    isOn: $settings.enableSpeechAnalysis
                )

                Divider().padding(.horizontal)

                // Smart Reply count stepper
                HStack(spacing: 12) {
                    Image(systemName: "number.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Smart Reply Count")
                            .font(.caption.weight(.medium))
                        Text("Suggestions per response")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Stepper(value: $settings.smartReplyCount, in: 1...5) {
                        Text("\(settings.smartReplyCount)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                    .fixedSize()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider().padding(.horizontal)

                // Info-only features (always active when available)
                aiFeatureInfoRow(
                    icon: "photo.on.rectangle.angled",
                    color: .mint,
                    title: "Image Playground",
                    subtitle: "Interactive image creation from document content"
                )

                aiFeatureInfoRow(
                    icon: "lightbulb.max.fill",
                    color: .yellow,
                    title: "App Tips",
                    subtitle: "Contextual guidance & onboarding"
                )

                aiFeatureInfoRow(
                    icon: "text.book.closed.fill",
                    color: .brown,
                    title: "Gazetteer",
                    subtitle: "Builds domain vocabulary during ingestion"
                )
            }
            .padding(.vertical, 4)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// A toggleable Apple Intelligence feature row.
    @ViewBuilder
    private func aiFeatureToggleRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.accentColor)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    DSHaptics.selection()
                }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// An info-only (always active) Apple Intelligence feature row.
    @ViewBuilder
    private func aiFeatureInfoRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("Always On")
                .font(.caption2.weight(.medium))
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Appearance Card (continued)

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
