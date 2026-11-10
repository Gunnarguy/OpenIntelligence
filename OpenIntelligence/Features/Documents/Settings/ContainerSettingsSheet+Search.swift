//
//  ContainerSettingsSheet+Search.swift
//  OpenIntelligence
//
//  Part of ContainerSettingsSheet, moved from ContainerSettingsSheet+Sections.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import NaturalLanguage
import SwiftUI

extension ContainerSettingsSheet {
    // MARK: - Search Section (5.7)

    /// The library's search settings: a style, and the Advanced Controls under it. Each control changes the
    /// search as its text says; the minimum score acts on Standard answers and Find Passages, Passages Needed on
    /// Standard answers, the other two in every mode (`RetrievalStyle`, `RetrievalPolicyService`). Through 5.6 the styles were not shown and
    /// the controls sat behind a developer switch that was always off.
    @ViewBuilder
    var searchSection: some View {
        Section {
            Text("How this library finds the passages an answer is written from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tour(.searchStyle, in: Tour.librarySettings)

            VStack(spacing: DSSpacing.sm) {
                // Automatic reads only the file types (`RetrievalConfig.recommended(forDocumentTypes:)`, called from
                // `autoTuneRetrievalConfigIfNeeded` after an import), not the text.
                retrievalStyleCard(
                    style: .automatic,
                    icon: "wand.and.stars",
                    title: "Automatic",
                    subtitle: "Chosen from this library's file types after each import",
                    isSelected: retrievalConfig.style == .automatic
                )
                retrievalStyleCard(
                    style: .balanced,
                    icon: "scale.3d",
                    title: "Balanced",
                    subtitle: "Exact words and meaning weighed evenly",
                    isSelected: retrievalConfig.style == .balanced
                )
                retrievalStyleCard(
                    style: .precise,
                    icon: "target",
                    title: "High Precision",
                    subtitle: "A Standard answer needs two passages at or over the minimum",
                    isSelected: retrievalConfig.style == .precise
                )
                retrievalStyleCard(
                    style: .technical,
                    icon: "wrench.and.screwdriver",
                    title: "Technical Manual",
                    subtitle: "Leans on exact words, for specs and part numbers",
                    isSelected: retrievalConfig.style == .technical
                )
                retrievalStyleCard(
                    style: .exploratory,
                    icon: "binoculars",
                    title: "Exploratory",
                    subtitle: "Leans on meaning, with more varied passages",
                    isSelected: retrievalConfig.style == .exploratory
                )
            }

            if retrievalConfig.style == .automatic {
                // `RetrievalConfig.recommended(forDocumentTypes:)`: code files (its list includes HTML, CSS, JSON, XML,
                // YAML, SQL and shell) more than half, or CSV, Excel and Numbers files at least 2 and at least two-thirds,
                // give Technical Manual; every other library gets Balanced (`.default`).
                Text(
                    "Automatic picks Technical Manual when more than half of the library's files are code (HTML, JSON and XML count), or when two or more are spreadsheets and they make up at least two-thirds of it. Every other library gets Balanced. It's on \(retrievalConfig.summary == "Custom" ? "custom values" : retrievalConfig.summary) now."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if retrievalConfig.style == nil {
                Label("Custom: set in Advanced Controls", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            // Every retrieval benchmark on record ran on libraries the harness made, which start on `RetrievalConfig.default`
            // (KnowledgeContainer init) and keep it after tuning, since their files are PDFs and text: QASPER and the
            // table set in BenchmarkRuns/2026-11-10-rule-audit (iOS 27 Simulator) and the golden sets before it. Nothing in
            // the harness or the tests sets `.highAccuracy`, `.technicalManual` or `.exploratory`.
            // [evidence_level: code_verified, confidence: medium, evidence_source: grep of OpenIntelligence and BenchmarkRuns, 2026-11-10]
            Text(
                "Search has been benchmarked only with Balanced, which Automatic uses for PDF and text libraries. The other styles, and values changed in Advanced Controls, change how search ranks passages and haven't been benchmarked."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            DisclosureGroup("Advanced Controls") {
                advancedSearchControls
            }
        } header: {
            Text("Search")
        } footer: {
            Text(
                "Apple's model is asked to cite its passages in every answer, so citations have no setting here. Changing a control here makes the library keep your settings instead of Automatic's."
            )
        }
    }

    @ViewBuilder
    private func retrievalStyleCard(
        style: RetrievalStyle,
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        Button {
            Tour.used(.searchStyle)
            withAnimation(DSAnimations.snappySpring) {
                retrievalConfig = .chosen(style, documentTypes: activeContainerDocuments.map(\.contentType))
            }
            DSHaptics.selection()
        } label: {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .scaledFont(size: 16, weight: .medium)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let values = presetValues(style) {
                        Text(values)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A chosen style's values, read from its preset (`RetrievalStyle.preset`, the `RetrievalConfig` presets in
    /// KnowledgeContainer.swift) so the row can never disagree with what it sets. Automatic has none of its own.
    /// A meaning weight over 65% is searched as 65% and the words weight as 35%: `QueryProfile.adjustedHybridWeights`
    /// keeps each between 35% and 65% after a shift of at most 10 points, and the slider moves in steps of 5, so
    /// anything over 65% is 70% or more and lands on 65% for every kind of question.
    private func presetValues(_ style: RetrievalStyle) -> String? {
        guard let preset = style.preset else { return nil }
        var parts = ["Minimum \(percent(preset.minSimilarity))"]
        var weights = "words \(percent(preset.lexicalWeight)) / meaning \(percent(preset.vectorWeight))"
        if preset.vectorWeight > 0.65 {
            weights += " (searched as 35% / 65%)"
        }
        parts.append(weights)
        if preset.minConfidentChunks >= 2 {
            parts.append("\(preset.minConfidentChunks) passages needed")
        }
        parts.append("variety \(String(format: "%.2f", preset.mmrLambda))")
        return parts.joined(separator: ", ")
    }

    // MARK: - Advanced Controls

    /// A binding into the library's search settings that marks them as the person's own when it changes one. The
    /// value is rounded to `step`, and a write that changes nothing (a control showing its value) marks nothing, so
    /// opening Advanced Controls never turns Automatic off.
    private func chosenSetting(_ keyPath: WritableKeyPath<RetrievalConfig, Float>, step: Float = 0.05) -> Binding<Float>
    {
        Binding(
            get: { retrievalConfig[keyPath: keyPath] },
            set: { newValue in
                let rounded = (newValue / step).rounded() * step
                guard abs(rounded - retrievalConfig[keyPath: keyPath]) >= 0.001 else { return }
                retrievalConfig[keyPath: keyPath] = rounded
                retrievalConfig.isChosenByPerson = true
            }
        )
    }

    private func chosenCount(_ keyPath: WritableKeyPath<RetrievalConfig, Int>) -> Binding<Int> {
        Binding(
            get: { retrievalConfig[keyPath: keyPath] },
            set: { newValue in
                guard newValue != retrievalConfig[keyPath: keyPath] else { return }
                retrievalConfig[keyPath: keyPath] = newValue
                retrievalConfig.isChosenByPerson = true
            }
        )
    }

    /// The weight given to meaning, with the weight given to exact words as the rest. The search shifts both for
    /// each question and keeps each between 35% and 65% (`QueryProfile.adjustedHybridWeights`).
    private var meaningWeight: Binding<Float> {
        Binding(
            get: { retrievalConfig.vectorWeight },
            set: { newValue in
                let rounded = (newValue * 20).rounded() / 20
                guard abs(rounded - retrievalConfig.vectorWeight) >= 0.001 else { return }
                retrievalConfig.vectorWeight = rounded
                retrievalConfig.lexicalWeight = 1 - rounded
                retrievalConfig.isChosenByPerson = true
            }
        )
    }

    private func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    @ViewBuilder
    var advancedSearchControls: some View {
        // Minimum score
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Minimum Score")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(percent(retrievalConfig.minSimilarity))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: chosenSetting(\.minSimilarity), in: 0.15...0.70) {
                Text("Minimum Score")
            }
            .accessibilityValue("\(Int((retrievalConfig.minSimilarity * 100).rounded())) percent")
            Text(
                "The score a passage needs to be used in a Standard answer. Scores are relative: the app ranks the passages it finds for a question against each other, so a passage can score high when nothing matches well. When a question's best passages mostly score lower, or it asks for a single fact, the app lowers the minimum for that question so it can still answer. Find Passages in Shortcuts uses this minimum too."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if settings.showTechnicalDetails {
                Text(
                    "In a Standard answer it is compared with the re-ranker's score: the cross-encoder's scores for a question are rescaled to 10 to 90, then lowered for tables of contents, question banks and bibliographies. A step-by-step question uses a minimum of at least 25%. Find Passages compares it with the hybrid search's score, before re-ranking, and never lowers it. Deep Think and Maximum set their own minimum for each research step."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DSSpacing.xs)

        // Passages needed
        Stepper(value: chosenCount(\.minConfidentChunks), in: 1...5) {
            HStack {
                Text("Passages Needed")
                    .font(.subheadline)
                Spacer()
                Text("\(retrievalConfig.minConfidentChunks)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
        }
        Text(
            retrievalConfig.minConfidentChunks >= 2
                ? "A Standard answer is written only when at least \(retrievalConfig.minConfidentChunks) of its passages score at or over the minimum. Otherwise you get the closest passages and how many made it."
                : "At 1, the app answers from its best passages. Set 2 or more to answer only when that many score at or over the minimum."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        // Exact words and meaning
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Exact Words and Meaning")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(percent(retrievalConfig.vectorWeight)) meaning")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: meaningWeight, in: 0.35...0.75) {
                Text("Exact Words and Meaning")
            } minimumValueLabel: {
                Text("Words").font(.caption2)
            } maximumValueLabel: {
                Text("Meaning").font(.caption2)
            }
            .accessibilityValue("\(Int((retrievalConfig.vectorWeight * 100).rounded())) percent meaning")
            // The slider reaches 75%, but `QueryProfile.adjustedHybridWeights` keeps each weight between 35% and 65%, so
            // 70% and 75% search as 65% meaning and 35% words (see `presetValues`).
            Text(
                "Toward Words favors passages that use your exact terms. Toward Meaning favors passages that say the same thing in other words. Over 65% meaning searches the same as 65%: the search keeps each side between 35% and 65%. Used in every mode."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if settings.showTechnicalDetails {
                Text(
                    "The vector and BM25 weights of the hybrid search. Each question shifts them by up to 10 points by its kind, then each is kept between 35% and 65%."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DSSpacing.xs)

        // Variety
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Variety")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f", retrievalConfig.mmrLambda))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: chosenSetting(\.mmrLambda), in: 0.30...0.95) {
                Text("Variety")
            } minimumValueLabel: {
                Text("Varied").font(.caption2)
            } maximumValueLabel: {
                Text("Closest").font(.caption2)
            }
            .accessibilityValue(String(format: "%.2f", retrievalConfig.mmrLambda))
            Text(
                "Toward Varied, an answer draws on passages that say different things. Toward Closest, it keeps the closest passages even when they repeat each other. Used in every mode."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if settings.showTechnicalDetails {
                Text(
                    "Maximal Marginal Relevance λ. Step-by-step questions use at least 0.85 in Standard, so the steps stay together."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    // MARK: - Balanced Defaults Section

    @ViewBuilder
    var accuracyDefaultsSection: some View {
        Section(header: Text("Balanced defaults")) {
            // "persistent JSON storage" described a format this store no longer uses.
            // `VectorDBKind.persistentJSON` routes to `BNNSVectorDatabase`, which writes
            // `_meta.json` for chunk metadata alongside `_vectors.bin` and `_norms.bin`, memory
            // maps the vectors, and deletes the legacy single-JSON file after migrating it. The
            // metadata even stores `embedding: []`, because the numbers live in the binary. The
            // enum case name is the leftover; the wording no longer repeats it.
            // What `applyAccuracyDefaults` sets: the Core ML model (Neural Engine (MiniLM), 384), the on-disk store, and the
            // self-tuning switch, which picks a splitting style for each new file (`prescanChunkingPlan`). It was "the
            // recommended configuration", but a new library on a Mac with macOS 27 starts on Core AI
            // (`EmbeddingProviderDefaults.preferredSentenceProviderId`), and the button never touched the Search
            // settings, which have a style of the same name. A changed model makes Save ask to rebuild (`handleSave`).
            Text(
                "Sets the Neural Engine (MiniLM) embedding model (all-MiniLM-L6-v2, 384 dimensions), vectors stored on disk and memory mapped for search, and a splitting style picked for each new file. It doesn't change the Search settings."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Apply Balanced Defaults") {
                applyAccuracyDefaults()
            }
            .buttonStyle(.borderedProminent)

            Text(
                "You can still change any setting below. If the embedding model changes, Save asks before rebuilding this library's vectors."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func applyAccuracyDefaults() {
        providerId = "coreml_sentence_embedding"
        dim = 384
        dbKind = .persistentJSON
        autoAdaptDimension = true
    }

    @ViewBuilder
    var intelligenceSection: some View {
        if let report = activeIntelligenceReport {
            Section(header: Text("Auto Intelligence snapshot")) {
                AutoIntelligencePanel(
                    report: report,
                    libraryEmbedding: activeContainer.map {
                        (providerId: $0.embeddingProviderId, dimension: $0.embeddingDim)
                    },
                    isAutoEnabled: autoAdaptDimension,
                    onToggleAuto: {
                        autoAdaptDimension.toggle()
                    }
                )
            }
        } else if autoAdaptDimension {
            Section(header: Text("Auto Intelligence snapshot")) {
                SettingHelpCallout(
                    icon: "sparkles",
                    title: "Awaiting first ingest",
                    description:
                        "Drop a few documents into this library and the dynamic engine will profile everything, set chunking windows, and pick a splitting style for each new file.",
                    bullets: [
                        "New files get a style picked from their text. Rebuilding is always your choice",
                        "You'll get recommendations before anything hits the cloud (and only with your consent)",
                        "Pause auto mode anytime to freeze the current profile",
                    ],
                    accent: .accentColor
                )
            }
        }
    }

    @ViewBuilder
    var embeddingProviderSection: some View {
        // Both options load the bundled all-MiniLM-L6-v2 (`THIRD_PARTY_NOTICES.md`), 384 numbers a passage
        // (`supportedDimensions: [384]`), from the app bundle, so nothing here uses the network.
        Section(header: Text("Embedding model")) {
            Text(
                "The model that turns each passage and each question into numbers, so search can match meaning. Both options are the same all-MiniLM-L6-v2 model, 384 numbers a passage, and run on this device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            // The saved library's model, whatever the self-tuning switch says: the switch never changes it.
            if let library = activeContainer {
                libraryModelCard(providerId: library.embeddingProviderId, dimension: library.embeddingDim)
            }

            ForEach(embeddingProviderOptions) { option in
                SelectableOptionCard(
                    icon: option.icon,
                    title: option.title,
                    subtitle: option.tagline,
                    detail: option.detail,
                    isActive: providerId == option.id,
                    badgeText: option.badgeText,
                    isDisabled: !option.isSelectable,
                    metrics: option.metrics
                ) {
                    guard option.isSelectable else { return }
                    providerId = option.id
                }
            }

            // The retrieval benchmarks of 2026-11-09 and 2026-11-10 ran in the iOS 27 Simulator, where a new library starts
            // on the Core ML option (`preferredSentenceProviderId` is Core AI only on macOS 27). The Core AI model was
            // re-exported with mean pooling ("MiniLM-L6-v2/coreai-mlirb-meanpool"), and LEDGER.md still lists "Corrected
            // Core AI export" under "Open, not yet run". [evidence_level: code_verified, confidence: medium]
            Text(
                "The latest search benchmarks used Neural Engine (MiniLM). Core AI Sentence runs the same weights, and its search accuracy hasn't been benchmarked in its current form."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !providerAlerts.isEmpty {
                VStack(spacing: DSSpacing.sm) {
                    ForEach(providerAlerts) { alert in
                        SettingHelpCallout(
                            icon: alert.icon,
                            title: alert.title,
                            description: alert.description,
                            bullets: alert.bullets,
                            accent: alert.accent
                        )
                    }
                }
                .padding(.top, DSSpacing.xs)
            }
        }
    }

    /// The model this library uses and how it got it. Until 2026-11-10 this card was "Smart Embedding Selection" with an
    /// "N% match" and the analysis's reasons joined by semicolons. That percentage is a heuristic score halved
    /// (`AdaptiveEmbeddingOptimizer.recommendConfiguration`: fixed points for vocabulary, jargon, code, math and size,
    /// `confidence = min(1, score / 2)`), not a measured match, and the model it named is never applied: the only
    /// path that applies it (`evaluateEmbeddingShift` through `resolveAutoAdjustments`) runs behind
    /// `IngestionContext.allowsSelfTuningScheduling`, false for every import, and no refresh passes
    /// `allowSelfTuningScheduling: true`. It could name Apple Natural Language at 512 or an Apple Foundation Model at
    /// 1024, which no library here uses. What does set the model: `EmbeddingProviderDefaults.preferredSentenceProviderId`
    /// for a new library, the person's pick below, and the fallback when a model can't run on the device
    /// (`RAGService+Import` and `+Storage` reconcile to `actualProviderId` and clear the vectors).
    /// [evidence_level: code_verified, confidence: high, evidence_source: read 2026-11-10]
    @ViewBuilder
    private func libraryModelCard(providerId libraryProviderId: String, dimension: Int) -> some View {
        let isMiniLM = EmbeddingProviderDefaults.areCopiesOfOneModel(
            libraryProviderId, EmbeddingProviderDefaults.coreML)
        let startsOn =
            EmbeddingProviderDefaults.preferredSentenceProviderId == EmbeddingProviderDefaults.coreAI
            ? "Core AI Sentence" : "Neural Engine (MiniLM)"
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("This Library's Model")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            Text(
                "This library uses \(libraryModelName(libraryProviderId))\(isMiniLM ? ", all-MiniLM-L6-v2," : "") with \(dimension) numbers a passage. A new library on this device starts on \(startsOn). The library analysis never changes the model. It changes only when you pick another below, when you apply Balanced Defaults, or when the one chosen can't run on this device, and a new model means rebuilding the library's vectors."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text("\(dimension) dimensions")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.accentColor)

                if libraryProviderId == "apple_fm_embed" {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "cloud")
                            .font(.caption2)
                        Text("Cloud")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                } else {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "iphone")
                            .font(.caption2)
                        Text("On-Device")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    /// The option names the cards below use, so the card and the list say the same thing.
    private func libraryModelName(_ id: String) -> String {
        switch id {
        case EmbeddingProviderDefaults.coreML: return "Neural Engine (MiniLM)"
        case EmbeddingProviderDefaults.coreAI: return "Core AI Sentence"
        case "nl_contextual_embedding": return "Contextual Embeddings"
        case "apple_fm_embed": return "Apple Foundation Model"
        default: return "Apple Natural Language"
        }
    }

    @ViewBuilder
    var embeddingResolutionSection: some View {
        Section(header: Text("Vector dimension")) {
            embeddingResolutionContent
        }
    }

    @ViewBuilder
    private var embeddingResolutionContent: some View {
        Text(
            "Dimension is fixed by the embedding model (384D for MiniLM-L6-v2). Higher dims = richer semantics, more storage (4 bytes × dim per chunk)."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Picker("Dimension", selection: $dim) {
            ForEach(availableDimensionOptions, id: \.value) { option in
                Text("\(option.value)").tag(option.value)
            }
        }
        .pickerStyle(.menu)

        autoAdaptToggle
        dimensionDetailCard
        reembedWarnings
    }

    @ViewBuilder
    private var autoAdaptToggle: some View {
        Toggle(isOn: $autoAdaptDimension) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Dynamic self-tuning library")
                if autoAdaptDimension, let directive = activeContainer?.chunkingDirective {
                    Text(
                        "Chunking locked on \(directive.strategy.capitalized) • \(directive.targetWordWindow)w / \(directive.overlapWords) overlap from the last run."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }

        if autoAdaptDimension {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(
                    "New files get a splitting style picked from their text. The app never re-chunks or re-embeds the whole library on its own; rebuilding is always your choice."
                )
                // Self-tuning is not scheduled by any import (`allowsSelfTuningScheduling` is false), so nothing here
                // promises a next tune (refuting review, 2026-11-10); a library tuned before says when.
                if let summary = lastSelfTuneSummary {
                    Text("Last tuned \(summary).")
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.top, DSSpacing.xs)
        } else {
            Text(
                "Leave this off to keep manual control—recommendations still show up, but nothing will re-index or re-chunk without you pressing the button."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, DSSpacing.xs)
        }
    }

    @ViewBuilder
    private var dimensionDetailCard: some View {
        if let selectedOption = dimensionOptions.first(where: { $0.value == dim }) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: selectedOption.icon)
                        .foregroundStyle(Color.accentColor)
                    Text(selectedOption.title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(selectedOption.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !selectedOption.metrics.isEmpty {
                    HStack(spacing: DSSpacing.md) {
                        ForEach(selectedOption.metrics) { metric in
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: metric.icon)
                                    .font(.caption2)
                                Text(metric.text)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
    }

    @ViewBuilder
    private var reembedWarnings: some View {
        if activeContainer?.embeddingDim != dim {
            SettingHelpCallout(
                icon: "arrow.triangle.2.circlepath",
                title: "Re-embed required",
                description:
                    "Changing dimensions reshapes every vector. Reprocess your documents so searches stay accurate.",
                bullets: [
                    "Export/backup if you need a snapshot",
                    "Re-run ingestion to rebuild embeddings",
                    "Old indexes are discarded once new vectors exist",
                ],
                accent: .orange
            )
        }

        if isReembedding, let progress = reembedProgress {
            ReembedStatusBanner(progress: progress)
        }
    }

    @ViewBuilder
    var vectorDatabaseSection: some View {
        Section(header: Text("Vector database — where embeddings live")) {
            vectorDatabaseContent
        }
    }

    @ViewBuilder
    private var vectorDatabaseContent: some View {
        Text("Choose how search indexes are stored. For maximum reliability, use the exact/persistent engine.")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Warn if changing from persistent to in-memory with existing data
        if dbKind == .inMemory, activeContainer?.vectorDBKind != .inMemory, !activeContainerDocuments.isEmpty {
            SettingHelpCallout(
                icon: "exclamationmark.triangle.fill",
                title: "Data will be lost on restart",
                description:
                    "In-Memory storage doesn't persist. Your \(activeContainerDocuments.count) document(s) will need to be re-indexed after every app restart.",
                bullets: ["Consider using Persistent JSON for production use", "In-Memory is ideal for testing only"],
                accent: .orange
            )
        }

        ForEach(vectorDBOptions) { option in
            SelectableOptionCard(
                icon: option.icon,
                title: option.title,
                subtitle: option.caption,
                detail: option.detail,
                isActive: dbKind == option.kind
            ) {
                let previousKind = dbKind
                dbKind = option.kind

                // Warn about switching to in-memory if docs exist
                if option.kind == .inMemory, previousKind != .inMemory, !activeContainerDocuments.isEmpty {
                    pendingDBChange = option.kind
                    showingDBChangeConfirmation = true
                }
            }
        }
    }

}
