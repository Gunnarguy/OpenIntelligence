import Foundation

enum OpenIntelligenceRuntimePaths {
    nonisolated(unsafe) private static var overrideBaseDirectory: URL?

    nonisolated static func setBaseDirectory(_ url: URL?) {
        objc_sync_enter(Self.self)
        defer { objc_sync_exit(Self.self) }
        overrideBaseDirectory = url
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

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(defaultFolderName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum OpenIntelligenceResourceBundle {
    private final class Marker: NSObject {}

    nonisolated static var current: Bundle {
        Bundle(for: Marker.self)
    }

    nonisolated static func url(forResource name: String, withExtension ext: String) -> URL? {
        current.url(forResource: name, withExtension: ext)
    }
}
