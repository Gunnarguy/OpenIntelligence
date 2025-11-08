import Combine
import SwiftUI

@MainActor
struct ModelManagerView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @State private var deviceCapabilities = DeviceCapabilities()
    @State private var availableModels: [LLMModel] = []
    @State private var showingCustomModelHelp = false
    @State private var showingComparison = false
    @State private var didLoad = false
    @StateObject private var downloadService = ModelDownloadService.shared
    @StateObject private var modelRegistry = ModelRegistry.shared

    var body: some View {
        List {
            overviewSection

            if !activeDownloads.isEmpty {
                downloadsSection
            }

            installedModelsSection
            availableModelsSection
            toolsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Model Manager")
        .navigationBarTitleDisplayMode(.large)
        .task { await prepareOnce() }
        .sheet(isPresented: $showingCustomModelHelp) { CustomModelInstructionsView() }
        .sheet(isPresented: $showingComparison) {
            ModelComparisonSheet(
                deviceCapabilities: deviceCapabilities,
                installedModels: modelRegistry.installed
            )
        }
        .onReceive(modelRegistry.$installed) { _ in
            refreshAvailableModels()
        }
    }

    private var activeDownloads: [DownloadState] {
        downloadService.downloads.values
            .filter { state in
                switch state.status {
                case .downloading, .verifying, .registering:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.progress > $1.progress }
    }

    private var overviewSection: some View {
        Section("Overview") {
            StatusSummaryView(
                currentModel: ragService.currentModelName,
                documents: ragService.documents.count,
                chunks: ragService.totalChunksStored,
                storage: estimatedMemoryUsage
            )

            DeviceSupportView(capabilities: deviceCapabilities)
        }
    }

    private var downloadsSection: some View {
        Section("Active Downloads") {
            ForEach(activeDownloads, id: \.id) { state in
                ActiveDownloadRow(
                    state: state,
                    onPause: { downloadService.pause(entryID: state.id) },
                    onResume: { downloadService.resume(entryID: state.id) },
                    onCancel: { downloadService.cancel(entryID: state.id) }
                )
            }
        }
    }

    private var installedModelsSection: some View {
        Section("Installed Models") {
            if modelRegistry.installed.isEmpty {
                Text("No downloaded models yet. Open the gallery to grab one.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(modelRegistry.installed.filter { $0.backend != .mlxServer }) { model in
                    InstalledModelRow(
                        model: model,
                        isActive: isModelActive(model),
                        onActivate: { Task { await activate(model) } },
                        onRemove: { Task { await remove(model) } },
                        formatFileSize: formatFileSize
                    )
                }
            }
        }
    }

    private var availableModelsSection: some View {
        Section("Available Sources") {
            if availableModels.isEmpty {
                Text("Loading available models...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(availableModels) { model in
                    AvailableModelRow(model: model)
                }
            }
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            NavigationLink {
                ModelGalleryScreen(ragService: ragService)
            } label: {
                Label("Open Model Gallery", systemImage: "tray.and.arrow.down")
            }

            Button {
                showingComparison = true
            } label: {
                Label("Compare Models", systemImage: "chart.bar.doc.horizontal")
            }

            Button {
                showingCustomModelHelp = true
            } label: {
                Label("Custom Model Instructions", systemImage: "questionmark.circle")
            }
        }
    }

    @MainActor
    private func prepareOnce() async {
        guard !didLoad else { return }
        didLoad = true
        // Capture device capabilities up front so the status cards and available list are in sync.
        deviceCapabilities = RAGService.checkDeviceCapabilities()
        refreshAvailableModels()
        if downloadService.catalog.isEmpty {
            await downloadService.loadCatalog(from: nil)
        }
    }

    @MainActor
    private func activate(_ model: InstalledModel) async {
        // Drive the shared activation path so telemetry and auto-tune hooks stay consistent.
        await ModelActivationService.activate(model, ragService: ragService, settings: settings)
        refreshAvailableModels()
    }

    @MainActor
    private func remove(_ model: InstalledModel) async {
        // Remove the cartridge, clean up persisted selection, and re-evaluate availability badges.
        ModelRegistry.shared.remove(model, deleteFromDisk: true)
        clearSelectionIfNeeded(for: model)
        refreshAvailableModels()
    }

    @MainActor
    private func refreshAvailableModels() {
        // Rebuild the catalog of built-in pathways so UI state reflects current installs and hardware support.
        var items: [LLMModel] = []
        items.append(contentsOf: foundationModels())
        items.append(onDeviceAnalysisModel())
        if let coreML = coreMLModel() {
            items.append(coreML)
        }
        availableModels = items
    }

    @MainActor
    private func foundationModels() -> [LLMModel] {
        var models: [LLMModel] = []
        let tokens = deviceCapabilities.appleIntelligenceContextTokens
        let contextDescription =
            deviceCapabilities.appleIntelligenceContextDescription ?? "Unavailable on this device."
        let availability = deviceCapabilities.supportsFoundationModels
        let note =
            availability
            ? "Runs on-device with automatic Private Cloud Compute expansion for longer prompts."
            : (deviceCapabilities.appleIntelligenceUnavailableReason
                ?? "Requires supported Apple Silicon hardware.")

        models.append(
            LLMModel(
                name: "Apple Intelligence",
                modelType: .appleHybrid,
                parameterCount: "System managed",
                quantization: "Neural Engine optimised",
                contextLength: tokens,
                contextDescription: contextDescription,
                availabilityNote: note,
                isAvailable: availability
            )
        )

        #if os(iOS)
            if #available(iOS 18.1, *), deviceCapabilities.supportsAppleIntelligence {
                let chatGPTNote =
                    deviceCapabilities.appleIntelligenceUnavailableReason
                    ?? "Enable ChatGPT under Apple Intelligence & Siri settings."
                models.append(
                    LLMModel(
                        name: "ChatGPT (Apple Intelligence)",
                        modelType: .appleChatGPT,
                        parameterCount: "System managed",
                        quantization: nil,
                        contextLength: tokens,
                        contextDescription: "System-level consent driven ChatGPT access.",
                        availabilityNote: chatGPTNote,
                        isAvailable: true
                    )
                )
            }
        #endif

        return models
    }

    private func onDeviceAnalysisModel() -> LLMModel {
        LLMModel(
            name: "On-Device Analysis",
            modelType: .onDeviceAnalysis,
            parameterCount: "Extractive QA",
            quantization: "Deterministic",
            contextLength: 0,
            contextDescription: "Answers straight from retrieved text without generation.",
            availabilityNote: "Always available, no setup required.",
            isAvailable: true
        )
    }

    private func coreMLModel() -> LLMModel? {
        guard deviceCapabilities.supportsCoreML else { return nil }
        let hasRegistryModel = modelRegistry.installed.contains { $0.backend == .coreML }
        let isReady = hasRegistryModel || CoreMLLLMService.selectionIsReady()
        guard isReady else { return nil }

        let note = hasRegistryModel
            ? "Ready to run using the Neural Engine."
            : "Previously imported Core ML package detected."
        return LLMModel(
            name: "Core ML (.mlpackage)",
            modelType: .coreMLPackage,
            parameterCount: "Varies",
            quantization: "Core ML runtime",
            contextLength: 8_000,
            contextDescription: "Bring-your-own Core ML LLM.",
            availabilityNote: note,
            isAvailable: isReady
        )
    }

    private var estimatedMemoryUsage: String {
        let bytesPerChunk = (512 * 4) + 500
        let totalBytes = bytesPerChunk * ragService.totalChunksStored
        guard totalBytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(totalBytes))
    }

    private func isModelActive(_ model: InstalledModel) -> Bool {
        let defaults = UserDefaults.standard
        switch model.backend {
        case .gguf:
            return defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey)
                == model.id.uuidString
        case .coreML:
            return defaults.string(forKey: CoreMLLLMService.selectedModelIdKey)
                == model.id.uuidString
        default:
            return false
        }
    }

    @MainActor
    private func clearSelectionIfNeeded(for model: InstalledModel) {
        let defaults = UserDefaults.standard
        switch model.backend {
        case .gguf:
            if defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey)
                == model.id.uuidString
            {
                LlamaCPPiOSLLMService.clearSelection()
                if settings.selectedModel == .ggufLocal {
                    settings.selectedModel =
                        settings.primaryModelOptions.first ?? .appleIntelligence
                }
            }
        case .coreML:
            if defaults.string(forKey: CoreMLLLMService.selectedModelIdKey) == model.id.uuidString {
                CoreMLLLMService.clearSelection()
                if settings.selectedModel == .coreMLLocal {
                    settings.selectedModel =
                        settings.primaryModelOptions.first ?? .appleIntelligence
                }
            }
        default:
            break
        }
    }

    private func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct StatusSummaryView: View {
    let currentModel: String
    let documents: Int
    let chunks: Int
    let storage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(currentModel)
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 16) {
                SummaryStat(title: "Documents", value: "\(documents)")
                SummaryStat(title: "Chunks", value: "\(chunks)")
                SummaryStat(title: "Vector Store", value: storage)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct DeviceSupportView: View {
    let capabilities: DeviceCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapabilityRow(
                icon: "sparkles",
                label: "Foundation Models",
                available: capabilities.supportsFoundationModels,
                detail: capabilities.deviceChip.rawValue
            )

            CapabilityRow(
                icon: "cloud.fill",
                label: "Private Cloud Compute",
                available: capabilities.supportsPrivateCloudCompute,
                detail: capabilities.supportsPrivateCloudCompute ? "Ready" : "Unavailable"
            )

            CapabilityRow(
                icon: "cpu",
                label: "Neural Engine",
                available: capabilities.hasNeuralEngine,
                detail: capabilities.deviceChip.neuralEnginePerformance
            )
        }
        .padding(.vertical, 4)
    }
}

private struct CapabilityRow: View {
    let icon: String
    let label: String
    let available: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(available ? .accentColor : .secondary)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(available ? detail : "Off")
                .font(.caption)
                .foregroundColor(available ? .secondary : .orange)
        }
    }
}

private struct ActiveDownloadRow: View {
    let state: DownloadState
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.entry.name)
                .font(.subheadline.weight(.semibold))

            if case .downloading = state.status {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }

            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                if let primary = primaryAction {
                    Button(action: primary.handler) {
                        Image(systemName: primary.icon)
                    }
                    .buttonStyle(.plain)
                }

                if canCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch state.status {
        case .downloading:
            return String(format: "%.0f%%", state.progress * 100)
        case .verifying:
            return "Verifying"
        case .registering:
            return "Installing"
        default:
            return ""
        }
    }

    private var canCancel: Bool {
        switch state.status {
        case .downloading, .paused:
            return true
        default:
            return false
        }
    }

    private var primaryAction: (handler: () -> Void, icon: String)? {
        switch state.status {
        case .downloading:
            return ({ onPause() }, "pause.circle.fill")
        case .paused:
            return ({ onResume() }, "play.circle.fill")
        default:
            return nil
        }
    }
}

private struct InstalledModelRow: View {
    let model: InstalledModel
    let isActive: Bool
    let onActivate: () -> Void
    let onRemove: () -> Void
    let formatFileSize: (Int64?) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 12) {
                Label(model.backend.displayName, systemImage: model.backend.iconName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let vendor = model.vendor {
                    Text(vendor)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let quant = model.quantization {
                    Text(quant)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let size = model.sizeBytes {
                    Text(formatFileSize(size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Activate", action: onActivate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isActive)

                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AvailableModelRow: View {
    let model: LLMModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.name)
                    .font(.headline)
                Spacer()
                AvailabilityBadge(isAvailable: model.isAvailable)
            }

            if let description = model.contextDescription {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Text(model.parameterCount)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let quant = model.quantization {
                    Text(quant)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let note = model.availabilityNote {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AvailabilityBadge: View {
    let isAvailable: Bool

    var body: some View {
        Text(isAvailable ? "Ready" : "Unavailable")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isAvailable ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundColor(isAvailable ? .green : .orange)
            .clipShape(Capsule())
    }
}

struct ModelComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let deviceCapabilities: DeviceCapabilities
    let installedModels: [InstalledModel]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)]
    }

    private var comparisonEntries: [ComparisonEntry] {
        LLMModelType.allCases
            .filter(isRelevant(_:))
            .map { type in
                ComparisonEntry(
                    type: type,
                    availability: availability(for: type),
                    highlights: highlights(for: type),
                    capabilities: Array(type.capabilities.prefix(4))
                )
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(comparisonEntries) { entry in
                        ModelComparisonCard(entry: entry)
                    }
                }
                .padding()
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Compare Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isRelevant(_ type: LLMModelType) -> Bool {
        #if os(iOS)
            let relevant: Set<LLMModelType> = [
                .appleIntelligence, .chatGPTExtension, .onDeviceAnalysis,
                .openAIDirect, .ggufLocal, .coreMLLocal,
            ]
            return relevant.contains(type)
        #else
            return true
        #endif
    }

    private func availability(for type: LLMModelType) -> ComparisonEntry.Availability {
        switch type {
        case .appleIntelligence:
            if deviceCapabilities.supportsFoundationModels {
                return .ready("Runs locally with PCC fallback")
            }
            return .blocked(
                deviceCapabilities.appleIntelligenceUnavailableReason
                    ?? "Requires supported hardware")
        case .chatGPTExtension:
            if deviceCapabilities.supportsAppleIntelligence {
                return .ready("Enable under Apple Intelligence settings")
            }
            return .blocked("Requires Apple Intelligence enabled device")
        case .ggufLocal:
            if installedModels.contains(where: { $0.backend == .gguf }) {
                return .ready("Cartridge installed")
            }
            return .optional("Download a GGUF from the gallery")
        case .coreMLLocal:
            if installedModels.contains(where: { $0.backend == .coreML }) {
                return .ready("Custom Core ML package detected")
            }
            return .optional("Import a .mlpackage via Files")
        case .onDeviceAnalysis:
            return .ready("Always on-device")
        case .openAIDirect:
            return .optional("Requires OpenAI API key")
        }
    }

    private func highlights(for type: LLMModelType) -> [String] {
        switch type {
        case .appleIntelligence:
            return ["Hybrid", "Private"]
        case .chatGPTExtension:
            return ["Apple Intelligence"]
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return ["Offline"]
        case .openAIDirect:
            return ["Cloud"]
        }
    }

    struct ComparisonEntry: Identifiable {
        enum Availability {
            case ready(String)
            case optional(String)
            case blocked(String)

            var color: Color {
                switch self {
                case .ready: return .green
                case .optional: return .orange
                case .blocked: return .red
                }
            }

            var label: String {
                switch self {
                case .ready: return "Ready"
                case .optional: return "Optional"
                case .blocked: return "Unavailable"
                }
            }

            var detail: String {
                switch self {
                case .ready(let detail), .optional(let detail), .blocked(let detail):
                    return detail
                }
            }
        }

        let id = UUID()
        let type: LLMModelType
        let availability: Availability
        let highlights: [String]
        let capabilities: [String]
    }
}

private struct ModelComparisonCard: View {
    let entry: ModelComparisonSheet.ComparisonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: entry.type.iconName)
                    .foregroundColor(.accentColor)
                Text(entry.type.displayName)
                    .font(.headline)
                Spacer()
            }

            ComparisonAvailabilityBadge(availability: entry.availability)

            if !entry.highlights.isEmpty {
                HStack {
                    ForEach(entry.highlights, id: \.self) { highlight in
                        Text(highlight)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Text(entry.type.description)
                .font(.caption)
                .foregroundColor(.secondary)

            if !entry.capabilities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.capabilities, id: \.self) { capability in
                        Label(capability, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SpecLine(title: "Category", value: entry.type.category)
                SpecLine(title: "Privacy", value: entry.type.privacyLevel)
                SpecLine(
                    title: "Network", value: entry.type.requiresNetwork ? "Required" : "Optional")
                SpecLine(title: "Context", value: entry.type.contextDescription)
            }
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ComparisonAvailabilityBadge: View {
    let availability: ModelComparisonSheet.ComparisonEntry.Availability

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(availability.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(availability.color.opacity(0.15))
                .foregroundColor(availability.color)
                .clipShape(Capsule())
            Text(availability.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct SpecLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

struct CustomModelInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Core ML Packages") {
                    InstructionRow(text: "Convert your model to .mlpackage using coremltools.")
                    InstructionRow(text: "Copy the package into OpenIntelligence via Files app.")
                    InstructionRow(text: "Activate it from Installed Models once detected.")
                }

                Section("GGUF Models") {
                    InstructionRow(text: "Download GGUF builds from trusted Hugging Face repos.")
                    InstructionRow(text: "AirDrop or Files-import the .gguf into the app.")
                    InstructionRow(text: "Activate once the llama.cpp runtime is available.")
                }

                Section("Suggested Starters") {
                    InstructionRow(text: "Qwen2.5 1.5B Q4_K_M")
                    InstructionRow(text: "Llama 3.1 8B Q4_K_M")
                    InstructionRow(text: "Phi-3 Mini 3.8B")
                }
            }
            .navigationTitle("Custom Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InstructionRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 6)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let service = RAGService()
    return NavigationStack {
        ModelManagerView(ragService: service)
            .environmentObject(SettingsStore(ragService: service))
    }
}
