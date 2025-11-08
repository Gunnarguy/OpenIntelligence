//
//  EventToasts.swift
//  OpenIntelligence
//
//  Lightweight ephemeral ribbon toasts for stage milestones.
//  Appears from the top and auto-dismisses.
//
//  Created by Cline on 10/29/25.
//

import SwiftUI

struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let tint: Color
}

struct EventToastView: View {
    let toast: ToastItem
    
    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: toast.icon)
                .font(.caption)
                .foregroundColor(toast.tint)
            Text(toast.title)
                .font(DSTypography.meta)
                .foregroundColor(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 8)
        .background(DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.chip)
                .stroke(toast.tint.opacity(0.25), lineWidth: 0.5)
        )
        .cornerRadius(DSCorners.chip)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(DSAnimations.fastEase, value: toast.id)
    }
}

struct ToastStackView: View {
    let items: [ToastItem]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(items) { t in
                EventToastView(toast: t)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .top) {
        DSColors.background.ignoresSafeArea()
        ToastStackView(items: [
            ToastItem(id: UUID(), title: "Embedding started", icon: "brain.head.profile", tint: DSColors.accent),
            ToastItem(id: UUID(), title: "Searching top 3", icon: "magnifyingglass", tint: .green),
            ToastItem(id: UUID(), title: "Generating…", icon: "sparkles", tint: DSColors.accent)
        ])
    }
}
