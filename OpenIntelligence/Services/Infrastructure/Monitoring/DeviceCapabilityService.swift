//
//  DeviceCapabilityService.swift
//  OpenIntelligence
//
//  Detects device hardware capabilities to optimize RAG/LLM configuration.
//  Adjusts agentic loop parameters based on chipset generation.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreML
import Metal

enum IngestionExecutionProfile: Sendable {
    case interactive
    case continuedProcessingCPUOnly
    case continuedProcessingGPU
}

/// User-facing execution preferences for GPU-capable work.
///
/// These are deliberately discrete: Apple frameworks retain final hardware scheduling control,
/// so a percentage would imply precision the app cannot guarantee.
enum GPUExecutionProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case efficiency
    case balanced
    case performance
    case maximum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .efficiency: return "Efficiency"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        // "Full Power" since 5.8 (the owner, 2026-11-11): "Maximum" is also an Intelligence Mode, and the two were
        // confused. The stored value stays "maximum", so a saved setting carries over.
        case .maximum: return "Full Power"
        }
    }

    /// Which compute units this profile permits, and what it changes.
    ///
    /// Exists so the picker can show the difference *before* a profile is chosen,
    /// and so the ladder can be asserted monotonic in tests: climbing it must never
    /// remove a unit. Maximum used to fail that, returning `.cpuAndGPU` for Core ML
    /// while Performance returned `.all`.
    struct Engagement: Equatable, Sendable {
        let usesCPU: Bool
        let usesNeuralEngine: Bool
        let usesGPU: Bool
        /// One sentence, in the user's terms, describing what selecting this does.
        let summary: String
        /// The concrete policy changes, for the expanded row.
        let effects: [String]

        var unitCount: Int {
            (usesCPU ? 1 : 0) + (usesNeuralEngine ? 1 : 0) + (usesGPU ? 1 : 0)
        }
    }

    /// What each profile changes, in the words Settings shows (5.7).
    ///
    /// The effects are built from the rules the app runs (`DeviceCapabilityService.coreMLComputeUnits(for:)`,
    /// `embeddingComputeUnits(for:)`, `cleansScannedPagesOnGPU(for:)` and `searchesLargeLibrariesOnGPU(for:)`), so the
    /// list can't say something the code doesn't do. Until 5.7 it was written by hand: Balanced said "answering stays on
    /// the Neural Engine", when this setting never touches how Apple's model answers; three profiles said "PDF pages
    /// render on the GPU", when the page's raster is CPU work on every device and the profile only adds or drops an
    /// extra Core Image pass over a rendered page (the cleanup that prepares every scanned page for text recognition,
    /// `DocumentProcessor.preprocessImageForOCR`, runs on its Metal context in every profile); and Maximum promised "Highest concurrency and GPU ceiling", when in the foreground it runs
    /// the same rules as Performance. What a profile changes in the background depends on the device, so Settings
    /// states that for the device it runs on (`BackgroundGPUAllowance`) rather than here.
    var engagement: Engagement {
        let searching = DeviceCapabilityService.coreMLComputeUnits(for: self)
        let importing = DeviceCapabilityService.embeddingComputeUnits(for: self)
        let cleanupOnGPU = DeviceCapabilityService.cleansScannedPagesOnGPU(for: self)
        let largeSearchesOnGPU = DeviceCapabilityService.searchesLargeLibrariesOnGPU(for: self)
        let modelUnits = [searching, importing]
        return Engagement(
            usesCPU: true,
            usesNeuralEngine: modelUnits.contains { $0 == .all || $0 == .cpuAndNeuralEngine },
            usesGPU: modelUnits.contains { $0 == .all || $0 == .cpuAndGPU } || cleanupOnGPU || largeSearchesOnGPU,
            summary: plainSummary,
            effects: [
                "Searching by meaning: \(Self.chipNames(searching))",
                "Importing: \(Self.chipNames(importing))",
                cleanupOnGPU ? "PDF pages: an extra cleanup pass on the GPU" : "PDF pages: no extra cleanup pass",
                "Large searches on the \(largeSearchesOnGPU ? "GPU" : "CPU")"
            ]
        )
    }

    /// One sentence for the selected profile, true of the rules `engagement` lists.
    private var plainSummary: String {
        switch self {
        case .efficiency:
            // 5.8 review: page preparation and a Mac's Core AI use the GPU in every profile, so "everything" was false.
            return "Coolest. The jobs this setting picks stay off the graphics processor, and imports do about half as much at once."
        case .balanced:
            return "The default. Imports can add the graphics processor, and PDF pages get an extra cleanup pass on it."
        case .performance:
            return "Searching and large searches can add the graphics processor too, and Standard searches go deeper."
        case .maximum:
            return "Performance, turned up where the device allows: full-detail pages and deeper search. Slower imports, warmer device."
        }
    }

    /// The chips a Core ML choice allows, in Settings' words. Core ML picks among them for each operation.
    nonisolated static func chipNames(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return "Neural Engine, GPU and CPU"
        case .cpuAndNeuralEngine: return "Neural Engine and CPU"
        case .cpuAndGPU: return "GPU and CPU"
        case .cpuOnly: return "CPU"
        @unknown default: return "the chips Core ML picks"
        }
    }

    /// Compatibility value retained for existing pipeline policy and older app versions.
    nonisolated var legacyLevel: Double {
        switch self {
        case .efficiency: return 0.0
        case .balanced: return 0.5
        case .performance: return 0.75
        case .maximum: return 1.0
        }
    }

    init(legacyLevel: Double) {
        switch min(max(legacyLevel, 0), 1) {
        case ..<0.3: self = .efficiency
        case ..<0.6: self = .balanced
        case ..<0.9: self = .performance
        default: self = .maximum
        }
    }
}

/// When an import that goes on in the background may ask iOS for the GPU, per device (5.7).
///
/// `BackgroundTaskService` applies it when it submits the import's `BGContinuedProcessingTaskRequest`, and Settings
/// states it for the device it runs on, so the two read one rule. iOS decides too: `BGTaskScheduler.supportedResources`
/// has to offer `.gpu` ("Not all devices support background GPU use", Apple's `BGContinuedProcessingTaskRequest.Resources.gpu`
/// page, read 2026-10-18), and Low Power Mode, a serious thermal state, critical memory pressure and the system's request
/// to use fewer resources each keep the GPU off (`BackgroundTaskService.continuedProcessingPolicy()`).
nonisolated struct BackgroundGPUAllowance: Equatable, Sendable {
    /// The GPU level a profile has to reach on this device, after the device's ceiling
    /// (`DeviceCapabilityService.maxSafeGPUAccelerationLevel(formFactor:tier:)`). Above 1, no profile reaches it.
    let requiredLevel: Double
    /// Below this battery percentage, when not charging, the import gets no GPU. -1 means no floor.
    let minimumBatteryPercent: Int
    /// Only while charging: an iPhone 15 Pro or Pro Max (A17 Pro).
    let chargingOnly: Bool

    static func forDevice(formFactor: DeviceFormFactor, tier: DeviceCapabilityTier) -> BackgroundGPUAllowance {
        switch formFactor {
        case .iPhone:
            switch tier {
            case .baseline:
                return BackgroundGPUAllowance(requiredLevel: 0.85, minimumBatteryPercent: 50, chargingOnly: true)
            case .enhanced:
                return BackgroundGPUAllowance(requiredLevel: 0.75, minimumBatteryPercent: 35, chargingOnly: false)
            case .advanced, .ultraAdvanced:
                return BackgroundGPUAllowance(requiredLevel: 0.65, minimumBatteryPercent: 35, chargingOnly: false)
            case .unsupported:
                return BackgroundGPUAllowance(requiredLevel: 1.1, minimumBatteryPercent: 35, chargingOnly: false)
            }
        case .iPadMini:
            return BackgroundGPUAllowance(requiredLevel: 0.8, minimumBatteryPercent: 40, chargingOnly: false)
        case .iPadAir:
            return BackgroundGPUAllowance(requiredLevel: 0.7, minimumBatteryPercent: 30, chargingOnly: false)
        case .iPadPro:
            return BackgroundGPUAllowance(requiredLevel: 0.6, minimumBatteryPercent: 25, chargingOnly: false)
        case .mac:
            return BackgroundGPUAllowance(requiredLevel: 0.6, minimumBatteryPercent: -1, chargingOnly: false)
        case .unknown:
            return BackgroundGPUAllowance(requiredLevel: 1.1, minimumBatteryPercent: 50, chargingOnly: false)
        }
    }

    /// The profiles that let a background import ask for the GPU on a device, lowest first.
    static func profiles(formFactor: DeviceFormFactor, tier: DeviceCapabilityTier) -> [GPUExecutionProfile] {
        let allowance = forDevice(formFactor: formFactor, tier: tier)
        let ceiling = DeviceCapabilityService.maxSafeGPUAccelerationLevel(formFactor: formFactor, tier: tier)
        return [GPUExecutionProfile.efficiency, .balanced, .performance, .maximum].filter { profile in
            min(profile.legacyLevel, ceiling) >= allowance.requiredLevel
        }
    }
}

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
        case .ultraAdvanced: return "Ultimate"
        case .unsupported: return "Not Supported"
        }
    }

}

/// Device form factor
enum DeviceFormFactor: String, Sendable {
    case iPhone
    case iPadMini // 8.3" - portable but limited screen
    case iPadAir // 10.9"-13" - balanced
    case iPadPro // 11"-13" - maximum performance
    case mac // MacBook Air, MacBook Pro, Mac mini, iMac, Mac Studio, Mac Pro
    case unknown

    /// The device in Settings' words (5.7).
    var deviceNoun: String {
        switch self {
        case .iPhone: return "iPhone"
        // One word for every iPad: the model detection maps some iPads to the wrong family (base iPads to Air or Pro).
        case .iPadMini, .iPadAir, .iPadPro: return "iPad"
        case .mac: return "Mac"
        case .unknown: return "device"
        }
    }

    /// Recommended max concurrent operations
    var recommendedConcurrency: Int {
        switch self {
        case .iPhone: return 2
        case .iPadMini: return 2
        case .iPadAir: return 3
        case .iPadPro: return 4
        case .mac: return 6 // A MacBook Pro or Studio has the headroom; a fanless Air does not, so the Vision throttle also follows the live thermal state
        case .unknown: return 2
        }
    }
}

struct MetalHardwareSnapshot: Sendable {
    let deviceName: String
    let hasUnifiedMemory: Bool
    let recommendedWorkingSetMB: Int
    let maxBufferLengthMB: Int
    let maxThreadsPerThreadgroup: Int
    let maxThreadgroupMemoryKB: Int
    /// The highest `MTLGPUFamily.appleN` the GPU reports supporting (9 on an A17 Pro or A18 Pro), nil without Metal.
    var highestAppleFamily: Int? = nil

    static let unavailable = MetalHardwareSnapshot(
        deviceName: "Metal unavailable",
        hasUnifiedMemory: false,
        recommendedWorkingSetMB: 0,
        maxBufferLengthMB: 0,
        maxThreadsPerThreadgroup: 0,
        maxThreadgroupMemoryKB: 0
    )

    var workingSetDescription: String {
        guard recommendedWorkingSetMB > 0 else { return "System managed" }
        if recommendedWorkingSetMB >= 1024 {
            return String(format: "%.1f GB", Double(recommendedWorkingSetMB) / 1024.0)
        }
        return "\(recommendedWorkingSetMB) MB"
    }
}

struct HardwareExecutionEnvelope: Sendable {
    let deviceIdentifier: String
    let chipName: String
    let formFactor: DeviceFormFactor
    let memoryGB: Double
    let npuTops: Double?
    let metal: MetalHardwareSnapshot
    let maxSafeGPUAccelerationLevel: Double
    let requestedGPUAccelerationLevel: Double
    let activeGPUAccelerationLevel: Double
    let coreMLRoute: String
    let embeddingRoute: String
    let visionOperationConcurrency: Int
    let visionCooldownMilliseconds: Int
    let visionPipelinePages: Int
    let ocrPipelinePages: Int
    let pdfRenderSlots: Int
    let embeddingConcurrency: Int
    let batchMatrixMultiplyThreshold: Int
}

/// Comprehensive device capability detection
final class DeviceCapabilityService: @unchecked Sendable {
    static let shared = DeviceCapabilityService()

    private enum GPUDefaults {
        static let profile = "gpuAccelerationProfile"
        static let legacyLevel = "gpuAccelerationLevel"
    }

    /// The defaults key of the GPU profile, for a view that watches it with `@AppStorage` (5.7).
    static let gpuProfileDefaultsKey = GPUDefaults.profile

    private nonisolated static let ingestionExecutionProfileLock = NSLock()
    private nonisolated(unsafe) static var ingestionExecutionProfileStorage: IngestionExecutionProfile = .interactive

    private let cachedTier: DeviceCapabilityTier
    private let cachedChipName: String
    private let cachedMemoryGB: Double
    private let cachedFormFactor: DeviceFormFactor
    private let cachedDeviceIdentifier: String
    private let cachedMetalSnapshot: MetalHardwareSnapshot
    private let cachedCPUClusters: [(name: String, cores: Int)]

    private init() {
        let (tier, chip, formFactor, identifier) = Self.detectFullCapability()
        let metal = Self.detectMetalHardwareSnapshot()
        #if targetEnvironment(simulator)
            let isSimulator = true
        #else
            let isSimulator = false
        #endif
        cachedTier = tier
        cachedChipName = Self.resolvedChipName(tableName: chip, metalDeviceName: metal.deviceName, isSimulator: isSimulator)
        cachedFormFactor = formFactor
        cachedDeviceIdentifier = identifier
        cachedMemoryGB = Self.detectMemoryGB()
        cachedMetalSnapshot = metal
        cachedCPUClusters = Self.detectCPUClusters()

        Self.migrateGPUExecutionProfile(in: .standard)
    }

    // MARK: - Public API

    /// Current device capability tier
    var tier: DeviceCapabilityTier { cachedTier }

    /// Chip name (e.g., "A17 Pro", "A18", "M2")
    var chipName: String { cachedChipName }

    /// Apple's own Neural Engine figure for this chip, or nil where Apple has published none (5.8: most chips).
    var npuTops: Double? { AppleDeviceCatalog.neuralEngineTOPS(forChip: cachedChipName) }

    /// "38 TOPS" where Apple published a figure for this chip, nil elsewhere.
    var npuTopsDescription: String? { AppleDeviceCatalog.neuralEngineFigure(forChip: cachedChipName).map { "\($0.text) TOPS" } }

    /// Whether the chip has a real name ("A18 Pro", "M3 Pro") rather than a fallback noun ("iPhone", "Apple Silicon",
    /// "Intel Mac") or the Simulator's host description (5.8 review: those were shown as the chip).
    var chipIdentified: Bool {
        cachedChipName.range(of: "^[AM][0-9]", options: .regularExpression) != nil || cachedChipName == "Intel Mac"
    }

    /// The chip name for a screen: the name, or "Chip not identified". The Simulator keeps its "Simulator on M3 Pro".
    var chipDisplayName: String {
        if chipIdentified || cachedChipName.hasPrefix("Simulator") { return cachedChipName }
        return "Chip not identified"
    }

    /// A Mac's model identifier ("Mac15,7") from `hw.model`; `uname` gives only "arm64" there (5.8 review).
    nonisolated static func macModelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let model = String(cString: buffer)
        return model.isEmpty ? nil : model
    }

    /// Memory the system reports (`ProcessInfo.physicalMemory`), in GB.
    var memoryGB: Double { cachedMemoryGB }

    /// "7.5 GB" or "18 GB": the reported memory, never rounded to a whole size.
    var memoryDescription: String { AppleDeviceCatalog.memoryDescription(gigabytes: cachedMemoryGB) }

    /// The model's name ("iPhone 16 Pro Max") from Xcode's device database, or nil for a Mac or an unknown model.
    var modelName: String? {
        let identifier = cachedDeviceIdentifier.replacingOccurrences(of: "Simulator:", with: "")
        return AppleDeviceCatalog.model(forIdentifier: identifier)?.name
    }

    /// CPU core clusters as the system names and counts them, e.g. [("Performance", 2), ("Efficiency", 4)].
    var cpuClusters: [(name: String, cores: Int)] { cachedCPUClusters }

    /// Metal device limits exposed via public APIs
    var metalSnapshot: MetalHardwareSnapshot { cachedMetalSnapshot }

    /// Device form factor (iPhone, iPad mini, iPad Air, iPad Pro, Mac)
    var formFactor: DeviceFormFactor { cachedFormFactor }

    /// Raw device identifier (e.g., "iPhone17,1", "iPad16,3", "Mac15,3")
    var deviceIdentifier: String { cachedDeviceIdentifier }

    /// Whether this is an iPad
    var isIPad: Bool {
        switch cachedFormFactor {
        case .iPadMini, .iPadAir, .iPadPro:
            return true
        case .iPhone, .mac, .unknown:
            return false
        }
    }

    /// Whether this is a Mac
    var isMac: Bool {
        cachedFormFactor == .mac
    }

    /// Whether Apple Intelligence is available on this device
    var supportsAppleIntelligence: Bool {
        cachedTier != .unsupported
    }

    /// Highest GPU level this device should sustain without pushing into crash-prone territory.
    var maxSafeGPUAccelerationLevel: Double {
        Self.maxSafeGPUAccelerationLevel(formFactor: cachedFormFactor, tier: cachedTier)
    }

    /// The ceiling for each device, pure so Settings and tests can state it for any device (5.7). A profile above
    /// it runs as the profile the ceiling falls in: Maximum on an iPad mini runs as Performance.
    nonisolated static func maxSafeGPUAccelerationLevel(formFactor: DeviceFormFactor, tier: DeviceCapabilityTier) -> Double {
        switch formFactor {
        case .iPadPro:
            return 1.0
        case .iPadAir:
            switch tier {
            case .advanced, .ultraAdvanced: return 1.0
            case .unsupported, .baseline, .enhanced: return 0.9
            }
        case .iPadMini:
            return 0.7
        case .iPhone:
            switch tier {
            case .unsupported:
                return 0.6
            case .baseline:
                return 0.9
            case .enhanced, .advanced, .ultraAdvanced:
                return 1.0
            }
        case .mac:
            return 1.0
        case .unknown:
            return 0.6
        }
    }

    /// The rule for a background import's GPU on this device.
    var backgroundGPUAllowance: BackgroundGPUAllowance {
        BackgroundGPUAllowance.forDevice(formFactor: cachedFormFactor, tier: cachedTier)
    }

    /// The profiles that let a background import ask for the GPU on this device.
    var backgroundGPUProfiles: [GPUExecutionProfile] {
        BackgroundGPUAllowance.profiles(formFactor: cachedFormFactor, tier: cachedTier)
    }

    /// Requested level after applying per-hardware ceilings.
    var activeGPUAccelerationLevel: Double {
        min(gpuAccelerationLevel, maxSafeGPUAccelerationLevel)
    }

    /// Requested user preference before hardware safety ceilings are applied.
    var gpuExecutionProfile: GPUExecutionProfile {
        get {
            if let raw = UserDefaults.standard.string(forKey: GPUDefaults.profile),
               let profile = GPUExecutionProfile(rawValue: raw)
            {
                return profile
            }
            return GPUExecutionProfile(legacyLevel: UserDefaults.standard.double(forKey: GPUDefaults.legacyLevel))
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.rawValue, forKey: GPUDefaults.profile)
            defaults.set(newValue.legacyLevel, forKey: GPUDefaults.legacyLevel)
        }
    }

    /// Effective preference after the device-specific sustained-load ceiling is applied.
    var activeGPUExecutionProfile: GPUExecutionProfile {
        GPUExecutionProfile(legacyLevel: activeGPUAccelerationLevel)
    }

    /// Actual Vision OCR concurrency ceiling used to avoid Metal command buffer instability, paced by the profile
    /// (`paced(_:for:)`: Efficiency takes half, 5.8).
    var visionOperationConcurrency: Int { Self.paced(baseVisionOperationConcurrency, for: Self.selectedProfile) }

    /// The chip's ceiling before the profile paces it.
    private var baseVisionOperationConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 2
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 8
            }
            if chipIsAtLeast("M3") {
                return 6
            }
            if chipIsAtLeast("M2") || chipIsAtLeast("M1") {
                return 4
            }
            return 4
        }

        if chipIsAtLeast("A20") || chipIsAtLeast("M5") || chipIsAtLeast("A19") || chipIsAtLeast("M4") {
            return 8
        }
        if chipIsAtLeast("A18") || chipIsAtLeast("M3") {
            return 6
        }
        if chipIsAtLeast("A17") || chipIsAtLeast("M2") || chipIsAtLeast("M1") {
            return 4
        }
        return 2
    }

    /// Vision concurrency after the live thermal state is applied. The chip picks the ceiling, but no public API says
    /// whether a Mac has a fan (a fanless MacBook Air throttled to 100% CPU against 400% over a five-hour import), so
    /// the measured state lowers it: half the ceiling (at least 2) at `.fair`, 2 at `.serious`, 1 at `.critical`.
    /// Never raises a ceiling that is already lower. Pure, so the shipping branch is the tested one.
    nonisolated static func thermallyLimitedVisionConcurrency(
        ceiling: Int,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        let limited: Int
        switch thermalState {
        case .nominal: limited = ceiling
        case .fair: limited = max(2, ceiling / 2)
        case .serious: limited = 2
        case .critical: limited = 1
        @unknown default: limited = max(2, ceiling / 2)
        }
        return max(1, min(ceiling, limited))
    }

    /// Brief cooldown that lets Metal/Vision finish outstanding work between OCR requests.
    var visionOperationCooldownSeconds: TimeInterval {
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 0.006
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 0.001
            }
            if chipIsAtLeast("M3") {
                return 0.002
            }
            return 0.003
        }

        if chipIsAtLeast("A20") || chipIsAtLeast("M5") || chipIsAtLeast("A19") || chipIsAtLeast("M4") {
            return 0.001
        }
        if chipIsAtLeast("A18") || chipIsAtLeast("M3") {
            return 0.002
        }
        if chipIsAtLeast("A17") || chipIsAtLeast("M2") || chipIsAtLeast("M1") {
            return 0.003
        }
        return 0.006
    }

    var visionOperationCooldownMilliseconds: Int {
        Int((visionOperationCooldownSeconds * 1000).rounded())
    }

    var preferredComputeUnitsDescription: String {
        Self.describeComputeUnits(preferredComputeUnits)
    }

    var embeddingComputeUnitsDescription: String {
        Self.describeComputeUnits(embeddingComputeUnitsDuringIngestion)
    }

    var hardwareExecutionEnvelope: HardwareExecutionEnvelope {
        HardwareExecutionEnvelope(
            deviceIdentifier: deviceIdentifier,
            chipName: chipName,
            formFactor: formFactor,
            memoryGB: memoryGB,
            npuTops: npuTops,
            metal: metalSnapshot,
            maxSafeGPUAccelerationLevel: maxSafeGPUAccelerationLevel,
            requestedGPUAccelerationLevel: gpuAccelerationLevel,
            activeGPUAccelerationLevel: activeGPUAccelerationLevel,
            coreMLRoute: preferredComputeUnitsDescription,
            embeddingRoute: embeddingComputeUnitsDescription,
            visionOperationConcurrency: visionOperationConcurrency,
            visionCooldownMilliseconds: visionOperationCooldownMilliseconds,
            visionPipelinePages: visionParsingConcurrency,
            ocrPipelinePages: ocrExtractionConcurrency,
            pdfRenderSlots: pdfRenderingConcurrency,
            embeddingConcurrency: embeddingConcurrency,
            batchMatrixMultiplyThreshold: batchMatrixMultiplyThreshold
        )
    }

    /// Maximum recommended concurrent agentic steps
    var maxConcurrentAgenticSteps: Int {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 3 // Conservative for A17 Pro
        case .enhanced: return 5 // A18 has better thermal headroom
        case .advanced: return 6 // A19 projected
        case .ultraAdvanced: 
            let ramMultiplier = max(1.0, cachedMemoryGB / 16.0)
            return min(32, Int(8.0 * ramMultiplier)) // M-series / future
        }
    }

    /// Maximum recommended total tokens for agentic loop
    var maxAgenticTokenBudget: Int {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 16000 // ~4 sessions
        case .enhanced: return 24000 // ~6 sessions
        case .advanced: return 32000 // ~8 sessions
        case .ultraAdvanced: 
            let ramMultiplier = max(1.0, cachedMemoryGB / 16.0)
            return min(256000, Int(48000.0 * ramMultiplier)) // ~12+ sessions depending on RAM
        }
    }

    /// Recommended delay between agentic steps (thermal management)
    var agenticStepCooldownMs: UInt64 {
        switch cachedTier {
        case .unsupported: return 0
        case .baseline: return 100  // A17 Pro: reduced cooldown, quality over battery
        case .enhanced: return 50   // A18 Pro: fast iteration
        case .advanced: return 25   // A19 Pro: near-instant
        case .ultraAdvanced: return 0 // M-series can go full speed
        }
    }

    /// Whether to prefer PCC for complex agentic queries
    var preferPCCForAgentic: Bool {
        // Baseline devices should offload to PCC when available
        cachedTier == .baseline
    }

    // MARK: - Vector Operation Batch Sizes (Accelerate/BNNS)

    /// Passages handed to the embedding model in one call during an import: the concurrency, at least 16
    /// (`EmbeddingService`). The tier table this name used to hold (24, 32, 48, up to 512) was read by nothing but
    /// Settings, onboarding and the library sheet (5.8).
    var embeddingBatchSize: Int { max(16, embeddingConcurrency) }

    /// Threshold above which to use batch matrix multiply vs individual dot products.
    ///
    /// Metal Feature Set: SIMD-scoped matrix multiply on Apple7+.
    /// Batch matrix multiply amortizes dispatch overhead for large datasets.
    var batchMatrixMultiplyThreshold: Int {
        // MAX POWER: Use SIMD matrix multiply as early as possible
        // Apple9 64-bit atomics make batch synchronization fast
        switch cachedTier {
        case .unsupported: return Int.max
        case .baseline: return 100  // A17 Pro: batch early
        case .enhanced: return 50   // A18 Pro: batch everything
        case .advanced: return 32   // A19 Pro: always batch
        case .ultraAdvanced: return 16 // M-series: batch from the start
        }
    }

    /// Maximum chunks to process in a single vector search before yielding.
    ///
    /// Metal Feature Set: Apple9+ supports 64-bit atomics for lock-free progress tracking.
    /// Higher-tier devices can process more chunks before yielding to UI.
    var maxChunksPerSearchYield: Int {
        // CRANKED: Process more chunks before yielding for higher search quality
        // 64-bit atomics enable lock-free progress tracking
        switch cachedTier {
        case .unsupported: return 200
        case .baseline: return 3000   // A17 Pro: fast single-core
        case .enhanced: return 6000   // A18 Pro: maximum chunk processing
        case .advanced: return 10000  // A19 Pro: next-gen cores
        case .ultraAdvanced: 
            let ramMultiplier = max(1, Int(cachedMemoryGB / 8))
            return min(250000, 20000 * ramMultiplier) // M-series: unlimited
        }
    }

    // MARK: - Document Ingestion Optimization

    /// Maximum concurrent pages for Vision structured parsing.
    ///
    /// Vision's RecognizeDocumentsRequest runs on Neural Engine (16-core) + GPU.
    /// NOTE: Too high causes swift_release_dealloc crashes from deallocation races.
    /// VisionOCRThrottle gates actual Vision ops; this is pre-render pipeline size.
    ///
    /// CRITICAL: Values must coordinate with VisionOCRThrottle maxConcurrentVisionOps!
    /// Pipeline size should be ~2x Vision ops to keep Vision saturated.
    ///
    /// IMPORTANT: Mac needs LOWER values despite more power!
    /// macOS Metal command buffer scheduling differs from iOS.
    var visionParsingConcurrency: Int { Self.paced(baseVisionParsingConcurrency, for: Self.selectedProfile) }

    private var baseVisionParsingConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        // Mac check - active cooling allows sustained throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 4
            }
            // Scale dynamically by RAM for Macs
            let ramMultiplier = max(1, Int(cachedMemoryGB / 8))
            var baseConcurrency = 8
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                baseConcurrency = 16
            } else if chipIsAtLeast("M3") {
                baseConcurrency = 12
            }
            return min(64, baseConcurrency * ramMultiplier)
        }

        // iOS devices: 2x VisionOCRThrottle limits for pipeline saturation
        // Pipeline pre-renders pages ahead of Vision to keep ANE saturated
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 8   // A17 Pro: 2x the 4 Vision ops
        case .enhanced: return 12  // A18 Pro: 2x the 6 Vision ops
        case .advanced: return 16  // A19 Pro: 2x the 8 Vision ops
        case .ultraAdvanced: 
            // Scale iPads by RAM too (e.g. 16GB M4 iPad Pro)
            let ramMultiplier = max(1, Int(cachedMemoryGB / 8))
            return min(32, 12 * ramMultiplier)
        }
    }

    /// Maximum concurrent pages for PDF OCR extraction.
    ///
    /// Metal Feature Set: Apple9 supports 256KB implicit imageblock (2x Apple8).
    /// NOTE: Too high causes swift_release_dealloc crashes from deallocation races.
    /// Keep moderate to avoid Vision observation deallocation races.
    ///
    /// CRITICAL: Values must coordinate with VisionOCRThrottle maxConcurrentVisionOps!
    var ocrExtractionConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        // Match vision parsing concurrency to maintain pipeline balance
        return visionParsingConcurrency
    }

    /// Maximum number of full-resolution PDF page images alive in memory simultaneously.
    ///
    /// At 360 DPI, each US Letter PDF page renders to 6210×11040px ≈ 206 MB (opaque RGB).
    /// MEMORY BUDGET: 3 pages × 206 MB = ~618 MB — well within iOS app limits.
    /// This is INDEPENDENT of Neural Engine pipeline depth (visionParsingConcurrency):
    ///   - The pipeline can queue 10+ pages for OCR work
    ///   - But only `pdfRenderingConcurrency` pages have full-res images alive at once
    ///   - Images are rendered on-demand inside TaskGroup tasks, not pre-rendered in bulk
    ///   - Each image is released immediately after Vision OCR completes for that page
    ///
    /// This prevents the OOM crash where 10 × 206 MB = 2 GB of images were held simultaneously.
    /// Quality is UNCHANGED: still 360 DPI, same preprocessing, same Vision accuracy.
    var pdfRenderingConcurrency: Int {
        Self.paced(basePDFRenderingConcurrency(fullDetail: isMaximumFidelityActive), for: Self.selectedProfile)
    }

    /// Pages held at once before the profile paces it; `fullDetail` is Maximum's 432 DPI, full-size layout page.
    private func basePDFRenderingConcurrency(fullDetail: Bool) -> Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        // Dynamically scale based on RAM: Allocate up to 15% of total system RAM for PDF image buffers
        // 206 MB per page. Maximum reads every page at 432 DPI with the layout pass at full size, about 592 MB a
        // page (411 MB at 360 DPI x 1.44), so fewer pages are held at once: 2 on an 8 GB iPhone against 4.
        let maxSafeMemoryMB = (cachedMemoryGB * 1024.0) * 0.15
        let megabytesPerPage = fullDetail ? MaximumFidelity.megabytesPerPage : 206.0
        // Two pages at least in Maximum: an "8 GB" iPhone reports about 7.5, which rounded Maximum down to one page
        // at a time (the owner's iPhone, 2026-11-10). Two full-detail pages (1.2 GB) are less than the four
        // full-size pages (1.6 GB) every profile already holds for a document of tables.
        let maxPagesByRam = max(fullDetail ? 2 : 1, Int(maxSafeMemoryMB / megabytesPerPage))

        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 2
            }
            return min(64, maxPagesByRam)
        }
        
        switch cachedTier {
        case .unsupported: return 1
        case .baseline: return min(3, maxPagesByRam)   // A17 Pro
        case .enhanced: return min(4, maxPagesByRam)   // A18 Pro
        case .advanced: return min(5, maxPagesByRam)   // A19 Pro
        case .ultraAdvanced: return min(16, maxPagesByRam) // M-series iPad
        }
    }

    /// Maximum concurrent embedding requests.
    ///
    /// CoreML embedding uses ANE (16-core Neural Engine) + optional GPU fallback.
    /// Metal Feature Set: SIMD-scoped matrix multiply available on Apple7+.
    /// STABLE: Reduced after Metal synchronizeResource crashes.
    /// GPU boost mode disabled - caused Metal command buffer conflicts.
    var embeddingConcurrency: Int { Self.paced(baseEmbeddingConcurrency, for: Self.selectedProfile) }

    private var baseEmbeddingConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 2
        }

        // Mac check - active cooling allows sustained GPU embedding throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 4
            }
            let ramMultiplier = max(1, Int(cachedMemoryGB / 8))
            var baseConcurrency = 12
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                baseConcurrency = 24
            } else if chipIsAtLeast("M3") {
                baseConcurrency = 16
            }
            return min(128, baseConcurrency * ramMultiplier)
        }

        // CRANKED: Embeddings run on GPU during ingestion (freeing ANE for Vision).
        // Higher concurrency = more chunks embedded per second = faster ingestion.
        // GPU has dedicated bandwidth separate from ANE.
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 12  // A17 Pro: GPU is underutilized during OCR
        case .enhanced: return 16  // A18 Pro: 6-core GPU, plenty of headroom
        case .advanced: return 20  // A19 Pro: scaled GPU throughput
        case .ultraAdvanced: 
            let ramMultiplier = max(1, Int(cachedMemoryGB / 8))
            return min(64, 16 * ramMultiplier)
        }
    }

    // MARK: - GPU Acceleration Settings

    /// Compatibility bridge for older callers and persisted builds.
    /// New UI and policy code should use `gpuExecutionProfile`.
    var gpuAccelerationLevel: Double {
        get { gpuExecutionProfile.legacyLevel }
        set { gpuExecutionProfile = GPUExecutionProfile(legacyLevel: newValue) }
    }

    /// Core ML compute preference for the active execution profile.
    var preferredComputeUnits: MLComputeUnits {
        #if targetEnvironment(simulator)
        return Self.simulatorComputeUnits
        #else
        if isBackgroundCPUSafeIngestionActive {
            return Self.backgroundComputeUnits
        }

        return Self.coreMLComputeUnits(for: activeGPUExecutionProfile)
        #endif
    }

    /// Core ML runs on the CPU in the iOS Simulator (5.7). On the units the app asks for on a device,
    /// the Core ML copy of the embedding model handed back all-zero vectors there: a library of the
    /// ten sample documents held 127 passages with every vector zero, and with the model limited to
    /// the CPU the same library held 2,375 passages with every norm 1.000 (both measured 2026-10-08,
    /// row "A library is built from all-zero vectors when the embedding model fails"). From 5.7 an
    /// import refuses empty vectors (`EmbeddingVectorCheck`), so without this every import in the
    /// Simulator would stop, and libraries built there can now be searched by meaning.
    nonisolated static let simulatorComputeUnits: MLComputeUnits = .cpuOnly

    /// Core ML units in a background import that has no GPU grant: the CPU and the Neural Engine (5.8). It was the CPU
    /// alone, but iOS 27 opens the Neural Engine to a backgrounded app that holds
    /// `com.apple.developer.background-tasks.continued-processing.inference` ("any Neural Engine access while your app is
    /// in the background, regardless of whether it's running a continued background task", Apple's entitlement page,
    /// fetched 2026-11-08), which the app has since 2026-11-05. Measured 2026-11-08 on an M3 Pro: the embedding model at
    /// 512 tokens took 12.6 ms on the CPU and 7.7 ms on CPU and Neural Engine. The GPU stays off here, as before.
    nonisolated static let backgroundComputeUnits: MLComputeUnits = .cpuAndNeuralEngine

    /// Core ML compute units for a profile.
    ///
    /// Extracted `nonisolated static` so the tested branch is the shipping branch:
    /// a test over a parallel copy of this decision would prove nothing about what
    /// actually runs.
    ///
    /// Maximum previously returned `.cpuAndGPU`, which *excludes* the Neural Engine,
    /// so choosing the highest setting removed hardware rather than adding it and
    /// left Maximum strictly less capable than Performance. Nothing sits above
    /// `.all`: it permits CPU, GPU and Neural Engine and lets Core ML place each
    /// operation on whichever unit wins.
    nonisolated static func coreMLComputeUnits(for profile: GPUExecutionProfile) -> MLComputeUnits {
        switch profile {
        case .efficiency, .balanced:
            // Neural Engine and CPU only. Leaving the GPU out is the point of the
            // lower half of the ladder: the ANE is the efficient unit for this work.
            return .cpuAndNeuralEngine
        case .performance, .maximum:
            return .all
        }
    }

    /// Embedding compute preference used when an ingestion session loads its model.
    var embeddingComputeUnitsDuringIngestion: MLComputeUnits {
        #if targetEnvironment(simulator)
        return Self.simulatorComputeUnits
        #else
        if isBackgroundCPUSafeIngestionActive {
            return Self.backgroundComputeUnits
        }

        guard cachedTier != .unsupported else {
            return .cpuAndNeuralEngine
        }

        return Self.embeddingComputeUnits(for: activeGPUExecutionProfile)
        #endif
    }

    /// Embedding compute units for a profile. Extracted for the same reason as
    /// `coreMLComputeUnits(for:)`.
    ///
    /// Balanced was the only profile using all three engines: Performance and
    /// Maximum both returned `.cpuAndGPU` and dropped the Neural Engine. On a
    /// 384-dimension embedding model the ANE is typically the fastest and most
    /// efficient unit available, so turning the profile up made document ingestion
    /// worse — the workload where it matters most.
    nonisolated static func embeddingComputeUnits(for profile: GPUExecutionProfile) -> MLComputeUnits {
        switch profile {
        case .efficiency:
            return .cpuAndNeuralEngine
        case .balanced, .performance, .maximum:
            return .all
        }
    }

    /// Whether the Core Image cleanup of a scanned page runs on the GPU (`cleansScannedPagesOnGPU(for:)`).
    var useGPUForPDFRendering: Bool {
        if isBackgroundCPUSafeIngestionActive {
            return false
        }

        return Self.cleansScannedPagesOnGPU(for: activeGPUExecutionProfile)
    }

    /// What Maximum turns up beyond which chips may run a job (5.8). Until 5.8 Maximum differed from Performance only in
    /// a background import's GPU on an iPhone 15 Pro; the owner asked (2026-11-10) for it to be a real maximum on every
    /// device. Each value is how hard or how carefully a job runs; none is measured yet (benchmark day 2026-11-11
    /// decides whether it ships).
    nonisolated enum MaximumFidelity {
        /// Every page read by text recognition is drawn at 432 DPI (scale 6.0); other profiles use 360 unless a page
        /// has small print, tables, columns or a garbled text layer.
        static let renderScale: CGFloat = 6.0
        /// Memory for one page at 432 DPI with its layout pass at full size.
        static let megabytesPerPage: Double = 592
        /// Hard regions re-read per page (12 in other profiles).
        static let rescueRegions = 24
        /// Passages the reranker scores at most (250 in other profiles), and its floor (100).
        static let rerankCeiling = 400
        static let rerankFloor = 150
        /// Keyword-search results taken at most (60 in other profiles).
        static let keywordLimit = 120
    }

    /// How deeply each job reads and searches, per profile (5.8). Until 5.8 every profile below Maximum ran the same
    /// depth and Maximum jumped to the top values; the owner asked (2026-11-10) for the steps to ramp. Depth never
    /// goes below Balanced's values, which are the ones 5.7 shipped and measured: accuracy comes first, so Efficiency
    /// saves energy by doing fewer things at once (`paced(_:for:)`), not by reading less. Performance's values are the
    /// midpoint between Balanced and Maximum and, like Maximum's, are unmeasured until benchmark day (2026-11-11).
    nonisolated struct Depth: Equatable, Sendable {
        /// Hard regions re-read per page.
        let rescueRegions: Int
        /// Passages the reranker scores at most, and at least.
        let rerankCeiling: Int
        let rerankFloor: Int
        /// Keyword-search results taken at most.
        let keywordLimit: Int
        /// Every page text recognition reads is drawn at 432 DPI and gets the layout pass at full size (otherwise
        /// 360 DPI, and 432 and full size only for hard pages).
        let fullDetailPages: Bool

        static let standard = Depth(rescueRegions: 12, rerankCeiling: 250, rerankFloor: 100, keywordLimit: 60, fullDetailPages: false)
        static let performance = Depth(rescueRegions: 18, rerankCeiling: 325, rerankFloor: 125, keywordLimit: 90, fullDetailPages: false)
        static let maximum = Depth(
            rescueRegions: MaximumFidelity.rescueRegions, rerankCeiling: MaximumFidelity.rerankCeiling,
            rerankFloor: MaximumFidelity.rerankFloor, keywordLimit: MaximumFidelity.keywordLimit, fullDetailPages: true)

        static func forProfile(_ profile: GPUExecutionProfile) -> Depth {
            switch profile {
            case .efficiency, .balanced: return .standard
            case .performance: return .performance
            case .maximum: return .maximum
            }
        }
    }

    /// The depth in force now: the stored profile after the device's ceiling (an iPad mini runs Maximum as
    /// Performance), and Balanced's depth in a background CPU-safe import, while the device is hot, or in Low Power Mode.
    nonisolated var activeDepth: Depth {
        guard !isBackgroundCPUSafeIngestionActive else { return .standard }
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .serious, thermal != .critical, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return .standard }
        return depth(for: Self.selectedProfile)
    }

    /// The depth a profile gets on this device when nothing holds it back: the profile after the device's ceiling, so
    /// an iPad mini shows Maximum as Performance (5.8 review: Settings showed 432 DPI and 400 reranked there).
    nonisolated func depth(for profile: GPUExecutionProfile) -> Depth {
        var profile = profile
        let ceiling = Self.maxSafeGPUAccelerationLevel(formFactor: cachedFormFactor, tier: cachedTier)
        if profile == .maximum, ceiling < 0.9 { profile = .performance }
        if profile == .performance, ceiling < 0.6 { profile = .balanced }
        return .forProfile(profile)
    }

    /// Whether Maximum's full-detail pages are in force now (`activeDepth`).
    nonisolated var isMaximumFidelityActive: Bool { activeDepth.fullDetailPages }

    /// How many things a job does at once under a profile (5.8): Efficiency takes half the chip's ceiling, rounded up,
    /// so an import runs cooler and slower with the same result; the other profiles take the ceiling, which is set for
    /// stability on each chip and is not raised. A ceiling of 1 stays 1.
    nonisolated static func paced(_ ceiling: Int, for profile: GPUExecutionProfile) -> Int {
        switch profile {
        case .efficiency: return max(1, (ceiling + 1) / 2)
        case .balanced, .performance, .maximum: return ceiling
        }
    }

    /// What Settings shows for a profile before it is chosen: pages parsed, read and drawn at once, and passages
    /// embedded at once, with that profile's pacing and page size.
    func concurrency(for profile: GPUExecutionProfile) -> (visionParsing: Int, ocr: Int, render: Int, embedding: Int) {
        let fullDetail = depth(for: profile).fullDetailPages
        let parsing = Self.paced(baseVisionParsingConcurrency, for: profile)
        return (parsing, isBackgroundCPUSafeIngestionActive ? 1 : parsing,
                Self.paced(basePDFRenderingConcurrency(fullDetail: fullDetail), for: profile),
                Self.paced(baseEmbeddingConcurrency, for: profile))
    }

    /// The stored profile, readable from any thread. `OI_COMPUTE_PROFILE` (efficiency, balanced, performance,
    /// maximum) overrides it for depth and pacing, and `OI_MAXIMUM_FIDELITY=on` or `off` (maximum or balanced), so a
    /// benchmark can compare profiles on one build.
    nonisolated static var selectedProfile: GPUExecutionProfile {
        let environment = ProcessInfo.processInfo.environment
        if let profile = environment["OI_COMPUTE_PROFILE"].flatMap(profileNamed) { return profile }
        if environment["OI_MAXIMUM_FIDELITY"] == "on" { return .maximum }
        if environment["OI_MAXIMUM_FIDELITY"] == "off" { return .balanced }
        return UserDefaults.standard.string(forKey: GPUDefaults.profile).flatMap(profileNamed) ?? .balanced
    }

    /// A profile from its stored name, matched by hand so any thread can call it.
    nonisolated private static func profileNamed(_ name: String) -> GPUExecutionProfile? {
        switch name {
        case "efficiency": return .efficiency
        case "balanced": return .balanced
        case "performance": return .performance
        case "maximum": return .maximum
        default: return nil
        }
    }

    /// The stored profile is Maximum (`selectedProfile`).
    nonisolated static var maximumProfileSelected: Bool { selectedProfile == .maximum }

    /// Whether large searches use Metal (`searchesLargeLibrariesOnGPU(for:)`).
    var useMetalForVectorOps: Bool {
        if isBackgroundCPUSafeIngestionActive {
            return false
        }

        return Self.searchesLargeLibrariesOnGPU(for: activeGPUExecutionProfile)
    }

    /// Whether a rendered PDF page gets an extra Core Image cleanup pass, on the GPU, before text recognition
    /// (`DocumentProcessor.renderPDFPageAsImage`). The page's raster is CPU work whatever this says, and the cleanup that
    /// prepares every scanned page for recognition (`preprocessImageForOCR`) runs on its Metal context in every
    /// profile; the name `useGPUForPDFRendering` is older than both findings.
    nonisolated static func cleansScannedPagesOnGPU(for profile: GPUExecutionProfile) -> Bool {
        switch profile {
        case .efficiency: return false
        case .balanced, .performance, .maximum: return true
        }
    }

    /// Whether large searches use Metal on the GPU: a vector search over 1,000 or more passages
    /// (`BNNSVectorDatabase`) and the diversity step over more than 50 results (`RAGEngine.applyMMR`), on a device
    /// with a Metal GPU.
    nonisolated static func searchesLargeLibrariesOnGPU(for profile: GPUExecutionProfile) -> Bool {
        switch profile {
        case .efficiency, .balanced: return false
        case .performance, .maximum: return true
        }
    }

    /// Migrates the old continuous preference without treating a real 0% choice as "unset."
    /// Internal for focused persistence-policy tests.
    static func migrateGPUExecutionProfile(in defaults: UserDefaults) {
        if let raw = defaults.string(forKey: GPUDefaults.profile),
           let profile = GPUExecutionProfile(rawValue: raw)
        {
            defaults.set(profile.legacyLevel, forKey: GPUDefaults.legacyLevel)
            return
        }

        let profile: GPUExecutionProfile
        if defaults.object(forKey: GPUDefaults.legacyLevel) != nil {
            profile = GPUExecutionProfile(legacyLevel: defaults.double(forKey: GPUDefaults.legacyLevel))
        } else {
            profile = .balanced
        }
        defaults.set(profile.rawValue, forKey: GPUDefaults.profile)
        defaults.set(profile.legacyLevel, forKey: GPUDefaults.legacyLevel)
    }

    nonisolated var ingestionExecutionProfile: IngestionExecutionProfile {
        Self.ingestionExecutionProfileLock.lock()
        defer { Self.ingestionExecutionProfileLock.unlock() }
        return Self.ingestionExecutionProfileStorage
    }

    nonisolated static var isBackgroundCPUSafeIngestionProfileActive: Bool {
        ingestionExecutionProfileLock.lock()
        defer { ingestionExecutionProfileLock.unlock() }

        switch ingestionExecutionProfileStorage {
        case .continuedProcessingCPUOnly:
            return true
        case .interactive, .continuedProcessingGPU:
            return false
        }
    }

    nonisolated var isBackgroundCPUSafeIngestionActive: Bool {
        Self.isBackgroundCPUSafeIngestionProfileActive
    }

    nonisolated func setIngestionExecutionProfile(_ profile: IngestionExecutionProfile) {
        Self.ingestionExecutionProfileLock.lock()
        Self.ingestionExecutionProfileStorage = profile
        Self.ingestionExecutionProfileLock.unlock()
    }

    /// Get optimized AgenticConfig for current device
    func optimizedAgenticConfig() -> AgenticConfig {
        switch cachedTier {
        case .unsupported:
            return .fast // Shouldn't happen, but fallback

        case .baseline:
            // A17 Pro: Moderate settings for quality without thermal throttling
            return AgenticConfig(
                maxSteps: 5,
                maxTotalTokens: 20000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.85, // Higher quality threshold
                escalationThreshold: 0.35
            )

        case .enhanced:
            // A18/A18 Pro: High quality, good thermal headroom
            return AgenticConfig(
                maxSteps: 8,
                maxTotalTokens: 32000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.90,
                escalationThreshold: 0.40
            )

        case .advanced:
            // A19/A19 Pro: Maximum quality
            return AgenticConfig(
                maxSteps: 10,
                maxTotalTokens: 40000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.92,
                escalationThreshold: 0.45
            )

        case .ultraAdvanced:
            // M-series / future: Full power, highest quality, dynamically scale to RAM
            let ramMultiplier = max(1.0, cachedMemoryGB / 16.0)
            let steps = min(32, Int(12.0 * ramMultiplier))
            let tokens = min(128000, Int(56000.0 * ramMultiplier))
            return AgenticConfig(
                maxSteps: steps,
                maxTotalTokens: tokens,
                streamIntermediateResults: true,
                confidenceThreshold: 0.95,
                escalationThreshold: 0.50
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

        // Check if running in Simulator FIRST (uname returns arm64/x86_64, not device ID)
        #if targetEnvironment(simulator)
            // In simulator, get the simulated device from environment
            if let simDevice = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                if simDevice.hasPrefix("iPhone") {
                    let (tier, chip) = detectiPhoneCapability(identifier: simDevice)
                    return (tier, chip, .iPhone, "Simulator:\(simDevice)")
                }
                if simDevice.hasPrefix("iPad") {
                    let (tier, chip, formFactor) = detectiPadCapabilityFull(identifier: simDevice)
                    return (tier, chip, formFactor, "Simulator:\(simDevice)")
                }
            }

            // Detect the HOST Mac's capabilities for accurate performance estimation
            // The simulator runs on your Mac, so we can use Mac-level performance
            let hostMac = detectHostMacCapability()
            return (hostMac.tier, "Simulator on \(hostMac.chip)", .mac, "Simulator:HostMac")
        #else
        // iPhone detection
        if identifier.hasPrefix("iPhone") {
            let (tier, chip) = detectiPhoneCapability(identifier: identifier)
            return (tier, chip, .iPhone, identifier)
        }

        // iPad detection (also covers iPad apps running on Mac via compatibility)
        if identifier.hasPrefix("iPad") {
            let (tier, chip, formFactor) = detectiPadCapabilityFull(identifier: identifier)
            // Check if we're actually running on a Mac (iPad app on Mac)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                // Running as iPad app on Mac - detect the actual Mac
                let hostMac = detectHostMacCapability()
                return (hostMac.tier, hostMac.chip, .mac, "iPadAppOnMac:\(identifier)")
            }

            return (tier, chip, formFactor, identifier)
        }

        // Mac detection (native Mac apps via Catalyst or macOS natively)
        if identifier.hasPrefix("Mac") || identifier.hasPrefix("iMac") || identifier == "arm64" || identifier == "x86_64" {
            let hostMac = detectHostMacCapability()
            return (hostMac.tier, hostMac.chip, .mac, identifier)
        }

        // Fallback for a device family this build does not recognise. The app only
        // runs on iOS and macOS, so an unmatched prefix means new hardware rather
        // than old, and `.unsupported` would disable four retrieval features over a
        // string this build has simply never seen. Full features at mid ceilings.
        return (.advanced, "Apple Device", .unknown, identifier)
        #endif
    }

    /// The Mac's chip from `machdep.cpu.brand_string`, which Apple silicon fills with "Apple M3 Pro", "Apple M5 Max"
    /// or, on a MacBook Neo, "Apple A18 Pro" (5.8). The name is the brand string after "Apple ", read rather than
    /// matched against a list, so a chip newer than this build is named as the Mac names it. It used to be a chain of
    /// `contains` checks that also returned a Neural Engine figure per chip, most of them never published by Apple,
    /// and a MacBook Neo matched none of it and was called "Apple Silicon".
    private static func detectHostMacCapability() -> (tier: DeviceCapabilityTier, chip: String) {
        var size = 0
        var brand = ""
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                brand = String(cString: buffer)
            }
        }

        guard brand.hasPrefix("Apple ") else {
            #if arch(arm64)
                // The brand string is unreadable, so the chip is genuinely unknown and is
                // named "Apple Silicon" rather than guessed. Memory, which is measured, picks
                // the ceilings that depend on it.
                let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
                if memoryGB >= 32 {
                    return (.ultraAdvanced, "Apple Silicon")
                } else if memoryGB >= 16 {
                    return (.advanced, "Apple Silicon")
                }
                return (.enhanced, "Apple Silicon")
            #else
                return (.unsupported, "Intel Mac")
            #endif
        }

        let chip = String(brand.dropFirst("Apple ".count)).trimmingCharacters(in: .whitespaces)
        return (macTier(forChip: chip), chip)
    }

    /// The ceiling tier for a Mac chip, unchanged from 5.7 for every chip it already knew: M1, M1 Pro and M1 Max
    /// `.enhanced`, M1 Ultra and every M2 and later `.ultraAdvanced` (see the note in `optimizedAgenticConfig` and the
    /// thermal handling in `thermallyLimitedVisionConcurrency`, which follows the live state rather than the tier).
    /// An A-series chip in a Mac (the MacBook Neo's A18 Pro) or a name this build cannot read is `.advanced`, the
    /// ceiling 5.7 gave a Mac it could not identify.
    nonisolated static func macTier(forChip chip: String) -> DeviceCapabilityTier {
        if chip.hasPrefix("M1") {
            return chip.contains("Ultra") ? .ultraAdvanced : .enhanced
        }
        if let generation = appleSiliconGeneration(in: chip), generation >= 2 {
            return .ultraAdvanced
        }
        return .advanced
    }

    private static func detectCapabilityTier() -> (DeviceCapabilityTier, String) {
        let (tier, chip, _, _) = detectFullCapability()
        return (tier, chip)
    }

    /// Tier and chip for an iPhone identifier. The chip comes from `AppleDeviceCatalog` (Apple's Tech Specs); the tier
    /// is the generation, unchanged from 5.7. An identifier the catalog does not know is named "iPhone" rather than
    /// guessed, and on a real device `resolvedChipName` replaces it with the chip Metal reports.
    nonisolated static func detectiPhoneCapability(identifier: String) -> (DeviceCapabilityTier, String) {
        let chip = AppleDeviceCatalog.model(forIdentifier: identifier)?.chip ?? "iPhone"
        let numbers = identifier.replacingOccurrences(of: "iPhone", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            // An unparseable identifier on a device running this app means hardware
            // newer than this build, not older. `.unsupported` would strip HyDE,
            // parent-document retrieval, contextual compression and iterative
            // retrieval via AdaptivePipelineOptimizer, so it is the wrong answer
            // here. `.advanced` keeps every feature on at mid-range ceilings.
            return (.advanced, chip)
        }

        let major = numbers[0]
        let minor = numbers[1]

        switch major {
        case 16:
            // iPhone 15 Pro (16,1) and 15 Pro Max (16,2): A17 Pro.
            return minor <= 2 ? (.baseline, chip) : (.unsupported, chip)
        case 17:
            return (.enhanced, chip)  // iPhone 16 family: A18 and A18 Pro
        case 18:
            return (.advanced, chip)  // iPhone 17 family and iPhone Air: A19 and A19 Pro
        case 19...:
            return (.ultraAdvanced, chip)  // iPhone 18 Pro, Pro Max and Duo: A20 Pro, and later
        default:
            // iPhone 15 and 15 Plus (A16 Bionic) and older: not Apple Intelligence devices.
            return (.unsupported, chip)
        }
    }

    /// Tier, chip and form factor for an iPad identifier (5.8). The chip and the model come from `AppleDeviceCatalog`;
    /// the tiers are 5.7's for every iPad it identified correctly. It misidentified five families: the iPad Air
    /// (5th generation, 13,16-17) and the M4 iPad Air (16,8-11) were called iPad Pro, the iPad (10th generation,
    /// 13,18-19, A14 Bionic) an M1 iPad Pro, the iPad (A16, 15,7-8) an M3 iPad Air, and the iPad mini (A20 Pro, 19,1-2)
    /// an "M7" iPad Pro. The A14 and A16 iPads are not on Apple's Apple Intelligence list (support.apple.com/121115,
    /// 2026-11-05: "iPad mini (A17 Pro and A20 Pro), iPad models with M1 or later").
    nonisolated static func detectiPadCapabilityFull(identifier: String) -> (DeviceCapabilityTier, String, DeviceFormFactor) {
        let chip = AppleDeviceCatalog.model(forIdentifier: identifier)?.chip ?? "iPad"
        let numbers = identifier.replacingOccurrences(of: "iPad", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            // Newer than this build: every feature on at mid-range ceilings (see the iPhone note).
            return (.advanced, chip, .iPadAir)
        }

        let major = numbers[0]
        let minor = numbers[1]

        switch (major, minor) {
        case (13, 4...11): return (.enhanced, chip, .iPadPro)  // iPad Pro M1, 11-inch and 12.9-inch
        case (13, 16...17): return (.enhanced, chip, .iPadAir)  // iPad Air (5th generation), M1
        case (13, 18...19): return (.unsupported, chip, .iPadAir)  // iPad (10th generation), A14 Bionic
        case (13, 12...): return (.enhanced, chip, .iPadAir)  // an unlisted model in the M1 family
        case (13, _): return (.unsupported, chip, .iPadAir)  // iPad Air (4th generation), A14 Bionic
        case (14, 1...2): return (.unsupported, chip, .iPadMini)  // iPad mini (6th generation), A15 Bionic
        case (14, 3...6): return (.ultraAdvanced, chip, .iPadPro)  // iPad Pro M2
        case (14, _): return (.enhanced, chip, .iPadAir)  // iPad Air M2, 11-inch and 13-inch
        case (15, 7...8): return (.unsupported, chip, .iPadAir)  // iPad (A16)
        case (15, _): return (.advanced, chip, .iPadAir)  // iPad Air M3
        case (16, 1...2): return (.baseline, chip, .iPadMini)  // iPad mini (A17 Pro)
        case (16, 8...11): return (.ultraAdvanced, chip, .iPadAir)  // iPad Air M4
        case (16, _): return (.ultraAdvanced, chip, .iPadPro)  // iPad Pro M4
        case (17, _): return (.ultraAdvanced, chip, .iPadPro)  // iPad Pro M5
        case (19, 1...2): return (.ultraAdvanced, chip, .iPadMini)  // iPad mini (A20 Pro)
        case (18..., _): return (.ultraAdvanced, chip, .iPadPro)  // newer than this build
        default: return (.unsupported, chip, .iPadAir)
        }
    }

    /// The chip name the screens show and the ceilings key off (5.8). On a device it is the chip Metal names
    /// ("Apple A18 Pro GPU" on the owner's iPhone 16 Pro Max), which the hardware reports and no table can get wrong;
    /// the table's name is the fallback when Metal gives none. The Simulator keeps the simulated device's name,
    /// because its Metal device is the Mac's.
    nonisolated static func resolvedChipName(tableName: String, metalDeviceName: String, isSimulator: Bool) -> String {
        guard !isSimulator, let metalChip = AppleDeviceCatalog.chipName(fromMetalDeviceName: metalDeviceName) else {
            return tableName
        }
        return metalChip
    }

    /// Generation number out of an Apple Silicon brand string, e.g. "Apple M6 Max" -> 6.
    ///
    /// Deliberately anchored to a standalone `M<digits>` token so it cannot match the
    /// `M` in an unrelated word, and so "M12" reads as twelve rather than one.
    /// `nonisolated static` because it is a pure function over a string and is unit
    /// tested without constructing the service.
    nonisolated static func appleSiliconGeneration(in brandString: String) -> Int? {
        guard let range = brandString.range(
            of: "\\bM([0-9]+)\\b",
            options: [.regularExpression]
        ) else { return nil }
        return Int(brandString[range].dropFirst())
    }

    /// The CPU's core clusters as the system names and counts them (`hw.perflevelN.name` and `.physicalcpu`), for
    /// example [("Performance", 2), ("Efficiency", 4)] on an A18 Pro. Apple calls the top cores "super cores" from the
    /// A20 Pro and M5 on, so the names are read, not assumed. Empty where the system reports no clusters.
    nonisolated static func detectCPUClusters() -> [(name: String, cores: Int)] {
        var levels = 0
        var size = MemoryLayout<Int32>.size
        var value: Int32 = 0
        guard sysctlbyname("hw.nperflevels", &value, &size, nil, 0) == 0 else { return [] }
        levels = Int(value)
        var clusters: [(name: String, cores: Int)] = []
        for level in 0 ..< max(0, levels) {
            var cores: Int32 = 0
            var coreSize = MemoryLayout<Int32>.size
            guard sysctlbyname("hw.perflevel\(level).physicalcpu", &cores, &coreSize, nil, 0) == 0, cores > 0 else { continue }
            var nameSize = 0
            var name = "Level \(level)"
            if sysctlbyname("hw.perflevel\(level).name", nil, &nameSize, nil, 0) == 0, nameSize > 0 {
                var buffer = [CChar](repeating: 0, count: nameSize)
                if sysctlbyname("hw.perflevel\(level).name", &buffer, &nameSize, nil, 0) == 0 {
                    let read = String(cString: buffer)
                    if !read.isEmpty { name = read }
                }
            }
            clusters.append((name, Int(cores)))
        }
        return clusters
    }

    private static func detectMemoryGB() -> Double {
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        return Double(memoryBytes) / (1024 * 1024 * 1024)
    }

    private static func detectMetalHardwareSnapshot() -> MetalHardwareSnapshot {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return .unavailable
        }

        // `maxThreadsPerThreadgroup` is an MTLSize of per-dimension maxima, not a
        // volume. Multiplying the axes produced 1024 * 1024 * 1024 = 1,073,741,824,
        // which the Hardware Envelope card displayed as a thread count. No
        // threadgroup can hold a billion threads; the real ceiling is the width.
        let maxThreads = device.maxThreadsPerThreadgroup
        let threadCount = Int(maxThreads.width)

        return MetalHardwareSnapshot(
            deviceName: device.name,
            hasUnifiedMemory: device.hasUnifiedMemory,
            recommendedWorkingSetMB: Int(device.recommendedMaxWorkingSetSize / 1_048_576),
            maxBufferLengthMB: Int(device.maxBufferLength / 1_048_576),
            maxThreadsPerThreadgroup: threadCount,
            maxThreadgroupMemoryKB: Int(device.maxThreadgroupMemoryLength / 1024),
            highestAppleFamily: (1 ... 11).reversed().first { family in
                MTLGPUFamily(rawValue: 1000 + family).map { device.supportsFamily($0) } ?? false
            }
        )
    }

    private func chipIsAtLeast(_ chipPrefix: String) -> Bool {
        if cachedChipName.hasPrefix(chipPrefix) {
            return true
        }
        // Handle simulated or sub-branded host chips (e.g., "Simulator on M3 Pro", "iPadAppOnMac:M3")
        let words = cachedChipName.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.contains(chipPrefix)
    }

    private static func describeComputeUnits(_ units: MLComputeUnits) -> String {
        switch units {
        case .all:
            return "Auto (CPU + GPU + Neural Engine)"
        case .cpuOnly:
            return "CPU only"
        case .cpuAndGPU:
            return "CPU + GPU"
        case .cpuAndNeuralEngine:
            return "CPU + Neural Engine"
        @unknown default:
            return "System default"
        }
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
            • Identifier: \(deviceIdentifier)
            • Tier: \(tier.displayName)(\(tier.rawValue))
                • Chip: \(chipName)
                • Memory: \(String(format: "%.1f", memoryGB)) GB
            • Neural Engine: \(npuTopsDescription ?? "Apple publishes no figure")
                • Metal: \(metalSnapshot.deviceName) • \(metalSnapshot.workingSetDescription) working set
                • Form Factor: \(formFactor.rawValue)
                • Apple Intelligence: \(supportsAppleIntelligence ? "✓" : "✗")
                • Vision OCR Ceiling: \(visionOperationConcurrency) ops @ \(visionOperationCooldownMilliseconds)ms
                • Max Agentic Steps: \(maxConcurrentAgenticSteps)
                • Token Budget: \(maxAgenticTokenBudget)
            """, category: .initialization)
    }
}
