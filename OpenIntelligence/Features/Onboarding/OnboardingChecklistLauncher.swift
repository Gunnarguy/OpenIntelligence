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
        HStack(alignment: .top, spacing: 8) {
            // Main launcher button
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup checklist")
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Text("Tap to continue setup")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
                .accessibilityLabel("Open onboarding checklist")

            // Dismiss permanently button
            Button(action: onDismissPermanently) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.secondary)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 32, height: 32)
                    )
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
