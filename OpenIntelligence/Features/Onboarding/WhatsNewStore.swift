//
//  WhatsNewStore.swift
//  OpenIntelligence
//
//  Decides whether to show the "what changed" sheet after an update, and holds
//  the release copy.
//
//  The content lives in Swift rather than a bundled file for the same reason
//  `SampleDocumentManager` does: it ships with the binary, cannot go missing, and
//  cannot drift from the version it describes.
//

import Combine
import Foundation

/// One shipped release, as users should hear about it.
struct WhatsNewRelease: Identifiable, Sendable {
    struct Item: Identifiable, Sendable {
        let id = UUID()
        /// SF Symbol shown beside the item.
        let symbol: String
        let title: String
        let detail: String
    }

    var id: String { version }
    let version: String
    /// One line that says why this update matters. Shown under the title.
    let headline: String
    let items: [Item]
}

@MainActor
final class WhatsNewStore: ObservableObject {
    /// Non-nil when there is something the user has not seen yet.
    @Published var pendingRelease: WhatsNewRelease?

    private let defaults: UserDefaults
    private let currentVersion: String

    private static let lastSeenKey = "whatsNew.lastSeenVersion"

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    /// Call once when the app becomes active.
    ///
    /// Deliberately silent on a fresh install. Someone opening the app for the very
    /// first time has no "before" to compare against, and the onboarding checklist
    /// already owns that moment — leading with a changelog would be noise. The first
    /// launch only records the version, so the sheet appears on the first *update*.
    func evaluateOnLaunch() {
        guard !currentVersion.isEmpty else { return }

        let lastSeen = defaults.string(forKey: Self.lastSeenKey)

        guard let lastSeen else {
            // Fresh install: remember where we started, show nothing.
            defaults.set(currentVersion, forKey: Self.lastSeenKey)
            return
        }

        guard lastSeen != currentVersion else { return }

        // Updated since the last launch. Show the notes for the version now running;
        // if this build has none authored, record it silently rather than showing an
        // empty sheet.
        guard let release = Self.releases[currentVersion] else {
            defaults.set(currentVersion, forKey: Self.lastSeenKey)
            return
        }

        pendingRelease = release
    }

    /// Dismiss and do not show this version again.
    func markSeen() {
        defaults.set(currentVersion, forKey: Self.lastSeenKey)
        pendingRelease = nil
    }

    /// Re-open the current release from Settings, regardless of seen state.
    func releaseForCurrentVersion() -> WhatsNewRelease? {
        Self.releases[currentVersion]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Release copy
    //
    // Keyed by CFBundleShortVersionString. Wording matches
    // `Docs/USER_CHANGELOG.md` so the store listing, the repo changelog and the
    // in-app sheet all say the same thing.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let releases: [String: WhatsNewRelease] = [
        "5.0": WhatsNewRelease(
            version: "5.0",
            headline: "Documents were quietly losing parts of themselves, answers were built from a fraction of what was found, and the app was rewriting your library on every launch. This release is the search for all three.",
            items: [
                .init(
                    symbol: "brain",
                    title: "The search index was reading the wrong part of the model",
                    detail: "Every document you have ever added was indexed using one position of the AI model instead of averaging the whole passage. It was never broken enough to notice and it made search markedly worse. Your libraries will offer to rebuild once, and searching improves substantially afterwards."
                ),
                .init(
                    symbol: "text.magnifyingglass",
                    title: "Deep Think was answering from a fraction of what it found",
                    detail: "It retrieved the right passages and then discarded most of them before writing, including the single best one. It now keeps the most relevant evidence and says in the logs what it left out."
                ),
                .init(
                    symbol: "hare",
                    title: "Deep Think is roughly three times faster",
                    detail: "On a smaller library it kept re-reading passages it had already read, word for word, for about a third of its total time. It now stops once it has covered the material, and still reads everything it retrieved."
                ),
                .init(
                    symbol: "wrench.and.screwdriver",
                    title: "A library that cannot answer now says so, and can fix itself",
                    detail: "If a library's search index goes missing, it now tells you and offers a rebuild that works. Before, it stayed silent and deleting the library was the only way out."
                ),
                .init(
                    symbol: "icloud",
                    title: "iCloud sync stopped re-uploading libraries that had not changed",
                    detail: "Every sync rewrote each library's index whether or not anything differed, and each rewrite looked like a change and started another one. Hundreds of megabytes per launch, for nothing."
                ),
                .init(
                    symbol: "bolt",
                    title: "The app starts faster and reaches the first screen sooner",
                    detail: "A 43 MB model loaded on every launch before anything appeared, even if you never asked a question. It now loads the first time it is actually needed."
                ),
                .init(
                    symbol: "bubble.left.and.text.bubble.right",
                    title: "Leaving the chat tab no longer kills the answer",
                    detail: "Switching away mid-answer used to cancel it and throw away everything written so far, with nothing to explain why. The chat also keeps your scroll position instead of jumping to the newest message."
                ),
                .init(
                    symbol: "hand.tap",
                    title: "The document screen is one tap everywhere",
                    detail: "Add, search, settings and both delete actions are five icons on a single row instead of two buttons and a hidden menu. Press-and-hold on a library behaves like the rest of iOS instead of fighting the scroll."
                ),
                .init(
                    symbol: "tablecells",
                    title: "Tables, images and scanned pages survive importing",
                    detail: "Word tables were read into rows and then dropped. Images collapsed to one unbroken line. A fully scanned PDF reported scanning zero pages."
                ),
                .init(
                    symbol: "exclamationmark.triangle",
                    title: "Pages, Numbers and Keynote files now fail clearly",
                    detail: "They were never actually readable. Importing one no longer looks like it worked."
                ),
            ]
        ),
        // iOS 4.8 was developer-rejected and never shipped, so an iPhone coming
        // from 4.7 sees all of this for the first time. macOS 4.8 was approved,
        // so a Mac coming from it only finds the iCloud item new. One list
        // serves both; the alternative is a per-platform key for one bullet.
        "4.9": WhatsNewRelease(
            version: "4.9",
            headline: "Deep Think and Maximum weren't wired up correctly. This release connects them.",
            items: [
                .init(
                    symbol: "brain",
                    title: "Deep Think and Maximum actually reason now",
                    detail: "Previously they returned Standard quality answers after a much longer wait."
                ),
                .init(
                    symbol: "quote.opening",
                    title: "Answers cite their sources in every mode",
                    detail: "Maximum produced none at all."
                ),
                .init(
                    symbol: "iphone",
                    title: "On-Device covers the entire query",
                    detail: "Including the final answer. The model picker now governs every mode, not just Standard."
                ),
                .init(
                    symbol: "gauge.with.dots.needle.33percent",
                    title: "Both modes stop when they're finished",
                    detail: "Typically halving the time Maximum takes."
                ),
                .init(
                    symbol: "doc.on.doc",
                    title: "Documents stop disappearing after import",
                    detail: "One that finished while the library was saving could be dropped from the list."
                ),
                .init(
                    symbol: "icloud",
                    title: "iCloud libraries stop asking you to re-import",
                    detail: "Documents processed on one device now carry over to your others."
                ),
                .init(
                    symbol: "doc.badge.plus",
                    title: "Document import works on Mac",
                    detail: "The file picker there was a placeholder."
                ),
            ]
        )
    ]
}
