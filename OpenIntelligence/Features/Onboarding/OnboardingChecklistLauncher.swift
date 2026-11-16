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
        // The pill and its close button are two pieces of glass side by side, so one container renders them together.
        GlassEffectContainer(spacing: DSSpacing.sm) {
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
                // Floats over every tab, so Liquid Glass, interactive since the whole pill is a button (5.8,
                // 2026-11-16; was `.ultraThinMaterial` with a drawn border and shadow).
                .glassEffect(
                    .regular.interactive(), in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open onboarding checklist")

            // Dismiss permanently button
            Button(action: onDismissPermanently) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: DSSpacing.tapTarget, minHeight: DSSpacing.tapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Dismiss setup checklist permanently")
        }
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
