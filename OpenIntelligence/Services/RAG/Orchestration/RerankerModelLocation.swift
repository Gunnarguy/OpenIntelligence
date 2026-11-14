//
//  RerankerModelLocation.swift
//  OpenIntelligence
//
//  Where the reranker is loaded from, so Core ML's compiled Neural Engine form is found again (5.8).
//

import CryptoKit
import Foundation

/// Where the reranker is loaded from (5.8).
///
/// Core ML keeps the Neural Engine form it compiles for a model under a key that includes the model's location. On an
/// M3 Pro (2026-11-12) the bundled `ReRankerModel.mlmodelc` loaded in 17 to 20 s in the first process and in 0.2 s in
/// every later one; the same files copied to another folder compiled again (21 s), and touching them did not. On the
/// owner's iPhone the load compiled again on most launches (journal `reranker.load`, about 30 loads of 20 to 130 s from
/// 2026-11-09 to 12, most with no install between) and left 202 compiled copies, 1.47 GB, in the app's
/// `Library/Caches`. Loading a copy kept at one path in Application Support, named by the model's own fingerprint,
/// keeps that location the same across launches, and across installs and updates that ship the same model. A new
/// model gets a new name, and the copy of the old one is removed. If the copy cannot be made, the bundled model loads,
/// as before.
nonisolated enum RerankerModelLocation {
    static let folderName = "Models"
    static let appGroup = "group.Gunndamental.OpenIntelligence"
    private static let completeSuffix = ".complete"
    private static let stagingPrefix = ".staging-"
    /// Files up to this size are hashed whole; larger ones (the weights) by name and size, which change with them.
    private static let hashWholeUnderBytes = 1_048_576

    /// The model to load: the fixed-path copy of a compiled `.mlmodelc`, or `bundled` itself when it is anything else,
    /// Application Support cannot be found, or the copy cannot be made.
    static func loadURL(for bundled: URL, fileManager: FileManager = .default) -> (url: URL, fixedPath: Bool) {
        // The app group's folder first (2026-11-13): the app's own data folder gets a new address at each install (five
        // in one day's trace on the owner's iPhone), so a copy in Application Support was at a new path after every
        // install and Core ML compiled again, 36 to 90 s each time, with nothing clearing its cache. Whether the group
        // folder's address survives an install is being measured on his iPhone (`reranker.load` after two installs).
        guard bundled.pathExtension == "mlmodelc",
            let root = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let copy = stableCopy(of: bundled, under: root, fileManager: fileManager)
        else { return (bundled, false) }
        return (copy, true)
    }

    /// The copy of `bundled` under `root/Models`, made when missing; nil when it cannot be made.
    static func stableCopy(of bundled: URL, under root: URL, fileManager: FileManager = .default) -> URL? {
        guard let fingerprint = fingerprint(of: bundled, fileManager: fileManager) else { return nil }
        let base = bundled.deletingPathExtension().lastPathComponent
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        let name = "\(base)-\(fingerprint).\(bundled.pathExtension)"
        let target = folder.appendingPathComponent(name, isDirectory: true)
        // A marker beside the copy, written last, so a copy cut short by the app ending is never loaded.
        let marker = folder.appendingPathComponent(name + completeSuffix)
        if fileManager.fileExists(atPath: marker.path), fileManager.fileExists(atPath: target.path) { return target }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var folderURL = folder
            try? folderURL.setResourceValues(excluded)
            let staging = folder.appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
            try fileManager.copyItem(at: bundled, to: staging)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.moveItem(at: staging, to: target)
            guard fileManager.createFile(atPath: marker.path, contents: Data()) else { return nil }
            removeOtherCopies(of: base, keeping: name, in: folder, fileManager: fileManager)
            return target
        } catch {
            return nil
        }
    }

    /// A short hash of the model's files: every relative path and size, and the bytes of every file under 1 MB (the
    /// program, metadata and model description). Nil when the folder cannot be read.
    static func fingerprint(of model: URL, fileManager: FileManager = .default) -> String? {
        guard
            let enumerator = fileManager.enumerator(
                at: model, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        else { return nil }
        var entries: [(path: String, size: Int, url: URL)] = []
        let rootPath = model.standardizedFileURL.path
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(rootPath.count))
            entries.append((relative, values.fileSize ?? 0, file))
        }
        guard !entries.isEmpty else { return nil }
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data("\(entry.path)|\(entry.size)\n".utf8))
            if entry.size < hashWholeUnderBytes {
                guard let bytes = try? Data(contentsOf: entry.url) else { return nil }
                hasher.update(data: bytes)
            }
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Removes earlier copies of the same model, their markers, and staging folders left by an import cut short.
    private static func removeOtherCopies(
        of base: String, keeping name: String, in folder: URL, fileManager: FileManager
    ) {
        guard let items = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        for item in items where item != name && item != name + completeSuffix {
            if item.hasPrefix(base + "-") || item.hasPrefix(stagingPrefix) {
                try? fileManager.removeItem(at: folder.appendingPathComponent(item))
            }
        }
    }
}
