//
//  EvidenceThreadStore.swift
//  OpenIntelligence
//

import Foundation
import os.log

/// The store for Evidence Threads, the app's saved conversations: one JSON file per thread in
/// `<base>/EvidenceThreads/<containerId>/`, where `<base>` is `OpenIntelligenceRuntimePaths.baseDirectory()`,
/// `<Application Support>/OpenIntelligence` in the app. That is the folder iCloud sync reads and writes for
/// a library set to iCloud Drive (`WorkspaceSyncService.synchronizeEvidenceThreads`), as it does for the
/// chat history and the conversation memory beside it.
///
/// Through the first 5.7 builds threads were saved one level up, in `<Application Support>/EvidenceThreads/`,
/// a folder sync never read, so a conversation stayed on the device it was had on. Threads found there, or in
/// the older `<Application Support>/LocalCache/EvidenceThreads/`, are moved here when a store is made, with
/// their modification dates, which sync compares; when a thread is in both places the newer copy is kept.
///
/// A deleted conversation is recorded in `deleted_threads.json` beside the threads folder, and sync removes
/// it on every device instead of copying it back from iCloud (`WorkspaceSyncService.synchronizeEvidenceThreads`).
final class EvidenceThreadStore: Sendable {
    /// The list of deleted conversations' ids, beside the threads folder, as `deleted_documents.json` is
    /// for documents.
    nonisolated static let deletedThreadsFileName = "deleted_threads.json"

    private let logger = Logger(subsystem: "com.openintelligence", category: "EvidenceThreadStore")
    private let root: URL

    /// - Parameters:
    ///   - root: the folder that holds one folder per library.
    ///   - legacyRoots: folders threads were saved in before; their threads are moved into `root`.
    init(root: URL = EvidenceThreadStore.defaultRoot(), legacyRoots: [URL]? = nil) {
        self.root = root
        moveThreads(from: legacyRoots ?? Self.legacyRoots(for: root))
    }

    /// `<base>/EvidenceThreads`, the folder iCloud sync reads.
    static func defaultRoot() -> URL {
        OpenIntelligenceRuntimePaths.baseDirectory().appendingPathComponent("EvidenceThreads", isDirectory: true)
    }

    /// Where threads were saved before 5.7, only for a store at the app's own location: a store a benchmark
    /// or a test points somewhere else never takes the person's threads.
    static func legacyRoots(for root: URL) -> [URL] {
        let appRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        guard root.standardizedFileURL == appRoot.appendingPathComponent("EvidenceThreads", isDirectory: true).standardizedFileURL
        else { return [] }
        let applicationSupport = appRoot.deletingLastPathComponent()
        return [
            applicationSupport.appendingPathComponent("LocalCache/EvidenceThreads", isDirectory: true),
            applicationSupport.appendingPathComponent("EvidenceThreads", isDirectory: true),
        ]
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func moveThreads(from legacyRoots: [URL]) {
        let fileManager = FileManager.default
        var moved = 0
        for legacyRoot in legacyRoots
        where legacyRoot.standardizedFileURL != root.standardizedFileURL && fileManager.fileExists(atPath: legacyRoot.path) {
            do {
                let libraries = try fileManager.contentsOfDirectory(
                    at: legacyRoot, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                for library in libraries where (try? library.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let target = root.appendingPathComponent(library.lastPathComponent, isDirectory: true)
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    let files = try fileManager.contentsOfDirectory(
                        at: library, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                    for file in files where file.pathExtension == "json" {
                        let destination = target.appendingPathComponent(file.lastPathComponent)
                        if !fileManager.fileExists(atPath: destination.path) {
                            try fileManager.moveItem(at: file, to: destination)
                        } else if Self.modified(file) > Self.modified(destination) {
                            _ = try fileManager.replaceItemAt(destination, withItemAt: file)
                        } else {
                            try fileManager.removeItem(at: file)
                        }
                        moved += 1
                    }
                    if (try? fileManager.contentsOfDirectory(atPath: library.path))?.isEmpty == true {
                        try? fileManager.removeItem(at: library)
                    }
                }
                if (try? fileManager.contentsOfDirectory(atPath: legacyRoot.path))?.isEmpty == true {
                    try? fileManager.removeItem(at: legacyRoot)
                }
            } catch {
                logger.error("Could not move threads from \(legacyRoot.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if moved > 0 {
            logger.info("Moved \(moved) thread file(s) to the folder iCloud sync reads.")
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
        }
    }

    /// Returns the URL for a specific container's directory: `.../EvidenceThreads/<containerId>/`
    private func getContainerDirectoryURL(for containerId: UUID) -> URL {
        root.appendingPathComponent(containerId.uuidString, isDirectory: true)
    }

    /// Returns the URL for a specific thread's JSON file.
    private func getThreadFileURL(id: UUID, containerId: UUID) -> URL {
        getContainerDirectoryURL(for: containerId).appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    /// Ensures the directory for the given container exists.
    private func ensureDirectoryExists(for containerId: UUID) throws {
        let containerURL = getContainerDirectoryURL(for: containerId)
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Saves the thread to disk as JSON.
    func saveThread(_ thread: EvidenceThread) throws {
        try ensureDirectoryExists(for: thread.containerId)
        let fileURL = getThreadFileURL(id: thread.id, containerId: thread.containerId)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(thread)
        try WorkspaceSyncService.coordinatedWriteData(data, to: fileURL)
        logger.debug("Successfully saved EvidenceThread \(thread.id) to local store.")
    }

    /// Retrieves a thread by ID and container ID.
    func getThread(id: UUID, containerId: UUID) throws -> EvidenceThread {
        let fileURL = getThreadFileURL(id: id, containerId: containerId)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Error.threadNotFound
        }
        
        let data = try WorkspaceSyncService.coordinatedReadData(from: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(EvidenceThread.self, from: data)
    }

    /// Lists all threads within a specific container.
    func listThreads(containerId: UUID) throws -> [EvidenceThread] {
        let containerURL = getContainerDirectoryURL(for: containerId)
        
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            return [] // Container directory doesn't exist yet, so no threads.
        }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        var threads: [EvidenceThread] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // A deleted conversation stays hidden even while a copy of it is still on its way out.
        let deleted = deletedThreadIDs()
        for url in fileURLs where url.pathExtension == "json" && !deleted.contains(url.deletingPathExtension().lastPathComponent) {
            do {
                let data = try WorkspaceSyncService.coordinatedReadData(from: url)
                let thread = try decoder.decode(EvidenceThread.self, from: data)
                threads.append(thread)
            } catch {
                logger.error("Failed to decode EvidenceThread at \(url.path): \(error.localizedDescription)")
            }
        }
        
        return threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Deletes a thread by ID and container ID, and records the deletion for iCloud sync, even when the
    /// file was already gone, so a copy in iCloud is removed too.
    func deleteThread(id: UUID, containerId: UUID) throws {
        let fileURL = getThreadFileURL(id: id, containerId: containerId)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try WorkspaceSyncService.coordinatedRemoveItem(at: fileURL)
            logger.debug("Successfully deleted EvidenceThread \(id).")
        }
        recordDeletion(of: id)
    }

    private var deletedThreadsURL: URL {
        root.deletingLastPathComponent().appendingPathComponent(Self.deletedThreadsFileName)
    }

    /// The ids of deleted conversations: this device's, and after a sync the other devices' too.
    func deletedThreadIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: deletedThreadsURL),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private func recordDeletion(of id: UUID) {
        var ids = deletedThreadIDs()
        guard ids.insert(id.uuidString).inserted, let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        do {
            try WorkspaceSyncService.coordinatedWriteData(data, to: deletedThreadsURL)
        } catch {
            logger.error("Could not record the deleted thread \(id): \(error.localizedDescription)")
        }
    }

    public enum Error: Swift.Error {
        case directoryNotFound
        case threadNotFound
    }
}
