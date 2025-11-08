//
//  ModelSelectorSheet.swift
//  OpenIntelligence
//
//  Enhanced granular model selection interface
//

import SwiftUI

struct ModelSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var modelRegistry = ModelRegistry.shared
    @State private var selectedFilter: ModelFilter = .all
    @State private var showComparison = false
    @State private var previewModel: LLMModelType?
    @State private var deviceCapabilities = DeviceCapabilities()

    enum ModelFilter: String, CaseIterable {
        case all = "All"
        case local = "Local"
        case cloud = "Cloud"
        case hybrid = "Hybrid"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .local: return "iphone"
            case .cloud: return "cloud.fill"
            case .hybrid: return "sparkles"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Filter chips
                    filterChips

                    // Quick stats
                    quickStatsCard

                    // Model cards grouped by category
                    modelCards
                }
                .padding()
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComparison = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                }
            }
            .sheet(isPresented: $showComparison) {
                ModelComparisonSheet(
                    deviceCapabilities: deviceCapabilities,
                    installedModels: modelRegistry.installed
                )
            }
            .sheet(item: $previewModel) { modelType in
                ModelPreviewSheet(
                    modelType: modelType, ragService: ragService,
                    onActivate: {
                        activateModel(modelType)
                    })
            }
            .onAppear {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ModelFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        count: modelCount(for: filter)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Quick Stats

    @ViewBuilder
    private var quickStatsCard: some View {
        HStack(spacing: 0) {
            QuickStatBadge(
                value: "\(modelRegistry.installed.filter { $0.backend == .gguf }.count)",
                label: "GGUF",
                icon: "doc.badge.gearshape",
                color: .blue
            )

            Divider()

            QuickStatBadge(
                value: "\(modelRegistry.installed.filter { $0.backend == .coreML }.count)",
                label: "Core ML",
                icon: "cpu",
                color: .purple
            )

            Divider()

            QuickStatBadge(
                value: deviceCapabilities.supportsFoundationModels ? "✓" : "✗",
                label: "Foundation",
                icon: "brain.head.profile",
                color: deviceCapabilities.supportsFoundationModels ? .green : .gray
            )
        }
        .frame(height: 80)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Model Cards

    @ViewBuilder
    private var modelCards: some View {
        VStack(spacing: 16) {
            // Local GGUF Models
            if shouldShowCategory(.local) && !ggufModels.isEmpty {
                ModelCategorySection(title: "Local GGUF Models", icon: "doc.badge.gearshape") {
                    ForEach(ggufModels) { model in
                        GGUFModelCard(
                            model: model,
                            isActive: isActiveGGUF(model),
                            formatBytes: formatBytes
                        ) {
                            activateGGUFModel(model)
                        } onPreview: {
                            previewModel = .ggufLocal
                        }
                    }
                }
            }

            // Core ML Models
            if shouldShowCategory(.local) && !coreMLModels.isEmpty {
                ModelCategorySection(title: "Core ML Models", icon: "cpu") {
                    ForEach(coreMLModels) { model in
                        CoreMLModelCard(
                            model: model,
                            isActive: isActiveCoreML(model),
                            formatBytes: formatBytes
                        ) {
                            activateCoreMLModel(model)
                        } onPreview: {
                            previewModel = .coreMLLocal
                        }
                    }
                }
            }

            // Foundation Models
            if shouldShowCategory(.hybrid) || shouldShowCategory(.cloud) {
                ModelCategorySection(title: "Apple Intelligence", icon: "sparkles") {
                    FoundationModelCard(
                        deviceCapabilities: deviceCapabilities,
                        isActive: settings.selectedModel == .appleIntelligence
                    ) {
                        activateModel(.appleIntelligence)
                    } onPreview: {
                        previewModel = .appleIntelligence
                    }

                    #if canImport(AppIntents)
                        if #available(iOS 18.1, *), deviceCapabilities.supportsAppleIntelligence {
                            ChatGPTModelCard(
                                isActive: settings.selectedModel == .chatGPTExtension
                            ) {
                                activateModel(.chatGPTExtension)
                            } onPreview: {
                                previewModel = .chatGPTExtension
                            }
                        }
                    #endif
                }
            }

            // Fallback
            if shouldShowCategory(.local) || shouldShowCategory(.all) {
                ModelCategorySection(title: "Fallback Options", icon: "arrow.triangle.2.circlepath")
                {
                    FallbackModelCard(
                        isActive: settings.selectedModel == .onDeviceAnalysis
                    ) {
                        activateModel(.onDeviceAnalysis)
                    } onPreview: {
                        previewModel = .onDeviceAnalysis
                    }
                }
            }

            // Empty state
            if filteredModelsEmpty {
                EmptyStateView(filter: selectedFilter)
            }
        }
    }

    // MARK: - Helper Methods

    private var ggufModels: [InstalledModel] {
        modelRegistry.installed.filter { $0.backend == .gguf }
    }

    private var coreMLModels: [InstalledModel] {
        modelRegistry.installed.filter { $0.backend == .coreML }
    }

    private func isActiveGGUF(_ model: InstalledModel) -> Bool {
        guard settings.selectedModel == .ggufLocal,
            let idString = UserDefaults.standard.string(
                forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
            let selectedId = UUID(uuidString: idString)
        else {
            return false
        }
        return selectedId == model.id
    }

    private func isActiveCoreML(_ model: InstalledModel) -> Bool {
        guard settings.selectedModel == .coreMLLocal,
            let idString = UserDefaults.standard.string(
                forKey: CoreMLLLMService.selectedModelIdKey),
            let selectedId = UUID(uuidString: idString)
        else {
            return false
        }
        return selectedId == model.id
    }

    private func shouldShowCategory(_ category: ModelFilter) -> Bool {
        if selectedFilter == .all { return true }
        return selectedFilter == category
    }

    private var filteredModelsEmpty: Bool {
        switch selectedFilter {
        case .all:
            return ggufModels.isEmpty && coreMLModels.isEmpty
        case .local:
            return ggufModels.isEmpty && coreMLModels.isEmpty
        case .cloud, .hybrid:
            return false  // Foundation Models always shown
        }
    }

    private func modelCount(for filter: ModelFilter) -> Int {
        switch filter {
        case .all:
            return modelRegistry.installed.count + 2  // +2 for Foundation + Fallback
        case .local:
            return modelRegistry.installed.count + 1  // +1 for Fallback
        case .cloud, .hybrid:
            return deviceCapabilities.supportsAppleIntelligence ? 2 : 1
        }
    }

    private func activateGGUFModel(_ model: InstalledModel) {
        Task {
            await ModelActivationService.activate(model, ragService: ragService, settings: settings)
            await MainActor.run {
                DSHaptics.success()
                dismiss()
            }
        }
    }

    private func activateCoreMLModel(_ model: InstalledModel) {
        Task {
            await ModelActivationService.activate(model, ragService: ragService, settings: settings)
            await MainActor.run {
                DSHaptics.success()
                dismiss()
            }
        }
    }

    private func activateModel(_ type: LLMModelType) {
        settings.selectedModel = type
        Task {
            // Let SettingsView's onChange handler apply the model
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s for UI feedback
            await MainActor.run {
                DSHaptics.success()
                dismiss()
            }
        }
    }

    private func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2)
                    )
                    .clipShape(Capsule())
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : DSColors.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct QuickStatBadge: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ModelCategorySection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)

            content
        }
    }
}

private struct GGUFModelCard: View {
    let model: InstalledModel
    let isActive: Bool
    let formatBytes: (Int64?) -> String
    let onActivate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "doc.badge.gearshape")
                        .font(.title2)
                        .foregroundColor(isActive ? .green : .accentColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        if let size = model.sizeBytes {
                            Label(formatBytes(size), systemImage: "externaldrive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let quant = model.quantization {
                            Label(quant, systemImage: "cpu")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.green)
                    }
                }

                Spacer()

                // Actions
                Button(action: onPreview) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.green.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CoreMLModelCard: View {
    let model: InstalledModel
    let isActive: Bool
    let formatBytes: (Int64?) -> String
    let onActivate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.purple.opacity(0.2) : Color.purple.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundColor(isActive ? .purple : .purple.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        if let size = model.sizeBytes {
                            Label(formatBytes(size), systemImage: "externaldrive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Label("Core ML", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.purple)
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.purple.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FoundationModelCard: View {
    let deviceCapabilities: DeviceCapabilities
    let isActive: Bool
    let onActivate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .opacity(0.2)
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Intelligence")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(
                        deviceCapabilities.supportsFoundationModels
                            ? "On-device + Private Cloud Compute"
                            : "Preparing..."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.blue)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    if !deviceCapabilities.supportsFoundationModels {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }

                    Button(action: onPreview) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(isActive ? Color.blue.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!deviceCapabilities.supportsFoundationModels)
    }
}

private struct ChatGPTModelCard: View {
    let isActive: Bool
    let onActivate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ChatGPT Extension")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("System-level ChatGPT access")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.green)
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.green.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FallbackModelCard: View {
    let isActive: Bool
    let onActivate: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("On-Device Analysis")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Extractive QA, no generative AI")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button(action: onPreview) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(isActive ? Color.orange.opacity(0.05) : DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyStateView: View {
    let filter: ModelSelectorSheet.ModelFilter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No \(filter.rawValue.lowercased()) models")
                .font(.headline)
                .foregroundColor(.primary)

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NavigationLink {
                ModelManagerView(ragService: RAGService())
            } label: {
                Label("Browse Model Gallery", systemImage: "tray.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyMessage: String {
        switch filter {
        case .all:
            return "Get started by downloading models from the Model Gallery"
        case .local:
            return "Download GGUF or Core ML models for offline inference"
        case .cloud, .hybrid:
            return "Apple Intelligence models are available when device supports them"
        }
    }
}

// MARK: - Model Preview Sheet

private struct ModelPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelType: LLMModelType
    let ragService: RAGService
    let onActivate: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero section
                    VStack(spacing: 12) {
                        Image(systemName: modelType.iconName)
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)

                        Text(modelType.displayName)
                            .font(.title.bold())

                        Text(modelType.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)

                    // Specs
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Specifications")
                            .font(.headline)

                        SpecRow(label: "Type", value: modelType.category)
                        SpecRow(label: "Privacy", value: modelType.privacyLevel)
                        SpecRow(
                            label: "Network",
                            value: modelType.requiresNetwork ? "Required" : "Optional")
                        SpecRow(label: "Context", value: modelType.contextDescription)
                    }
                    .padding(20)
                    .background(DSColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Capabilities
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Capabilities")
                            .font(.headline)

                        ForEach(modelType.capabilities, id: \.self) { capability in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(capability)
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                    .background(DSColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Activate button
                    Button(action: {
                        onActivate()
                        dismiss()
                    }) {
                        Label("Activate This Model", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Model Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - LLMModelType Extensions

#Preview {
    ModelSelectorSheet(ragService: RAGService())
        .environmentObject(SettingsStore(ragService: RAGService()))
}
