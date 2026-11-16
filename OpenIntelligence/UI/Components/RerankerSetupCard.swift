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
/// card reads "Search is ready" for a moment and goes. It floats over every tab, so it is regular Liquid Glass, as the
/// setup checklist's launcher and the import queue are (5.8, 2026-11-16).
struct RerankerSetupCard: View {
    /// What is happening, when, how long, and what a question asked meanwhile does (5.8, reworded at the owner's word on
    /// 2026-11-10: "Once after an update, about a minute. A question asked now waits for it." read as ambiguous). "Up
    /// to a minute": the longest first load measured on his iPhone took 59.7 s.
    ///
    /// Plain words (2026-11-16, the owner: nobody knew why "Preparing search for this device's Neural Engine" was
    /// there). What is true: 5.8 replaced the reranker, the model that re-reads the passages search finds and puts the
    /// best first, with IBM's Granite reranker, about ten times larger, and the Neural Engine compiles it once after an
    /// install or update, then loads it from its cache in about a second. The duration moved to the counter and the
    /// bars, which show it live; the two facts the owner fixed on 2026-11-10 stay: once after each update, and a question
    /// asked now starts as soon as this is done.
    ///
    /// Plainer again the same day (the owner: "its still preeeeetty ambiguous to people who dont know what that even
    /// means"): it says what the model does for an answer, that this device does it once after each update, roughly
    /// how long (75 to 83 s measured on an iPhone 16 Pro Max on 2026-11-16, 25 to 58 s earlier), and what asking now
    /// does. The device's own noun, so a Mac says Mac.
    static var explanation: String {
        // No version number: the card shows after every update, not only the one that brought the model.
        "Search uses a model that picks the best passages from your documents for each answer. "
            + "Your \(DeviceCapabilityService.shared.formFactor.deviceNoun) sets it up once after each update, which "
            + "takes a minute or two. You can ask now; the answer starts when it's ready."
    }

    @ObservedObject private var status = RerankerSetupStatus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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

    /// Since 2026-11-16 regular Liquid Glass, because it floats over content (Human Interface Guidelines, Materials), with
    /// text in the label colours. Before that it was drawn as the app's status panels are (5.8, 2026-11-16, the owner: "I don't like how this looks", then "make it all
    /// pastel"): the thin material let the tab's chips show through, the icon floated at mid-height, and the step line
    /// ran out of room ("longer than usual..."). Now a solid card that follows light and dark mode with a faint wash of
    /// its colour, a tinted icon tile at the title, the seconds as a figure, and one bar per step, each named.
    private func card(ready: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
        let tint = ready ? DSColors.success : DSColors.accent
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                iconTile(ready: ready, tint: tint)
                Text(ready ? "Search is ready" : "Getting search ready")
                    .font(DSTypography.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: DSSpacing.xs)
                if !ready {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(Int(max(0, context.date.timeIntervalSince(status.startedAt ?? context.date)))) s")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(DSColors.readable(tint))
                            .contentTransition(.numericText())
                    }
                }
            }
            if !ready {
                Text(Self.explanation)
                    .font(DSTypography.caption)
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(reduceMotion ? nil : .linear(duration: 0.5), value: overall)
                }
                .padding(.top, DSSpacing.xxs)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: shape)
        .padding(.horizontal, DSSpacing.lg)
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

    /// A soft tile of the card's colour behind its symbol.
    private func iconTile(ready: Bool, tint: Color) -> some View {
        let tile = RoundedRectangle(cornerRadius: DSCorners.control - 3, style: .continuous)
        return Image(systemName: ready ? "checkmark" : "sparkle.magnifyingglass")
            .scaledFont(size: 14, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(DSColors.readable(tint))
            .symbolEffect(.pulse, isActive: !ready && !reduceMotion)
            .frame(width: 30, height: 30)
            .background(tile.fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.14)))
    }

    /// One step's bar with its name under it: full when done, filling while it runs, empty before it starts.
    private func stepBar(_ name: String, fill: Double, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColors.accent.opacity(colorScheme == .dark ? 0.25 : 0.15))
                    Capsule()
                        .fill(DSColors.accent)
                        .frame(width: proxy.size.width * fill)
                }
            }
            .frame(height: 5)
            Text(name)
                .font(DSTypography.meta)
                .foregroundStyle(fill >= 1 || current ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
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
