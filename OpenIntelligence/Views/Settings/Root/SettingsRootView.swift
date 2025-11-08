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
        case openAI = "OpenAI"
        case generation = "Generation"
        case retrieval = "Retrieval"
        case gallery = "Model Gallery"
        case providers = "Local Providers"
        case systemStatus = "System Status"
        case developer = "Developer & Diagnostics"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .executionPrivacy: return "lock.shield"
            case .modelSelection:   return "brain.head.profile"
            case .fallbacks:        return "arrow.triangle.2.circlepath"
            case .openAI:           return "key"
            case .generation:       return "slider.horizontal.3"
            case .retrieval:        return "magnifyingglass"
            case .gallery:          return "rectangle.stack"
            case .providers:        return "bolt.horizontal"
            case .systemStatus:     return "waveform.path.ecg"
            case .developer:        return "wrench.and.screwdriver"
            case .about:            return "info.circle"
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
                .gallery,
                .providers,
                .systemStatus,
                .developer,
                .about
            ]
        }
        #else
        static var allCases: [Category] {
            [
                .executionPrivacy,
                .modelSelection,
                .fallbacks,
                .openAI,
                .generation,
                .retrieval,
                .gallery,
                .providers,
                .systemStatus,
                .developer,
                .about
            ]
        }
        #endif
    }

    #if os(iOS)
    var body: some View {
        NavigationStack {
            List {
                ForEach(Category.allCases) { cat in
                    NavigationLink(value: cat) {
                        Label(cat.rawValue, systemImage: cat.icon)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Category.self) { cat in
                destination(for: cat)
            }
        }
    }
    #elseif os(macOS)
    @State private var selection: Category? = .executionPrivacy
    var body: some View {
        NavigationSplitView {
            List(Category.allCases, selection: $selection) { cat in
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

    @ViewBuilder
    private func destination(for cat: Category) -> some View {
        switch cat {
        case .executionPrivacy: ExecutionPrivacyView()
        case .modelSelection:   ModelSelectionView()
        case .fallbacks:        FallbacksView()
        case .openAI:           OpenAISettingsView()
        case .generation:       GenerationParametersView()
        case .retrieval:        RetrievalSettingsView()
        case .gallery:          ModelGalleryView()
        case .providers:        LocalProvidersView()
        case .systemStatus:     SystemStatusView()
        case .developer:        DeveloperDiagnosticsView()
        case .about:            AboutSettingsView()
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
                    Text("Automatic").tag(ExecutionContext.automatic)
                    Text("On-Device Only").tag(ExecutionContext.onDeviceOnly)
                    Text("Prefer Cloud").tag(ExecutionContext.preferCloud)
                    Text("Cloud Only").tag(ExecutionContext.cloudOnly)
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
                Text("Choose where to run models. Private Cloud Compute may be used based on your selection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy Controls") {
                Toggle("Allow Private Cloud Compute", isOn: $settings.allowPrivateCloudCompute)
                Toggle("Prefer Private Cloud", isOn: $settings.preferPrivateCloudCompute)
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

struct OpenAISettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showInfo = false
    var body: some View {
        Form {
            Section("API") {
                SecureField("API Key (sk-...)", text: $settings.openaiAPIKey)
                    .textContentType(.password)
                Picker("Model", selection: $settings.openaiModel) {
                    Text("GPT-5 (Latest)").tag("gpt-5")
                    Text("o1 (Reasoning)").tag("o1")
                    Text("o1-mini (Fast Reasoning)").tag("o1-mini")
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("GPT-4 Turbo").tag("gpt-4-turbo-preview")
                }
            }
            Section {
                Button {
                    showInfo = true
                } label: {
                    Label("Privacy Notice", systemImage: "exclamationmark.shield.fill")
                }
                .tint(.orange)
                .alert("OpenAI Direct", isPresented: $showInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Direct OpenAI API bypasses Apple's privacy protections. Use only if you accept OpenAI's policies.")
                }
            }
        }
        .navigationTitle("OpenAI")
    }
}

struct GenerationParametersView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        List {
            Section("Temperature") {
                HStack {
                    Slider(value: $settings.temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
                Text("Controls creativity vs. determinism.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Max Tokens") {
                HStack {
                    Slider(value: Binding(get: { Double(settings.maxTokens) }, set: { settings.maxTokens = Int($0) }), in: 100...16000, step: 100)
                    Text("\(settings.maxTokens)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
                Text("Upper bound on response length.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Generation")
    }
}

struct RetrievalSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        List {
            Section("Retrieved Chunks") {
                HStack {
                    Slider(value: Binding(get: { Double(settings.topK) }, set: { settings.topK = Int($0) }), in: 1...50, step: 1)
                    Text("\(settings.topK)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Section {
                Toggle("Lenient Retrieval Mode", isOn: $settings.lenientRetrievalMode)
            }
        }
        .navigationTitle("Retrieval")
    }
}

struct ModelGalleryView: View {
    var body: some View {
        List {
            Section("Downloads") {
                Text("Model Gallery will be moved here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Model Gallery")
    }
}

struct LocalProvidersView: View {
    var body: some View {
        List {
            Section("Local Providers") {
                #if os(macOS)
                Text("Configure MLX, llama.cpp, and Ollama (macOS).")
                #else
                Text("Local providers available on macOS.")
                #endif
            }
        }
        .navigationTitle("Local Providers")
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
    var body: some View {
        List {
            Section("About") {
                Text("About and app information.")
                    .foregroundStyle(.secondary)
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
