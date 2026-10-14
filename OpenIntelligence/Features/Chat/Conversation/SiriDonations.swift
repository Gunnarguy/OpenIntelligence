//
//  SiriDonations.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Tells the system which library is used and when, so Siri, Spotlight and the Lock Screen can
/// suggest opening it at that time of day (5.7). Through 5.6 the app donated nothing.
///
/// Called from the screens, not from `ContainerService` or `RAGService`, so a switch made by an
/// action or by a Focus filter is not counted as the person's own.
@MainActor
enum SiriDonations {
    /// A library the person chose or asked a question in.
    static func libraryUsed(_ container: KnowledgeContainer?) {
        // A library's name goes to the system, so only while "Spotlight Indexing" is on.
        guard let container, AppActivity.mayShareWithSystemSearch else { return }
        let intent = OpenLibraryIntent()
        intent.target = OILibraryEntityQuery.entity(for: container)
        _ = IntentDonationManager.shared.donate(intent: intent)
    }
}
