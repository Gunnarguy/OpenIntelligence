//
//  LibraryDeletion.swift
//  OpenIntelligence
//
//  One implementation of "delete this library", shared by every screen that offers it.
//
//  There were two near-identical copies, in `DocumentLibraryView.confirmDeleteLibrary` and
//  `ContainerSettingsSheet.confirmDeleteLibrary`, and they had already diverged in the way that
//  matters most: on an iCloud library whose shared copy fails to delete, the first aborted and
//  told the user, and the second logged the error and deleted locally anyway. That second
//  behaviour is the dangerous one. The shared copy still exists, so the next sync pass brings the
//  library back, and the user is left believing they deleted something they did not.
//
//  Deleting locally while the shared copy survives is not a partial success, it is a wrong
//  outcome. So this aborts and reports, which is what the Documents screen already did.
//
//  Two things had to move for that to be safe. `ContainerSettingsSheet` called `dismiss()` before
//  the work began, so an aborted delete would have had no surface left to report on; it now
//  dismisses only on success. And `resolvedLocalDeletionContainerIDs` is gone rather than being
//  carried over: its fallback compared `id.uuidString.lowercased()` to itself, so it could only
//  ever match the id its own early return had already handled.
//
//  Not folded in here:
//
//  - `DocumentLibraryView.deleteConflictedLocalLibraries` looks similar and is a different
//    operation. It removes several libraries that iCloud has already dropped, so there is no
//    shared copy to delete and it ends with a `reconfigureIfNeeded` pass instead.
//  - `OpenIntelligenceEngine.deleteLibrary` calls `containerService.deleteContainer` alone,
//    leaving every document, chunk, vector and Spotlight entry behind. That is a real leak, but
//    it is `public` and synchronous, and routing it through this async path would break the SDK's
//    signature. Left deliberately, recorded rather than quietly changed.
//

//  Lives under `Features/` rather than `Services/`, and that placement is load-bearing.
//
//  `OpenIntelligenceEngine`, the SDK framework target, synchronises eighteen specific folders,
//  among them `Services/Infrastructure/Integration`, and does not synchronise
//  `Services/Infrastructure/Presentation` or `Features`. The app target synchronises all of
//  `OpenIntelligence`. So a file dropped into `Integration/` is silently compiled into the SDK
//  framework as well, and this one references `LibraryVisualizationEngine`, which lives in
//  `Presentation/` and is therefore absent from that target. The app built cleanly and the test
//  build failed with "cannot find 'LibraryVisualizationEngine' in scope", which looks like a
//  stale-DerivedData error and is not one.
//
//  Excluding it in `project.pbxproj` would fix it too, but that file is a hard boundary. Moving
//  the file is the change that needs no approval and no exception list to maintain.

import Foundation
import SwiftUI

/// Deletes a library and everything belonging to it.
@MainActor
enum LibraryDeletion {
    enum Outcome: Equatable {
        /// The library and its contents are gone, locally and from iCloud where applicable.
        case deleted
        /// iCloud refused, so nothing was deleted locally either. Carries a message to show.
        case iCloudDeleteFailed(String)
        /// The last remaining library cannot be deleted, so nothing happened.
        case refusedLastLibrary
    }

    /// Removes `container`, its documents, chunks, vectors, Spotlight entries and entity index
    /// rows, and its iCloud copy when it has one.
    ///
    /// Aborts before touching anything local if the iCloud delete fails, so the two never
    /// disagree about whether the library exists.
    static func delete(
        _ container: KnowledgeContainer,
        ragService: RAGService,
        containerService: ContainerService,
        workspaceSyncService: WorkspaceSyncService
    ) async -> Outcome {
        // Enforced here rather than only at each call site, because it is an invariant of the
        // app and not of any one screen. `DocumentLibraryView` guarded it in the handler that
        // opens the alert and `ContainerSettingsSheet` guarded it in the confirm handler, which
        // is two chances to forget it.
        guard containerService.containers.count > 1 else { return .refusedLastLibrary }

        if container.syncMode == .iCloudShared {
            do {
                try await workspaceSyncService.deleteSharedLibrary(container)
            } catch {
                return .iCloudDeleteFailed(error.localizedDescription)
            }
        }

        // Nothing to remove locally if it is already gone, which is the only case the deleted
        // `resolvedLocalDeletionContainerIDs` helper could actually reach.
        guard containerService.containers.contains(where: { $0.id == container.id }) else {
            return .deleted
        }

        let containerId = container.id

        // Stop any in-flight ingestion first, so a document cannot finish importing into a
        // library that is being torn down underneath it.
        await ragService.cancelAndPurgeIngestion(for: containerId)

        // Per document rather than in bulk, because `removeDocument` is what clears the chunks,
        // the full-text rows, the Spotlight entry, the entity index and the imported file.
        let docsToRemove = ragService.documents.filter { $0.containerId == containerId }
        for doc in docsToRemove {
            try? await ragService.removeDocument(doc)
        }

        containerService.deleteContainer(id: containerId)
        LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
        containerService.reloadFromDisk()
        ragService.reloadWorkspaceData()

        await EntityIndexService.shared.removeContainer(containerId)

        return .deleted
    }
}
