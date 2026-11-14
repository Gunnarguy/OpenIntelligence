//
//  ModelCompileCache.swift
//  OpenIntelligence
//
//  Removes Core ML's old compiled copies of the app's models when a bundled model changes (5.8).
//

import Foundation

/// Removes Core ML's compiled copies of the app's models when a bundled model changes (5.8; once per app version until
/// 2026-11-13, see `clearOncePerVersion`).
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

    static let clearedForModelsKey = "modelCompileCacheClearedForModels.v1"

    /// The bundled models as they are: each one's name and fingerprint. It changes only when a model does.
    static func bundledModels(fileManager: FileManager = .default) -> String {
        ["EmbeddingModel", "ReRankerModel"].map { name in
            let url = OpenIntelligenceResourceBundle.url(forResource: name, withExtension: "mlmodelc")
            let print = url.flatMap { RerankerModelLocation.fingerprint(of: $0, fileManager: fileManager) } ?? "none"
            return "\(name)-\(print)"
        }.joined(separator: ",")
    }

    /// Whether the compiled copies should be cleared now: only when the bundled models differ from the ones they were
    /// last cleared for. `adoptedFromVersionKey` is true where the per-version key of earlier 5.8 builds exists: those
    /// cleared at their last install, so the cache holds only the current models and is kept.
    static func shouldClear(models: String, clearedFor: String?, adoptedFromVersionKey: Bool) -> Bool {
        if let clearedFor { return clearedFor != models }
        return !adoptedFromVersionKey
    }

    /// Clears the folder when the bundled models change (5.8, 2026-11-13). Call at launch, before any model loads.
    ///
    /// Until that day it cleared on the first launch of every app version, on the reasoning that "a new version
    /// recompiles them once anyway". It does not: the models load from a fixed path, so Core ML finds what it compiled
    /// whatever the app's version. The clearing itself was what made every install spend a minute on "Getting search
    /// ready": the owner's iPhone journal shows `modelCache.cleared` (75 MB, the two models' compiled forms) at the
    /// first launch of each of nine installs on 2026-11-13, each followed by loads of 48 to 90 s, and loads of 1.0 and
    /// 1.6 s on the launches that followed with no install between. An update that ships the same models now keeps
    /// them; one that changes a model clears and compiles once.
    static func clearOncePerVersion(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        let models = bundledModels(fileManager: fileManager)
        let clear = shouldClear(
            models: models, clearedFor: defaults.string(forKey: clearedForModelsKey),
            adoptedFromVersionKey: defaults.string(forKey: clearedForVersionKey) != nil)
        defaults.set(models, forKey: clearedForModelsKey)
        guard clear else { return }
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
