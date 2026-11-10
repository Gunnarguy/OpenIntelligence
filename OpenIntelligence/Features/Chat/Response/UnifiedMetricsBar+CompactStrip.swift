//
//  UnifiedMetricsBar+CompactStrip.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Main Compact Strip (Premium Two-Row Layout)

    /// Three distinct visual treatments based on quality mode:
    /// - **Standard**: Blue theme, shows "Match" score (retrieval quality), single-pass indicator
    /// - **Deep Think**: Purple/cyan theme, shows "Confidence" building (3 sessions → 85% target)
    /// - **Maximum**: Gold/orange theme, shows "Confidence" meter (unlimited → 98% target)

    var mainCompactStrip: some View {
        VStack(spacing: DSSpacing.xs) {
            // Row 1: Primary metrics - adapts per mode. The mode's badges at the leading edge and the answer's figures
            // with the chevron at the trailing edge, each group going onto further lines when it does not fit: across
            // one line, up to eight fixed-size badges ran past the screen at the larger text sizes (5.7).
            // The chevron has its own place at the top trailing corner (5.7): inside the wrapping row it moved with
            // every badge's width and could land on the next line or over the detail text (owner, 2026-10-22).
            HStack(alignment: .top, spacing: DSSpacing.xs) {
            WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs, lastAtTrailingEdge: true) {
                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                    // 1. QUALITY MODE BADGE - Distinct per mode
                    premiumQualityBadge

                    // 2. SCORE INDICATOR - Different meaning per mode
                    if sourceCount > 0 || isProcessing {
                        modeAdaptiveScoreBadge
                    }

                    // 3. SESSIONS/PROGRESS - Only for Deep Think/Maximum
                    if isRecursiveRAG || isMaximumMode {
                        modeProgressIndicator
                    }

                    // 4. CONTEXT - Input tokens (only for Standard mode)
                    // Deep Think/Maximum use contextTokens for total agentic tokens, which is redundant
                    // with tokensGenerated - so we hide this badge for those modes
                    if contextTokens > 0 && !isRecursiveRAG && !isMaximumMode {
                        premiumContextBadge
                    }
                }

                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                    // 5. GENERATION STATS - Speed + output
                    if tokensGenerated > 0 || isProcessing {
                        premiumGenerationBadge
                    }

                    // 6. TIME
                    if elapsedTime > 0 || isProcessing {
                        premiumTimeBadge
                    }

                    // Thermal warning
                    let currentThermal = systemMonitor.currentState.thermalState
                    if currentThermal == .serious || currentThermal == .critical {
                        systemStateBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

                // Expand chevron
                Image(systemName: showExpandedDetails ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(DSColors.secondaryText)
                    .padding(.top, DSSpacing.xxs)
            }

            // Row 2: Mode-specific detail row
            modeSpecificDetailRow
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Mode-colored gradient border
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [qualityModeColor.opacity(0.4), .clear, qualityModeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .contentShape(Rectangle())
    }

    // MARK: - Mode-Specific Detail Row (Row 2)

    @ViewBuilder
    private var modeSpecificDetailRow: some View {
        if shouldShowLiveReasoning {
            liveReasoningDetailRow
        } else if isMaximumMode {
            // MAXIMUM: Show confidence progress bar toward 98% + session count
            maximumModeDetailRow
        } else if isRecursiveRAG {
            // DEEP THINK: Show reasoning chain progress + sparkline
            deepThinkDetailRow
        } else if speedHistory.count > 1 && (isProcessing || tokensGenerated > 0) {
            // STANDARD: Simple sparkline + sources
            standardModeDetailRow
        }
    }

    private var shouldShowLiveReasoning: Bool {
        isProcessing && (!liveReasoningTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !liveReasoningDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var liveReasoningSummary: String {
        let parts = [liveReasoningTitle, liveReasoningDetail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    private var liveReasoningAccent: Color {
        switch liveReasoningKind?.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "teal": return .teal
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "pink": return .pink
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return qualityModeColor
        }
    }

    private var liveReasoningDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: liveReasoningKind?.systemIconName ?? qualityMode.icon)
                    .scaledFont(size: 8, weight: .semibold)

                Text(isMaximumMode ? "Thinking" : isRecursiveRAG ? "Reasoning" : "Working")
                    .scaledFont(size: 8, weight: .bold)
                    .foregroundStyle(DSColors.primaryText)
            }
            .foregroundStyle(DSColors.readable(liveReasoningAccent))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(liveReasoningAccent.opacity(0.12))
            )

            Text(liveReasoningSummary)
                .scaledFont(size: 9, weight: .medium)
                .foregroundStyle(DSColors.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 0)

            if isMaximumMode || isRecursiveRAG {
                modeProgressIndicator
            } else if sourceCount > 0 {
                premiumSourcesBadge
            }
        }
    }

    private var standardModeDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            if sourceCount > 0 {
                premiumSourcesBadge
            }

            MiniSparkline(values: speedHistory, color: speedColor)
                .frame(height: 20)

            if toolCallCount > 0 {
                premiumToolsBadge
            }
        }
    }

    private var deepThinkDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Sources badge
            if sourceCount > 0 {
                premiumSourcesBadge
            }

            // Speed sparkline (purple for Deep Think)
            if speedHistory.count > 1 {
                MiniSparkline(values: speedHistory, color: .purple)
                    .frame(height: 20)
            }

            Spacer()

            if toolCallCount > 0 {
                premiumToolsBadge
            }
        }
    }

    private var maximumModeDetailRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Confidence progress bar toward 98%
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                            .frame(height: 6)

                        // Target marker at 98%
                        Capsule()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: geo.size.width * 0.98, height: 6)

                        // Current progress
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(liveConfidence)), height: 6)
                            .animation(DSAnimations.fastEase, value: liveConfidence)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: 100)

            Spacer()

            if speedHistory.count > 1 {
                MiniSparkline(values: speedHistory, color: .orange)
                    .frame(width: 50, height: 18)
            }

            if sourceCount > 0 {
                premiumSourcesBadge
            }
        }
    }

    // MARK: - Premium Badge: Quality Mode (The Brain)

    private var premiumQualityBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            // Animated brain icon
            ZStack {
                if isProcessing {
                    Circle()
                        .fill(qualityModeColor.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .scaleEffect(1.0 + sin(pulsePhase) * 0.15)
                        .animation(DSAnimations.stagePulse, value: pulsePhase)
                        .onAppear { pulsePhase = .pi * 2 }
                }
                Image(systemName: qualityMode.icon)
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(DSColors.readable(qualityModeColor))
            }

            Text(qualityModeLabel)
                .scaledFont(size: 9, weight: .bold)
                .foregroundStyle(DSColors.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(qualityModeColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(qualityModeColor.opacity(0.25), lineWidth: 0.5)
                )
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Retrieval Quality (Match Score)

    /// Mode-adaptive score badge:
    /// - Standard: "Match" - shows retrieval similarity (how well docs matched query)
    /// - Deep Think: "Confidence" - shows live reasoning confidence building to 85%
    /// - Maximum: "Confidence" - shows live agentic confidence building to 98%
    @ViewBuilder
    private var modeAdaptiveScoreBadge: some View {
        if isMaximumMode {
            // Maximum: Live confidence meter (orange/gold theme)
            maximumConfidenceBadge
        } else if isRecursiveRAG {
            // Deep Think: Live confidence (cyan theme)
            deepThinkConfidenceBadge
        } else {
            // Standard: Retrieval match quality (blue/green theme)
            standardMatchBadge
        }
    }

    private var standardMatchBadge: some View {
        let matchScore = computedMatchScore
        let matchPct = Int(matchScore * 100)
        let matchColor = matchScoreColor(matchScore)

        return HStack(spacing: DSSpacing.xxs) {
            // Circular match indicator
            ZStack {
                Circle()
                    .stroke(matchColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(matchScore))
                    .stroke(matchColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
            }

            Text("\(matchPct)%")
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(matchColor.opacity(0.1))
        )
        .fixedSize()
    }

    private var deepThinkConfidenceBadge: some View {
        let confidence = liveConfidence > 0 ? liveConfidence : 0.10
        let pct = Int(confidence * 100)
        // The confidence Deep Think aims for on this device (5.7): 0.85 on an A17 Pro up to 0.95 on M-series
        // (`optimizedAgenticConfig`). A fixed 0.85 showed the target reached while a Mac's run kept going.
        let target = DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold
        let targetReached = confidence >= target
        let color: Color = targetReached ? .green : .purple

        return HStack(spacing: DSSpacing.xxs) {
            // Circular confidence indicator
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(confidence / target, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
                    .animation(DSAnimations.fastEase, value: confidence)
            }

            Text("\(pct)%")
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            if targetReached {
                Image(systemName: "checkmark.circle.fill")
                    .scaledFont(size: 7)
                    .foregroundStyle(DSColors.readable(.green))
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .fixedSize()
    }

    private var maximumConfidenceBadge: some View {
        let confidence = liveConfidence
        let pct = Int(confidence * 100)
        let targetReached = confidence >= 0.98
        let color: Color = targetReached ? .green : .orange

        return HStack(spacing: DSSpacing.xxs) {
            // Circular confidence indicator
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(confidence / 0.98, 1.0)))
                    .stroke(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
                    .animation(DSAnimations.fastEase, value: confidence)
            }

            Text("\(pct)%")
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)

            if targetReached {
                Image(systemName: "star.fill")
                    .scaledFont(size: 7)
                    .foregroundStyle(DSColors.readable(.yellow))
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Mode Progress Indicator (Sessions/Depth)

    @ViewBuilder
    private var modeProgressIndicator: some View {
        if isMaximumMode {
            // Maximum: Unlimited sessions indicator
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "infinity")
                    .scaledFont(size: 7, weight: .bold)
                if maximumModeSessionCount > 0 {
                    Text("×\(maximumModeSessionCount)")
                        .scaledFont(size: 8, weight: .bold, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
            }
            .foregroundStyle(DSColors.readable(.orange))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.12))
            )
            .fixedSize()
        } else if isRecursiveRAG {
            // Deep Think: session count (no max - it goes until confident)
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "brain.head.profile")
                    .scaledFont(size: 7, weight: .semibold)
                Text("×\(recursiveCallCount)")
                    .scaledFont(size: 8, weight: .bold, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
            }
            .foregroundStyle(DSColors.readable(.purple))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.12))
            )
            .fixedSize()
        }
    }

    /// Computed match score from retrieval similarity, rescaled for user comprehension.
    /// The cross-encoder reranker min-max normalizes each batch's scores to the 0.10-0.90 range (`RAGEngine`).
    /// A score of 0.90 means "perfect match" but shows as 90% which confuses users.
    /// We rescale: (score - 0.10) / 0.80 → maps 0.10→0%, 0.50→50%, 0.90→100%
    private var computedMatchScore: Float {
        // Use actual retrieval quality metrics
        if topSimilarity > 0 {
            // Rescale reranker scores from [0.10, 0.90] to [0, 1] for intuitive display
            // This makes 0.90 (max reranker score) show as 100%
            let rescaled = max(0, (topSimilarity - 0.10) / 0.80)
            return min(1.0, rescaled)  // Cap at 100%
        } else if let avg = averageSourceScore, avg > 0 {
            // Also rescale averages from reranker
            let rescaled = max(0, (avg - 0.10) / 0.80)
            return min(1.0, rescaled)
        } else if sourceCount > 0 {
            return 0.5  // Default if we have sources but no score
        }
        return 0
    }

    func matchScoreColor(_ score: Float) -> Color {
        if score >= 0.75 { return .green }
        if score >= 0.55 { return .blue }
        if score >= 0.35 { return .orange }
        return .red
    }

    // MARK: - Premium Badge: Sessions (Reasoning Depth)

    private var premiumSessionsBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "brain.head.profile")
                .scaledFont(size: 7, weight: .semibold)
            Text("×\(recursiveCallCount)")
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(.purple))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                )
        )
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Premium Badge: Context (Input Tokens)

    private var premiumContextBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "arrow.down.doc.fill")
                .scaledFont(size: 7, weight: .semibold)
            Text(formatTokenCount(contextTokens))
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(contextColor))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(contextColor.opacity(0.1))
        )
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Premium Badge: Generation (Speed + Output + Words)

    private var premiumGenerationBadge: some View {
        HStack(spacing: DSSpacing.xs) {
            // Speed metric
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "bolt.fill")
                    .scaledFont(size: 7, weight: .bold)
                Text(String(format: "%.0f", tokensPerSecond))
                    .scaledFont(size: 8, weight: .bold, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
                Text("t/s")
                    .scaledFont(size: 6, weight: .medium)
                    .foregroundStyle(DSColors.primaryText)
                    .opacity(0.7)
            }
            .foregroundStyle(DSColors.readable(liveTokenMetricColor))
            .lineLimit(1)
            .fixedSize()

            // Divider + Output tokens
            if tokensGenerated > 0 || isProcessing {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 10)

                // Output token count
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: tokenCounterIcon)
                        .scaledFont(size: 7, weight: .semibold)
                    Text(formatTokenCount(tokensGenerated))
                        .scaledFont(size: 8, weight: .bold, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
                .foregroundStyle(DSColors.readable(tokenCounterColor))
                .lineLimit(1)
                .fixedSize()
            }

            // Cumulative word count (the big number!)
            if characterCount > 0 {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 10)

                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "character.cursor.ibeam")
                        .scaledFont(size: 7, weight: .semibold)
                    Text(formatLargeCount(characterCount))
                        .scaledFont(size: 8, weight: .bold, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                }
                .foregroundStyle(DSColors.readable(.purple))
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(liveTokenMetricColor.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(liveTokenMetricColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Premium Badge: Time

    private var premiumTimeBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: isProcessing ? "hourglass" : "checkmark.circle.fill")
                .scaledFont(size: 7, weight: .medium)
                .symbolEffect(.pulse, isActive: isProcessing)
            Text(formatElapsed(elapsedTime))
                .scaledFont(size: 8, weight: .semibold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(isProcessing ? .orange : .green))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill((isProcessing ? Color.orange : Color.green).opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Sources (Row 2)

    private var premiumSourcesBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "doc.text.magnifyingglass")
                .scaledFont(size: 7, weight: .semibold)
            Text("\(sourceCount)")
                .scaledFont(size: 8, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(sourceQualityColor))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(sourceQualityColor.opacity(0.1))
        )
        .fixedSize()
    }

    // MARK: - Premium Badge: Tools (Row 2)

    private var premiumToolsBadge: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .scaledFont(size: 8, weight: .semibold)
            Text("\(toolCallCount)")
                .scaledFont(size: 9, weight: .bold, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
        .foregroundStyle(DSColors.readable(.purple))
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
        )
    }

}
