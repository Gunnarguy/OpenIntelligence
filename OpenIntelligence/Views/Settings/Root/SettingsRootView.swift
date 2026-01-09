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
            Section("Execution Context") {
                Picker("Run on", selection: Binding(
                    get: { settings.executionContext },
                    set: { settings.executionContext = $0 }
                )) {
                    Text("Automatic (Reliability-first)").tag(ExecutionContext.automatic)
                    Text("On-Device Only").tag(ExecutionContext.onDeviceOnly)
                    Text("Prefer Cloud").tag(ExecutionContext.preferCloud)
                    Text("Cloud Only").tag(ExecutionContext.cloudOnly)
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
                Text("Choose where to run models. Automatic prefers PCC for library queries when allowed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy Controls") {
                // Execution Context is now the single source of truth for PCC preferences
                if settings.executionContext == .automatic || settings.executionContext == .preferCloud {
                    Label("Private Cloud Compute preferred when available", systemImage: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settings.executionContext == .cloudOnly {
                    Label("Forced Cloud Execution", systemImage: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Strictly On-Device", systemImage: "iphone.gen3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Text("Target context budget (input + output). Apple FM caps on-device at 4,096 tokens; PCC expands to long context when allowed.").font(.footnote).foregroundStyle(.secondary)
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
    var body: some View {
        List {
            Section("Retrieval Strategy") {
                Text("Retrieval runs in balanced mode for coverage and reliability without blocking answers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.useHighAccuracyEmbeddings) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High-Accuracy Embeddings")
                        Text("Uses NLContextualEmbedding for 15-25% better semantic search. New libraries will use contextual embeddings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Embedding Quality")
            } footer: {
                if settings.useHighAccuracyEmbeddings {
                    Label("Active provider: nl_contextual_embedding", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Active provider: nl_embedding (standard)")
                        .font(.caption)
                }
            }

        }
        .navigationTitle("Retrieval")
    }
}

// ModelGalleryView and LocalProvidersView removed - local downloadable models no longer supported

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
        }
        .navigationTitle("About")
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
