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
nonisolated(unsafe) private let isAppleSilicon: Bool = {
    #if arch(arm64)
    return true
    #else
    return false
    #endif
}()

/// Check if running on Mac (native or iOS app on Mac)
nonisolated(unsafe) private let isRunningOnMac: Bool = {
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
nonisolated(unsafe) private let metalDevice: MTLDevice? = {
    // On Apple Silicon Macs, we skip GPU sync entirely
    // Shared storage mode doesn't need synchronization
    if isAppleSilicon && isRunningOnMac {
        return nil
    }
    return MTLCreateSystemDefaultDevice()
}()
nonisolated(unsafe) private let metalQueue: MTLCommandQueue? = metalDevice?.makeCommandQueue()

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
nonisolated(unsafe) private let maxConcurrentVisionOps: Int = {
    // Detect device tier at initialization
    // Uses same logic as DeviceCapabilityService but without creating dependency cycle
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }

    // Check if running as iOS app on Mac (iPad compatibility mode)
    // On Mac, Metal command buffer behaves differently - need more conservative limits
    let isRunningOnMac = machine.contains("Mac") || ProcessInfo.processInfo.isiOSAppOnMac

    // Metal Feature Set Tables (Oct 2025):
    // Apple9 (A18/M3): 1024 threads/group, 32KB threadgroup mem, 256KB imageblock
    // Apple10 (A19/M4/M5): Same limits + 8x MSAA, 32K textures, sampler LOD bias
    //
    // Vision uses Neural Engine (16-core) + GPU. Higher-tier devices sustain more parallelism.
    // The semaphore controls actual Vision ops; pipeline pre-rendering can exceed this.
    //
    // ADAPTIVE OCR: PageComplexityAnalyzer now pre-screens pages, so we only run Vision OCR
    // on pages that truly need it. This means fewer total Vision calls, so we can be
    // slightly more aggressive with concurrency without risking crashes.
    //
    // IMPORTANT: Mac has different Metal command buffer scheduling than iPhone.
    // MTLDebugBlitCommandEncoder crashes happen when command buffers pile up.
    // Mac needs LOWER concurrency despite more powerful hardware!

    if isRunningOnMac {
        // Mac (M-series): Conservative for macOS Metal stability
        return 3   // Increased from 2 - fewer pages need OCR now
    } else if machine.contains("iPhone18") || machine.contains("iPad16") {
        return 5   // A19 Pro - more aggressive with adaptive filtering
    } else if machine.contains("iPhone17") || machine.contains("iPad15") {
        return 4   // A18 Pro - increased with adaptive filtering
    } else if machine.contains("iPhone16") || machine.contains("iPad14") {
        return 3   // A17 Pro - safe
    } else if machine.contains("iPad13") {
        return 3   // M-series iPad - safe
    } else {
        return 2   // Older devices - safe (was 1, now 2 with fewer OCR pages)
    }
}()

/// Cooldown time between Vision operations (seconds)
/// Brief delay to let GPU command buffers settle
/// High-tier devices use shorter cooldown
nonisolated(unsafe) private let gpuCooldownSeconds: TimeInterval = {
    // Match the tier detection from above
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }

    // Check if running as iOS app on Mac
    let isRunningOnMac = machine.contains("Mac") || ProcessInfo.processInfo.isiOSAppOnMac

    // Metal GPU command buffer synchronization needs minimal cooldown on high-tier devices.
    // Apple9+ has improved command buffer scheduling and 64-bit atomics for synchronization.
    //
    // ADAPTIVE OCR: PageComplexityAnalyzer now filters pages BEFORE they reach Vision.
    // With fewer concurrent Vision calls (only complex pages), we can use shorter cooldowns.
    // The reduction in total Vision calls (often 50-80% skip rate) is the main speedup.
    //
    // IMPORTANT: Mac requires slightly longer cooldown due to different Metal lifecycle.

    if isRunningOnMac {
        // Mac: Moderate cooldown for stability
        return 0.008  // 8ms - reduced with adaptive filtering
    } else if machine.contains("iPhone18") || machine.contains("iPad16") {
        return 0.004  // 4ms - A19/M4: fast with adaptive filtering
    } else if machine.contains("iPhone17") || machine.contains("iPad15") {
        return 0.005  // 5ms - A18/M3: fast with adaptive filtering
    } else if machine.contains("iPhone16") || machine.contains("iPad14") {
        return 0.006  // 6ms - A17/M2: moderate
    } else if machine.contains("iPad13") {
        return 0.005  // 5ms - M-series iPad
    } else {
        return 0.010  // 10ms - older devices: safe
    }
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
nonisolated(unsafe) private let asyncVisionSemaphore = AsyncVisionSemaphore(maxConcurrent: maxConcurrentVisionOps)

/// Legacy semaphore for truly synchronous operations only
/// NOTE: This will cause priority inversion warnings - unavoidable for sync code
nonisolated(unsafe) private let syncVisionSemaphore = DispatchSemaphore(value: maxConcurrentVisionOps)

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
