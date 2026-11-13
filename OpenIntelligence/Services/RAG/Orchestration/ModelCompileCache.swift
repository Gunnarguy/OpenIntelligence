//
//  ModelCompileCache.swift
//  OpenIntelligence
//
//  Removes Core ML's old compiled copies of the app's models once per app version (5.8).
//

import Foundation

/// Removes Core ML's compiled copies of the app's models on the first launch of each app version (5.8).
///
/// Core ML compiles a model for the Neural Engine on its first load and keeps the result in the app's
/// `Library/Caches/<bundle id>/com.apple.e5rt.e5bundlecache`, keyed in part by the model's location. It never removes an
/// entry it no longer uses. Loading from the app bundle, whose path changes with each install, made it compile again
/// on most launches on the owner's iPhone and leave 202 entries, 1.47 GB, by 2026-11-12. The models now load from a
/// fixed path (`RerankerModelLocation`), and a new version recompiles them once anyway, so clearing the folder at the
/// first launch of a version costs nothing extra and keeps it from growing. The folder is renamed first (instant) and
/// deleted off the main thread, so no model load can meet a half-deleted entry.
nonisolated enum ModelCompileCache {
    static let folderName = "com.apple.e5rt.e5bundlecache"
    static let clearedForVersionKey = "modelCompileCacheClearedForVersion.v1"

    /// The app's version and build, which a new install from the App Store or a development build changes.
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let executableDate = Bundle.main.executableURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        }
        return "\(version) (\(build)) \(executableDate.map { "\(Int($0.timeIntervalSince1970))" } ?? "")"
    }

    /// The folder Core ML keeps its compiled models in for this app.
    static func cacheFolder(fileManager: FileManager = .default) -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            let bundleId = Bundle.main.bundleIdentifier
        else { return nil }
        return caches.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
    }

    /// Clears the folder once per app version. Call at launch, before any model loads.
    static func clearOncePerVersion(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        let version = currentVersion
        guard defaults.string(forKey: clearedForVersionKey) != version else { return }
        defaults.set(version, forKey: clearedForVersionKey)
        guard let folder = cacheFolder(fileManager: fileManager), fileManager.fileExists(atPath: folder.path) else { return }
        let retired = folder.deletingLastPathComponent()
            .appendingPathComponent("\(folderName).retired-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.moveItem(at: folder, to: retired)
        } catch {
            Log.warning("[ModelCompileCache] Could not set the old compiled models aside: \(error.localizedDescription)", category: .initialization)
            return
        }
        Task.detached(priority: .utility) {
            let bytes = Self.size(of: retired, fileManager: fileManager)
            try? fileManager.removeItem(at: retired)
            Log.info(
                "[ModelCompileCache] Removed old compiled models: \(String(format: "%.1f", Double(bytes) / 1_048_576)) MB",
                category: .initialization)
            VerificationJournal.record("modelCache.cleared", .ok, ["megabytes": "\(bytes / 1_048_576)"])
        }
    }

    private static func size(of folder: URL, fileManager: FileManager) -> Int64 {
        guard let walk = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
