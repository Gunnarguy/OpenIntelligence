import SwiftUI

struct CloudConsentPromptView: View {
    let record: CloudTransmissionRecord
    let onDecision: (CloudConsentDecision) -> Void

    @State private var showDetails = false

    private var isPrewarm: Bool {
        record.promptCharacterCount == 0 && record.contextChunkCount == 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            VStack(spacing: DSSpacing.lg) {
                // Icon and Title
                headerSection
                    .padding(.top, 8)  // Extra padding to prevent cloud icon clipping

                // Simple explanation
                explanationSection

                // Expandable details (collapsed by default)
                if showDetails {
                    detailsSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Action buttons
                buttonsSection
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xl)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .animation(.spring(response: 0.3), value: showDetails)
    }

    private var headerSection: some View {
        VStack(spacing: DSSpacing.sm) {
            // Apple-style cloud icon with shield
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("Private Cloud Compute")
                .font(.title2.weight(.semibold))

            Text(isPrewarm ? "Enable Apple's secure cloud processing" : "Request requires cloud processing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ConsentFeatureRow(
                icon: "lock.shield.fill",
                iconColor: .green,
                title: "End-to-end encrypted",
                subtitle: "Your data is never stored"
            )

            ConsentFeatureRow(
                icon: "server.rack",
                iconColor: .blue,
                title: "Apple Silicon servers",
                subtitle: "Same security as your device"
            )

            ConsentFeatureRow(
                icon: "eye.slash.fill",
                iconColor: .purple,
                title: "No data retention",
                subtitle: "Deleted after processing"
            )
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ConsentDetailRow(label: "Provider", value: record.provider.displayName)
            ConsentDetailRow(label: "Model", value: record.modelName)
            if record.promptCharacterCount > 0 {
                ConsentDetailRow(label: "Prompt", value: "\(record.promptCharacterCount) chars")
            }
            if record.contextChunkCount > 0 {
                ConsentDetailRow(label: "Context", value: "\(record.contextChunkCount) chunks")
            }
        }
        .font(.footnote)
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var buttonsSection: some View {
        VStack(spacing: DSSpacing.sm) {
            // Primary action: Always Allow (permanent)
            Button {
                DSHaptics.success()
                onDecision(.allowAndRemember)
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Always Allow")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            // Secondary actions row
            HStack(spacing: DSSpacing.sm) {
                // Allow Once
                if !isPrewarm {
                    Button {
                        DSHaptics.selection()
                        onDecision(.allowOnce)
                    } label: {
                        Text("Just Once")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }

                // Deny
                Button(role: .destructive) {
                    DSHaptics.warning()
                    onDecision(.deny)
                } label: {
                    Text(isPrewarm ? "Not Now" : "Deny")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }

            // Show details toggle
            if !isPrewarm {
                Button {
                    showDetails.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Hide Details" : "Show Details")
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, DSSpacing.xs)
            }
        }
    }
}

// MARK: - Supporting Views (scoped to avoid conflicts)

private struct ConsentFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct ConsentDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview("Prewarm") {
    CloudConsentPromptView(
        record: CloudTransmissionRecord(
            provider: .applePCC,
            modelName: "Apple Foundation Model (On-Device)",
            promptPreview: "[Consent prewarm]",
            promptCharacterCount: 0,
            contextChunkCount: 0,
            contextHashes: [],
            estimatedBytes: 0
        ),
        onDecision: { _ in }
    )
    .frame(maxHeight: 500)
}

#Preview("With Data") {
    CloudConsentPromptView(
        record: CloudTransmissionRecord(
            provider: .applePCC,
            modelName: "Apple Foundation Models",
            promptPreview: "What kind of oil does this car take?",
            promptCharacterCount: 180,
            contextChunkCount: 3,
            contextHashes: ["abc123", "def456", "789ghi"],
            estimatedBytes: 4096
        ),
        onDecision: { _ in }
    )
    .frame(maxHeight: 600)
}
