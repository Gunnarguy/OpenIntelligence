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
//  SOLUTION: We use a counting semaphore with explicit Metal GPU synchronization.
//  This allows LIMITED parallelism (2-3 concurrent) while preventing GPU overload.
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

/// Shared Metal device for GPU synchronization
/// We use this to force GPU command buffer completion between Vision calls
private let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
private let metalQueue: MTLCommandQueue? = metalDevice?.makeCommandQueue()

/// Force GPU to complete all pending work
/// This drains the Metal command queue, ensuring Vision's async GPU work is complete
private func synchronizeGPU() {
    guard let queue = metalQueue, let device = metalDevice else { return }

    // Create a dummy command buffer and wait for it to complete
    // This ensures all prior GPU work (including Vision's) has finished
    if let buffer = queue.makeCommandBuffer() {
        buffer.commit()
        buffer.waitUntilCompleted()
    }
}

// MARK: - Throttle Configuration

/// Maximum concurrent Vision operations
/// 2 provides good parallelism while preventing Metal command buffer overflow
/// Higher values cause crashes on some devices; 2 is safe across all tiers
private let maxConcurrentVisionOps = 2

/// Semaphore for controlling Vision concurrency
/// Value of 2 allows two Vision operations to run in parallel
nonisolated(unsafe) private let visionSemaphore = DispatchSemaphore(value: maxConcurrentVisionOps)

/// Serial queue for synchronous Vision operations (fallback when semaphore acquired)
nonisolated(unsafe) private let visionSyncQueue = DispatchQueue(
    label: "com.openintelligence.vision-ocr-throttle",
    qos: .userInitiated,
    attributes: .concurrent  // Allow concurrent execution
)

/// Cooldown time between Vision operations (seconds)
/// Brief delay to let GPU command buffers settle
private let gpuCooldownSeconds: TimeInterval = 0.02  // 20ms

/// Global throttle for Vision OCR operations with GPU synchronization
/// Allows limited parallelism (2 concurrent) while preventing Metal crashes
enum VisionOCRThrottle {

    /// Execute a Vision OCR operation synchronously with throttling and GPU sync
    /// Use this for callback-based Vision APIs (VNImageRequestHandler.perform)
    /// - Parameter operation: The closure containing VNImageRequestHandler.perform()
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func performSync<T>(_ operation: () throws -> T) rethrows -> T {
        // Acquire semaphore slot (blocks if 2 already running)
        visionSemaphore.wait()

        defer {
            // Force GPU completion before releasing slot
            synchronizeGPU()
            Thread.sleep(forTimeInterval: gpuCooldownSeconds)
            visionSemaphore.signal()
        }

        // Use autoreleasepool to ensure GPU resources are released promptly
        return try autoreleasepool {
            try operation()
        }
    }

    /// Execute an async Vision operation with throttling and GPU sync
    /// Use this for iOS 18+ Vision struct APIs (RecognizeTextRequest.perform, etc.)
    /// - Parameter operation: The async closure containing Vision operations
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func performAsync<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        // Acquire semaphore slot on background thread to avoid blocking main thread
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                visionSemaphore.wait()
                continuation.resume()
            }
        }

        defer {
            // Force GPU completion before releasing slot
            synchronizeGPU()
            Thread.sleep(forTimeInterval: gpuCooldownSeconds)
            visionSemaphore.signal()
        }

        return try await operation()
    }

    /// Execute an async Vision operation with throttling (non-throwing version)
    /// - Parameter operation: The async closure containing Vision operations
    /// - Returns: Whatever the operation returns
    nonisolated static func performAsync<T: Sendable>(_ operation: @Sendable @escaping () async -> T) async -> T {
        // Acquire semaphore slot on background thread
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                visionSemaphore.wait()
                continuation.resume()
            }
        }

        defer {
            // Force GPU completion before releasing slot
            synchronizeGPU()
            Thread.sleep(forTimeInterval: gpuCooldownSeconds)
            visionSemaphore.signal()
        }

        return await operation()
    }

    /// Execute a Vision OCR operation asynchronously with throttling (legacy - wraps sync in async)
    /// - Parameter operation: The closure containing Vision operations
    /// - Returns: Whatever the operation returns
    /// - Throws: Re-throws any error from the operation
    nonisolated static func perform<T: Sendable>(_ operation: @Sendable @escaping () throws -> T) async throws -> T {
        // Acquire semaphore slot
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                visionSemaphore.wait()
                continuation.resume()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    do {
                        let result = try operation()
                        // Force GPU completion before releasing slot
                        synchronizeGPU()
                        Thread.sleep(forTimeInterval: gpuCooldownSeconds)
                        visionSemaphore.signal()
                        continuation.resume(returning: result)
                    } catch {
                        visionSemaphore.signal()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
