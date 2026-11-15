//
//  SettingsView+List.swift
//  OpenIntelligence
//
//  Part of SettingsView, moved from SettingsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
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

extension SettingsView {
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

    /// The Settings row each tour tip points at (5.8).
    private static func tourStep(for id: SettingsEntryID) -> TourStep? {
        switch id {
        case .howItWorks: .howItWorks
        case .glossary: .glossary
        case .privateCloudCompute: .privateCloud
        case .siriShortcuts: .siri
        default: nil
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
        let keywords: [String]

        static let all: [SettingsEntry] = [
            // First row of the first group on purpose. This answers the questions a user
            // has before they have opinions about retrieval depth, and burying it under
            // About would defeat the reason it exists.
            .init(
                id: .howItWorks, group: .intelligence,
                title: "How This Works",
                subtitle: "What happens to a document, and what stays on this device",
                icon: "questionmark.circle",
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
                icon: "character.book.closed",
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
                subtitle: "Standard, Deep Think or Maximum, and how much each reads",
                icon: "sparkles",
                keywords: [
                    "standard", "deep think", "maximum", "quality", "reasoning", "verification", "gates", "agentic",
                ]
            ),
            .init(
                id: .appleIntelligence, group: .intelligence,
                title: "Apple Intelligence",
                subtitle: "On-device features and the active model",
                icon: "apple.logo",
                keywords: [
                    "smart replies", "content tagging", "spotlight", "writing tools", "speech", "translation", "model",
                    "foundation models",
                ]
            ),
            .init(
                id: .privateCloudCompute, group: .intelligence,
                title: "Private Cloud Compute",
                subtitle: "When a question may leave this device",
                icon: "cloud",
                keywords: ["pcc", "cloud", "privacy", "consent", "routing", "context window", "quota"]
            ),
            .init(
                id: .librariesSync, group: .library,
                title: "Libraries & iCloud",
                subtitle: "Sharing your libraries between devices",
                icon: "icloud",
                keywords: ["icloud", "sync", "workspace", "shared", "libraries", "containers"]
            ),
            .init(
                id: .devicePerformance, group: .device,
                title: "Device & Performance",
                subtitle: "Your chip, memory and Compute Profile",
                icon: "cpu",
                keywords: [
                    "chip", "neural engine", "tops", "gpu", "metal", "memory", "ram", "thermal", "context window",
                    "batch", "languages",
                ]
            ),
            .init(
                id: .appearance, group: .device,
                title: "Appearance",
                subtitle: "Accent colour and the hardware HUD",
                icon: "paintbrush",
                keywords: [
                    "accent", "colour", "color", "theme", "hud", "silicon", "telemetry", "telemetry hud", "x-ray",
                    "xray", "glow", "haptics", "technical", "technical details", "console", "stats", "simple",
                ]
            ),
            .init(
                id: .notifications, group: .device,
                title: "Notifications",
                subtitle: "When an import or a long answer finishes",
                icon: "bell.badge",
                keywords: [
                    "notifications", "notify", "alert", "banner", "finished", "import", "deep think", "maximum",
                    "background",
                ]
            ),
            .init(
                id: .plan, group: .account,
                title: "Plan & Usage",
                subtitle: "Documents, libraries, and Maximum runs",
                icon: "creditcard",
                keywords: [
                    "plan", "billing", "subscription", "pro", "lifetime", "quota", "limit", "upgrade", "purchase",
                ]
            ),
            .init(
                id: .siriShortcuts, group: .account,
                title: "Siri & Shortcuts",
                subtitle: "Voice commands and automation actions",
                icon: "mic",
                keywords: ["siri", "shortcuts", "app intents", "automation", "voice"]
            ),
            .init(
                id: .advanced, group: .system,
                title: "Advanced",
                subtitle: "Temperature, response length, system prompt",
                icon: "slider.horizontal.3",
                keywords: [
                    "system prompt", "instructions", "temperature", "max tokens", "response length", "top p", "top k",
                    "sampling", "penalty", "generation", "tuning", "context length", "context window",
                ]
            ),
            .init(
                id: .developer, group: .system,
                title: "Developer & Diagnostics",
                subtitle: "RAG audit, chunk inspector, telemetry",
                icon: "wrench.and.screwdriver",
                keywords: [
                    "developer", "diagnostics", "debug", "logging", "telemetry", "chunk", "audit", "validation",
                    "benchmark",
                ]
            ),
            .init(
                id: .about, group: .system,
                title: "About",
                subtitle: "Version, device, and what's new",
                icon: "info.circle",
                keywords: [
                    "about", "version", "release notes", "what's new", "support", "feedback", "privacy policy", "terms",
                ]
            ),
            .init(
                id: .versionHistory, group: .system,
                title: "Version History",
                subtitle: "Every release, and what changed in it",
                icon: "clock.arrow.circlepath",
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
    var settingsList: some View {
        List {
            Section {
                heroSummaryRow
            }

            ForEach(SettingsGroup.allCases) { group in
                let entries = visibleEntries(in: group)
                if !entries.isEmpty {
                    // A header in the readable gray (5.7): the List's own header "nearly passed" Apple's contrast audit.
                    Section {
                        ForEach(entries) { entry in
                            Group {
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
                                            // The tour's step is used when its page opens (5.8). It was a tap gesture on
                                            // the link, and with it the rows opened only now and then on the owner's
                                            // iPhone however often he tapped (2026-11-04).
                                            .onAppear { Self.tourStep(for: entry.id).map(Tour.used) }
                                    } label: {
                                        settingsRow(entry)
                                            .tour(
                                                Self.tourStep(for: entry.id) ?? .howItWorks, in: Tour.settings,
                                                when: Self.tourStep(for: entry.id) != nil)
                                    }
                                }
                            }
                            .settingsIndexRowInsets()
                        }
                    } header: {
                        // A footnote-sized header (2026-11-15): the List's default header is near title size on
                        // iOS 27 and read louder than the rows under it.
                        Text(group.title)
                            .font(.footnote.weight(.medium))
                            .textCase(nil)
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
        #if os(iOS)
            // Groups closer together (2026-11-15), as in Settings.app; macOS has no section spacing to set.
            .listSectionSpacing(.compact)
        #endif
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
    func syncDetailRow(label: String, value: String) -> some View {
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
    func pccWindowRow(icon: String, label: String, value: String) -> some View {
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
    var pccWindowDescription: String {
        guard deviceCapabilities.supportsPrivateCloudCompute else {
            return "Unavailable"
        }
        if let size = pccCapability?.pccContextSize, size > 0 {
            return "\(size.formatted()) tokens"
        }
        return "\(FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false).formatted()) tokens"
    }

    /// Apple's name for the on-device model (iOS 27 `SystemLanguageModel.variant`: "AFM 3 Core" or "AFM 3 Core
    /// Advanced", Apple's documentation read 2026-11-13), or nil before iOS 27 or where the model isn't available.
    var onDeviceModelName: String? {
        #if canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                let model = SystemLanguageModel.default
                guard case .available = model.availability else { return nil }
                let name = model.variant.displayName.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        #endif
        return nil
    }

    /// Private Cloud Compute's window for the Intelligence Mode card, or nil where this build or device can't use it.
    var cloudWindowForModeCard: String? {
        guard DeviceCapabilities.pccRoutingCompiledIn, deviceCapabilities.supportsPrivateCloudCompute else {
            return nil
        }
        return pccWindowDescription
    }

    /// The on-device window, preferring the live capability snapshot over the budget
    /// helper's fallback for the same reason as `pccWindowDescription`.
    /// The languages Apple's on-device model reports on this device, by name in the person's language, or nil
    /// where Foundation Models isn't available.
    var modelLanguageNames: [String]? {
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

    var onDeviceWindowDescription: String {
        if let size = pccCapability?.onDeviceContextSize, size > 0 {
            return "\(size.formatted()) tokens"
        }
        // Both the snapshot and `SystemLanguageModel.default.contextSize` report 0 where
        // Foundation Models are unavailable, which is every simulator. Rendering that as
        // "0 tokens" reads as a broken device rather than an absent model.
        let budget = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        return budget > 0 ? "\(budget.formatted()) tokens" : "Unavailable"
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
    ///
    /// The pills became one quiet line of secondary text (2026-11-15, the owner asked for the page to look premium and
    /// without colour), so the row reads like the Apple Account row: icon, name, status.
    private var heroSummaryRow: some View {
        let rowLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(spacing: DSSpacing.md))
        return rowLayout {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                // Decorative and drawn in a 40-point circle, so it stops growing at the largest standard size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(DSColors.accent)
                .frame(width: 40, height: 40)
                .background(DSColors.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("OpenIntelligence")
                    .font(.headline)
                    .foregroundStyle(DSColors.primaryText)
                    // One word, so at the largest accessibility size it shrank to fit instead of hyphenating as
                    // "OpenIntelli-gence" (seen in the iOS 27 Simulator, 2026-11-15).
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(routeSummary)
                    .font(.footnote)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// What the two status pills said, as one line: "On-device first", and "PCC available" where it is.
    private var routeSummary: String {
        if deviceCapabilities.supportsPrivateCloudCompute, settings.applePCCConsent != .denied {
            return "On-device first · PCC available"
        }
        return "On-device first"
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

    // Rows sized like Settings.app's (2026-11-15, the owner: "clean it up, it doesnt need colorizing or anything but
    // it does need to look premium"). Every icon is the accent in one weight and one column width, where each entry
    // had its own tint, and the subtitle is a footnote held close under the title, so a row is about a system row's
    // height instead of a tall rounded card. The subtitle still wraps rather than truncating, at every text size.
    @ViewBuilder
    private func settingsRow(_ entry: SettingsEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(DSColors.primaryText)
                Text(entry.subtitle)
                    .font(.footnote)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: entry.icon)
                .font(.body)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(DSColors.accent)
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
            detailScroll {
                retrievalCard
                    #if DEBUG
                        .onAppear {
                            // The window the card was given to show (5.8 journal); the card moved here from Device &
                            // Performance with the context window.
                            VerificationJournal.record(
                                "settings.contextWindow",
                                ["tokens": "\(FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true))"])
                        }
                    #endif
            }
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
    /// The widest a Settings page's column gets, in points.
    static let detailColumnWidth: CGFloat = 620

    @ViewBuilder
    private func detailScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: DSSpacing.lg) {
                content()
            }
            .padding(DSSpacing.lg)
            // A column no wider than a large phone's page, centred (5.8). On a Mac or an iPad the cards stretched to
            // the window, which put a row's three chip dots a hand's width from the name they belong to; the
            // iPhone's layout read better because it is narrow (the owner, 2026-11-14).
            .frame(maxWidth: Self.detailColumnWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            DSColors.background
                .ignoresSafeArea()
        )
        #if os(macOS)
            // On a Mac a pushed page replaces the list, so the plans sheet attached to the list (`SettingsView.body`)
            // has nothing to present from: View Plans on Plan & Usage did nothing (seen on the owner's Mac,
            // 2026-11-14). The page presents it itself there. On iPhone and iPad the list stays under the page
            // and presents it, and a second presenter for the same flag would fight the first.
            .sheet(isPresented: $showPlanSheet) {
                PlanUpgradeSheet(entryPoint: planEntryPoint)
            }
        #endif
    }

}

extension View {
    /// Less padding above and below a Settings index row on iPhone and iPad (2026-11-15), so a row is close to a
    /// Settings.app row's height; the side insets stay the system's. A Mac list row is already that compact.
    @ViewBuilder
    fileprivate func settingsIndexRowInsets() -> some View {
        #if os(iOS)
            listRowInsets(.vertical, 7)
        #else
            self
        #endif
    }
}
