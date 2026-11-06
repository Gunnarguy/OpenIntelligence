//
//  ContainerSettingsSheet+Intelligence.swift
//  OpenIntelligence
//
//  Part of ContainerSettingsSheet, moved from ContainerSettingsSheet+Sections.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import NaturalLanguage
import SwiftUI

extension ContainerSettingsSheet {
    // MARK: - AI Feature Overrides Section

    @ViewBuilder
    var aiFeatureOverridesSection: some View {
        Section(header: Text("AI features — per-library overrides")) {
            Text("Control which Apple Intelligence features are active for this library. Where supported, these can diverge from the global defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $autoTagOnIngestion) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Auto-Tag on Ingestion")
                    Text("Automatically generate content tags when documents are added")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("Translation Language")
                    .font(.subheadline.weight(.semibold))
                    .tour(.translation, in: Tour.librarySettings)

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
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }

    // MARK: - Silicon-Native RAG Info

    @ViewBuilder
    var siliconNativeChunkingInfo: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Silicon-Native Acceleration")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(DeviceCapabilityService.shared.chipName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Was "All vector operations use Apple's Accelerate framework with Neural Engine optimization." Accelerate
            // is CPU work ("high-performance, energy-efficient computation on the CPU", Apple's Accelerate page, read
            // 2026-10-18), and a large library is searched with Metal under Performance and Maximum (5.7).
            Text("Vector search uses Apple's Accelerate framework on the CPU. With the GPU setting on Performance or Maximum, a library of 1,000 passages or more is searched on the GPU with Metal. Batch sizes are set for your device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
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

            HStack(spacing: DSSpacing.md) {
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
        .padding(DSSpacing.md)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func siliconFeatureRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func siliconInfoPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Corpus Intelligence Card

    @ViewBuilder
    func corpusIntelligenceCard(report: LibraryIntelligenceCenter.IntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header with live status
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text("Live Corpus Intelligence")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Analyzed")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            if report.corpus.isEstimate {
                // A large library is measured from a sample of its passages.
                Text("Measured from \(report.corpus.analysedChunkCount) of \(report.corpus.chunkCount) chunks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Content Detection Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DSSpacing.sm),
                GridItem(.flexible(), spacing: DSSpacing.sm),
            ], spacing: DSSpacing.sm) {
                intelligenceStatCell(
                    icon: "doc.text.fill",
                    label: "Documents",
                    value: "\(report.corpus.documentCount)",
                    color: .accentColor
                )
                intelligenceStatCell(
                    icon: "square.split.2x2.fill",
                    label: "Chunks",
                    value: "\(report.corpus.chunkCount)",
                    color: .accentColor
                )
                intelligenceStatCell(
                    icon: "character.textbox",
                    label: "Avg Words",
                    value: "\(Int(report.corpus.avgWordsPerChunk))",
                    color: .accentColor
                )
                intelligenceStatCell(
                    icon: "brain",
                    label: "Complexity",
                    value: complexityLabel(report.corpus.semanticComplexity),
                    color: .accentColor
                )
            }

            // Content Type Detection
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Content Detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        if report.corpus.hasCode {
                            contentBadge(icon: "chevron.left.forwardslash.chevron.right", label: "Code", color: .accentColor)
                        }
                        if report.corpus.hasMath {
                            contentBadge(icon: "function", label: "Math", color: .accentColor)
                        }
                        if report.corpus.technicalDensity > 0.3 {
                            contentBadge(icon: "gearshape.2.fill", label: "Technical", color: .accentColor)
                        }
                        if report.corpus.multilingualScore > 0.2 {
                            contentBadge(icon: "globe", label: "Multilingual", color: .accentColor)
                        }
                        if report.corpus.structuredRatio > 0.4 {
                            contentBadge(icon: "list.bullet.rectangle", label: "Structured", color: .accentColor)
                        }
                        if report.corpus.vocabularyRichness > 0.4 {
                            contentBadge(icon: "textformat.abc", label: "Rich Vocab", color: .accentColor)
                        }
                        // Always show at least one badge
                        if !report.corpus.hasCode && !report.corpus.hasMath && report.corpus.technicalDensity <= 0.3 {
                            contentBadge(icon: "doc.plaintext", label: "Prose", color: .secondary)
                        }
                    }
                }
            }

            // Recommended Strategy
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Recommended: \(report.chunking.strategy.rawValue.capitalized)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(report.chunking.targetWordWindow)w / \(report.chunking.overlapWords)w overlap")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func intelligenceStatCell(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DSSpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    @ViewBuilder
    private func contentBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
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
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Smart Retrieval Config")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(report.retrieval.fusionStyle.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Weight visualization
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Semantic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: DSSpacing.xs) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * report.retrieval.vectorWeight)
                        }
                        .frame(height: 6)
                        Text("\(Int(report.retrieval.vectorWeight * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Keyword")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: DSSpacing.xs) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.secondary)
                                .frame(width: geo.size.width * report.retrieval.lexicalWeight)
                        }
                        .frame(height: 6)
                        Text("\(Int(report.retrieval.lexicalWeight * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MMR and Reranker info
            HStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                    Text("MMR: \(String(format: "%.2f", report.retrieval.mmrLambda))")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.accentColor)

                if report.retrieval.reranker != .none {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                        Text("Reranker: \(report.retrieval.reranker.rawValue.capitalized)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Notes
            if !report.retrieval.notes.isEmpty {
                Text(report.retrieval.notes.first ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.md)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

}
