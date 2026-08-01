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
        "4.8": WhatsNewRelease(
            version: "4.8",
            headline: "Deep Think and Maximum weren't wired up correctly. This release connects them.",
            items: [
                .init(
                    symbol: "brain",
                    title: "Deep Think and Maximum now reason over your evidence",
                    detail: "Both modes run several reasoning passes across your documents, each building on the last. The handoff between retrieval and the reasoning step was never connected, so every pass concluded there was nothing to work with."
                ),
                .init(
                    symbol: "magnifyingglass",
                    title: "Retrieval was never the problem",
                    detail: "Your documents were being found, ranked, and prepared correctly the entire time. The evidence simply never reached the step that decides how to answer."
                ),
                .init(
                    symbol: "checkmark.shield",
                    title: "Resolved \"The selected model isn't available right now\"",
                    detail: "That message appeared when the reasoning step found nothing to plan against. It was never a model or hardware problem."
                ),
                .init(
                    symbol: "arrow.triangle.branch",
                    title: "The model picker now governs every mode",
                    detail: "On-Device, Hybrid, and Private Cloud Compute reached Standard correctly but were dropped in the two agentic modes. On-Device now applies to the entire query, including the final answer."
                ),
                .init(
                    symbol: "doc.badge.plus",
                    title: "Document import works on Mac",
                    detail: "The macOS file picker was a placeholder. It is now a native picker supporting the same formats as iOS."
                ),
                .init(
                    symbol: "gauge.with.dots.needle.33percent",
                    title: "Deep Think stops when it's finished",
                    detail: "Its internal confidence target couldn't be reached mathematically, so every query ran the maximum number of passes whether or not it was still learning anything."
                ),
            ]
        )
    ]
}
