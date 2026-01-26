//
//  DeviceCapabilityService.swift
//  OpenIntelligence
//
//  Detects device hardware capabilities to optimize RAG/LLM configuration.
//  Adjusts agentic loop parameters based on chipset generation.
//

import Foundation
import UIKit
import CoreML

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

    /// Neural Engine core count
    var neuralEngineCores: Int {
        switch self {
        case .baseline: return 16 // A17 Pro
        case .enhanced: return 16 // A18/A18 Pro
        case .advanced: return 16 // A19 (projected)
        case .ultraAdvanced: return 16 // M-series typically 16
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
    case mac // MacBook Air, MacBook Pro, Mac mini, iMac, Mac Studio, Mac Pro
    case unknown

    /// Whether device has active cooling
    var hasActiveCooling: Bool {
        self == .iPadPro || self == .mac
    }

    /// Recommended max concurrent operations
    var recommendedConcurrency: Int {
        switch self {
        case .iPhone: return 2
        case .iPadMini: return 2
        case .iPadAir: return 3
        case .iPadPro: return 4
        case .mac: return 6 // Macs have better thermal headroom
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
    private let cachedNPUTops: Int // Accurate TOPS for this specific chip

    private init() {
        let (tier, chip, formFactor, identifier, tops) = Self.detectFullCapability()
        cachedTier = tier
        cachedChipName = chip
        cachedFormFactor = formFactor
        cachedDeviceIdentifier = identifier
        cachedNPUTops = tops
        cachedMemoryGB = Self.detectMemoryGB()

        // Set sensible default GPU acceleration if never set (0.0 means unset)
        // Balanced (0.5) is a good default - uses ANE primarily with GPU assist
        if UserDefaults.standard.double(forKey: "gpuAccelerationLevel") == 0.0 {
            UserDefaults.standard.set(0.5, forKey: "gpuAccelerationLevel")
        }
    }

    // MARK: - Public API

    /// Current device capability tier
    var tier: DeviceCapabilityTier { cachedTier }

    /// Chip name (e.g., "A17 Pro", "A18", "M2")
    var chipName: String { cachedChipName }

    /// Accurate NPU TOPS for this specific chip
    var npuTops: Int { cachedNPUTops }

    /// Available RAM in GB
    var memoryGB: Double { cachedMemoryGB }

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

    /// Whether device has thermal headroom for sustained workloads
    var hasThermalHeadroom: Bool {
        // iPads have more thermal mass, iPad Pro has fan, Macs have active cooling
        isIPad || isMac || cachedTier >= .advanced
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

    // MARK: - Vector Operation Batch Sizes (Accelerate/BNNS)

    /// Recommended batch size for vector similarity operations using Accelerate/BNNS.
    ///
    /// These values are tuned for the Neural Engine memory bandwidth and cache hierarchy:
    /// - Smaller batches: Better for thermal-constrained devices (iPhone)
    /// - Larger batches: Better for high-bandwidth devices (iPad Pro, M-series)
    ///
    /// Used by BNNSVectorDatabase for vDSP_mmul batch matrix operations.
    var vectorBatchSize: Int {
        switch cachedTier {
        case .unsupported: return 64
        case .baseline: return 256 // A17 Pro: Conservative to avoid ANE throttling
        case .enhanced: return 512 // A18: Better Neural Engine bandwidth
        case .advanced: return 768 // A19: Projected improvement
        case .ultraAdvanced: return 1024 // M-series: Maximum throughput
        }
    }

    /// Recommended batch size for embedding generation.
    ///
    /// Larger batches amortize CoreML model loading overhead but risk memory pressure.
    var embeddingBatchSize: Int {
        switch cachedTier {
        case .unsupported: return 8
        case .baseline: return 16 // A17 Pro: Conservative memory usage
        case .enhanced: return 24 // A18: Better memory bandwidth
        case .advanced: return 32 // A19: Projected
        case .ultraAdvanced: return 48 // M-series with 8GB+ RAM
        }
    }

    /// Threshold above which to use batch matrix multiply vs individual dot products.
    ///
    /// Batch matrix multiply has overhead but scales better for large chunk counts.
    /// Below this threshold, individual vDSP_dotpr calls are faster.
    var batchMatrixMultiplyThreshold: Int {
        switch cachedTier {
        case .unsupported: return Int.max // Never use batch
        case .baseline: return 500 // A17 Pro: Conservative threshold
        case .enhanced: return 300 // A18: Earlier switch to batch
        case .advanced: return 200 // A19: More aggressive batching
        case .ultraAdvanced: return 100 // M-series: Batch almost always
        }
    }

    /// Maximum chunks to process in a single vector search before yielding.
    ///
    /// Prevents UI jank during large searches by breaking work into cooperative chunks.
    var maxChunksPerSearchYield: Int {
        switch cachedTier {
        case .unsupported: return 100
        case .baseline: return 500
        case .enhanced: return 1000
        case .advanced: return 2000
        case .ultraAdvanced: return 5000
        }
    }

    // MARK: - Document Ingestion Optimization

    /// Maximum concurrent pages for Vision structured parsing.
    ///
    /// Vision's RecognizeDocumentsRequest runs on Neural Engine + GPU.
    /// VisionOCRThrottle limits to 2 concurrent Vision ops with GPU sync.
    /// We set batch size slightly higher (3-4) to keep the pipeline fed,
    /// since rendering/preprocessing can overlap with Vision processing.
    var visionParsingConcurrency: Int {
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 3   // A17 Pro
        case .enhanced: return 4   // A18 Pro
        case .advanced: return 4   // A19 Pro
        case .ultraAdvanced: return 5  // M-series
        }
    }

    /// Maximum concurrent pages for PDF OCR extraction.
    ///
    /// VisionOCRThrottle limits actual Vision calls to 2 concurrent.
    /// Higher batch size allows rendering/preprocessing to overlap.
    var ocrExtractionConcurrency: Int {
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 4   // A17 Pro
        case .enhanced: return 5   // A18 Pro
        case .advanced: return 6   // A19 Pro
        case .ultraAdvanced: return 8 // M-series
        }
    }

    /// Maximum concurrent embedding requests.
    ///
    /// CoreML embedding runs on ANE; limited parallelism prevents throttling.
    /// GPU boost increases parallelism for faster ingestion.
    var embeddingConcurrency: Int {
        let gpuBoost = gpuAccelerationLevel > 0.7
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return gpuBoost ? 10 : 6  // A17 Pro
        case .enhanced: return gpuBoost ? 14 : 8  // A18 Pro
        case .advanced: return gpuBoost ? 16 : 10 // A19 Pro
        case .ultraAdvanced: return gpuBoost ? 20 : 12 // M-series
        }
    }

    // MARK: - GPU Acceleration Settings

    /// GPU acceleration level for ingestion (0.0 = Neural Engine only, 1.0 = Maximum GPU)
    /// User-configurable via Settings. Higher values use more GPU but generate more heat.
    ///
    /// Levels:
    /// - 0.0-0.3: Efficiency mode (ANE preferred, minimal GPU)
    /// - 0.3-0.6: Balanced mode (ANE + some GPU for image processing)
    /// - 0.6-0.9: Performance mode (GPU for CoreML + image processing)
    /// - 1.0: Maximum mode (Force GPU for everything possible, high heat)
    var gpuAccelerationLevel: Double {
        get { UserDefaults.standard.double(forKey: "gpuAccelerationLevel") }
        set { UserDefaults.standard.set(newValue, forKey: "gpuAccelerationLevel") }
    }

    /// CoreML compute units based on GPU acceleration level
    var preferredComputeUnits: MLComputeUnits {
        let level = gpuAccelerationLevel
        if level >= 0.9 {
            return .cpuAndGPU  // Force GPU, bypass Neural Engine
        } else if level >= 0.6 {
            return .all  // Let system choose (may use GPU for some ops)
        } else {
            return .cpuAndNeuralEngine  // Prefer ANE for efficiency
        }
    }

    /// Whether to use GPU-backed CIContext for PDF rendering
    var useGPUForPDFRendering: Bool {
        gpuAccelerationLevel >= 0.3
    }

    /// Maximum concurrent GPU operations (image processing, rendering)
    var gpuConcurrency: Int {
        let level = gpuAccelerationLevel
        if level >= 0.9 {
            // Maximum GPU mode - push GPU hard
            switch cachedTier {
            case .unsupported: return 4
            case .baseline: return 8   // A17 Pro GPU
            case .enhanced: return 10  // A18 Pro GPU
            case .advanced: return 12  // A19 Pro projected
            case .ultraAdvanced: return 16 // M-series GPU
            }
        } else if level >= 0.6 {
            // Performance mode
            switch cachedTier {
            case .unsupported: return 2
            case .baseline: return 5
            case .enhanced: return 6
            case .advanced: return 8
            case .ultraAdvanced: return 10
            }
        } else {
            // Efficiency/balanced mode
            return 2
        }
    }

    /// Whether to use Metal compute shaders for vector operations
    var useMetalForVectorOps: Bool {
        gpuAccelerationLevel >= 0.6
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
                confidenceThreshold: 0.80, // Stop earlier to save battery
                    escalationThreshold: 0.30
            )

        case .enhanced:
            // A18/A18 Pro: Balanced performance
            return AgenticConfig(
                maxSteps: 6,
                maxTotalTokens: 24000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.85,
                escalationThreshold: 0.35
            )

        case .advanced:
            // A19/A19 Pro: More aggressive
            return AgenticConfig(
                maxSteps: 8,
                maxTotalTokens: 32000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.90,
                escalationThreshold: 0.40
            )

        case .ultraAdvanced:
            // M-series / future: Full power
            return AgenticConfig(
                maxSteps: 10,
                maxTotalTokens: 48000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.95,
                escalationThreshold: 0.45
            )
        }
    }

    // MARK: - Detection Logic

    private static func detectFullCapability() -> (DeviceCapabilityTier, String, DeviceFormFactor, String, Int) {
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
                    let (tier, chip, tops) = detectiPhoneCapability(identifier: simDevice)
                    return (tier, chip, .iPhone, "Simulator:\(simDevice)", tops)
                }
                if simDevice.hasPrefix("iPad") {
                    let (tier, chip, formFactor, tops) = detectiPadCapabilityFull(identifier: simDevice)
                    return (tier, chip, formFactor, "Simulator:\(simDevice)", tops)
                }
            }

            // Detect the HOST Mac's capabilities for accurate performance estimation
            // The simulator runs on your Mac, so we can use Mac-level performance
            let hostMac = detectHostMacCapability()
            return (hostMac.tier, "Simulator on \(hostMac.chip)", .mac, "Simulator:HostMac", hostMac.tops)
        #else
        // iPhone detection
        if identifier.hasPrefix("iPhone") {
            let (tier, chip, tops) = detectiPhoneCapability(identifier: identifier)
            return (tier, chip, .iPhone, identifier, tops)
        }

        // iPad detection (also covers iPad apps running on Mac via compatibility)
        if identifier.hasPrefix("iPad") {
            let (tier, chip, formFactor, tops) = detectiPadCapabilityFull(identifier: identifier)
            // Check if we're actually running on a Mac (iPad app on Mac)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                // Running as iPad app on Mac - detect the actual Mac
                let hostMac = detectHostMacCapability()
                return (hostMac.tier, hostMac.chip, .mac, "iPadAppOnMac:\(identifier)", hostMac.tops)
            }

            return (tier, chip, formFactor, identifier, tops)
        }

        // Mac detection (native Mac apps via Catalyst)
        if identifier.hasPrefix("Mac") {
            let (tier, chip, tops) = detectMacCapability(identifier: identifier)
            return (tier, chip, .mac, identifier, tops)
        }

        // Fallback for unknown devices
        return (.unsupported, "Unknown", .unknown, identifier, 0)
        #endif
    }

    /// Detect host Mac capabilities using sysctl for accurate chip identification
    /// This is used when running in Simulator or as iPad app on Mac
    private static func detectHostMacCapability() -> (tier: DeviceCapabilityTier, chip: String, tops: Int) {
        // Try to get the actual chip brand string from sysctl
        // This works on macOS but may fail in iOS Simulator
        var size = 0
        let result = sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        // Check if sysctl succeeded and returned a valid size
        guard result == 0, size > 0 else {
            // Fallback: Check if we're on Apple Silicon by looking at architecture
            #if arch(arm64)
                // We're on Apple Silicon but can't determine exact chip
                // Use ProcessInfo to get some hints
                let physicalMemory = ProcessInfo.processInfo.physicalMemory
                let memoryGB = Double(physicalMemory) / (1024 * 1024 * 1024)

                // Estimate chip based on memory (rough heuristic)
                if memoryGB >= 128 {
                    return (.ultraAdvanced, "M-series Ultra", 45)
                } else if memoryGB >= 64 {
                    return (.ultraAdvanced, "M-series Max", 38)
                } else if memoryGB >= 32 {
                    return (.ultraAdvanced, "M-series Pro", 18)
                } else if memoryGB >= 16 {
                    return (.advanced, "M-series", 18)
                } else {
                    return (.enhanced, "M-series", 16)
                }
            #else
                // Intel Mac - not Apple Intelligence capable
                return (.unsupported, "Intel Mac", 0)
            #endif
        }

        var brandString = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brandString, &size, nil, 0)

        // Safely convert to String
        let cpuBrand = String(cString: brandString)

        // Check if we got a valid string
        guard !cpuBrand.isEmpty else {
            #if arch(arm64)
                return (.advanced, "Apple Silicon", 18)
            #else
                return (.unsupported, "Intel Mac", 0)
            #endif
        }

        // Parse Apple Silicon chip from brand string
        // Examples: "Apple M1", "Apple M2 Pro", "Apple M3 Max", "Apple M4"
        if cpuBrand.contains("Apple") {
            if cpuBrand.contains("M5 Ultra") {
                return (.ultraAdvanced, "M5 Ultra", 90)
            } else if cpuBrand.contains("M5 Max") {
                return (.ultraAdvanced, "M5 Max", 45)
            } else if cpuBrand.contains("M5 Pro") {
                return (.ultraAdvanced, "M5 Pro", 45)
            } else if cpuBrand.contains("M5") {
                return (.ultraAdvanced, "M5", 45)
            } else if cpuBrand.contains("M4 Ultra") {
                return (.ultraAdvanced, "M4 Ultra", 76)
            } else if cpuBrand.contains("M4 Max") {
                return (.ultraAdvanced, "M4 Max", 38)
            } else if cpuBrand.contains("M4 Pro") {
                return (.ultraAdvanced, "M4 Pro", 38)
            } else if cpuBrand.contains("M4") {
                return (.ultraAdvanced, "M4", 38)
            } else if cpuBrand.contains("M3 Ultra") {
                return (.ultraAdvanced, "M3 Ultra", 36)
            } else if cpuBrand.contains("M3 Max") {
                return (.ultraAdvanced, "M3 Max", 18)
            } else if cpuBrand.contains("M3 Pro") {
                return (.ultraAdvanced, "M3 Pro", 18)
            } else if cpuBrand.contains("M3") {
                return (.advanced, "M3", 18)
            } else if cpuBrand.contains("M2 Ultra") {
                return (.ultraAdvanced, "M2 Ultra", 32)
            } else if cpuBrand.contains("M2 Max") {
                return (.ultraAdvanced, "M2 Max", 16)
            } else if cpuBrand.contains("M2 Pro") {
                return (.ultraAdvanced, "M2 Pro", 16)
            } else if cpuBrand.contains("M2") {
                return (.enhanced, "M2", 16)
            } else if cpuBrand.contains("M1 Ultra") {
                return (.ultraAdvanced, "M1 Ultra", 22)
            } else if cpuBrand.contains("M1 Max") {
                return (.enhanced, "M1 Max", 11)
            } else if cpuBrand.contains("M1 Pro") {
                return (.enhanced, "M1 Pro", 11)
            } else if cpuBrand.contains("M1") {
                return (.enhanced, "M1", 11)
            }
        }

        // Fallback - assume modern Apple Silicon if we can't determine
        #if arch(arm64)
            return (.advanced, "Apple Silicon", 18)
        #else
            return (.unsupported, "Intel Mac", 0)
        #endif
    }

    private static func detectCapabilityTier() -> (DeviceCapabilityTier, String) {
        let (tier, chip, _, _, _) = detectFullCapability()
        return (tier, chip)
    }

    private static func detectiPhoneCapability(identifier: String) -> (DeviceCapabilityTier, String, Int) {
        // Extract major/minor version numbers from identifier
        // Format: iPhoneXX,Y where XX is major generation
        let numbers = identifier.replacingOccurrences(of: "iPhone", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            return (.unsupported, "iPhone (Unknown)", 0)
        }

        let major = numbers[0]
        let minor = numbers[1]

        // iPhone generations (major number in identifier):
        // iPhone 15 Pro/Pro Max: iPhone16,1 / iPhone16,2 (A17 Pro - 35 TOPS)
        // iPhone 15/15 Plus: iPhone15,4 / iPhone15,5 (A16 - NOT AI capable)
        // iPhone 16 series: iPhone17,x (A18/A18 Pro - 35/38 TOPS)
        // iPhone 17 series: iPhone18,x (A19/A19 Pro - projected 40/45 TOPS)

        switch major {
        case 16:
            // iPhone 15 Pro (16,1) and Pro Max (16,2) have A17 Pro
            if minor <= 2 {
                return (.baseline, "A17 Pro", 35)
            }
            // iPhone 15 (16,3) and 15 Plus (16,4) have A16 - NOT AI capable
            return (.unsupported, "A16 Bionic", 0)

        case 17:
            // iPhone 16 series (2024)
            // Pro models (17,1 and 17,2) have A18 Pro
            // Standard models (17,3 and 17,4) have A18
            if minor <= 2 {
                return (.enhanced, "A18 Pro", 38)
            }
            return (.enhanced, "A18", 35)

        case 18:
            // iPhone 17 series (2025)
            if minor <= 2 {
                return (.advanced, "A19 Pro", 45)
            }
            return (.advanced, "A19", 40)

            case 19:
                // iPhone 18 series (2026)
                if minor <= 2
            {
                return (.ultraAdvanced, "A20 Pro", 50)
            }

            return (.ultraAdvanced, "A20", 48)

            case 20...:
            // Future iPhones
            return (.ultraAdvanced, "A\(major + 1) Pro", 55)

        default:
            return (.unsupported, "Legacy iPhone", 0)
        }
    }

    /// Full iPad detection returning tier, chip, form factor, AND accurate TOPS
    private static func detectiPadCapabilityFull(identifier: String) -> (DeviceCapabilityTier, String, DeviceFormFactor, Int) {
        let numbers = identifier.replacingOccurrences(of: "iPad", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard numbers.count >= 2 else {
            return (.unsupported, "iPad (Unknown)", .iPadAir, 0)
        }

        let major = numbers[0]
        let minor = numbers[1]

        // Comprehensive iPad model mapping with form factors and accurate TOPS:
        // M1: 11 TOPS (16-core Neural Engine)
        // M2: 15.8 TOPS (16-core Neural Engine, improved)
        // M3: 18 TOPS (16-core Neural Engine, 3nm)
        // M4: 38 TOPS (16-core Neural Engine, major upgrade)
        //
        // iPad13,4-11 = iPad Pro M1 (2021) - 11" and 12.9"
        // iPad14,1-2 = iPad mini 6 (A15 - NOT Apple Intelligence capable)
        // iPad14,3-6 = iPad Pro M2 (2022) - 11" and 12.9"
        // iPad14,8-9 = iPad Air M2 (2024) - 11" and 13"
        // iPad15,3-6 = iPad Air M3 (2025)
        // iPad16,3-6 = iPad Pro M4 (2024) - 11" and 13" OLED
        // iPad17+ = Future iPads (M5+)

        switch major {
        case 13:
            // iPad Pro M1 (2021) - 11 TOPS
            if minor >= 4 {
                return (.enhanced, "M1", .iPadPro, 11)
            }
            return (.unsupported, "Legacy iPad", .iPadAir, 0)

        case 14:
            // iPad mini 6 (14,1-2) has A15 - 15.8 TOPS but not AI capable
            if minor <= 2 {
                return (.unsupported, "A15 Bionic", .iPadMini, 0)
            }
            // iPad Pro M2 (14,3-6) - 2022 - 15.8 TOPS
            if minor >= 3, minor <= 6 {
                return (.ultraAdvanced, "M2", .iPadPro, 16)
            }
            // iPad Air M2 (14,8-9) - 2024 - 15.8 TOPS
            if minor >= 8 {
                return (.enhanced, "M2", .iPadAir, 16)
            }
            return (.unsupported, "Unknown iPad14", .iPadAir, 0)

        case 15:
            // iPad Air M3 (2025) - 18 TOPS
            return (.advanced, "M3", .iPadAir, 18)

        case 16:
            // iPad Pro M4 (2024) - OLED models - 38 TOPS
            return (.ultraAdvanced, "M4", .iPadPro, 38)

            case 17:
                // iPad Pro M5 (2026) - projected ~45 TOPS
                return (.ultraAdvanced, "M5", .iPadPro, 45)

        case 18...:
            // Future iPads - assume Pro tier with increasing TOPS
            let estimatedTops = 45 + (major - 17) * 5
        return (.ultraAdvanced, "M\(major - 12)", .iPadPro, estimatedTops)

        default:
            return (.unsupported, "Legacy iPad", .iPadAir, 0)
        }
    }

    /// Detect Mac capability - all Apple Silicon Macs are capable
    /// Returns (tier, chipName, accurateTOPS)
    private static func detectMacCapability(identifier: String) -> (DeviceCapabilityTier, String, Int) {
        // Mac identifiers use format: MacXX,Y
        //
        // M-series Neural Engine TOPS (actual Apple specs):
        // M1: 11 TOPS (16-core Neural Engine)
        // M1 Pro/Max: 11 TOPS (same Neural Engine)
        // M1 Ultra: 22 TOPS (2x Neural Engines)
        // M2: 15.8 TOPS (16-core Neural Engine, improved)
        // M2 Pro/Max: 15.8 TOPS
        // M2 Ultra: 31.6 TOPS (2x Neural Engines)
        // M3: 18 TOPS (16-core Neural Engine, 3nm)
        // M3 Pro/Max: 18 TOPS
        // M4: 38 TOPS (16-core Neural Engine, major upgrade)
        // M4 Pro: 38 TOPS
        // M4 Max: 38 TOPS (single die)
        // M5 (2025-2026): ~45 TOPS projected
        //
        // Notable Mac identifiers:
        // Mac13,x = M1 Pro/Max/Ultra Macs (2021)
        // Mac14,2 = MacBook Air M2 (2022)
        // Mac14,3 = Mac mini M2 (2023)
        // Mac14,5 = MacBook Pro 14" M2 Pro (2023)
        // Mac14,6 = MacBook Pro 16" M2 Pro (2023)
        // Mac14,7 = MacBook Pro 13" M2 (2022)
        // Mac14,8 = Mac Pro M2 Ultra (2023)
        // Mac14,9 = MacBook Pro 14" M2 Max (2023)
        // Mac14,10 = MacBook Pro 16" M2 Max (2023)
        // Mac14,12 = Mac mini M2 Pro (2023)
        // Mac14,13 = Mac Studio M2 Max (2023)
        // Mac14,14 = Mac Studio M2 Ultra (2023)
        // Mac14,15 = MacBook Air 15" M2 (2023)
        // Mac15,3 = MacBook Pro 14" M3 (2023)
        // Mac15,4 = iMac 24" M3 (2023)
        // Mac15,5 = iMac 24" M3 (2023)
        // Mac15,6 = MacBook Pro 14" M3 Pro (2023)
        // Mac15,7 = MacBook Pro 16" M3 Pro (2023)
        // Mac15,8 = MacBook Pro 14" M3 Max (2023)
        // Mac15,9 = MacBook Pro 16" M3 Max (2023)
        // Mac15,10 = MacBook Pro 16" M3 Max (2023)
        // Mac15,11 = MacBook Pro 14" M3 Max (2023)
        // Mac15,12 = MacBook Air 13" M3 (2024)
        // Mac15,13 = MacBook Air 15" M3 (2024)
        // Mac16,x = M4 Macs (2024-2025)
        // Mac17,x = M5 Macs (2025-2026)

        let numbers = identifier.replacingOccurrences(of: "Mac", with: "")
            .split(separator: ",")
            .compactMap { Int($0) }

        guard !numbers.isEmpty else {
            // If we can't parse but it starts with "Mac", assume modern Apple Silicon
            return (.ultraAdvanced, "Apple Silicon Mac", 38)
        }

        let major = numbers[0]
        let minor = numbers.count >= 2 ? numbers[1] : 1

        switch major {
        case 13:
            // Mac13,x = M1 Pro/Max/Ultra Macs (2021)
            // Minor 1-2: Mac Studio M1 Max/Ultra
            if minor == 2 {
                return (.ultraAdvanced, "M1 Ultra", 22) // 2x Neural Engines
            }
            return (.enhanced, "M1 Pro/Max", 11)

        case 14:
            // Mac14,x = M2 family
            switch minor {
            case 8:
                // Mac Pro M2 Ultra
                return (.ultraAdvanced, "M2 Ultra", 32)
            case 14:
                // Mac Studio M2 Ultra
                return (.ultraAdvanced, "M2 Ultra", 32)
            case 5, 6, 12:
                // M2 Pro (MacBook Pro, Mac mini Pro)
                return (.ultraAdvanced, "M2 Pro", 16)
            case 9, 10, 13:
                // M2 Max (MacBook Pro, Mac Studio Max)
                return (.ultraAdvanced, "M2 Max", 16)
            default:
                // Base M2 (MacBook Air, MacBook Pro 13", Mac mini)
                return (.enhanced, "M2", 16)
            }

        case 15:
            // Mac15,x = M3 family
            switch minor {
            case 6, 7:
                // MacBook Pro M3 Pro
                return (.ultraAdvanced, "M3 Pro", 18)
            case 8, 9, 10, 11:
                // MacBook Pro M3 Max
                return (.ultraAdvanced, "M3 Max", 18)
            default:
                // Base M3 (iMac, MacBook Air, base MacBook Pro 14")
                return (.advanced, "M3", 18)
            }

        case 16:
            // Mac16,x = M4 family (2024-2025)
            // M4 has significantly upgraded Neural Engine: 38 TOPS
            switch minor {
            case 1 ... 4:
                // M4 MacBook Pro, iMac, Mac mini
                return (.ultraAdvanced, "M4", 38)
            case 5 ... 8:
                // M4 Pro variants
                return (.ultraAdvanced, "M4 Pro", 38)
            case 9 ... 12:
                // M4 Max variants
                return (.ultraAdvanced, "M4 Max", 38)
            default:
                return (.ultraAdvanced, "M4", 38)
            }

            case 17:
                // Mac17,x = M5 family (2025-2026)
                // Projected ~45 TOPS based on typical generational improvement
                switch minor
            {
            case 1 ... 4:
                return (.ultraAdvanced, "M5", 45)
            case 5 ... 8:
                return (.ultraAdvanced, "M5 Pro", 45)
            case 9 ... 12:
                return (.ultraAdvanced, "M5 Max", 45)
            case 13...:
                return (.ultraAdvanced, "M5 Ultra", 90) // Dual-die
            default:
                return (.ultraAdvanced, "M5", 45)
            }

        case 18...:
            // Future Macs (M6+)
            // Estimate TOPS based on generation with ~15% improvement per year
            let chipGen = major - 12 // Mac18 = M6, Mac19 = M7, etc.
        let estimatedTops = 45 + (major - 17) * 7 // ~15% annual improvement
        return (.ultraAdvanced, "M\(chipGen)", estimatedTops)

        default:
            // Intel Macs (Mac12 and below) - not Apple Intelligence capable
            return (.unsupported, "Intel Mac", 0)
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
            • Identifier: \(deviceIdentifier)
            • Tier: \(tier.displayName)(\(tier.rawValue))
                • Chip: \(chipName)
                • Memory: \(String(format: "%.1f", memoryGB)) GB
            • NPU: \(npuTops) TOPS
                • Form Factor: \(formFactor.rawValue)
                • Apple Intelligence: \(supportsAppleIntelligence ? "✓" : "✗")
                • Max Agentic Steps: \(maxConcurrentAgenticSteps)
                • Token Budget: \(maxAgenticTokenBudget)
            """, category: .initialization)
    }
}
