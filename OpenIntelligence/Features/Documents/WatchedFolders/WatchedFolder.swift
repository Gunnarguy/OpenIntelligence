//
//  WatchedFolder.swift
//  OpenIntelligence
//
//  A folder a library keeps up with, and what the app has seen in it (5.8).
//

import Foundation

/// A folder whose new and changed files are imported into a library by themselves.
///
/// Kept on this device, in the local cache: a bookmark to a folder means nothing on another device, and the
/// cache is never copied to iCloud (`WorkspaceSyncService.localOnlyEntryNames`). Losing the file costs nothing:
/// every file reads as new, and the check's hash comparison finds them already in the library.
nonisolated struct WatchedFolder: Codable, Identifiable, Equatable, Sendable {
    /// A file as last seen. Date and size decide whether to look further, so an unchanged folder costs a walk
    /// and no reads. The hash ties the file to its document, which an import doesn't report back.
    struct SeenFile: Codable, Equatable, Sendable {
        var size: Int64
        var modified: Date
        var hash: String
        /// Nil until the import has finished.
        var documentId: UUID?
        /// Whether this file's import made `documentId`. False when the library already held these bytes, from
        /// a person's own import or another file, and then the document is never this file's to remove.
        var ownsDocument = false
        /// The old version, removed only once the new one is in the library.
        var replacesDocumentId: UUID?
        /// The queue's item, so an import stopped by a restart can be continued without asking.
        var queueItemId: UUID?
    }

    let id: UUID
    let libraryId: UUID
    var name: String
    var bookmark: Data
    var lastCheckedAt: Date?
    /// What the person should know from the last check, or nil.
    var note: String?
    /// By path relative to the folder.
    var files: [String: SeenFile] = [:]
}

/// What a check found in a folder.
nonisolated struct WatchedFolderFile: Equatable, Sendable {
    let relativePath: String
    let url: URL
    let size: Int64
    let modified: Date
    /// False for a file in iCloud Drive or another provider that is still only a placeholder.
    var isDownloaded = true
}

/// What to do about a folder's files. Decides nothing about the disk or the queue, so it can be tested alone.
nonisolated enum WatchedFolderChanges {
    struct Result: Equatable, Sendable {
        /// New or changed files to read, up to the room the plan has.
        var toRead: [WatchedFolderFile] = []
        /// New or changed files over the plan's document limit, left for a later check.
        var overLimit = 0
        /// Files not on the device yet: asked for, and read by a later check.
        var waitingForDownload: [WatchedFolderFile] = []
    }

    static func decide(found: [WatchedFolderFile], seen: [String: WatchedFolder.SeenFile], room: Int) -> Result {
        var result = Result()
        var left = max(0, room)
        for file in found {
            if let known = seen[file.relativePath], known.size == file.size, known.modified == file.modified {
                continue
            }
            guard file.isDownloaded else {
                result.waitingForDownload.append(file)
                continue
            }
            guard left > 0 else {
                result.overLimit += 1
                continue
            }
            left -= 1
            result.toRead.append(file)
        }
        return result
    }

    /// What the library shows about a check. Nil when there is nothing to say.
    static func note(overLimit: Int, waitingForDownload: Int, failed: Int = 0, unreadable: Int = 0) -> String? {
        func files(_ count: Int) -> String { "\(count) \(count == 1 ? "file is" : "files are")" }
        var parts: [String] = []
        if overLimit > 0 { parts.append("\(files(overLimit)) over your plan's document limit.") }
        if waitingForDownload > 0 { parts.append("\(files(waitingForDownload)) still downloading.") }
        if unreadable > 0 {
            parts.append("\(unreadable) \(unreadable == 1 ? "file" : "files") can't be read right now.")
        }
        if failed > 0 {
            parts.append("\(failed) \(failed == 1 ? "file" : "files") couldn't be imported, and will be tried again if changed.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The file the watched folders are kept in.
nonisolated enum WatchedFolderStore {
    /// Where the list is kept. Tests point this elsewhere.
    nonisolated(unsafe) static var fileURL: () -> URL = {
        AppSupportPaths.localCacheDir().appendingPathComponent("watched_folders.json")
    }

    static func load() -> [WatchedFolder] {
        guard let data = try? Data(contentsOf: fileURL()),
            let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data)
        else { return [] }
        return folders
    }

    static func save(_ folders: [WatchedFolder]) {
        do {
            try JSONEncoder().encode(folders).write(to: fileURL(), options: .atomic)
        } catch {
            Log.error(
                "[WatchedFolders] The list could not be saved: \(error.localizedDescription)", category: .ingestion)
        }
    }
}
