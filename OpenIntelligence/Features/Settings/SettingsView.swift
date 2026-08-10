//
//  SettingsView.swift
//  OpenIntelligence
//
//  Comprehensive settings for the RAG pipeline and AI experience.
//  Optimized for Apple Intelligence with Private Cloud Compute.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

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
    @State private var settingsSearch = ""
    @State private var showModelConfiguration = false
    @State private var showPlanSheet = false
    @State private var planEntryPoint: PlanUpgradeEntryPoint = .settings
    @State private var showAdvancedGeneration = false
    @State private var isRefreshingSharedWorkspace = false
    @State private var sharedWorkspaceRefreshMessage: String?
    @State private var pccCapability: FoundationModelCapabilitySnapshot?

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
            settingsList

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
        .task { await refreshPCCCapability() }
        .onChange(of: settings.selectedModel) { _, _ in
            updatePipelineStages()
        }
    }

    // MARK: - Settings index

    /// Top-level grouping of the settings tree.
    private enum SettingsGroup: String, CaseIterable, Identifiable {
        case intelligence
        case library
        case device
        case account
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .intelligence: return "Intelligence"
            case .library: return "Libraries"
            case .device: return "This Device"
            case .account: return "Account"
            case .system: return "System"
            }
        }
    }

    private enum SettingsEntryID: String {
        case intelligenceMode, appleIntelligence, privateCloudCompute
        case librariesSync
        case devicePerformance, appearance
        case plan, siriShortcuts
        case advanced, developer, about
    }

    /// One navigable destination, plus the words that should find it.
    ///
    /// `keywords` is what makes the tree searchable by the name a knob has in the code
    /// rather than by the screen it happens to sit on, which is the whole point of
    /// pushing depth behind navigation instead of stacking it on one scroll.
    private struct SettingsEntry: Identifiable {
        let id: SettingsEntryID
        let group: SettingsGroup
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let keywords: [String]

        static let all: [SettingsEntry] = [
            .init(
                id: .intelligenceMode, group: .intelligence,
                title: "Intelligence Mode",
                subtitle: "Standard, Deep Think, or Maximum",
                icon: "sparkles", tint: .blue,
                keywords: ["standard", "deep think", "maximum", "quality", "reasoning", "verification", "gates", "agentic"]
            ),
            .init(
                id: .appleIntelligence, group: .intelligence,
                title: "Apple Intelligence",
                subtitle: "On-device features and the active model",
                icon: "apple.logo", tint: .primary,
                keywords: ["smart replies", "content tagging", "spotlight", "writing tools", "speech", "translation", "model", "foundation models"]
            ),
            .init(
                id: .privateCloudCompute, group: .intelligence,
                title: "Private Cloud Compute",
                subtitle: "When a question may leave this device",
                icon: "cloud", tint: .blue,
                keywords: ["pcc", "cloud", "privacy", "consent", "routing", "context window", "quota"]
            ),
            .init(
                id: .librariesSync, group: .library,
                title: "Libraries & iCloud",
                subtitle: "Sharing your libraries between devices",
                icon: "icloud", tint: .cyan,
                keywords: ["icloud", "sync", "workspace", "shared", "libraries", "containers"]
            ),
            .init(
                id: .devicePerformance, group: .device,
                title: "Device & Performance",
                subtitle: "Chip, memory, GPU profile, and limits",
                icon: "cpu", tint: .orange,
                keywords: ["chip", "neural engine", "tops", "gpu", "metal", "memory", "ram", "thermal", "context window", "batch", "languages"]
            ),
            .init(
                id: .appearance, group: .device,
                title: "Appearance",
                subtitle: "Accent colour and the hardware HUD",
                icon: "paintbrush", tint: .pink,
                keywords: ["accent", "colour", "color", "theme", "hud", "silicon", "telemetry", "glow", "haptics"]
            ),
            .init(
                id: .plan, group: .account,
                title: "Plan & Usage",
                subtitle: "Documents, libraries, and Maximum runs",
                icon: "creditcard", tint: .green,
                keywords: ["plan", "billing", "subscription", "pro", "lifetime", "quota", "limit", "upgrade", "purchase"]
            ),
            .init(
                id: .siriShortcuts, group: .account,
                title: "Siri & Shortcuts",
                subtitle: "Voice commands and automation actions",
                icon: "mic", tint: .indigo,
                keywords: ["siri", "shortcuts", "app intents", "automation", "voice"]
            ),
            .init(
                id: .advanced, group: .system,
                title: "Advanced",
                subtitle: "Temperature, response length, system prompt",
                icon: "slider.horizontal.3", tint: .purple,
                keywords: ["system prompt", "instructions", "temperature", "max tokens", "response length", "top p", "top k", "sampling", "penalty", "generation", "tuning", "context length", "context window"]
            ),
            .init(
                id: .developer, group: .system,
                title: "Developer & Diagnostics",
                subtitle: "RAG audit, chunk inspector, telemetry",
                icon: "wrench.and.screwdriver", tint: .orange,
                keywords: ["developer", "diagnostics", "debug", "logging", "telemetry", "chunk", "audit", "validation", "benchmark"]
            ),
            .init(
                id: .about, group: .system,
                title: "About",
                subtitle: "Version, device, and what's new",
                icon: "info.circle", tint: .blue,
                keywords: ["about", "version", "release notes", "what's new", "support", "feedback", "privacy policy", "terms"]
            ),
        ]
    }

    // MARK: - Root list

    // Settings was a single ScrollView of fifteen hand-built cards, ~2800 lines, every
    // card at the same visual altitude — your plan sat level with the GPU execution
    // profile. That is a depth problem rather than a styling one, and converting the
    // cards to Form sections would not have touched it.
    //
    // The cards themselves are unchanged and still live on this type; only the root
    // changed. Each is now reached through a `NavigationLink`, so the top level is a
    // dozen rows instead of fifteen stacked panels, and `.searchable` means the depth
    // costs nothing to reach — you can type "temperature" without knowing which screen
    // owns it. That combination is what lets the surface stay calm without removing any
    // of the complexity.
    //
    // A native `List` also brings correct Dynamic Type row layout, platform insets, and
    // `Section` footers for copy that was previously loose `Text` inside tinted panels.
    private var settingsList: some View {
        List {
            Section {
                heroSummaryRow
            }

            ForEach(SettingsGroup.allCases) { group in
                let entries = visibleEntries(in: group)
                if !entries.isEmpty {
                    Section(group.title) {
                        ForEach(entries) { entry in
                            if entry.id == .advanced {
                                // Advanced opens the parameters directly. Pushing a screen
                                // whose only content was a button that opened this sheet
                                // made it two taps to reach the one thing behind the row.
                                Button {
                                    DSHaptics.selection()
                                    showModelConfiguration = true
                                } label: {
                                    HStack {
                                        settingsRow(entry)
                                        Spacer(minLength: 0)
                                        // A `Button` row gets no disclosure indicator of
                                        // its own, so without this it sits between two
                                        // NavigationLink rows looking inert.
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    destination(for: entry)
                                        .navigationTitle(entry.title)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    settingsRow(entry)
                                }
                            }
                        }
                    }
                }
            }

            if trimmedSearch.isEmpty {
                Section {
                    supportCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .searchable(text: $settingsSearch, prompt: "Search settings")
        .sheet(isPresented: $showModelConfiguration) {
            ModelConfigurationSheet()
        }
        .overlay {
            if !trimmedSearch.isEmpty, SettingsGroup.allCases.allSatisfy({ visibleEntries(in: $0).isEmpty }) {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
    }

    // `modelParametersCard` was removed when the Advanced row began presenting
    // `ModelConfigurationSheet` directly. It existed only to hold the button that
    // opened the sheet, which was the second of the two taps.

    /// Compact identity row at the top of the index.
    ///
    /// The full `heroCard` is a ~500pt tall centred panel — a reasonable opening for a
    /// single long scroll, and far too much for the first row of a navigation index,
    /// where it pushed the first real section most of a screen down. Settings.app makes
    /// the same trade: the Apple Account card is a compact row, not a hero. The status
    /// text and both pills survive, laid out horizontally.
    private var heroSummaryRow: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(DSColors.accent)
                .frame(width: 44, height: 44)
                .background(DSColors.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("OpenIntelligence")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: DSSpacing.xs) {
                    statusPill(
                        icon: "checkmark.shield.fill",
                        text: "On-Device First",
                        active: true
                    )
                    if deviceCapabilities.supportsPrivateCloudCompute, settings.applePCCConsent != .denied {
                        statusPill(icon: "cloud.fill", text: "PCC Available", active: true)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var trimmedSearch: String {
        settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Entries in `group` that match the current search.
    ///
    /// Matching includes each entry's `keywords`, so a knob can be found by the name it
    /// has in the code ("temperature", "top-k", "chunk overlap") and not only by the
    /// screen it happens to live on. That is the difference between a deep settings tree
    /// and a hostile one.
    private func visibleEntries(in group: SettingsGroup) -> [SettingsEntry] {
        let entries = SettingsEntry.all.filter { $0.group == group }
        let query = trimmedSearch.lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.lowercased().contains(query)
                || entry.subtitle.lowercased().contains(query)
                || entry.keywords.contains { $0.contains(query) }
        }
    }

    @ViewBuilder
    private func settingsRow(_ entry: SettingsEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entry.icon)
                .foregroundStyle(entry.tint)
        }
        .accessibilityLabel(entry.title)
        .accessibilityHint(entry.subtitle)
    }

    @ViewBuilder
    private func destination(for entry: SettingsEntry) -> some View {
        switch entry.id {
        case .intelligenceMode:
            detailScroll { retrievalCard }
        case .appleIntelligence:
            detailScroll {
                modelSelectionCard
                appleIntelligenceFeaturesCard
            }
        case .privateCloudCompute:
            detailScroll { privateCloudComputeCard }
        case .librariesSync:
            detailScroll { sharedWorkspaceCard }
        case .devicePerformance:
            detailScroll { contextWindowCard }
        case .appearance:
            detailScroll { appearanceCard }
        case .plan:
            detailScroll { billingCard }
        case .siriShortcuts:
            detailScroll {
                siriIntegrationCard
                shortcutsAutomationCard
            }
        case .advanced:
            // Unreachable: the Advanced row presents `ModelConfigurationSheet` directly
            // rather than pushing a screen. Kept so the switch stays exhaustive over
            // `SettingsEntryID`, which is what makes adding an entry a compile error until
            // it has a destination.
            EmptyView()
            .sheet(isPresented: $showModelConfiguration) {
                ModelConfigurationSheet()
            }
        case .developer:
            DeveloperDiagnosticsHubView(ragService: ragService)
        case .about:
            AboutView()
        }
    }

    /// Shared chrome for a pushed detail screen, so every one of them scrolls, pads and
    /// tints the same way instead of each card carrying its own container.
    @ViewBuilder
    private func detailScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: DSSpacing.lg) {
                content()
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
.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    openURL(OpenIntelligenceLinks.writeReviewURL)
                } label: {
                    Label("Write Review", systemImage: "star.bubble.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Text(settings.selectedModel.capabilityCard.nickname)
                        .font(.subheadline.weight(.medium))
                    Text(settings.selectedModel.capabilityCard.tagline)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
.background(Color.accentColor.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Model capabilities
            HStack(spacing: 12) {
                modelCapabilityPill(icon: "text.bubble.fill", label: "Text Generation")
                modelCapabilityPill(icon: "photo.fill", label: "ADM 3 Visuals")
                modelCapabilityPill(icon: "doc.text.fill", label: "RAG-Ready")
            }
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    // MARK: - Private Cloud Compute Card

    @ViewBuilder
    private var privateCloudComputeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cloud.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private Cloud Compute")
                        .font(.headline)
                    Text("Larger context window than the device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(deviceCapabilities.supportsPrivateCloudCompute ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(deviceCapabilities.supportsPrivateCloudCompute ? "Available" : "Unavailable")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(deviceCapabilities.supportsPrivateCloudCompute ? .green : .orange)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PCC Usage")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("PCC Usage", selection: $settings.pccSetting) {
                        ForEach(PCCSettings.allCases, id: \.self) { setting in
                            Text(setting.rawValue).tag(setting)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!deviceCapabilities.supportsPrivateCloudCompute)
                }
                
                Text("Apple's Private Cloud Compute (PCC) allows OpenIntelligence to process complex queries with a massive 32,768 token context window, significantly improving multi-document analysis and Deep Think capabilities. OpenIntelligence does not operate its own servers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                Divider()
                
                // PCC Quota Status
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("PCC Quota Status")
                            .font(.subheadline.weight(.medium))
                    }
                    
                    if let capability = pccCapability, capability.pccAvailable {
                        HStack {
                            Text("Status:")
                                .font(.caption)
                            Spacer()
                            Text(capability.pccQuota == .limitReached ? "Limit Reached" : capability.pccQuota.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(capability.pccQuota == .limitReached ? .red : .green)
                        }
                        if let contextSize = capability.pccContextSize {
                            LabeledContent("Context", value: "\(contextSize) tokens")
                                .font(.caption)
                        }
                    } else if pccCapability == nil {
                        ProgressView("Reading PCC capability…")
                            .font(.caption)
                    } else {
                        Text(pccCapability?.unavailabilityReason ?? "PCC is currently unavailable on this device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 4)
                .padding(.top, 4)
            }
            #endif
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func refreshPCCCapability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            pccCapability = await LiveFoundationModelCapabilityProvider().snapshot()
        }
        #endif
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
                    Text("Each library chooses Local Only or iCloud Sync")
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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
               hasConfiguredICloudLibraries {
                VStack(alignment: .leading, spacing: 10) {
                        Text("Review iCloud library changes")
                        .font(.subheadline.weight(.semibold))

                        Text("Only libraries marked iCloud Sync are involved here. This device currently has \(bootstrapConflict.localLibraryCount) libraries marked iCloud Sync / \(bootstrapConflict.localDocumentCount) documents, and iCloud already has \(bootstrapConflict.sharedLibraryCount) shared librar\(bootstrapConflict.sharedLibraryCount == 1 ? "y" : "ies") / \(bootstrapConflict.sharedDocumentCount) documents.")
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                    Text("Change Local Only or iCloud Sync per library, and refresh shared libraries, from the Documents screen.")
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
                .fixedSize(horizontal: false, vertical: true)

            if let sharedWorkspaceRefreshMessage {
                Text(sharedWorkspaceRefreshMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rootDescription = workspaceSyncService.workspaceRootDescription, workspaceSyncService.isUsingSharedWorkspace {
                Text(rootDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastErrorMessage = workspaceSyncService.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            return "iCloud Sync"
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
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local. Libraries marked iCloud Sync use iCloud as the shared copy. Local Only libraries stay on just this device."
        }

        return "All libraries are Local Only right now. Turn iCloud Sync on per library when you want it on another device."
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Context Window Card

    @ViewBuilder
    private var contextWindowCard: some View {
        let deviceService = DeviceCapabilityService.shared

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Active Device")
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
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                    Text("Maximum mode utilizes exhaustive Neural Engine synthesis. It chains multiple reasoning sessions, each with a 4K-token Apple FM window. Compressed insights pass between sessions via Self-RAG 2.0 enrichment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text("Deep Think chains \(max(4, agenticConfig.maxSteps - 2))–\(agenticConfig.maxSteps) serial reasoning sessions (device-optimized for the \(DeviceCapabilityService.shared.chipName)). Each session gets a fresh 4K-token window with compressed prior insights. Stops at \(Int(agenticConfig.confidenceThreshold * 100))% confidence.")
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
                        contextInfoPill(icon: "flame.fill", label: "Synthesis", value: "Exhaustive")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Per Session", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Sessions", value: "\(max(4, agenticConfig.maxSteps - 2))–\(agenticConfig.maxSteps) (\((agenticConfig.maxSteps * 4096) / 1000)K effective)")
                    } else {
                        contextInfoPill(icon: "square.3.layers.3d", label: "Single Pass", value: "4K tokens")
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "If Complex", value: "3 sessions (12K)")
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

                // Language list — verified Apple Intelligence languages as of iOS 26.0+
                Text("English, Spanish, French, German, Italian, Japanese, Korean, Portuguese, Chinese, Hindi, Vietnamese, Indonesian, Thai, Dutch, Arabic, Turkish, Polish, Romanian, Swedish")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))

                Text("On-device Foundation Model language support may vary. Apple routes automatically.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
.padding(10)
    .background(Color.blue.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        hardwareLimitRow(icon: "eye.fill", label: "Vision / ADM 3 Ceiling", value: "\(envelope.visionOperationConcurrency) ops • \(envelope.visionCooldownMilliseconds) ms cooldown")
                        hardwareLimitRow(icon: "photo.stack", label: "Adaptive PDF Budget", value: imageBudgetText)
                        hardwareLimitRow(icon: "function", label: "Vector Search Ceiling", value: "\(envelope.vectorBatchSize) batch • matrix @ \(envelope.batchMatrixMultiplyThreshold)+")
                    }
                }
                .padding(12)
                .background(Color.indigo.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            // "4x faster" removed 2026-08-06. No benchmark supporting it exists in
            // `Benchmarks/` or the evaluation docs, same class as the `1,000x` dedup and
            // `240x` scrolling figures withdrawn in this release. The GPU path is real;
            // the multiplier was never measured.
            Text("Vector math uses Apple's Accelerate framework (vDSP/BLAS) for CPU SIMD acceleration. Metal GPU RAG shaders handle bulk cosine similarity and MMR diversity when GPU level ≥ 60%. Batch sizes are tuned for the \(deviceService.chipName).")
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    @State private var gpuProfile: GPUExecutionProfile = DeviceCapabilityService.shared.gpuExecutionProfile

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

            Text("Choose how OpenIntelligence schedules GPU-capable work. Apple frameworks still make the final hardware decision, so these are execution preferences rather than a literal utilization percentage.")
                .font(.caption)
                .foregroundColor(.secondary)

            if deviceService.activeGPUExecutionProfile != gpuProfile {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\(deviceService.chipName) is using the \(deviceService.activeGPUExecutionProfile.displayName) profile instead of \(gpuProfile.displayName) to avoid unstable sustained loads.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Discrete profiles avoid implying a precise GPU percentage that Core ML cannot promise.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Execution Profile")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Picker("Execution Profile", selection: $gpuProfile) {
                        ForEach(GPUExecutionProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(gpuModeColor)
                    .onChange(of: gpuProfile) { _, newValue in
                        DeviceCapabilityService.shared.gpuExecutionProfile = newValue
                    }
                }

                Text(gpuProfileDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Core ML changes apply when its model next loads; PDF and vector policies apply to the next operation.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: gpuProfile)

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Current policy derived from the same profile the execution paths consult.
            VStack(alignment: .leading, spacing: 6) {
                gpuSettingRow(
                    icon: "cpu",
                    label: "Core ML (next load)",
                    value: deviceService.preferredComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Ingestion Embeddings",
                    value: deviceService.embeddingComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "PDF Rendering",
                    value: deviceService.useGPUForPDFRendering ? "Metal CIContext (GPU)" : "CPU CIContext"
                )
                gpuSettingRow(
                    icon: "function",
                    label: "Metal Vector Ops",
                    value: deviceService.useMetalForVectorOps ? "Automatic for large searches" : "Off (Accelerate CPU)"
                )
                gpuSettingRow(
                    icon: "thermometer.medium",
                    label: "Thermal Impact",
                    value: gpuThermalImpact
                )
            }
            .animation(.easeInOut(duration: 0.2), value: gpuProfile)

            Divider()
                .padding(.vertical, 2)

            // Pipeline concurrency remains tier-based rather than profile-controlled.
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipeline Concurrency")
                    .font(.caption.weight(.medium))
                Text("Set by device tier, not the execution profile. Optimized for the \(deviceService.chipName).")
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
            .animation(.easeInOut(duration: 0.2), value: gpuProfile)

            // Warning for high GPU mode
            if gpuProfile == .maximum {
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            gpuProfile = DeviceCapabilityService.shared.gpuExecutionProfile
        }
    }

    private var gpuProfileDescription: String {
        switch gpuProfile {
        case .efficiency:
            return "Prefers CPU and Neural Engine paths; disables GPU PDF rendering and Metal vector search."
        case .balanced:
            return "Uses GPU-backed PDF rendering while keeping normal model work Neural Engine-focused."
        case .performance:
            return "Allows all Core ML compute units and enables Metal for sufficiently large vector workloads."
        case .maximum:
            return "Prefers CPU + GPU model execution and the most aggressive supported GPU policy."
        }
    }

    private var gpuThermalImpact: String {
        switch gpuProfile {
        case .efficiency: return "✅ Lowest"
        case .balanced: return "✅ Low"
        case .performance: return "⚠️ Moderate"
        case .maximum: return "🔥 High"
        }
    }

    private var gpuModeName: String {
        DeviceCapabilityService.shared.activeGPUExecutionProfile.displayName
    }

    private var gpuModeColor: Color {
        switch DeviceCapabilityService.shared.activeGPUExecutionProfile {
        case .efficiency: return .blue
        case .balanced: return .green
        case .performance: return .orange
        case .maximum: return .red
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: settings.ragQualityMode)
        }
.padding()
    .background(DSColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        // "1,000x faster" was an unmeasured multiplier with no benchmark behind it, the
        // same class of claim as the `≈65 tok/s` figure removed from the capability card.
        // The algorithmic change is real; the number was never measured.
        items.append(.init(id: "fast-dedup", icon: "bolt.fill", label: "O(N) Fast Deduplication", desc: "Linear-time evidence dedup, so large libraries stay fast", color: .green))
        items.append(.init(id: "native-embed", icon: "cpu.fill", label: "Native Embeddings", desc: "CoreAISentenceEmbeddingProvider hardware acceleration", color: .green))
        items.append(.init(id: "contextual-embed", icon: "doc.badge.gearshape", label: "Contextual Embeddings", desc: "Document title + section baked into every vector", color: .green))
        items.append(.init(id: "table-extract", icon: "tablecells", label: "Smart Table Extraction", desc: "iOS 26 Vision API preserves tables with captions", color: .green))
        items.append(.init(id: "entity-link", icon: "link", label: "Cross-Document Entity Linking", desc: "Global entity index finds related info across library", color: .green))
        items.append(.init(id: "parent-doc", icon: "doc.on.doc", label: "Parent Document Retrieval", desc: "Expands chunk window ±5 for full paragraph context", color: .green))
        items.append(.init(id: "query-understand", icon: "lightbulb", label: "Query Understanding", desc: "NLTagger resolves pronouns, NER extracts key entities", color: .green))
        items.append(.init(id: "hybrid-rrf", icon: "arrow.triangle.merge", label: "Hybrid Search + RRF", desc: "Vector + BM25 keyword search with Reciprocal Rank Fusion", color: .green))
        // "TinyBERT" is correct and is documented provenance, not a guess. An earlier pass
        // removed it on the grounds that `ReRankerModel.mlpackage/Manifest.json` declares no
        // model family, but that manifest is a Core ML packaging artifact and never carried
        // one. `THIRD_PARTY_NOTICES.md` binds `cross-encoder/ms-marco-TinyBERT-L2-v2`
        // (Apache 2.0) to this exact bundled artifact path. Attribution required for a
        // license is stronger evidence than a converted package's metadata, so the specific
        // name is restored. Do not remove it again without checking that file first.
        items.append(.init(id: "cross-encoder", icon: "arrow.up.arrow.down", label: "Cross-Encoder Reranking", desc: "TinyBERT cross-encoder scores query-document relevance", color: .green))
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
            // "Dynamic Profiles" and "Model Judges" were listed here but neither
            // exists: `FoundationModelDynamicProfileRegistry` has zero call sites,
            // and there is no judge implementation anywhere in `Services/`. This
            // list is shown to users as what the active mode is doing, so an
            // unimplemented row is a false claim, not a roadmap teaser. Both are
            // tracked on the roadmap; re-add each one when it actually runs.
            items.append(.init(id: "pcc-escalation", icon: "cloud.lock.fill", label: "Private Cloud Compute", desc: "Context-heavy queries escalate to Apple's secure enclaves", color: .purple))
            items.append(.init(id: "native-spotlight", icon: "magnifyingglass", label: "Spotlight Indexing", desc: "Your documents are indexed into Apple Core Spotlight", color: .purple))
            items.append(.init(id: "intent-route", icon: "signpost.right.and.left", label: "Intent Routing", desc: "Classifies query as lookup/procedure/compare/summarize", color: .purple))
            items.append(.init(id: "multi-query", icon: "magnifyingglass.circle.fill", label: "Multi-Query Expansion", desc: "LLM generates diverse search queries for broader retrieval", color: .purple))
            items.append(.init(id: "graph-expand", icon: "point.3.connected.trianglepath.dotted", label: "2-Hop Graph Expansion", desc: "Entity-based traversal finds related chunks", color: .purple))
            items.append(.init(id: "recursive-loop", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Recursive Research Loop", desc: "Autonomous [SEARCH:]/[ANSWER] protocol until confident", color: .purple))
            items.append(.init(id: "verify-gates", icon: "checkmark.seal.fill", label: "Verification Gates A–I", desc: "9-stage anti-hallucination checks before answering (Confidence, Coverage, Numeric, Contradiction, Semantic, Quote, Quality, Completeness, Isolation)", color: .purple))
            items.append(.init(id: "confidence-cal", icon: "function", label: "Confidence Calibration", desc: "Sigmoid-calibrated scores from rerank + margin + evidence count", color: .purple))
            items.append(.init(id: "extract-summary", icon: "text.line.first.and.arrowtriangle.forward", label: "Extractive Summarization", desc: "Sentence selection via bi-encoder for summarize intent", color: .purple))
            items.append(.init(id: "graph-pack", icon: "rectangle.compress.vertical", label: "Graph Context Packing", desc: "Optimal token budget allocation across evidence", color: .purple))
            items.append(.init(id: "orchestrator", icon: "brain.head.profile", label: "Agentic Orchestrator", desc: "\(max(4, DeviceCapabilityService.shared.optimizedAgenticConfig().maxSteps - 2))–\(DeviceCapabilityService.shared.optimizedAgenticConfig().maxSteps) sessions targeting \(Int(DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold * 100))% confidence", color: .purple))
            // Named from `FoundationModelToolRegistry.createTools`, which is the only
            // place tools are handed to a session. It registers these four. The eight
            // previously listed here (SearchDocs, ListDocs, GetSummary, CountPattern,
            // ExactSearch, Stats, Related, Compare) are declared in the same file but
            // registered nowhere, so the UI was naming the dead set and none of the live
            // one. Keep this list in sync with `createTools`, not with the struct count.
            items.append(.init(id: "tool-funcs", icon: "hammer.fill", label: "4 Tool Functions", desc: "RetrieveCorpusEvidence, InspectDocument, CompareTopicAcrossDocuments, GetLibraryOverview", color: .purple))
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
            // Was "200K+ Token Budget — 50 sessions × 4K". That multiplies out to a number
            // that reads like a context window and is not one: Maximum runs up to 50
            // *separate* 4K windows, it never holds 200K at once. The 50 is also a ceiling
            // rather than a typical run — `AgenticConfig.unlimited`'s own comment says
            // thermal will stop it first, and 4.9 added convergence stopping specifically
            // so it exits once it stops learning. Describe the mechanism, not a product.
            items.append(.init(id: "token-budget", icon: "cpu", label: "Up to 50 Sessions", desc: "Each gets a fresh 4K window; stops early once it converges", color: .orange))
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? accent.opacity(0.08) : Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
    /// Number of the toggleable Apple Intelligence features currently on.
    ///
    /// Counts four, not seven. `enableWritingTools`, `enableSpeechAnalysis` and
    /// `enableTranslation` used to be in this list, so the badge was reporting three
    /// switches that gated nothing as if they were live capability. These four are the
    /// ones with real consumers, and they are the four that still render as switches.
    private var activeAIFeatureCount: Int {
        [
            settings.enableSmartReplies,
            settings.enableContentTagging,
            settings.enableSpotlightIndexing,
            settings.enableBackgroundMaintenance,
        ].filter { $0 }.count
    }

    private var totalAIFeatureCount: Int { 4 }

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
                Text("\(activeAIFeatureCount)/\(totalAIFeatureCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 3)
                    .background(activeAIFeatureCount == totalAIFeatureCount ? Color.green : Color.orange)
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

                // These three were switches bound to `enableWritingTools`,
                // `enableSpeechAnalysis` and `enableTranslation`. Each key persisted to
                // UserDefaults and had **zero consumers** anywhere in the app, tests or
                // the extension — so flipping them changed nothing at all.
                //
                // The features themselves are real and always on, which is why these are
                // status rows now rather than deletions: Writing Tools ships through
                // `.writingToolsBehavior(.complete)` on the chat composer,
                // `SpeechAnalyzerService` runs inside `DocumentProcessor` for audio and
                // video, and `TranslationService` has live call sites. Removing the claim
                // would have withdrawn something true; removing the control removes
                // something false.
                aiFeatureInfoRow(
                    icon: "pencil.and.outline",
                    color: .indigo,
                    title: "Writing Tools",
                    subtitle: "Summarize, rewrite, proofread"
                )

                aiFeatureInfoRow(
                    icon: "waveform",
                    color: .green,
                    title: "Speech Analysis",
                    subtitle: "Audio transcription & voice input"
                )

                aiFeatureInfoRow(
                    icon: "character.book.closed.fill",
                    color: .purple,
                    title: "Translation",
                    subtitle: "Multilingual document analysis"
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

                // Same as the three above: `enableScreenAwareness` and
                // `enableADM3Visuals` had no consumers, while the App Intents and the
                // Image Playground path they describe are registered and live.
                aiFeatureInfoRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    color: .blue,
                    title: "Screen Awareness",
                    subtitle: "Seamless AppIntents integration via Shortcuts"
                )

                aiFeatureInfoRow(
                    icon: "photo.on.rectangle.angled",
                    color: .mint,
                    title: "Image Playground",
                    subtitle: "Interactive ADM 3 image creation from document content"
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
     }

    private var siriIntegrationCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "siri")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Siri Voice Shortcuts")
                        .font(.headline)
                    Text("Speak directly to Siri without any manual setup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("9 of 10 Registered")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            .padding()

            Divider().padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Instant Voice Phrases")
                    .font(.subheadline.bold())
                    .padding(.horizontal)
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    shortcutCommandRow(title: "Query Active Documents", phrase: "Ask OpenIntelligence about my documents")
                    shortcutCommandRow(title: "List Loaded Files", phrase: "List my documents in OpenIntelligence")
                    shortcutCommandRow(title: "Check Import Queue", phrase: "Check document import status in OpenIntelligence")
                    shortcutCommandRow(title: "Query Specific Document", phrase: "Ask OpenIntelligence about [Document Name]")
                    shortcutCommandRow(title: "Generate File Summary", phrase: "Summarize [Document Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Compare Multiple Files", phrase: "Compare documents in OpenIntelligence")
                    shortcutCommandRow(title: "Search Custom Library", phrase: "Search [Library Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Ingest Current Screen PDF", phrase: "Add this document to OpenIntelligence")
                    shortcutCommandRow(title: "Ingest Current Safari URL", phrase: "Extract this webpage into OpenIntelligence")
                }

                Divider().padding(.horizontal)

                Text("Trust & Hallucination Prevention")
                    .font(.subheadline.bold())
                    .padding(.horizontal)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Strict Verification Gates")
                            .font(.subheadline.weight(.semibold))
                        Text("Siri voice responses run the exact same on-device validation rules as the main chat view. If no precise document evidence supports a claim, Siri returns a prominent 'Needs Verification' dialog instead of hallucinating.")
                            .font(.caption)
                            .foregroundColor(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: false)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shortcutsAutomationCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "square.2.layers.3d")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcuts App Integration")
                        .font(.headline)
                    Text("Custom automations & drag-and-drop actions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("16 Actions Available")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .padding()

            Divider().padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("App Actions in Shortcuts Library")
                    .font(.subheadline.bold())
                    .padding(.horizontal)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 14) {
                    shortcutsActionGroup(title: "Document Ingestion", actions: [
                        "Add Document" : "Ingest a file parameter directly into a selected library.",
                        "Ingest Current Document" : "Imports the open document from screen context.",
                        "Ingest Safari URL" : "Extracts and processes the active Safari webpage URL.",
                        "Ingest From Camera" : "Launch document scanner or camera feed to import."
                    ])

                    shortcutsActionGroup(title: "Retrieval & QA", actions: [
                        "Query Documents" : "Hybrid vector/keyword search with RRF over active library.",
                        "Ask Document" : "Direct QA targeted at a single document entity.",
                        "Search Library" : "Switches to and searches a designated library container."
                    ])

                    shortcutsActionGroup(title: "Summarization & Analysis", actions: [
                        "Summarize Document" : "Generates abstractive summary of document contents.",
                        "Compare Documents" : "Evaluate differences in facts or metrics across files.",
                        "Analyze Image" : "Run visual OCR and VLM analysis on a camera photo.",
                        "Visual Search" : "Queries visual library database index using an image."
                    ])

                    shortcutsActionGroup(title: "Conversation & History", actions: [
                        "List Evidence Threads" : "Exposes conversational history and thread properties.",
                        "Create New Evidence Thread" : "Instantiates a new workspace conversation session."
                    ])

                    shortcutsActionGroup(title: "Telemetry & System", actions: [
                        "Get Active Embedding Model" : "Returns active hardware acceleration route (Core AI vs Core ML).",
                        "Check Import Queue Status" : "Queries background ingestion, OCR, and vector indices."
                    ])
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortcutsActionGroup(title: String, actions: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(actions.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(.caption.bold())
                            .foregroundColor(DSColors.primaryText)
                            .frame(width: 170, alignment: .leading)
                        Text(actions[key] ?? "")
                            .font(.caption2)
                            .foregroundColor(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: false)
                        Spacer()
                    }
                }
            }
            .padding(.leading, 8)
        }
    }

    private func shortcutCommandRow(title: String, phrase: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(DSColors.secondaryText)
                Text("\"\(phrase)\"")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(DSColors.primaryText)
            }
            Spacer()
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = phrase
                #elseif canImport(AppKit)
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(phrase, forType: .string)
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
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
                        Text("Telemetry HUD")
                            .font(.subheadline.weight(.medium))
                        Text("Real-time model routing and token telemetry")
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // `developerCard` and `aboutCard` were removed with the Settings restructure.
    // Both were NavigationLink-in-a-card wrappers; the same destinations are now
    // reached from `SettingsEntry.all` like every other screen.

    // MARK: - Support Card

    @ViewBuilder
    private var supportCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }

                Text("Support & Feedback")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal)

            // Rate App Row
            Button {
                openURL(OpenIntelligenceLinks.writeReviewURL)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate on the App Store")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("Love OpenIntelligence? Rate it 5 stars!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal)

            // Feedback Row
            Button {
                openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "Settings Screen"))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send Feedback")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("Provide feedback to improve the experience")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal)

            // Share App Row
            Button {
                shareApp()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.purple)
                        .font(.system(size: 16))
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share with Friends")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("Recommend OpenIntelligence to others")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shareApp() {
        let items: [Any] = [
            "I'm using OpenIntelligence for private, on-device AI and RAG search. Check it out on the App Store!",
            OpenIntelligenceLinks.appStoreURL
        ]
        
        #if canImport(UIKit)
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Setup popover for iPad support
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            // For iPad compatibility
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let picker = NSSharingServicePicker(items: items)
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }),
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }

    // MARK: - Helpers

    private func updatePipelineStages() {
        pipelineStages = [
            ModelPipelineStage(
                name: "Embedding",
                role: .primary,
                detail: "Native FoundationModels Embeddings",
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
