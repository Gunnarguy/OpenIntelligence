//
//  SharedInboxImport.swift
//  OpenIntelligence
//
//  Adds what was shared to OpenIntelligence from another app's share sheet (5.7).
//

import Foundation
import SwiftUI

/// Adds what the Share Sheet extension left in the app group's inbox (`SharedInbox`) the way the Documents screen's
/// Paste button adds a copied address or text (5.7): through `PastedContentStaging`, so a web address is downloaded the
/// way "Save a Web Page" does it and text is saved as a note, then the Documents screen runs its plan check and import
/// review on the files (`AppNavigationRequest`, `.importFiles`). One item at a time: an item leaves the inbox once it
/// is stored, and one that couldn't be (a page while offline, say) goes back to be tried the next time the app is in
/// front, up to `SharedInbox.maxAttempts` times.
enum SharedInboxImport {
    /// One run at a time, across windows: a second activation while the first is downloading finds nothing to do.
    private static var isTaking = false

    /// A shared item as the Paste button reads it. Text that is one web address and nothing else is a link, as when
    /// it's pasted; an address that isn't http or https is nothing.
    nonisolated static func pastedItem(_ item: SharedInbox.Item) -> PastedContentStaging.Item? {
        switch item.kind {
        case .link: return URL(string: item.value).flatMap { PastedContentStaging.item(for: $0) }
        case .text: return PastedContentStaging.item(for: item.value)
        }
    }

    /// How an item is named in a message: a page by its site, text as "Text", as the Paste button names them.
    nonisolated static func label(for item: SharedInbox.Item) -> String {
        pastedItem(item).map(PastedContentStaging.label(for:)) ?? "Something you shared"
    }

    /// The provider the Paste button's staging reads for an item.
    nonisolated static func provider(for item: PastedContentStaging.Item) -> NSItemProvider? {
        switch item {
        case .link(let url): return NSItemProvider(object: url as NSURL)
        case .text(let text): return NSItemProvider(object: text as NSString)
        case .file: return nil
        }
    }

    /// Takes what is waiting and stores it in the imported-documents folder, at most `room` items: the Documents screen
    /// removes a file it can't add, so what the plan has no room for goes back into the inbox as it was and waits
    /// (review of 2026-10-17). A failure names the item, and says when it will be tried again. Returns how many wait.
    static func takeAndStage(from folder: URL, room: Int = .max) async -> (
        outcome: PastedContentStaging.Outcome, waiting: Int
    ) {
        guard !isTaking else { return (PastedContentStaging.Outcome(), 0) }
        isTaking = true
        defer { isTaking = false }

        var outcome = PastedContentStaging.Outcome()
        var waiting = 0
        let claim = SharedInbox.claimAll(from: folder)
        for item in claim.letGo {
            outcome.failures.append(
                "\(label(for: item)): OpenIntelligence closed while adding it \(SharedInbox.maxAttempts) times, so it wasn't added.")
        }
        for claimed in claim.items {
            guard outcome.staged.count < room else {
                SharedInbox.release(claimed, into: folder)
                waiting += 1
                continue
            }
            guard let item = pastedItem(claimed.item), let provider = provider(for: item) else {
                SharedInbox.finish(claimed)
                continue
            }
            // Marked while it is stored, so if the app ends now only this item counts a try.
            let trying = SharedInbox.beginTrying(claimed)
            let one = await PastedContentStaging.stage([provider])
            outcome.staged += one.staged
            if one.failures.isEmpty {
                SharedInbox.finish(trying)
            } else if SharedInbox.putBack(trying, into: folder) {
                outcome.failures += one.failures.map { "\($0) It's tried again the next time you open OpenIntelligence." }
            } else {
                outcome.failures += one.failures
            }
        }
        return (outcome, waiting)
    }
}

/// What the app says when some of what was shared could not be added (5.7), in the Paste button's words. What was
/// stored has already gone to the Documents screen: it doesn't wait for the alert, so nothing stored is left in the
/// imported-documents folder if the app closes while the alert is up (review of 2026-10-17).
struct SharedItemsMessage: Identifiable {
    let id = UUID()
    /// Whether any of it was stored.
    let addedSome: Bool
    /// One line per item that could not be stored.
    let failures: [String]
    /// A title of its own, for a message about pages from the Lock Screen camera (5.7).
    var customTitle: String? = nil

    var title: String {
        customTitle ?? (addedSome ? "Some of What You Shared Was Not Added" : "What You Shared Was Not Added")
    }
}

/// The alert for what was shared and not added (5.7), as a modifier of its own: one more alert inline in
/// `ContentView`'s chain of modifiers was more than the compiler would type-check in reasonable time.
struct SharedItemsAlert: ViewModifier {
    @Binding var message: SharedItemsMessage?

    func body(content: Content) -> some View {
        content.alert(
            message?.title ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { shown in
            Text(shown.failures.joined(separator: "\n"))
        }
    }
}
