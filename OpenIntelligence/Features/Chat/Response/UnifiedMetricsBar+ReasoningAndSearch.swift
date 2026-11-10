//
//  UnifiedMetricsBar+ReasoningAndSearch.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Section: Mode-Specific Reasoning

    @ViewBuilder
    var modeSpecificReasoningSection: some View {
        if isMaximumMode {
            maximumModeReasoningSection
        } else if isRecursiveRAG {
            deepThinkReasoningSection
        } else {
            standardModeReasoningSection
        }
    }

    private var standardModeReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "bolt.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.blue)
                Text("Standard Retrieval")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("single-pass")
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            // What techniques were used
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // Hybrid search weights
                HStack(spacing: DSSpacing.lg) {
                    HStack(spacing: DSSpacing.xs) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Semantic: \(Int(vectorWeight * 100))%")
                            .scaledFont(size: 11, weight: .medium)
                            .monospacedDigit()
                    }
                    HStack(spacing: DSSpacing.xs) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Keyword: \(Int(lexicalWeight * 100))%")
                            .scaledFont(size: 11, weight: .medium)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(DSColors.secondaryText)

                // Active techniques
                HStack(spacing: DSSpacing.sm) {
                    if hydeEnabled {
                        techniquePill(icon: "wand.and.stars", text: "HyDE", color: .purple)
                    }
                    if hierarchicalChunkingActive {
                        techniquePill(icon: "doc.on.doc", text: "Parent Expansion", color: .teal)
                    }
                    if siblingChunksAdded > 0 {
                        techniquePill(icon: "arrow.left.arrow.right", text: "+\(siblingChunksAdded) siblings", color: .cyan)
                    }
                    if lenientRetrieval {
                        techniquePill(icon: "hand.thumbsup", text: "Lenient", color: .orange)
                    }
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var deepThinkReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("Deep Think Reasoning")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("multi-session")
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Session info
            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("\(recursiveCallCount)")
                        .scaledFont(size: 24, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.purple)
                    // The count is the answer's model calls (planning, sessions, synthesis, checks), live and final
                    // (5.8); the progress card's "Session N" counts sessions alone, so the two differ.
                    Text("model calls")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                }

                if liveConfidence > 0 || !isProcessing {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(liveConfidence * 100))%")
                            .scaledFont(size: 24, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(liveConfidence >= 0.85 ? .green : .purple)
                        Text("final confidence")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                if contextTokens > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(formatTokenCount(contextTokens))
                            .scaledFont(size: 18, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                        Text("total tokens")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Techniques used
            HStack(spacing: DSSpacing.sm) {
                techniquePill(icon: "arrow.triangle.branch", text: "Multi-Query", color: .purple)
                if graphExpansionActive {
                    techniquePill(icon: "point.3.connected.trianglepath.dotted", text: "Graph Expansion", color: .indigo)
                }
                if graphEntitiesExtracted > 0 {
                    techniquePill(icon: "tag.fill", text: "\(graphEntitiesExtracted) entities", color: .teal)
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var maximumModeReasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "flame.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.orange)
                Text("Maximum Reasoning")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                // Was "unlimited": Maximum stops at 50 sessions, fewer when few passages match (5.7).
                Text("up to 50")
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Session info - bigger numbers for Maximum
            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("\(maximumModeSessionCount)")
                        .scaledFont(size: 28, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("reasoning sessions")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                }

                // Confidence with progress to 98%
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xs) {
                        Text("\(Int(liveConfidence * 100))%")
                            .scaledFont(size: 24, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(liveConfidence >= 0.98 ? .green : .orange)
                        Text("/ 98%")
                            .scaledFont(size: 14, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    Text(liveConfidence >= 0.98 ? "target reached!" : "confidence target")
                        .scaledFont(size: 10)
                        .foregroundStyle(liveConfidence >= 0.98 ? .green : DSColors.secondaryText)
                }

                Spacer()

                if contextTokens > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(formatTokenCount(contextTokens))
                            .scaledFont(size: 18, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                        Text("total tokens")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Maximum mode techniques
            HStack(spacing: DSSpacing.sm) {
                techniquePill(icon: "arrow.triangle.branch", text: "Multi-Query", color: .orange)
                techniquePill(icon: "repeat", text: "Iterative Refinement", color: .yellow)
                if graphExpansionActive {
                    techniquePill(icon: "point.3.connected.trianglepath.dotted", text: "Graph", color: .indigo)
                }
            }

            ThinkingStreamView(events: thinkingEvents, qualityMode: qualityMode)
        }
        .padding(DSSpacing.md)
        .background(
            LinearGradient(colors: [.orange.opacity(0.08), .yellow.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func techniquePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 8)
            Text(text)
                .scaledFont(size: 9, weight: .medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Section: Quality Signals

    var qualitySignalsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.green)
                Text("Confidence & Quality")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            HStack(spacing: DSSpacing.lg) {
                // Top match score
                if topSimilarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xs) {
                            Text("\(Int(topSimilarity * 100))%")
                                .scaledFont(size: 20, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(matchScoreColor(topSimilarity))
                            Image(systemName: "star.fill")
                                .scaledFont(size: 10)
                                .foregroundStyle(.yellow)
                        }
                        Text("best match")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Second best (gap indicates confidence)
                if secondSimilarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(secondSimilarity * 100))%")
                            .scaledFont(size: 16, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(secondSimilarity))
                        Text("2nd best")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                // Average of top results
                if avgTop5Similarity > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("\(Int(avgTop5Similarity * 100))%")
                            .scaledFont(size: 16, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(avgTop5Similarity))
                        Text("avg top 5")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // MMR diversity used
                if mmrDiversity > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text("λ=\(String(format: "%.1f", mmrDiversity))")
                            .scaledFont(size: 14, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.teal)
                        Text("diversity")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else {
            return String(format: "%.1fs", seconds)
        }
    }

    // MARK: - Section: Query Understanding

    var queryUnderstandingSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "text.bubble.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.indigo)
                Text("Query Understanding")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                if hydeEnabled {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "wand.and.stars")
                            .scaledFont(size: 9)
                        Text("HyDE Active")
                            .scaledFont(size: 9, weight: .medium)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Original query (full, not truncated)
            if !originalQuery.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("You asked:")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(originalQuery)
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true) // Full text, never truncate
                }
            }

            // Rewritten/clarified query (if different)
            if !rewrittenQuery.isEmpty && rewrittenQuery != originalQuery {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "arrow.right.circle.fill")
                            .scaledFont(size: 10)
                            .foregroundStyle(.green)
                        Text("Clarified to:")
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    Text(rewrittenQuery)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.sm)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }

            // Extracted keywords & intent
            HStack(spacing: DSSpacing.md) {
                // Keywords
                if !extractedKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Key terms extracted:")
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DSColors.secondaryText)
                        FlowLayout(spacing: DSSpacing.xxs) {
                            ForEach(extractedKeywords.prefix(8), id: \.self) { keyword in
                                Text(keyword)
                                    .scaledFont(size: 10, weight: .semibold)
                                    .padding(.horizontal, DSSpacing.sm)
                                    .padding(.vertical, DSSpacing.xxs)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                // Query expansions
                if expansionCount > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text("\(expansionCount)")
                            .scaledFont(size: 18, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                        Text("query variations")
                            .scaledFont(size: 9)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            // Intent classification
            if !queryIntent.isEmpty {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .scaledFont(size: 10)
                        .foregroundStyle(.yellow)
                    Text("Detected intent: \(queryIntent)")
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(DSColors.primaryText)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Best match info (if available)
            if topMatchScore > 0 {
                HStack(spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "star.fill")
                                .scaledFont(size: 10)
                                .foregroundStyle(.yellow)
                            Text("Best Match")
                                .scaledFont(size: 11, weight: .semibold)
                        }
                        if !topMatchSource.isEmpty {
                            Text(topMatchSource)
                                .scaledFont(size: 12, weight: .medium)
                                .foregroundStyle(DSColors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("\(Int(topMatchScore * 100))% vector similarity")
                                .scaledFont(size: 11, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(matchScoreColor(topMatchScore))
                            Text("Database match vs. LLM confidence")
                                .scaledFont(size: 9)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    Spacer()

                    // Relevance gauge
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(topMatchScore))
                            .stroke(matchScoreColor(topMatchScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(topMatchScore * 100))")
                            .scaledFont(size: 11, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(matchScoreColor(topMatchScore))
                    }
                    .frame(width: 40, height: 40)
                }
                .padding(DSSpacing.sm)
                .background(matchScoreColor(topMatchScore).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }

            // Stats grid
            HStack(spacing: DSSpacing.lg) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(sourceCount)")
                                .scaledFont(size: 22, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                            Text("sources")
                                .scaledFont(size: 12)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if let avg = averageSourceScore {
                            Text("\(Int(avg * 100))% avg vector distance")
                                .scaledFont(size: 11)
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(coveredDocuments)")
                                .scaledFont(size: 22, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                            Text("of \(totalDocuments) docs")
                                .scaledFont(size: 12)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if totalChunks > 0 {
                            Text("\(totalChunks) passages scanned")
                                .scaledFont(size: 11)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }

                Spacer()

                if toolCallCount > 0 {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .scaledFont(size: 14)
                            Text("\(toolCallCount)")
                                .scaledFont(size: 22, weight: .bold, design: .rounded)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.purple)
                        Text("agentic tools invoked")
                            .scaledFont(size: 11)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: Search Strategy

    private var searchStrategySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("Search Strategy")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                // Retrieval mode badge
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: retrievalMode.icon)
                        .scaledFont(size: 9)
                    Text(retrievalMode.rawValue)
                        .scaledFont(size: 9, weight: .semibold)
                }
                .foregroundStyle(retrievalMode.color)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(retrievalMode.color.opacity(0.12))
                .clipShape(Capsule())
            }

            // Visual weight comparison
            HStack(spacing: DSSpacing.md) {
                // Semantic search
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("Semantic Search")
                            .scaledFont(size: 12, weight: .semibold)
                    }
                    Text("Finds content with similar meaning, even if different words are used")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DSSpacing.sm) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * vectorWeight)
                        }
                        .frame(height: 8)
                        .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                        Text("\(Int(vectorWeight * 100))%")
                            .scaledFont(size: 12, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)

                // Keyword search
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                        Text("Keyword Search")
                            .scaledFont(size: 12, weight: .semibold)
                    }
                    Text("Matches exact words and phrases using BM25 scoring algorithm")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DSSpacing.sm) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(Color.orange)
                                .frame(width: geo.size.width * lexicalWeight)
                        }
                        .frame(height: 8)
                        .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                        Text("\(Int(lexicalWeight * 100))%")
                            .scaledFont(size: 12, weight: .bold, design: .monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Additional strategy details
            HStack(spacing: DSSpacing.md) {
                if semanticChunksUsed {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .scaledFont(size: 10)
                            .foregroundStyle(.green)
                        Text("Smart chunking preserves topic boundaries")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "shuffle")
                        .scaledFont(size: 10)
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescriptionFull)")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            // NEW: Advanced RAG Features (FullBlownUpgrade)
            advancedRAGFeaturesSection
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Advanced RAG Features (FullBlownUpgrade)

    @ViewBuilder
    private var advancedRAGFeaturesSection: some View {
        let hasAdvancedFeatures = hierarchicalChunkingActive || graphExpansionActive || intentAwareWeightsActive

        if hasAdvancedFeatures {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Divider()
                    .padding(.vertical, DSSpacing.xxs)

                // Header for advanced features
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "sparkles")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(.yellow)
                    Text("Advanced RAG")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(.yellow)
                }

                // Feature badges in a flow layout
                FlowLayout(spacing: DSSpacing.xs) {
                    // Hierarchical Chunking badge
                    if hierarchicalChunkingActive {
                        advancedFeatureBadge(
                            icon: "rectangle.3.group",
                            title: "Hierarchical",
                            detail: parentChunksUsed > 0 ? "\(parentChunksUsed) parent" : nil,
                            color: .cyan,
                            tooltip: "Parent-child indexing: precise embedding + rich context"
                        )
                    }

                    // Parent expansion stats
                    if siblingChunksAdded > 0 {
                        advancedFeatureBadge(
                            icon: "plus.rectangle.on.rectangle",
                            title: "+\(siblingChunksAdded) siblings",
                            detail: nil,
                            color: .teal,
                            tooltip: "Adjacent chunks merged for complete context"
                        )
                    }

                    // Intent-Aware Weights
                    if intentAwareWeightsActive && !queryIntent.isEmpty {
                        advancedFeatureBadge(
                            icon: "brain",
                            title: "Intent: \(queryIntent)",
                            detail: nil,
                            color: .purple,
                            tooltip: "Dynamic weights adjusted for query type"
                        )
                    }

                    // GraphRAG-lite expansion
                    if graphExpansionActive {
                        advancedFeatureBadge(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Graph 2-hop",
                            detail: graphEntitiesExtracted > 0 ? "\(graphEntitiesExtracted) entities" : nil,
                            color: .orange,
                            tooltip: "Entity extraction + relationship search"
                        )
                    }
                }
            }
        }
    }

    private func advancedFeatureBadge(
        icon: String,
        title: String,
        detail: String?,
        color: Color,
        tooltip: String
    ) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 9, weight: .semibold)
            Text(title)
                .scaledFont(size: 9, weight: .semibold)
            if let detail {
                Text("•")
                    .scaledFont(size: 5)
                    .opacity(0.6)
                Text(detail)
                    .scaledFont(size: 8, weight: .medium)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .help(tooltip)
    }

    private var diversityDescriptionFull: String {
        if mmrDiversity >= 0.8 { return "High – pulls from varied sources to give broader perspective" }
        if mmrDiversity >= 0.5 { return "Balanced – mix of relevance and source variety" }
        return "Low – focuses on most relevant matches only"
    }

}
