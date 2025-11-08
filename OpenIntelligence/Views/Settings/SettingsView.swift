import SwiftUI

struct SettingsView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var downloadService = ModelDownloadService.shared
    @StateObject private var modelRegistry = ModelRegistry.shared

    @State private var deviceCapabilities = DeviceCapabilities()
    @State private var pipelineStages: [ModelPipelineStage] = []
    @State private var apiKeyStatus: APIKeyValidationStatus = .unknown
    @State private var isValidatingAPIKey = false
    @State private var isApplyingModel = false
    @State private var showAPIKey = false
    @State private var showModelManager = false
    @State private var showModelSelector = false
    @State private var showWhyUnavailable = false
    @State private var applyTask: Task<Void, Never>? = nil
    @FocusState private var apiKeyFieldFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                heroCard
                executionCard
                modelSelectionCard
                fallbackCard
                pipelineCard
                #if os(macOS)
                    openAICard
                #endif
                generationCard
                retrievalCard
                downloadsCard
                developerCard
                aboutCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.4),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await bootstrap() }
        .onDisappear { applyTask?.cancel() }
        .onChange(of: settings.selectedModel) {
            normalizeFallbacks()
            applyNow()
        }
        .onChange(of: settings.firstFallback, initial: false) {
            normalizeFallbacks()
            if settings.enableFirstFallback {
                applyNow()
            }
        }
        .onChange(of: settings.secondFallback, initial: false) {
            normalizeFallbacks()
            if settings.enableSecondFallback {
                applyNow()
            }
        }
        .onChange(of: settings.enableFirstFallback, initial: false) {
            refreshPipeline()
            applyNow()
        }
        .onChange(of: settings.enableSecondFallback, initial: false) {
            refreshPipeline()
            applyNow()
        }
        .onChange(of: settings.allowPrivateCloudCompute, initial: false) { refreshPipeline() }
        .onChange(of: settings.localComputePreference, initial: false) { applyNow() }
        #if os(macOS)
            .onChange(of: settings.openaiAPIKey, initial: false) {
                apiKeyStatus = .unknown
                refreshPipeline()
            }
        #endif
        .sheet(isPresented: $showModelManager) {
            ModelManagerSheet(ragService: ragService)
        }
        .sheet(isPresented: $showModelSelector) {
            ModelSelectorSheet(ragService: ragService)
        }
        .sheet(isPresented: $showWhyUnavailable) {
            NavigationStack {
                ScrollView {
                    Text(gatingHelpText(for: settings.selectedModel, status: selectedModelStatus))
                        .font(.callout)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("Why Unavailable?")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showWhyUnavailable = false }
                    }
                }
            }
            #if os(iOS)
                .presentationDetents([.medium, .large])
            #endif
        }
    }
}

extension SettingsView {
    @ViewBuilder
    fileprivate var heroCard: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.9),
                    Color.accentColor.opacity(0.6),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Intelligence Pipeline")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(settings.selectedModel.displayName)
                    .font(.title.bold())
                    .foregroundColor(.white)

                if !pipelineStages.isEmpty {
                    Text(pipelineHeadline())
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                HStack(spacing: 16) {
                    HeroStat(value: "\(ragService.documents.count)", label: "Documents")
                    HeroStat(value: "\(ragService.totalChunksStored)", label: "Chunks")
                    HeroStat(value: settings.executionContext.description, label: "Execution")
                }

                Button {
                    applyNow()
                } label: {
                    HStack(spacing: 8) {
                        if isApplyingModel {
                            ProgressView()
                                .scaleEffect(0.85)
                            Text("Applying...")
                        } else {
                            Label("Apply Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .disabled(isApplyingModel)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    fileprivate var executionCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "cloud.fill", title: "Execution & Privacy",
                caption: "Control where inference runs")
            Toggle("Allow Private Cloud Compute", isOn: $settings.allowPrivateCloudCompute)
            Toggle("Prefer Private Cloud", isOn: $settings.preferPrivateCloudCompute)
                .disabled(!settings.allowPrivateCloudCompute)
            Picker("Execution Strategy", selection: $settings.executionContext) {
                ForEach(executionOptions, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            SectionFooter(executionSummaryText)
        }
    }

    @ViewBuilder
    fileprivate var modelSelectionCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "brain.head.profile", title: "Model Selection",
                caption: "Primary intelligence pathway")

            // Current model display - tappable card
            Button {
                showModelSelector = true
            } label: {
                HStack(spacing: 14) {
                    // Model icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: settings.selectedModel.iconName)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }

                    // Model info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.selectedModel.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Tap to change model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(DSColors.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if let primaryStage = pipelineStages.first {
                PipelineStageRow(stage: primaryStage)
            }
            SectionFooter(modelSummary(for: settings.selectedModel))

            if shouldShowWhyUnavailable {
                Button {
                    showWhyUnavailable = true
                } label: {
                    Label("Why Unavailable?", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            localModelInlineManager
        }
    }

    @ViewBuilder
    fileprivate var localModelInlineManager: some View {
        Divider()
            .padding(.vertical, 6)

        VStack(alignment: .leading, spacing: 12) {
            localModelsHeader
            localModelsList
            localModelActionButtons
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var localModelsHeader: some View {
        HStack {
            Label("Local Models", systemImage: "externaldrive")
                .font(.subheadline.weight(.semibold))
            Spacer()
            computePreferenceMenu
        }
        HStack(spacing: 8) {
            if downloadService.isLoadingCatalog {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Text(localModelsSummaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(computePreferenceSummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Text(localModelStatusText)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var localModelsList: some View {
        if installedLocalModels.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No local models yet")
                    .font(.caption.weight(.medium))
                Text("Browse the gallery or import your own pack to enable fully offline chat.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(installedLocalModels) { model in
                    Button {
                        activateLocalModel(model)
                    } label: {
                        LocalModelRow(
                            model: model,
                            formatBytes: formatBytes,
                            isActive: isActiveInstalledModel(model),
                            canActivate: canActivateInstalledModel(model),
                            activePreference: isActiveInstalledModel(model)
                                ? settings.localComputePreference : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canActivateInstalledModel(model))
                }

                Text("Tap a model to make it your local primary. Manage installs for more options.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var localModelActionButtons: some View {
        HStack {
            Button {
                showModelManager = true
            } label: {
                Label("Manage Models", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer(minLength: 12)

            Menu {
                Button {
                    showModelManager = true
                } label: {
                    Label("Browse Catalog", systemImage: "tray.and.arrow.down")
                }
                Button {
                    showModelManager = true
                } label: {
                    Label("Import Local Package", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("More Actions", systemImage: "ellipsis.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        }
    }

    private var installedLocalModels: [InstalledModel] {
        modelRegistry.installed.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var activeLocalModel: InstalledModel? {
        switch settings.selectedModel {
        case .ggufLocal:
            guard let id = selectedGGUFModelId else { return nil }
            return installedLocalModels.first { $0.id == id }
        case .coreMLLocal:
            guard let id = selectedCoreMLModelId else { return nil }
            return installedLocalModels.first { $0.id == id }
        default:
            return nil
        }
    }

    private var localModelsSummaryText: String {
        let count = installedLocalModels.count
        return count == 0 ? "None installed" : "\(count) installed"
    }

    private var localModelStatusText: String {
        if let active = activeLocalModel {
            return "Currently using \(active.name) for offline inference."
        }
        if installedLocalModels.isEmpty {
            return "Install a GGUF or Core ML pack to unlock on-device responses."
        }
        return "Tap a local model below to activate it for offline chat."
    }

    private var computePreferenceSummary: String {
        "Compute: \(settings.localComputePreference.title)"
    }

    private func activateLocalModel(_ model: InstalledModel) {
        guard canActivateInstalledModel(model) else { return }
        Task {
            await ModelActivationService.activate(
                model, ragService: ragService, settings: settings)
            await MainActor.run { refreshPipeline() }
        }
    }

    @ViewBuilder
    private var computePreferenceMenu: some View {
        Menu {
            ForEach(LocalComputePreference.allCases) { preference in
                Button {
                    settings.localComputePreference = preference
                } label: {
                    Label(preference.title, systemImage: preference.iconName)
                    if preference == settings.localComputePreference {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.localComputePreference.iconName)
                Text(settings.localComputePreference.badgeText)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    @ViewBuilder
    fileprivate var fallbackCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "arrow.triangle.2.circlepath", title: "Fallback Strategy",
                caption: "Stay responsive when networks fluctuate")
            Toggle("Enable First Fallback", isOn: $settings.enableFirstFallback)
            if settings.enableFirstFallback {
                Picker("First Fallback", selection: $settings.firstFallback) {
                    ForEach(firstFallbackOptions, id: \.self) { model in
                        Label(model.displayName, systemImage: model.iconName)
                            .tag(model)
                    }
                }
            }
            Toggle("Enable Second Fallback", isOn: $settings.enableSecondFallback)
            if settings.enableSecondFallback {
                Picker("Second Fallback", selection: $settings.secondFallback) {
                    ForEach(secondFallbackOptions, id: \.self) { model in
                        Label(model.displayName, systemImage: model.iconName)
                            .tag(model)
                    }
                }
            }
            SectionFooter(
                "Fallback models engage automatically if the primary pathway is unavailable.")
        }
    }

    @ViewBuilder
    fileprivate var pipelineCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "bolt.horizontal", title: "Execution Pipeline",
                caption: "Current model order and status")
            ForEach(pipelineStages) { stage in
                PipelineStageRow(stage: stage)
                if stage.id != pipelineStages.last?.id {
                    Divider()
                }
            }
            if pipelineStages.isEmpty {
                Text("No models configured")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
            Button {
                refreshPipeline()
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            SectionFooter(
                "Models are tried in order. If the primary fails, fallbacks engage automatically.")
        }
    }

    #if os(macOS)
        @ViewBuilder
        fileprivate var openAICard: some View {
            SurfaceCard {
                SectionHeader(
                    icon: "key.fill", title: "OpenAI Direct", caption: "Use your own API key")
                apiKeyEntry
                Picker("Model", selection: $settings.openaiModel) {
                    ForEach(openAIModelOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                Divider()
                Toggle("Send reasoning settings", isOn: $settings.responsesIncludeReasoning)
                Toggle("Send verbosity hint", isOn: $settings.responsesIncludeVerbosity)
                Toggle("Link previous CoT", isOn: $settings.responsesIncludeCoT)
                Toggle("Enforce max tokens", isOn: $settings.responsesIncludeMaxTokens)
                    .padding(.bottom, 4)
                apiKeyStatusView
                HStack {
                    Button(role: .destructive) {
                        settings.openaiAPIKey = ""
                        apiKeyStatus = .unknown
                    } label: {
                        Label("Clear Key", systemImage: "xmark.circle")
                    }
                    .disabled(settings.openaiAPIKey.isEmpty)

                    Spacer()

                    Button {
                        Task { await validateAPIKey() }
                    } label: {
                        if isValidatingAPIKey {
                            ProgressView()
                        } else {
                            Label("Validate Key", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(trimmedAPIKey.isEmpty || isValidatingAPIKey)
                }
                .font(.callout)
                SectionFooter(openAIContextFooter)
            }
        }
    #endif

    @ViewBuilder
    fileprivate var generationCard: some View {
        SurfaceCard {
            SectionHeader(icon: "slider.horizontal.3", title: "Generation Parameters")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.temperature, in: 0...1, step: 0.05)
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(settings.maxTokens)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxTokens) },
                        set: { settings.maxTokens = Int($0) }
                    ),
                    in: 100...16000,
                    step: 100
                )
            }
            SectionFooter(
                "Lower temperature keeps answers grounded. Increase max tokens for longer responses."
            )
        }
    }

    @ViewBuilder
    fileprivate var retrievalCard: some View {
        SurfaceCard {
            SectionHeader(icon: "magnifyingglass", title: "Retrieval Settings")
            HStack {
                Text("Top-K Chunks")
                Spacer()
                Text("\(settings.topK)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.topK) },
                    set: { settings.topK = Int($0) }
                ),
                in: 1...30,
                step: 1
            )
            Toggle("Lenient Retrieval Mode", isOn: $settings.lenientRetrievalMode)
            SectionFooter(
                "Higher K values surface more context but may include noise. Lenient mode relaxes similarity thresholds."
            )
        }
    }

    @ViewBuilder
    fileprivate var downloadsCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "tray.and.arrow.down", title: "Model Downloads",
                caption: "Manage local models")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Catalog", systemImage: "list.bullet.rectangle")
                    Spacer()
                    if downloadService.isLoadingCatalog {
                        ProgressView()
                    } else {
                        Text("\(downloadService.catalog.count)")
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Label("Installed Models", systemImage: "externaldrive")
                    Spacer()
                    Text("\(modelRegistry.installed.count)")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            NavigationLink {
                ModelManagerView(ragService: ragService)
            } label: {
                Label("Open Model Manager", systemImage: "brain.head.profile")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    fileprivate var developerCard: some View {
        SurfaceCard {
            SectionHeader(icon: "wrench.and.screwdriver", title: "Developer & Diagnostics")
            NavigationLink {
                DeveloperDiagnosticsHubView(ragService: ragService)
            } label: {
                Label("Diagnostics Hub", systemImage: "waveform.path.ecg")
            }
            NavigationLink {
                DeveloperSettingsView()
            } label: {
                Label("Developer Settings", systemImage: "hammer.fill")
            }
        }
    }

    @ViewBuilder
    fileprivate var aboutCard: some View {
        SurfaceCard {
            SectionHeader(icon: "info.circle", title: "About")
            NavigationLink {
                AboutView()
            } label: {
                Label("About OpenIntelligence", systemImage: "sparkles")
            }
        }
    }

    #if os(macOS)
        @ViewBuilder
        fileprivate var apiKeyEntry: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("API Key")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(showAPIKey ? "Hide" : "Show") {
                        showAPIKey.toggle()
                    }
                    .font(.caption)
                }
                HStack(spacing: 8) {
                    Group {
                        if showAPIKey {
                            TextField("sk-...", text: $settings.openaiAPIKey)
                        } else {
                            SecureField("sk-...", text: $settings.openaiAPIKey)
                        }
                    }
                    .focused($apiKeyFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                    #endif

                    if !settings.openaiAPIKey.isEmpty {
                        Button {
                            settings.openaiAPIKey = ""
                            apiKeyStatus = .unknown
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        @ViewBuilder
        fileprivate var apiKeyStatusView: some View {
            switch apiKeyStatus {
            case .unknown:
                EmptyView()
            case .validating:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            case .valid, .invalid:
                HStack(spacing: 8) {
                    Image(systemName: apiKeyStatus.icon)
                        .foregroundColor(apiKeyStatus.color)
                    Text(apiKeyStatus.message)
                        .font(.caption)
                        .foregroundColor(apiKeyStatus.color)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    #endif

    fileprivate var executionOptions: [ExecutionContext] {
        [.automatic, .onDeviceOnly, .preferCloud, .cloudOnly]
    }

    #if os(macOS)
        fileprivate var openAIModelOptions: [(id: String, name: String)] {
            [
                ("gpt-5", "GPT-5 (Reasoning)"),
                ("gpt-5-mini", "GPT-5 Mini"),
                ("o1", "o1 (Reasoning)"),
                ("o1-mini", "o1 Mini"),
                ("gpt-4o", "GPT-4o"),
                ("gpt-4o-mini", "GPT-4o Mini"),
                ("gpt-4-turbo-preview", "GPT-4 Turbo"),
                ("gpt-4.1-mini", "GPT-4.1 Mini"),
            ]
        }
    #endif

    fileprivate var executionSummaryText: String {
        var base: String
        switch settings.executionContext {
        case .automatic:
            base =
                "Automatic uses on-device compute first and seamlessly requests Private Cloud Compute when needed."
        case .onDeviceOnly:
            base =
                "On-device only keeps every token local. Complex requests may return concise answers."
        case .preferCloud:
            base =
                "Prefer cloud leans on Private Cloud Compute for richer responses, falling back on-device when offline."
        case .cloudOnly:
            base =
                "Cloud only routes all prompts through Private Cloud Compute. Requires connectivity."
        }
        if !settings.allowPrivateCloudCompute && settings.executionContext != .onDeviceOnly {
            base += " Enable Private Cloud Compute to unlock richer responses."
        }
        return base
    }

    #if os(macOS)
        fileprivate var openAIContextFooter: String {
            if trimmedAPIKey.isEmpty {
                return
                    "Add an API key to enable OpenAI Direct. Keys stay on device and are stored securely."
            }
            return
                "OpenAI Direct bypasses Apple Intelligence. Usage is billed by OpenAI under your account."
        }
    #endif

    fileprivate func pipelineHeadline() -> String {
        pipelineStages
            .map { "[\($0.role.shortCode)] \($0.name)" }
            .joined(separator: "  ->  ")
    }

    fileprivate func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024.0 { return String(format: "%.2f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    fileprivate func canActivateInstalledModel(_ model: InstalledModel) -> Bool {
        guard let url = model.localURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    fileprivate func isActiveInstalledModel(_ model: InstalledModel) -> Bool {
        switch model.backend {
        case .gguf:
            return settings.selectedModel == .ggufLocal && selectedGGUFModelId == model.id
        case .coreML:
            return settings.selectedModel == .coreMLLocal && selectedCoreMLModelId == model.id
        default:
            return false
        }
    }

    fileprivate var selectedGGUFModelId: UUID? {
        guard
            let idString = UserDefaults.standard.string(
                forKey: LlamaCPPiOSLLMService.selectedModelIdKey)
        else { return nil }
        return UUID(uuidString: idString)
    }

    fileprivate var selectedCoreMLModelId: UUID? {
        guard
            let idString = UserDefaults.standard.string(forKey: CoreMLLLMService.selectedModelIdKey)
        else { return nil }
        return UUID(uuidString: idString)
    }

    fileprivate func modelSummary(for type: LLMModelType) -> String {
        switch type {
        case .appleIntelligence:
            return
                "Apple Foundation Models with instant Private Cloud Compute fallback when queries demand it."
        case .chatGPTExtension:
            return
                "Uses Apple's ChatGPT integration (iOS 18.1+). User consent is requested by the system."
        case .onDeviceAnalysis:
            return
                "Extracts answers from your documents using NaturalLanguage on-device with zero AI downloads."
        case .openAIDirect:
            return "Calls OpenAI directly using your API key. Ideal for GPT-4o/GPT-5 experiments."
        case .ggufLocal:
            return "Runs an embedded GGUF model in-process on iOS for fully offline inference."
        case .coreMLLocal:
            return "Loads a custom Core ML model package for private on-device inference."
        }
    }

    fileprivate func bootstrap() async {
        await MainActor.run {
            deviceCapabilities = RAGService.checkDeviceCapabilities()
        }
        await MainActor.run { refreshPipeline() }
        if downloadService.catalog.isEmpty && !downloadService.isLoadingCatalog {
            await downloadService.loadCatalog(from: nil)
        }
        if modelRegistry.installed.isEmpty {
            await modelRegistry.load()
        }
    }

    @MainActor
    fileprivate func refreshPipeline() {
        pipelineStages = buildPipelineStages()
    }

    @MainActor
    fileprivate func normalizeFallbacks() {
        if settings.firstFallback == settings.selectedModel {
            if let replacement = firstFallbackOptions.first(where: { $0 != settings.selectedModel })
            {
                settings.firstFallback = replacement
            }
        }
        if settings.secondFallback == settings.selectedModel
            || settings.secondFallback == settings.firstFallback
        {
            if let replacement = secondFallbackOptions.first(where: {
                $0 != settings.selectedModel && $0 != settings.firstFallback
            }) {
                settings.secondFallback = replacement
            }
        }
        refreshPipeline()
    }

    fileprivate func buildPipelineStages() -> [ModelPipelineStage] {
        let preferences = preferredModelOrder()
        let currentActive = ragService.currentModelName

        return preferences.enumerated().map { index, entry in
            let role: ModelPipelineStage.Role =
                index == 0 ? .primary : (entry.enabled ? .fallback : .optional)
            let stage = self.stage(for: entry.type, role: role, enabled: entry.enabled)

            // Mark as active if this is the currently running model
            if stage.name.contains(currentActive) || currentActive.contains(entry.type.displayName)
            {
                return ModelPipelineStage(
                    name: stage.name,
                    role: stage.role,
                    detail: stage.detail,
                    status: .active,
                    icon: stage.icon
                )
            }

            return stage
        }
    }

    fileprivate func stage(for type: LLMModelType, role: ModelPipelineStage.Role, enabled: Bool)
        -> ModelPipelineStage
    {
        ModelPipelineStage(
            name: type.displayName,
            role: role,
            detail: stageDetail(for: type),
            status: stageStatus(for: type, enabled: enabled),
            icon: type.iconName
        )
    }

    fileprivate func stageStatus(for type: LLMModelType, enabled: Bool) -> ModelPipelineStage.Status
    {
        guard enabled else { return .disabled }
        switch type {
        case .appleIntelligence:
            if deviceCapabilities.supportsFoundationModels {
                return .available
            }
            if deviceCapabilities.supportsAppleIntelligence {
                return settings.allowPrivateCloudCompute
                    ? .requiresConfiguration(message: "Foundation Models are still downloading.")
                    : .requiresConfiguration(
                        message: "Enable Private Cloud Compute to unlock the full model.")
            }
            return .unavailable(reason: deviceCapabilities.appleIntelligenceStatus)
        case .chatGPTExtension:
            #if os(iOS)
                if #available(iOS 18.1, *) {
                    return deviceCapabilities.supportsAppleIntelligence
                        ? .available : .unavailable(reason: "Requires Apple Intelligence hardware")
                } else {
                    return .unavailable(reason: "Requires iOS 18.1+")
                }
            #else
                return .unavailable(reason: "Available on iOS only")
            #endif
        case .openAIDirect:
            #if os(macOS)
                return trimmedAPIKey.isEmpty
                    ? .requiresConfiguration(message: "Add your API key to enable this pathway.")
                    : .available
            #else
                return .unavailable(reason: "Disabled for Apple-native configuration")
            #endif
        case .onDeviceAnalysis:
            return .available
        case .ggufLocal:
            #if os(iOS)
                guard LlamaCPPiOSLLMService.runtimeAvailable else {
                    return .unavailable(reason: "GGUF runtime not bundled in this build")
                }
                return ggufConfigured
                    ? .available
                    : .requiresConfiguration(message: "Import a GGUF model via Model Manager.")
            #else
                return .unavailable(reason: "iOS only")
            #endif
        case .coreMLLocal:
            guard deviceCapabilities.supportsCoreML else {
                return .unavailable(reason: "Requires Core ML capable hardware")
            }
            return CoreMLLLMService.selectionIsReady()
                ? .available
                : .requiresConfiguration(
                    message: "Select a Core ML model package via Model Manager.")
        }
    }

    fileprivate func stageDetail(for type: LLMModelType) -> String {
        switch type {
        case .appleIntelligence:
            return "Apple Foundation Models with automatic PCC fallback"
        case .chatGPTExtension:
            return "System-level ChatGPT (Apple Intelligence)"
        case .onDeviceAnalysis:
            return "Extractive QA powered by NaturalLanguage"
        case .openAIDirect:
            return "OpenAI API using your credentials"
        case .ggufLocal:
            return "Embedded GGUF runtime (iOS)"
        case .coreMLLocal:
            return "Custom Core ML LLM package"
        }
    }

    fileprivate func preferredModelOrder() -> [(type: LLMModelType, enabled: Bool)] {
        var order: [(LLMModelType, Bool)] = []
        var seen = Set<LLMModelType>()
        let entries: [(LLMModelType, Bool)] = [
            (settings.selectedModel, true),
            (settings.firstFallback, settings.enableFirstFallback),
            (settings.secondFallback, settings.enableSecondFallback),
            (.onDeviceAnalysis, true),
        ]
        let allowed = Set(availablePrimaryModels)
        for entry in entries where !seen.contains(entry.0) && allowed.contains(entry.0) {
            order.append(entry)
            seen.insert(entry.0)
        }
        return order
    }

    @MainActor
    fileprivate func applyNow() {
        applyTask?.cancel()
        isApplyingModel = true
        applyTask = Task {
            defer { self.isApplyingModel = false }
            await self.applyPreferredService()
        }
    }

    @MainActor
    fileprivate func applyPreferredService() async {
        let preferences = preferredModelOrder()

        // Build chain: collect all available services
        var serviceChain: [LLMService] = []
        for entry in preferences {
            if let service = await instantiateService(for: entry.type, enabled: entry.enabled) {
                serviceChain.append(service)
            }
        }

        guard !serviceChain.isEmpty else {
            // Ultimate fallback if nothing works
            let ultimateFallback = OnDeviceAnalysisService()
            ragService.updateLLMService(ultimateFallback, fallbacks: [])
            refreshPipeline()
            return
        }

        // Primary is first, rest are fallbacks
        let primary = serviceChain[0]
        let fallbacks = Array(serviceChain.dropFirst())

        ragService.updateLLMService(primary, fallbacks: fallbacks)
        refreshPipeline()
        DSHaptics.success()
    }

    fileprivate func instantiateService(for type: LLMModelType, enabled: Bool) async -> LLMService?
    {
        guard enabled else { return nil }
        switch type {
        case .appleIntelligence:
            #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 15.0, *) {
                    return await MainActor.run {
                        let service = AppleFoundationLLMService()
                        service.toolHandler = ragService
                        return service.isAvailable ? service : nil
                    }
                }
            #endif
            return nil
        case .chatGPTExtension:
            #if os(iOS)
                let service = AppleChatGPTExtensionService()
                return service.isAvailable ? service : nil
            #else
                return nil
            #endif
        case .openAIDirect:
            #if os(macOS)
                guard !trimmedAPIKey.isEmpty else { return nil }
                return OpenAILLMService(apiKey: trimmedAPIKey, model: settings.openaiModel)
            #else
                return nil
            #endif
        case .onDeviceAnalysis:
            return OnDeviceAnalysisService()
        case .ggufLocal:
            #if os(iOS)
                return await MainActor.run { LlamaCPPiOSLLMService.fromRegistry() }
            #else
                return nil
            #endif
        case .coreMLLocal:
            return await CoreMLLLMService.fromRegistry()
        }
    }

    #if os(macOS)
        fileprivate func validateAPIKey() async {
            let key = trimmedAPIKey
            guard !key.isEmpty else {
                apiKeyStatus = .unknown
                return
            }
            await MainActor.run {
                isValidatingAPIKey = true
                apiKeyStatus = .validating
            }
            let config = InferenceConfig(maxTokens: 8, temperature: 0)
            let service = OpenAILLMService(apiKey: key, model: settings.openaiModel)
            do {
                let response = try await service.generate(
                    prompt: "pong", context: nil, config: config)
                await MainActor.run {
                    apiKeyStatus = response.text.isEmpty ? .invalid : .valid
                    isValidatingAPIKey = false
                }
            } catch {
                await MainActor.run {
                    apiKeyStatus = .invalid
                    isValidatingAPIKey = false
                }
            }
        }
    #endif

    fileprivate var trimmedAPIKey: String {
        settings.openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var availablePrimaryModels: [LLMModelType] {
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

    fileprivate var firstFallbackOptions: [LLMModelType] {
        settings.fallbackOptions(excluding: Set([settings.selectedModel]))
    }

    fileprivate var secondFallbackOptions: [LLMModelType] {
        settings.fallbackOptions(excluding: Set([settings.selectedModel, settings.firstFallback]))
    }

    fileprivate var selectedModelStatus: ModelPipelineStage.Status {
        stageStatus(for: settings.selectedModel, enabled: true)
    }

    fileprivate var shouldShowWhyUnavailable: Bool {
        switch selectedModelStatus {
        case .unavailable, .requiresConfiguration:
            return true
        default:
            return false
        }
    }

    fileprivate func gatingHelpText(for type: LLMModelType, status: ModelPipelineStage.Status)
        -> String
    {
        switch type {
        case .ggufLocal:
            #if os(iOS)
                var reasons: String = ""
                switch status {
                case .unavailable(let reason):
                    reasons = reason
                case .requiresConfiguration(let msg):
                    reasons = msg
                default:
                    reasons = "Unknown configuration issue."
                }
                let runtimeNote: String =
                    LlamaCPPiOSLLMService.runtimeAvailable
                    ? ""
                    : """
                    • GGUF runtime not bundled. Add the LocalLLMClient package and link its products to the app target:
                      - Xcode: File → Add Packages… → Add Local Package → select Vendor/LocalLLMClient
                      - Add products: LocalLLMClient, LocalLLMClientCore, LocalLLMClientLlama, LocalLLMClientLlamaC
                      - Build for a real device (recommended).
                    """

                return """
                    GGUF Local (iOS) runs an embedded llama.cpp runtime fully on-device.

                    Why unavailable:
                    - \(reasons)
                    \(runtimeNote)

                    Next steps:
                    1) Open Model Manager and import a small .gguf (e.g., 2–3B, 4-bit).
                    2) Set Local Primary → GGUF for your installed model.
                    3) Open Developer & Diagnostics → Backend Health → GGUF Local.
                       - Run “Verify Model File”, then “Smoke Test” or “Benchmark”.

                    Tip: Use iPhone 16 Pro/Max or newer for best performance.
                    """
            #else
                return "GGUF Local is available on iOS only."
            #endif

        case .coreMLLocal:
            var reasons: String = ""
            switch status {
            case .unavailable(let reason):
                reasons = reason
            case .requiresConfiguration(let msg):
                reasons = msg
            default:
                reasons = "No Core ML model selected."
            }
            return """
                Core ML Local runs a custom .mlpackage fully on-device.

                Why unavailable:
                - \(reasons)

                Next steps:
                1) Import a Core ML LLM package via Model Manager.
                2) Set Local Primary → Core ML.
                3) Apply and test in Backend Health.
                """

        case .appleIntelligence:
            return """
                Apple Intelligence (Foundation Models) runs on-device and can seamlessly use Private Cloud Compute when allowed.

                Status: \(deviceCapabilities.appleIntelligenceStatus)

                Next steps:
                • Ensure device meets requirements (A17 Pro+/M‑series) and Apple Intelligence is enabled in Settings.
                • On iOS 26+, the model may be downloading; try again later.
                • Use Execution & Privacy to force On‑Device Only or allow PCC.
                """

        default:
            return "No additional information for this model."
        }
    }
    #if os(iOS)
        fileprivate var ggufConfigured: Bool {
            guard LlamaCPPiOSLLMService.runtimeAvailable else { return false }
            guard
                let idString = UserDefaults.standard.string(
                    forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
                UUID(uuidString: idString) != nil
            else { return false }
            return modelRegistry.installed.contains(where: { $0.backend == .gguf })
        }
    #endif
}

private enum APIKeyValidationStatus {
    case unknown
    case validating
    case valid
    case invalid

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .validating: return "hourglass"
        case .valid: return "checkmark.seal.fill"
        case .invalid: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .validating: return .orange
        case .valid: return .green
        case .invalid: return .red
        }
    }

    var message: String {
        switch self {
        case .unknown: return ""
        case .validating: return "Validating key..."
        case .valid: return "API key verified."
        case .invalid: return "Could not validate key."
        }
    }
}

private struct HeroStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

private struct PipelineStageRow: View {
    let stage: ModelPipelineStage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stage.icon)
                .font(.title3)
                .foregroundColor(stage.role.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(stage.role.title) · \(stage.name)")
                        .font(.headline)
                    Spacer()
                    StageChip(status: stage.status)
                }
                Text(stage.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if case .unavailable(let reason) = stage.status {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                if case .requiresConfiguration(let message) = stage.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

private struct StageChip: View {
    let status: ModelPipelineStage.Status

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct LocalModelRow: View {
    let model: InstalledModel
    let formatBytes: (Int64?) -> String
    let isActive: Bool
    let canActivate: Bool
    let activePreference: LocalComputePreference?

    private var iconName: String {
        switch model.backend {
        case .gguf: return "doc.badge.gearshape"
        case .coreML: return "cpu"
        default: return "server.rack"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let vendor = model.vendor {
                        Label(vendor, systemImage: "tag")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let size = model.sizeBytes {
                        Label(formatBytes(size), systemImage: "externaldrive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let quant = model.quantization {
                        Label(quant, systemImage: "dial.low")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let meta = metadataLine() {
                    Text(meta)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isActive {
                HStack(spacing: 6) {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                    if let preference = activePreference {
                        Text(preference.badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            } else {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor.opacity(canActivate ? 1.0 : 0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .opacity(canActivate ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.12) : DSColors.surface.opacity(0.9))
    }

    private func metadataLine() -> String? {
        var components: [String] = []
        if let installedText = installDescriptor() {
            components.append(installedText)
        }
        if model.supportsToolUse {
            components.append("Tool Calls")
        }
        if let context = model.contextWindow {
            components.append("Context \(context)T")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func installDescriptor() -> String? {
        let relative = LocalModelRow.relativeFormatter.localizedString(
            for: model.installedAt, relativeTo: Date())
        return "Installed \(relative)"
    }
}

private struct ModelManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ragService: RAGService

    var body: some View {
        NavigationStack {
            ModelManagerView(ragService: ragService)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        // Full screen presentation - no detents to avoid scroll bugs
    }
}

extension ModelPipelineStage.Status {
    fileprivate var label: String {
        switch self {
        case .active: return "Active"
        case .available: return "Available"
        case .unavailable: return "Unavailable"
        case .requiresConfiguration: return "Configure"
        case .disabled: return "Disabled"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .active: return .green
        case .available: return .accentColor
        case .unavailable: return .red
        case .requiresConfiguration: return .orange
        case .disabled: return .secondary
        }
    }

    fileprivate var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .available: return "bolt.circle.fill"
        case .unavailable: return "xmark.octagon.fill"
        case .requiresConfiguration: return "gearshape.2"
        case .disabled: return "pause.circle"
        }
    }
}
