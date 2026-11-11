//
//  LiveSystemMonitorWrapper.swift
//  OpenIntelligence
//
//  Isolated view wrapper for SystemStateMonitor to prevent full SettingsView redraws.
//  The 2-second timer updates now only cause THIS view to re-render, not the entire SettingsView.
//

import SwiftUI

#if os(macOS)
    import IOKit.ps
#endif

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
                // On a Mac the shared state assumes mains power; the tile reads the Mac's own power source (5.8 review:
                // a desktop Mac showed "100%, Charging").
                SpecTile(
                    name: "Battery", value: Self.batteryValue(state),
                    icon: SystemStateMonitor.batteryIcon(level: state.batteryLevel, isCharging: state.isCharging),
                    caption: Self.batteryCaption(state))
                // On an iPhone or iPad this is the memory left for this app (`os_proc_available_memory`), not the
                // device's free memory (5.8 review); on a Mac it is the system's free memory.
                SpecTile(
                    name: Self.memoryTileName, value: formatMemorySize(state.availableMemoryMB), icon: state.memoryPressure.icon,
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

            // Status line (5.8 review): "Pipeline Adjusted" showed whenever a limit was near, even with the pipeline at full
            // quality, and "All systems nominal" showed in Low Power Mode. It now says what the pipeline is doing.
            let reasons = constraintReasons(state)
            if state.optimizationLevel != .full {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Pipeline adjusted")
                            .font(.caption.weight(.semibold))
                        Text(reasons.isEmpty ? pipelineDetailText(state.optimizationLevel) : reasons.joined(separator: ", "))
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
                    Text(reasons.isEmpty ? "Full quality" : "Full quality, with " + reasons.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // The tip that pointed at live stats in the metrics bar is gone (5.8 review): that panel shows none.
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helper Views

    // MARK: - Helper Functions

    private static var memoryTileName: String {
        #if os(iOS) && !targetEnvironment(simulator)
            return "Memory for app"
        #else
            return "Free memory"
        #endif
    }

    private func thermalDetailText(_ thermal: ProcessInfo.ThermalState) -> String {
        switch thermal {
        // Apple's own descriptions of ProcessInfo.ThermalState (5.8 review: "Throttling active" claimed an effect the
        // app does not apply at .serious).
        case .nominal: return "Within normal limits"
        case .fair: return "Slightly elevated"
        case .serious: return "High"
        case .critical: return "Hurting performance"
        @unknown default: return "Unknown state"
        }
    }

    private static func batteryValue(_ state: SystemStateSnapshot) -> String {
        #if os(macOS)
            return macPower().value
        #else
            return state.batteryLevel < 0 ? "Not reported" : "\(state.batteryPercent)%"
        #endif
    }

    private static func batteryCaption(_ state: SystemStateSnapshot) -> String {
        #if os(macOS)
            return macPower().caption
        #else
            if state.batteryLevel < 0 { return "no battery reading" }
            if state.isFullyCharged { return "Fully charged" }
            if state.isCharging { return "Charging" }
            return state.batteryLevel < 0.20 ? "On battery, low" : "On battery"
        #endif
    }

    #if os(macOS)
        /// The Mac's internal battery from IOKit's power sources, or "No battery" on a desktop Mac.
        private static func macPower() -> (value: String, caption: String) {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
            else { return ("Not reported", "no power reading") }
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                    description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
                else { continue }
                let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
                let percent = maximum > 0 ? current * 100 / maximum : current
                let charging = description[kIOPSIsChargingKey] as? Bool ?? false
                let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                return ("\(percent)%", charging ? "Charging" : (onAC ? "Plugged in" : "On battery"))
            }
            return ("No battery", "mains power")
        }
    #endif

    private func formatMemorySize(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    private func pipelineDetailText(_ level: PipelineOptimizationLevel) -> String {
        switch level {
        case .full: return "No adjustments"
        case .balanced: return "Some steps lighter"
        case .efficient: return "Power saving"
        case .minimal: return "Essential steps only"
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

    private func constraintReasons(_ state: SystemStateSnapshot) -> [String] {
        var reasons: [String] = []
        if state.thermalState == .serious || state.thermalState == .critical {
            reasons.append("the device hot")
        }
        if state.memoryPressure != .nominal {
            reasons.append("memory tight")
        }
        if state.batteryLevel >= 0 && state.batteryLevel < 0.20 && !state.isCharging {
            reasons.append("battery under 20%")
        }
        if state.isLowPowerModeEnabled {
            reasons.append("Low Power Mode on")
        }
        return reasons
    }
}

#Preview {
    LiveSystemMonitorWrapper()
}
