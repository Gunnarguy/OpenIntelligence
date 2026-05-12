//
//  VisionOCRThrottle.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  GPU-Synchronized Vision OCR Throttle
//
//  VNRecognizeTextRequestRevision3 uses Metal/ANE for GPU-accelerated text recognition.
//  When multiple requests run in parallel, they can cause race conditions in Metal's
//  command buffer synchronization, leading to crashes like:
//      MTLDebugBlitCommandEncoder synchronizeResource:
//
//  SOLUTION: Actor-based async semaphore that leverages Swift Concurrency's
//  priority propagation to avoid priority inversion warnings.
//
//  Usage (synchronous - for legacy VN* APIs):
//      VisionOCRThrottle.performSync {
//          try handler.perform([textRequest])
//      }
//
//  Usage (async - for iOS 18+ Vision struct APIs):
//      try await VisionOCRThrottle.performAsync {
//          try await request.perform(on: image)
//      }
//

import Foundation
import Metal

// MARK: - Metal GPU Synchronization

/// Check if we're running on Apple Silicon (unified memory architecture)
/// On Apple Silicon, Metal uses MTLResourceStorageModeShared by default.
/// Calling synchronizeResource on shared storage is INVALID and crashes.
nonisolated private let isAppleSilicon: Bool = {
    #if arch(arm64)
    return true
    #else
    return false
    #endif
}()

/// Check if running on Mac (native or iOS app on Mac)
nonisolated private let isRunningOnMac: Bool = {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }
    return machine.contains("Mac") || ProcessInfo.processInfo.isiOSAppOnMac
}()

/// Shared Metal device for GPU synchronization
/// We use this to force GPU command buffer completion between Vision calls
/// Only used on iOS devices - disabled on Apple Silicon Macs due to shared memory architecture
nonisolated private let metalDevice: MTLDevice? = {
    // On Apple Silicon Macs, we skip GPU sync entirely
    // Shared storage mode doesn't need synchronization
    if isAppleSilicon && isRunningOnMac {
        return nil
    }
    return MTLCreateSystemDefaultDevice()
}()
nonisolated private let metalQueue: MTLCommandQueue? = metalDevice?.makeCommandQueue()

/// Force GPU to complete all pending work
/// This drains the Metal command queue, ensuring Vision's async GPU work is complete
/// Must be nonisolated to be callable from any context
///
/// IMPORTANT: This is a NO-OP on Apple Silicon Macs!
/// Apple Silicon uses unified memory with MTLResourceStorageModeShared.
/// Calling synchronizeResource on shared storage causes assertion failures:
///   "synchronizeResource: only applies when resourceOptions & MTLResourceStorageModeMask == MTLResourceStorageModeManaged"
/// iOS devices use different storage modes and need this synchronization.
nonisolated private func synchronizeGPU() {
    // Skip entirely on Apple Silicon Macs - shared memory doesn't need sync
    if isAppleSilicon && isRunningOnMac {
        return
    }

    guard let queue = metalQueue else { return }

    // Create a dummy command buffer and wait for it to complete
    // This ensures all prior GPU work (including Vision's) has finished
    // Only valid on iOS or Intel Macs with managed storage mode
    if let buffer = queue.makeCommandBuffer() {
        buffer.commit()
        buffer.waitUntilCompleted()
    }
}

// MARK: - Throttle Configuration

/// Device-tier-aware maximum concurrent Vision operations
/// Higher-tier devices (A18 Pro, M-series) can sustain more parallel Vision ops
/// Lower-tier devices are limited to 2 to prevent Metal command buffer overflow
nonisolated private let maxConcurrentVisionOps: Int = {
    DeviceCapabilityService.shared.visionOperationConcurrency
}()

/// Cooldown time between Vision operations (seconds)
/// Brief delay to let GPU command buffers settle
/// High-tier devices use shorter cooldown
nonisolated private let gpuCooldownSeconds: TimeInterval = {
    DeviceCapabilityService.shared.visionOperationCooldownSeconds
}()

// MARK: - Actor-Based Async Semaphore (Apple-approved approach)

/// Actor-based async semaphore that uses Swift Concurrency's cooperative threading.
/// This avoids priority inversion because Swift's runtime handles priority propagation
/// automatically for actor-isolated async code.
///
/// Unlike DispatchSemaphore, this doesn't block threads - it suspends tasks cooperatively.
private actor AsyncVisionSemaphore {
    private var availableSlots: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.availableSlots = maxConcurrent
    }

    /// Acquire a slot, suspending if none available
    /// Swift's runtime propagates the caller's priority to the actor
    func acquire() async {
        if availableSlots > 0 {
            availableSlots -= 1
            return
        }

        // No slot available - suspend until one opens up
        // Swift Concurrency handles priority propagation automatically
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Release a slot, waking the next waiter if any
    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availableSlots += 1
        }
    }

    /// Current state for debugging
    var debugState: (available: Int, waiting: Int) {
        (availableSlots, waiters.count)
    }
}

/// Global async semaphore for Vision operations
/// Uses actor isolation for proper Swift Concurrency integration
nonisolated private let asyncVisionSemaphore = AsyncVisionSemaphore(maxConcurrent: maxConcurrentVisionOps)

/// Legacy semaphore for truly synchronous operations only
/// NOTE: This will cause priority inversion warnings - unavoidable for sync code
nonisolated private let syncVisionSemaphore = DispatchSemaphore(value: maxConcurrentVisionOps)

// MARK: - VisionOCRThrottle

/// Global throttle for Vision OCR operations with GPU synchronization
/// Allows limited parallelism while preventing Metal crashes
enum VisionOCRThrottle {

    /// Execute a Vision OCR operation synchronously with throttling and GPU sync
    /// Use this for callback-based Vision APIs (VNImageRequestHandler.perform)
    /// NOTE: This uses DispatchSemaphore which may cause priority inversion warnings.
    /// For new code, prefer performAsync or perform (async) methods.
    /// - Parameter operation: The closure containing VNImageRequestHandler.perform()
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func performSync<T>(_ operation: () throws -> T) rethrows -> T {
        // Acquire sync semaphore slot - this is inherently blocking
        // Priority inversion is unavoidable for truly synchronous operations
        syncVisionSemaphore.wait()

        // Capture cooldown value locally to avoid actor isolation issues
        let cooldown = gpuCooldownSeconds

        defer {
            // Force GPU completion before releasing slot
            synchronizeGPU()
            Thread.sleep(forTimeInterval: cooldown)
            syncVisionSemaphore.signal()
        }

        // Use autoreleasepool to ensure GPU resources are released promptly
        return try autoreleasepool {
            try operation()
        }
    }

    /// Execute an async Vision operation with throttling and GPU sync
    /// Use this for iOS 18+ Vision struct APIs (RecognizeTextRequest.perform, etc.)
    /// Uses actor-based AsyncSemaphore - Swift Concurrency handles priority automatically.
    /// - Parameter operation: The async closure containing Vision operations
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func performAsync<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        // Acquire slot via actor - Swift Concurrency propagates priority automatically
        await asyncVisionSemaphore.acquire()

        // Capture cooldown value locally
        let cooldown = gpuCooldownSeconds

        do {
            let result = try await operation()
            // Force GPU completion before releasing slot
            synchronizeGPU()
            try? await Task.sleep(for: .seconds(cooldown))
            await asyncVisionSemaphore.release()
            return result
        } catch {
            synchronizeGPU()
            try? await Task.sleep(for: .seconds(cooldown))
            await asyncVisionSemaphore.release()
            throw error
        }
    }

    /// Execute an async Vision operation with throttling (non-throwing version)
    /// Uses actor-based AsyncSemaphore - Swift Concurrency handles priority automatically.
    /// - Parameter operation: The async closure containing Vision operations
    /// - Returns: Whatever the operation returns
    nonisolated static func performAsync<T: Sendable>(_ operation: @Sendable @escaping () async -> T) async -> T {
        // Acquire slot via actor - Swift Concurrency propagates priority automatically
        await asyncVisionSemaphore.acquire()

        // Capture cooldown value locally
        let cooldown = gpuCooldownSeconds

        let result = await operation()
        // Force GPU completion before releasing slot
        synchronizeGPU()
        try? await Task.sleep(for: .seconds(cooldown))
        await asyncVisionSemaphore.release()
        return result
    }

    /// Execute a Vision OCR operation asynchronously with throttling (legacy - wraps sync in async)
    /// Uses actor-based AsyncSemaphore - Swift Concurrency handles priority automatically.
    /// - Parameter operation: The closure containing Vision operations
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func perform<T: Sendable>(_ operation: @Sendable @escaping () throws -> T) async throws -> T {
        // Acquire slot via actor - Swift Concurrency propagates priority automatically
        await asyncVisionSemaphore.acquire()

        // Capture cooldown value locally
        let cooldown = gpuCooldownSeconds

        do {
            // Execute in autoreleasepool for proper Vision object cleanup
            let result: T = try autoreleasepool {
                try operation()
            }
            // Force GPU completion before releasing slot
            synchronizeGPU()
            try? await Task.sleep(for: .seconds(cooldown))
            await asyncVisionSemaphore.release()
            return result
        } catch {
            synchronizeGPU()
            try? await Task.sleep(for: .seconds(cooldown))
            await asyncVisionSemaphore.release()
            throw error
        }
    }
}
