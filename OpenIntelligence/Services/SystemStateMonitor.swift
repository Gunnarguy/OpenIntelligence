//
//  SystemStateMonitor.swift
//  OpenIntelligence
//
//  Centralized real-time monitoring of all device state metrics.
//  Exposes every relevant Apple API metric for transparency.
//

import Combine
import Foundation
import UIKit

// MARK: - System State Snapshot

/// Complete snapshot of current device state
struct SystemStateSnapshot: Sendable, Equatable {
    // Thermal
    let thermalState: ProcessInfo.ThermalState
    let thermalStateName: String

    // Battery
    let batteryLevel: Float // 0.0-1.0, -1 if unknown
    let batteryState: UIDevice.BatteryState
    let isCharging: Bool
    let isFullyCharged: Bool

    // Memory
    let availableMemoryBytes: UInt64
    let totalMemoryBytes: UInt64
    let memoryUsageRatio: Double
    let memoryPressure: MemoryPressureLevel

    // CPU/Performance
    let processorCount: Int
    let activeProcessorCount: Int
    let isLowPowerModeEnabled: Bool

    // System
    let systemUptime: TimeInterval
    let osVersion: String
    let deviceModel: String

    // Pipeline optimization
    let optimizationLevel: PipelineOptimizationLevel
    let isConstrained: Bool

    // Computed
    var batteryPercent: Int {
        batteryLevel >= 0 ? Int(batteryLevel * 100) : -1
    }

    /// Display string for battery - handles Mac/desktop where battery info unavailable
    var batteryDisplayString: String {
        if batteryLevel < 0 {
            // On Mac or devices without battery info
            return "Plugged In"
        }
        return "\(batteryPercent)%"
    }

    var availableMemoryMB: Int {
        Int(availableMemoryBytes / 1024 / 1024)
    }

    var memoryUsagePercent: Int {
        Int(memoryUsageRatio * 100)
    }

    /// Human-readable summary
    var summary: String {
        var parts: [String] = []
        parts.append("🌡️ \(thermalStateName)")
        if batteryLevel >= 0 {
            parts.append("🔋 \(batteryPercent)%\(isCharging ? "⚡" : "")")
        } else {
            // Mac or device without battery - show as plugged in
            parts.append("🔌 Plugged In")
        }
        parts.append("💾 \(availableMemoryMB)MB free")
        if isLowPowerModeEnabled {
            parts.append("🔅 LPM")
        }
        return parts.joined(separator: " • ")
    }

    /// Whether any metric is in a warning/critical state
    var hasWarning: Bool {
        thermalState == .serious ||
            thermalState == .critical ||
            memoryPressure == .warning ||
            memoryPressure == .critical ||
            (batteryLevel >= 0 && batteryLevel < 0.10 && !isCharging) ||
            isLowPowerModeEnabled
    }

    /// Whether any metric is in a critical state
    var hasCritical: Bool {
        thermalState == .critical ||
            memoryPressure == .critical ||
            (batteryLevel >= 0 && batteryLevel < 0.05 && !isCharging)
    }
}

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: String, Sendable {
    case nominal = "Nominal"
    case warning = "Warning"
    case critical = "Critical"

    var icon: String {
        switch self {
        case .nominal: return "memorychip"
        case .warning: return "memorychip.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .nominal: return "green"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

// MARK: - System State Monitor

/// Real-time monitor for all device state metrics
@MainActor
final class SystemStateMonitor: ObservableObject {
    // MARK: - Singleton

    static let shared = SystemStateMonitor()

    // MARK: - Published State

    @Published private(set) var currentState: SystemStateSnapshot
    @Published private(set) var stateHistory: [SystemStateSnapshot] = []

    /// How often to capture state (seconds)
    private let captureInterval: TimeInterval = 2.0
    private let maxHistoryCount = 60 // Keep last 2 minutes

    // MARK: - Private

    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var batteryLevelObserver: NSObjectProtocol?
    private var batteryStateObserver: NSObjectProtocol?
    private var lowPowerObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?

    // MARK: - Initialization

    private init() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Capture initial state
        currentState = Self.captureState()

        // Setup observers
        setupObservers()

        // Start periodic capture
        startPeriodicCapture()
    }

    deinit {
        timer?.invalidate()
        [thermalObserver, batteryLevelObserver, batteryStateObserver, lowPowerObserver, memoryObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public API

    /// Force refresh of state
    func refresh() {
        updateState()
    }

    /// Get thermal state color
    static func thermalColor(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "green"
        case .fair: return "blue"
        case .serious: return "orange"
        case .critical: return "red"
        @unknown default: return "gray"
        }
    }

    /// Get thermal icon
    static func thermalIcon(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "thermometer.sun.fill"
        @unknown default: return "thermometer"
        }
    }

    /// Get battery icon
    static func batteryIcon(level: Float, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        if level < 0 {
            return "battery.0percent"
        }
        if level < 0.10 {
            return "battery.0percent"
        }
        if level < 0.25 {
            return "battery.25percent"
        }
        if level < 0.50 {
            return "battery.50percent"
        }
        if level < 0.75 {
            return "battery.75percent"
        }
        return "battery.100percent"
    }

    // MARK: - Private Helpers

    private static func captureState() -> SystemStateSnapshot {
        let processInfo = ProcessInfo.processInfo
        let device = UIDevice.current

        // Thermal
        let thermal = processInfo.thermalState
        let thermalName: String = {
            switch thermal {
            case .nominal: return "Nominal"
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }()

        // Battery - Mac detection needed because iOS battery API often returns garbage on Mac
        let isMac = DeviceCapabilityService.shared.isMac || processInfo.isiOSAppOnMac
        let rawBatteryLevel = device.batteryLevel
        let rawBatteryState = device.batteryState

        let batteryLevel: Float
        let batteryState: UIDevice.BatteryState
        let isCharging: Bool
        let isFullyCharged: Bool

        if isMac {
            // On Mac, check if battery values look like garbage
            let looksLikeGarbage = rawBatteryState == .unknown ||
                rawBatteryLevel < 0 ||
                (rawBatteryLevel < 0.05 && rawBatteryState != .unplugged)

            if looksLikeGarbage {
                // Garbage values - assume full power (desktop Mac or broken API)
                batteryLevel = 1.0
                batteryState = .full
                isCharging = true
                isFullyCharged = true
            } else {
                // Values look plausible - trust them (MacBook with working battery API)
                batteryLevel = rawBatteryLevel
                batteryState = rawBatteryState
                isCharging = rawBatteryState == .charging || rawBatteryState == .full
                isFullyCharged = rawBatteryState == .full
            }
        } else {
            batteryLevel = rawBatteryLevel
            batteryState = rawBatteryState
            isCharging = rawBatteryState == .charging || rawBatteryState == .full
            isFullyCharged = rawBatteryState == .full
        }

        // Memory
        let availableMemory = UInt64(os_proc_available_memory())
        let totalMemory = processInfo.physicalMemory
        let memoryRatio = 1.0 - (Double(availableMemory) / Double(totalMemory))

        let memoryPressure: MemoryPressureLevel
        let availableRatio = Double(availableMemory) / Double(totalMemory)
        if availableRatio < 0.10 {
            memoryPressure = .critical
        } else if availableRatio < 0.20 {
            memoryPressure = .warning
        } else {
            memoryPressure = .nominal
        }

        // CPU
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        let isLowPowerMode = processInfo.isLowPowerModeEnabled

        // System
        let uptime = processInfo.systemUptime
        let osVersion = "\(processInfo.operatingSystemVersionString)"
        let deviceModel = device.model

        // Pipeline
        let optimizer = AdaptivePipelineOptimizer.shared
        let optimizationLevel = optimizer.currentOptimizationLevel
        let isConstrained = optimizer.currentState.isConstrained

        return SystemStateSnapshot(
            thermalState: thermal,
            thermalStateName: thermalName,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            availableMemoryBytes: availableMemory,
            totalMemoryBytes: totalMemory,
            memoryUsageRatio: memoryRatio,
            memoryPressure: memoryPressure,
            processorCount: processorCount,
            activeProcessorCount: activeProcessorCount,
            isLowPowerModeEnabled: isLowPowerMode,
            systemUptime: uptime,
            osVersion: osVersion,
            deviceModel: deviceModel,
            optimizationLevel: optimizationLevel,
            isConstrained: isConstrained
        )
    }

    private func updateState() {
        let newState = Self.captureState()
        currentState = newState

        // Add to history
        stateHistory.append(newState)
        if stateHistory.count > maxHistoryCount {
            stateHistory.removeFirst(stateHistory.count - maxHistoryCount)
        }
    }

    private func setupObservers() {
        // Thermal state changes (immediate update)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }

        // Battery level changes
        batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }

        // Battery state changes (charging, unplugged)
        batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }

        // Low power mode changes
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }

        // Memory warnings
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }
    }

    private func startPeriodicCapture() {
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState()
            }
        }
    }
}

// MARK: - Extensions

extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

extension UIDevice.BatteryState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }
}
