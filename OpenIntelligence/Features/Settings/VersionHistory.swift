//
//  VersionHistory.swift
//  OpenIntelligence
//
//  Parses the shipped user-facing changelog into a browsable release history.
//

import Foundation

/// One release, as read from the bundled changelog.
struct VersionHistoryRelease: Identifiable {
    struct Item: Identifiable {
        let id = UUID()
        /// Lead sentence. The bolded part of a `*   **Title.** Detail` bullet, or the
        /// whole bullet when it has no bold lead.
        let title: String
        /// Remainder of the bullet, if any.
        let detail: String?
    }

    struct Section: Identifiable {
        let id = UUID()
        /// `### Heading`, or `nil` for bullets that appear before any subheading.
        let heading: String?
        var items: [Item]
    }

    let id = UUID()
    /// "5.0", "4.5.1", or the raw heading text when it does not start with a version.
    let version: String
    /// "August 10, 2026", "June 2026", or `nil` when the heading carries no date.
    let date: String?
    /// The single line under the heading that summarises the release.
    let summary: String?
    var sections: [Section]
}

/// Reads `VersionHistory.md` out of the app bundle and turns it into releases.
///
/// The bundled file is a copy of `Docs/USER_CHANGELOG.md`, which is the file the repo
/// already requires to be updated whenever user-visible behaviour changes. Rendering that
/// rather than hand-maintaining a second list in Swift means the in-app history cannot
/// fall behind the written one — and `VersionHistoryFixtureTests` fails the build if the
/// two copies ever diverge.
///
/// The parser is deliberately narrow. It recognises exactly the shapes that file actually
/// uses, counted across all eleven releases: `## vX.Y - Date` headings, `### Subheading`,
/// `*   **Bold lead.** Remainder` bullets (119 of them), plain `*   ` bullets (about 19),
/// and `> ` notes. Anything else is skipped rather than guessed at, so an unfamiliar line
/// degrades to a missing bullet instead of a mangled one.
enum VersionHistoryLoader {
    static func load(bundle: Bundle = .main) -> [VersionHistoryRelease] {
        guard
            let url = bundle.url(forResource: "VersionHistory", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return parse(text)
    }

    static func parse(_ markdown: String) -> [VersionHistoryRelease] {
        var releases: [VersionHistoryRelease] = []

        var version: String?
        var date: String?
        var summary: String?
        var sections: [VersionHistoryRelease.Section] = []
        var currentHeading: String?
        var currentItems: [VersionHistoryRelease.Item] = []
        var awaitingSummary = false

        func closeSection() {
            guard !currentItems.isEmpty || currentHeading != nil else { return }
            guard !currentItems.isEmpty else {
                currentHeading = nil
                return
            }
            sections.append(.init(heading: currentHeading, items: currentItems))
            currentItems = []
            currentHeading = nil
        }

        func closeRelease() {
            closeSection()
            guard let version else { return }
            releases.append(
                .init(version: version, date: date, summary: summary, sections: sections)
            )
            sections = []
            summary = nil
            date = nil
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## ") {
                closeRelease()
                let heading = String(line.dropFirst(3))
                (version, date) = splitHeading(heading)
                awaitingSummary = true
                continue
            }

            // Everything before the first release heading is the file's own title and
            // documentation-status banner, which is not user-facing content.
            guard version != nil else { continue }

            if line.hasPrefix("### ") {
                closeSection()
                currentHeading = String(line.dropFirst(4))
                awaitingSummary = false
                continue
            }

            if line.hasPrefix("*   ") || line.hasPrefix("- ") {
                awaitingSummary = false
                let body = line.hasPrefix("*   ")
                    ? String(line.dropFirst(4))
                    : String(line.dropFirst(2))
                if let item = parseBullet(body) {
                    currentItems.append(item)
                }
                continue
            }

            if line.hasPrefix(">") {
                // Callouts read as ordinary guidance once the quote marker is gone.
                awaitingSummary = false
                let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty {
                    currentItems.append(.init(title: stripEmphasis(body), detail: nil))
                }
                continue
            }

            if line.isEmpty || line.hasPrefix("---") || line.hasPrefix("# ") {
                continue
            }

            // A bare paragraph directly under a version heading is that release's summary.
            if awaitingSummary {
                summary = stripEmphasis(line)
                awaitingSummary = false
            }
        }

        closeRelease()
        return releases
    }

    /// Splits `v5.0 - August 10, 2026` into its version and date.
    private static func splitHeading(_ heading: String) -> (String, String?) {
        let parts = heading.components(separatedBy: " - ")
        let rawVersion = parts[0].trimmingCharacters(in: .whitespaces)
        let version = rawVersion.hasPrefix("v") ? String(rawVersion.dropFirst()) : rawVersion
        let date = parts.count > 1
            ? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            : nil
        return (version, date)
    }

    /// Turns `**Lead sentence.** Remainder` into a title and a detail.
    private static func parseBullet(_ body: String) -> VersionHistoryRelease.Item? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.hasPrefix("**"), let closing = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2) ..< trimmed.endIndex) else {
            return .init(title: stripEmphasis(trimmed), detail: nil)
        }

        let title = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2) ..< closing.lowerBound])
        let remainder = String(trimmed[closing.upperBound...]).trimmingCharacters(in: .whitespaces)
        return .init(
            title: stripEmphasis(title),
            detail: remainder.isEmpty ? nil : stripEmphasis(remainder)
        )
    }

    /// Removes the inline markers this file uses. Rendering happens through styled
    /// `Text`, so the markers themselves must not survive into the label.
    private static func stripEmphasis(_ value: String) -> String {
        value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
