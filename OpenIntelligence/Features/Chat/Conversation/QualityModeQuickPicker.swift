//
//  QualityModeQuickPicker.swift
//  OpenIntelligence
//
//  Moved unchanged from ChatScreen.swift on 2026-11-05 (5.8 split).
//

import AppIntents
import Combine
import Foundation
import StoreKit
import SwiftUI
import TipKit
import Translation

#if os(iOS)
    import PDFKit
    import VisionKit
#endif

/// Quick picker for quality mode - shows in chat header
/// Dropdown menu to switch between Standard and Deep Think
struct QualityModeQuickPicker: View {
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Binding var selectedMode: RAGQualityMode
    var onMaximumModeBlocked: (() -> Void)? = nil
    /// Called when mode changes, passing old and new mode
    var onModeChange: ((RAGQualityMode, RAGQualityMode) -> Void)?

    var body: some View {
        Menu {
            ForEach(RAGQualityMode.userVisibleCases, id: \.id) { mode in
                Button {
                    guard canSelect(mode) else { return }
                    let previousMode = selectedMode
                    withAnimation(DSAnimations.snappySpring) {
                        selectedMode = mode
                    }
                    DSHaptics.selection()

                    // Notify parent to reset stale metrics when mode changes
                    if previousMode.canonical != mode.canonical {
                        onModeChange?(previousMode, mode)
                    }
                } label: {
                    // A native menu row on this OS renders a title and an icon, and
                    // nothing else. `RAGQualityMode.description` cannot be shown here.
                    //
                    // The original code nested a `VStack` of two `Text`s in the `Label`'s
                    // title slot, so the rows read "Standard", "Deep Think", "Maximum"
                    // and nothing more, and every `description` string was dead copy.
                    // Two documented subtitle forms were then tried and photographed on
                    // iPhone 17 Pro / iOS 27, and neither rendered: three siblings
                    // (`Text`/`Text`/`Image`), and a `Label` with a sibling subtitle
                    // `Text`. SwiftUI mirrors a menu button's label to extract the parts,
                    // and iOS 26 changed that component's behaviour.
                    //
                    // So the distinction goes in the title, which does render. The full
                    // descriptions still reach users in Settings -> Intelligence Mode,
                    // where all three are shown in full alongside their capability lists.
                    // Do not reintroduce a subtitle `Text` here without photographing the
                    // open menu first.
                    Label(menuTitle(for: mode), systemImage: isActive(mode) ? "checkmark" : mode.icon)
                }
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(modeColor.opacity(0.14))
                        .frame(width: 20, height: 20)
                    Image(systemName: selectedMode.canonical.icon)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(modeColor)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedMode.canonical.displayName)
                        .font(.caption.weight(.semibold))
                    Text(modeTagline)
                        .font(.caption2)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            // The words in the label color, the mode's color in the icon and the tint (5.7, the owner's choice). Blue
            // on the blue-tinted chip measured 3.6 to 1 even in Apple's high-contrast blue; Apple asks for 4.5.
            .foregroundStyle(DSColors.primaryText)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            // Shared shape and material with the model pill beside it. These two sat
            // next to each other as a tinted Capsule and an untinted
            // RoundedRectangle(8) with different padding, which is the single most
            // visible styling mismatch on the primary screen.
            //
            // The tint is applied here rather than through `glassEffectHelper`, whose
            // `isSelected: true` path tints at full strength — on a red or blue status
            // that produces a solid, shouting capsule. These are ambient status
            // indicators, so the colour belongs mostly in the content.
            .glassEffect(.regular.tint(modeColor.opacity(0.18)).interactive(), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Answer quality")
        .accessibilityValue("\(selectedMode.canonical.displayName), \(modeTagline)")
        .accessibilityHint("Choose how much reasoning to spend on each question")
    }

    private func isActive(_ mode: RAGQualityMode) -> Bool {
        selectedMode.canonical == mode.canonical
    }

    /// Title for a row in the open menu, carrying the one-word distinction the row
    /// cannot show as a subtitle.
    ///
    /// Maximum is gated by billing rather than by hardware, and the only signal for that
    /// used to be the 8pt tagline on the *collapsed* pill — visible after the mode is
    /// already selected, so a user out of runs learned about the limit by tapping and
    /// receiving a paywall. The row stays tappable on purpose, because the paywall is the
    /// useful destination, but it now says why beforehand.
    private func menuTitle(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard:
            return "Standard · Single pass"
        case .deepThink:
            return "Deep Think · Iterative"
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return "Maximum · Deepest search"
            }
            let remaining = entitlementStore.maximumModeRemainingUses
            return remaining <= 0
                ? "Maximum · Limit reached"
                : "Maximum · \(remaining) left today"
        default:
            return mode.displayName
        }
    }

    private var modeTagline: String {
        switch selectedMode.canonical {
        case .standard: return "Fastest"
        case .deepThink: return "Iterative"
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return "Unlimited"
            }
            return "\(entitlementStore.maximumModeRemainingUses) left"
        default: return "Fastest"
        }
    }

    private var modeColor: Color {
        switch selectedMode.canonical {
        case .standard: return .blue
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .blue
        }
    }

    private func canSelect(_ mode: RAGQualityMode) -> Bool {
        guard mode.canonical == .maximum else { return true }
        guard entitlementStore.canUseMaximumModeNow else {
            onMaximumModeBlocked?()
            return false
        }
        return true
    }
}
