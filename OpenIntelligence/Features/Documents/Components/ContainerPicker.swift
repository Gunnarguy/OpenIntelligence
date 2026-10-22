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

    /// White on a darker circle on a selected chip, and the label color on the tint otherwise (5.7): a count in 92%
    /// white on a lighter circle of the chip's color, and gray on a gray tint, measured under 4.5 to 1.
    func foreground(isSelected: Bool) -> Color {
        isSelected ? .white : DSColors.primaryText
    }

    func background(isSelected: Bool) -> Color {
        switch self {
        case .count:
            return isSelected ? .black.opacity(0.18) : Color.secondary.opacity(0.14)
        case .local:
            return isSelected ? .black.opacity(0.18) : Color.secondary.opacity(0.12)
        case .iCloud:
            return isSelected ? .black.opacity(0.18) : Color.accentColor.opacity(0.12)
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
                GlassEffectContainer(spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        pillList
                    }
                    .modifier(LibraryReordering(containerService: containerService))
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
            } else {
                HStack(spacing: DSSpacing.sm) {
                    pillList
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
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
        // A chip can be dragged to put the libraries in another order on iOS and macOS 27 (5.7).
        if #available(iOS 27.0, macOS 27.0, *) {
            pills.reorderable()
        } else {
            pills
        }
        creationButton
    }

    private var pills: some DynamicViewContent {
        // The libraries a Focus filter allows while its Focus is on, otherwise all (5.7).
        ForEach(containerService.pickableContainers) { container in
            ContainerPill(
                container: container,
                displayName: disambiguatedName(for: container),
                isSelected: containerService.activeContainerId == container.id,
                canDelete: onDeleteLibrary != nil && containerService.containers.count > 1,
                badgeText: documentCountText(for: container),
                badgeStyle: .count,
                onSelect: {
                    // Marks the tap so the switch can be reported as an interval rather
                    // than as a feeling. Switching libraries is the specific complaint,
                    // and until now nothing on this path was timed at all.
                    NavigationTiming.begin("library")
                    withAnimation(DSAnimations.snappySpring) {
                        containerService.setActive(container.id)
                    }
                    SiriDonations.libraryUsed(container)
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
    }

    @ViewBuilder
    private var creationButton: some View {
        if allowsCreation {
            Button {
                onCreateLibrary?()
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.semibold))
                    Text("New Library")
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
                .background(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
                .foregroundStyle(DSColors.secondaryText)
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

    /// The badge as VoiceOver reads it: a count as documents, other badges as they are written.
    private var accessibilityBadge: String {
        guard let badgeText else { return "" }
        guard case .count = badgeStyle, let count = Int(badgeText) else { return badgeText }
        return count == 1 ? "1 document" : "\(count) documents"
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: container.icon)
                .font(.caption2.weight(.medium))
            Text(displayName ?? container.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
            if let badgeText {
                Text(badgeText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(badgeStyle.background(isSelected: isSelected))
                    .foregroundStyle(badgeStyle.foreground(isSelected: isSelected))
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(isSelected ? containerColor : DSColors.surface)
        )
        .foregroundStyle(isSelected ? .white : .primary)
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.clear : containerColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: isSelected ? containerColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        .contentShape(Capsule())
        .onTapGesture {
            onSelect()
        }
        // One element for VoiceOver, read as a button: the library's name, its document count and whether
        // it is the active library. Its icon and its name were two small elements with no button trait,
        // and the icon read "Move", the folder symbol's own label (5.7, accessibility audit).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName ?? container.name)
        .accessibilityValue(accessibilityBadge)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
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
        //
        // The menu goes on before the glass (5.7). With `glassEffect` applied outside `.contextMenu`, interactive or
        // not, a long press opened nothing: measured 2026-10-19 in the iOS 27.0 Simulator with a probe app, where the
        // same chip without the glass, or with the menu applied first, opened its menu, and still reordered.
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Select Library", systemImage: "checkmark.circle")
            }

            // A link that opens this library in OpenIntelligence, as a document's Copy Link does (5.7).
            Button {
                SystemClipboard.copy(AppLink.webURL(for: .library(container.id)).absoluteString)
            } label: {
                Label("Copy Link", systemImage: "link")
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
        // One `glassEffect` with the glass picked by value, not `glassEffectHelper`, whose `if`s make the chip a
        // different view in each state (5.7). A chip is a reorderable row on iOS and macOS 27, and when a view-builder
        // branch, an `if #available` or an `AnyView` holds all of a row's content, even under other modifiers such as
        // the `contextMenu` above, SwiftUI starts the drag with no id for it and stops the app in `DragContainerStorage.payload(for:)` ("Unexpected identifier type. Expected UUID, got
        // UUID": its cast of the dragged id fails because the id is nil). Measured 2026-10-19 in the iOS 27.0
        // Simulator with a probe app: each of those around the chip crashed the drag, and one glass call, a branch
        // around the count alone, or one around the name alone reordered the chips.
        .glassEffect(isSelected ? .regular.tint(containerColor).interactive() : .regular.interactive(), in: Capsule())
    }
}

#Preview {
    ContainerPickerStrip(containerService: ContainerService())
        .padding()
}

/// Applies a dragged chip's new place to the library list, on iOS and macOS 27, where SwiftUI's
/// `reorderContainer` reports a drag as the dragged ids and the chip they were dropped before
/// (5.7). Before 27 the chips do not move.
///
/// Two things stop the drag working, both found on iOS 27.0 on 2026-10-19. A view-builder branch, an `if #available`
/// or an `AnyView` that holds all of a chip's content, even under other modifiers, starts the drag with no id and
/// stops the app (`ContainerPill`). A drop target around this row makes a drag report the chip's own place, so no
/// library moves (`DocumentLibraryView.takingDroppedFiles(as:)`). Keep both off the chips and off every screen that
/// shows the row.
private struct LibraryReordering: ViewModifier {
    let containerService: ContainerService

    func body(content: Content) -> some View {
        if #available(iOS 27.0, macOS 27.0, *) {
            content.reorderContainer(for: KnowledgeContainer.self) { difference in
                let target: UUID?
                if case .before(let id) = difference.destination.position {
                    target = id
                } else {
                    target = nil
                }
                withAnimation(DSAnimations.snappySpring) {
                    containerService.move(difference.sources, before: target)
                }
            }
        } else {
            content
        }
    }
}
