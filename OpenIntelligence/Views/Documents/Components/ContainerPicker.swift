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
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(containerService.containers) { container in
                    ContainerPill(
                        container: container,
                        isSelected: containerService.activeContainerId == container.id
                    ) {
                        withAnimation {
                            containerService.setActive(container.id)
                        }
                    }
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
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
                    .fill(isSelected ? Color.accentColor : DSColors.surface)
            )
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
    }
}
