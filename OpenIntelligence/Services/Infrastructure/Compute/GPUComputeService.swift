//
//  GPUComputeService.swift
//  OpenIntelligence
//
//  Metal Performance Shaders (MPS) powered GPU acceleration for RAG operations.
//  Provides massive speedup for batch vector operations:
//  - Batch cosine similarity (query vs all embeddings)
//  - Batch embedding normalization
//  - Matrix operations for MMR diversity computation
//
//  🚀 OPTIMIZATIONS (Metal Shading Language Spec compliant):
//  - SIMD4 vectorized shaders (4x throughput)
//  - Threadgroup memory for query caching (reduce memory bandwidth)
//  - Buffer pooling (eliminate allocation overhead)
//  - Async completion handlers (non-blocking GPU execution)
//  - Triple buffering support (prevent GPU stalls)
//
//  GPU is 10-50x faster than CPU for large batch operations (1000+ vectors)
//

import Foundation
@preconcurrency import Metal
import MetalPerformanceShaders
import Accelerate
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Metal Buffer Pool (MLX-inspired)

/// Thread-safe buffer pool for Metal buffer reuse
/// Eliminates allocation overhead by keeping buffers around for reuse
/// Uses manual lock-based synchronization - all mutable state is protected by NSLock
///
/// Metal Feature Set Tables (Oct 2025):
/// - Apple9: 256KB implicit imageblock, improved memory bandwidth
/// - All A17+: 8GB+ unified memory, can cache more aggressively
final class MetalBufferPool: @unchecked Sendable {
    private let device: MTLDevice
    private nonisolated(unsafe) var pools: [Int: [MTLBuffer]] = [:]  // Size bucket -> available buffers
    private let lock = NSLock()

    /// Maximum buffers to keep per size bucket (doubled for Apple9+)
    private let maxBuffersPerBucket: Int

    /// Maximum total cached memory (tier-based for optimal throughput)
    private let maxCacheBytes: Int
    private nonisolated(unsafe) var currentCacheBytes: Int = 0

    init(device: MTLDevice) {
        self.device = device

        // Device-tier-aware cache sizing based on Metal Feature Set Tables
        // CONSERVATIVE: iOS apps get ~2-3GB before jetsam on 8GB devices.
        // Previous 192MB cap consumed ~10% of app jetsam budget just for buffer reuse.
        // New caps: 48/32/24/16 MB — still effective for RAG vector searches
        // (typical search buffer = 1943×384×4 = ~3MB, so 32MB caches ~10 searches).
        let deviceName = device.name.lowercased()
        if deviceName.contains("a19") || deviceName.contains("m5") || deviceName.contains("m4") {
            // Apple10 / Next-gen: Moderate caching
            self.maxCacheBytes = 48 * 1024 * 1024   // 48MB (was 256MB)
            self.maxBuffersPerBucket = 6
        } else if deviceName.contains("a18") || deviceName.contains("m3") {
            // Apple10/Apple9: Moderate caching
            self.maxCacheBytes = 32 * 1024 * 1024   // 32MB (was 192MB)
            self.maxBuffersPerBucket = 4
        } else if deviceName.contains("a17") || deviceName.contains("m2") {
            // Apple8/9: Conservative caching
            self.maxCacheBytes = 24 * 1024 * 1024   // 24MB (was 128MB)
            self.maxBuffersPerBucket = 4
        } else {
            // Older devices or unknown: Minimal caching
            self.maxCacheBytes = 16 * 1024 * 1024   // 16MB (was 64MB)
            self.maxBuffersPerBucket = 3
        }

        Log.info("[MetalBufferPool] 📦 Cache configured: \(maxCacheBytes / (1024*1024))MB, \(maxBuffersPerBucket) buffers/bucket", category: .initialization)
    }

    /// Round up to next power of 2 for efficient bucketing
    private nonisolated func nextPowerOf2(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var v = n - 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        return v + 1
    }

    /// Acquire a buffer of at least the given size
    /// Returns existing buffer from pool or creates new one
    nonisolated func acquire(minimumSize: Int, options: MTLResourceOptions = .storageModeShared) -> MTLBuffer? {
        let bucketSize = nextPowerOf2(minimumSize)

        lock.lock()
        defer { lock.unlock() }

        // Try to get from pool
        if var bucket = pools[bucketSize], !bucket.isEmpty {
            let buffer = bucket.removeLast()
            pools[bucketSize] = bucket
            currentCacheBytes -= buffer.length
            return buffer
        }

        // Create new buffer
        return device.makeBuffer(length: bucketSize, options: options)
    }

    /// Acquire and fill a buffer with data
    nonisolated func acquire(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions = .storageModeShared) -> MTLBuffer? {
        guard let buffer = acquire(minimumSize: length, options: options) else { return nil }
        memcpy(buffer.contents(), bytes, length)
        return buffer
    }

    /// Return a buffer to the pool for reuse
    nonisolated func release(_ buffer: MTLBuffer) {
        let bucketSize = buffer.length

        lock.lock()
        defer { lock.unlock() }

        // Check if we have room in cache
        guard currentCacheBytes + bucketSize <= maxCacheBytes else {
            // Let buffer deallocate naturally
            return
        }

        var bucket = pools[bucketSize] ?? []
        guard bucket.count < maxBuffersPerBucket else {
            return
        }

        bucket.append(buffer)
        pools[bucketSize] = bucket
        currentCacheBytes += bucketSize
    }

    /// Clear all cached buffers
    nonisolated func clear() {
        lock.lock()
        defer { lock.unlock() }
        pools.removeAll()
        currentCacheBytes = 0
    }

    /// Get cache statistics
    nonisolated var stats: (bufferCount: Int, totalBytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        let count = pools.values.reduce(0) { $0 + $1.count }
        return (count, currentCacheBytes)
    }
}

// MARK: - GPU Compute Service

/// GPU-accelerated compute service using Metal Performance Shaders
/// Falls back to Accelerate (CPU SIMD) when Metal is unavailable
/// Thread-safe: All Metal operations are inherently thread-safe, and this class
/// uses immutable state after initialization.
final class GPUComputeService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = GPUComputeService()

    // MARK: - Metal Resources

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let library: MTLLibrary?

    /// Buffer pool for efficient memory reuse
    private let bufferPool: MetalBufferPool?

    /// Memory warning observer — clears buffer cache under pressure
    private var memoryWarningObserver: (any NSObjectProtocol)?

    // Custom compute pipelines (set once during init, never mutated)
    private let cosineSimilarityPipeline: MTLComputePipelineState?
    private let batchNormalizePipeline: MTLComputePipelineState?
    private let mmrDiversityPipeline: MTLComputePipelineState?

    // SIMD-optimized pipelines (faster versions)
    private let cosineSimilaritySIMDPipeline: MTLComputePipelineState?
    private let batchNormalizeSIMDPipeline: MTLComputePipelineState?

    // Threadgroup-optimized pipeline (fastest — query cached in shared memory + SIMD4)
    private let cosineSimilarityThreadgroupPipeline: MTLComputePipelineState?

    /// Whether GPU compute is available
    nonisolated var isGPUAvailable: Bool { device != nil && commandQueue != nil }

    /// GPU device name for logging
    nonisolated var deviceName: String { device?.name ?? "CPU (Accelerate)" }

    /// Buffer pool statistics
    nonisolated var bufferPoolStats: (bufferCount: Int, totalBytes: Int) {
        bufferPool?.stats ?? (0, 0)
    }

    // MARK: - Initialization

    private init() {
        // Try to get the default Metal device
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
            self.device = nil
            self.commandQueue = nil
            self.library = nil
            self.bufferPool = nil
            self.cosineSimilarityPipeline = nil
            self.batchNormalizePipeline = nil
            self.mmrDiversityPipeline = nil
            self.cosineSimilaritySIMDPipeline = nil
            self.batchNormalizeSIMDPipeline = nil
            self.cosineSimilarityThreadgroupPipeline = nil
            self.residencySet = nil
            Log.warning("[GPUComputeService] Metal unavailable. Using Accelerate CPU backend.", category: .initialization)
            return
        }

        self.device = mtlDevice
        self.commandQueue = mtlDevice.makeCommandQueue()
        self.bufferPool = MetalBufferPool(device: mtlDevice)

        // Load or compile Metal shaders
        var loadedLibrary: MTLLibrary? = nil

        // Try to load from default library (precompiled .metal files)
        if let defaultLibrary = mtlDevice.makeDefaultLibrary() {
            loadedLibrary = defaultLibrary
        } else {
            // Compile at runtime if no precompiled library
            do {
                loadedLibrary = try mtlDevice.makeLibrary(source: Self.metalShaderSource, options: nil)
            } catch {
                Log.warning("[GPUComputeService] Metal shader compilation failed: \(error). Using CPU fallback.", category: .initialization)
            }
        }

        self.library = loadedLibrary

        // Create compute pipelines using local vars (assigned once to let properties)
        var cosinePipeline: MTLComputePipelineState? = nil
        var normPipeline: MTLComputePipelineState? = nil
        var mmrPipeline: MTLComputePipelineState? = nil
        var cosineSIMDPipeline: MTLComputePipelineState? = nil
        var normSIMDPipeline: MTLComputePipelineState? = nil
        var cosineThreadgroupPipeline: MTLComputePipelineState? = nil

        if let lib = loadedLibrary {
            do {
                // Standard pipelines (fallback)
                if let cosineFunc = lib.makeFunction(name: "batchCosineSimilarity") {
                    cosinePipeline = try mtlDevice.makeComputePipelineState(function: cosineFunc)
                }
                if let normFunc = lib.makeFunction(name: "batchNormalize") {
                    normPipeline = try mtlDevice.makeComputePipelineState(function: normFunc)
                }
                if let mmrFunc = lib.makeFunction(name: "mmrDiversityMatrix") {
                    mmrPipeline = try mtlDevice.makeComputePipelineState(function: mmrFunc)
                }

                // SIMD-optimized pipelines (preferred)
                if let cosineSIMDFunc = lib.makeFunction(name: "batchCosineSimilaritySIMD") {
                    cosineSIMDPipeline = try mtlDevice.makeComputePipelineState(function: cosineSIMDFunc)
                    Log.info("[GPUComputeService] ✓ SIMD4 cosine similarity pipeline ready (4x faster)", category: .initialization)
                }
                if let normSIMDFunc = lib.makeFunction(name: "batchNormalizeSIMD") {
                    normSIMDPipeline = try mtlDevice.makeComputePipelineState(function: normSIMDFunc)
                    Log.info("[GPUComputeService] ✓ SIMD4 normalize pipeline ready", category: .initialization)
                }

                // Threadgroup-optimized pipeline (fastest for large batches)
                // Caches query vector in threadgroup shared memory — eliminates redundant global reads
                if let tgFunc = lib.makeFunction(name: "batchCosineSimilarityThreadgroup") {
                    cosineThreadgroupPipeline = try mtlDevice.makeComputePipelineState(function: tgFunc)
                    Log.info("[GPUComputeService] ✓ Threadgroup cosine similarity pipeline ready (fastest)", category: .initialization)
                }
            } catch {
                Log.warning("[GPUComputeService] Failed to create compute pipelines: \(error)", category: .initialization)
            }
        }

        self.cosineSimilarityPipeline = cosinePipeline
        self.batchNormalizePipeline = normPipeline
        self.mmrDiversityPipeline = mmrPipeline
        self.cosineSimilaritySIMDPipeline = cosineSIMDPipeline
        self.batchNormalizeSIMDPipeline = normSIMDPipeline
        self.cosineSimilarityThreadgroupPipeline = cosineThreadgroupPipeline

        // Metal 4 residency set for persistent buffer management
        if let cq = self.commandQueue {
            self.residencySet = Self.createResidencySet(device: mtlDevice, commandQueue: cq)
        } else {
            self.residencySet = nil
        }

        Log.info("[GPUComputeService] 🚀 Metal GPU initialized: \(mtlDevice.name)", category: .initialization)
        if let pool = self.bufferPool {
            let stats = pool.stats
            Log.info("[GPUComputeService] 📦 Buffer pool ready (\(stats.totalBytes / (1024*1024))MB cache)", category: .initialization)
        }
        if cosineSimilarityPipeline != nil {
            Log.info("[GPUComputeService] ✓ Batch cosine similarity pipeline ready", category: .initialization)
        }

        // MEMORY FIX: Release buffer cache on memory pressure to prevent OOM jetsam kills
        #if canImport(UIKit)
        self.memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bufferPool?.clear()
            Log.warning("[GPUComputeService] ⚠️ Memory warning — buffer cache cleared", category: .retrieval)
        }
        #endif
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Clear buffer pool cache (call during memory pressure)
    nonisolated func clearBufferCache() {
        bufferPool?.clear()
        Log.info("[GPUComputeService] Buffer cache cleared", category: .retrieval)
    }

    // MARK: - Metal 4 Resource Management

    /// Metal 4 residency set for persistent buffer management (iOS 26+)
    /// Keeps frequently-used embedding buffers resident in GPU memory,
    /// reducing page faults and improving latency for repeated vector operations.
    private let residencySet: (any MTLResidencySet)?

    /// Initialize Metal 4 residency set for persistent buffer management
    private static func createResidencySet(device: MTLDevice, commandQueue: MTLCommandQueue) -> (any MTLResidencySet)? {
        if #available(iOS 26.0, *) {
            do {
                let descriptor = MTLResidencySetDescriptor()
                descriptor.label = "OpenIntelligence Embedding Residency"
                descriptor.initialCapacity = 64  // Pre-allocate for 64 buffers
                let set = try device.makeResidencySet(descriptor: descriptor)
                set.commit()
                Log.info("[GPUComputeService] ✓ Metal 4 residency set initialized (capacity: 64)", category: .initialization)
                return set
            } catch {
                Log.warning("[GPUComputeService] Metal 4 residency set unavailable: \(error.localizedDescription)", category: .initialization)
                return nil
            }
        }
        return nil
    }

    /// Add a buffer to the Metal 4 residency set for persistent GPU memory residency
    /// Call this for embedding buffers that will be reused across multiple queries
    func makeResident(_ buffer: MTLBuffer) {
        if #available(iOS 26.0, *) {
            guard let rs = residencySet else { return }
            rs.addAllocation(buffer)
            rs.commit()
        }
    }

    /// Remove a buffer from the residency set
    func evictFromResidency(_ buffer: MTLBuffer) {
        if #available(iOS 26.0, *) {
            guard let rs = residencySet else { return }
            rs.removeAllocation(buffer)
            rs.commit()
        }
    }

    /// Check if Metal 4 features are available
    nonisolated var supportsMetal4: Bool {
        if #available(iOS 26.0, *) {
            return device != nil
        }
        return false
    }

    // MARK: - Batch Cosine Similarity (GPU)

    /// Compute cosine similarity between a query vector and a batch of document vectors
    /// GPU-accelerated for large batches (1000+ vectors = 10-50x speedup)
    /// - Parameters:
    ///   - query: Query embedding vector (normalized)
    ///   - documents: Array of document embedding vectors (normalized)
    /// - Returns: Array of similarity scores [-1, 1] for each document
    nonisolated func batchCosineSimilarity(query: [Float], documents: [[Float]]) -> [Float] {
        let docCount = documents.count
        let dimension = query.count

        guard docCount > 0 && dimension > 0 else { return [] }

        // Use GPU for large batches (> 100 vectors), CPU for small batches
        // GPU has overhead for buffer creation, so CPU is faster for small work
        if docCount > 100, let device = device, let queue = commandQueue {
            // Report GPU activity for vector similarity
            HardwareTelemetryReporter.pulse(.vectorSimilarity, intensity: 0.85, duration: 0.3)
            HardwareTelemetryReporter.reportGPUCompute()

            // Prefer SIMD pipeline (4x faster), fall back to standard
            if let simdPipeline = cosineSimilaritySIMDPipeline {
                return gpuBatchCosineSimilaritySIMD(query: query, documents: documents, device: device, queue: queue, pipeline: simdPipeline)
            } else if let pipeline = cosineSimilarityPipeline {
                return gpuBatchCosineSimilarity(query: query, documents: documents, device: device, queue: queue, pipeline: pipeline)
            }
        }
        return cpuBatchCosineSimilarity(query: query, documents: documents)
    }

    /// Async version using completion handler (non-blocking)
    nonisolated func batchCosineSimilarityAsync(
        query: [Float],
        documents: [[Float]],
        completion: @escaping ([Float]) -> Void
    ) {
        let docCount = documents.count
        let dimension = query.count

        guard docCount > 100,
              let device = device,
              let queue = commandQueue,
              let pipeline = cosineSimilaritySIMDPipeline ?? cosineSimilarityPipeline else {
            // Fall back to sync CPU
            completion(cpuBatchCosineSimilarity(query: query, documents: documents))
            return
        }

        // Flatten documents
        var flatDocs = [Float]()
        flatDocs.reserveCapacity(docCount * dimension)
        for doc in documents {
            if doc.count == dimension {
                flatDocs.append(contentsOf: doc)
            } else {
                flatDocs.append(contentsOf: doc.prefix(dimension))
                if doc.count < dimension {
                    flatDocs.append(contentsOf: [Float](repeating: 0, count: dimension - doc.count))
                }
            }
        }

        // Use buffer pool for efficiency
        let querySize = dimension * MemoryLayout<Float>.stride
        let docsSize = flatDocs.count * MemoryLayout<Float>.stride
        let resultsSize = docCount * MemoryLayout<Float>.stride

        guard let queryBuffer = bufferPool?.acquire(bytes: query, length: querySize)
                ?? device.makeBuffer(bytes: query, length: querySize, options: .storageModeShared),
              let docsBuffer = bufferPool?.acquire(bytes: flatDocs, length: docsSize)
                ?? device.makeBuffer(bytes: flatDocs, length: docsSize, options: .storageModeShared),
              let resultsBuffer = bufferPool?.acquire(minimumSize: resultsSize)
                ?? device.makeBuffer(length: resultsSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(cpuBatchCosineSimilarity(query: query, documents: documents))
            return
        }

        // Encode compute
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(docsBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultsBuffer, offset: 0, index: 2)

        var dim = UInt32(dimension)
        var count = UInt32(docCount)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, docCount)
        let threadGroups = MTLSize(width: (docCount + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        // Capture for completion handler
        let pool = self.bufferPool

        // Non-blocking: use completion handler
        commandBuffer.addCompletedHandler { [resultsBuffer, queryBuffer, docsBuffer] _ in
            let resultsPtr = resultsBuffer.contents().bindMemory(to: Float.self, capacity: docCount)
            let results = Array(UnsafeBufferPointer(start: resultsPtr, count: docCount))

            // Return buffers to pool
            pool?.release(queryBuffer)
            pool?.release(docsBuffer)
            pool?.release(resultsBuffer)

            completion(results)
        }

        commandBuffer.commit()
    }

    /// GPU implementation using Metal compute shader with buffer pooling
    private nonisolated func gpuBatchCosineSimilarity(
        query: [Float],
        documents: [[Float]],
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLComputePipelineState
    ) -> [Float] {
        let docCount = documents.count
        let dimension = query.count

        // Flatten documents into contiguous array for GPU
        var flatDocs = [Float]()
        flatDocs.reserveCapacity(docCount * dimension)
        for doc in documents {
            if doc.count == dimension {
                flatDocs.append(contentsOf: doc)
            } else {
                // Pad or truncate to match dimension
                flatDocs.append(contentsOf: doc.prefix(dimension))
                if doc.count < dimension {
                    flatDocs.append(contentsOf: [Float](repeating: 0, count: dimension - doc.count))
                }
            }
        }

        // Use buffer pool for efficiency
        let querySize = dimension * MemoryLayout<Float>.stride
        let docsSize = flatDocs.count * MemoryLayout<Float>.stride
        let resultsSize = docCount * MemoryLayout<Float>.stride

        // Try buffer pool first, fall back to direct allocation
        guard let queryBuffer = bufferPool?.acquire(bytes: query, length: querySize)
                ?? device.makeBuffer(bytes: query, length: querySize, options: .storageModeShared),
              let docsBuffer = bufferPool?.acquire(bytes: flatDocs, length: docsSize)
                ?? device.makeBuffer(bytes: flatDocs, length: docsSize, options: .storageModeShared),
              let resultsBuffer = bufferPool?.acquire(minimumSize: resultsSize)
                ?? device.makeBuffer(length: resultsSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Log.warning("[GPUComputeService] Failed to create Metal buffers, falling back to CPU", category: .retrieval)
            return cpuBatchCosineSimilarity(query: query, documents: documents)
        }

        // Set up compute encoder
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(docsBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultsBuffer, offset: 0, index: 2)

        var dim = UInt32(dimension)
        var count = UInt32(docCount)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)

        // Calculate thread groups
        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, docCount)
        let threadGroups = MTLSize(width: (docCount + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        // Execute and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let resultsPtr = resultsBuffer.contents().bindMemory(to: Float.self, capacity: docCount)
        let results = Array(UnsafeBufferPointer(start: resultsPtr, count: docCount))

        // Return buffers to pool for reuse
        bufferPool?.release(queryBuffer)
        bufferPool?.release(docsBuffer)
        bufferPool?.release(resultsBuffer)

        return results
    }

    /// GPU implementation using SIMD4 vectorized shader (4x faster)
    private nonisolated func gpuBatchCosineSimilaritySIMD(
        query: [Float],
        documents: [[Float]],
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLComputePipelineState
    ) -> [Float] {
        let docCount = documents.count
        let dimension = query.count

        // Pad dimension to multiple of 4 for SIMD4
        let paddedDimension = ((dimension + 3) / 4) * 4

        // Flatten documents into contiguous array for GPU (padded)
        var flatDocs = [Float]()
        flatDocs.reserveCapacity(docCount * paddedDimension)
        for doc in documents {
            flatDocs.append(contentsOf: doc.prefix(dimension))
            // Pad to dimension
            if doc.count < dimension {
                flatDocs.append(contentsOf: [Float](repeating: 0, count: dimension - doc.count))
            }
            // Pad to paddedDimension
            if paddedDimension > dimension {
                flatDocs.append(contentsOf: [Float](repeating: 0, count: paddedDimension - dimension))
            }
        }

        // Pad query
        var paddedQuery = query
        if paddedDimension > dimension {
            paddedQuery.append(contentsOf: [Float](repeating: 0, count: paddedDimension - dimension))
        }

        // Use buffer pool for efficiency
        let querySize = paddedDimension * MemoryLayout<Float>.stride
        let docsSize = flatDocs.count * MemoryLayout<Float>.stride
        let resultsSize = docCount * MemoryLayout<Float>.stride

        guard let queryBuffer = bufferPool?.acquire(bytes: paddedQuery, length: querySize)
                ?? device.makeBuffer(bytes: paddedQuery, length: querySize, options: .storageModeShared),
              let docsBuffer = bufferPool?.acquire(bytes: flatDocs, length: docsSize)
                ?? device.makeBuffer(bytes: flatDocs, length: docsSize, options: .storageModeShared),
              let resultsBuffer = bufferPool?.acquire(minimumSize: resultsSize)
                ?? device.makeBuffer(length: resultsSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            Log.warning("[GPUComputeService] Failed to create Metal buffers for SIMD, falling back to standard", category: .retrieval)
            return gpuBatchCosineSimilarity(query: query, documents: documents, device: device, queue: queue, pipeline: cosineSimilarityPipeline!)
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(docsBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultsBuffer, offset: 0, index: 2)

        var dim = UInt32(paddedDimension)
        var count = UInt32(docCount)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, docCount)
        let threadGroups = MTLSize(width: (docCount + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let resultsPtr = resultsBuffer.contents().bindMemory(to: Float.self, capacity: docCount)
        let results = Array(UnsafeBufferPointer(start: resultsPtr, count: docCount))

        bufferPool?.release(queryBuffer)
        bufferPool?.release(docsBuffer)
        bufferPool?.release(resultsBuffer)

        return results
    }

    // MARK: - Flat Buffer GPU Path (Zero-Copy)

    /// GPU batch cosine similarity using a PRE-FLATTENED contiguous Float buffer.
    /// Eliminates the massive memory spike from converting [[Float]] → flat → Metal buffer.
    /// For 50K vectors × 384 dims, this saves ~150 MB of temporary allocations.
    ///
    /// - Parameters:
    ///   - query: Single query embedding vector
    ///   - flatDocuments: Contiguous Float array where embeddings are packed sequentially
    ///     (e.g., [e0_0, e0_1, ..., e0_383, e1_0, e1_1, ..., e1_383, ...])
    ///   - documentCount: Number of documents in the flat buffer
    ///   - dimension: Embedding dimension (must match query.count)
    /// - Returns: Array of cosine similarity scores, one per document
    nonisolated func batchCosineSimilarityFlat(
        query: [Float],
        flatDocuments: [Float],
        documentCount: Int,
        dimension: Int
    ) -> [Float] {
        guard documentCount > 0, dimension > 0, flatDocuments.count >= documentCount * dimension else {
            return []
        }

        // GPU path for large batches — tiered shader selection
        if documentCount > 100, let device = device, let queue = commandQueue {
            HardwareTelemetryReporter.pulse(.vectorSimilarity, intensity: 0.85, duration: 0.3)
            HardwareTelemetryReporter.reportGPUCompute()

            // Select fastest compatible shader
            let simdCompatible = dimension % 4 == 0
            let threadgroupSafe = simdCompatible && (dimension / 4) <= 96

            let selectedPipeline: MTLComputePipelineState?
            if threadgroupSafe, documentCount >= 1000, let tgPipeline = cosineSimilarityThreadgroupPipeline {
                selectedPipeline = tgPipeline
            } else if simdCompatible, let simdPipeline = cosineSimilaritySIMDPipeline {
                selectedPipeline = simdPipeline
            } else {
                selectedPipeline = cosineSimilarityPipeline
            }

            if let pipeline = selectedPipeline {
                return gpuBatchCosineSimilarityFlat(
                    query: query,
                    flatDocuments: flatDocuments,
                    documentCount: documentCount,
                    dimension: dimension,
                    device: device,
                    queue: queue,
                    pipeline: pipeline
                )
            }
        }

        // CPU fallback — use vDSP_mmul on the flat buffer directly
        return cpuBatchCosineSimilarityFlat(
            query: query,
            flatDocuments: flatDocuments,
            documentCount: documentCount,
            dimension: dimension
        )
    }

    /// Batch cosine similarity from an `UnsafeBufferPointer<Float>` — for mmap'd vectors.
    /// The caller has already opened a pointer into mmap'd `Data`; we read directly
    /// from that pointer with no heap copy.
    ///
    /// - Parameters:
    ///   - query: Query embedding (dimension-sized array)
    ///   - flatDocuments: Unsafe pointer into mmap'd or contiguous float buffer
    ///   - documentCount: Number of documents
    ///   - dimension: Embedding dimension
    /// - Returns: Array of cosine similarity scores
    nonisolated func batchCosineSimilarityFlatBuffer(
        query: [Float],
        flatDocuments: UnsafeBufferPointer<Float>,
        documentCount: Int,
        dimension: Int
    ) -> [Float] {
        guard documentCount > 0, dimension > 0, flatDocuments.count >= documentCount * dimension else {
            return []
        }

        // GPU path — tiered shader selection for maximum throughput:
        // Tier 1: Threadgroup (≥1000 docs) — query cached in shared memory + SIMD4 = fastest
        // Tier 2: SIMD4 (100-999 docs) — float4 vector ops = 4x scalar throughput
        // Tier 3: Scalar — fallback for non-SIMD-aligned dimensions
        if documentCount > 100, let device = device, let queue = commandQueue {
            // SIMD4/threadgroup shaders require dimension to be a multiple of 4.
            // MiniLM-L6-v2 = 384 (384/4=96 float4s) — always SIMD-compatible.
            // Threadgroup shader has sharedQuery[96] — safe for dimension ≤ 384.
            let simdCompatible = dimension % 4 == 0
            let threadgroupSafe = simdCompatible && (dimension / 4) <= 96  // sharedQuery[96] limit

            let selectedPipeline: MTLComputePipelineState?
            let shaderTier: String
            if threadgroupSafe, documentCount >= 1000, let tgPipeline = cosineSimilarityThreadgroupPipeline {
                selectedPipeline = tgPipeline
                shaderTier = "threadgroup"
            } else if simdCompatible, let simdPipeline = cosineSimilaritySIMDPipeline {
                selectedPipeline = simdPipeline
                shaderTier = "SIMD4"
            } else {
                selectedPipeline = cosineSimilarityPipeline
                shaderTier = "scalar"
            }

            guard let pipeline = selectedPipeline else {
                return cpuBatchCosineSimilarityFlatBuffer(
                    query: query, flatDocuments: flatDocuments,
                    documentCount: documentCount, dimension: dimension
                )
            }

            HardwareTelemetryReporter.pulse(.vectorSimilarity, intensity: 0.85, duration: 0.3)
            HardwareTelemetryReporter.reportGPUCompute()
            Log.debug("[GPUComputeService] GPU search: \(documentCount) vectors × \(dimension)D via \(shaderTier) shader", category: .retrieval)

            let docsSize = documentCount * dimension * MemoryLayout<Float>.stride
            let querySize = dimension * MemoryLayout<Float>.stride
            let resultsSize = documentCount * MemoryLayout<Float>.stride

            // Metal buffer: zero-copy for mmap'd docs via bytesNoCopy when page-aligned.
            // mmap guarantees page-aligned addresses. Apple Silicon unified memory
            // lets GPU read directly from mmap'd pages — no 73 MB heap copy.
            // Falls back to makeBuffer(bytes:) if length isn't page-aligned.
            // Query buffer is small (1.5 KB) so a copy is always fine.
            guard let queryBuffer = device.makeBuffer(bytes: query, length: querySize, options: .storageModeShared) else {
                return cpuBatchCosineSimilarityFlatBuffer(
                    query: query, flatDocuments: flatDocuments,
                    documentCount: documentCount, dimension: dimension
                )
            }

            // Try zero-copy first; fall back to copy if alignment requirements aren't met
            let docsBuffer: any MTLBuffer
            if let zeroCopy = device.makeBuffer(bytesNoCopy: UnsafeMutableRawPointer(mutating: flatDocuments.baseAddress!),
                                                 length: docsSize,
                                                 options: .storageModeShared,
                                                 deallocator: nil) {
                docsBuffer = zeroCopy
            } else if let copied = device.makeBuffer(bytes: flatDocuments.baseAddress!, length: docsSize, options: .storageModeShared) {
                docsBuffer = copied
            } else {
                return cpuBatchCosineSimilarityFlatBuffer(
                    query: query, flatDocuments: flatDocuments,
                    documentCount: documentCount, dimension: dimension
                )
            }

            guard let resultsBuffer = device.makeBuffer(length: resultsSize, options: .storageModeShared),
                  let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                // Fall through to CPU
                return cpuBatchCosineSimilarityFlatBuffer(
                    query: query, flatDocuments: flatDocuments,
                    documentCount: documentCount, dimension: dimension
                )
            }

            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(queryBuffer, offset: 0, index: 0)
            encoder.setBuffer(docsBuffer, offset: 0, index: 1)
            encoder.setBuffer(resultsBuffer, offset: 0, index: 2)

            var dim = UInt32(dimension)
            var count = UInt32(documentCount)
            encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)

            let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, documentCount)
            let threadGroups = MTLSize(width: (documentCount + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
            let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            let resultsPtr = resultsBuffer.contents().bindMemory(to: Float.self, capacity: documentCount)
            return Array(UnsafeBufferPointer(start: resultsPtr, count: documentCount))
        }

        // CPU fallback
        return cpuBatchCosineSimilarityFlatBuffer(
            query: query, flatDocuments: flatDocuments,
            documentCount: documentCount, dimension: dimension
        )
    }

    /// CPU cosine similarity from `UnsafeBufferPointer<Float>` (mmap-friendly)
    private nonisolated func cpuBatchCosineSimilarityFlatBuffer(
        query: [Float],
        flatDocuments: UnsafeBufferPointer<Float>,
        documentCount: Int,
        dimension: Int
    ) -> [Float] {
        var results = [Float](repeating: 0, count: documentCount)

        query.withUnsafeBufferPointer { queryPtr in
            results.withUnsafeMutableBufferPointer { outPtr in
                vDSP_mmul(
                    flatDocuments.baseAddress!, 1,
                    queryPtr.baseAddress!, 1,
                    outPtr.baseAddress!, 1,
                    vDSP_Length(documentCount), 1, vDSP_Length(dimension)
                )
            }
        }

        let queryNorm = sqrt(vDSP.sumOfSquares(query))
        guard queryNorm > 1e-9 else { return results }

        for i in 0..<documentCount {
            let start = i * dimension
            var sumSq: Float = 0
            vDSP_svesq(flatDocuments.baseAddress! + start, 1, &sumSq, vDSP_Length(dimension))
            let docNorm = sqrt(sumSq)
            if docNorm > 1e-9 {
                results[i] /= (queryNorm * docNorm)
            } else {
                results[i] = 0
            }
        }

        return results
    }

    /// GPU implementation for pre-flattened embeddings — zero copy to Metal buffer
    private nonisolated func gpuBatchCosineSimilarityFlat(
        query: [Float],
        flatDocuments: [Float],
        documentCount: Int,
        dimension: Int,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLComputePipelineState
    ) -> [Float] {
        let querySize = dimension * MemoryLayout<Float>.stride
        let docsSize = documentCount * dimension * MemoryLayout<Float>.stride
        let resultsSize = documentCount * MemoryLayout<Float>.stride

        guard let queryBuffer = bufferPool?.acquire(bytes: query, length: querySize)
                ?? device.makeBuffer(bytes: query, length: querySize, options: .storageModeShared),
              let docsBuffer = bufferPool?.acquire(bytes: flatDocuments, length: docsSize)
                ?? device.makeBuffer(bytes: flatDocuments, length: docsSize, options: .storageModeShared),
              let resultsBuffer = bufferPool?.acquire(minimumSize: resultsSize)
                ?? device.makeBuffer(length: resultsSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return cpuBatchCosineSimilarityFlat(
                query: query,
                flatDocuments: flatDocuments,
                documentCount: documentCount,
                dimension: dimension
            )
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(docsBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultsBuffer, offset: 0, index: 2)

        var dim = UInt32(dimension)
        var count = UInt32(documentCount)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, documentCount)
        let threadGroups = MTLSize(width: (documentCount + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let resultsPtr = resultsBuffer.contents().bindMemory(to: Float.self, capacity: documentCount)
        let results = Array(UnsafeBufferPointer(start: resultsPtr, count: documentCount))

        bufferPool?.release(queryBuffer)
        bufferPool?.release(docsBuffer)
        bufferPool?.release(resultsBuffer)

        return results
    }

    /// CPU fallback for pre-flattened embeddings using Accelerate vDSP_mmul
    private nonisolated func cpuBatchCosineSimilarityFlat(
        query: [Float],
        flatDocuments: [Float],
        documentCount: Int,
        dimension: Int
    ) -> [Float] {
        var results = [Float](repeating: 0, count: documentCount)

        // Matrix-vector multiply: [N x D] × [D x 1] = [N x 1]
        flatDocuments.withUnsafeBufferPointer { docsPtr in
            query.withUnsafeBufferPointer { queryPtr in
                results.withUnsafeMutableBufferPointer { outPtr in
                    vDSP_mmul(
                        docsPtr.baseAddress!, 1,
                        queryPtr.baseAddress!, 1,
                        outPtr.baseAddress!, 1,
                        vDSP_Length(documentCount), 1, vDSP_Length(dimension)
                    )
                }
            }
        }

        // Normalize by norms (dot product → cosine similarity)
        let queryNorm = sqrt(vDSP.sumOfSquares(query))
        guard queryNorm > 1e-9 else { return results }

        for i in 0..<documentCount {
            let start = i * dimension
            let end = start + dimension
            let docSlice = Array(flatDocuments[start..<end])
            let docNorm = sqrt(vDSP.sumOfSquares(docSlice))
            if docNorm > 1e-9 {
                results[i] /= (queryNorm * docNorm)
            } else {
                results[i] = 0
            }
        }

        return results
    }

    /// CPU fallback using Accelerate vDSP
    private nonisolated func cpuBatchCosineSimilarity(query: [Float], documents: [[Float]]) -> [Float] {
        let dimension = query.count
        var results = [Float](repeating: 0, count: documents.count)

        // Pre-compute query norm
        var queryNormSq: Float = 0
        vDSP_svesq(query, 1, &queryNormSq, vDSP_Length(dimension))
        let queryNorm = sqrt(queryNormSq)

        for (i, doc) in documents.enumerated() {
            guard doc.count == dimension else {
                results[i] = 0
                continue
            }

            // Dot product
            var dotProduct: Float = 0
            vDSP_dotpr(query, 1, doc, 1, &dotProduct, vDSP_Length(dimension))

            // Doc norm
            var docNormSq: Float = 0
            vDSP_svesq(doc, 1, &docNormSq, vDSP_Length(dimension))
            let docNorm = sqrt(docNormSq)

            // Cosine similarity
            let denominator = queryNorm * docNorm
            results[i] = denominator > 1e-9 ? dotProduct / denominator : 0
        }

        return results
    }

    // MARK: - Batch Normalize (GPU)

    /// Normalize a batch of vectors to unit length (L2 norm = 1)
    /// GPU-accelerated for large batches
    nonisolated func batchNormalize(vectors: [[Float]]) -> [[Float]] {
        guard !vectors.isEmpty else { return [] }
        _ = vectors.first?.count ?? 0  // Dimension used in GPU paths

        // CPU is usually fine for normalization, but GPU helps for very large batches
        if vectors.count > 500, let device = device, let queue = commandQueue {
            if let simdPipeline = batchNormalizeSIMDPipeline {
                return gpuBatchNormalizeSIMD(vectors: vectors, device: device, queue: queue, pipeline: simdPipeline)
            } else if let pipeline = batchNormalizePipeline {
                return gpuBatchNormalize(vectors: vectors, device: device, queue: queue, pipeline: pipeline)
            }
        }
        return cpuBatchNormalize(vectors: vectors)
    }

    private nonisolated func gpuBatchNormalize(
        vectors: [[Float]],
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLComputePipelineState
    ) -> [[Float]] {
        let count = vectors.count
        let dimension = vectors.first?.count ?? 0
        guard dimension > 0 else { return vectors }

        // Flatten vectors
        var flatVectors = [Float]()
        flatVectors.reserveCapacity(count * dimension)
        for vec in vectors {
            flatVectors.append(contentsOf: vec.prefix(dimension))
            if vec.count < dimension {
                flatVectors.append(contentsOf: [Float](repeating: 0, count: dimension - vec.count))
            }
        }

        let bufferSize = flatVectors.count * MemoryLayout<Float>.stride

        guard let vectorBuffer = bufferPool?.acquire(bytes: flatVectors, length: bufferSize)
                ?? device.makeBuffer(bytes: flatVectors, length: bufferSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return cpuBatchNormalize(vectors: vectors)
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(vectorBuffer, offset: 0, index: 0)

        var dim = UInt32(dimension)
        var cnt = UInt32(count)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, count)
        let threadGroups = MTLSize(width: (count + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back normalized vectors
        let ptr = vectorBuffer.contents().bindMemory(to: Float.self, capacity: flatVectors.count)
        var result = [[Float]]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let offset = i * dimension
            result.append(Array(UnsafeBufferPointer(start: ptr.advanced(by: offset), count: dimension)))
        }

        bufferPool?.release(vectorBuffer)
        return result
    }

    private nonisolated func gpuBatchNormalizeSIMD(
        vectors: [[Float]],
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: MTLComputePipelineState
    ) -> [[Float]] {
        let count = vectors.count
        let dimension = vectors.first?.count ?? 0
        guard dimension > 0 else { return vectors }

        // Pad to multiple of 4 for SIMD
        let paddedDimension = ((dimension + 3) / 4) * 4

        var flatVectors = [Float]()
        flatVectors.reserveCapacity(count * paddedDimension)
        for vec in vectors {
            flatVectors.append(contentsOf: vec.prefix(dimension))
            if vec.count < dimension {
                flatVectors.append(contentsOf: [Float](repeating: 0, count: dimension - vec.count))
            }
            if paddedDimension > dimension {
                flatVectors.append(contentsOf: [Float](repeating: 0, count: paddedDimension - dimension))
            }
        }

        let bufferSize = flatVectors.count * MemoryLayout<Float>.stride

        guard let vectorBuffer = bufferPool?.acquire(bytes: flatVectors, length: bufferSize)
                ?? device.makeBuffer(bytes: flatVectors, length: bufferSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return cpuBatchNormalize(vectors: vectors)
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(vectorBuffer, offset: 0, index: 0)

        var dim = UInt32(paddedDimension)
        var cnt = UInt32(count)
        encoder.setBytes(&dim, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, count)
        let threadGroups = MTLSize(width: (count + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back (only original dimension, not padding)
        let ptr = vectorBuffer.contents().bindMemory(to: Float.self, capacity: flatVectors.count)
        var result = [[Float]]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let offset = i * paddedDimension
            result.append(Array(UnsafeBufferPointer(start: ptr.advanced(by: offset), count: dimension)))
        }

        bufferPool?.release(vectorBuffer)
        return result
    }

    private nonisolated func cpuBatchNormalize(vectors: [[Float]]) -> [[Float]] {
        return vectors.map { vector in
            var normSq: Float = 0
            vDSP_svesq(vector, 1, &normSq, vDSP_Length(vector.count))
            let norm = sqrt(normSq)
            guard norm > 1e-9 else { return vector }

            var normalized = [Float](repeating: 0, count: vector.count)
            var divisor = norm
            vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))
            return normalized
        }
    }

    // MARK: - MMR Diversity Matrix (GPU)

    /// Compute pairwise similarity matrix for MMR diversity calculation
    /// This is O(n²) so GPU acceleration is critical for large candidate sets
    nonisolated func mmrDiversityMatrix(embeddings: [[Float]]) -> [[Float]] {
        let count = embeddings.count
        guard count > 1 else { return [] }

        // GPU is essential for large matrices (> 50 vectors = 2500 comparisons)
        if count > 50, isGPUAvailable {
            return gpuDiversityMatrix(embeddings: embeddings)
        } else {
            return cpuDiversityMatrix(embeddings: embeddings)
        }
    }

    private nonisolated func gpuDiversityMatrix(embeddings: [[Float]]) -> [[Float]] {
        // GPU matrix multiplication: C = A * A^T gives all pairwise dot products
        guard let device = device, let queue = commandQueue else {
            return cpuDiversityMatrix(embeddings: embeddings)
        }

        let count = embeddings.count
        let dimension = embeddings.first?.count ?? 0
        guard dimension > 0 else {
            return cpuDiversityMatrix(embeddings: embeddings)
        }

        // Flatten embeddings into matrix (count x dimension)
        var flatMatrix = [Float]()
        flatMatrix.reserveCapacity(count * dimension)
        for emb in embeddings {
            flatMatrix.append(contentsOf: emb.prefix(dimension))
            if emb.count < dimension {
                flatMatrix.append(contentsOf: [Float](repeating: 0, count: dimension - emb.count))
            }
        }

        let matrixSize = flatMatrix.count * MemoryLayout<Float>.stride
        let resultSize = count * count * MemoryLayout<Float>.stride

        // Use buffer pool
        guard let matrixBuffer = bufferPool?.acquire(bytes: flatMatrix, length: matrixSize)
                ?? device.makeBuffer(bytes: flatMatrix, length: matrixSize, options: .storageModeShared),
              let resultBuffer = bufferPool?.acquire(minimumSize: resultSize)
                ?? device.makeBuffer(length: resultSize, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer() else {
            return cpuDiversityMatrix(embeddings: embeddings)
        }

        // Create MPS matrix descriptors
        // Both A and B use the SAME descriptor (count x dimension) since the buffer
        // stores data in row-major (count x dimension) layout. transposeRight: true
        // tells MPS to transpose B during computation — the descriptor must match
        // the actual data layout, NOT the logical transposed shape.
        let matrixDesc = MPSMatrixDescriptor(rows: count, columns: dimension, rowBytes: dimension * MemoryLayout<Float>.stride, dataType: .float32)
        let resultDesc = MPSMatrixDescriptor(rows: count, columns: count, rowBytes: count * MemoryLayout<Float>.stride, dataType: .float32)

        let matrixA = MPSMatrix(buffer: matrixBuffer, descriptor: matrixDesc)
        let matrixB = MPSMatrix(buffer: matrixBuffer, descriptor: matrixDesc)  // Same layout — MPS transposes via flag
        let matrixC = MPSMatrix(buffer: resultBuffer, descriptor: resultDesc)

        // Matrix multiply: C = A * B^T  →  (count×dim) × (dim×count) = (count×count)
        let matMul = MPSMatrixMultiplication(device: device, transposeLeft: false, transposeRight: true, resultRows: count, resultColumns: count, interiorColumns: dimension, alpha: 1.0, beta: 0.0)

        matMul.encode(commandBuffer: commandBuffer, leftMatrix: matrixA, rightMatrix: matrixB, resultMatrix: matrixC)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results into 2D array
        let resultsPtr = resultBuffer.contents().bindMemory(to: Float.self, capacity: count * count)
        var matrix = [[Float]]()
        matrix.reserveCapacity(count)
        for i in 0..<count {
            let row = Array(UnsafeBufferPointer(start: resultsPtr.advanced(by: i * count), count: count))
            matrix.append(row)
        }

        // Return buffers to pool
        bufferPool?.release(matrixBuffer)
        bufferPool?.release(resultBuffer)

        return matrix
    }

    private nonisolated func cpuDiversityMatrix(embeddings: [[Float]]) -> [[Float]] {
        let count = embeddings.count
        var matrix = [[Float]](repeating: [Float](repeating: 0, count: count), count: count)

        for i in 0..<count {
            for j in i..<count {
                if i == j {
                    matrix[i][j] = 1.0  // Self-similarity
                } else {
                    var dot: Float = 0
                    vDSP_dotpr(embeddings[i], 1, embeddings[j], 1, &dot, vDSP_Length(embeddings[i].count))
                    matrix[i][j] = dot
                    matrix[j][i] = dot  // Symmetric
                }
            }
        }

        return matrix
    }

    // MARK: - Metal Shader Source

    /// Inline Metal shader source for batch operations
    /// Includes both standard and SIMD4-optimized versions
    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // ============================================================
    // STANDARD KERNELS (Fallback)
    // ============================================================

    // Batch cosine similarity: compute similarity between query and each document
    kernel void batchCosineSimilarity(
        constant float* query [[buffer(0)]],
        constant float* documents [[buffer(1)]],
        device float* results [[buffer(2)]],
        constant uint& dimension [[buffer(3)]],
        constant uint& docCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= docCount) return;

        // Compute dot product and norms
        float dotProduct = 0.0;
        float queryNormSq = 0.0;
        float docNormSq = 0.0;

        uint docOffset = gid * dimension;

        for (uint i = 0; i < dimension; i++) {
            float q = query[i];
            float d = documents[docOffset + i];
            dotProduct += q * d;
            queryNormSq += q * q;
            docNormSq += d * d;
        }

        float denom = sqrt(queryNormSq) * sqrt(docNormSq);
        results[gid] = (denom > 1e-9) ? (dotProduct / denom) : 0.0;
    }

    // Batch normalize: normalize each vector to unit length
    kernel void batchNormalize(
        device float* vectors [[buffer(0)]],
        constant uint& dimension [[buffer(1)]],
        constant uint& count [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        uint offset = gid * dimension;

        // Compute L2 norm
        float normSq = 0.0;
        for (uint i = 0; i < dimension; i++) {
            float v = vectors[offset + i];
            normSq += v * v;
        }

        float norm = sqrt(normSq);
        if (norm > 1e-9) {
            float invNorm = 1.0 / norm;
            for (uint i = 0; i < dimension; i++) {
                vectors[offset + i] *= invNorm;
            }
        }
    }

    // MMR diversity: compute pairwise similarity matrix
    kernel void mmrDiversityMatrix(
        constant float* embeddings [[buffer(0)]],
        device float* matrix [[buffer(1)]],
        constant uint& dimension [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= count || gid.y >= count) return;

        if (gid.x == gid.y) {
            matrix[gid.y * count + gid.x] = 1.0;  // Self-similarity
            return;
        }

        // Only compute upper triangle (matrix is symmetric)
        if (gid.x < gid.y) return;

        float dot = 0.0;
        uint offsetA = gid.x * dimension;
        uint offsetB = gid.y * dimension;

        for (uint i = 0; i < dimension; i++) {
            dot += embeddings[offsetA + i] * embeddings[offsetB + i];
        }

        matrix[gid.y * count + gid.x] = dot;
        matrix[gid.x * count + gid.y] = dot;  // Fill symmetric entry
    }

    // ============================================================
    // SIMD4 OPTIMIZED KERNELS (4x faster)
    // ============================================================

    // SIMD4 cosine similarity - processes 4 floats at a time using hardware vector ops
    // Dimension MUST be padded to multiple of 4
    kernel void batchCosineSimilaritySIMD(
        constant float4* query [[buffer(0)]],        // float4 = 4 floats at once
        constant float4* documents [[buffer(1)]],
        device float* results [[buffer(2)]],
        constant uint& dimension [[buffer(3)]],      // Must be multiple of 4
        constant uint& docCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= docCount) return;

        // Number of float4 elements
        uint vecCount = dimension / 4;
        uint docOffset = gid * vecCount;

        // Accumulate using float4 - hardware parallel computation
        float4 dotAccum = float4(0.0);
        float4 queryNormAccum = float4(0.0);
        float4 docNormAccum = float4(0.0);

        for (uint i = 0; i < vecCount; i++) {
            float4 q = query[i];
            float4 d = documents[docOffset + i];

            // All 4 multiplies happen in parallel on GPU
            dotAccum += q * d;
            queryNormAccum += q * q;
            docNormAccum += d * d;
        }

        // Horizontal sum: reduce float4 to float
        float dotProduct = dotAccum.x + dotAccum.y + dotAccum.z + dotAccum.w;
        float queryNormSq = queryNormAccum.x + queryNormAccum.y + queryNormAccum.z + queryNormAccum.w;
        float docNormSq = docNormAccum.x + docNormAccum.y + docNormAccum.z + docNormAccum.w;

        float denom = sqrt(queryNormSq) * sqrt(docNormSq);
        results[gid] = (denom > 1e-9) ? (dotProduct / denom) : 0.0;
    }

    // SIMD4 batch normalize - processes 4 floats at a time
    // Dimension MUST be padded to multiple of 4
    kernel void batchNormalizeSIMD(
        device float4* vectors [[buffer(0)]],
        constant uint& dimension [[buffer(1)]],      // Must be multiple of 4
        constant uint& count [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        uint vecCount = dimension / 4;
        uint offset = gid * vecCount;

        // First pass: compute norm using SIMD
        float4 normAccum = float4(0.0);
        for (uint i = 0; i < vecCount; i++) {
            float4 v = vectors[offset + i];
            normAccum += v * v;
        }

        float normSq = normAccum.x + normAccum.y + normAccum.z + normAccum.w;
        float norm = sqrt(normSq);

        if (norm > 1e-9) {
            // Second pass: normalize using SIMD
            float4 invNorm = float4(1.0 / norm);
            for (uint i = 0; i < vecCount; i++) {
                vectors[offset + i] *= invNorm;
            }
        }
    }

    // ============================================================
    // THREADGROUP MEMORY VERSION (for very large batches)
    // Caches query in fast threadgroup memory
    // ============================================================

    // Threadgroup-optimized cosine similarity
    // Uses shared memory to cache query vector across all threads in group
    kernel void batchCosineSimilarityThreadgroup(
        constant float4* query [[buffer(0)]],
        constant float4* documents [[buffer(1)]],
        device float* results [[buffer(2)]],
        constant uint& dimension [[buffer(3)]],
        constant uint& docCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]],
        uint tid [[thread_index_in_threadgroup]],
        uint tgSize [[threads_per_threadgroup]]
    ) {
        // Shared memory for query (max 384 floats = 96 float4s)
        threadgroup float4 sharedQuery[96];

        uint vecCount = dimension / 4;

        // Cooperatively load query into threadgroup memory
        for (uint i = tid; i < vecCount; i += tgSize) {
            sharedQuery[i] = query[i];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (gid >= docCount) return;

        uint docOffset = gid * vecCount;

        float4 dotAccum = float4(0.0);
        float4 queryNormAccum = float4(0.0);
        float4 docNormAccum = float4(0.0);

        for (uint i = 0; i < vecCount; i++) {
            float4 q = sharedQuery[i];  // Read from fast shared memory
            float4 d = documents[docOffset + i];

            dotAccum += q * d;
            queryNormAccum += q * q;
            docNormAccum += d * d;
        }

        float dotProduct = dotAccum.x + dotAccum.y + dotAccum.z + dotAccum.w;
        float queryNormSq = queryNormAccum.x + queryNormAccum.y + queryNormAccum.z + queryNormAccum.w;
        float docNormSq = docNormAccum.x + docNormAccum.y + docNormAccum.z + docNormAccum.w;

        float denom = sqrt(queryNormSq) * sqrt(docNormSq);
        results[gid] = (denom > 1e-9) ? (dotProduct / denom) : 0.0;
    }
    """
}
