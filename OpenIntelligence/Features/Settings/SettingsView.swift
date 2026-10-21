//
//  SettingsView.swift
//  OpenIntelligence
//
//  Comprehensive settings for the RAG pipeline and AI experience.
//  Optimized for Apple Intelligence with Private Cloud Compute.
//

import AppIntents
import SwiftUI
import TipKit

#if canImport(FoundationModels)
import FoundationModels
#endif

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    #if os(macOS)
        /// Whether the menu bar item shows (`MenuBarAsk`); the app reads the same key.
        @AppStorage(MenuBarAsk.visibilityKey) private var showsMenuBarItem = true
    #endif

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
        case howItWorks, glossary
        case intelligenceMode, appleIntelligence, privateCloudCompute
        case librariesSync
        case devicePerformance, appearance, notifications
        case plan, siriShortcuts
        case advanced, developer, about, versionHistory
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
            // First row of the first group on purpose. This answers the questions a user
            // has before they have opinions about retrieval depth, and burying it under
            // About would defeat the reason it exists.
            .init(
                id: .howItWorks, group: .intelligence,
                title: "How This Works",
                subtitle: "What happens to a document, and what stays on this device",
                icon: "questionmark.circle", tint: .teal,
                keywords: [
                    "how", "works", "explain", "privacy", "on-device", "on device", "local",
                    "server", "upload", "cloud", "embedding", "chunk", "index", "retrieval",
                    "citation", "sources", "vision", "ocr",
                ]
            ),
            // Second row, immediately after the narrative explanation. The two answer
            // different questions: How This Works explains the pipeline in order, this
            // defines a single word you did not recognise while reading it.
            .init(
                id: .glossary, group: .intelligence,
                title: "Plain English",
                subtitle: "Every word this app uses, defined twice",
                icon: "character.book.closed", tint: .mint,
                keywords: [
                    "glossary", "plain", "english", "definition", "definitions", "meaning",
                    "jargon", "vocabulary", "terms", "what does", "explain", "chunk",
                    "vector", "embedding", "token", "tops", "neural engine", "ane", "batch",
                    "rag", "rerank", "bm25", "context window", "temperature", "ocr",
                ]
            ),
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
                keywords: ["accent", "colour", "color", "theme", "hud", "silicon", "telemetry", "telemetry hud", "x-ray", "xray", "glow", "haptics", "technical", "technical details", "console", "stats", "simple"]
            ),
            .init(
                id: .notifications, group: .device,
                title: "Notifications",
                subtitle: "When an import or a long answer finishes",
                icon: "bell.badge", tint: .red,
                keywords: ["notifications", "notify", "alert", "banner", "finished", "import", "deep think", "maximum", "background"]
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
            .init(
                id: .versionHistory, group: .system,
                title: "Version History",
                subtitle: "Every release, and what changed in it",
                icon: "clock.arrow.circlepath", tint: .gray,
                keywords: ["version", "history", "changelog", "release notes", "updates", "what's new", "previous"]
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

            // `ModelConfigTip` promises "Tune retrieval depth, temperature, and context
            // window". That was aspirational until this release: the sheet holding those
            // controls had no call site, so a tip pointing at them would have pointed at
            // nothing. It is wired now because Advanced actually reaches them.
            //
            // Retired by opening Advanced, not by opening Settings, so it persists until
            // the user has been where it is sending them.
            if trimmedSearch.isEmpty {
                Section {
                    InlineTipView(tip: ModelConfigTip())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            ForEach(SettingsGroup.allCases) { group in
                let entries = visibleEntries(in: group)
                if !entries.isEmpty {
                    // A header in the readable gray (5.7): the List's own header "nearly passed" Apple's contrast audit.
                    Section {
                        ForEach(entries) { entry in
                            if entry.id == .advanced {
                                // Advanced opens the parameters directly. Pushing a screen
                                // whose only content was a button that opened this sheet
                                // made it two taps to reach the one thing behind the row.
                                Button {
                                    DSHaptics.selection()
                                    // Retires `ModelConfigTip`, which points here.
                                    Task { await ModelConfigTip.settingsVisited.donate() }
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
                    } header: {
                        Text(group.title)
                            .foregroundStyle(DSColors.secondaryText)
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

    /// A labelled status row for the iCloud card, replacing loose grey paragraphs.
    @ViewBuilder
    private func syncDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }

    @ViewBuilder
    private func pccWindowRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }

    /// The PCC context window, read live where the system reports it.
    ///
    /// Never a hardcoded 32,768. `FoundationModelTokenBudget` falls back to that figure,
    /// but the live capability snapshot is authoritative and the two can differ, which is
    /// how this screen previously managed to show two different numbers at once.
    private var pccWindowDescription: String {
        guard deviceCapabilities.supportsPrivateCloudCompute else {
            return "Unavailable"
        }
        if let size = pccCapability?.pccContextSize, size > 0 {
            return "\(size.formatted()) tokens"
        }
        return "\(FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false).formatted()) tokens"
    }

    /// The on-device window, preferring the live capability snapshot over the budget
    /// helper's fallback for the same reason as `pccWindowDescription`.
    /// The languages Apple's on-device model reports on this device, by name in the person's language, or nil
    /// where Foundation Models isn't available.
    private var modelLanguageNames: [String]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let names = SystemLanguageModel.default.supportedLanguages.compactMap { language in
                Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            }
            return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        #endif
        return nil
    }

    private var onDeviceWindowDescription: String {
        if let size = pccCapability?.onDeviceContextSize, size > 0 {
            return "\(size.formatted()) tokens"
        }
        // Both the snapshot and `SystemLanguageModel.default.contextSize` report 0 where
        // Foundation Models are unavailable, which is every simulator. Rendering that as
        // "0 tokens" reads as a broken device rather than an absent model.
        let budget = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        return budget > 0 ? "\(budget.formatted()) tokens" : "Unavailable"
    }

    /// Cooling line for the Active Device card.
    ///
    /// This used to read "Active cooling" on every Mac, because the form factor asserted
    /// it. The MacBook Air is fanless and no public API reports fan presence, so on Mac
    /// the app now reports the live `ProcessInfo.thermalState` it already monitors instead
    /// of a claim about the enclosure. Measured beats guessed, and it is the more useful
    /// number anyway.
    private var coolingDescription: String {
        switch DeviceCapabilityService.shared.formFactor.hasActiveCooling {
        case .some(true): return "Active cooling"
        case .some(false): return "Passive cooling"
        case .none:
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "Thermals nominal"
            case .fair: return "Thermals fair"
            case .serious: return "Thermals serious"
            case .critical: return "Thermals critical"
            @unknown default: return "Thermals unknown"
            }
        }
    }

    /// Compact identity row at the top of the index.
    ///
    /// The full `heroCard` is a ~500pt tall centred panel — a reasonable opening for a
    /// single long scroll, and far too much for the first row of a navigation index,
    /// where it pushed the first real section most of a screen down. Settings.app makes
    /// the same trade: the Apple Account card is a compact row, not a hero. The status
    /// text and both pills survive, laid out horizontally. At accessibility text sizes the
    /// icon goes above the text, and the two pills stack whenever they do not fit side by side
    /// (5.7): at the largest size each had about 130 points, and "PCC" and "Available" broke in
    /// the middle of the word.
    private var heroSummaryRow: some View {
        let rowLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(spacing: DSSpacing.md))
        return rowLayout {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                // Decorative and drawn in a 44-point circle, so it stops growing at the largest standard size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(DSColors.accent)
                .frame(width: 44, height: 44)
                .background(DSColors.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("OpenIntelligence")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                    statusPills
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusPills: some View {
        statusPill(
            icon: "checkmark.shield.fill",
            text: "On-Device First",
            active: true
        )
        if deviceCapabilities.supportsPrivateCloudCompute, settings.applePCCConsent != .denied {
            statusPill(icon: "cloud.fill", text: "PCC Available", active: true)
        }
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
        case .howItWorks:
            HowItWorksView()
        case .glossary:
            GlossaryView()
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
        case .notifications:
            detailScroll { CompletionNotificationSettingsCard() }
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
        case .versionHistory:
            VersionHistoryView()
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
                .foregroundStyle(active ? Color.accentColor : DSColors.secondaryText)
            Text(text)
                .font(.caption2.weight(.medium))
                // Its full height for the width it gets, so at large sizes it wraps instead of ending in "Fir..." (5.7).
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // The words in the label color when active, the accent in the icon and the tint (5.7, the owner's choice):
        // blue on the blue-tinted pill measured 3.8 to 1.
        .foregroundStyle(active ? DSColors.primaryText : DSColors.secondaryText)
        // A capsule around one line. At accessibility text sizes the words can take two lines, where a capsule's round
        // ends cut into them, so there the pill is a rounded rectangle, and only the background is shaped (5.7).
        .background(
            active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
            in: dynamicTypeSize.isAccessibilitySize
                ? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) : AnyShape(Capsule()))
    }

    private var statusText: String {
        if deviceCapabilities.supportsFoundationModels {
            return "Apple Intelligence Ready"
        } else {
            // "Preparing AI Models..." was shown for every reason, so it never ended on a device
            // that cannot run Apple Intelligence or has it switched off.
            return AppleIntelligenceCopy.status(for: deviceCapabilities.foundationModelUnavailability)
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
                Text("Lifetime")
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
                    // The card's own nickname and tagline ("AFM 3 Ecosystem", "Evidence-first routing ...") with
                    // Technical Details on; plain words otherwise (5.7 UI cleanup).
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.nickname : plainModelName)
                        .font(.subheadline.weight(.medium))
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.tagline : plainModelTagline)
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
                // The model's name only with Technical Details on (5.7 UI cleanup).
                modelCapabilityPill(icon: "photo.fill", label: settings.showTechnicalDetails ? "ADM 3 Visuals" : "Images")
                modelCapabilityPill(icon: "doc.text.fill", label: settings.showTechnicalDetails ? "RAG-Ready" : "Your documents")
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
                    // Corrected 2026-10-15: "after you approve each request" is untrue of Allow without asking,
                    // and on iOS and macOS 26 the reason it's off is the system, not the build.
                    Text(deviceCapabilities.supportsPrivateCloudCompute
                        ? "Apple's servers, for the writing step only, with your permission"
                        : DeviceCapabilities.pccRoutingCompiledIn
                            ? "Needs iOS or macOS 27. Every answer is written on this device."
                            : "Not in this build. Every answer is written on this device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Status indicator. The live snapshot decides once it has loaded: `supportsPrivateCloudCompute`
                // is only "compiled in and iOS or macOS 27", so the Simulator said Available above a quota line
                // saying Private Cloud Compute is unavailable there (2026-10-15).
                let pccAvailable = pccCapability?.pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute
                HStack(spacing: 4) {
                    Circle()
                        .fill(pccAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(pccAvailable ? "Available" : "Unavailable")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(pccAvailable ? .green : .orange)
                }
            }

            // The paragraph this replaces read "Apple's Private Cloud Compute (PCC) allows
            // OpenIntelligence to process complex queries with a massive 32,768 token
            // context window...". Three problems. It framed PCC as the thing that makes
            // the app work, which is backwards: `FoundationModelRoutePolicy` returns
            // `.onDevice` on every branch of the automatic path unless a prompt exceeds
            // the device window. "Massive" is doing work that a number should do. And the
            // 32,768 was hardcoded directly above a block that renders the *live* figure,
            // so the same screen could show two different numbers.
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                // Corrected 2026-10-15: the sentence named only the answer too large for the device.
                // `ModelExecutionPlanner` also sends a Deep Think or Maximum answer drawn from more than one
                // document (`complexityRequestsPCC`), and the model picker's Private Cloud Compute sends every one.
                Text("Answers are written on this device unless Private Cloud Compute is allowed: with Hybrid, for an answer whose passages don't fit in this device's model, or a Deep Think or Maximum answer drawn from more than one document; with Private Cloud Compute chosen in the model picker, for every answer drawn from your documents.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    pccWindowRow(
                        icon: "iphone",
                        label: "On this device",
                        value: onDeviceWindowDescription
                    )
                    Divider().padding(.leading, 30)
                    pccWindowRow(
                        icon: "cloud",
                        label: "Private Cloud Compute",
                        value: pccWindowDescription
                    )
                }
                .padding(.vertical, DSSpacing.xs)
                .background(DSColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))

                HStack {
                    Text("When to allow it")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("When to allow it", selection: $settings.pccSetting) {
                        ForEach(PCCSettings.allCases, id: \.self) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!deviceCapabilities.supportsPrivateCloudCompute)
                }

                Text("OpenIntelligence does not operate its own servers. Nothing is sent anywhere else. Reading, indexing and searching your documents all happen here regardless of this setting; only the final answer can ever leave.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            // This was four unlabelled grey paragraphs stacked on each other, followed by
            // a raw container path (/private/var/mobile/Library/Mobile Documents/...)
            // shown to every user. Nothing said which line was status, which was activity,
            // or what the path was for. They are labelled rows now, and the path moved
            // behind a disclosure since it exists for support and debugging rather than
            // for reading.
            VStack(spacing: 0) {
                syncDetailRow(label: "Status", value: workspaceSyncService.statusMessage)

                if let syncActivitySummary {
                    Divider().padding(.leading, DSSpacing.md)
                    syncDetailRow(label: "Last synced", value: syncActivitySummary)
                }

                if let sharedWorkspaceRefreshMessage {
                    Divider().padding(.leading, DSSpacing.md)
                    syncDetailRow(label: "Last action", value: sharedWorkspaceRefreshMessage)
                }
            }
            .background(DSColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))

            if let rootDescription = workspaceSyncService.workspaceRootDescription,
               workspaceSyncService.isUsingSharedWorkspace {
                DisclosureGroup("Storage location") {
                    Text(rootDescription)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DSSpacing.xs)
                }
                .font(.caption.weight(.medium))
                .tint(.secondary)
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

                // The first figure a curious user meets in Settings, and the one most
                // likely to be mistaken for a live measurement. Its definition says
                // plainly that it is a per-chip lookup rather than something the app
                // measured here.
                if settings.showTechnicalDetails {
                    HStack(spacing: 6) {
                        Text("Neural Engine: \(deviceService.npuTops) TOPS • \(coolingDescription)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        GlossaryInfoButton(termID: .tops, size: .caption2)
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 12) {
                    // Was "\(maxSteps) max sessions": 5 on an iPhone 15 Pro and 13 on an 18 GB M3 Pro, while Deep Think's
                    // chain stops at 8 sessions on every device (`AgenticPolicyService.maxSessionsForMode`). What does
                    // differ by device is the confidence it aims for (`optimizedAgenticConfig`) (5.7).
                    deviceCapabilityPill(icon: "brain.head.profile", label: "Deep Think", value: "aims for \(Int(deviceService.optimizedAgenticConfig().confidenceThreshold * 100))%")
                    deviceCapabilityPill(icon: "flame", label: "Thermal", value: deviceService.hasThermalHeadroom ? "High" : "Standard")
                }
            }
.padding(10)
.background(Color.purple.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Divider()

            // Device ID, Metal ceilings and Core ML routes: internals, with Technical Details on (5.7).
            if settings.showTechnicalDetails {
                hardwareEnvelopeSection(deviceService: deviceService)

                Divider()
            }

            // Context Window
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(settings.showTechnicalDetails ? "Context Window" : "How Much the Model Reads")
                        .font(.subheadline.weight(.medium))
                }

                // Dynamic explanation based on mode
                let agenticConfig = DeviceCapabilityService.shared.optimizedAgenticConfig()
                if settings.ragQualityMode.canonical == .maximum {
                    // Corrected 2026-10-15: the window is the one this device reports (8,192 on the owner's Mac,
                    // not 4K), "exhaustive Neural Engine synthesis" named hardware the app can't see, and Self-RAG 2.0
                    // is Maximum's check of the answer against its sources (`AgenticOrchestrator`), not what passes
                    // between sessions.
                    Text(
                        settings.showTechnicalDetails
                            ? "Maximum chains several reasoning sessions on Apple's model, each with a fresh window (\(onDeviceWindowDescription) on this device) carrying compressed findings from the last, and then checks the answer against its sources (Self-RAG 2.0)."
                            : "Maximum asks Apple's model several times in a row, each time with room for \(onDeviceWindowDescription) on this device and a summary of what it found before, then checks the answer against your documents.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text(
                        settings.showTechnicalDetails
                            ? "Deep Think's reasoning chain runs up to 8 sessions in a row on Apple's model, each with a fresh window (\(onDeviceWindowDescription) on this device) carrying compressed insights from the last, and research rounds can follow it when parts of the question are still uncovered. On the \(DeviceCapabilityService.shared.chipName) it aims for \(Int(agenticConfig.confidenceThreshold * 100))% confidence, and from the fifth session it can stop early once it has that confidence, has covered the question's parts and stops finding anything new."
                            : "Deep Think asks Apple's model up to 8 times in a row, each time with room for \(onDeviceWindowDescription) on this device and a summary of what it found before, and it can search again for parts of the question it hasn't covered. On the \(DeviceCapabilityService.shared.chipName) it aims to be \(Int(agenticConfig.confidenceThreshold * 100))% sure, and from the fifth time it can stop once it is, has covered the question and isn't finding anything new.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(
                        settings.showTechnicalDetails
                            ? "Standard runs one pass of Apple's model over the passages that fit its window (\(onDeviceWindowDescription) on this device), with verification gates and graph context packing. Use Deep Think or Maximum when you want several reasoning sessions."
                            : "Standard asks Apple's model once, with the passages that fit in \(onDeviceWindowDescription) on this device, and checks the answer against them. Deep Think and Maximum ask several times.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    if settings.ragQualityMode.canonical == .maximum {
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Per Session" : "Each Time", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "checkmark.seal", label: "Answer Check", value: settings.showTechnicalDetails ? "Self-RAG 2.0" : "Against your documents")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Per Session" : "Each Time", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: settings.showTechnicalDetails ? "Chain" : "Times", value: settings.showTechnicalDetails ? "up to 8 sessions" : "up to 8")
                    } else {
                        // "If Complex: 3 sessions (12K)" was untrue: Standard chains sessions only when a developer
                        // turns on `forceReasoningChain` (RAGService, `useReasoningChain`).
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Single Pass" : "Room", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: settings.showTechnicalDetails ? "Sessions" : "Times", value: "1")
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: settings.ragQualityMode)

            Divider()

            // Silicon-Native RAG Engine: vDSP, Metal shaders and batch sizes, with Technical Details on (5.7).
            if settings.showTechnicalDetails {
                siliconNativeRAGSection(deviceService: deviceService)

                Divider()
            }

            // GPU Acceleration Controls
            gpuAccelerationSection(deviceService: deviceService)

            Divider()

            // Live System Monitor: thermal state, memory, cores and the pipeline's own adjustments, with Technical
            // Details on (5.7).
            if settings.showTechnicalDetails {
                LiveSystemMonitorWrapper()

                Divider()
            }

            // Language Support
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Language Support")
                        .font(.subheadline.weight(.medium))
                }

                // The languages this device's model reports (`SystemLanguageModel.supportedLanguages`, iOS and macOS 26),
                // named in the person's own language. Through the first 5.7 builds this was a list of 19 typed in by
                // hand as "verified Apple Intelligence languages as of iOS 26.0+", which nothing checked against the
                // device, with "Apple routes automatically" under it, which no code here does (2026-10-20).
                if let languages = modelLanguageNames, !languages.isEmpty {
                    Text(settings.showTechnicalDetails ? "SystemLanguageModel.supportedLanguages on this device:" : "Apple's model on this device answers in:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(languages.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Apple's model hasn't said which languages it answers in on this device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

                    // This is the densest jargon in the app, and it is reached by anyone
                    // curious enough to open Device & Performance rather than only by
                    // developers. The rows that name a concept carry its definition; the
                    // rows that report a raw system value do not, because there is nothing
                    // to define about a Metal device name.
                    VStack(alignment: .leading, spacing: 6) {
                        hardwareLimitRow(icon: "number", label: "Device ID", value: envelope.deviceIdentifier, term: .chip)
                        hardwareLimitRow(icon: "memorychip", label: "Metal Device", value: envelope.metal.deviceName)
                        hardwareLimitRow(icon: "square.stack.3d.up", label: "Unified Memory", value: "\(envelope.metal.hasUnifiedMemory ? "Yes" : "No") • \(envelope.metal.workingSetDescription) working set", term: .unifiedMemory)
                        hardwareLimitRow(icon: "square.grid.3x3.fill", label: "Threadgroup Ceiling", value: "\(envelope.metal.maxThreadsPerThreadgroup) threads • \(envelope.metal.maxThreadgroupMemoryKB) KB shared")
                        hardwareLimitRow(icon: "gauge.with.needle", label: "GPU Ceiling", value: gpuCeilingText, term: .gpuProfile)
                        hardwareLimitRow(icon: "cpu", label: "CoreML Route", value: envelope.coreMLRoute, term: .neuralEngine)
                        hardwareLimitRow(icon: "text.badge.checkmark", label: "Embedding Route", value: envelope.embeddingRoute, term: .vector)
                        hardwareLimitRow(icon: "eye.fill", label: "Vision / ADM 3 Ceiling", value: "\(envelope.visionOperationConcurrency) ops • \(envelope.visionCooldownMilliseconds) ms cooldown", term: .ocr)
                        hardwareLimitRow(icon: "photo.stack", label: "Adaptive PDF Budget", value: imageBudgetText, term: .ocr)
                        hardwareLimitRow(icon: "function", label: "Vector Search Ceiling", value: "\(envelope.vectorBatchSize) batch • matrix @ \(envelope.batchMatrixMultiplyThreshold)+", term: .searchBatch)
                    }
                }
                .padding(12)
                .background(Color.indigo.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            @ViewBuilder
            private func hardwareLimitRow(icon: String, label: String, value: String, term: GlossaryTermID? = nil) -> some View {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundColor(.indigo)
                        .frame(width: 16)
                    Text(label)
                        .font(.caption.weight(.medium))
                    if let term {
                        GlossaryInfoButton(termID: term, size: .caption2)
                    }
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
            // "GPU level ≥ 60%" named a percentage the GPU setting no longer shows; the gate is
            // `searchesLargeLibrariesOnGPU(for:)` with the stores' own thresholds (5.7).
            Text("Vector math uses Apple's Accelerate framework (vDSP/BLAS) on the CPU. With the GPU setting on Performance or Maximum, Metal shaders take over cosine similarity for a library of 1,000 passages or more and the diversity step for more than 50 results. Batch sizes are set for the \(deviceService.chipName).")
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
                    value: "\(deviceService.vectorBatchSize)",
                    term: .searchBatch
                )
                siliconInfoPill(
                    icon: "text.badge.checkmark",
                    label: "Embed Batch",
                    value: "\(deviceService.embeddingBatchSize)",
                    term: .embedBatch
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
    private func siliconInfoPill(icon: String, label: String, value: String, term: GlossaryTermID? = nil) -> some View {
        let pill = HStack(spacing: 4) {
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

        if let term {
            pill
                .contentShape(Capsule())
                .definedTerm(term)
        } else {
            pill
        }
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

            // Until 5.7: "Choose how OpenIntelligence schedules GPU-capable work...". The profiles cover the Core ML
            // embedding model, the Core Image cleanup of scanned pages and Metal vector search, never Apple's model.
            Text("Sets which chips the app's own embedding model, its large searches and an extra cleanup pass over scanned PDF pages can use. Apple's frameworks make the final choice among the ones allowed. Answers from Apple's model, text recognition and the reranker work the same way in every profile.")
                .font(.caption)
                .foregroundColor(.secondary)

            if deviceService.activeGPUExecutionProfile != gpuProfile {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("On the \(deviceService.chipName), \(gpuProfile.displayName) runs as \(deviceService.activeGPUExecutionProfile.displayName), to keep long imports stable.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Discrete profiles avoid implying a precise GPU percentage that Core ML cannot promise.
            VStack(alignment: .leading, spacing: 10) {
                Text("Execution Profile")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    ForEach(GPUExecutionProfile.allCases) { profile in
                        executionProfileCard(profile)
                    }
                }

                // What the selected profile actually does, listed rather than
                // summarised, so switching between them reads as cause and effect.
                VStack(alignment: .leading, spacing: 7) {
                    Text(gpuProfile.engagement.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(gpuProfile.engagement.effects, id: \.self) { effect in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(gpuModeColor(for: gpuProfile).opacity(0.75))
                            Text(effect)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .animation(.snappy(duration: 0.25), value: gpuProfile)

                // What the profile does when an import goes on in the background, for this device (5.7).
                Text(backgroundImportNote(for: gpuProfile, deviceService: deviceService))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Changes apply from the next import, and to searching by the next time the app opens at the latest. Every scanned page is prepared for text recognition on the GPU in every profile.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.showTechnicalDetails {
                    Text("Covered: the Core ML embedding model (the default for a new library on iPhone and iPad), an extra Core Image pass over rendered PDF pages, and Metal for vector search over 1,000 or more passages. Not covered: a Core AI library (the default on a Mac with macOS 27), which embeds on the GPU in every profile; the reranker, which may use all three chips; and text recognition, whose page preparation runs on the GPU.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: gpuProfile)

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(settings.showTechnicalDetails ? "Adaptive Visual Ingestion" : "Reading PDFs and Images")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Automatic")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(
                    settings.showTechnicalDetails
                        ? "PDFs and images now use one automatic source-preservation strategy. The engine raises OCR detail, structure recovery, and visual analysis when pages are garbled, table-heavy, columnar, image-heavy, or small-text risky, and stays lighter on clean text-native pages."
                        : "A PDF page or an image gets a closer reading when it needs one: text that comes out garbled, tables, columns, pictures or small print. A page whose text is already clean gets a lighter one."
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // The live policy, read from the same properties the execution paths consult, so it shows the
            // device's ceiling, a background import and the Simulator's CPU-only Core ML as they are (5.7: behind
            // Technical Details; the "Thermal Impact" row is gone, it ranked Maximum hotter than Performance when in
            // the foreground the two run the same rules).
            if settings.showTechnicalDetails {
            VStack(alignment: .leading, spacing: 6) {
                gpuSettingRow(
                    icon: "cpu",
                    label: "Embedding model, searching",
                    value: deviceService.preferredComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding model, importing",
                    value: deviceService.embeddingComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Extra PDF page pass",
                    value: deviceService.useGPUForPDFRendering ? "On, Core Image on the GPU" : "Off"
                )
                gpuSettingRow(
                    icon: "function",
                    label: "Large searches",
                    value: deviceService.useMetalForVectorOps ? "Metal on the GPU" : "Accelerate on the CPU"
                )
            }
            .animation(.easeInOut(duration: 0.2), value: gpuProfile)

            Divider()
                .padding(.vertical, 2)

            // Pipeline concurrency remains tier-based rather than profile-controlled.
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipeline Concurrency")
                    .font(.subheadline.weight(.medium))
                Text("Set by the \(deviceService.chipName), not by the profile.")
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
            }
            // Until 5.7 a warning here said Maximum "may cause device heating during large document ingestion".
            // An import runs the same rules in Balanced, Performance and Maximum while the app is open, so the
            // warning singled out a profile that imports no differently.
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            gpuProfile = DeviceCapabilityService.shared.gpuExecutionProfile
        }
    }

    /// What an import does in the background with `profile` on this device (5.7). The rule is `BackgroundGPUAllowance`,
    /// the one `BackgroundTaskService` applies when it asks iOS to let the import go on.
    private func backgroundImportNote(for profile: GPUExecutionProfile, deviceService: DeviceCapabilityService) -> String {
        // The policy is worked out when the import is handed to iOS, in the foreground, and kept
        // (`BackgroundTaskService.continuedProcessingPolicy`), so the conditions read "when it starts". What the GPU grant
        // changes is what the import may use; a file already being embedded keeps the model it loaded.
        #if os(iOS) && !targetEnvironment(macCatalyst)
            let noun = deviceService.formFactor.deviceNoun
            let allowance = deviceService.backgroundGPUAllowance
            let admitting = deviceService.backgroundGPUProfiles
            guard BackgroundTaskService.shared.systemOffersBackgroundGPU else {
                return "In the background, iOS doesn't offer this \(noun) the GPU, so an import goes on there without it."
            }
            guard !admitting.isEmpty else {
                return "In the background, no profile asks iOS to keep the GPU for an import on this \(noun)."
            }
            let when: String
            if allowance.chargingOnly {
                when = "when the \(noun) is charging as the import starts"
            } else if allowance.minimumBatteryPercent > 0 {
                when = "when the \(noun) is charging or has \(allowance.minimumBatteryPercent)% battery or more as the import starts"
            } else {
                when = "at any battery level"
            }
            guard admitting.contains(profile) else {
                let names = ListFormatter.localizedString(byJoining: admitting.map(\.displayName))
                let verb = admitting.count == 1 ? "does" : "do"
                return "In the background, \(profile.displayName) doesn't ask iOS to keep the GPU for an import on this \(noun). \(names) \(verb), \(when)."
            }
            return "In the background, an import asks iOS to keep the GPU \(when), unless Low Power Mode is on, the \(noun) is hot, memory is short or iOS has asked apps to use less."
        #else
            return "On a Mac, this setting works the same way while the app is in the background."
        #endif
    }

    private var gpuModeName: String {
        DeviceCapabilityService.shared.activeGPUExecutionProfile.displayName
    }

    private var gpuModeColor: Color {
        gpuModeColor(for: DeviceCapabilityService.shared.activeGPUExecutionProfile)
    }

    private func gpuModeColor(for profile: GPUExecutionProfile) -> Color {
        switch profile {
        case .efficiency: return .blue
        case .balanced: return .green
        case .performance: return .orange
        case .maximum: return .red
        }
    }

    /// One profile card.
    ///
    /// A menu showed one option and hid three. The whole point of this control is
    /// that the choice changes which silicon runs the work, so all four are on
    /// screen with their engines visible before anything is tapped.
    @ViewBuilder
    private func executionProfileCard(_ profile: GPUExecutionProfile) -> some View {
        let isSelected = gpuProfile == profile
        let accent = gpuModeColor(for: profile)

        Button {
            guard gpuProfile != profile else { return }
            DSHaptics.light()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                gpuProfile = profile
            }
            DeviceCapabilityService.shared.gpuExecutionProfile = profile
        } label: {
            VStack(spacing: 5) {
                Text(profile.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? accent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // The engine badges, with Technical Details on (5.7). With it off, the lines under the cards name
                // each engine in words for the profile chosen, and VoiceOver reads them from the hint below.
                if settings.showTechnicalDetails {
                    HStack(spacing: 2.5) {
                        engineChip("CPU", isOn: profile.engagement.usesCPU, accent: accent, isSelected: isSelected)
                        engineChip("ANE", isOn: profile.engagement.usesNeuralEngine, accent: accent, isSelected: isSelected)
                        engineChip("GPU", isOn: profile.engagement.usesGPU, accent: accent, isSelected: isSelected)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.16 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accent.opacity(isSelected ? 0.55 : 0.0), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.0 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.displayName) execution profile")
        .accessibilityHint(profile.engagement.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A single engine badge. Dimmed rather than hidden when a profile does not use
    /// it, so the difference between profiles is visible at a glance.
    private func engineChip(_ name: String, isOn: Bool, accent: Color, isSelected: Bool) -> some View {
        Text(name)
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            // One line, smaller rather than broken: in a quarter-width card on an iPhone 15 Pro the badges wrapped
            // as "CP U" and "AN E" (2026-10-21).
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundColor(isOn ? (isSelected ? accent : .secondary) : .secondary.opacity(0.28))
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1.5)
            .background(
                Capsule().fill(isOn ? accent.opacity(isSelected ? 0.20 : 0.08) : Color.clear)
            )
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

            // The step-by-step list is the pipeline's own vocabulary, so it waits behind Technical Details (5.7 UI
            // cleanup); its lines are claims about code all the same (.claude/rules/user-facing-copy.md).
            if !settings.showTechnicalDetails {
                Text("Technical Details, in Appearance, lists the techniques behind the selected mode.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
            Divider()

            // Mode-specific features
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: modeHeaderIcon)
                        .foregroundColor(modeAccentColor)
                        .font(.caption)
                    Text(modeHeaderTitle)
                        .font(.subheadline.weight(.medium))
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
        items.append(.init(id: "native-embed", icon: "cpu.fill", label: "Native Embeddings", desc: "MiniLM sentence embeddings on device, through Core ML or Core AI", color: .green))
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
        // Only for the modes that use it: Standard never runs HyDE (`RAGQualityMode.usesHyDE`) (5.7).
        if settings.ragQualityMode.usesHyDE {
            items.append(.init(id: "hyde", icon: "sparkles", label: "HyDE Query Expansion", desc: "LLM generates hypothetical doc, embedded for cosine retrieval", color: .green))
        }

        // Deep Think only: Standard and Maximum keep the passages whole (`RAGQualityMode.usesContextualCompression`) (5.7).
        if settings.ragQualityMode.usesContextualCompression {
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
            if DeviceCapabilities.pccRoutingCompiledIn {
                items.append(.init(id: "pcc-escalation", icon: "cloud.lock.fill", label: "Private Cloud Compute", desc: "An answer too large for this device, or a Deep Think or Maximum answer from more than one document, can be written on Apple's servers with your permission", color: .purple))
            }
            items.append(.init(id: "native-spotlight", icon: "magnifyingglass", label: "Spotlight Indexing", desc: "Your documents are indexed into Apple Core Spotlight", color: .purple))
            items.append(.init(id: "intent-route", icon: "signpost.right.and.left", label: "Intent Routing", desc: "Classifies query as lookup/procedure/compare/summarize", color: .purple))
            items.append(.init(id: "multi-query", icon: "magnifyingglass.circle.fill", label: "Multi-Query Expansion", desc: "LLM generates diverse search queries for broader retrieval", color: .purple))
            items.append(.init(id: "graph-expand", icon: "point.3.connected.trianglepath.dotted", label: "2-Hop Graph Expansion", desc: "Entity-based traversal finds related chunks", color: .purple))
            items.append(.init(id: "recursive-loop", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Recursive Research Loop", desc: "Autonomous [SEARCH:]/[ANSWER] protocol until confident", color: .purple))
            items.append(.init(id: "verify-gates", icon: "checkmark.seal.fill", label: "Verification Gates A–I", desc: "9-stage anti-hallucination checks before answering (Confidence, Coverage, Numeric, Contradiction, Semantic, Quote, Quality, Completeness, Isolation)", color: .purple))
            items.append(.init(id: "confidence-cal", icon: "function", label: "Confidence Calibration", desc: "Sigmoid-calibrated scores from rerank + margin + evidence count", color: .purple))
            items.append(.init(id: "extract-summary", icon: "text.line.first.and.arrowtriangle.forward", label: "Extractive Summarization", desc: "Sentence selection via bi-encoder for summarize intent", color: .purple))
            items.append(.init(id: "graph-pack", icon: "rectangle.compress.vertical", label: "Graph Context Packing", desc: "Optimal token budget allocation across evidence", color: .purple))
            // Deep Think's chain stops at 8 sessions (`AgenticPolicyService`); the step count this line showed was the
            // orchestrator's, and it described Maximum with Deep Think's numbers. Maximum has its own line below (5.7).
            if !settings.ragQualityMode.isUnlimitedMode {
                items.append(.init(id: "orchestrator", icon: "brain.head.profile", label: "Agentic Orchestrator", desc: "Up to 8 sessions, aiming for \(Int(DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold * 100))% confidence on this device", color: .purple))
            }
            // No tool line here since 2026-10-14. It read "4 Tool Functions" while
            // `FoundationModelToolRegistry.createTools` registers six, and neither number
            // was true of these modes: every model call Deep Think and Maximum make passes
            // `disableTools: true` (the fourteen `generateWithProperConsent` calls in
            // `AgenticOrchestrator`, the chain sessions through `disableToolsForSession`),
            // so no tool reaches the model in them. Re-add a line when one does.
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
            items.append(.init(id: "token-budget", icon: "cpu", label: "Up to 50 Sessions", desc: "Each gets a fresh window of the on-device model; stops early once it converges", color: .orange))
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
                    // Plain by default; the pipeline's own words with Technical Details on (5.7).
                    Text(settings.showTechnicalDetails ? mode.description : plainModeSummary(for: mode))
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

    /// What a mode is for, in plain words, under its name (5.7 UI cleanup). Technical Details shows `description`.
    private func plainModeSummary(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard: return "Quick answers to everyday questions"
        case .deepThink: return "For comparisons and harder questions"
        case .maximum: return "For the hardest questions"
        default: return mode.displayName
        }
    }

    /// What a mode does, in plain words (5.7 UI cleanup), each a claim about code. Standard checks its answer with the
    /// verification gates and searches again only when the first search finds little (the retrieval cascade); it skips
    /// the source-only check when the gates pass, so it does not run "every check". Deep Think's reasoning chain stops at
    /// 8 sessions (`AgenticPolicyService`, `min(8, sessionCount + 4)`), but research rounds can follow it, so its badge
    /// names no number; its precision lookup answers without the gates, so it has no "checks" badge. Maximum's loop, when retrieval is good enough to
    /// reach it, stops when its findings stop changing, at 50 sessions at most and fewer when few passages match
    /// (`executeTrueUnlimitedReasoning`); its 0.98 target is unreachable by the code's own comment, so no "98%" here.
    private func modeCallout(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard:
            return "Searches your documents and checks the answer against them, searching again only when the first search finds little. The fastest mode."
        case .deepThink:
            return "Can search several times and build the answer in steps, for comparisons and questions that need more than one passage."
        case .maximum:
            let work = "Can make up to 50 passes over your documents, fewer when only a few passages match, and stops when its findings stop changing."
            if entitlementStore.hasUnlimitedMaximumMode {
                return "\(work) Slowest, with no daily limit on your plan."
            }
            return "\(work) Slowest. Free plans get \(QuotaPolicy.freeMaximumModeDailyLimit) a day, and you have \(entitlementStore.maximumModeRemainingUses) left today."
        default:
            return mode.description
        }
    }

    private func modeBadges(for mode: RAGQualityMode) -> [String] {
        switch mode.canonical {
        case .standard:
            return ["Fastest", "Checks its answer", "Best for lookups"]
        case .deepThink:
            return ["Several passes", "Best for analysis"]
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return ["No daily limit", "Up to 50 passes", "Slowest"]
            }
            return ["\(QuotaPolicy.freeMaximumModeDailyLimit) a day", "\(entitlementStore.maximumModeRemainingUses) left today", "Up to 50 passes"]
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

    /// The selected model in plain words. Citation Scout answers with spans of the passages and writes nothing
    /// (`LLMModelType`: "Extractive only, no generation"); Apple's model can reach Private Cloud Compute only with
    /// the person's consent (Docs/PRIVACY_AND_ROUTING.md).
    private var plainModelName: String {
        switch settings.selectedModel {
        case .appleIntelligence: "Apple's model"
        case .onDeviceAnalysis: "Quotes only"
        }
    }

    private var plainModelTagline: String {
        switch settings.selectedModel {
        case .appleIntelligence:
            "Writes answers from your documents on this device, and can use Private Cloud Compute when you allow it."
        case .onDeviceAnalysis:
            "Answers with sentences taken word for word from your documents, and no model writes anything."
        }
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
                // The page's title and the model card above already say "Apple Intelligence" (5.7 UI cleanup).
                Text(settings.showTechnicalDetails ? "Apple Intelligence" : "Features")
                    .font(.headline)
                Spacer()
                Text(settings.showTechnicalDetails ? "\(activeAIFeatureCount)/\(totalAIFeatureCount)" : "\(activeAIFeatureCount) of \(totalAIFeatureCount) on")
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
                    subtitle: settings.showTechnicalDetails ? "Conversational follow-up suggestions" : "Suggested follow-up questions under an answer",
                    isOn: $settings.enableSmartReplies
                )

                aiFeatureToggleRow(
                    icon: "tag.fill",
                    color: .orange,
                    title: "Content Tagging",
                    subtitle: settings.showTechnicalDetails ? "LLM-powered topic, action & object tagging" : "Labels each document's topics with Apple's model as it's added",
                    isOn: $settings.enableContentTagging
                )

                aiFeatureToggleRow(
                    icon: "magnifyingglass",
                    color: .pink,
                    title: "Spotlight Indexing",
                    subtitle: settings.showTechnicalDetails ? "System-wide search integration" : "Find your documents from Spotlight search",
                    isOn: $settings.enableSpotlightIndexing
                )

                aiFeatureToggleRow(
                    icon: "arrow.clockwise.circle.fill",
                    color: .teal,
                    title: "Background Maintenance",
                    subtitle: settings.showTechnicalDetails ? "Scheduled index health checks & Spotlight refresh" : "Checks the search index and refreshes Spotlight on a schedule",
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

                // Voice input is the chat field's dictation button (`VoiceDictation`), built in 5.7;
                // through 5.6 this line claimed it with no microphone code in the app. The Mac has the
                // button too since the audio-input entitlement went in (2026-10-14).
                aiFeatureInfoRow(
                    icon: "waveform",
                    color: .green,
                    title: "Speech Analysis",
                    subtitle: speechAnalysisSubtitle
                )

                aiFeatureInfoRow(
                    icon: "character.book.closed.fill",
                    color: .purple,
                    title: "Translation",
                    subtitle: settings.showTechnicalDetails ? "Multilingual document analysis" : "Searches across languages when a library has a translation language set"
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
                    subtitle: settings.showTechnicalDetails ? "Seamless AppIntents integration via Shortcuts" : "Siri can tell which document or chat is on your screen"
                )

                aiFeatureInfoRow(
                    icon: "photo.on.rectangle.angled",
                    color: .mint,
                    title: "Image Playground",
                    subtitle: settings.showTechnicalDetails
                        ? "Interactive ADM 3 image creation from document content"
                        : "Create an image from a document's content"
                )

                aiFeatureInfoRow(
                    icon: "lightbulb.max.fill",
                    color: .yellow,
                    title: "App Tips",
                    subtitle: settings.showTechnicalDetails ? "Contextual guidance & onboarding" : "Tips that point out features as you go"
                )

                aiFeatureInfoRow(
                    icon: "text.book.closed.fill",
                    color: .brown,
                    // "Gazetteer" is NaturalLanguage's name for it (`NLGazetteer`), kept with Technical Details on (5.7).
                    title: settings.showTechnicalDetails ? "Gazetteer" : "Vocabulary",
                    subtitle: settings.showTechnicalDetails ? "Builds domain vocabulary during ingestion" : "Learns the special terms in your documents as they're added"
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
                Text("\(RAGAppShortcutsProvider.appShortcuts.count) shortcuts")
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
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal)
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    #if os(iOS)
                        // Apple's own tip view: it shows the phrase Siri has registered for the
                        // action, in the person's language, so it cannot drift from the provider.
                        SiriTipView(intent: QueryDocumentsIntent())
                    #endif
                    // One row per App Shortcut, with the first phrase it registers
                    // (RAGAppShortcutsProvider). Keep the two in step.
                    shortcutCommandRow(title: "Ask My Documents", phrase: "Ask OpenIntelligence a question")
                    shortcutCommandRow(title: "List Documents", phrase: "List my documents in OpenIntelligence")
                    shortcutCommandRow(title: "Import Status", phrase: "Is OpenIntelligence still importing")
                    shortcutCommandRow(title: "Ask About a Document", phrase: "Ask OpenIntelligence about [Document Name]")
                    shortcutCommandRow(title: "Summarize a Document", phrase: "Summarize [Document Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Compare Two Documents", phrase: "Compare documents in OpenIntelligence")
                    shortcutCommandRow(title: "Ask a Library", phrase: "Ask [Library Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Add a File", phrase: "Add this document to OpenIntelligence")
                    shortcutCommandRow(title: "Save a Web Page", phrase: "Save this page to OpenIntelligence")
                    shortcutCommandRow(title: "Find Passages", phrase: "Find passages in OpenIntelligence")
                }

                Divider().padding(.horizontal)

                Text(settings.showTechnicalDetails ? "Trust & Hallucination Prevention" : "Answers Are Checked")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.showTechnicalDetails ? "Strict Verification Gates" : "The same checks as the chat")
                            .font(.subheadline.weight(.semibold))
                        // The actions ask through `RAGService.query`, the chat's own path and checks. "Needs Verification"
                        // is what `SourceOnlyAnswerService` puts in front of a drafted answer when its check abstains,
                        // with the reason; through 5.6 this said Siri returned a "dialog instead of hallucinating",
                        // which is not what happens (2026-10-20).
                        Text(
                            settings.showTechnicalDetails
                                ? "Siri and Shortcuts ask through RAGService.query, the chat's own pipeline and verification gates. When the source-only check abstains, the answer is prefixed with \"[Needs Verification]\" and its reason (SourceOnlyAnswerService)."
                                : "An answer from Siri or Shortcuts is checked against your documents the same way as one in the chat. When the last check can't back it, the answer starts with \"Needs Verification\" and says why.")
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
                Text("\(Self.shortcutActionGroups.reduce(0) { $0 + $1.actions.count }) Actions Available")
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
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.shortcutActionGroups, id: \.title) { group in
                        shortcutsActionGroup(title: group.title, actions: group.actions)
                    }
                    #if os(iOS)
                        // Opens the Shortcuts app on this app's actions.
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                            .frame(maxWidth: .infinity)
                    #endif
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Every action the app gives Shortcuts, by the name Shortcuts shows, with what it does. The
    /// count on the card is the count of this list, and each line is a claim about an action's
    /// code: change both together. "Scan a Document" exists on iPhone and iPad only.
    private static var scanActionForThisPlatform: [String: String] {
        #if os(iOS)
            return ["Scan a Document": "Opens the app on the camera."]
        #else
            return [:]
        #endif
    }

    private static let shortcutActionGroups: [(title: String, actions: [String: String])] = [
        (
            "Add", [
                "Add to Library": "Adds a file, a web page or text to a library you choose.",
                "Add a File": "Adds a file to your active library.",
                "Save a Web Page": "Downloads a page and adds its text to your active library.",
                "Add a Document": "Opens the app on the file picker.",
            ].merging(scanActionForThisPlatform) { current, _ in current }
        ),
        (
            "Ask", [
                "Ask My Documents": "Answers a question from a library, in the mode you pick, and returns the answer with its sources.",
                "Ask About a Document": "Answers a question from one document only, in Standard.",
                "Ask a Library": "Answers a question from one library.",
                "Summarize a Document": "Writes a summary of one document.",
                "Compare Two Documents": "Compares what two documents say about a topic.",
                "Ask About an Image": "Reads the text in an image and answers a question about it.",
                "Search with a Photo": "Reads the text in a photo and asks your library about it.",
                "Check a Claim": "Says whether your active library holds up a sentence, and names the passage it checked.",
            ]
        ),
        (
            "Find and Open", [
                "Find Passages": "Returns the passages that match a search, without writing an answer.",
                "List Documents": "Returns the documents in your libraries, or in one.",
                "List Conversations": "Returns the saved conversations in a library.",
                "Open Library": "Opens the app on a library.",
                "Open Document": "Opens a document's page in its library.",
            ]
        ),
        (
            "Libraries and Conversations", [
                "Create Library": "Creates a library and returns it.",
                "Set Active Library": "Chooses the library that questions and imports use.",
                "Start a Conversation": "Opens the app on a new conversation.",
                "Export Conversation": "Returns a saved conversation as a Markdown, JSON Lines or PDF file.",
                "Delete Documents": "Deletes documents with their passages, after asking.",
            ]
        ),
        (
            "Settings", [
                "Set Answer Mode": "Sets the chat's answer mode: Standard, Deep Think or Maximum.",
                "Get Settings": "Returns the answer mode and the active library.",
            ]
        ),
        (
            "Status", [
                "Check Import Status": "Says whether imports are queued or running.",
                "Get Embedding Model": "Returns the name of the embedding model the active library uses.",
            ]
        ),
    ]

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
            // The title is the switch's name for VoiceOver; `labelsHidden()` keeps it off the screen (5.7).
            Toggle(title, isOn: isOn)
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

                // The chat's technical view (5.7)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Technical Details")
                            .font(.subheadline.weight(.medium))
                        Text("In the chat: the live stats, each step as it runs, and the answer mode, reasoning and confidence under an answer. In Settings: the techniques behind each mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("Technical Details", isOn: $settings.showTechnicalDetails)
                        .labelsHidden()
                        .tint(.accentColor)
                        .onChange(of: settings.showTechnicalDetails) { _, _ in
                            DSHaptics.toggle()
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()
                    .padding(.horizontal)

                // Silicon HUD Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telemetry HUD")
                            .font(.subheadline.weight(.medium))
                        // Was "Real-time model routing and token telemetry"; the X-Ray shows neither (5.7).
                        Text("A floating map of the chip: this app's CPU use, the work it sends to the Neural Engine and GPU, and free memory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("Telemetry HUD", isOn: $settings.showSiliconHUD)
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
                            // Its name and the number shown beside it, for VoiceOver (5.7).
                            .accessibilityLabel("Glow Intensity")
                            .accessibilityValue("\(Int(settings.hudGlowIntensity * 100))%")
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
                            // Was "Show ops count and latency"; with it on the legend shows each chip's activity and free
                            // memory, and with it off "idle" (`HardwareTelemetryState.componentActivities`) (5.7).
                            Text("Show each chip's activity and free memory in the legend")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Live Metrics", isOn: $settings.hudShowMetrics)
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
                        Toggle("Taptic Engine", isOn: $settings.hudShowTaptic)
                            .labelsHidden()
                            .tint(.pink)
                            .onChange(of: settings.hudShowTaptic) { _, _ in
                                DSHaptics.toggle()
                            }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                #if os(macOS)
                    Divider()
                        .padding(.horizontal)

                    // The menu bar item (5.7), on until it is turned off here.
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Menu Bar")
                                .font(.subheadline.weight(.medium))
                            Text("Ask, add documents or search from the menu bar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("Menu Bar", isOn: $showsMenuBarItem)
                            .labelsHidden()
                            .tint(.purple)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                #endif
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

    private var speechAnalysisSubtitle: String {
        settings.showTechnicalDetails ? "Audio transcription & voice input" : "Transcribes audio files and what you say"
    }

    private func shareApp() {
        let items: [Any] = [
            "I'm using OpenIntelligence for private, on-device AI and RAG search. Check it out on the App Store!",
            OpenIntelligenceLinks.sharedAppStoreURL
        ]
        
        #if canImport(UIKit)
        // The sheet's header shows the app's name and icon rather than the bare address (5.7).
        let activityVC = UIActivityViewController(
            activityItems: PreviewedShareItem.items(items, preview: .app), applicationActivities: nil)
        
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
        let preview = ShareSheetPreview.app
        let picker = NSSharingServicePicker(items: [
            items[0],
            NSPreviewRepresentingActivityItem(
                item: OpenIntelligenceLinks.sharedAppStoreURL, title: preview.title, image: nil,
                icon: ShareSheetPreview.appIcon),
        ])
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
