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
    /// What is happening, when, how long, and what a question asked meanwhile does (5.8, reworded at the owner's word on
    /// 2026-11-10: "Once after an update, about a minute. A question asked now waits for it." read as ambiguous). "Up
    /// to a minute": the longest first load measured on his iPhone took 59.7 s.
    static let explanation = "Preparing search for this device's Neural Engine. This happens once after each update and takes up to a minute. You can still ask a question; it starts as soon as this is done."

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

    /// Drawn as the app's lit status panel (5.8, 2026-11-16, the owner: "I don't like how this looks"): the thin material
    /// let the tab's chips show through, the icon floated at mid-height, and the step line ran out of room ("longer than
    /// usual..."). Now a dark panel with the accent edge, a graphite icon tile at the title, the seconds as a figure, and
    /// one bar per step, each named, so nothing has to be cut.
    private func card(ready: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
        let tint = ready ? DSColors.success : DSColors.accent
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                iconTile(ready: ready, tint: tint)
                Text(ready ? "Search is ready" : "Getting search ready")
                    .font(DSTypography.title)
                    .foregroundStyle(.white)
                Spacer(minLength: DSSpacing.xs)
                if !ready {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(Int(max(0, context.date.timeIntervalSince(status.startedAt ?? context.date)))) s")
                            .font(DSTypography.figure)
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                    }
                }
            }
            if !ready {
                Text(Self.explanation)
                    .font(DSTypography.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let overall = RerankerSetupStatus.progress(
                        step: status.step, stepStartedAt: status.stepStartedAt, startedAt: status.startedAt,
                        now: context.date)
                    let seconds = max(0, context.date.timeIntervalSince(status.startedAt ?? context.date))
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack(spacing: DSSpacing.xs) {
                            stepBar("Short passages", fill: min(1, max(0, overall * 2)), current: status.step <= 1)
                            stepBar("Long passages", fill: min(1, max(0, overall * 2 - 1)), current: status.step == 2)
                        }
                        if seconds > RerankerSetupStatus.expectedSeconds + 10 {
                            Text("Taking longer than usual on this device.")
                                .font(DSTypography.meta)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    .animation(reduceMotion ? nil : .linear(duration: 0.5), value: overall)
                }
                .padding(.top, DSSpacing.xxs)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: 440)
        .background(
            ZStack {
                shape.fill(Color(white: 0.07))
                Canvas { context, size in
                    var path = Path()
                    stride(from: 0, through: size.height, by: 9).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 0.5)
                }
                .clipShape(shape)
            }
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [tint, tint.opacity(0.35)], startPoint: .leading, endPoint: .trailing),
                lineWidth: 1.2)
        )
        .shadow(color: tint.opacity(0.22), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 6)
        .padding(.horizontal, DSSpacing.lg)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ready
                ? "Search is ready"
                : "Getting search ready. \(Self.explanation)"
        )
        .accessibilityValue(
            ready ? "" : RerankerSetupStatus.stepLine(step: status.step, startedAt: status.startedAt, now: .now)
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The Settings rows' graphite tile, tinted at its edge by the card's colour.
    private func iconTile(ready: Bool, tint: Color) -> some View {
        let tile = RoundedRectangle(cornerRadius: DSCorners.control - 3, style: .continuous)
        return Image(systemName: ready ? "checkmark" : "sparkle.magnifyingglass")
            .scaledFont(size: 14, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(ready ? tint : .white)
            .symbolEffect(.pulse, isActive: !ready && !reduceMotion)
            .frame(width: 28, height: 28)
            .background(
                tile.fill(
                    LinearGradient(colors: [Color(white: 0.26), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(tile.strokeBorder(tint.opacity(0.5), lineWidth: 0.5))
    }

    /// One step's bar with its name under it: full when done, filling while it runs, empty before it starts.
    private func stepBar(_ name: String, fill: Double, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(DSColors.accent)
                        .frame(width: proxy.size.width * fill)
                        .shadow(color: DSColors.accent.opacity(current ? 0.6 : 0), radius: 4)
                }
            }
            .frame(height: 5)
            Text(name)
                .font(DSTypography.meta)
                .foregroundStyle(Color.white.opacity(fill >= 1 || current ? 0.8 : 0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack { RerankerSetupCard() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.secondary.opacity(0.1))
}
