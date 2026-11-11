//
//  UnifiedMetricsBar+RunSections.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Section: Where It's Running

    var whereRunningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: execution.icon)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(execution.color)
                Text("Processing Location")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            HStack(spacing: DSSpacing.md) {
                // Main execution info
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(executionExplanationFull)
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true) // Never truncate

                    if let modelName, !modelName.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "brain")
                                .scaledFont(size: 10)
                                .foregroundStyle(DSColors.secondaryText)
                            Text(modelName)
                                .scaledFont(size: 12)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }

                    // Privacy assurance
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: execution == .privateCloudCompute ? "lock.shield.fill" : "iphone")
                            .scaledFont(size: 10)
                            .foregroundStyle(.green)
                        Text(privacyExplanation)
                            .scaledFont(size: 11)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }

                Spacer()

                // Context usage (visual + text) - BUT NOT for Deep Think/Maximum which uses tokens
                if isRecursiveRAG {
                    // Deep Think / Maximum mode: Show tokens and sessions instead
                    // Use mode-appropriate color (purple for Deep Think, orange for Maximum)
                    let modeColor: Color = isMaximumMode ? .orange : .purple
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "arrow.trianglehead.branch")
                                    .scaledFont(size: 8)
                                    .foregroundStyle(modeColor)
                                Text("Multi-Session")
                                    .scaledFont(size: 10, weight: .medium)
                                    .foregroundStyle(DSColors.secondaryText)
                            }

                            HStack(spacing: DSSpacing.xs) {
                                // Sessions count
                                if recursiveCallCount > 0 {
                                    HStack(spacing: DSSpacing.xxs) {
                                        Text("\(recursiveCallCount)")
                                            .scaledFont(size: 14, weight: .bold, design: .monospaced)
                                            .monospacedDigit()
                                            .foregroundStyle(modeColor)
                                        Text("sessions")
                                            .scaledFont(size: 10)
                                            .foregroundStyle(DSColors.secondaryText)
                                    }
                                }
                            }

                            // Total tokens
                            if contextTokens > 0 {
                                HStack(spacing: DSSpacing.xxs) {
                                    Text(formatTokenCount(contextTokens))
                                        .scaledFont(size: 12, weight: .bold, design: .monospaced)
                                        .monospacedDigit()
                                        .foregroundStyle(modeColor)
                                    Text("tokens")
                                        .scaledFont(size: 10)
                                        .foregroundStyle(DSColors.secondaryText)
                                }
                            }
                        }

                        // Response time
                        if let t = ttft {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "clock.fill")
                                    .scaledFont(size: 10)
                                Text("First token in \(formatDuration(t))")
                                    .scaledFont(size: 11, weight: .medium)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(t < 0.5 ? .green : (t < 1.5 ? .blue : .orange))
                        }
                    }
                } else {
                    // Standard mode: Show context window usage
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        // Context bar with smart label
                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            HStack(spacing: DSSpacing.xxs) {
                                if hierarchicalChunkingActive {
                                    Image(systemName: "rectangle.3.group")
                                        .scaledFont(size: 8)
                                        .foregroundStyle(.cyan)
                                }
                                Text(hierarchicalChunkingActive ? "Smart Context" : "Context Window")
                                    .scaledFont(size: 10, weight: .medium)
                                    .foregroundStyle(DSColors.secondaryText)
                            }

                            HStack(spacing: DSSpacing.xs) {
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 70, height: 8)
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .fill(contextColor)
                                        .frame(width: 70 * contextUsageRatio, height: 8)
                                }

                                Text("\(Int(contextUsageRatio * 100))%")
                                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                                    .monospacedDigit()
                                    .foregroundStyle(contextColor)
                            }

                            Text(contextDetailLabel)
                                .scaledFont(size: 10)
                                .monospacedDigit()
                                .foregroundStyle(DSColors.secondaryText)
                        }

                        // Response time
                        if let t = ttft {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: "clock.fill")
                                    .scaledFont(size: 10)
                                Text("First token in \(formatDuration(t))")
                                    .scaledFont(size: 11, weight: .medium)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(t < 0.5 ? .green : (t < 1.5 ? .blue : .orange))
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(execution.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    var executionExplanationFull: String {
        let device = DeviceCapabilityService.shared
        switch execution {
        // Apple's 2024 research article on its on-device model says its key-value cache updates run on "our neural
        // engines" (machinelearning.apple.com/research/introducing-apple-foundation-models, read 2026-10-19), so the
        // Neural Engine is named. A 2026-10-18 change took it out after reading only the Foundation Models pages,
        // which name no chip, and was reverted the next day.
        // 5.8 review: an on-device answer can come from Quotes only, which runs no model, and the app cannot see which
        // unit Apple's model used, so the line names the chip and Apple's figure, not "Neural Engine" as the engine.
        case .onDevice:
            return "\(device.chipDisplayName) • on this device" + (device.npuTopsDescription.map { " • Neural Engine \($0)" } ?? "")
        case .privateCloudCompute:
            return "Private Cloud Compute • Encrypted"
        case .unknown:
            return device.chipDisplayName
        }
    }

    private var privacyExplanation: String {
        switch execution {
        case .onDevice:
            return "On-device only"
        case .privateCloudCompute:
            return "End-to-end encrypted"
        case .unknown:
            return "Private"
        }
    }

    // MARK: - Section: Agentic Tools Used

    var agenticToolsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("Agentic Tools")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                Text("\(toolCallCount) invoked")
                    .scaledFont(size: 11, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.purple)
            }

            let toolEvents = thinkingEvents.filter { $0.kind == .toolCall || $0.kind == .agentic }
            if !toolEvents.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(toolEvents) { event in
                        HStack(alignment: .top, spacing: DSSpacing.xs) {
                            Image(systemName: "circle.fill")
                                .scaledFont(size: 4)
                                .foregroundStyle(.purple.opacity(0.6))
                                .padding(.top, DSSpacing.xxs)
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(event.title)
                                    .scaledFont(size: 11, weight: .medium)
                                    .foregroundStyle(DSColors.primaryText)
                                if let detail = event.detail {
                                    Text(detail)
                                        .scaledFont(size: 10)
                                        .foregroundStyle(DSColors.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.top, DSSpacing.xxs)
            } else if toolCallCount > 0 {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "circle.fill")
                            .scaledFont(size: 4)
                            .foregroundStyle(.purple.opacity(0.6))
                            .padding(.top, DSSpacing.xxs)
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text("Vector Search Engine")
                                .scaledFont(size: 11, weight: .medium)
                                .foregroundStyle(DSColors.primaryText)
                            Text("The AI autonomously searched your documents and retrieved additional context.")
                                .scaledFont(size: 10)
                                .foregroundStyle(DSColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, DSSpacing.xxs)
            } else {
                Text("No additional tools were required to answer this query.")
                    .scaledFont(size: 11)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Section: How Smart It's Being

    private var howSmartSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("Search Intelligence")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Two-column layout for search methods
            HStack(spacing: DSSpacing.md) {
                // Meaning-based search
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("Meaning")
                            .scaledFont(size: 11, weight: .semibold)
                    }
                    Text("Finds similar ideas")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                    }
                    .frame(height: 6)
                    .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                    Text("\(Int(vectorWeight * 100))% weight")
                        .scaledFont(size: 10, weight: .medium, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)

                // Keyword-based search
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Keywords")
                            .scaledFont(size: 11, weight: .semibold)
                    }
                    Text("Matches exact words")
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)

                    // Visual bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                    .frame(height: 6)
                    .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                    Text("\(Int(lexicalWeight * 100))% weight")
                        .scaledFont(size: 10, weight: .medium, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            }

            // Bottom row: diversity setting
            HStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "shuffle")
                        .scaledFont(size: 10)
                        .foregroundStyle(.cyan)
                    Text("Diversity: \(diversityDescription)")
                        .scaledFont(size: 11)
                }

                if semanticChunksUsed {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .scaledFont(size: 10)
                            .foregroundStyle(.green)
                        Text("Smart chunking enabled")
                            .scaledFont(size: 11)
                    }
                }

                Spacer()
            }
            .foregroundStyle(DSColors.secondaryText)
        }
        .padding(DSSpacing.md)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private var diversityDescription: String {
        if mmrDiversity >= 0.8 { return "High (varied sources)" }
        if mmrDiversity >= 0.5 { return "Balanced" }
        return "Low (focused)"
    }

    // MARK: - Section: What It Found

    private var whatFoundSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Section header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.blue)
                Text("Search Results")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)
            }

            // Stats in readable format
            HStack(spacing: DSSpacing.lg) {
                if sourceCount > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(sourceCount)")
                                .scaledFont(size: 18, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(sourceQualityColor)
                            Text("sources used")
                                .scaledFont(size: 12)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        if let avg = averageSourceScore {
                            Text("\(sourceQualityLabel(avg)) relevance")
                                .scaledFont(size: 11)
                                .foregroundStyle(sourceQualityColor)
                        }
                    }
                }

                if totalDocuments > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xxs) {
                            Text("\(coveredDocuments)/\(totalDocuments)")
                                .scaledFont(size: 18, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                            Text("docs searched")
                                .scaledFont(size: 12)
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
                            Image(systemName: "wrench.and.screwdriver")
                                .scaledFont(size: 12)
                            Text("\(toolCallCount)")
                                .scaledFont(size: 18, weight: .bold, design: .rounded)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.purple)
                        Text("tools used")
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

    // MARK: - Section: Device Health

    private var deviceHealthSection: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header with live indicator
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.green)
                Text("Device Status")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DSColors.secondaryText)

                Spacer()

                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(.green)
                }
            }

            // Horizontal scroll of status pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    // Chip
                    statusPill(
                        icon: "cpu",
                        title: device.chipDisplayName,
                        subtitle: device.memoryDescription,
                        color: .purple
                    )

                    // Thermal
                    statusPill(
                        icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                        title: state.thermalStateName,
                        subtitle: thermalSubtitle(state.thermalState),
                        color: systemStateThermalColor(state.thermalState)
                    )

                    // Memory
                    statusPill(
                        icon: state.memoryPressure.icon,
                        title: formatMemory(state.availableMemoryMB),
                        subtitle: memorySubtitle(state.memoryPressure),
                        color: memoryColor(pressure: state.memoryPressure)
                    )

                    // Battery
                    if state.batteryLevel >= 0 {
                        statusPill(
                            icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                            title: "\(state.batteryPercent)%",
                            subtitle: state.isCharging ? "Charging" : "Battery",
                            color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                        )
                    }
                }
            }

            // Warnings (only if constrained - removed cloud status chips as they're not useful)
            if state.isConstrained {
                HStack(spacing: DSSpacing.sm) {
                    warningChip(
                        icon: "exclamationmark.triangle.fill",
                        text: "Performance reduced: \(constraintReason(state))",
                        color: .orange
                    )
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func thermalSubtitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Running cool"
        case .fair: return "Slightly warm"
        case .serious: return "Getting hot"
        case .critical: return "Throttling"
        @unknown default: return ""
        }
    }

    private func memorySubtitle(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .nominal: return "Plenty free"
        case .warning: return "Getting low"
        case .critical: return "Very low"
        }
    }

    private func statusPill(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .scaledFont(size: 12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.primaryText)
                Text(subtitle)
                    .scaledFont(size: 10)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }

    private func warningChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 10)
            Text(text)
                .scaledFont(size: 11, weight: .medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

}
