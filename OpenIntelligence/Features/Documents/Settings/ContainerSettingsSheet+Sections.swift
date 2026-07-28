//
//  ContainerSettingsSheet+Sections.swift
//  OpenIntelligence
//
//  Extracted view sections to reduce body complexity for Swift compiler.
//

import NaturalLanguage
import SwiftUI

// MARK: - Extracted Form Sections

extension ContainerSettingsSheet {
    /// Document names for smart icon suggestions
    private var documentNamesForIconSuggestion: [String] {
        activeContainerDocuments.map { $0.filename }
    }

    @ViewBuilder
    var identitySection: some View {
        Section(header: Text("Library identity")) {
            Text("Give this workspace a clear name, friendly icon, and color so you always know which knowledge base you're editing.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Name", text: $name)

            // SF Symbol Picker with smart suggestions based on library content
            SFSymbolPickerButton(
                selectedSymbol: $icon,
                documentNames: documentNamesForIconSuggestion
            )

            // Color Picker
            ColorPickerButton(selectedColorHex: $colorHex, label: "Color")
        }
    }

    // MARK: - Chunking Section

    @ViewBuilder
    var chunkingSection: some View {
        Section(header: Text("Semantic chunking — topic-aware splitting")) {
            Text("Documents are split using embedding-based boundary detection (Late Chunking). Topic shifts are detected via cosine similarity drops between adjacent sentences, producing semantically coherent chunks.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(isOn: $autoAdaptDimension) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Intelligence")
                    Text("Automatically optimizes chunking based on your content")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if autoAdaptDimension {
                if let lastSelfTuneSummary {
                    Label("Last tuned: \(lastSelfTuneSummary)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Label("Will analyze your documents and tune automatically", systemImage: "wand.and.stars")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            } else {
                Label("Manual mode: You control all chunking settings below", systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if autoAdaptDimension {
                // Live Corpus Intelligence Panel
                if let report = activeIntelligenceReport {
                    corpusIntelligenceCard(report: report)
                }

                SettingHelpCallout(
                    icon: "wand.and.stars",
                    title: "Auto-tuning active",
                    description: "Chunking is managed by Auto Intelligence based on your document content. Disable auto-tuning to manually configure.",
                    bullets: activeIntelligenceReport?.chunking.rationales ?? [
                        "Current: \(chunkingStrategy.capitalized) strategy",
                        "Window: \(targetWordWindow) words, Overlap: \(overlapWords) words",
                    ],
                    accent: .accentColor
                )

                // Silicon-Native optimization info
                siliconNativeChunkingInfo
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
            return "150-200 word chunks for code, formulas, or dense technical content. Higher precision, more granular retrieval."
        case "elastic":
            return "Dynamically sizes chunks to paragraph/section boundaries. Uses NLTokenizer sentence detection + embedding similarity."
        default:
            return "280-400 word target with 17% overlap. Balances semantic coherence with retrieval granularity."
        }
    }

    // MARK: - AI Feature Overrides Section

    @ViewBuilder
    var aiFeatureOverridesSection: some View {
        Section(header: Text("AI features — per-library overrides")) {
            Text("Control which Apple Intelligence features are active for this library. Where supported, these can diverge from the global defaults.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(isOn: $autoTagOnIngestion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Tag on Ingestion")
                    Text("Automatically generate content tags when documents are added")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Translation Language")
                    .font(.subheadline.weight(.semibold))

                Picker("Translation Language", selection: $preferredTranslationLanguage) {
                    Text("No override").tag("auto")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Chinese (Simplified)").tag("zh-Hans")
                    Text("Korean").tag("ko")
                    Text("Portuguese").tag("pt")
                    Text("Italian").tag("it")
                    Text("Arabic").tag("ar")
                }
                .pickerStyle(.menu)

                Text("Choose a target retrieval language for this library. Changing it requires re-indexing existing documents.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Silicon-Native RAG Info

    @ViewBuilder
    var siliconNativeChunkingInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption)
                    .foregroundColor(.cyan)
                Text("Silicon-Native Acceleration")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(DeviceCapabilityService.shared.chipName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text("All vector operations use Apple's Accelerate framework with Neural Engine optimization. Batch sizes are tuned for your device.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                siliconFeatureRow(
                    icon: "function",
                    label: "vDSP Vector Math",
                    detail: "Hardware-accelerated similarity"
                )
                siliconFeatureRow(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Semantic Boundaries",
                    detail: "Topic detection via embeddings"
                )
                siliconFeatureRow(
                    icon: "lock.fill",
                    label: "Library Isolation",
                    detail: "Retrieval stays scoped to this library"
                )
            }

            HStack(spacing: 12) {
                siliconInfoPill(
                    icon: "square.stack.3d.up",
                    label: "Vector",
                    value: "\(DeviceCapabilityService.shared.vectorBatchSize)"
                )
                siliconInfoPill(
                    icon: "text.badge.checkmark",
                    label: "Embed",
                    value: "\(DeviceCapabilityService.shared.embeddingBatchSize)"
                )
                siliconInfoPill(
                    icon: "square.grid.3x3",
                    label: "Matrix",
                    value: "\(DeviceCapabilityService.shared.batchMatrixMultiplyThreshold)+"
                )
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func siliconFeatureRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.cyan)
                .frame(width: 16)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func siliconInfoPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Corpus Intelligence Card

    @ViewBuilder
    private func corpusIntelligenceCard(report: LibraryIntelligenceCenter.IntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with live status
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                Text("Live Corpus Intelligence")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Analyzed")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Content Detection Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                intelligenceStatCell(
                    icon: "doc.text.fill",
                    label: "Documents",
                    value: "\(report.corpus.documentCount)",
                    color: .blue
                )
                intelligenceStatCell(
                    icon: "square.split.2x2.fill",
                    label: "Chunks",
                    value: "\(report.corpus.chunkCount)",
                    color: .indigo
                )
                intelligenceStatCell(
                    icon: "character.textbox",
                    label: "Avg Words",
                    value: "\(Int(report.corpus.avgWordsPerChunk))",
                    color: .orange
                )
                intelligenceStatCell(
                    icon: "brain",
                    label: "Complexity",
                    value: complexityLabel(report.corpus.semanticComplexity),
                    color: .purple
                )
            }

            // Content Type Detection
            VStack(alignment: .leading, spacing: 6) {
                Text("Content Detected")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if report.corpus.hasCode {
                            contentBadge(icon: "chevron.left.forwardslash.chevron.right", label: "Code", color: .green)
                        }
                        if report.corpus.hasMath {
                            contentBadge(icon: "function", label: "Math", color: .orange)
                        }
                        if report.corpus.technicalDensity > 0.3 {
                            contentBadge(icon: "gearshape.2.fill", label: "Technical", color: .blue)
                        }
                        if report.corpus.multilingualScore > 0.2 {
                            contentBadge(icon: "globe", label: "Multilingual", color: .purple)
                        }
                        if report.corpus.structuredRatio > 0.4 {
                            contentBadge(icon: "list.bullet.rectangle", label: "Structured", color: .indigo)
                        }
                        if report.corpus.vocabularyRichness > 0.4 {
                            contentBadge(icon: "textformat.abc", label: "Rich Vocab", color: .cyan)
                        }
                        // Always show at least one badge
                        if !report.corpus.hasCode && !report.corpus.hasMath && report.corpus.technicalDensity <= 0.3 {
                            contentBadge(icon: "doc.plaintext", label: "Prose", color: .secondary)
                        }
                    }
                }
            }

            // Recommended Strategy
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("Recommended: \(report.chunking.strategy.rawValue.capitalized)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(report.chunking.targetWordWindow)w / \(report.chunking.overlapWords)w overlap")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func intelligenceStatCell(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func contentBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func complexityLabel(_ score: Double) -> String {
        switch score {
        case 0 ..< 0.3: return "Simple"
        case 0.3 ..< 0.6: return "Moderate"
        case 0.6 ..< 0.8: return "Complex"
        default: return "Dense"
        }
    }

    @ViewBuilder
    private func retrievalIntelligenceCard(report: LibraryIntelligenceCenter.IntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.caption)
                    .foregroundColor(.teal)
                Text("Smart Retrieval Config")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(report.retrieval.fusionStyle.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.teal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Weight visualization
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Semantic")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * report.retrieval.vectorWeight)
                        }
                        .frame(height: 6)
                        Text("\(Int(report.retrieval.vectorWeight * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.blue)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyword")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * report.retrieval.lexicalWeight)
                        }
                        .frame(height: 6)
                        Text("\(Int(report.retrieval.lexicalWeight * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.orange)
                    }
                }
            }

            // MMR and Reranker info
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                    Text("MMR: \(String(format: "%.2f", report.retrieval.mmrLambda))")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.teal)

                if report.retrieval.reranker != .none {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                        Text("Reranker: \(report.retrieval.reranker.rawValue.capitalized)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(.purple)
                }
            }

            // Notes
            if !report.retrieval.notes.isEmpty {
                Text(report.retrieval.notes.first ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Retrieval Style Section (User-Friendly Presets)

    @ViewBuilder
    var retrievalStyleSection: some View {
        Section(header: Text("Search behavior — how results are found")) {
            Text("Choose a search style that matches your content. This tunes how strictly results are filtered and how semantic vs keyword matching is balanced.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                retrievalStyleCard(
                    style: .balanced,
                    icon: "scale.3d",
                    title: "Balanced",
                    subtitle: "Best for most documents",
                    description: "Good mix of precision and recall. Works well for general knowledge bases.",
                    isSelected: retrievalConfig.isCloseTo(.default)
                )

                retrievalStyleCard(
                    style: .precision,
                    icon: "target",
                    title: "High Precision",
                    subtitle: "Strict filtering, explicit citations",
                    description: "For research, legal, or medical content where accuracy matters most.",
                    isSelected: retrievalConfig.isCloseTo(.highAccuracy)
                )

                retrievalStyleCard(
                    style: .technical,
                    icon: "wrench.and.screwdriver",
                    title: "Technical Manual",
                    subtitle: "Keyword-heavy, low threshold",
                    description: "Optimized for specs, manuals, and reference docs with domain-specific terms.",
                    isSelected: retrievalConfig.isCloseTo(.technicalManual)
                )

                retrievalStyleCard(
                    style: .exploratory,
                    icon: "binoculars",
                    title: "Exploratory",
                    subtitle: "Diverse results, permissive",
                    description: "For creative or brainstorming queries where you want varied perspectives.",
                    isSelected: retrievalConfig.isCloseTo(.exploratory)
                )
            }

            // Quick stats showing current config
            if !retrievalConfig.isCloseTo(.default) && !retrievalConfig.isCloseTo(.highAccuracy)
                && !retrievalConfig.isCloseTo(.technicalManual) && !retrievalConfig.isCloseTo(.exploratory)
            {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Configuration")
                            .font(.caption.weight(.medium))
                        Text("Min: \(Int(retrievalConfig.minSimilarity * 100))% • Vector: \(Int(retrievalConfig.vectorWeight * 100))% • MMR: \(String(format: "%.2f", retrievalConfig.mmrLambda))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private enum RetrievalStyle {
        case balanced, precision, technical, exploratory
    }

    @ViewBuilder
    private func retrievalStyleCard(
        style: RetrievalStyle,
        icon: String,
        title: String,
        subtitle: String,
        description: String,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                switch style {
                case .balanced:
                    retrievalConfig = .default
                case .precision:
                    retrievalConfig = .highAccuracy
                case .technical:
                    retrievalConfig = .technicalManual
                case .exploratory:
                    retrievalConfig = .exploratory
                }
            }
            DSHaptics.selection()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Retrieval Tuning Section

    @ViewBuilder
    var retrievalTuningSection: some View {
        Section(header: Text("Hybrid retrieval — vector + BM25 fusion")) {
            Text("Fine-tune HybridSearchService's Reciprocal Rank Fusion (RRF). Adjust vector/lexical weights, MMR λ for diversity, and minimum similarity thresholds.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Show retrieval intelligence when auto-tuning is on
            if autoAdaptDimension, let report = activeIntelligenceReport {
                retrievalIntelligenceCard(report: report)
            }

            // Advanced sliders (collapsed by default, expand for custom)
            DisclosureGroup("Advanced Controls") {
                // Min similarity threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Minimum Cosine Similarity")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(retrievalConfig.minSimilarity * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $retrievalConfig.minSimilarity, in: 0.15 ... 0.70, step: 0.05)

                    Text("Pre-filter threshold: chunks with sim < this are discarded before RRF. Higher = stricter, fewer candidates.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // Vector vs Lexical weight
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Vector / BM25 Weight")
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

                    Text("RRF fusion weight: Left = favor BM25 term-frequency, Right = favor cosine embedding similarity.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                // MMR Lambda
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MMR λ (Diversity)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.2f", retrievalConfig.mmrLambda))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $retrievalConfig.mmrLambda, in: 0.3 ... 0.95, step: 0.05)

                    Text("Maximal Marginal Relevance: λ−1 = pure relevance, λ→0 = penalize redundancy. Balances quality vs coverage.")
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
            Text("Apply the recommended configuration: CoreML sentence embeddings (all-MiniLM-L6-v2), persistent JSON storage, and auto-tuned semantic chunking.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Apply Balanced Defaults") {
                applyAccuracyDefaults()
            }
            .buttonStyle(.borderedProminent)

            Text("You can still customize any setting below. Saving will trigger a re-embed if the embedding model or dimension changes.")
                .font(.caption2)
                .foregroundColor(.secondary)
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
        Section(header: Text("Embedding model — sentence → vector transformation")) {
            Text("Select the neural encoder that maps text to dense vectors. Currently using bundled MiniLM-L6-v2 (384D). All inference runs on-device via Neural Engine.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Show embedding intelligence when auto-tuning is on
            if autoAdaptDimension, let report = activeIntelligenceReport {
                embeddingIntelligenceCard(report: report)
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
    private func embeddingIntelligenceCard(report: LibraryIntelligenceCenter.IntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundColor(.indigo)
                Text("Smart Embedding Selection")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(report.embedding.confidence * 100))% match")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(report.embedding.rationale)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text("Dim: \(report.embedding.dimension)")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.indigo)

                if report.embedding.requiresCloudConsent {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud")
                            .font(.caption2)
                        Text("Cloud")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone")
                            .font(.caption2)
                        Text("On-Device")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    var embeddingResolutionSection: some View {
        Section(header: Text("Vector dimension")) {
            embeddingResolutionContent
        }
    }

    @ViewBuilder
    private var embeddingResolutionContent: some View {
        Text("Dimension is fixed by the embedding model (384D for MiniLM-L6-v2). Higher dims = richer semantics, more storage (4 bytes × dim per chunk).")
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

    // MARK: - Library Nerd Stats Section (Deep Dive)

    @ViewBuilder
    var libraryNerdStatsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showNerdStats) {
                if isLoadingNerdStats {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading deep stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    libraryNerdStatsContent
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Library Deep Dive")
                            .font(.subheadline.weight(.semibold))
                        Text("Library-scoped diagnostics")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: showNerdStats) { _, expanded in
                if expanded && containerFTSStats.isEmpty {
                    loadNerdStats()
                }
            }
        }
    }

    @ViewBuilder
    private var libraryNerdStatsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Corpus Intelligence (if available)
            if let report = activeIntelligenceReport {
                corpusSignalsCard(report.corpus)
            }

            // Vector Space Statistics
            vectorSpaceStatsCard

            // AI Subsystem Diagnostics (X-Ray Vision)
            aiSubsystemDiagnosticsCard

            // Document Distribution
            documentDistributionCard

            // Top Terms (Vocabulary Analysis)
            topTermsCard

            // Retrieval Config Summary
            retrievalConfigSummaryCard
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func corpusSignalsCard(_ signals: LibraryIntelligenceCenter.CorpusSignals) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Corpus Intelligence", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundColor(.pink)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                nerdStatCell(label: "Vocabulary Richness", value: String(format: "%.1f%%", signals.vocabularyRichness * 100), icon: "book.fill")
                nerdStatCell(label: "Technical Density", value: String(format: "%.1f%%", signals.technicalDensity * 100), icon: "gearshape.fill")
                nerdStatCell(label: "Semantic Complexity", value: String(format: "%.2f", signals.semanticComplexity), icon: "waveform.path")
                nerdStatCell(label: "Structured Ratio", value: String(format: "%.1f%%", signals.structuredRatio * 100), icon: "tablecells")
            }

            // Content type badges
            HStack(spacing: 8) {
                if signals.hasCode {
                    corpusBadge(text: "Code", icon: "chevron.left.forwardslash.chevron.right", color: .blue)
                }
                if signals.hasMath {
                    corpusBadge(text: "Math", icon: "function", color: .purple)
                }
                if signals.multilingualScore > 0.1 {
                    corpusBadge(text: "Multilingual", icon: "globe", color: .green)
                }
            }

            // Language breakdown
            if !signals.languageHypotheses.isEmpty {
                let sortedLangs = signals.languageHypotheses.sorted { $0.value > $1.value }.prefix(3)
                HStack(spacing: 8) {
                    Text("Languages:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(Array(sortedLangs), id: \.key) { lang, conf in
                        Text("\(lang.rawValue) \(String(format: "%.0f%%", conf * 100))")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.pink.opacity(0.8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.pink.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func corpusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var vectorSpaceStatsCard: some View {
        if let container = activeContainer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Vector Space", systemImage: "cube.transparent")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan)

                let documentCount = activeContainerDocuments.count
                let chunkCount = activeContainerDocuments.reduce(0) { $0 + $1.totalChunks }
                let estimatedMemoryBytes = chunkCount * container.embeddingDim * 4
                let bytesPerVector = container.embeddingDim * 4

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    nerdStatCell(label: "Chunks", value: "\(chunkCount)", icon: "point.3.filled.connected.trianglepath.dotted")
                    nerdStatCell(label: "Dimension", value: "\(container.embeddingDim)D", icon: "cube.fill")
                    nerdStatCell(label: "Documents", value: "\(documentCount)", icon: "doc.fill")
                    nerdStatCell(label: "Est. Vector Bytes", value: formatBytes(estimatedMemoryBytes), icon: "memorychip")
                }

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text("~\(bytesPerVector) bytes/vector")
                        .font(.caption2.monospacedDigit())
                    Text("(Float32 estimate)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.cyan.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var documentDistributionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Document Distribution", systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)

            if containerFTSStats.isEmpty {
                Text("No documents in this library")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Size distribution
                let totalChars = containerFTSStats.reduce(0) { $0 + $1.characterCount }
                let totalWords = containerFTSStats.reduce(0) { $0 + $1.wordCount }
                let avgChars = containerFTSStats.count > 0 ? totalChars / containerFTSStats.count : 0
                let avgWords = containerFTSStats.count > 0 ? totalWords / containerFTSStats.count : 0

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    nerdStatCell(label: "Total Chars", value: formatNumber(totalChars), icon: "character")
                    nerdStatCell(label: "Total Words", value: formatNumber(totalWords), icon: "text.word.spacing")
                    nerdStatCell(label: "Avg Chars", value: formatNumber(avgChars), icon: "textformat.size")
                    nerdStatCell(label: "Avg Words", value: formatNumber(avgWords), icon: "textformat")
                }

                // Size histogram (visual)
                if containerFTSStats.count > 1 {
                    sizeHistogramView
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var sizeHistogramView: some View {
        let sortedBySize = containerFTSStats.sorted { $0.characterCount > $1.characterCount }
        let maxSize = sortedBySize.first?.characterCount ?? 1

        VStack(alignment: .leading, spacing: 4) {
            Text("Size Distribution (largest → smallest)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(sortedBySize.prefix(10), id: \.id) { doc in
                    let height = CGFloat(doc.characterCount) / CGFloat(maxSize) * 24
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 8, height: max(4, height))
                }
                if sortedBySize.count > 10 {
                    Text("...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 28)
        }
    }

    @ViewBuilder
    private var topTermsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Terms (This Library)", systemImage: "textformat.abc")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)

            if containerTopTerms.isEmpty {
                Text("No term data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Show top 12 terms as tags
                FlowLayout(spacing: 6) {
                    ForEach(containerTopTerms.prefix(12)) { term in
                        HStack(spacing: 3) {
                            Text(term.term)
                                .font(.caption2.weight(.medium))
                            Text("×\(term.totalOccurrences)")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                // Vocabulary summary
                HStack(spacing: 12) {
                    Label("Loaded \(containerTopTerms.count) frequent terms", systemImage: "text.book.closed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var retrievalConfigSummaryCard: some View {
        let config = retrievalConfig

        VStack(alignment: .leading, spacing: 8) {
            Label("Retrieval Config", systemImage: "gearshape.2.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.indigo)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                nerdStatCell(label: "Min Similarity", value: String(format: "%.2f", config.minSimilarity), icon: "slider.horizontal.3")
                nerdStatCell(label: "Vector Weight", value: String(format: "%.1f", config.vectorWeight), icon: "cube.fill")
                nerdStatCell(label: "Lexical Weight", value: String(format: "%.1f", config.lexicalWeight), icon: "text.magnifyingglass")
                nerdStatCell(label: "MMR λ", value: String(format: "%.2f", config.mmrLambda), icon: "arrow.triangle.branch")
            }

            // Effective mode description
            let modeDescription: String = {
                if config.vectorWeight > 0.7 { return "Semantic-heavy" }
                if config.lexicalWeight > 0.5 { return "Keyword-heavy" }
                return "Hybrid balanced"
            }()

            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                Text("Mode: \(modeDescription)")
                    .font(.caption2)
            }
            .foregroundColor(.indigo.opacity(0.8))
        }
        .padding(12)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func nerdStatCell(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func formatBytes64(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        } else {
            return "\(n)"
        }
    }

    @ViewBuilder
    var deleteLibrarySection: some View {
        if containerService.containers.count > 1 {
            Section(header: Text("Danger zone")) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Library", systemImage: "trash")
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    var privateCloudComputeSection: some View {
        let deviceCapabilities = RAGService.checkDeviceCapabilities()
        Section(header: Text("Private Cloud Compute (PCC) Status")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Escalated query modes (Deep Think/Maximum) and large contexts (>4K tokens) dynamically scale to Apple's Private Cloud Compute enclaves.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                // 1. Hardware/OS Support
                HStack {
                    Label("Platform Support", systemImage: "iphone")
                        .font(.subheadline)
                    Spacer()
                    if deviceCapabilities.supportsPrivateCloudCompute {
                        Text("iOS 27+ Available")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                    } else {
                        Text("iOS 26 Fallback Only")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
                    }
                }

                // 2. Entitlement Status
                HStack {
                    Label("Developer Entitlement", systemImage: "signature")
                        .font(.subheadline)
                    Spacer()
                    #if targetEnvironment(simulator)
                    Text("Simulator (Bypassed)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    #else
                    let hasEntitlement = EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
                    Text(hasEntitlement ? "Verified Shipped" : "Missing / Not Signed")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(hasEntitlement ? .green : .red)
                    #endif
                }

                // 3. User Preferences Policy
                HStack {
                    Label("iCloud Execution Consent", systemImage: "cloud.fill")
                        .font(.subheadline)
                    Spacer()
                    Text(self.settings.applePCCConsent == .allowed ? "Allowed" : (self.settings.applePCCConsent == .denied ? "Denied" : "Not Determined"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(self.settings.applePCCConsent == .allowed ? .green : .orange)
                }

                // 4. Effective Routing Fallback
                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Label("Effective RAG Fallback", systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                    Spacer()
                    let canUseNativePCC: Bool = {
                        #if targetEnvironment(simulator)
                        return false
                        #else
                        if deviceCapabilities.supportsPrivateCloudCompute {
                            return EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
                        }
                        return false
                        #endif
                    }()
                    
                    if canUseNativePCC && self.settings.applePCCConsent == .allowed {
                        Text("Native PCC (PT-MoE 32K)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.blue)
                    } else {
                        Text("On-Device (Apple Intelligence)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.green)
                    }
                }
                
                Text(effectiveFallbackDescription(capabilities: deviceCapabilities))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func effectiveFallbackDescription(capabilities: DeviceCapabilities) -> String {
        #if targetEnvironment(simulator)
        return "Simulators do not support Private Cloud Compute enclaves. Queries will run on-device via local simulation."
        #else
        if capabilities.supportsPrivateCloudCompute {
            let hasEntitlement = EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
            if !hasEntitlement {
                return "The binary lacks the required com.apple.developer.private-cloud-compute entitlement. Deep Think and Maximum mode queries will automatically fallback to local ANE-accelerated on-device models to prevent crashes."
            } else if self.settings.applePCCConsent != .allowed {
                return "iCloud consent is disabled or not determined. Queries will strictly execute locally on-device."
            } else {
                return "PCC is fully operational. Queries exceeding 4,096 tokens or using Deep Think/Maximum mode will execute on Apple's secure server enclaves."
            }
        } else {
            return "iOS 26 targets do not have native PCC APIs. Escalated queries will run locally on SystemLanguageModel.default via compatibility wrapper."
        }
        #endif
    }

    @ViewBuilder
    private var aiSubsystemDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("AI Subsystem Diagnostics")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("v4.5.0")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 1. Embedding Model Diagnostics
            VStack(alignment: .leading, spacing: 6) {
                Text("Embedding Pipeline")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                
                HStack {
                    Label("Active Model", systemImage: "cube.transparent")
                        .font(.caption)
                    Spacer()
                    Text("MiniLM-L6-v2 (384D)")
                        .font(.caption.weight(.medium))
                }
                
                HStack {
                    Label("Acceleration Target", systemImage: "bolt.fill")
                        .font(.caption)
                    Spacer()
                    #if canImport(CoreAI)
                    if #available(iOS 27.0, macOS 27.0, *) {
                        Text("Core AI Neural Engine")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.indigo)
                    } else {
                        Text("Core ML Neural Engine")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)
                    }
                    #else
                    Text("Core ML Neural Engine")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                    #endif
                }
                
                HStack {
                    Label("Readiness Gate", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                    Spacer()
                    #if canImport(CoreAI)
                    if #available(iOS 27.0, macOS 27.0, *) {
                        let isReady = CoreAISentenceEmbeddingProvider.shared.isModelLoaded
                        Text(isReady ? "Verified Ready" : "Unloaded")
                            .font(.caption.weight(.medium))
                            .foregroundColor(isReady ? .green : .red)
                    } else {
                        Text("Verified Ready")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                    }
                    #else
                    Text("Verified Ready")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.green)
                    #endif
                }
            }
            .padding(.bottom, 6)
            
            Divider()
            
            // 2. Tokenizer Diagnostics
            VStack(alignment: .leading, spacing: 6) {
                Text("Tokenizer Pipeline")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                
                HStack {
                    Label("Core Parser", systemImage: "curlybraces")
                        .font(.caption)
                    Spacer()
                    Text("Rust-backed swift-tokenizers")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.green)
                }
                
                HStack {
                    Label("Vocabulary", systemImage: "book.closed.fill")
                        .font(.caption)
                    Spacer()
                    Text("30,522 (BERT WordPiece)")
                        .font(.caption.weight(.medium))
                }
                
                HStack {
                    Label("Citation Alignment", systemImage: "target")
                        .font(.caption)
                    Spacer()
                    Text("Exact Byte-Level Offsets")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Label("Latency Profile", systemImage: "gauge.with.needle")
                        .font(.caption)
                    Spacer()
                    Text("Microsecond Batching (<1ms)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Chunking Preview Visualization

struct ChunkingPreview: View {
    let targetWords: Int
    let overlap: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chunk Layout Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                // Semantic chunking indicator
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Semantic")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let chunkWidth = min(width * 0.35, CGFloat(targetWords) / 600.0 * width * 0.7)
                let overlapWidth = min(chunkWidth * 0.4, CGFloat(overlap) / CGFloat(targetWords) * chunkWidth)

                HStack(spacing: -overlapWidth) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(chunkColor(for: index))
.frame(width: chunkWidth, height: 20)
    .overlay(
        Text("Chunk \(index + 1)")
            .font(.caption2)
            .foregroundColor(.white)
    )
                            // Section snap indicator
                            if index == 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.turn.right.down")
                                        .font(.system(size: 6))
                                    Text("Section")
                                        .font(.system(size: 7))
                                }
                                .foregroundColor(.purple.opacity(0.8))
                            }
                        }
                    }
                }
            }
            .frame(height: 36)

            // Stats row
            HStack(spacing: 12) {
                Label("\(targetWords)w target", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if overlap > 0 {
                    Label("\(overlap)w overlap", systemImage: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Spacer()

                // Overlap percentage
                let overlapPct = targetWords > 0 ? Int(Double(overlap) / Double(targetWords) * 100) : 0
                Text("\(overlapPct)% context")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.cyan)
            }

            // Estimated chunks with semantic features
            let estimatedChunks = max(1, 2000 / max(1, targetWords - overlap))

            VStack(alignment: .leading, spacing: 4) {
                Text("A 2,000-word document → ~\(estimatedChunks) semantic chunks")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    featureTag(icon: "text.line.first.and.arrowtriangle.forward", label: "Topic boundaries")
                    featureTag(icon: "list.bullet.indent", label: "Section snapping")
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func featureTag(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundColor(.secondary)
    }

    private func chunkColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .indigo]
        return colors[index % colors.count].opacity(0.8)
    }
}


// MARK: - Date Extension for Relative Description

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
