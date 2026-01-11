//
//  DeviceCapabilityService.swift
//  OpenIntelligence
//
//  Detects device hardware capabilities to optimize RAG/LLM configuration.
//  Adjusts agentic loop parameters based on chipset generation.
//

import Foundation
import UIKit

/// Device capability tiers for Apple Intelligence
enum DeviceCapabilityTier: String, Sendable, Comparable {
    case baseline // A17 Pro (iPhone 15 Pro/Pro Max) - first Apple Intelligence
    case enhanced // A18/A18 Pro (iPhone 16 series) - improved NPU
    case advanced // A19/A19 Pro (iPhone 17 series) - next-gen
    case ultraAdvanced // Future devices (A20+, M-series iPads)
    case unsupported // Devices without Apple Intelligence

    static func < (lhs: DeviceCapabilityTier, rhs: DeviceCapabilityTier) -> Bool {
        let order: [DeviceCapabilityTier] = [.unsupported, .baseline, .enhanced, .advanced, .ultraAdvanced]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .baseline: return "Standard"
        case .enhanced: return "Enhanced"
        case .advanced: return "Advanced"
        case .ultraAdvanced: return "Ultra"
        case .unsupported: return "Not Supported"
        }
    }

    /// Approximate NPU TOPS (Tera Operations Per Second)
    var estimatedNPUTops: Int {
        switch self {
        case .baseline: return 35 // A17 Pro
        case .enhanced: return 38 // A18 Pro (estimated)
        case .advanced: return 45 // A19 Pro (projected)
        case .ultraAdvanced: return 55 // Future
        case .unsupported: return 0
        }
    }
}

/// Device form factor
enum DeviceFormFactor: String, Sendable {
    case iPhone
    case iPadMini // 8.3" - portable but limited screen
    case iPadAir // 10.9"-13" - balanced
    case iPadPro // 11"-13" - maximum performance
    case unknown

    /// Whether device has active cooling (only M-series iPads)
    var hasActiveCooling: Bool {
        self == .iPadPro
    }

    /// Recommended max concurrent operations
    var recommendedConcurrency: Int {
        switch self {
        case .iPhone: return 2
        case .iPadMini: return 2
        case .iPadAir: return 3
        case .iPadPro: return 4
        case .unknown: return 2
        }
    }
}

/// Comprehensive device capability detection
final class DeviceCapabilityService: @unchecked Sendable {
    static let shared = DeviceCapabilityService()

    private let cachedTier: DeviceCapabilityTier
    private let cachedChipName: String
    private let cachedMemoryGB: Double
    private let cachedFormFactor: DeviceFormFactor
    private let cachedDeviceIdentifier: String

    private init() {
        let (tier, chip, formFactor, identifier) = Self.detectFullCapability()
        cachedTier = tier
        cachedChipName = chip
        cachedFormFactor = formFactor
        cachedDeviceIdentifier = identifier
        cachedMemoryGB = Self.detectMemoryGB()
    }

    // MARK: - Public API

    /// Current device capability tier
    var tier: DeviceCapabilityTier { cachedTier }

    /// Chip name (e.g., "A17 Pro", "A18", "M2")
    var chipName: String { cachedChipName }

    /// Available RAM in GB
    var memoryGB: Double { cachedMemoryGB }

    /// Device form factor (iPhone, iPad mini, iPad Air, iPad Pro)
    var formFactor: DeviceFormFactor { cachedFormFactor }

    /// Raw device identifier (e.g., "iPhone17,1", "iPad16,3")
    var deviceIdentifier: String { cachedDeviceIdentifier }

    /// Whether this is an iPad
    var isIPad: Bool {
        cachedFormFactor != .iPhone && cachedFormFactor != .unknown
    }

    /// Whether device has thermal headroom for sustained workloads
    var hasThermalHeadroom: Bool {
        // iPads have more thermal mass, iPad Pro has fan
        isIPad || cachedTier >= .advanced
    }

    /// Whether Apple Intelligence is available on this device
    var supportsAppleIntelligence: Bool {
        cachedTier != .unsupported
    }

    /// Maximum recommended concurrent agentic steps
    var maxConcurrentAgenticSteps: Int {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 3 // Conservative for A17 Pro
        case .enhanced: return 5 // A18 has better thermal headroom
        case .advanced: return 6 // A19 projected
        case .ultraAdvanced: return 8 // M-series / future
        }
    }

    /// Maximum recommended total tokens for agentic loop
    var maxAgenticTokenBudget: Int {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 16000 // ~4 sessions
        case .enhanced: return 24000 // ~6 sessions
        case .advanced: return 32000 // ~8 sessions
        case .ultraAdvanced: return 48000 // ~12 sessions
        }
    }

    /// Recommended delay between agentic steps (thermal management)
    var agenticStepCooldownMs: UInt64 {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 200 // Longer cooldown for A17 Pro
        case .enhanced: return 100 // A18 has better thermals
        case .advanced: return 50 // A19 projected
        case .ultraAdvanced: return 0 // M-series can go full speed
        }
    }

    /// Whether to prefer PCC for complex agentic queries
    var preferPCCForAgentic: Bool {
        // Baseline devices should offload to PCC when available
        cachedTier == .baseline
    }

    /// Get optimized AgenticConfig for current device
    func optimizedAgenticConfig() -> AgenticConfig {
        switch cachedTier {
        case .unsupported:
            return .fast // Shouldn't happen, but fallback

        case .baseline:
            // A17 Pro: Conservative settings to prevent thermal throttling
            return AgenticConfig(
                maxSteps: 4,
                maxTotalTokens: 16000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.80 // Stop earlier to save battery
            )

        case .enhanced:
            // A18/A18 Pro: Balanced performance
            return AgenticConfig(
                maxSteps: 6,
                maxTotalTokens: 24000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.85
            )

        case .advanced:
            // A19/A19 Pro: More aggressive
            return AgenticConfig(
                maxSteps: 8,
                maxTotalTokens: 32000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.90
            )

        case .ultraAdvanced:
            // M-series / future: Full power
            return AgenticConfig(
                maxSteps: 10,
                maxTotalTokens: 48000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.95
            )
        }
    }

    // MARK: - Detection Logic

    private static func detectFullCapability() -> (DeviceCapabilityTier, String, DeviceFormFactor, String) {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // iPhone detection
        if identifier.hasPrefix("iPhone") {
            let (tier, chip) = detectiPhoneCapability(identifier: identifier)
            return (tier, chip, .iPhone, identifier)
        }

        // iPad detection
        if identifier.hasPrefix("iPad") {
            let (tier, chip, formFactor) = detectiPadCapabilityFull(identifier: identifier)
            return (tier, chip, formFactor, identifier)
        }

        // Simulator fallback
        #if targetEnvironment(simulator)
            if let simDevice = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                if simDevice.hasPrefix("iPhone") {
                    let (tier, chip) = detectiPhoneCapability(identifier: simDevice)
                    return (tier, chip, .iPhone, simDevice)
                }
                if simDevice.hasPrefix("iPad") {
                    let (tier, chip, formFactor) = detectiPadCapabilityFull(identifier: simDevice)
                    return (tier, chip, formFactor, simDevice)
                }
            }
            // Default simulator to enhanced for testing
            return (.enhanced, "Simulator (A18 Simulated)", .iPhone, "Simulator")
        #else
            return (.unsupported, "Unknown", .unknown, identifier)
        #endif
    }

    private static func detectCapabilityTier() -> (DeviceCapabilityTier, String) {
        let (tier, chip, _, _) = detectFullCapability()
        return (tier, chip)
    }

    private static func detectiPhoneCapability(identifier: String) -> (DeviceCapabilityTier, String) {
        // Extract major/minor version numbers from identifier
        // Format: iPhoneXX,Y where XX is major generation
        let numbers = identifier.replacingOccurrences(of: "iPhone", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            return (.unsupported, "iPhone (Unknown)")
        }

        let major = numbers[0]
        let minor = numbers[1]

        // iPhone generations (major number in identifier):
        // iPhone 15 Pro/Pro Max: iPhone16,1 / iPhone16,2 (A17 Pro)
        // iPhone 15/15 Plus: iPhone15,4 / iPhone15,5 (A16 - NOT AI capable)
        // iPhone 16 series: iPhone17,x (A18/A18 Pro)
        // iPhone 17 series: iPhone18,x (A19/A19 Pro) - projected

        switch major {
        case 16:
            // iPhone 15 Pro (16,1) and Pro Max (16,2) have A17 Pro
            if minor <= 2 {
                return (.baseline, "A17 Pro")
            }
            // iPhone 15 (16,3) and 15 Plus (16,4) have A16 - NOT AI capable
            return (.unsupported, "A16 Bionic")

        case 17:
            // iPhone 16 series (2024)
            // Pro models (17,1 and 17,2) have A18 Pro
            // Standard models (17,3 and 17,4) have A18
            if minor <= 2 {
                return (.enhanced, "A18 Pro")
            }
            return (.enhanced, "A18")

        case 18:
            // iPhone 17 series (2025) - projected
            if minor <= 2 {
                return (.advanced, "A19 Pro")
            }
            return (.advanced, "A19")

        case 19...:
            // Future iPhones
            return (.ultraAdvanced, "A\(major + 1) Pro")

        default:
            return (.unsupported, "Legacy iPhone")
        }
    }

    private static func detectiPadCapability(identifier: String) -> (DeviceCapabilityTier, String) {
        // iPad detection - M-series chips are all capable
        let numbers = identifier.replacingOccurrences(of: "iPad", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            return (.unsupported, "iPad (Unknown)")
        }

        let major = numbers[0]
        let minor = numbers[1]

        // Comprehensive iPad model mapping:
        // iPad13,4-11 = iPad Pro M1 (2021) - 11" and 12.9"
        // iPad14,1-2 = iPad mini 6 (A15 - NOT Apple Intelligence capable)
        // iPad14,3-6 = iPad Pro M2 (2022) - 11" and 12.9"
        // iPad14,8-9 = iPad Air M2 (2024) - 11" and 13"
        // iPad15,3-6 = iPad Air M3 (2025) - projected
        // iPad16,3-6 = iPad Pro M4 (2024) - 11" and 13" OLED
        // iPad17+ = Future iPads

        switch major {
        case 13:
            // iPad Pro M1 (2021) - capable but older
            if minor >= 4 {
                return (.enhanced, "M1")
            }
            return (.unsupported, "Legacy iPad")

        case 14:
            // iPad mini 6 (14,1-2) has A15 - NOT capable
            if minor <= 2 {
                return (.unsupported, "A15 Bionic")
            }
            // iPad Pro M2 (14,3-6) - 2022
            if minor >= 3, minor <= 6 {
                return (.ultraAdvanced, "M2")
            }
            // iPad Air M2 (14,8-9) - 2024
            if minor >= 8 {
                return (.enhanced, "M2")
            }
            return (.unsupported, "Unknown iPad14")

        case 15:
            // iPad Air M3 (2025) - projected
            return (.advanced, "M3")

        case 16:
            // iPad Pro M4 (2024) - OLED models
            if minor >= 3, minor <= 6 {
                return (.ultraAdvanced, "M4")
            }
            return (.ultraAdvanced, "M4")

        case 17...:
            // Future iPads - assume ultra advanced
            return (.ultraAdvanced, "M-series")

        default:
            return (.unsupported, "Legacy iPad")
        }
    }

    /// Full iPad detection returning tier, chip, AND form factor
    private static func detectiPadCapabilityFull(identifier: String) -> (DeviceCapabilityTier, String, DeviceFormFactor) {
        let numbers = identifier.replacingOccurrences(of: "iPad", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            return (.unsupported, "iPad (Unknown)", .iPadAir)
        }

        let major = numbers[0]
        let minor = numbers[1]

        // Comprehensive iPad model mapping with form factors:
        // iPad13,4-11 = iPad Pro M1 (2021) - 11" and 12.9"
        // iPad14,1-2 = iPad mini 6 (A15 - NOT Apple Intelligence capable)
        // iPad14,3-6 = iPad Pro M2 (2022) - 11" and 12.9"
        // iPad14,8-9 = iPad Air M2 (2024) - 11" and 13"
        // iPad15,3-6 = iPad Air M3 (2025) - projected
        // iPad16,3-6 = iPad Pro M4 (2024) - 11" and 13" OLED
        // iPad17+ = Future iPads

        switch major {
        case 13:
            // iPad Pro M1 (2021)
            if minor >= 4 {
                return (.enhanced, "M1", .iPadPro)
            }
            return (.unsupported, "Legacy iPad", .iPadAir)

        case 14:
            // iPad mini 6 (14,1-2) has A15
            if minor <= 2 {
                return (.unsupported, "A15 Bionic", .iPadMini)
            }
            // iPad Pro M2 (14,3-6) - 2022
            if minor >= 3, minor <= 6 {
                return (.ultraAdvanced, "M2", .iPadPro)
            }
            // iPad Air M2 (14,8-9) - 2024
            if minor >= 8 {
                return (.enhanced, "M2", .iPadAir)
            }
            return (.unsupported, "Unknown iPad14", .iPadAir)

        case 15:
            // iPad Air M3 (2025) - projected
            return (.advanced, "M3", .iPadAir)

        case 16:
            // iPad Pro M4 (2024) - OLED models
            return (.ultraAdvanced, "M4", .iPadPro)

        case 17...:
            // Future iPads - assume Pro tier
            return (.ultraAdvanced, "M-series", .iPadPro)

        default:
            return (.unsupported, "Legacy iPad", .iPadAir)
        }
    }

    private static func detectMemoryGB() -> Double {
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        return Double(memoryBytes) / (1024 * 1024 * 1024)
    }
}

// MARK: - AgenticOrchestrator Integration

extension AgenticOrchestrator {
    /// Create an orchestrator with device-optimized configuration
    static func createOptimized(for ragService: RAGService) -> AgenticOrchestrator {
        let config = DeviceCapabilityService.shared.optimizedAgenticConfig()
        return AgenticOrchestrator(ragService: ragService, config: config)
    }
}

// MARK: - Logging

extension DeviceCapabilityService {
    /// Log device capabilities at startup
    func logCapabilities() {
        Log.info("""
        [Device] Capability Detection:
        • Tier: \(tier.displayName) (\(tier.rawValue))
        • Chip: \(chipName)
        • Memory: \(String(format: "%.1f", memoryGB)) GB
        • NPU: ~\(tier.estimatedNPUTops) TOPS
        • Apple Intelligence: \(supportsAppleIntelligence ? "✓" : "✗")
        • Max Agentic Steps: \(maxConcurrentAgenticSteps)
        • Token Budget: \(maxAgenticTokenBudget)
        """, category: .initialization)
    }
}
