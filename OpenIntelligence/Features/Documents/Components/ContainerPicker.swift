//
//  ContainerPicker.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

enum ContainerPillBadgeStyle {
    case count
    case local
    case iCloud

    func foreground(isSelected: Bool) -> Color {
        switch self {
        case .count:
            return isSelected ? .white.opacity(0.92) : .secondary
        case .local:
            return isSelected ? .white.opacity(0.95) : .secondary
        case .iCloud:
            return isSelected ? .white.opacity(0.95) : .blue
        }
    }

    func background(isSelected: Bool) -> Color {
        switch self {
        case .count:
            return isSelected ? .white.opacity(0.2) : Color.secondary.opacity(0.14)
        case .local:
            return isSelected ? .white.opacity(0.16) : Color.secondary.opacity(0.12)
        case .iCloud:
            return isSelected ? .white.opacity(0.16) : Color.blue.opacity(0.12)
        }
    }
}

struct ContainerPickerStrip: View {
    @ObservedObject var containerService: ContainerService
    var allowsCreation: Bool = false
    var onCreateLibrary: (() -> Void)? = nil
    var onDeleteLibrary: ((KnowledgeContainer) -> Void)?
    var onSetLibraryStorage: ((KnowledgeContainer, LibrarySyncMode) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        pillList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    pillList
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    /// Names shared by more than one library, so those chips can be told apart.
    ///
    /// Duplicates are reachable: the suggested name is positional, so deleting a middle library
    /// frees its number for the next one, and nothing validates the name a user types.
    /// Cross-device they are unavoidable by design, because `WorkspaceSyncService` keys library
    /// identity on the UUID precisely so that two libraries called the same thing stay separate.
    /// So this cannot be prevented at the model layer without merging libraries that are not the
    /// same library, and it is solved where it is actually a problem, on screen.
    private var duplicatedNames: Set<String> {
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for container in containerService.containers {
            let key = container.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seen.insert(key).inserted { duplicated.insert(key) }
        }
        return duplicated
    }

    private func disambiguatedName(for container: KnowledgeContainer) -> String {
        let key = container.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard duplicatedNames.contains(key) else { return container.name }
        // The first four characters of the id, which is the same value sync uses to tell these
        // two apart, so the label matches the thing that actually distinguishes them.
        let suffix = container.id.uuidString.prefix(4)
        return "\(container.name) (\(suffix))"
    }

    @ViewBuilder
    private var pillList: some View {
        ForEach(containerService.containers) { container in
            ContainerPill(
                container: container,
                displayName: disambiguatedName(for: container),
                isSelected: containerService.activeContainerId == container.id,
                canDelete: onDeleteLibrary != nil && containerService.containers.count > 1,
                badgeText: documentCountText(for: container),
                badgeStyle: .count,
                onSelect: {
                    withAnimation {
                        containerService.setActive(container.id)
                    }
                },
                // `.map`, matching `onDelete` directly below, so a nil callback stays nil.
                //
                // This was an unconditional closure literal, which is never nil, so the
                // storage actions appeared on every screen that shows these chips. In Semantic
                // Search, which passes no callbacks at all, that meant "Make Local Only" and
                // "Make iCloud Sync" were visible and silently did nothing. The nil-ness is now
                // read directly by the context menu, which omits the whole section.
                onSetLibraryStorage: onSetLibraryStorage.map { setStorage in
                    { syncMode in
                        setStorage(container, syncMode)
                    }
                },
                onDelete: onDeleteLibrary.map { deleteLibrary in
                    {
                        deleteLibrary(container)
                    }
                }
            )
            .fixedSize(horizontal: true, vertical: false)
        }

        if allowsCreation {
            Button {
                onCreateLibrary?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Library")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .glassEffectHelper(isSelected: false, tintColor: .secondary)
        }
    }

    private func documentCountText(for container: KnowledgeContainer) -> String? {
        let count = containerService.documentCount(for: container.id)
        return count > 0 ? "\(count)" : nil
    }
}

struct ContainerPill: View {
    let container: KnowledgeContainer
    /// What to show on the chip. Defaults to the library's own name; `ContainerPickerStrip`
    /// passes a disambiguated form when two libraries share a name, which is reachable both on
    /// one device and across synced devices.
    var displayName: String? = nil
    let isSelected: Bool
    var canDelete: Bool = true
    var badgeText: String? = nil
    var badgeStyle: ContainerPillBadgeStyle = .local
    let onSelect: () -> Void
    var onSetLibraryStorage: ((LibrarySyncMode) -> Void)? = nil
    var onDelete: (() -> Void)?

    /// The container's custom color, or accent color as fallback
    private var containerColor: Color {
        Color(hex: container.colorHex) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: container.icon)
                .font(.system(size: 11, weight: .medium))
            Text(displayName ?? container.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(badgeStyle.background(isSelected: isSelected))
                    .foregroundStyle(badgeStyle.foreground(isSelected: isSelected))
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isSelected ? containerColor : DSColors.surface)
        )
        .foregroundColor(isSelected ? .white : .primary)
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.clear : containerColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: isSelected ? containerColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        .contentShape(Capsule())
        .onTapGesture {
            onSelect()
        }
        .glassEffectHelper(isSelected: isSelected, tintColor: containerColor, interactive: true)
        // Press-and-hold is `.contextMenu`, not a manual `onLongPressGesture` plus a
        // confirmation dialog, and that is a behaviour fix rather than a style preference.
        //
        // These chips live in a horizontal ScrollView. An `onLongPressGesture` there competes
        // directly with the scroll pan: UIKit has no way to arbitrate a SwiftUI long-press
        // against its own gesture recogniser, so a press that drifts a few points either
        // scrolls or opens the dialog, unpredictably, with no press affordance to say which is
        // happening. `.contextMenu` is arbitrated by UIKit itself, so scrolling always wins
        // until the press resolves, and it brings the preview, the threshold haptic and the
        // standard animation for free.
        //
        // Interactive glass was previously switched off whenever the chip had actions
        // (`interactive: !hasLibraryActions`), which disabled the pressure response on exactly
        // the chips a user needs to press. It was presumably suppressing a visual clash with
        // the manual gesture; with the gesture gone the suppression goes too.
        //
        // This block was already the macCatalyst implementation. It is now the only one, so
        // both platforms present the same actions in the same order.
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Select Library", systemImage: "checkmark.circle")
            }

            if let onSetLibraryStorage {
                Divider()

                Button {
                    onSetLibraryStorage(.localOnly)
                } label: {
                    Label(
                        container.syncMode == .localOnly ? "Local Only (Current)" : "Make Local Only",
                        systemImage: container.syncMode == .localOnly ? "checkmark.circle.fill" : "lock.fill"
                    )
                }

                Button {
                    onSetLibraryStorage(.iCloudShared)
                } label: {
                    Label(
                        container.syncMode == .iCloudShared ? "iCloud Sync (Current)" : "Make iCloud Sync",
                        systemImage: container.syncMode == .iCloudShared ? "checkmark.circle.fill" : "icloud.fill"
                    )
                }
            }

            if canDelete {
                Divider()

                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete Library", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    ContainerPickerStrip(containerService: ContainerService())
        .padding()
}
