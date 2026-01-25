//
//  SettingsRootView.swift
//  OpenIntelligence
//
//  Initial scaffold for the new Settings navigation shell.
//  Uses SettingsStore as a single source of truth for bindings.
//  Category views are stubbed for now and will be extracted incrementally.
//

import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: SettingsStore

    enum Category: String, CaseIterable, Identifiable {
        case executionPrivacy = "Execution & Privacy"
        case modelSelection = "Model Selection"
        case fallbacks = "Fallbacks"
        case generation = "Generation"
        case retrieval = "Retrieval"
        case systemStatus = "System Status"
        case developer = "Developer & Diagnostics"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .executionPrivacy: return "lock.shield"
            case .modelSelection: return "brain.head.profile"
            case .fallbacks: return "arrow.triangle.2.circlepath"
            case .generation: return "slider.horizontal.3"
            case .retrieval: return "magnifyingglass"
            case .systemStatus: return "waveform.path.ecg"
            case .developer: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }

        #if os(iOS)
            static var allCases: [Category] {
                [
                    .executionPrivacy,
                    .modelSelection,
                    .fallbacks,
                    .generation,
.retrieval,
                    .systemStatus,
                    .developer,
                    .about,
                ]
            }
        #else
            static var allCases: [Category] {
                [
                    .executionPrivacy,
                    .modelSelection,
.fallbacks,
                    .generation,
.retrieval,
                    .systemStatus,
                    .developer,
                    .about,
                ]
            }
        #endif
    }

    #if os(iOS)
        @State private var path = NavigationPath()
        var body: some View {
            NavigationStack(path: $path) {
                List {
                    ForEach(availableCategories) { cat in
                        NavigationLink(value: cat) {
                            Label(cat.rawValue, systemImage: cat.icon)
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationDestination(for: Category.self) { cat in
                    destination(for: cat)
                }
                .onChange(of: settings.reviewerModeEnabled) { _, enabled in
                    if !enabled {
                        path = NavigationPath()
                    }
                }
            }
        }

    #elseif os(macOS)
        @State private var selection: Category? = .executionPrivacy
        var body: some View {
            NavigationSplitView {
                List(availableCategories, selection: $selection) { cat in
                    Label(cat.rawValue, systemImage: cat.icon)
                }
                .navigationTitle("Settings")
            } detail: {
                if let sel = selection {
                    destination(for: sel)
                } else {
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                }
            }
        }
    #endif

    private var availableCategories: [Category] {
        #if os(iOS)
            var categories: [Category] = [
                .executionPrivacy,
                .modelSelection,
                .fallbacks,
                .generation,
.retrieval,
                .systemStatus,
                .developer,
                .about,
            ]
        #else
            var categories: [Category] = [
                .executionPrivacy,
                .modelSelection,
.fallbacks,
                .generation,
.retrieval,
                .systemStatus,
                .developer,
                .about,
            ]
        #endif

        return categories
    }

    @ViewBuilder
    private func destination(for cat: Category) -> some View {
        switch cat {
        case .executionPrivacy: ExecutionPrivacyView()
        case .modelSelection: ModelSelectionView()
        case .fallbacks: FallbacksView()
        case .generation: GenerationParametersView()
        case .retrieval: RetrievalSettingsView()
        case .systemStatus: SystemStatusView()
        case .developer: DeveloperDiagnosticsView()
        case .about: AboutSettingsView()
        }
    }
}

// MARK: - Stub Category Views (to be replaced with real implementations)

struct ExecutionPrivacyView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        List {
            Section("Automatic Routing") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Smart Execution", systemImage: "gearshape.2.fill")
                        .font(.headline)
                    Text("OpenIntelligence automatically uses on-device processing when possible, and seamlessly escalates to Private Cloud Compute for complex queries or large documents.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Private Cloud Compute") {
                Label("End-to-end encrypted", systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Label("No data retention by Apple", systemImage: "eye.slash.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Label("Cryptographically verifiable", systemImage: "doc.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Label("Handles complex reasoning tasks", systemImage: "brain")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            Section {
                Label("On-Device: 4K tokens", systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("PCC: Complex queries", systemImage: "cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Context Windows")
            } footer: {
                Text("Private Cloud Compute handles queries that benefit from server-side processing.")
                    .font(.caption)
            }
        }
        .navigationTitle("Execution & Privacy")
    }
}

struct ModelSelectionView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        List {
            Section("Primary Model") {
                let options = primaryPickerOptions

                if options.isEmpty {
                    Text("No Apple-native models available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "AI Model",
                        selection: Binding(
                            get: { selectedModelForPicker },
                            set: { settings.selectedModel = $0 }
                        )
                    ) {
                        ForEach(options, id: \.self) { t in
                            Label(t.displayName, systemImage: t.iconName).tag(t)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif
                }
                Text("Choose the primary inference pathway. Fallbacks are configured separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Model Selection")
    }
}

private extension ModelSelectionView {
    /// Ensures the Picker sees a stable option set that always contains the active selection.
    var primaryPickerOptions: [LLMModelType] {
        var options = settings.primaryModelOptions
        if !options.contains(settings.selectedModel) {
            options.append(settings.selectedModel)
        }
        var deduped: [LLMModelType] = []
        deduped.reserveCapacity(options.count)
        var seen = Set<LLMModelType>()
        for option in options {
            if seen.insert(option).inserted {
                deduped.append(option)
            }
        }
        return deduped
    }

    /// Provides a fallback selection should the underlying options lag behind state changes briefly.
    var selectedModelForPicker: LLMModelType {
        guard let first = primaryPickerOptions.first else { return settings.selectedModel }
        return primaryPickerOptions.contains(settings.selectedModel) ? settings.selectedModel : first
    }
}

struct FallbacksView: View {
    @EnvironmentObject private var settings: SettingsStore
    private var firstOptions: [LLMModelType] {
        settings.fallbackOptions(excluding: Set([settings.selectedModel]))
    }

    private var secondOptions: [LLMModelType] {
        settings.fallbackOptions(excluding: Set([settings.selectedModel, settings.firstFallback]))
    }

    var body: some View {
        List {
            Section("First Fallback") {
                Toggle("Enable First Fallback", isOn: $settings.enableFirstFallback)
                if settings.enableFirstFallback {
                    Picker("Model", selection: $settings.firstFallback) {
                        ForEach(firstOptions, id: \.self) { m in
                            Label(m.displayName, systemImage: m.iconName).tag(m)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif
                }
            }
            Section("Second Fallback") {
                Toggle("Enable Second Fallback", isOn: $settings.enableSecondFallback)
                if settings.enableSecondFallback {
                    Picker("Model", selection: $settings.secondFallback) {
                        ForEach(secondOptions, id: \.self) { m in
                            Label(m.displayName, systemImage: m.iconName).tag(m)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #endif
                }
            }
        }
        .navigationTitle("Fallbacks")
    }
}

struct GenerationParametersView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        List {
            Section("System Prompt") {
                TextEditor(text: $settings.systemPrompt)
                    .frame(height: 100)
                Text("Instructions prepended to every conversation.").font(.footnote).foregroundStyle(.secondary)
            }

            Section("Context & Length") {
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(settings.maxTokens)")
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: Binding(get: { Double(settings.maxTokens) }, set: { settings.maxTokens = Int($0) }), in: 100 ... 4096, step: 100)
                Text("Maximum number of tokens to generate.").font(.footnote).foregroundStyle(.secondary)

                HStack {
                    Text("Context Window")
                    Spacer()
                    Text("\(settings.contextLength)")
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: Binding(get: { Double(settings.contextLength) }, set: { settings.contextLength = Int($0) }), in: 512 ... 32768, step: 512)
                Text("Target context budget (input + output). Apple Foundation Models use a 4,096 token context window.").font(.footnote).foregroundStyle(.secondary)
            }

            Section("Sampling") {
                HStack {
                    Text("Creativity")
                    Spacer()
                    Text("\(Int(settings.temperature * 100))%")
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $settings.temperature, in: 0 ... 1.0, step: 0.05)
                Text("Controls randomness (0% = deterministic, 100% = creative).").font(.footnote).foregroundStyle(.secondary)

                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", settings.topP))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $settings.topP, in: 0 ... 1.0, step: 0.05)
                Text("Nucleus sampling probability.").font(.footnote).foregroundStyle(.secondary)
            }

            Section("Penalties") {
                HStack {
                    Text("Frequency Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.frequencyPenalty))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $settings.frequencyPenalty, in: 0 ... 2.0, step: 0.1)

                HStack {
                    Text("Presence Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.presencePenalty))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $settings.presencePenalty, in: 0 ... 2.0, step: 0.1)

                HStack {
                    Text("Repetition Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.repetitionPenalty))
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $settings.repetitionPenalty, in: 1.0 ... 2.0, step: 0.05)
            }
        }
        .navigationTitle("Generation")
    }
}

struct RetrievalSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("docCacheAutoEnabled") private var docCacheAutoEnabled: Bool = true
    @AppStorage("docCacheExpirationDays") private var docCacheExpirationDays: Int = 30

    var body: some View {
        List {
            Section("Retrieval Strategy") {
                Text("Full hybrid retrieval pipeline with vector search, keyword matching, and neural reranking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Neural Engine Embeddings")
                            .font(.body)
                        Text("384-dimensional sentence embeddings optimized for Apple Silicon. Hardware accelerated for fast, accurate semantic search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Embedding Model")
            } footer: {
                Label("Active: coreml_sentence_embedding", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Section("Ingestion Features") {
                featureItem(icon: "doc.badge.gearshape", title: "Contextual Embeddings", detail: "Document title + section context baked into vectors")
                featureItem(icon: "tablecells", title: "Smart Table Extraction", detail: "iOS 26 Vision API preserves tables with captions")
                featureItem(icon: "link", title: "Entity Index", detail: "Cross-document linking via global entity correlation")
                featureItem(icon: "tree", title: "RAPTOR-lite Summaries", detail: "~150-word document summaries for overview queries")
            }

            Section("Search Features") {
                featureItem(icon: "arrow.triangle.merge", title: "Hybrid Search + RRF", detail: "Vector + BM25 keyword search with Reciprocal Rank Fusion")
                featureItem(icon: "arrow.up.arrow.down", title: "Cross-Encoder Reranking", detail: "TinyBERT neural reranker for precision")
                featureItem(icon: "shuffle", title: "MMR Diversification", detail: "Maximal Marginal Relevance for result diversity")
                featureItem(icon: "doc.on.doc", title: "Parent Document Retrieval", detail: "±5 chunk window expansion for full context")
                featureItem(icon: "arrow.left.arrow.right", title: "Lost-in-Middle Mitigation", detail: "Best evidence at start AND end of context")
            }

            Section("Advanced (Deep Think / Maximum)") {
                featureItem(icon: "signpost.right.and.left", title: "Intent Routing", detail: "lookup/procedure/compare/summarize classification")
                featureItem(icon: "point.3.connected.trianglepath.dotted", title: "2-Hop Graph Expansion", detail: "Entity-based traversal across chunks")
                featureItem(icon: "checkmark.seal.fill", title: "Verification Gates A-D", detail: "4-stage anti-hallucination checks")
                featureItem(icon: "function", title: "Confidence Calibration", detail: "Platt-scaled scores for reliable uncertainty")
            }

            Section {
                Toggle(isOn: $docCacheAutoEnabled) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Cache Web Docs")
                                .font(.subheadline.weight(.medium))
                            Text("Automatically cache referenced documentation pages for offline access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache Expiration")
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: $docCacheExpirationDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("60 days").tag(60)
                            Text("90 days").tag(90)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            } header: {
                Text("Documentation Cache")
            } footer: {
                Text("Cached documents can be ingested into any library for offline RAG queries.")
                    .font(.caption)
            }
        }
        .navigationTitle("Retrieval")
    }

    @ViewBuilder
    private func featureItem(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SystemStatusView: View {
    var body: some View {
        List {
            Section("Status") {
                Text("System status overview will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("System Status")
    }
}

struct DeveloperDiagnosticsView: View {
    var body: some View {
        List {
            Section("Diagnostics") {
                Text("Developer tools and diagnostics live here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer & Diagnostics")
    }
}

struct AboutSettingsView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @State private var showResetConfirmation = false
    @State private var resetComplete = false

    private struct PricingPlan: Identifiable {
        let id = UUID()
        let name: String
        let price: String
        let allowances: String
        let highlights: [String]
    }

    private var pricingPlans: [PricingPlan] {
        [
            .init(
                name: "Free",
                price: "$0",
                allowances: "5 documents · 1 library",
                highlights: [
                    "Hybrid retrieval with on-device + PCC models",
                    "Full privacy dashboard",
                ]
            ),
            .init(
                name: "Pro",
                price: "$5.99/mo or $49.99/yr",
                allowances: "Unlimited docs · 5 libraries",
                highlights: [
                    "Full hybrid retrieval with MMR tuning",
                    "Priority ingestion",
                    "Advanced retrieval controls",
                ]
            ),
            .init(
                name: "Lifetime",
                price: "$59.99 one-time",
                allowances: "Unlimited docs · 10 libraries",
                highlights: [
                    "All Pro features forever",
                    "No recurring charges",
                ]
            ),
        ]
    }

    private var supportURL: URL? {
        URL(string: "https://openintelligence.app/support")
    }

    private var marketingURL: URL? {
        URL(string: "https://openintelligence.app")
    }

    private var privacyURL: URL? {
        URL(string: "https://openintelligence.app/privacy")
    }

    var body: some View {
        List {
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenIntelligence is a privacy-first RAG assistant. All inference stays on-device or within Apple's Private Cloud Compute unless you explicitly connect a reviewer-only provider.")
                    Text("Version 1.0.0 · Build target iOS 26+")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Plans & Pricing") {
                ForEach(pricingPlans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(plan.name)
                                .font(.headline)
                            Spacer()
                            Text(plan.price)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(plan.allowances)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(plan.highlights, id: \.self) { highlight in
                                Label(highlight, systemImage: "checkmark.seal.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Text("Pricing aligns with current App Store tiers and mirrors the submission collateral in Docs/reference/PRICING_STRATEGY.md. Actual availability may vary by region and promotion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Helpful Links") {
                if let supportURL {
                    Link(destination: supportURL) {
                        Label("Support", systemImage: "lifepreserver")
                    }
                }
                if let marketingURL {
                    Link(destination: marketingURL) {
                        Label("Marketing Site", systemImage: "globe")
                    }
                }
                if let privacyURL {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset App Data", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Clears onboarding state, theme preferences, and all cached settings. Documents and embeddings are preserved.")
            }
        }
        .navigationTitle("About")
        .alert("Reset App Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                performReset()
            }
        } message: {
            Text("This will reset onboarding, theme, and all preferences. Your documents will not be deleted.")
        }
        .alert("Reset Complete", isPresented: $resetComplete) {
            Button("OK") { }
        } message: {
            Text("Please restart the app for changes to take effect.")
        }
    }

    private func performReset() {
        // Reset onboarding
        onboardingStore.resetAllOnboarding()

        // Reset common AppStorage keys
        let defaults = UserDefaults.standard
        let keysToRemove = [
            "selectedColorScheme",
            "app_theme",
            "accentColor",
            "embedding3d_hasSeenOnboarding",
            "hasLaunchedBefore",
            "lastSelectedContainer",
        ]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        resetComplete = true
    }
}

#Preview {
    // Preview with a temporary store
    let containerSvc = ContainerService()
    let ragSvc = RAGService(containerService: containerSvc)
    let store = SettingsStore(ragService: ragSvc)
    return SettingsRootView()
        .environmentObject(store)
}
