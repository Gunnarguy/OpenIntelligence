import SwiftUI

/// Compact button that lets users reopen the onboarding checklist after dismissing it.
/// Includes a dismiss button to permanently hide the launcher.
struct OnboardingChecklistLauncher: View {
    let completedSteps: Int
    let totalSteps: Int
    let action: () -> Void
    let onDismissPermanently: () -> Void

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            // Main launcher button
            Button(action: action) {
                HStack(spacing: DSSpacing.md) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Setup checklist")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Tap to continue setup")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DSColors.accent)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                        // Was `Color.white.opacity(0.15)`, which is very nearly invisible on a
                        // light background: the pill sits on `.ultraThinMaterial` over whatever
                        // is behind it, so a white hairline only reads against a dark one.
                        .stroke(DSColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
            .accessibilityLabel("Open onboarding checklist")

            // Dismiss permanently button
            Button(action: onDismissPermanently) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: DSSpacing.xxl, height: DSSpacing.xxl)
                    )
                    .frame(minWidth: DSSpacing.tapTarget, minHeight: DSSpacing.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss setup checklist permanently")
        }
    }
}

#Preview {
    OnboardingChecklistLauncher(
        completedSteps: 2,
        totalSteps: 4,
        action: {},
        onDismissPermanently: {}
    )
    .padding()
    .background(Color.secondary.opacity(0.1))
}
