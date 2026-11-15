//
//  WatchedFolderRow.swift
//  OpenIntelligence
//
//  The watched folder on the Documents page itself (5.8). Until this it was reachable only inside Library
//  Settings, three sections down, so a person who never opened that sheet never learned it exists.
//

import SwiftUI

/// A folder with an eye in it. SF Symbols has no folder-and-eye symbol in iOS 27 or macOS 27 (`folder.badge.eye`
/// and `eye.folder` both resolve to nothing, checked 2026-11-14), so this sets the system `eye.fill` inside the
/// system `folder`, both scaled by the font the caller gives.
struct WatchedFolderGlyph: View {
    var body: some View {
        Image(systemName: "folder")
            .overlay {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .bold))
                    .offset(y: 2)
            }
            .accessibilityHidden(true)
    }
}

/// One row under the Documents page's buttons: what the library's watched folder is doing, or an offer to pick one.
struct WatchedFolderRow: View {
    let library: KnowledgeContainer?
    let hasAccess: Bool
    let action: () -> Void

    @ObservedObject private var watcher = WatchedFolderService.shared

    private var folder: WatchedFolder? { watcher.folder(forLibrary: library?.id) }

    var body: some View {
        Button(action: action) {
            // One line, the height of a chip (the owner, 2026-11-14: the two-line card was too big for what it is).
            HStack(spacing: DSSpacing.sm) {
                WatchedFolderGlyph()
                    .font(.body)
                    .foregroundStyle(folder == nil ? DSColors.secondaryText : Color.accentColor)
                Text(folder.map { "Watching \($0.name)" } ?? "Watch a Folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                detail
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if folder == nil, !hasAccess {
                    Text("Pro")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DSColors.secondaryText)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs + DSSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface.opacity(0.6))
            )
            .contentShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchedFolderRow")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the watched folder for this library")
    }

    @ViewBuilder private var detail: some View {
        if let folder {
            if watcher.isChecking {
                Text("Checking for new files")
            } else if let checked = folder.lastCheckedAt {
                // `Text(_, style: .relative)` keeps counting by itself, so the row never shows a stale time.
                Text("Checked \(Text(checked, style: .relative)) ago")
            } else {
                Text("Not checked yet")
            }
        } else {
            Text("imports new files by itself")
        }
    }
}

/// The watched folder by itself, opened from the Documents page's row. The same section Library Settings shows.
struct WatchedFolderSheet: View {
    let library: KnowledgeContainer?
    @ObservedObject var ragService: RAGService
    let hasAccess: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showingPlans = false

    var body: some View {
        #if os(macOS)
            // A Mac sheet: the grouped form macOS settings use, a title in the sheet and Done at the bottom. As a
            // `NavigationStack` with an iOS form it came up with an empty band above its title and unpadded text
            // at the sheet's edge (the owner's screenshot, 2026-11-14).
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DSSpacing.sm) {
                    WatchedFolderGlyph()
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    Text("Watched Folder")
                        .font(.title3.weight(.semibold))
                }
                .padding([.horizontal, .top], DSSpacing.xl)
                Form { section }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding([.horizontal, .bottom], DSSpacing.xl)
            }
            .frame(minWidth: 480, idealWidth: 520, maxWidth: 620, minHeight: 320)
            .sheet(isPresented: $showingPlans) {
                PlanUpgradeSheet(entryPoint: .watchedFolder)
            }
        #else
            NavigationStack {
                Form { section }
                    .navigationTitle("Watched Folder")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                    .sheet(isPresented: $showingPlans) {
                        PlanUpgradeSheet(entryPoint: .watchedFolder)
                    }
            }
        #endif
    }

    private var section: some View {
        WatchedFolderSection(
            library: library,
            ragService: ragService,
            hasAccess: hasAccess,
            showPlans: { showingPlans = true }
        )
    }
}
