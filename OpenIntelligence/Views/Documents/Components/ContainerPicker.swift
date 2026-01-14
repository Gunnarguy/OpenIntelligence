//
//  ContainerPicker.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct ContainerPickerStrip: View {
    @ObservedObject var containerService: ContainerService
    var allowsCreation: Bool = false
    var onCreateLibrary: (() -> Void)? = nil
    var onDeleteLibrary: ((KnowledgeContainer) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(containerService.containers) { container in
                    ContainerPill(
                        container: container,
                        isSelected: containerService.activeContainerId == container.id,
                        canDelete: containerService.containers.count > 1, // Can't delete last library
                            onSelect: {
                                withAnimation {
                                    containerService.setActive(container.id)
                                }
                        },
                        onDelete: {
                                onDeleteLibrary?(container)
                        }
                    )
                }

                if allowsCreation {
                    Button {
                        onCreateLibrary?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct ContainerPill: View {
    let container: KnowledgeContainer
    let isSelected: Bool
    var canDelete: Bool = true
    let onSelect: () -> Void
    var onDelete: (() -> Void)?

    /// The container's custom color, or accent color as fallback
    private var containerColor: Color {
        Color(hex: container.colorHex) ?? .accentColor
    }

    var body: some View {
        Button(action: onSelect) { 
            HStack(spacing: 6) {
                Image(systemName: container.icon)
                    .font(.caption)
                Text(container.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Select Library", systemImage: "checkmark.circle")
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
