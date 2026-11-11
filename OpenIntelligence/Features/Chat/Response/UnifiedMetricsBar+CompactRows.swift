//
//  UnifiedMetricsBar+CompactRows.swift
//  OpenIntelligence
//
//  Part of UnifiedMetricsBar, moved from UnifiedMetricsBar.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI


extension UnifiedMetricsBar {
    // MARK: - Legacy Compact Row: Execution + Context (kept for reference)

    private var executionContextRow: some View {
        HStack(spacing: DSSpacing.md) {
            // Execution
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: execution.icon)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(execution.color)
                Text(execution.displayName)
                    .scaledFont(size: 11, weight: .semibold)
                if let modelName, !modelName.isEmpty {
                    Text("•")
                        .scaledFont(size: 6)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(modelName)
                        .scaledFont(size: 10)
                        .foregroundStyle(DSColors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Context gauge inline
            HStack(spacing: DSSpacing.xxs) {
                Text("Context:")
                    .scaledFont(size: 9)
                    .foregroundStyle(DSColors.secondaryText)
                Text("\(contextTokens)/\(maxContextTokens)")
                    .scaledFont(size: 10, weight: .medium, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(contextColor)

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(contextColor)
                            .frame(width: geo.size.width * contextUsageRatio)
                    }
                }
                .frame(width: 40, height: 4)
            }

            // TTFT if available
            if let t = ttft {
                Text(String(format: "%.0fms", t * 1000))
                    .scaledFont(size: 9, weight: .medium, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(t < 0.5 ? .green : .blue)
            }
        }
    }

    // MARK: - Compact Row: System Vitals

    private var systemVitalsRow: some View {
        let state = systemMonitor.currentState
        let device = DeviceCapabilityService.shared

        return HStack(spacing: DSSpacing.sm) {
            // Chip
            compactMetric(icon: "cpu", value: device.chipName, color: .purple)

            // Thermal
            compactMetric(
                icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                value: state.thermalStateName,
                color: systemStateThermalColor(state.thermalState)
            )

            // Memory
            compactMetric(
                icon: state.memoryPressure.icon,
                value: formatMemory(state.availableMemoryMB),
                color: memoryColor(pressure: state.memoryPressure)
            )

            // Battery
            if state.batteryLevel >= 0 {
                compactMetric(
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    value: "\(state.batteryPercent)%",
                    color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                )
            }

            // Neural Engine: Apple's own figure, shown only for the ten chips Apple published one for (5.8).
            if let tops = device.npuTops {
                compactMetric(
                    icon: "brain.head.profile",
                    value: "\(AppleDeviceCatalog.topsDescription(tops))T",
                    color: .blue
                )
            }

            Spacer()

            // Live indicator
            HStack(spacing: DSSpacing.xxs) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("Live")
                    .scaledFont(size: 8, weight: .medium)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    // MARK: - Compact Row: RAG Pipeline

    private var ragPipelineRow: some View {
        HStack(spacing: DSSpacing.sm) {
            // Mode
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: retrievalMode.icon)
                    .scaledFont(size: 9)
                Text(retrievalMode.rawValue)
                    .scaledFont(size: 10, weight: .semibold)
            }
            .foregroundStyle(retrievalMode.color)

            // Semantic/Lexical split bar
            HStack(spacing: DSSpacing.xxs) {
                Text("V:\(Int(vectorWeight * 100))")
                    .scaledFont(size: 8, weight: .medium, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(.blue)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue)
                            .frame(width: geo.size.width * vectorWeight)
                        Rectangle().fill(Color.orange)
                            .frame(width: geo.size.width * lexicalWeight)
                    }
                }
                .frame(width: 50, height: 4)
                .clipShape(Capsule())

                Text("L:\(Int(lexicalWeight * 100))")
                    .scaledFont(size: 8, weight: .medium, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }

            // Chunking
            if semanticChunksUsed {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "brain")
                        .scaledFont(size: 8)
                    Text("Semantic")
                        .scaledFont(size: 9, weight: .medium)
                }
                .foregroundStyle(.purple)
            }

            // MMR
            Text("MMR:\(String(format: "%.1f", mmrDiversity))")
                .scaledFont(size: 8, weight: .medium, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(.cyan)

            Spacer()

            // Silicon badge
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "bolt.horizontal.fill")
                    .scaledFont(size: 7)
                Text("vDSP")
                    .scaledFont(size: 8, weight: .medium)
            }
            .foregroundStyle(.cyan)
        }
        .padding(.vertical, DSSpacing.xxs)
        .padding(.horizontal, DSSpacing.sm)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

    // MARK: - Compact Row: Coverage

    private var coverageRow: some View {
        HStack(spacing: DSSpacing.md) {
            if sourceCount > 0 {
                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(sourceQualityColor)
                        .frame(width: 5, height: 5)
                    Text("\(sourceCount) sources")
                        .scaledFont(size: 10, weight: .medium)
                        .monospacedDigit()
                    if let avg = averageSourceScore {
                        Text("(\(String(format: "%.0f%%", avg * 100)) avg)")
                            .scaledFont(size: 9)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            if totalDocuments > 0 {
                Text("\(coveredDocuments)/\(totalDocuments) docs")
                    .scaledFont(size: 10, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            if totalChunks > 0 {
                Text("\(totalChunks) chunks")
                    .scaledFont(size: 10)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }

            if toolCallCount > 0 {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "wrench.and.screwdriver")
                        .scaledFont(size: 8)
                    Text("\(toolCallCount)")
                        .scaledFont(size: 10, weight: .medium)
                        .monospacedDigit()
                }
                .foregroundStyle(.purple)
            }

            Spacer()
        }
    }

    // MARK: - Compact Row: Warnings

    private var statusWarningsRow: some View {
        HStack(spacing: DSSpacing.sm) {
            if pccActive {
                miniWarning(icon: "cloud.fill", text: "PCC Active", color: .blue)
            }
            if cloudFallbackActive {
                miniWarning(icon: "iphone", text: "Local Fallback", color: .orange)
            }
            if systemMonitor.currentState.isConstrained {
                miniWarning(
                    icon: "exclamationmark.triangle.fill",
                    text: "Throttled: \(constraintReason(systemMonitor.currentState))",
                    color: .orange
                )
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func compactMetric(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 9, weight: .medium)
                .foregroundStyle(color)
            Text(value)
                .scaledFont(size: 10, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(DSColors.primaryText)
        }
    }

    @ViewBuilder
    private func miniWarning(icon: String, text: String, color: Color) -> some View {
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

    // MARK: - System State Detail Card (Legacy - kept for reference)

    private var systemStateDetailCard: some View {
        let state = systemMonitor.currentState
        let deviceService = DeviceCapabilityService.shared

        return VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.purple)
                Text("System State")
                    .scaledFont(size: 13, weight: .semibold)
                Spacer()
                // Live indicator
                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(.green)
                }
            }

            // 2-column grid for better readability
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DSSpacing.sm),
                GridItem(.flexible(), spacing: DSSpacing.sm),
            ], spacing: DSSpacing.sm) {
                // Thermal - Apple's exact terminology
                systemMetricCell(
                    icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                    label: "Thermal State",
                    value: state.thermalStateName,
                    detail: thermalDetail(state.thermalState),
                    color: systemStateThermalColor(state.thermalState)
                )

                // Battery
                systemMetricCell(
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    label: "Battery Level",
                    value: state.batteryDisplayString,
                    detail: batteryDetail(state),
                    color: batteryColor(level: state.batteryLevel, isCharging: state.isCharging)
                )

                // Memory
                systemMetricCell(
                    icon: state.memoryPressure.icon,
                    label: "Available RAM",
                    value: formatMemory(state.availableMemoryMB),
                    detail: state.memoryPressure.rawValue,
                    color: memoryColor(pressure: state.memoryPressure)
                )

                // Pipeline Mode
                systemMetricCell(
                    icon: "slider.horizontal.3",
                    label: "Pipeline Mode",
                    value: state.optimizationLevel.displayName,
                    detail: pipelineDetail(state.optimizationLevel),
                    color: pipelineColor(level: state.optimizationLevel)
                )

                // Chip
                systemMetricCell(
                    icon: "cpu",
                    label: "Processor",
                    value: deviceService.chipName,
                    detail: "\(state.activeProcessorCount)/\(state.processorCount) cores",
                    color: .purple
                )

                // Neural Engine: Apple's figure where it published one; the cell says so where it did not (5.8). The
                // detail was the app's internal tier name.
                systemMetricCell(
                    icon: "brain.head.profile",
                    label: "Neural Engine",
                    value: deviceService.npuTopsDescription ?? "No figure",
                    detail: deviceService.npuTops == nil ? "Apple publishes none" : "Apple's figure",
                    color: .blue
                )
            }

            // Status indicators row
            HStack(spacing: DSSpacing.md) {
                if state.isLowPowerModeEnabled {
                    statusPill(icon: "leaf.fill", text: "Low Power Mode", color: .orange)
                }

                // The live thermal state, not a fixed guess by device type (5.8).
                if state.thermalState == .nominal && !state.isConstrained {
                    statusPill(icon: "thermometer.snowflake", text: "Thermals nominal", color: .green)
                }

                if state.isCharging {
                    statusPill(icon: "bolt.fill", text: "Charging", color: .green)
                }

                Spacer()
            }

            // Constrained state warning
            if state.isConstrained {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(size: 12)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Pipeline Adjusted")
                            .scaledFont(size: 11, weight: .semibold)
                        Text(constraintReason(state))
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                .foregroundStyle(.orange)
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

}
