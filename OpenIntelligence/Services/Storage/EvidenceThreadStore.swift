//
//  EvidenceThreadStore.swift
//  OpenIntelligence
//

import Foundation
import os.log

/// A local-only store for Evidence Threads.
/// Stores threads as isolated JSON files in `Application Support/LocalCache/EvidenceThreads/<containerId>/`.
/// Explicitly isolated from WorkspaceSyncService and ChatMessage.
public final class EvidenceThreadStore: Sendable {
    private let logger = Logger(subsystem: "com.openintelligence", category: "EvidenceThreadStore")

    public init() {}

    /// Returns the root URL for all Evidence Threads: `Application Support/LocalCache/EvidenceThreads/`
    private func getRootDirectoryURL() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Error.directoryNotFound
        }
        return appSupportURL.appendingPathComponent("LocalCache/EvidenceThreads", isDirectory: true)
    }

    /// Returns the URL for a specific container's directory: `.../EvidenceThreads/<containerId>/`
    private func getContainerDirectoryURL(for containerId: UUID) throws -> URL {
        let rootURL = try getRootDirectoryURL()
        return rootURL.appendingPathComponent(containerId.uuidString, isDirectory: true)
    }

    /// Returns the URL for a specific thread's JSON file.
    private func getThreadFileURL(id: UUID, containerId: UUID) throws -> URL {
        let containerURL = try getContainerDirectoryURL(for: containerId)
        return containerURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    /// Ensures the directory for the given container exists.
    private func ensureDirectoryExists(for containerId: UUID) throws {
        let containerURL = try getContainerDirectoryURL(for: containerId)
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Saves the thread to disk as JSON.
    public func saveThread(_ thread: EvidenceThread) throws {
        try ensureDirectoryExists(for: thread.containerId)
        let fileURL = try getThreadFileURL(id: thread.id, containerId: thread.containerId)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(thread)
        try data.write(to: fileURL, options: .atomic)
        logger.debug("Successfully saved EvidenceThread \(thread.id) to local store.")
    }

    /// Retrieves a thread by ID and container ID.
    public func getThread(id: UUID, containerId: UUID) throws -> EvidenceThread {
        let fileURL = try getThreadFileURL(id: id, containerId: containerId)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Error.threadNotFound
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(EvidenceThread.self, from: data)
    }

    /// Lists all threads within a specific container.
    public func listThreads(containerId: UUID) throws -> [EvidenceThread] {
        let containerURL = try getContainerDirectoryURL(for: containerId)
        
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            return [] // Container directory doesn't exist yet, so no threads.
        }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        var threads: [EvidenceThread] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for url in fileURLs where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let thread = try decoder.decode(EvidenceThread.self, from: data)
                threads.append(thread)
            } catch {
                logger.error("Failed to decode EvidenceThread at \(url.path): \(error.localizedDescription)")
                // Continue loading other valid threads
            }
        }
        
        // Sort by updated descending
        return threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Deletes a thread by ID and container ID.
    public func deleteThread(id: UUID, containerId: UUID) throws {
        let fileURL = try getThreadFileURL(id: id, containerId: containerId)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            logger.debug("Successfully deleted EvidenceThread \(id).")
        }
    }

    public enum Error: Swift.Error {
        case directoryNotFound
        case threadNotFound
    }
}
