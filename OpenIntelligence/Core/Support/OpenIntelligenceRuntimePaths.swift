import Foundation

enum OpenIntelligenceRuntimePaths {
    nonisolated(unsafe) private static var overrideBaseDirectory: URL?
    nonisolated(unsafe) private static var overrideLocalCacheDirectory: URL?
    nonisolated(unsafe) private static var overridesPinned = false

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
    nonisolated static func pinOverrides(base: URL, localCache: URL) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        overrideBaseDirectory = base
        overrideLocalCacheDirectory = localCache
        overridesPinned = true
    }

    nonisolated static func setBaseDirectory(_ url: URL?) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        if overridesPinned {
            print("[RuntimePaths] refused setBaseDirectory(\(url?.path ?? "nil")): overrides are pinned for this run")
            return
        }
        overrideBaseDirectory = url
    }

    nonisolated static func setLocalCacheDirectory(_ url: URL?) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        if overridesPinned {
            print("[RuntimePaths] refused setLocalCacheDirectory(\(url?.path ?? "nil")): overrides are pinned for this run")
            return
        }
        overrideLocalCacheDirectory = url
    }

    nonisolated static func resetOverrides() {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
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
        objc_sync_enter(Self.self)
        let overrideBaseDirectory = overrideBaseDirectory
        objc_sync_exit(Self.self)

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
        objc_sync_enter(Self.self)
        let overrideLocalCacheDirectory = overrideLocalCacheDirectory
        objc_sync_exit(Self.self)

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
