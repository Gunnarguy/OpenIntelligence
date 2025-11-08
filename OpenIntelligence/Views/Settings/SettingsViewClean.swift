//
//  SettingsViewClean.swift
//  OpenIntelligence
//
//  Clean, modern settings redesign
//

import SwiftUI

struct SettingsViewClean: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var modelRegistry = ModelRegistry.shared

    @State private var showModelGallery = false

    var body: some View {
        List {
            // Current Model Section
            Section {
                NavigationLink {
                    ModelSelectionScreen(ragService: ragService)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: settings.selectedModel.iconName)
                            .font(.title2)
                            .foregroundStyle(.blue.gradient)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Model")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(ragService.currentModelName)
                                .font(.body.weight(.medium))
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Intelligence")
            }

            // Installed Local Models
            if !modelRegistry.installed.isEmpty {
                Section {
                    ForEach(modelRegistry.installed) { model in
                        ModelRowClean(model: model, ragService: ragService)
                    }
                } header: {
                    HStack {
                        Text("Local Models")
                        Spacer()
                        Button {
                            showModelGallery = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                    }
                }
            }

            // Generation Settings
            Section {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", settings.temperature))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.temperature, in: 0...2, step: 0.1)

                Stepper(
                    "Max Tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 50...4000,
                    step: 50)
            } header: {
                Text("Generation")
            }

            // Retrieval Settings
            Section {
                Stepper("Top Results: \(settings.topK)", value: $settings.topK, in: 1...10)

                Toggle("Lenient Mode", isOn: $settings.lenientRetrievalMode)
            } header: {
                Text("Retrieval")
            } footer: {
                Text("Lenient mode returns results even with low similarity scores")
                    .font(.caption)
            }

            // Privacy
            Section {
                Toggle("Allow Private Cloud Compute", isOn: $settings.allowPrivateCloudCompute)
            } header: {
                Text("Privacy")
            } footer: {
                Text("When enabled, some models may process data on Apple's secure servers")
                    .font(.caption)
            }

            // About
            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    Label("About OpenIntelligence", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showModelGallery) {
            ModelGalleryScreen(ragService: ragService)
        }
    }
}

// MARK: - Model Row

struct ModelRowClean: View {
    let model: InstalledModel
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore

    private var isActive: Bool {
        let defaults = UserDefaults.standard
        switch model.backend {
        case .gguf:
            guard settings.selectedModel == .ggufLocal,
                let idStr = defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
                let id = UUID(uuidString: idStr)
            else { return false }
            return id == model.id
        case .coreML:
            guard settings.selectedModel == .coreMLLocal,
                let idStr = defaults.string(forKey: CoreMLLLMService.selectedModelIdKey),
                let id = UUID(uuidString: idStr)
            else { return false }
            return id == model.id
        case .mlxServer:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(isActive ? Color.blue : Color.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(model.backend.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let size = model.sizeBytes {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let quant = model.quantization {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(quant)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue.gradient)
            } else {
                Button {
                    activateModel()
                } label: {
                    Text("Use")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch model.backend {
        case .gguf: return "cube.fill"
        case .coreML: return "cpu.fill"
        case .mlxServer: return "server.rack"
        }
    }

    private func activateModel() {
        Task { @MainActor in
            await ModelActivationService.activate(model, ragService: ragService, settings: settings)
        }
    }
}

// MARK: - Model Selection Screen

struct ModelSelectionScreen: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        List {
            ForEach(settings.primaryModelOptions, id: \.self) { modelType in
                Button {
                    settings.selectedModel = modelType
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: modelType.iconName)
                            .font(.title3)
                            .foregroundStyle(
                                settings.selectedModel == modelType ? Color.blue : Color.secondary
                            )
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(modelType.displayName)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)

                            Text(modelType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if settings.selectedModel == modelType {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue.gradient)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Select Model")
    }
}

// MARK: - About Screen

struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("0.1.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            }

            Section {
                Text(
                    "OpenIntelligence is a privacy-first RAG (Retrieval-Augmented Generation) app for iOS. All processing happens on-device or through Apple's Private Cloud Compute."
                )
                .font(.callout)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("About")
    }
}
