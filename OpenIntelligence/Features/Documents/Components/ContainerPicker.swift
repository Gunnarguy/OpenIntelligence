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
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pillList
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pillList
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var pillList: some View {
        ForEach(containerService.containers) { container in
            ContainerPill(
                container: container,
                isSelected: containerService.activeContainerId == container.id,
                canDelete: onDeleteLibrary != nil && containerService.containers.count > 1,
                badgeText: documentCountText(for: container),
                badgeStyle: .count,
                onSelect: {
                    withAnimation {
                        containerService.setActive(container.id)
                    }
                },
                onSetLibraryStorage: { syncMode in
                    onSetLibraryStorage?(container, syncMode)
                },
                onDelete: onDeleteLibrary.map { deleteLibrary in
                    {
                        deleteLibrary(container)
                    }
                }
            )
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
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: container.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(badgeStyle.background(isSelected: isSelected))
                        .foregroundStyle(badgeStyle.foreground(isSelected: isSelected))
                        .clipShape(Capsule())
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
        }
        .buttonStyle(.plain)
        .glassEffectHelper(isSelected: isSelected, tintColor: containerColor)
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
