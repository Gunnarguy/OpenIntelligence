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

struct MetalHardwareSnapshot: Sendable {
    let deviceName: String
    let hasUnifiedMemory: Bool
    let recommendedWorkingSetMB: Int
    let maxBufferLengthMB: Int
    let maxThreadsPerThreadgroup: Int
    let maxThreadgroupMemoryKB: Int

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
    let npuTops: Int
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
    let pdfPageMemory360MB: Int
    let pdfPageMemory432MB: Int
    let embeddingConcurrency: Int
    let embeddingBatchSize: Int
    let vectorBatchSize: Int
    let batchMatrixMultiplyThreshold: Int
    let gpuConcurrency: Int
}

/// Comprehensive device capability detection
final class DeviceCapabilityService: @unchecked Sendable {
    static let shared = DeviceCapabilityService()

    private nonisolated static let ingestionExecutionProfileLock = NSLock()
    private nonisolated(unsafe) static var ingestionExecutionProfileStorage: IngestionExecutionProfile = .interactive

    private let cachedTier: DeviceCapabilityTier
    private let cachedChipName: String
    private let cachedMemoryGB: Double
    private let cachedFormFactor: DeviceFormFactor
    private let cachedDeviceIdentifier: String
    private let cachedNPUTops: Int // Accurate TOPS for this specific chip
    private let cachedMetalSnapshot: MetalHardwareSnapshot

    private init() {
        let (tier, chip, formFactor, identifier, tops) = Self.detectFullCapability()
        cachedTier = tier
        cachedChipName = chip
        cachedFormFactor = formFactor
        cachedDeviceIdentifier = identifier
        cachedNPUTops = tops
        cachedMemoryGB = Self.detectMemoryGB()
        cachedMetalSnapshot = Self.detectMetalHardwareSnapshot()

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

    /// Whether device has thermal headroom for sustained workloads
    var hasThermalHeadroom: Bool {
        // iPads have more thermal mass, iPad Pro has fan, Macs have active cooling
        isIPad || isMac || cachedTier >= .advanced
    }

    /// Whether Apple Intelligence is available on this device
    var supportsAppleIntelligence: Bool {
        cachedTier != .unsupported
    }

    /// Highest GPU level this device should sustain without pushing into crash-prone territory.
    var maxSafeGPUAccelerationLevel: Double {
        if isMac {
            return 1.0
        }

        switch cachedFormFactor {
        case .iPadPro:
            return 1.0
        case .iPadAir:
            return cachedTier >= .advanced ? 1.0 : 0.9
        case .iPadMini:
            return 0.7
        case .iPhone:
            switch cachedTier {
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

    /// Requested level after applying per-hardware ceilings.
    var activeGPUAccelerationLevel: Double {
        min(gpuAccelerationLevel, maxSafeGPUAccelerationLevel)
    }

    /// Actual Vision OCR concurrency ceiling used to avoid Metal command buffer instability.
    var visionOperationConcurrency: Int {
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
            pdfPageMemory360MB: estimatedPDFPageMegabytes(at: 360),
            pdfPageMemory432MB: estimatedPDFPageMegabytes(at: 432),
            embeddingConcurrency: embeddingConcurrency,
            embeddingBatchSize: embeddingBatchSize,
            vectorBatchSize: vectorBatchSize,
            batchMatrixMultiplyThreshold: batchMatrixMultiplyThreshold,
            gpuConcurrency: gpuConcurrency
        )
    }

    func estimatedPDFPageMegabytes(at dpi: Int) -> Int {
        let baselineMB = 206.0
        let scaleFactor = Double(dpi) / 360.0
        return Int((baselineMB * scaleFactor * scaleFactor).rounded())
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

    /// Recommended batch size for vector similarity operations using Accelerate/BNNS.
    ///
    /// These values are tuned for the Neural Engine memory bandwidth and cache hierarchy:
    /// - Smaller batches: Better for thermal-constrained devices (iPhone)
    /// - Larger batches: Better for high-bandwidth devices (iPad Pro, M-series)
    ///
    /// Used by BNNSVectorDatabase for vDSP_mmul batch matrix operations.
    /// STABLE: Reduced after Metal command buffer crashes at MAX POWER.
    var vectorBatchSize: Int {
        // CRANKED: Larger batch sizes amortize dispatch overhead.
        // Apple9+ 64-bit atomics enable lock-free batch coordination.
        // vDSP_mmul is highly optimized for these sizes on Apple Silicon.
        switch cachedTier {
        case .unsupported: return 128
        case .baseline: return 512    // A17 Pro: vDSP handles this easily
        case .enhanced: return 768    // A18 Pro: larger batches for throughput
        case .advanced: return 1024   // A19 Pro: full SIMD utilization
        case .ultraAdvanced: return 1536 // M-series: maximum batch throughput
        }
    }

    /// Recommended batch size for embedding generation.
    ///
    /// Larger batches amortize CoreML model loading overhead.
    /// Metal Feature Set: Apple9+ has 256KB implicit imageblock and improved memory.
    /// MiniLM-L6-v2 uses ~100MB; these batch sizes fit comfortably.
    /// STABLE: Reduced for pipeline stability.
    var embeddingBatchSize: Int {
        // CRANKED: Larger batches amortize CoreML model loading overhead.
        // MiniLM-L6-v2 uses ~100MB; these batch sizes fit comfortably.
        // Bigger batches = fewer model invocations = faster ingestion.
        switch cachedTier {
        case .unsupported: return 8
        case .baseline: return 24   // A17 Pro: boosted from 16
        case .enhanced: return 32   // A18 Pro: boosted from 24
        case .advanced: return 48   // A19 Pro: full throughput
        case .ultraAdvanced: return 64 // M-series: maximum batch
        }
    }

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
        case .ultraAdvanced: return 20000 // M-series: unlimited
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
    var visionParsingConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        // Mac check - active cooling allows sustained throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 4
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 16
            }
            if chipIsAtLeast("M3") {
                return 12
            }
            if chipIsAtLeast("M2") || chipIsAtLeast("M1") {
                return 8
            }
            return 8
        }

        // iOS devices: 2x VisionOCRThrottle limits for pipeline saturation
        // Pipeline pre-renders pages ahead of Vision to keep ANE saturated
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 8   // A17 Pro: 2x the 4 Vision ops
        case .enhanced: return 12  // A18 Pro: 2x the 6 Vision ops
        case .advanced: return 16  // A19 Pro: 2x the 8 Vision ops
        case .ultraAdvanced: return 12 // M-series iPad: 2x + headroom
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

        // Mac check - active cooling allows sustained throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 4
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 16
            }
            if chipIsAtLeast("M3") {
                return 12
            }
            if chipIsAtLeast("M2") || chipIsAtLeast("M1") {
                return 8
            }
            return 8
        }

        // iOS devices - 2x VisionOCRThrottle for pipeline saturation
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 8   // A17 Pro: 2x the 4 Vision ops
        case .enhanced: return 12  // A18 Pro: 2x the 6 Vision ops
        case .advanced: return 16  // A19 Pro: 2x the 8 Vision ops
        case .ultraAdvanced: return 12 // M-series iPad: 2x + headroom
        }
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
                return 6
            }
            return 6
        }
        // CRANKED: Modern devices have plenty of RAM for concurrent page images.
        // Images are released immediately after Vision OCR completes per page.
        // At 360 DPI, 206 MB/page: 4 pages = 824 MB (well within 8 GB headroom)
        switch cachedTier {
        case .unsupported: return 1
        case .baseline: return 3   // A17 Pro: ~6 GB RAM, 3 × 206 MB = 618 MB (safe)
        case .enhanced: return 4   // A18 Pro: ~8 GB RAM, 4 × 206 MB = 824 MB
        case .advanced: return 5   // A19 Pro: ~8 GB RAM, 5 × 206 MB = 1.0 GB (fine with fast release)
        case .ultraAdvanced: return 5 // M-series iPad: 8-16 GB RAM
        }
    }

    /// Maximum concurrent embedding requests.
    ///
    /// CoreML embedding uses ANE (16-core Neural Engine) + optional GPU fallback.
    /// Metal Feature Set: SIMD-scoped matrix multiply available on Apple7+.
    /// STABLE: Reduced after Metal synchronizeResource crashes.
    /// GPU boost mode disabled - caused Metal command buffer conflicts.
    var embeddingConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 2
        }

        // Mac check - active cooling allows sustained GPU embedding throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 4
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 24
            }
            if chipIsAtLeast("M3") {
                return 16
            }
            if chipIsAtLeast("M2") || chipIsAtLeast("M1") {
                return 12
            }
            return 12
        }

        // CRANKED: Embeddings run on GPU during ingestion (freeing ANE for Vision).
        // Higher concurrency = more chunks embedded per second = faster ingestion.
        // GPU has dedicated bandwidth separate from ANE.
        switch cachedTier {
        case .unsupported: return 2
        case .baseline: return 12  // A17 Pro: GPU is underutilized during OCR
        case .enhanced: return 16  // A18 Pro: 6-core GPU, plenty of headroom
        case .advanced: return 20  // A19 Pro: scaled GPU throughput
        case .ultraAdvanced: return 16 // M-series iPad: balanced with other GPU work
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
        if isBackgroundCPUSafeIngestionActive {
            return .cpuOnly
        }

        let level = activeGPUAccelerationLevel
        if level >= 0.9 {
            return .cpuAndGPU  // Force GPU, bypass Neural Engine
        } else if level >= 0.6 {
            return .all  // Let system choose (may use GPU for some ops)
        } else {
            return .cpuAndNeuralEngine  // Prefer ANE for efficiency
        }
    }

    /// Force embeddings to GPU during ingestion to parallelize with Vision OCR on ANE
    ///
    /// Vision OCR is ANE-bound. Running embeddings on GPU simultaneously creates true parallelism:
    /// - ANE: Vision OCR (text recognition)
    /// - GPU: CoreML embeddings (MiniLM-L6-v2)
    ///
    /// This prevents ANE contention and can nearly double ingestion throughput.
    var embeddingComputeUnitsDuringIngestion: MLComputeUnits {
        if isBackgroundCPUSafeIngestionActive {
            return .cpuOnly
        }

        // Always use GPU for embeddings during ingestion to free ANE for Vision
        // GPU is 5-6% utilized during ingestion - let's put it to work!
        switch cachedTier {
        case .unsupported:
            return .cpuAndNeuralEngine  // Older devices may not have good GPU CoreML support
        case .baseline, .enhanced, .advanced, .ultraAdvanced:
            return .cpuAndGPU  // Force GPU, leave ANE for Vision OCR
        }
    }

    /// Whether to use GPU-backed CIContext for PDF rendering
    var useGPUForPDFRendering: Bool {
        if isBackgroundCPUSafeIngestionActive {
            return false
        }

        return activeGPUAccelerationLevel >= 0.3
    }

    /// Maximum concurrent GPU operations (image processing, rendering)
    ///
    /// Metal Feature Set Tables:
    /// - Apple9 (A17 Pro): 6-core GPU, 1024 threads/group, 32KB threadgroup mem
    /// - Apple10 (A18/A18 Pro): 5-6 core GPU, improved scheduling
    /// - All support Metal 3 & 4, ray tracing, mesh shaders
    /// STABLE: Reduced after MTLDebugBlitCommandEncoder crashes.
    ///
    /// IMPORTANT: Mac needs LOWER values despite more GPU cores!
    /// macOS Metal command buffer scheduling differs from iOS.
    var gpuConcurrency: Int {
        if isBackgroundCPUSafeIngestionActive {
            return 1
        }

        // Mac check - active cooling allows sustained GPU throughput
        if isMac || ProcessInfo.processInfo.isiOSAppOnMac {
            if cachedTier == .unsupported {
                return 2
            }
            if chipIsAtLeast("M5") || chipIsAtLeast("M4") {
                return 12
            }
            if chipIsAtLeast("M3") {
                return 8
            }
            if chipIsAtLeast("M2") || chipIsAtLeast("M1") {
                return 6
            }
            return 6
        }

        let level = activeGPUAccelerationLevel
        if level >= 0.9 {
            // Maximum mode - CRANKED maximums for iOS
            switch cachedTier {
            case .unsupported: return 2
            case .baseline: return 10   // A17 Pro: 6-core GPU, boosted
            case .enhanced: return 14   // A18 Pro: 6-core GPU, full utilization
            case .advanced: return 16   // A19 Pro: next-gen GPU cores
            case .ultraAdvanced: return 12 // M-series iPad: thermal-limited
            }
        } else if level >= 0.6 {
            // Performance mode
            switch cachedTier {
            case .unsupported: return 2
            case .baseline: return 8
            case .enhanced: return 10
            case .advanced: return 12
            case .ultraAdvanced: return 8 // M-series iPad
            }
        } else if level >= 0.3 {
            // Balanced mode - GPU-backed PDF rendering + moderate concurrency
            switch cachedTier {
            case .unsupported: return 2
            case .baseline: return 6    // A17 Pro: light GPU assist
            case .enhanced: return 8    // A18 Pro: moderate GPU assist
            case .advanced: return 8    // A19 Pro: moderate GPU assist
            case .ultraAdvanced: return 6 // M-series iPad
            }
        } else {
            // Efficiency mode - minimal GPU usage
            return 4
        }
    }

    /// Whether to use Metal compute shaders for vector operations
    var useMetalForVectorOps: Bool {
        if isBackgroundCPUSafeIngestionActive {
            return false
        }

        return activeGPUAccelerationLevel >= 0.6
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
            // M-series / future: Full power, highest quality
            return AgenticConfig(
                maxSteps: 12,
                maxTotalTokens: 56000,
                streamIntermediateResults: true,
                confidenceThreshold: 0.95,
                escalationThreshold: 0.50
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

    private static func detectMetalHardwareSnapshot() -> MetalHardwareSnapshot {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return .unavailable
        }

        let maxThreads = device.maxThreadsPerThreadgroup
        let threadCount = Int(maxThreads.width * maxThreads.height * maxThreads.depth)

        return MetalHardwareSnapshot(
            deviceName: device.name,
            hasUnifiedMemory: device.hasUnifiedMemory,
            recommendedWorkingSetMB: Int(device.recommendedMaxWorkingSetSize / 1_048_576),
            maxBufferLengthMB: Int(device.maxBufferLength / 1_048_576),
            maxThreadsPerThreadgroup: threadCount,
            maxThreadgroupMemoryKB: Int(device.maxThreadgroupMemoryLength / 1024)
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
            • NPU: \(npuTops) TOPS
                • Metal: \(metalSnapshot.deviceName) • \(metalSnapshot.workingSetDescription) working set
                • Form Factor: \(formFactor.rawValue)
                • Apple Intelligence: \(supportsAppleIntelligence ? "✓" : "✗")
                • Vision OCR Ceiling: \(visionOperationConcurrency) ops @ \(visionOperationCooldownMilliseconds)ms
                • Max Agentic Steps: \(maxConcurrentAgenticSteps)
                • Token Budget: \(maxAgenticTokenBudget)
            """, category: .initialization)
    }
}
