//
//  LiveSystemMonitorWrapper.swift
//  OpenIntelligence
//
//  Isolated view wrapper for SystemStateMonitor to prevent full SettingsView redraws.
//  The 2-second timer updates now only cause THIS view to re-render, not the entire SettingsView.
//

import SwiftUI

/// Wrapper view that isolates SystemStateMonitor's ObservableObject updates.
/// This prevents the 2-second timer from causing the entire SettingsView to re-render.
struct LiveSystemMonitorWrapper: View {
    @ObservedObject private var systemMonitor = SystemStateMonitor.shared

    var body: some View {
        let state = systemMonitor.currentState

        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header with live indicator
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Live System Monitor")
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: DSSpacing.xs) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DSColors.readable(.green))
                }
            }

            // Live metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DSSpacing.sm),
                GridItem(.flexible(), spacing: DSSpacing.sm),
            ], spacing: DSSpacing.sm) {
                // Thermal - Apple's official ProcessInfo.ThermalState terminology
                liveMetricCard(
                    icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                    label: "Thermal State",
                    value: state.thermalStateName,
                    detail: thermalDetailText(state.thermalState),
                    color: thermalStateColor(state.thermalState)
                )

                // Battery
                liveMetricCard(
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    label: "Battery Level",
                    value: state.batteryDisplayString,
                    detail: batteryDetailText(state),
                    color: batteryStateColor(level: state.batteryLevel, isCharging: state.isCharging)
                )

                // Memory
                liveMetricCard(
                    icon: state.memoryPressure.icon,
                    label: "Available RAM",
                    value: formatMemorySize(state.availableMemoryMB),
                    detail: state.memoryPressure.rawValue,
                    color: memoryPressureColor(state.memoryPressure)
                )

                // Pipeline Optimization
                liveMetricCard(
                    icon: "slider.horizontal.3",
                    label: "Pipeline Mode",
                    value: state.optimizationLevel.displayName,
                    detail: pipelineDetailText(state.optimizationLevel),
                    color: pipelineOptColor(state.optimizationLevel)
                )
            }

            // Status pills row
            HStack(spacing: DSSpacing.sm) {
                // Cores
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text("\(state.activeProcessorCount)/\(state.processorCount) cores")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xs)
                .background(DSColors.surfaceElevated)
                .clipShape(Capsule())

                if state.isLowPowerModeEnabled {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                        Text("Low Power")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(DSColors.readable(.orange))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(DSColors.chipBackground(for: .orange))
                    .clipShape(Capsule())
                }

                if state.isCharging {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("Charging")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(DSColors.readable(.green))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(DSColors.chipBackground(for: .green))
                    .clipShape(Capsule())
                }

                Spacer()
            }

            // Status message
            if state.isConstrained {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Pipeline Adjusted")
                            .font(.caption.weight(.semibold))
                        Text(constraintExplanation(state))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(DSColors.readable(.orange))
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColors.chipBackground(for: .orange))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            } else {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("All systems nominal — full performance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Tip about UnifiedMetricsBar
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                Text("Expand the metrics bar in chat for live stats during queries")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.top, DSSpacing.xxs)
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func liveMetricCard(icon: String, label: String, value: String, detail: String = "", color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Label row
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Value - prominent
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            // Detail if provided
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.chipBackground(for: color))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helper Functions

    private func thermalDetailText(_ thermal: ProcessInfo.ThermalState) -> String {
        switch thermal {
        case .nominal: return "Optimal performance"
        case .fair: return "Slightly elevated"
        case .serious: return "Throttling active"
        case .critical: return "Maximum throttling"
        @unknown default: return "Unknown state"
        }
    }

    private func batteryDetailText(_ state: SystemStateSnapshot) -> String {
        if state.isFullyCharged { return "Fully charged" }
        if state.isCharging { return "Charging" }
        if state.batteryLevel < 0.10 { return "Low battery" }
        if state.batteryLevel < 0.20 { return "Battery saver" }
        return "On battery"
    }

    private func formatMemorySize(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    private func pipelineDetailText(_ level: PipelineOptimizationLevel) -> String {
        switch level {
        case .full: return "All features enabled"
        case .balanced: return "Smart optimization"
        case .efficient: return "Power saving mode"
        case .minimal: return "Essential only"
        }
    }

    private func thermalStateColor(_ thermal: ProcessInfo.ThermalState) -> Color {
        switch thermal {
        case .nominal: return .green
        case .fair: return .accentColor
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    private func batteryStateColor(level: Float, isCharging: Bool) -> Color {
        if isCharging { return .green }
        if level < 0 { return .secondary }
        if level < 0.10 { return .red }
        if level < 0.25 { return .orange }
        return .green
    }

    private func memoryPressureColor(_ pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .nominal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func pipelineOptColor(_ level: PipelineOptimizationLevel) -> Color {
        switch level {
        case .full: return .green
        case .balanced: return .accentColor
        case .efficient: return .orange
        case .minimal: return .red
        }
    }

    private func constraintExplanation(_ state: SystemStateSnapshot) -> String {
        var reasons: [String] = []
        if state.thermalState == .serious || state.thermalState == .critical {
            reasons.append("thermal management")
        }
        if state.memoryPressure != .nominal {
            reasons.append("memory pressure")
        }
        if state.batteryLevel >= 0 && state.batteryLevel < 0.20 && !state.isCharging {
            reasons.append("battery preservation")
        }
        if state.isLowPowerModeEnabled {
            reasons.append("low power mode")
        }
        return reasons.isEmpty ? "device constraints" : reasons.joined(separator: ", ")
    }
}

#Preview {
    LiveSystemMonitorWrapper()
}
