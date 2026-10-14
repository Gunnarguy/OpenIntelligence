//
//  ViewAnnotations.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import AppIntents
import SwiftUI

/// The items a screen names to Siri and Apple Intelligence, so "this document" or "this
/// conversation" means what is on screen (5.7).
extension EntityIdentifier {
    static func document(_ id: UUID) -> EntityIdentifier {
        EntityIdentifier(for: OIDocumentEntity.self, identifier: id)
    }

    static func library(_ id: UUID) -> EntityIdentifier {
        EntityIdentifier(for: OILibraryEntity.self, identifier: id)
    }

    static func conversation(_ id: UUID) -> EntityIdentifier {
        EntityIdentifier(for: OIThreadEntity.self, identifier: id)
    }
}

extension View {
    /// Annotates the view with a document entity so Siri and Apple Intelligence can refer to it,
    /// and advertises the document for Handoff.
    ///
    /// Written in June 2026 and never called through 5.6, so no screen named its document. The
    /// document screen calls it from 5.7. Its library twin, also never called, was removed on
    /// 2026-10-14: the Documents screen names its library in the activity it already had.
    func annotateActiveDocument(_ document: OIDocumentEntity?) -> some View {
        self.modifier(ActiveDocumentAnnotationModifier(document: document))
    }
}

private struct ActiveDocumentAnnotationModifier: ViewModifier {
    let document: OIDocumentEntity?

    func body(content: Content) -> some View {
        content
            .userActivity(AppActivity.viewingDocument, element: document) { docEntity, activity in
                activity.title = "Viewing \(docEntity.filename)"
                activity.userInfo = AppActivity.userInfo(library: nil, document: docEntity.id)
                // The title names the file, so it reaches Spotlight and Siri's suggestions only
                // while the Spotlight switch is on (5.7).
                activity.isEligibleForSearch = AppActivity.mayShareWithSystemSearch
                #if os(iOS)
                    activity.isEligibleForPrediction = AppActivity.mayShareWithSystemSearch
                #endif
                activity.appEntityIdentifier = EntityIdentifier(for: docEntity)
            }
            // The view names the document as well, which holds whichever of the screen's
            // activities the system treats as current.
            .appEntityIdentifier(document.map { EntityIdentifier.document($0.id) })
    }
}
