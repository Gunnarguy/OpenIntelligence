//
//  ContainerSettingsSheet+Sections.swift
//  OpenIntelligence
//
//  Extracted view sections to reduce body complexity for Swift compiler.
//

import SwiftUI

// MARK: - Extracted Form Sections

extension ContainerSettingsSheet {
    @ViewBuilder
    var identitySection: some View {
        Section(header: Text("Library identity")) {
            Text("Give this workspace a clear name, friendly icon, and color so you always know which knowledge base you're editing.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Name", text: $name)
            TextField("Icon (SF Symbol)", text: $icon)
            Text("Examples: book.closed, doc.text, sparkles, folder.badge.gear. Open the SF Symbols app to browse icons that match your library's vibe.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
            TextField("Color Hex", text: $colorHex)
            Text("Use #RRGGBB values (e.g., #3366FF). This tints cards and pickers so it's obvious which library is active.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Chunking Section

    @ViewBuilder
    var chunkingSection: some View {
        Section(header: Text("Text chunking — how documents are split")) {
            Text("Controls how documents are divided into searchable pieces. Smaller chunks = more precise matches, larger = more context per result.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Auto Intelligence (adaptive chunking + embeddings)", isOn: $autoAdaptDimension)

            if let lastSelfTuneSummary {
                Text("Last auto-tune: \(lastSelfTuneSummary)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("When enabled, the library profiles your corpus and auto-tunes chunking/embeddings for accuracy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if autoAdaptDimension {
                SettingHelpCallout(
                    icon: "wand.and.stars",
                    title: "Auto-tuning active",
                    description: "Chunking is managed by Auto Intelligence based on your document content. Disable auto-tuning to manually configure.",
                    bullets: [
                        "Current: \(chunkingStrategy.capitalized) strategy",
                        "Window: \(targetWordWindow) words, Overlap: \(overlapWords) words",
                    ],
                    accent: .accentColor
                )
            } else {
                // Strategy picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Strategy")
                        .font(.subheadline.weight(.semibold))

                    Picker("Strategy", selection: $chunkingStrategy) {
                        Text("Balanced").tag("balanced")
                        Text("Dense Precision").tag("densePrecision")
                        Text("Elastic").tag("elastic")
                    }
                    .pickerStyle(.segmented)

                    Text(chunkingStrategyDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Word window slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target Words per Chunk")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(targetWordWindow)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: Binding(
                        get: { Double(targetWordWindow) },
                        set: { targetWordWindow = Int($0) }
                    ), in: 100 ... 600, step: 20)

                    Text("Smaller = more precise matches, larger = more context per chunk. 200-400 is typical.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Overlap slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Overlap Words")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(overlapWords)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: Binding(
                        get: { Double(overlapWords) },
                        set: { overlapWords = Int($0) }
                    ), in: 0 ... 200, step: 10)

                    Text("How many words to repeat between chunks. More overlap = better context continuity, but more storage.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Visual preview
                ChunkingPreview(targetWords: targetWordWindow, overlap: overlapWords)
            }
        }
    }

    private var chunkingStrategyDescription: String {
        switch chunkingStrategy {
        case "densePrecision":
            return "Smaller, tighter chunks for code, math, or technical content where precision matters."
        case "elastic":
            return "Flexible sizing that adapts to natural document structure like paragraphs and sections."
        default:
            return "Standard chunking balanced between precision and context. Good for most documents."
        }
    }

    // MARK: - Retrieval Tuning Section

    @ViewBuilder
    var retrievalTuningSection: some View {
        Section(header: Text("Retrieval tuning — how search results are ranked")) {
            Text("Fine-tune how the search engine balances semantic meaning vs keyword matching, and how strictly it filters results. No presets—just direct controls.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Advanced sliders (collapsed by default, expand for custom)
            DisclosureGroup("Advanced Controls") {
                // Min similarity threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Minimum Similarity")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(retrievalConfig.minSimilarity * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $retrievalConfig.minSimilarity, in: 0.15 ... 0.70, step: 0.05)

                    Text("Chunks below this similarity score are filtered out. Higher = stricter, fewer results.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Vector vs Lexical weight
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Semantic vs Keyword")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(retrievalConfig.vectorWeight * 100))% / \(Int(retrievalConfig.lexicalWeight * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $retrievalConfig.vectorWeight, in: 0.3 ... 0.9, step: 0.05)
                        .onChange(of: retrievalConfig.vectorWeight) { _, newValue in
                            retrievalConfig.lexicalWeight = 1.0 - newValue
                        }

                    Text("Left = more keyword matching (BM25), Right = more semantic embedding similarity.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // MMR Lambda
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Result Diversity (MMR λ)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.2f", retrievalConfig.mmrLambda))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $retrievalConfig.mmrLambda, in: 0.3 ... 0.95, step: 0.05)

                    Text("Higher = favor most relevant results, Lower = favor diverse results from different parts of documents.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Min confident chunks
                Stepper(value: $retrievalConfig.minConfidentChunks, in: 1 ... 5) {
                    HStack {
                        Text("Min. Confident Chunks")
                            .font(.subheadline)
                        Spacer()
                        Text("\(retrievalConfig.minConfidentChunks)")
                            .foregroundColor(.accentColor)
                    }
                }

                Text("Require at least this many chunks above threshold before answering. Higher = more conservative.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Explicit citations toggle
                Toggle("Require Explicit Citations", isOn: $retrievalConfig.requireExplicitCitations)

                Text("When enabled, the AI will cite specific source documents in responses.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Balanced Defaults Section

    @ViewBuilder
    var accuracyDefaultsSection: some View {
        Section(header: Text("Balanced defaults")) {
            Text("Apply the most reliable configuration for this library. This favors contextual embeddings, persistent storage, and auto-tuned chunking.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Apply Balanced Defaults") {
                applyAccuracyDefaults()
            }
            .buttonStyle(.borderedProminent)

            Text("You can still customize any setting below. Saving will trigger a re-embed if needed.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func applyAccuracyDefaults() {
        providerId = "nl_contextual_embedding"
        dim = 512
        dbKind = .persistentJSON
        autoAdaptDimension = true
    }

    @ViewBuilder
    var intelligenceSection: some View {
        if let report = activeIntelligenceReport {
            Section(header: Text("Auto Intelligence snapshot")) {
                AutoIntelligencePanel(
                    report: report,
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
                    description: "Drop a few documents into this library and the dynamic engine will profile everything, set chunking windows, and be ready to re-index the rest whenever the strategy shifts.",
                    bullets: [
                        "We'll automatically re-chunk + re-embed when new docs change the optimal strategy",
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
        Section(header: Text("Embedding model — how text becomes numbers")) {
            Text("Pick the translator that turns sentences into vectors. Each option stays on-device unless noted.")
                .font(.caption)
                .foregroundColor(.secondary)

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

            if !providerAlerts.isEmpty {
                VStack(spacing: 8) {
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
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    var embeddingResolutionSection: some View {
        Section(header: Text("Embedding resolution")) {
            embeddingResolutionContent
        }
    }

    @ViewBuilder
    private var embeddingResolutionContent: some View {
        Text("Higher dimensions capture more nuance but increase storage and indexing time.")
            .font(.caption)
            .foregroundColor(.secondary)

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
            VStack(alignment: .leading, spacing: 2) {
                Text("Dynamic self-tuning library")
                if autoAdaptDimension, let directive = activeContainer?.chunkingDirective {
                    Text("Chunking locked on \(directive.strategy.capitalized) • \(directive.targetWordWindow)w / \(directive.overlapWords) overlap from the last run.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }

        if autoAdaptDimension {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenIntelligence watches the entire corpus. When a fresh upload shifts the optimal chunking windows or embedding space, we'll automatically re-chunk and re-embed the whole library for you.")
                if let summary = lastSelfTuneSummary {
                    Text("Last tune \(summary). Next one kicks in as soon as the intelligence profile drifts again.")
                } else {
                    Text("First tune will kick off as soon as enough signal lands to profile your stack.")
                }
            }
            .font(.caption2)
            .foregroundColor(.accentColor)
            .padding(.top, 4)
        } else {
            Text("Leave this off to keep manual control—recommendations still show up, but nothing will re-index or re-chunk without you pressing the button.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var dimensionDetailCard: some View {
        if let selectedOption = dimensionOptions.first(where: { $0.value == dim }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: selectedOption.icon)
                        .foregroundColor(.accentColor)
                    Text(selectedOption.title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(selectedOption.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !selectedOption.metrics.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(selectedOption.metrics) { metric in
                            HStack(spacing: 4) {
                                Image(systemName: metric.icon)
                                    .font(.caption2)
                                Text(metric.text)
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var reembedWarnings: some View {
        if activeContainer?.embeddingDim != dim {
            SettingHelpCallout(
                icon: "arrow.triangle.2.circlepath",
                title: "Re-embed required",
                description: "Changing dimensions reshapes every vector. Reprocess your documents so searches stay accurate.",
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
            .foregroundColor(.secondary)

        // Warn if changing from persistent to in-memory with existing data
        if dbKind == .inMemory, activeContainer?.vectorDBKind != .inMemory, !activeContainerDocuments.isEmpty {
            SettingHelpCallout(
                icon: "exclamationmark.triangle.fill",
                title: "Data will be lost on restart",
                description: "In-Memory storage doesn't persist. Your \(activeContainerDocuments.count) document(s) will need to be re-indexed after every app restart.",
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

// MARK: - Chunking Preview Visualization

struct ChunkingPreview: View {
    let targetWords: Int
    let overlap: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chunk Layout Preview")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let chunkWidth = min(width * 0.4, CGFloat(targetWords) / 600.0 * width * 0.8)
                let overlapWidth = min(chunkWidth * 0.5, CGFloat(overlap) / CGFloat(targetWords) * chunkWidth)

                HStack(spacing: -overlapWidth) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(chunkColor(for: index))
                            .frame(width: chunkWidth, height: 24)
                            .overlay(
                                Text("Chunk \(index + 1)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .frame(height: 24)

            HStack(spacing: 16) {
                Label("\(targetWords)w each", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if overlap > 0 {
                    Label("\(overlap)w overlap", systemImage: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            // Estimated chunks for sample doc
            let estimatedChunks = max(1, 2000 / max(1, targetWords - overlap))
            Text("A 2,000-word document would produce ~\(estimatedChunks) chunks")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chunkColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .indigo]
        return colors[index % colors.count].opacity(0.8)
    }
}
