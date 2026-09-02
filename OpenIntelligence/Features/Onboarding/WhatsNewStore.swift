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
        // Keyed by CFBundleShortVersionString, and the key must exist or the sheet
        // silently never appears: `showIfNeeded` marks an unknown version as seen and
        // returns. macOS shipped 5.0 as build 379 and is missing everything here; iOS
        // never shipped 5.0 at all, so on iPhone and iPad this is the first 5.x release.
        "5.1": WhatsNewRelease(
            version: "5.1",
            headline: "Importing a large document on the Mac had become slow enough to be unusable, and the app kept working away while idle. This release is those two, better text recognition on every platform, and built-in guides that finally describe the app you are running. On iPhone and iPad it also brings across the two Mac-only releases before it.",
            items: [
                .init(
                    symbol: "doc.richtext",
                    title: "The Mac was drawing every PDF page four times too large",
                    detail: "Each page was rendered at four times the resolution requested, then copied through an uncompressed image format and straight back, once per page. On a Retina display that was roughly 370 MB written and read per page, for nothing. The iPhone never did this. Each page is now drawn once, at the size asked for."
                ),
                .init(
                    symbol: "moon.zzz",
                    title: "An idle app was re-reading every search index seventeen times a second",
                    detail: "A background timer kept finding one library in a state it could not resolve and reloaded every index on each pass whether or not anything had changed. Left running for a few hours it built a backlog it could never clear and stopped responding. Indexes are now re-read only when they have actually changed on disk."
                ),
                .init(
                    symbol: "arrow.clockwise.circle",
                    title: "A paused import no longer looks lost",
                    detail: "Quitting during a large PDF import and reopening showed the document at zero, as though the work was gone. It never was: the app has always resumed from the last page it finished. But the screen said otherwise, and removing the item is the one action that does discard that progress. A resumed import now reports how many pages it already has."
                ),
                .init(
                    symbol: "character.book.closed",
                    title: "Text recognition is told the document's language instead of guessing it",
                    detail: "The app was asking the system to guess each page's language while also handing it a list of thirteen to choose from. A wrong guess corrects words against the wrong dictionary, which damages text rather than just slowing things down. The language is now worked out once from the document itself. Page images also go to recognition scaled to what is needed to read the smallest real print, instead of at the slowest possible setting."
                ),
                .init(
                    symbol: "book.pages",
                    title: "The built-in guides describe this version of the app",
                    detail: "The three sample documents said complex questions were sent to Private Cloud Compute, which nothing in this build does, and knew nothing about how importing works. They are rewritten from the code: every format the app reads, what happens during an import and after a quit, what each quality mode actually changes, and what Private Cloud Compute will add when it arrives with iOS and macOS 27. If you already imported them, they update in place."
                ),
                .init(
                    symbol: "app.badge",
                    title: "The Mac icon is no longer a square",
                    detail: "Every Mac icon was a solid square filling the whole tile, and the dark version still carried a thin blue rim from the light one. Both are redrawn to sit inside the rounded shape macOS expects. The iPhone and iPad icons were already correct."
                ),
            ]
        ),
        "5.0.2": WhatsNewRelease(
            version: "5.0.2",
            headline: "Mac only. There was no way to get a document into the app: the Add Documents button opened nothing, and dragging a file onto the window did nothing either. Both are fixed.",
            items: [
                .init(
                    symbol: "folder.badge.plus",
                    title: "The Add Documents button opened nothing",
                    detail: "The button asked macOS for a file picker at the one moment the system refuses to open one, so the request was discarded and no window ever appeared. The two file buttons inside a chat had the same fault. All three now ask at a point the system accepts."
                ),
                .init(
                    symbol: "arrow.down.doc",
                    title: "Drag files from Finder straight into a library",
                    detail: "Nothing in the app was listening for a dropped file. The whole library area now accepts them, and dropped files go through the same size and plan checks and the same import review as picked ones. Folders are not accepted yet; drop the files from inside them."
                ),
                .init(
                    symbol: "sidebar.left",
                    title: "Library Settings was unreadable on the Mac",
                    detail: "The screen was drawn as a narrow strip beside a large blank area, squeezed hard enough to break words apart. It was built on an older navigation container that macOS turns into a two-pane layout. It now uses a single column at a sensible width."
                ),
                .init(
                    symbol: "doc.on.doc",
                    title: "The built-in samples were quietly duplicating themselves",
                    detail: "When a sample is corrected in a new version the app replaces your copy, but it was deleting the original and not the duplicate an earlier update had left behind, so each round added one more. Existing duplicates are cleaned up on the next update, and documents you named yourself are never touched."
                ),
            ]
        ),
        "5.0.1": WhatsNewRelease(
            version: "5.0.1",
            headline: "Turning the performance up was making the app slower, Macs were being held to iPhone limits, and the Documents tab was waiting on a number it never showed you. This release is those three and the rest of what came after 5.0.",
            items: [
                .init(
                    symbol: "gauge.with.dots.needle.67percent",
                    title: "Turning performance up was making it slower",
                    detail: "Efficiency, Balanced, Performance and Maximum were inverted: climbing the ladder removed hardware instead of adding it, so the setting meant to unlock the machine was quietly holding it back. Each option now says which of the CPU, GPU and Neural Engine it engages, and the selector shows you all four instead of hiding three behind a menu."
                ),
                .init(
                    symbol: "desktopcomputer",
                    title: "Macs were being given iPhone-sized limits",
                    detail: "The app sorts devices into capability tiers, and base M4 and M5 Macs had been demoted for a reason that did not survive checking. They now sit alongside their Pro and Max siblings, which is what their actual throughput supports."
                ),
                .init(
                    symbol: "cpu",
                    title: "It understands Apple chips that do not exist yet",
                    detail: "A chip this build has never heard of used to read as two generations old and fall back to the slowest settings. Newer silicon now scales forward instead. One hardware reading was also reporting a ceiling of 1,073,741,824 threads, which was three separate limits multiplied together."
                ),
                .init(
                    symbol: "bolt.horizontal",
                    title: "The Documents tab stopped waiting on a number it never showed you",
                    detail: "Opening it counted your cached documents first, and that count feeds one row that stays hidden unless the count is above zero. On the device this was traced on it was zero, so the row was never drawn. It cost up to 393 milliseconds on every single open, and it was the slowest thing in a log of nearly six thousand lines."
                ),
                .init(
                    symbol: "tag",
                    title: "The Atlas was labelling a medical paper \"API Reference\"",
                    detail: "Cluster labels were matched on letters rather than words, so \"api\" inside \"therapies\" and \"min\" inside \"dopamine\" were enough to name a group. The same mistake existed in three separate copies of the labelling code. A tag that appears only once in a document also no longer describes it."
                ),
                .init(
                    symbol: "hourglass",
                    title: "\"Analyzing corpus…\" was never analyzing anything",
                    detail: "It was an empty state wearing a progress indicator, and it could not finish because nothing had been started. Choosing a library on the Database screen is also a row of buttons now rather than a menu, which matters when you have eight of them."
                ),
                .init(
                    symbol: "slider.horizontal.3",
                    title: "The Temperature slider did nothing on one setting",
                    detail: "Greedy sampling always takes the most likely next word, so temperature has no effect on it, but the slider stayed live and looked like it was doing something. It is now disabled there and says why. The Deep Think card also described a minimum number of passes that never existed."
                ),
                .init(
                    symbol: "rotate.right",
                    title: "Rotating the device left black rectangles on screen",
                    detail: "The floating hardware readout lives in its own window and was clamping itself against screen bounds that never rotate. The chip and haptic engine outlines stay put when you turn the device, because the hardware does not move. The readout itself now also shows free memory."
                ),
            ]
        ),
        "5.0": WhatsNewRelease(
            version: "5.0",
            headline: "Documents were quietly losing parts of themselves, answers were built from a fraction of what was found, and the app was rewriting your library on every launch. This release is the search for all three.",
            items: [
                .init(
                    symbol: "scissors",
                    title: "More than half of every document never reached the search index",
                    detail: "A limit in the text handling cut every passage at about a quarter of what the model could actually read, and the length check returned the same number for every input, so nothing looked wrong. Across a real library, 90% of passages were cut short. This is the main reason your libraries offer to rebuild once."
                ),
                .init(
                    symbol: "brain",
                    title: "The search index was reading the wrong part of the model",
                    detail: "Every document you have ever added was indexed using one position of the AI model instead of averaging the whole passage. It was never broken enough to notice and it made search markedly worse. Your libraries will offer to rebuild once, and searching improves substantially afterwards."
                ),
                .init(
                    symbol: "doc.richtext",
                    title: "Two-column pages are read column by column, not straight across",
                    detail: "Papers, reports and anything set in two columns were read across the gutter, so the end of a line on the left ran into the start of a line on the right. Pages could also come out in the wrong order. Both are fixed, and the stored text now matches what is on the page."
                ),
                .init(
                    symbol: "checkmark.seal",
                    title: "A finished answer can no longer be replaced by a worse one",
                    detail: "A final editing pass could swap a complete, cited answer for a short stub, or strip its citations out, and nothing checked before it did. Every replacement is now checked first. An answer that claims your documents say nothing while citing them is caught and retried."
                ),
                .init(
                    symbol: "books.vertical",
                    title: "Reference lists stopped outranking the papers that cited them",
                    detail: "A bibliography is the strongest keyword match on a page and the weakest evidence, so answers were being built from lists of author names. Reference sections now rank lower, and a document's tags are no longer generated from them."
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
                    title: "Four ways a library could lose its answers while keeping its documents, closed",
                    detail: "A library could look fine and answer nothing, with no warning, sometimes for an entire session. Detection now runs the moment a question comes back empty, and a repair no longer reports success when it was blocked from doing anything."
                ),
                .init(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Importing certain documents could freeze the whole queue",
                    detail: "One file lookup could deadlock, and everything queued behind it waited forever with no explanation. Fixed at the root; a stuck import can no longer take the rest of the queue down with it."
                ),
                .init(
                    symbol: "arrow.left.arrow.right.square",
                    title: "Switching libraries no longer resets your place or flashes the screen",
                    detail: "The library picker was rebuilding itself from scratch on certain switches, which reset it back to your first library and made the whole screen visibly redraw."
                ),
                .init(
                    symbol: "quote.opening",
                    title: "Citations always point at a real source now",
                    detail: "An answer could cite a source number past the end of its own list, and confidence still reported a reassuring middle number. Citations are checked before you see them, and confidence can now report a genuine failure."
                ),
                .init(
                    symbol: "arrow.triangle.merge",
                    title: "Combining keyword and meaning-based search stopped losing to keyword search alone",
                    detail: "The two are supposed to complement each other. The combined result was ranking worse than plain keyword search by itself; it no longer does."
                ),
                .init(
                    symbol: "character.book.closed",
                    title: "Plain English definitions open reliably, and cover a lot more of the app",
                    detail: "Tapping a term could animate to nothing and leave the back button pointed at a blank screen; fixed. Seven new entries too, including the difference between Standard, Deep Think and Maximum, and what confidence and the trust badges actually mean."
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
