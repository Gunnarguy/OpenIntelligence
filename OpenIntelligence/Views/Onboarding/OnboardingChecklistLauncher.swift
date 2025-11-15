import SwiftUI

/// Compact button that lets users reopen the onboarding checklist after dismissing it.
struct OnboardingChecklistLauncher: View {
    let completedSteps: Int
    let totalSteps: Int
    let action: () -> Void

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup checklist")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("\(completedSteps)/\(totalSteps) complete")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
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
        .accessibilityValue("\(completedSteps) of \(totalSteps) steps complete")
    }
}
