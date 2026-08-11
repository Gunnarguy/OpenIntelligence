//
//  VersionHistoryView.swift
//  OpenIntelligence
//
//  Every shipped release, browsable from Settings.
//

import SwiftUI

/// The full release history, read from the bundled changelog.
///
/// Deliberately reachable rather than interruptive. The post-update sheet still fires only
/// for people who actually updated and stays silent on a fresh install, because a list of
/// fixes to problems you never hit is noise on day one and competes with onboarding for
/// the same moment. Someone weighing up whether the app is maintained goes looking for
/// this instead, and eleven dated releases answer that better than a popup would.
///
/// Rows use the same shape as `WhatsNewView`: bold lead sentence, secondary detail
/// beneath. One format, one source, so the history cannot drift from the changelog.
struct VersionHistoryView: View {
    @State private var releases: [VersionHistoryRelease] = []
    @State private var expanded: Set<UUID> = []

    var body: some View {
        List {
            if releases.isEmpty {
                ContentUnavailableView(
                    "No release history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("The changelog could not be read from this build.")
                )
            } else {
                ForEach(releases) { release in
                    Section {
                        if expanded.contains(release.id) {
                            ForEach(release.sections) { section in
                                if let heading = section.heading {
                                    Text(heading)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .listRowSeparator(.hidden)
                                }
                                ForEach(section.items) { item in
                                    itemRow(item)
                                }
                            }
                        }
                    } header: {
                        releaseHeader(release)
                    }
                }
            }
        }
        .navigationTitle("Version History")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard releases.isEmpty else { return }
            let loaded = VersionHistoryLoader.load()
            releases = loaded
            // Open the newest release only. Eleven expanded releases is a wall of text,
            // and the one people came to read is almost always the most recent.
            if let newest = loaded.first {
                expanded = [newest.id]
            }
        }
    }

    private func releaseHeader(_ release: VersionHistoryRelease) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expanded.contains(release.id) {
                    expanded.remove(release.id)
                } else {
                    expanded.insert(release.id)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(release.version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColors.primaryText)
                    if let date = release.date {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = release.summary, expanded.contains(release.id) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: DSSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(release.id) ? 90 : 0))
            }
            .padding(.vertical, DSSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("Version \(release.version)\(release.date.map { ", \($0)" } ?? "")")
        .accessibilityHint(expanded.contains(release.id) ? "Collapse" : "Expand")
    }

    private func itemRow(_ item: VersionHistoryRelease.Item) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(DSColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = item.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
