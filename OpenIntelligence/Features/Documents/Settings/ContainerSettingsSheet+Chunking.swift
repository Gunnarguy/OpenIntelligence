//
//  ContainerSettingsSheet+Chunking.swift
//  OpenIntelligence
//
//  Part of ContainerSettingsSheet, moved from ContainerSettingsSheet+Sections.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import NaturalLanguage
import SwiftUI

extension ContainerSettingsSheet {
    // MARK: - Chunking Section

    @ViewBuilder
    var chunkingSection: some View {
        Section(header: Text("Semantic chunking — topic-aware splitting")) {
            // Dropped the "(Late Chunking)" label. That names a specific technique the
            // app does not implement: late chunking embeds the whole document with a
            // long-context model and mean-pools token vectors per chunk, so each chunk
            // vector carries full-document context. `SemanticChunker` embeds individual
            // sentences to locate boundaries and returns positions, then chunks are
            // embedded independently. The rest of this sentence describes what actually
            // runs and is unchanged. Real late chunking is tracked on the roadmap.
            Text("Documents are split using embedding-based boundary detection. Topic shifts are detected via cosine similarity drops between adjacent sentences, producing semantically coherent chunks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $autoAdaptDimension) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Auto Intelligence")
                    Text("Automatically optimizes chunking based on your content")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if autoAdaptDimension {
                if let lastSelfTuneSummary {
                    Label("Last tuned: \(lastSelfTuneSummary)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Label("Will analyze your documents and tune automatically", systemImage: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Label("Manual mode: You control all chunking settings below", systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                // Says plainly that this section is optional and that the default is already
                // per-file-type, because the failure mode here is a user changing it, getting
                // worse retrieval, and concluding the app is bad.
                //
                // The claim is checkable: `ChunkingConfig.recommended(for:)` switches on
                // `DocumentType` and returns `.code` (180 words, 35 overlap, topic detection off,
                // because source files have no prose transitions) for source files,
                // `.technicalReference` (240/45) for PDFs, scans and CSV, `.narrative` for Office
                // files and transcripts, and the balanced default for markdown and plain text.
                // `DocumentProcessor` uses `chunkOverride?.targetWordWindow ?? baseConfig.targetSize`,
                // so setting a value here replaces that per-type choice with one fixed number for
                // every file type in this library. That is the actual cost, and it is what this
                // copy describes. `ChunkingLimitsTests.testPerFileTypeDefaultsRemainDistinct`
                // fails if those presets ever collapse into one, which would make this untrue.
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text("ADVANCED. YOU DO NOT NEED TO CHANGE THIS")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.orange)

                    Text("Left alone, the app already picks a chunk size from the kind of file you imported: smaller for code, larger for reports and transcripts, and it skips prose based splitting on source files entirely. Setting a value here replaces that with one size for every file type in this library, which usually makes results worse rather than better. Changing it also re-chunks and re-indexes every document in the library.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.sm)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                .padding(.bottom, DSSpacing.xs)
                .accessibilityElement(children: .combine)

                // Strategy picker
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
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
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DSSpacing.xs)

                // Word window slider
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack {
                        Text("Target Words per Chunk")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(targetWordWindow)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }

                    // Bounded by the ceiling the pipeline enforces, read from the same constant
                    // `DocumentProcessor` clamps to. This ran to 600 while ingestion applied
                    // `min(value, 260)`, so more than half the track did nothing and the app
                    // reported a setting it was discarding.
                    Slider(value: Binding(
                        get: { Double(targetWordWindow) },
                        set: { targetWordWindow = Int($0) }
                    ),
                    in: Double(SemanticChunker.ChunkingConfig.minTargetSize)
                        ... Double(SemanticChunker.ChunkingConfig.maxTargetSize),
                    step: 20)
                    .accessibilityLabel("Target Words per Chunk")
                    .accessibilityValue("\(targetWordWindow) words")

                    Text("Smaller = more precise matches, larger = more context per chunk. \(SemanticChunker.ChunkingConfig.maxTargetSize) words is the most the embedding model can take with room for its prefix.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DSSpacing.xs)

                // Overlap slider
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack {
                        Text("Overlap Words")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(overlapWords)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }

                    // Same reason as the target slider: this ran to 200 against an enforced
                    // `min(value, 50)`.
                    Slider(value: Binding(
                        get: { Double(overlapWords) },
                        set: { overlapWords = Int($0) }
                    ),
                    in: 0 ... Double(SemanticChunker.ChunkingConfig.maxOverlap),
                    step: 5)
                    .accessibilityLabel("Overlap Words")
                    .accessibilityValue("\(overlapWords) words")

                    Text("How many words to repeat between chunks. More overlap = better context continuity, but more storage.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DSSpacing.xs)

                // Visual preview
                ChunkingPreview(targetWords: targetWordWindow, overlap: overlapWords)
            }
        }
    }

    /// What each strategy actually does.
    ///
    /// Two of these were wrong. "elastic" claimed "embedding similarity", and
    /// `SemanticChunker.embeddingService` is declared at line 67 and assigned nowhere in the
    /// repository, so `detectEmbeddingBoundaries` returns an empty array at its own guard on
    /// every path; the chunker logs "Embedding service unavailable - using linguistic boundaries
    /// only" and `detectTopicBoundaries` is ten hardcoded English phrases. The default promised a
    /// "280-400 word target" that `DocumentProcessor` clamps to `maxTargetSize`, making the whole
    /// range unreachable. The target is read from the constant now so it cannot drift again.
    private var chunkingStrategyDescription: String {
        switch chunkingStrategy {
        case "densePrecision":
            return "150-200 word chunks for code, formulas, or dense technical content. Higher precision, more granular retrieval."
        case "elastic":
            return "Sizes chunks to paragraph and section boundaries, using Apple's sentence detection plus a fixed list of ten English transition phrases. It does not compare meaning between sentences, so the boundaries it finds are structural rather than semantic, and the phrase list is English only."
        default:
            return "Up to a \(SemanticChunker.ChunkingConfig.maxTargetSize) word target with \(SemanticChunker.ChunkingConfig.maxOverlap) words of overlap. Balances how much context a chunk carries against how precisely it can be matched."
        }
    }

}
