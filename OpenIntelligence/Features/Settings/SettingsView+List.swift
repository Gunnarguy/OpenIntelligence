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
        case .modelPrivacy: .privateCloud
        case .siriShortcuts: .siri
        default: nil
        }
    }

    private enum SettingsEntryID: String {
        case howItWorks, glossary
        case intelligenceMode, modelPrivacy
        case librariesSync
        case devicePerformance, general
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

        /// Every entry a customer sees. Developer & Diagnostics is in Debug builds only (5.8): it showed every
        /// customer lines such as "PCC Entitlement Missing" from the release build's diagnostics hub.
        static let all: [SettingsEntry] = everyEntry.filter { entry in
            #if DEBUG
                return true
            #else
                return entry.id != .developer
            #endif
        }

        private static let everyEntry: [SettingsEntry] = [
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
            // Apple Intelligence and Private Cloud Compute, one page since 2026-11-16, with the answer route that was
            // only in the chat's model pill. The keywords are both pages' plus the route's names.
            .init(
                id: .modelPrivacy, group: .intelligence,
                title: "Model & Privacy",
                subtitle: "Apple's model, where answers are written, and Private Cloud Compute",
                icon: "apple.intelligence",
                keywords: [
                    "apple intelligence", "smart replies", "content tagging", "spotlight", "writing tools", "speech",
                    "translation", "model", "foundation models", "languages", "language", "pcc", "private cloud compute",
                    "cloud", "privacy", "consent", "permission", "routing", "route", "on-device", "on device", "hybrid",
                    "context window", "quota", "background maintenance",
                ]
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
                    "chip", "neural engine", "tops", "gpu", "metal", "memory", "ram", "thermal", "compute profile",
                    "batch",
                ]
            ),
            // Appearance and Notifications, one page since 2026-11-16 (three rows and one row before).
            .init(
                id: .general, group: .device,
                title: "General",
                subtitle: "Accent colour, Technical Details, the hardware HUD and notifications",
                icon: "gearshape",
                keywords: [
                    "appearance", "accent", "colour", "color", "theme", "hud", "silicon", "telemetry", "telemetry hud",
                    "x-ray", "xray", "glow", "haptics", "technical", "technical details", "technical version",
                    "console", "stats", "simple", "menu bar", "notifications", "notify", "alert", "banner", "finished",
                    "import", "background",
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
                subtitle: "Version, privacy policy and links",
                icon: "info.circle",
                keywords: [
                    "about", "version", "privacy policy", "terms", "crash", "crash report", "github", "source",
                    "roadmap", "app store",
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
            if trimmedSearch.isEmpty {
                Section {
                    statusPanelRow
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
                            Group {
                                if let opensSheet = sheetAction(for: entry.id) {
                                    // Advanced opens the parameters directly. Pushing a screen
                                    // whose only content was a button that opened this sheet
                                    // made it two taps to reach the one thing behind the row.
                                    // Plan & Usage opens the plans the same way (2026-11-15): its page
                                    // held the usage panel and a View Plans button, three taps to a plan.
                                    Button {
                                        DSHaptics.selection()
                                        opensSheet()
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
                        // Set like a card's `SectionHeader` (2026-11-15): small, uppercase and tracked, so the list's
                        // groups read the way the Settings pages' cards do. The List's own header is near title size on
                        // iOS 27 and read louder than the rows under it.
                        Text(group.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .textCase(nil)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Also shown for a search that names it (2026-11-16): feedback, the review and sharing are only here
            // now, About having dropped its copies, and the card is not an entry the search can find.
            if trimmedSearch.isEmpty || supportCardMatchesSearch {
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
            if !trimmedSearch.isEmpty, !supportCardMatchesSearch,
                SettingsGroup.allCases.allSatisfy({ visibleEntries(in: $0).isEmpty })
            {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
    }

    /// What a row that opens a sheet instead of pushing a page does when tapped, or nil for a row that pushes.
    private func sheetAction(for id: SettingsEntryID) -> (() -> Void)? {
        switch id {
        case .advanced:
            return { showModelConfiguration = true }
        case .plan:
            return {
                planEntryPoint = .settings
                showPlanSheet = true
            }
        default:
            return nil
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

    /// The top of the index: the dark lit panel the Settings pages open with (2026-11-15), stating the live state in four
    /// blocks. It replaced an icon, a name and two grey lines; the owner asked for the list to look premium and to
    /// belong with the pages he approved ("those look phenomenal"). Every figure is one this view already reads: the
    /// model's name from `onDeviceModelName`, the answer mode from `settings`, the plan from `entitlementStore` and the
    /// libraries from `containerService`. Hidden while searching, so results start at the top.
    private var statusPanelRow: some View {
        let modelName = onDeviceModelName
        let modelReady = deviceCapabilities.supportsFoundationModels
        // "AFM 3 Core Advanced" doesn't fit a quarter of a phone's width at 12 points: the family ("AFM 3") goes in
        // the caption and the rest is the figure. A name of another shape is shown whole. Where the model isn't
        // available the block says Unavailable and the reason is the line under the panel, the same words
        // (`statusText`) the row showed before, so the panel never states a reason it doesn't know.
        let modelWords = modelName?.split(separator: " ").map(String.init) ?? []
        let splitsFamily = modelWords.count > 2 && modelWords[0] == "AFM"
        let modelFigure =
            splitsFamily ? modelWords.dropFirst(2).joined(separator: " ") : (modelName ?? (modelReady ? "Ready" : "Unavailable"))
        let modelCaption = splitsFamily ? modelWords.prefix(2).joined(separator: " ") + ", on device" : "on device"
        let libraries = SettingsStatusPanel.used(containerService.countedLibraryCount, of: entitlementStore.libraryLimit)
        let mode = settings.ragQualityMode.canonical
        // "Ready" only once the person has allowed it; available but not yet allowed reads "available", as the pill did.
        // The same live source the Private Cloud Compute page reads (5.8): the panel said "PCC available" above a page
        // saying Unavailable, because `supportsPrivateCloudCompute` is only "compiled in and iOS or macOS 27".
        let pccLive = pccCapability?.pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute
        let pccAvailable = pccLive && settings.applePCCConsent != .denied
        let pccAllowed = pccAvailable && settings.applePCCConsent == .allowed
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SettingsStatusPanel(
                symbol: "brain.head.profile",
                title: "OpenIntelligence",
                badge: pccAllowed ? "PCC ready" : (pccAvailable ? "PCC available" : "On device"),
                badgeColor: pccAvailable ? .cyan : Color.secondary,
                blocks: [
                    .init(
                        symbol: "apple.intelligence", name: "Model", color: .blue, figure: modelFigure,
                        share: modelReady ? nil : 0, caption: modelReady ? modelCaption : "see below"),
                    .init(
                        symbol: "sparkles", name: "Mode", color: .purple, figure: mode.displayName,
                        share: mode == .standard ? 1.0 / 3 : (mode == .deepThink ? 2.0 / 3 : 1), caption: "answers"),
                    .init(
                        symbol: "creditcard", name: "Plan", color: .orange,
                        figure: entitlementStore.effectiveTier.displayName, share: nil,
                        caption: entitlementStore.effectiveTier == .free ? "tap to upgrade" : "tap for plans"),
                    .init(
                        symbol: "books.vertical", name: "Libraries", color: .green, figure: libraries.figure,
                        share: libraries.share, caption: libraries.caption),
                ]
            )
            // The Plan block, the third of four equal blocks, opens the plans screen (2026-11-15), as the Plan & Usage
            // row does. The other three take no tap, so the row stays inert around it; VoiceOver reads the panel as
            // one element, so there it is a named action.
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                    Color.clear
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { sheetAction(for: .plan)?() }
                    Color.clear
                }
            }
            .accessibilityAction(named: "Open Plans") { sheetAction(for: .plan)?() }
            if !modelReady {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSSpacing.xs)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    /// Whether the search names something on the Support & Feedback card.
    private var supportCardMatchesSearch: Bool {
        let query = trimmedSearch.lowercased()
        guard !query.isEmpty else { return false }
        return ["support", "feedback", "email", "contact", "rate", "rating", "review", "share", "recommend"]
            .contains { $0.contains(query) }
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
    // it does need to look premium and not have such large pill like page taps"). Each icon sits in a small rounded
    // graphite tile with a white glyph, the dark of the status panel above, where Settings.app gives each tile its own
    // colour. Title in the body size of the Settings pages (`.subheadline`, medium), subtitle a caption close under it,
    // so a row is about a system row's height. The subtitle still wraps rather than truncating, at every text size.
    @ViewBuilder
    private func settingsRow(_ entry: SettingsEntry) -> some View {
        HStack(spacing: DSSpacing.md) {
            SettingsIconTile(symbol: entry.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DSColors.primaryText)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
        case .modelPrivacy:
            detailScroll { modelAndPrivacyPage }
        case .librariesSync:
            detailScroll { sharedWorkspaceCard }
        case .devicePerformance:
            detailScroll { contextWindowCard }
        case .general:
            detailScroll { generalPage }
        case .plan:
            // Unreachable, like `.advanced` below: the Plan & Usage row presents the plans screen directly
            // (2026-11-15), and the screen opens with the usage panel this page showed.
            EmptyView()
        case .siriShortcuts:
            detailScroll { siriIntegrationCard }
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

    /// Every pushed page is drawn inside `SettingsLivePage`, so it redraws when a setting changes (2026-11-17). A page
    /// pushed by a `NavigationLink` is built once from the list's body, which observes `SettingsStore`, and was not
    /// drawn again when a setting changed: on the Mac, tapping a route or permission on Model & Privacy stored the new
    /// value while the page went on showing the old one, so a second tap on the old choice did nothing.
    @ViewBuilder
    private func detailScroll<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: DSSpacing.lg) {
                SettingsLivePage(content: content)
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
            // 2026-11-14). The page presents it itself there; since 2026-11-15 that is the upgrade buttons on
            // Intelligence Mode and Libraries & iCloud, the Plan & Usage row being on the list. On iPhone and iPad
            // the list stays under the page and presents it, and a second presenter for the same flag would fight
            // the first.
            .sheet(isPresented: $showPlanSheet) {
                PlanUpgradeSheet(entryPoint: planEntryPoint, usage: planUsage)
            }
        #endif
    }

}

/// A Settings row's icon: a white glyph in a small graphite tile with a faint lit edge, drawn like the status panel's
/// background (2026-11-15). The tile grows with the text size up to the largest standard size and stops there.
private struct SettingsIconTile: View {
    let symbol: String
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSCorners.control - 3, style: .continuous)
        Image(systemName: symbol)
            .scaledFont(size: 14, weight: .semibold, relativeTo: .subheadline)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: min(side, 40), height: min(side, 40))
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.26), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Less padding above and below a Settings index row on iPhone and iPad (2026-11-15), so a row is close to a
    /// Settings.app row's height; the side insets stay the system's. A Mac list row is already that compact.
    @ViewBuilder
    fileprivate func settingsIndexRowInsets() -> some View {
        #if os(iOS)
            listRowInsets(.vertical, 6)
        #else
            self
        #endif
    }
}
