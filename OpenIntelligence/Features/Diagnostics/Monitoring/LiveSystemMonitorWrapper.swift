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
            // The shared header and tiles of Device & Performance (5.8); the thermal state lives here, the hardware facts
            // on Active Device above.
            SettingsSectionHeader(
                icon: "gauge.with.dots.needle.bottom.50percent", title: "Live System Monitor", badge: "Live",
                badgeColor: .green, live: true)

            LazyVGrid(columns: SpecTile.columns, spacing: DSSpacing.xs) {
                // Thermal: Apple's ProcessInfo.ThermalState terms.
                SpecTile(
                    name: "Thermals", value: state.thermalStateName,
                    icon: SystemStateMonitor.thermalIcon(for: state.thermalState),
                    caption: thermalDetailText(state.thermalState),
                    tint: state.thermalState == .nominal ? nil : thermalStateColor(state.thermalState))
                SpecTile(
                    name: "Battery", value: state.batteryDisplayString,
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    caption: state.isCharging ? "Charging" : batteryDetailText(state))
                SpecTile(
                    name: "Free memory", value: formatMemorySize(state.availableMemoryMB), icon: state.memoryPressure.icon,
                    caption: state.memoryPressure.rawValue)
                SpecTile(
                    name: "Pipeline", value: state.optimizationLevel.displayName, icon: "slider.horizontal.3",
                    caption: pipelineDetailText(state.optimizationLevel))
                SpecTile(
                    name: "Cores active", value: "\(state.activeProcessorCount) of \(state.processorCount)", icon: "cpu",
                    caption: "the system reports")
                SpecTile(
                    name: "Low Power", value: state.isLowPowerModeEnabled ? "On" : "Off", icon: "leaf",
                    caption: "Low Power Mode",
                    tint: state.isLowPowerModeEnabled ? .orange : nil)
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
                    Text("All systems nominal: full performance")
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
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helper Views

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
