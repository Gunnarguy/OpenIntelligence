//
//  LockedCaptureImport.swift
//  OpenIntelligence
//
//  Pages scanned from the Lock Screen (5.7).
//

import Foundation

#if os(iOS) && canImport(LockedCameraCapture)
    import LockedCameraCapture
#endif

/// Takes the pages OpenIntelligence's Lock Screen camera kept (`OpenIntelligenceCapture`, 5.7) and stores them in the
/// imported-documents folder, so the Documents screen runs its plan check and import review on them and adds them to
/// the library that is open (`AppNavigationRequest`, `.importFiles`). The camera keeps each photo in its session's
/// folder, which is in the app's own data container; the app lists those folders with
/// `LockedCameraCaptureManager.sessionContentURLs` (developer.apple.com, read 2026-10-17). A photo is removed from its
/// session folder once it has been copied, so it is added once, and a folder whose photos were all stored is handed
/// back to the system with `invalidateSessionContent(at:)` (the iOS 27 SDK's interface, read 2026-10-17).
///
/// Only as many photos are taken as the plan has room for: the Documents screen removes a handed-over file it can't
/// add, and the camera's copy is the only one (review of 2026-10-17). The rest wait in the camera's folder.
nonisolated enum LockedCaptureImport {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "png"]

    /// One run at a time across windows, as for the share inbox: two windows that become active together would each
    /// copy a page before either had removed it.
    @MainActor private static var isTaking = false

    /// Copies the photos in the folders into the imported-documents folder, oldest name first and at most `limit` of
    /// them, and removes each one from its folder once it is copied. Returns the copies, and the folders whose photos
    /// were all stored, for the system to remove. `store` stands in for the copy in tests.
    static func takeAll(
        from folders: [URL],
        atMost limit: Int = .max,
        store: (URL) throws -> URL = { try IntentSupport.copyIntoImports($0) }
    ) -> (staged: [URL], finished: [URL]) {
        let fileManager = FileManager.default
        var staged: [URL] = []
        var finished: [URL] = []
        for folder in folders {
            let photos = photos(in: folder)
            var storedAll = true
            for photo in photos {
                guard staged.count < limit, let copy = try? store(photo) else {
                    storedAll = false
                    continue
                }
                staged.append(copy)
                try? fileManager.removeItem(at: photo)
            }
            if storedAll { finished.append(folder) }
        }
        return (staged, finished)
    }

    /// The photos waiting in the folders.
    static func waitingCount(in folders: [URL]) -> Int {
        folders.reduce(0) { $0 + photos(in: $1).count }
    }

    private static func photos(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// The photos the Lock Screen camera kept and the plan has room for, copied and taken from it, and how many still
    /// wait; nothing on the Mac, which has no such camera, and nothing while another window is taking them.
    @MainActor
    static func takeFromTheLockScreen(atMost limit: Int) async -> (staged: [URL], waiting: Int) {
        guard !isTaking else { return ([], 0) }
        isTaking = true
        defer { isTaking = false }
        return await takeAndRelease(atMost: limit)
    }

    /// Off the main actor: the copies are photos of several megabytes.
    @concurrent
    private static func takeAndRelease(atMost limit: Int) async -> (staged: [URL], waiting: Int) {
        #if os(iOS) && canImport(LockedCameraCapture)
            let manager = LockedCameraCaptureManager.shared
            let folders = manager.sessionContentURLs
            let taken = takeAll(from: folders, atMost: limit)
            for folder in taken.finished {
                // A failure leaves the folder, which the next run hands back again.
                try? await manager.invalidateSessionContent(at: folder)
            }
            return (taken.staged, waitingCount(in: folders))
        #else
            return ([], 0)
        #endif
    }
}
