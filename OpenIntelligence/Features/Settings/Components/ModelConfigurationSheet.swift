//
//  ModelConfigurationSheet.swift
//  OpenIntelligence
//
//  The model parameters that change a Standard answer, plus Adaptive Profiles and the reasoning profile.
//  Since 5.8 (2026-11-18) it holds only controls something reads: the presets, Reset to Defaults, the three
//  penalties, the System Prompt and Max Tokens were removed, and the Context Length picker became a read-only line.
//

import SwiftUI

struct ModelConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var temperature: Double
    @State private var topP: Double
    @State private var topK: Int
    @State private var samplingStrategy: SamplingStrategy
    @State private var useFixedSeed: Bool
    @State private var seedValue: Int

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
        _temperature = State(initialValue: 0.4)
        _topP = State(initialValue: 0.9)
        _topK = State(initialValue: 40)
        _samplingStrategy = State(initialValue: .topK)
        _useFixedSeed = State(initialValue: false)
        _seedValue = State(initialValue: 42)
    }

    var body: some View {
        NavigationStack {
            // Cards on the page like every other Settings page (2026-11-16). This was a stock `Form` with large grey
            // section headers, a lock emoji for the privacy badge, a "123" glyph beside Max Tokens and a presets row
            // cut off at the right edge. Every control, value and stored key is the one it was, and Cancel and Apply
            // still stage the values until Apply.
            //
            // 5.8 (2026-11-18): Quick Presets, Reset to Defaults, the three penalties, the System Prompt and Max
            // Tokens are gone, because nothing they set reached an answer. Deep Think and Maximum build their own
            // `InferenceConfig` per call (`RAGService+Agentic.swift:109`, `:184`); Standard replaces the system prompt
            // before every answer (`RAGService+QueryAnswer.swift:574`, `:586`); Apple's `GenerationOptions` has no
            // penalty field, and their only reader (`LocalOpenAIServerLLMService.swift`) is `#if false`; continuations
            // size to the window, so Max Tokens never bounded an answer's length. The stored keys stay in
            // `SettingsStore`, so saved values load as they did.
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    currentModelSection
                    adaptiveProfilesSection
                    customReasoningSection
                    coreParametersSection
                    samplingSection
                    contextSection
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
    private var adaptiveProfilesSection: some View {
        parameterCard(
            icon: "wand.and.stars", title: "Adaptive Profiles",
            footer: adaptiveProfiles
                ? "Temperature and length are chosen per question and override the temperature below. Deep Think and Maximum use the temperature but keep their own per-step lengths. Your saved settings are not changed, and turning this off restores them immediately."
                : "Off. Every question uses the values below. Turn this on to let the app pick a temperature and length from what the question is asking for, so an open comparison gets room to work."
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
        // in the mode someone happens to be using is the failure the penalty sliders (removed in 5.8)
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
            footer: "Used by Standard answers. Deep Think and Maximum choose their own for each step."
        ) {
            // Temperature
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                valueHeader("Temperature", icon: "thermometer", value: String(format: "%.2f", temperature))

                // 0 to 0.4 since 5.8: Standard caps its temperature at 0.4, or 0.2 for Evidence-First and High
                // Precision (`RAGService+QueryAnswer.swift:597`, `:602`, `:607`), so the old 0.4 to 2 did nothing.
                Slider(value: $temperature, in: 0...0.4, step: 0.05) {
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
                        : "Standard answers only, up to 0.4. Deep Think and Maximum set their own."
                )
            }
            .opacity(samplingStrategy == .greedy ? 0.55 : 1)
            .animation(DSAnimations.fastEase, value: samplingStrategy)
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
            footer: "How the model chooses each next word. Apple's API takes one strategy at a time, so picking one replaces the other two. Standard answers only. Deep Think and Maximum use their own sampling."
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

            // The shortlist sliders are for development builds only (5.8). The strategy picker above is what changes
            // an answer for most people, and a saved Top-K or Top-P still reaches Standard answers in every build.
            #if DEBUG
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
            #endif

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
                        ? "Fixes the model's word choices for Standard answers. The passages found can still differ between runs."
                        : "Answers vary slightly between runs."
                )
            }
        }
    }

    /// Hidden where the device reports no window (`reportedOnDeviceContextSize` is nil when the model is unavailable),
    /// rather than showing the 4,096 fallback as if the model had said it.
    @ViewBuilder
    private var contextSection: some View {
        if let window = FoundationModelTokenBudget.reportedOnDeviceContextSize {
            parameterCard(
                icon: "text.alignleft", title: "Context",
                footer: "Set by Apple's model on this device, not here."
            ) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    valueHeader("Context window", icon: "text.alignleft", value: "\(window.formatted()) tokens")
                    // Read only since 2026-11-18. The old 1K to 32K picker stored `llmContextLength`, which no answer
                    // path reads for Apple's models: `RAGService+QueryPipeline` sizes the prompt from
                    // `FoundationModelTokenBudget.contextSize` (the window the device's model reports) and reads the
                    // setting only for a non-Apple service, which the app no longer has. The owner's iPhone showed
                    // "4K" here while its model reported 8,192.
                    note(contextGuidance(window: window))
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCurrentSettings() {
        // Shown within the slider's 0 to 0.4; Standard applied no more than 0.4 to a higher saved value anyway.
        temperature = min(max(settings.temperature, 0), 0.4)
        topP = settings.topP
        samplingStrategy = settings.samplingStrategy
        topK = settings.topK
        useFixedSeed = settings.seed != nil
        seedValue = settings.seed.map { Int($0 % 10000) } ?? 42
    }

    /// Says what the device's window means for an answer.
    private func contextGuidance(window: Int) -> String {
        let model = FoundationModelTokenBudget.reportedOnDeviceModelName.map { "\($0) reports" } ?? "Apple's model reports"
        return "\(model) \(window.formatted()) tokens on this device, and the app uses all of it for your "
            + "question, the passages it found and the answer. Private Cloud Compute has its own, larger window."
    }

    private func applySettings() {
        settings.temperature = temperature
        settings.topP = topP
        settings.samplingStrategy = samplingStrategy
        settings.topK = topK
        settings.seed = useFixedSeed ? UInt64(seedValue) : nil

        DSHaptics.success()
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        ModelConfigurationSheet()
            .environmentObject(SettingsStore(ragService: RAGService()))
    }
#endif
