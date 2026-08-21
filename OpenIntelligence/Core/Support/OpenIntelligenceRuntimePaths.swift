import Foundation

enum OpenIntelligenceRuntimePaths {
    nonisolated(unsafe) private static var overrideBaseDirectory: URL?
    nonisolated(unsafe) private static var overrideLocalCacheDirectory: URL?
    nonisolated(unsafe) private static var overridesPinned = false

    /// Guards the three override properties above.
    ///
    /// This used the `objc_sync` pair on `Self.self`, and it deadlocked ingestion. Sampled on
    /// 2026-08-21 during a benchmark case sitting at 0.0% CPU that would otherwise have timed out
    /// at 1800s:
    ///
    ///     RAGService.runIngestionLoop -> addDocument
    ///       -> SuggestedQuestionsService.generateQuestionsForIngestedDocument
    ///         -> mergeIntoPersistedBank -> loadQuestionBank
    ///           -> AppSupportPaths.suggestedQuestionsURL -> baseDir
    ///             -> OpenIntelligenceRuntimePaths.baseDirectory
    ///               -> [lock acquisition] -> _os_unfair_lock_lock_slow -> __ulock_wait2
    ///
    /// Blocked for the entire sample window while the main thread sat idle in its run loop, and
    /// every acquisition in this file was correctly paired with a release or a defer — so nothing
    /// of ours held it.
    ///
    /// That API takes an Objective-C object and selects a lock from a global striped table keyed
    /// by the pointer, so unrelated objects sharing a stripe share a lock. A Swift enum metatype
    /// is not an Objective-C object, and this type's stripe can be held by code with nothing to do
    /// with path resolution. A dedicated lock cannot be contended by anything but this file.
    ///
    /// Non-recursive is safe and must stay so: no method below calls another while holding it.
    /// `baseDirectory` and `localCacheDirectory` deliberately read the override, release, and only
    /// then touch the filesystem — file I/O must never happen under this lock.
    private static let overridesLock = NSLock()

    /// Set both overrides and refuse every later mutation for the life of the process.
    ///
    /// Exists for the benchmark harness, whose `--rag-validation-storage` override was being
    /// silently destroyed: `WorkspaceSyncService.init` runs `activateLocalWorkspace`, which calls
    /// `configureBaseDir(nil)` as part of ordinary workspace activation and cleared the override
    /// process-wide. From that point every write resolved to the owner's real library, which is how
    /// benchmark fixtures polluted it on every run and how a reset came to delete six real
    /// documents on 2026-08-16.
    ///
    /// The pin also covers the cache directory, because `localCacheDirectory()` falls back to
    /// `applicationSupportRoot()/LocalCache` rather than to the base override, so FTS5 writes
    /// reached the real index even while the base override was still alive. The owner's real
    /// FTS5 index was found holding 4,077 distinct document ids for roughly 15 documents.
    ///
    /// A refused mutation prints rather than logs: this file also builds in the engine package,
    /// which has no `Log`, and the pin can only ever be engaged by the DEBUG-only harness, so the
    /// print cannot fire in a shipping app.
    /// Whether a harness has pinned the runtime directories for this process.
    ///
    /// Exposed so workspace sync can decline to touch the owner's real library during a benchmark.
    /// `applicationSupportRoot()` deliberately does **not** consult the override, because four
    /// `coordinated*` iCloud primitives and `BNNSVectorDatabase` resolve through it, and redirecting
    /// those would point live iCloud sync at a temporary directory. The correct fix is for callers
    /// that should stand down during a benchmark to ask, rather than for the path to lie to
    /// everybody.
    nonisolated static var areOverridesPinned: Bool {
        overridesLock.lock()
        defer { overridesLock.unlock() }
        return overridesPinned
    }

    nonisolated static func pinOverrides(base: URL, localCache: URL) {
        overridesLock.lock()
        defer { overridesLock.unlock() }
        overrideBaseDirectory = base
        overrideLocalCacheDirectory = localCache
        overridesPinned = true
    }

    nonisolated static func setBaseDirectory(_ url: URL?) {
        overridesLock.lock()
        defer { overridesLock.unlock() }
        if overridesPinned {
            print("[RuntimePaths] refused setBaseDirectory(\(url?.path ?? "nil")): overrides are pinned for this run")
            return
        }
        overrideBaseDirectory = url
    }

    nonisolated static func setLocalCacheDirectory(_ url: URL?) {
        overridesLock.lock()
        defer { overridesLock.unlock() }
        if overridesPinned {
            print("[RuntimePaths] refused setLocalCacheDirectory(\(url?.path ?? "nil")): overrides are pinned for this run")
            return
        }
        overrideLocalCacheDirectory = url
    }

    nonisolated static func resetOverrides() {
        overridesLock.lock()
        defer { overridesLock.unlock() }
        if overridesPinned {
            print("[RuntimePaths] refused resetOverrides(): overrides are pinned for this run")
            return
        }
        overrideBaseDirectory = nil
        overrideLocalCacheDirectory = nil
    }

    nonisolated static func applicationSupportRoot(defaultFolderName: String = "OpenIntelligence") -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(defaultFolderName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func baseDirectory(defaultFolderName: String = "OpenIntelligence") -> URL {
        overridesLock.lock()
        let overrideBaseDirectory = overrideBaseDirectory
        overridesLock.unlock()

        if let overrideBaseDirectory {
            try? FileManager.default.createDirectory(
                at: overrideBaseDirectory,
                withIntermediateDirectories: true
            )
            return overrideBaseDirectory
        }

        return applicationSupportRoot(defaultFolderName: defaultFolderName)
    }

    nonisolated static func localCacheDirectory(defaultFolderName: String = "OpenIntelligence") -> URL {
        overridesLock.lock()
        let overrideLocalCacheDirectory = overrideLocalCacheDirectory
        overridesLock.unlock()

        if let overrideLocalCacheDirectory {
            try? FileManager.default.createDirectory(
                at: overrideLocalCacheDirectory,
                withIntermediateDirectories: true
            )
            return overrideLocalCacheDirectory
        }

        let dir = applicationSupportRoot(defaultFolderName: defaultFolderName)
            .appendingPathComponent("LocalCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum OpenIntelligenceResourceBundle {
    private final class Marker: NSObject {}
    nonisolated private static let swiftPackageBundleName = "OpenIntelligenceEngine_OpenIntelligenceEngine.bundle"
    nonisolated private static let tokenizersBundleName = "swift-transformers_TransformersTokenizers.bundle"

    nonisolated(unsafe) static var current: Bundle {
        Bundle(for: Marker.self)
    }

    nonisolated static func url(forResource name: String, withExtension ext: String? = nil) -> URL? {
        // 1. Search in the resolved tokenizers package bundle
        if let tokenizersBundle = resolveSwiftPackageBundle(named: tokenizersBundleName),
           let url = tokenizersBundle.url(forResource: name, withExtension: ext) {
            return url
        }

        // 2. Search in the resolved engine package bundle
        if let engineBundle = resolveSwiftPackageBundle(named: swiftPackageBundleName),
           let url = engineBundle.url(forResource: name, withExtension: ext) {
            return url
        }

        // 3. Search in the target framework bundle
        if let url = Bundle(for: Marker.self).url(forResource: name, withExtension: ext) {
            return url
        }

        // 4. Search in the main app bundle
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    nonisolated private static func resolveSwiftPackageBundle(named bundleName: String) -> Bundle? {
        let allBundles = Bundle.allBundles + Bundle.allFrameworks
        if let existingBundle = allBundles.first(where: { $0.bundleURL.lastPathComponent == bundleName }) {
            return existingBundle
        }

        let candidateRoots: [URL] = [
            Bundle.main.bundleURL,
            Bundle.main.resourceURL,
            Bundle(for: Marker.self).bundleURL,
            Bundle(for: Marker.self).resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ].compactMap { $0 }

        for root in candidateRoots {
            let directCandidate = root.appendingPathComponent(bundleName, isDirectory: true)
            if let bundle = Bundle(url: directCandidate) {
                return bundle
            }

            let contentsResourcesCandidate = root
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(bundleName, isDirectory: true)

            if let bundle = Bundle(url: contentsResourcesCandidate) {
                return bundle
            }
        }

        return nil
    }
}
