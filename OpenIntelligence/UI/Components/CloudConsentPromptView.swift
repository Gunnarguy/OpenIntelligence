import SwiftUI

struct CloudConsentPromptView: View {
    let record: CloudTransmissionRecord
    let onDecision: (CloudConsentDecision) -> Void

    @State private var showDetails = false

    private var isPrewarm: Bool {
        record.promptCharacterCount == 0 && record.contextChunkCount == 0
    }

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var isCompactHeight: Bool {
        #if os(iOS)
        return verticalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.md)

            if isCompactHeight {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DSSpacing.lg) {
                        // Icon and Title
                        headerSection
                            .padding(.top, DSSpacing.xs)

                        // Simple explanation
                        explanationSection

                        // Expandable details (collapsed by default)
                        if showDetails {
                            detailsSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Divider()
                            .padding(.top, DSSpacing.sm)

                        // Inline action buttons
                        buttonsSection
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.lg)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DSSpacing.lg) {
                        // Icon and Title
                        headerSection
                            .padding(.top, DSSpacing.xs)  // Extra padding to prevent cloud icon clipping

                        // Simple explanation
                        explanationSection

                        // Expandable details (collapsed by default)
                        if showDetails {
                            detailsSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, DSSpacing.lg)
                }

                Divider()
                    .padding(.top, DSSpacing.sm)

                // Sticky action buttons at the bottom
                buttonsSection
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.md)
                    .padding(.bottom, DSSpacing.lg)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .animation(DSAnimations.snappySpring, value: showDetails)
    }

    private var headerSection: some View {
        VStack(spacing: DSSpacing.sm) {
            // Apple-style cloud icon with shield
            ZStack {
                Circle()
                    .fill(DSColors.accent.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "cloud.fill")
                    .font(.title.weight(.medium))
                    .foregroundStyle(DSColors.accent)
            }

            Text("Private Cloud Compute")
                .font(.title2.weight(.semibold))

            Text(isPrewarm ? "Enable Apple's secure cloud processing" : "Request requires cloud processing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// What Apple says about Private Cloud Compute, in Apple's terms and said to be Apple's
    /// (security.apple.com/blog/private-cloud-compute, read 2026-10-15): the app can't check these, and
    /// `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` rules out promising them in the app's own voice.
    /// Through 5.6 the rows read "Your data is never stored" and "Same security as your device"; Apple's
    /// words are "the same hardware security technologies used in iPhone, including the Secure Enclave and
    /// Secure Boot" and "no user data is retained in any form after the response is returned".
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ConsentFeatureRow(
                icon: "lock.shield.fill",
                iconColor: .green,
                title: "Encrypted end to end",
                subtitle: "From this device to Apple's servers"
            )

            ConsentFeatureRow(
                icon: "server.rack",
                iconColor: .accentColor,
                title: "Apple silicon servers",
                subtitle: "With the Secure Enclave and Secure Boot from iPhone"
            )

            ConsentFeatureRow(
                icon: "eye.slash.fill",
                iconColor: .accentColor,
                title: "Deleted after the answer",
                subtitle: "Kept in no form, and not available to Apple"
            )

            Text("As Apple describes Private Cloud Compute.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
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
            if record.contextCharacterCount > 0 {
                ConsentDetailRow(label: "Context size", value: "\(record.contextCharacterCount) chars")
            }
            ConsentDetailRow(
                label: "Payload",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(record.estimatedBytes),
                    countStyle: .file
                )
            )
            if let routeReason = record.routeReason {
                ConsentDetailRow(label: "Why PCC", value: routeReason.rawValue)
            }
        }
        .font(.footnote)
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(DSColors.accent)

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DSSpacing.sm)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.sm)
                }
                .buttonStyle(.bordered)
            }

            // Show details toggle
            if !isPrewarm {
                Button {
                    showDetails.toggle()
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Text(showDetails ? "Hide Details" : "Show Details")
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: DSSpacing.tapTarget)
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
                .font(.body.weight(.medium))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
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
                .monospacedDigit()
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
