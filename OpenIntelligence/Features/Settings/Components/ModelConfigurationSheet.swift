//
//  ModelConfigurationSheet.swift
//  OpenIntelligence
//
//  Unified sheet for all model inference parameters with presets
//  and per-model defaults. Consolidates scattered parameter settings
//  into one granular, customizable interface.
//

import SwiftUI

struct ModelConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var temperature: Double
    @State private var maxTokens: Int
    @State private var topP: Double
    @State private var contextLength: Int
    @State private var frequencyPenalty: Double
    @State private var presencePenalty: Double
    @State private var repetitionPenalty: Double
    @State private var systemPrompt: String

    @State private var showSystemPromptEditor = false
    @State private var selectedPreset: InferencePreset?

    init() {
        // Initialize with placeholder values - actual values loaded in onAppear
        _temperature = State(initialValue: 0.7)
        _maxTokens = State(initialValue: 512)
        _topP = State(initialValue: 0.9)
        _contextLength = State(initialValue: 2048)
        _frequencyPenalty = State(initialValue: 0.0)
        _presencePenalty = State(initialValue: 0.0)
        _repetitionPenalty = State(initialValue: 1.0)
        _systemPrompt = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current Model Info
                currentModelSection

                // Presets
                presetsSection

                // Core Parameters
                coreParametersSection

                // Advanced Parameters
                advancedParametersSection

                // System Prompt
                systemPromptSection

                // Reset
                resetSection
            }
            .navigationTitle("Model Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applySettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
            .sheet(isPresented: $showSystemPromptEditor) {
                SystemPromptEditorSheet(prompt: $systemPrompt)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var currentModelSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: settings.selectedModel.iconName)
                    .font(.title2)
                    .foregroundStyle(.accent)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.selectedModel.displayName)
                        .font(.headline)

                    Text(settings.executionPathDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Privacy badge
                VStack(spacing: 2) {
                    Text(settings.privacyBadge.emoji)
                        .font(.title3)
                    Text(settings.mayTransmitData ? "Cloud" : "Local")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Active Model")
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(InferencePreset.allCases) { preset in
                        PresetCard(
                            preset: preset,
                            isSelected: selectedPreset == preset
                        ) {
                            applyPreset(preset)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        } header: {
            Text("Quick Presets")
        } footer: {
            Text("Presets adjust multiple parameters for common use cases. You can fine-tune individual values below.")
        }
    }

    @ViewBuilder
    private var coreParametersSection: some View {
        Section {
            // Temperature
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Temperature", systemImage: "thermometer")
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $temperature, in: 0 ... 2, step: 0.05) {
                    Text("Temperature")
                }

                Text("Lower = more focused, higher = more creative")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // Max Tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Max Tokens", systemImage: "textformat.123")
                    Spacer()
                    Text("\(maxTokens)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(maxTokens) },
                    set: { maxTokens = Int($0) }
                ), in: 64 ... 4096, step: 64) {
                    Text("Max Tokens")
                }

                Text("Maximum response length in tokens (~4 chars each)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // Top P
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Top P (Nucleus)", systemImage: "chart.bar")
                    Spacer()
                    Text(String(format: "%.2f", topP))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $topP, in: 0 ... 1, step: 0.05) {
                    Text("Top P")
                }

                Text("Probability mass to sample from (1.0 = all tokens)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Core Parameters")
        }
    }

    @ViewBuilder
    private var advancedParametersSection: some View {
        Section {
            // Context Length
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Context Length", systemImage: "text.alignleft")
                    Spacer()
                    Text("\(contextLength)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Picker("Context Length", selection: $contextLength) {
                    Text("1K").tag(1024)
                    Text("2K").tag(2048)
                    Text("4K").tag(4096)
                    Text("8K").tag(8192)
                    Text("16K").tag(16384)
                    Text("32K").tag(32768)
                }
                .pickerStyle(.segmented)

                Text("Maximum conversation context (model dependent)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Apple Foundation Models use a 4,096 token context window.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // Frequency Penalty
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Frequency Penalty", systemImage: "repeat")
                    Spacer()
                    Text(String(format: "%.2f", frequencyPenalty))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $frequencyPenalty, in: 0 ... 2, step: 0.1) {
                    Text("Frequency Penalty")
                }

                Text("Penalize frequently used tokens (reduces repetition)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // Presence Penalty
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Presence Penalty", systemImage: "plus.circle")
                    Spacer()
                    Text(String(format: "%.2f", presencePenalty))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $presencePenalty, in: 0 ... 2, step: 0.1) {
                    Text("Presence Penalty")
                }

                Text("Penalize any token that appeared before (encourages new topics)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // Repetition Penalty
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Repetition Penalty", systemImage: "arrow.2.circlepath")
                    Spacer()
                    Text(String(format: "%.2f", repetitionPenalty))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $repetitionPenalty, in: 1 ... 2, step: 0.05) {
                    Text("Repetition Penalty")
                }

                Text("Additional penalty for repeated sequences (1.0 = off)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Advanced Parameters")
        } footer: {
            Text("These parameters affect token sampling behavior. Defaults work well for most use cases.")
        }
    }

    @ViewBuilder
    private var systemPromptSection: some View {
        Section {
            Button {
                showSystemPromptEditor = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .foregroundStyle(.primary)
                        Text(systemPrompt.isEmpty ? "Default assistant behavior" : systemPrompt.prefix(50) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Define the model's personality and response style")
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                resetToDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: - Actions

    private func loadCurrentSettings() {
        temperature = settings.temperature
        maxTokens = settings.maxTokens
        topP = settings.topP
        contextLength = settings.contextLength
        frequencyPenalty = settings.frequencyPenalty
        presencePenalty = settings.presencePenalty
        repetitionPenalty = settings.repetitionPenalty
        systemPrompt = settings.systemPrompt
    }

    private func applySettings() {
        settings.temperature = temperature
        settings.maxTokens = maxTokens
        settings.topP = topP
        settings.contextLength = contextLength
        settings.frequencyPenalty = frequencyPenalty
        settings.presencePenalty = presencePenalty
        settings.repetitionPenalty = repetitionPenalty
        settings.systemPrompt = systemPrompt

        DSHaptics.success()
    }

    private func applyPreset(_ preset: InferencePreset) {
        selectedPreset = preset

        withAnimation(.spring(response: 0.3)) {
            switch preset {
            case .balanced:
                temperature = 0.7
                topP = 0.9
                maxTokens = 512
                frequencyPenalty = 0.0
                presencePenalty = 0.0
                repetitionPenalty = 1.0

            case .creative:
                temperature = 1.0
                topP = 0.95
                maxTokens = 1024
                frequencyPenalty = 0.3
                presencePenalty = 0.5
                repetitionPenalty = 1.0

            case .precise:
                temperature = 0.3
                topP = 0.85
                maxTokens = 512
                frequencyPenalty = 0.7
                presencePenalty = 0.0
                repetitionPenalty = 1.3

            case .concise:
                temperature = 0.5
                topP = 0.8
                maxTokens = 256
                frequencyPenalty = 0.5
                presencePenalty = 0.3
                repetitionPenalty = 1.2

            case .verbose:
                temperature = 0.8
                topP = 0.95
                maxTokens = 2048
                frequencyPenalty = 0.1
                presencePenalty = 0.0
                repetitionPenalty = 1.0
            }
        }

        DSHaptics.light()
    }

    private func resetToDefaults() {
        selectedPreset = .balanced
        applyPreset(.balanced)
        systemPrompt = "You are a helpful assistant."
    }
}

// MARK: - Inference Presets

enum InferencePreset: String, CaseIterable, Identifiable {
    case balanced = "Balanced"
    case creative = "Creative"
    case precise = "Precise"
    case concise = "Concise"
    case verbose = "Verbose"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .balanced: return "equal.circle"
        case .creative: return "paintpalette"
        case .precise: return "scope"
        case .concise: return "text.alignleft"
        case .verbose: return "text.justify"
        }
    }

    var description: String {
        switch self {
        case .balanced: return "Good for most tasks"
        case .creative: return "Story writing, brainstorming"
        case .precise: return "Technical, factual answers"
        case .concise: return "Short, direct responses"
        case .verbose: return "Detailed explanations"
        }
    }

    var color: Color {
        switch self {
        case .balanced: return .blue
        case .creative: return .purple
        case .precise: return .green
        case .concise: return .orange
        case .verbose: return .cyan
        }
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: InferencePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : preset.color)

                Text(preset.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(preset.description)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? preset.color : preset.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : preset.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System Prompt Editor

private struct SystemPromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var prompt: String

    @State private var localPrompt: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $localPrompt)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(DSColors.surface)

                // Quick templates
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SystemPromptTemplate.allCases) { template in
                            Button {
                                localPrompt = template.prompt
                            } label: {
                                Text(template.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(DSColors.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("System Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        prompt = localPrompt
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                localPrompt = prompt
            }
        }
    }
}

enum SystemPromptTemplate: String, CaseIterable, Identifiable {
    case assistant = "Assistant"
    case expert = "Expert"
    case teacher = "Teacher"
    case coder = "Coder"
    case concise = "Concise"

    var id: String { rawValue }

    var prompt: String {
        switch self {
        case .assistant:
            return "You are a helpful assistant."
        case .expert:
            return "You are an expert in the subject matter being discussed. Provide detailed, accurate, and well-reasoned responses."
        case .teacher:
            return "You are a patient and knowledgeable teacher. Explain concepts clearly with examples, and check for understanding."
        case .coder:
            return "You are an experienced software developer. Provide clean, well-documented code with explanations. Follow best practices and consider edge cases."
        case .concise:
            return "Be concise. Give direct answers without unnecessary elaboration. Use bullet points when appropriate."
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        ModelConfigurationSheet()
            .environmentObject(SettingsStore(ragService: RAGService()))
    }
#endif
