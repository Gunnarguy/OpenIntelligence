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
    @State private var topK: Int
    @State private var samplingStrategy: SamplingStrategy
    @State private var useFixedSeed: Bool
    @State private var seedValue: Int
    @State private var contextLength: Int
    @State private var frequencyPenalty: Double
    @State private var presencePenalty: Double
    @State private var repetitionPenalty: Double
    @State private var systemPrompt: String

    @State private var showSystemPromptEditor = false
    @State private var selectedPreset: InferencePreset?

    /// Read by `RAGService` straight from `UserDefaults` under this key, so the toggle and the
    /// pipeline cannot drift apart through an intermediate copy. Absent means false, which is
    /// what makes this off for every existing install.
    @AppStorage("adaptiveInferenceProfiles") private var adaptiveProfiles = false

    /// Read by `AppleFoundationModelRoute.reasoningLevel` straight from `UserDefaults` under this
    /// key, so the field and the route cannot drift apart through an intermediate copy. Empty means
    /// "use Apple's named levels", which is what every existing install has.
    @AppStorage("customReasoningProfile") private var customReasoningProfile = ""

    init() {
        // Initialize with placeholder values - actual values loaded in onAppear
        _temperature = State(initialValue: 0.7)
        _maxTokens = State(initialValue: 512)
        _topP = State(initialValue: 0.9)
        _topK = State(initialValue: 40)
        _samplingStrategy = State(initialValue: .topK)
        _useFixedSeed = State(initialValue: false)
        _seedValue = State(initialValue: 42)
        _contextLength = State(initialValue: 2048)
        _frequencyPenalty = State(initialValue: 0.0)
        _presencePenalty = State(initialValue: 0.0)
        _repetitionPenalty = State(initialValue: 1.0)
        _systemPrompt = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            // Cards on the page like every other Settings page (2026-11-16). This was a stock `Form` with large grey
            // section headers, a lock emoji for the privacy badge, a "123" glyph beside Max Tokens and a presets row
            // cut off at the right edge. Every control, value and stored key is the one it was, and Cancel and Apply
            // still stage the values until Apply.
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    currentModelSection
                    presetsSection
                    adaptiveProfilesSection
                    customReasoningSection
                    coreParametersSection
                    samplingSection
                    contextSection
                    penaltiesSection
                    systemPromptSection
                    resetSection
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DSColors.background.ignoresSafeArea())
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
        .macSheetFrame(width: 600, height: 760)
    }

    // MARK: - Sections

    /// One card: a `SectionHeader`, the controls, and the footnote that was the `Form` section's footer.
    private func parameterCard<Content: View>(
        icon: String, title: String, footer: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        SurfaceCard {
            SectionHeader(icon: icon, title: title)
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A slider's name, its value on the right, and the line under it, in the size every Settings page uses.
    private func valueHeader(_ name: String, icon: String, value: String) -> some View {
        HStack {
            Label(name, systemImage: icon)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DSColors.secondaryText)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var currentModelSection: some View {
        parameterCard(icon: "cpu", title: "Active Model") {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: settings.selectedModel.iconName)
                    .font(.title3)
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(settings.selectedModel.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(settings.executionPathDescription)
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Where it runs, as a symbol and a word (`privacyBadge.emoji` was a lock or cloud emoji).
                Label(settings.mayTransmitData ? "Cloud" : "Local", systemImage: settings.mayTransmitData ? "cloud" : "lock")
                    .chipStyle(tint: settings.mayTransmitData ? .accentColor : .green)
            }
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        parameterCard(
            icon: "square.grid.2x2", title: "Quick Presets",
            footer: "Presets adjust multiple parameters for common use cases. You can fine-tune individual values below."
        ) {
            // A grid that wraps, so no preset sits past the card's edge (it was a sideways scroll, cut off).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DSSpacing.sm)], spacing: DSSpacing.sm) {
                ForEach(InferencePreset.allCases) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset
                    ) {
                        applyPreset(preset)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var adaptiveProfilesSection: some View {
        parameterCard(
            icon: "wand.and.stars", title: "Adaptive Profiles",
            footer: adaptiveProfiles
                ? "Temperature and length are chosen per question and override the values below. Deep Think and Maximum use the temperature but keep their own per-step lengths. Your saved settings are not changed, and turning this off restores them immediately."
                : "Off. Every question uses the values below. Turn this on to let the app pick a temperature and length from what the question is asking for, so a value lookup answers the same way twice and an open comparison gets room to work."
        ) {
            Toggle(isOn: $adaptiveProfiles) {
                Text("Adapt to the question")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.accentColor)
            if adaptiveProfiles {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    profileRow("Looking up a value, or a calculation", "0.10", "400")
                    profileRow("Following a procedure, or reporting findings", "0.30", "900")
                    profileRow("Comparing or investigating", "0.35", "1400")
                    profileRow("Summarizing", "0.40", "1000")
                }
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var customReasoningSection: some View {
        // Says where it does and does not apply, because a setting that silently does nothing
        // in the mode someone happens to be using is the failure the penalty sliders already
        // demonstrated on this same screen.
        // Two different things are called reasoning and conflating them produced a footer
        // saying this app does not reason on device, which is the opposite of what it does.
        // Deep Think and Maximum run their own multi-session reasoning and four of those call
        // sites pass `forceOnDevice: true`. What is PCC-only is Apple's *model-internal*
        // reasoning setting, which is the thing this field writes.
        parameterCard(
            icon: "brain", title: "Your Own Reasoning Profile",
            footer: "Apple's model has a reasoning setting with three fixed levels, or a description you "
                + "write yourself. Write one here and it replaces the level: for example, "
                + "\"work backwards from the conclusion and say which step is weakest\", or "
                + "\"check every number against the source before using it\".\n\n"
                + "This is separate from the app's own reasoning. Deep Think and Maximum think "
                + "across many steps on this device, and that is unaffected by what you write here. "
                + "What this changes is how hard Apple's model works inside a single answer, which "
                + "Apple only allows on Private Cloud Compute, so it applies to answers written "
                + "there and not to ones written on the device."
        ) {
            TextField(
                "How should it think through a problem?",
                text: $customReasoningProfile,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
            .font(.subheadline)

            if !customReasoningProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Clear", role: .destructive) {
                    customReasoningProfile = ""
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ name: String, _ temperature: String, _ tokens: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(temperature) · \(tokens) tok").monospacedDigit()
        }
    }

    @ViewBuilder
    private var coreParametersSection: some View {
        parameterCard(
            icon: "slider.horizontal.3", title: "Core Parameters",
            footer: "Both reach Apple Intelligence directly, on this device and on Private Cloud Compute."
        ) {
            // Temperature
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Temperature", icon: "thermometer", value: String(format: "%.2f", temperature))

                Slider(value: $temperature, in: 0...2, step: 0.05) {
                    Text("Temperature")
                }
                .disabled(samplingStrategy == .greedy)

                // Greedy always takes the single highest-probability token, so
                // temperature has no effect on it at all. Every other parameter on this
                // sheet is already gated on the strategy it belongs to — Top-K, Top-P and
                // the seed each appear only where they apply — and temperature was the
                // one that was not, so it stayed live and adjustable while doing nothing.
                // Dimmed rather than hidden: it is a Core Parameter, and a control that
                // vanishes is harder to understand than one that explains itself.
                note(
                    samplingStrategy == .greedy
                        ? "No effect on Predictable sampling, which always takes the most likely next word. Choose Balanced or Adaptive below to use this."
                        : "Lower = more focused, higher = more creative"
                )
            }
            .opacity(samplingStrategy == .greedy ? 0.55 : 1)
            .animation(DSAnimations.fastEase, value: samplingStrategy)

            Divider()

            // Max Tokens
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Max Tokens", icon: "text.alignleft", value: "\(maxTokens)")

                Slider(
                    value: Binding(
                        get: { Double(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 64...4096, step: 64
                ) {
                    Text("Max Tokens")
                }

                note("Maximum response length in tokens (~4 chars each)")
            }
        }
    }

    // Sampling used to be inferred rather than chosen: `LLMService` took top-K
    // whenever it was in (0,100), and every chat query passed a hardcoded 40, so the
    // Top-P slider below was read, threaded through `InferenceConfig`, and discarded.
    // `greedy` was unreachable for the same reason. The three modes are alternatives
    // in Apple's API, so they are a picker rather than three independent sliders.
    @ViewBuilder
    private var samplingSection: some View {
        parameterCard(
            icon: "dice", title: "Sampling",
            footer: "How the model chooses each next word. Apple's API takes one strategy at a time, so picking one replaces the other two."
        ) {
            Picker("Strategy", selection: $samplingStrategy) {
                ForEach(SamplingStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(samplingStrategy.technicalName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
                note(samplingStrategy.explanation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if samplingStrategy == .topK {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    valueHeader("Top-K", icon: "list.number", value: "\(topK)")
                    Slider(
                        value: Binding(get: { Double(topK) }, set: { topK = Int($0) }),
                        in: 1...100,
                        step: 1
                    ) { Text("Top-K") }
                    note("Choose from the \(topK) most likely next words.")
                }
            }

            if samplingStrategy == .topP {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    valueHeader("Top-P (Nucleus)", icon: "chart.bar", value: String(format: "%.2f", topP))
                    Slider(value: $topP, in: 0.05...0.99, step: 0.05) { Text("Top-P") }
                    note("Probability mass to sample from. Lower is more focused.")
                }
            }

            // Apple accepts a seed on both random modes and the app never sent one, so
            // the same question could not reproduce the same answer. Greedy is already
            // deterministic, so the control is meaningless there and is hidden.
            if samplingStrategy != .greedy {
                Divider()
                Toggle(isOn: $useFixedSeed) {
                    Label("Reproducible answers", systemImage: "lock.rotation")
                        .font(.subheadline.weight(.medium))
                }
                .tint(.accentColor)
                if useFixedSeed {
                    Stepper(value: $seedValue, in: 0...9999) {
                        HStack {
                            Text("Seed")
                                .font(.subheadline)
                            Spacer()
                            Text("\(seedValue)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }
                note(
                    useFixedSeed
                        ? "The same question against the same library returns the same answer."
                        : "Answers vary slightly between runs."
                )
            }
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        parameterCard(
            icon: "text.alignleft", title: "Context",
            footer: "How much conversation the model is given to work with."
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Context Length", icon: "text.alignleft", value: "\(contextLength)")

                Picker("Context Length", selection: $contextLength) {
                    Text("1K").tag(1024)
                    Text("2K").tag(2048)
                    Text("4K").tag(4096)
                    Text("8K").tag(8192)
                    Text("16K").tag(16384)
                    Text("32K").tag(32768)
                }
                .pickerStyle(.segmented)

                // The old caption hardcoded "Apple Foundation Models use a 4,096 token
                // context window", which is the fallback rather than the truth: the real
                // figure comes from `SystemLanguageModel.default.contextSize` and Private
                // Cloud Compute reports a larger one. More importantly, the picker offers
                // sizes far above what this device can accept, and choosing one is not
                // free — the context budget is what the packing stage fills, so setting
                // 32K on a 4K device builds a prompt the model then rejects. That is the
                // shape of the "4521 tokens against a 4096 window" report.
                note("How much conversation and document context to pack into each request.")
                Text(contextGuidance)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(contextLength > onDeviceContextWindow ? DSColors.readable(.orange) : DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // The three sliders below are split into their own card on purpose.
    //
    // They do not affect Apple Intelligence, and the previous single-section
    // footer ("These parameters affect token sampling behavior") said they did.
    // `GenerationOptions` in the iOS 27 SDK exposes exactly `sampling`/
    // `samplingMode`, `temperature`, `maximumResponseTokens` and `toolCallingMode`
    // — the string "penalty" does not occur anywhere in the FoundationModels
    // interface. So on-device and Private Cloud Compute answers ignore all three.
    //
    // They are NOT deleted, because their only consumer,
    // `LocalOpenAIServerLLMService`, is scaffolding for the roadmap row "Bring-
    // your-own local model on Mac (third-party model host)", which targets v5.0.
    // Zero call sites is what an open roadmap row means; deleting the controls
    // would delete a planned feature's UI. `repetitionPenalty` reaches nothing at
    // all even there, and is marked as such rather than removed.
    //
    // The previous footer said these "affect token sampling behavior", which is false
    // for every model this app can currently run. Saying so plainly costs one sentence
    // and is cheaper than the controls.
    @ViewBuilder
    private var penaltiesSection: some View {
        parameterCard(
            icon: "repeat", title: "Advanced Parameters",
            footer: "Apple Intelligence ignores all three. Apple's generation API takes a sampling "
                + "mode, a temperature and a response length, and has no penalty setting of any "
                + "kind, so these change nothing on this device or on Private Cloud Compute. "
                + "They are here for a local model host on Mac, which is not built yet."
        ) {
            // Frequency Penalty
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Frequency Penalty", icon: "repeat", value: String(format: "%.2f", frequencyPenalty))
                Slider(value: $frequencyPenalty, in: 0...2, step: 0.1) {
                    Text("Frequency Penalty")
                }
                note("Penalize frequently used tokens (reduces repetition)")
            }

            Divider()

            // Presence Penalty
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Presence Penalty", icon: "plus.circle", value: String(format: "%.2f", presencePenalty))
                Slider(value: $presencePenalty, in: 0...2, step: 0.1) {
                    Text("Presence Penalty")
                }
                note("Penalize any token that appeared before (encourages new topics)")
            }

            Divider()

            // Repetition Penalty
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader(
                    "Repetition Penalty", icon: "arrow.2.circlepath", value: String(format: "%.2f", repetitionPenalty))
                Slider(value: $repetitionPenalty, in: 1...2, step: 0.05) {
                    Text("Repetition Penalty")
                }
                // Marked rather than removed, per the comment above: unlike the other
                // two, this one is not read even by `LocalOpenAIServerLLMService`, so it would
                // still do nothing on the day the local model host ships.
                note(
                    "Additional penalty for repeated sequences (1.0 = off). Not sent anywhere, including to the planned local model host."
                )
            }
        }
    }

    @ViewBuilder
    private var systemPromptSection: some View {
        parameterCard(
            icon: "text.quote", title: "Behavior", footer: "Define the model's personality and response style"
        ) {
            Button {
                showSystemPromptEditor = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("System Prompt")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        // One line, cut by the system where it has to be; it added "..." to every prompt, even
                        // one shorter than the 50 characters it kept.
                        Text(systemPrompt.isEmpty ? "Default assistant behavior" : systemPrompt)
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Button(role: .destructive) {
            resetToDefaults()
        } label: {
            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Actions

    private func loadCurrentSettings() {
        temperature = settings.temperature
        maxTokens = settings.maxTokens
        topP = settings.topP
        samplingStrategy = settings.samplingStrategy
        topK = settings.topK
        useFixedSeed = settings.seed != nil
        seedValue = settings.seed.map { Int($0 % 10000) } ?? 42
        contextLength = settings.contextLength
        frequencyPenalty = settings.frequencyPenalty
        presencePenalty = settings.presencePenalty
        repetitionPenalty = settings.repetitionPenalty
        systemPrompt = settings.systemPrompt
    }

    /// The real on-device context window, not the historical 4,096 fallback.
    private var onDeviceContextWindow: Int {
        FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
    }

    /// Says what the chosen context size actually means on this device.
    ///
    /// Answers the reasonable question "can I just max these out?" with a no: the context
    /// budget is what the packing stage fills, so a size above the device's window
    /// produces a prompt the model rejects. Above the window the app must escalate to
    /// Private Cloud Compute, which is a routing consequence rather than a free upgrade.
    private var contextGuidance: String {
        let window = onDeviceContextWindow
        if contextLength <= window {
            return "Fits on this device (\(window.formatted()) tokens on-device)."
        }
        return
            "Above this device's \(window.formatted())-token window. Requests this large can only run on Private Cloud Compute, and will fail if it is unavailable or you have chosen On-Device."
    }

    private func applySettings() {
        settings.temperature = temperature
        settings.maxTokens = maxTokens
        settings.topP = topP
        settings.samplingStrategy = samplingStrategy
        settings.topK = topK
        settings.seed = useFixedSeed ? UInt64(seedValue) : nil
        settings.contextLength = contextLength
        settings.frequencyPenalty = frequencyPenalty
        settings.presencePenalty = presencePenalty
        settings.repetitionPenalty = repetitionPenalty
        settings.systemPrompt = systemPrompt

        DSHaptics.success()
    }

    private func applyPreset(_ preset: InferencePreset) {
        selectedPreset = preset

        withAnimation(DSAnimations.snappySpring) {
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
        DSColors.accent
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: InferencePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? preset.color : .secondary)

                Text(preset.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(isSelected ? preset.color.opacity(0.15) : DSColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(isSelected ? preset.color : DSColors.border, lineWidth: 1)
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
                    .padding(DSSpacing.lg)
                    .scrollContentBackground(.hidden)
                    .background(DSColors.surface)

                // Quick templates
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(SystemPromptTemplate.allCases) { template in
                            Button {
                                localPrompt = template.prompt
                            } label: {
                                Text(template.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.xs)
                                    .background(DSColors.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DSSpacing.lg)
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
            return
                "You are an expert in the subject matter being discussed. Provide detailed, accurate, and well-reasoned responses."
        case .teacher:
            return
                "You are a calm and knowledgeable teacher. Explain concepts clearly with examples, and check for understanding."
        case .coder:
            return
                "You are an experienced software developer. Provide clean, well-documented code with explanations. Follow best practices and consider edge cases."
        case .concise:
            return
                "Be concise. Give direct answers without unnecessary elaboration. Use bullet points when appropriate."
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
