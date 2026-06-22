//
//  TranscriptPersistenceService.swift
//  OpenIntelligence
//
//  Persists Apple Foundation Models session transcripts to disk.
//  Enables rehydrating conversations across app launches without losing context.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Transcript Persistence Service

/// Service for persisting and restoring Apple FoundationModels session transcripts.
///
/// The `Transcript` type from FoundationModels is `Codable`, enabling JSON serialization.
/// This allows the app to:
/// 1. Save the session state when the app backgrounds or user switches containers
/// 2. Restore the session state when returning to a container, preserving full conversation context
/// 3. Enable "resume conversation" UX without re-prompting the model
///
/// The transcript includes:
/// - Instructions (system prompt)
/// - Prompts (user messages)
/// - Responses (assistant messages)
/// - Tool calls and their results (for agentic RAG)
@available(iOS 26.0, *)
@MainActor
final class TranscriptPersistenceService {
    // MARK: - Singleton

    static let shared = TranscriptPersistenceService()
    private init() {}

    // MARK: - File Paths

    /// URL for storing transcript data for a specific container
    private func transcriptURL(containerId: UUID) -> URL {
        AppSupportPaths.baseDir().appendingPathComponent("transcript_\(containerId.uuidString).json")
    }

    // MARK: - Persistence Operations

    /// Save a transcript to disk for a specific container.
    ///
    /// - Parameters:
    ///   - transcript: The FoundationModels Transcript to persist
    ///   - containerId: The container ID to associate with this transcript
    /// - Returns: `true` if save succeeded, `false` otherwise
    @discardableResult
    func saveTranscript(_ transcript: Transcript, for containerId: UUID) -> Bool {
        let url = transcriptURL(containerId: containerId)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            
            let entryCount = transcript.count
            Task.detached {
                do {
                    try WorkspaceSyncService.coordinatedWriteData(data, to: url)
                    Log.debug("[TranscriptPersistence] Saved transcript with \(entryCount) entries for container \(containerId)", category: .initialization)
                } catch {
                    Log.error("[TranscriptPersistence] Failed to save transcript for container \(containerId): \(error.localizedDescription)", category: .initialization)
                }
            }
            return true
        } catch {
            Log.error("[TranscriptPersistence] Failed to encode transcript for container \(containerId): \(error.localizedDescription)", category: .initialization)
            return false
        }
    }

    /// Load a previously saved transcript for a container.
    ///
    /// - Parameter containerId: The container ID to load transcript for
    /// - Returns: The restored `Transcript`, or `nil` if not found or corrupted
    func loadTranscript(for containerId: UUID) -> Transcript? {
        let url = transcriptURL(containerId: containerId)

        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.debug("[TranscriptPersistence] No saved transcript found for container \(containerId)", category: .initialization)
            return nil
        }

        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: url)
            let transcript = try JSONDecoder().decode(Transcript.self, from: data)
            Log.info("[TranscriptPersistence] Loaded transcript with \(transcript.count) entries for container \(containerId)", category: .initialization)
            return transcript
        } catch {
            Log.error("[TranscriptPersistence] Failed to load transcript for container \(containerId): \(error.localizedDescription)", category: .initialization)
            // Delete corrupted file
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Delete the saved transcript for a container.
    ///
    /// Call this when:
    /// - User clears chat history
    /// - Container is deleted
    /// - Transcript becomes invalid (e.g., after significant app update)
    ///
    /// - Parameter containerId: The container ID to clear transcript for
    func deleteTranscript(for containerId: UUID) {
        let url = transcriptURL(containerId: containerId)

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        Task.detached {
            do {
                try WorkspaceSyncService.coordinatedRemoveItem(at: url)
                Log.debug("[TranscriptPersistence] Deleted transcript for container \(containerId)", category: .initialization)
            } catch {
                Log.error("[TranscriptPersistence] Failed to delete transcript for container \(containerId): \(error.localizedDescription)", category: .initialization)
            }
        }
    }

    /// Check if a saved transcript exists for a container.
    ///
    /// - Parameter containerId: The container ID to check
    /// - Returns: `true` if a transcript file exists
    func hasTranscript(for containerId: UUID) -> Bool {
        let url = transcriptURL(containerId: containerId)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Transcript Trimming

    /// Maximum entries to persist to prevent unbounded file growth.
    /// Each entry averages ~500 bytes. 100 entries ≈ 50KB per container.
    private static let maxEntriesToPersist = 100

    /// Save a transcript with automatic trimming to prevent unbounded growth.
    ///
    /// Keeps the first entry (usually instructions) and the most recent entries.
    ///
    /// - Parameters:
    ///   - transcript: The full transcript
    ///   - containerId: The container ID
    /// - Returns: `true` if save succeeded
    @discardableResult
    func saveTranscriptTrimmed(_ transcript: Transcript, for containerId: UUID) -> Bool {
        guard transcript.count > Self.maxEntriesToPersist else {
            // No trimming needed
            return saveTranscript(transcript, for: containerId)
        }

        // Keep first entry (instructions) + most recent entries
        let allEntries = Array(transcript)
        guard let firstEntry = allEntries.first else {
            return saveTranscript(transcript, for: containerId)
        }

        let recentEntries = Array(allEntries.suffix(Self.maxEntriesToPersist - 1))
        let trimmedEntries = [firstEntry] + recentEntries
        let trimmedTranscript = Transcript(entries: trimmedEntries)

        Log.debug("[TranscriptPersistence] Trimmed transcript from \(transcript.count) to \(trimmedTranscript.count) entries", category: .initialization)

        return saveTranscript(trimmedTranscript, for: containerId)
    }

    // MARK: - Metadata

    /// Get basic stats about a saved transcript without fully loading it.
    ///
    /// - Parameter containerId: The container ID
    /// - Returns: Tuple of (fileSize in bytes, estimatedEntries) or nil if no transcript
    func transcriptMetadata(for containerId: UUID) -> (fileSize: Int, estimatedEntries: Int)? {
        let url = transcriptURL(containerId: containerId)

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int
        else {
            return nil
        }

        // Rough estimate: ~500 bytes per entry on average
        let estimatedEntries = max(1, fileSize / 500)

        return (fileSize, estimatedEntries)
    }
}

// MARK: - Fallback for Pre-iOS 26

/// Stub implementation for devices without FoundationModels
@available(iOS, deprecated: 26.0, message: "Use TranscriptPersistenceService on iOS 26+")
final class TranscriptPersistenceServiceUnavailable {
    static let shared = TranscriptPersistenceServiceUnavailable()
    private init() {}

    func saveTranscript(_: Any, for _: UUID) -> Bool { false }
    func loadTranscript(for _: UUID) -> Any? { nil }
    func deleteTranscript(for _: UUID) {}
    func hasTranscript(for _: UUID) -> Bool { false }
}
