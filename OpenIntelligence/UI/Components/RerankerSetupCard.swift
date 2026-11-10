//
//  RerankerSetupCard.swift
//  OpenIntelligence
//
//  The one-time "Setting up search" card, shown on every tab while the reranker compiles for the Neural Engine.
//

import SwiftUI

/// Floats at the top of every tab while `RerankerSetupStatus` says the reranker is being prepared: the first launch
/// after an install or an update, about 45 s on an iPhone 16 Pro Max (2026-11-09). It says what is happening, that it
/// happens once, and what it means for a question asked now; its bar estimates the time against
/// `RerankerSetupStatus.expectedSeconds` and stops short of the end until the load really finishes. When it does, the
/// card reads "Search is ready" for a moment and goes. Styled as the setup checklist's launcher is (material, sheet
/// corners, border hairline), so it reads as the app's own.
struct RerankerSetupCard: View {
    @ObservedObject private var status = RerankerSetupStatus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if status.isPreparing {
                card(ready: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if status.justFinished {
                card(ready: true)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: status.isPreparing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: status.justFinished)
    }

    private func card(ready: Bool) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            Image(systemName: ready ? "checkmark.circle.fill" : "sparkle.magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ready ? DSColors.success : DSColors.accent)
                .symbolEffect(.pulse, isActive: !ready && !reduceMotion)
                .frame(width: DSSpacing.xl)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(ready ? "Search is ready" : "Setting up search")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !ready {
                    Text("Once after an update, about a minute. A question asked now waits for it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        ProgressView(
                            value: RerankerSetupStatus.estimatedProgress(startedAt: status.startedAt, now: context.date)
                        )
                        .tint(DSColors.accent)
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: context.date)
                    }
                    .padding(.top, DSSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .stroke(DSColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        .padding(.horizontal, DSSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ready
                ? "Search is ready"
                : "Setting up search. This happens once after an update and takes about a minute. A question asked now waits for it."
        )
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    VStack { RerankerSetupCard() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.secondary.opacity(0.1))
}
