import Foundation

enum OpenIntelligenceRuntimePaths {
    nonisolated(unsafe) private static var overrideBaseDirectory: URL?
    nonisolated(unsafe) private static var overrideLocalCacheDirectory: URL?

    nonisolated static func setBaseDirectory(_ url: URL?) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        overrideBaseDirectory = url
    }

    nonisolated static func setLocalCacheDirectory(_ url: URL?) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        overrideLocalCacheDirectory = url
    }

    nonisolated static func resetOverrides() {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
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

    nonisolated(unsafe) static var current: Bundle {
#if SWIFT_PACKAGE
        if let bundle = resolveSwiftPackageBundle() {
            return bundle
        }

        return Bundle.main
#else
        Bundle(for: Marker.self)
#endif
    }

    nonisolated static func url(forResource name: String, withExtension ext: String? = nil) -> URL? {
        current.url(forResource: name, withExtension: ext)
    }

#if SWIFT_PACKAGE
    nonisolated private static func resolveSwiftPackageBundle() -> Bundle? {
        let allBundles = Bundle.allBundles + Bundle.allFrameworks
        if let existingBundle = allBundles.first(where: { $0.bundleURL.lastPathComponent == swiftPackageBundleName }) {
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
            let directCandidate = root.appendingPathComponent(swiftPackageBundleName, isDirectory: true)
            if let bundle = Bundle(url: directCandidate) {
                return bundle
            }

            let contentsResourcesCandidate = root
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(swiftPackageBundleName, isDirectory: true)

            if let bundle = Bundle(url: contentsResourcesCandidate) {
                return bundle
            }
        }

        return nil
    }
#endif
}
