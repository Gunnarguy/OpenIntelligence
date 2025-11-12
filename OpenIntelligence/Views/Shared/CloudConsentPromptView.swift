import SwiftUI

struct CloudConsentPromptView: View {
    let record: CloudTransmissionRecord
    let onDecision: (CloudConsentDecision) -> Void

    private var estimatedKilobytes: String {
        let kb = Double(record.estimatedBytes) / 1024.0
        return kb < 1 ? "<1 KB" : String(format: "%.1f KB", kb)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    headlineSection
                    metadataSection
                    hashesSection
                    buttonsSection
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Cloud Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headlineSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Send this request to \(record.provider.displayName)?")
                .font(DSTypography.title)
            Text("The model runs in a secure cloud environment. Approving transmits the prompt and optional context chunks shown below.")
                .font(DSTypography.body)
                .foregroundColor(DSColors.secondaryText)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            LabeledContent("Provider") {
                Text(record.provider.displayName)
            }
            LabeledContent("Model") {
                Text(record.modelName)
            }
            LabeledContent("Prompt Preview") {
                Text(record.promptPreview)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4)
            }
            LabeledContent("Prompt Characters") {
                Text("\(record.promptCharacterCount)")
            }
            LabeledContent("Context Chunks") {
                Text("\(record.contextChunkCount)")
            }
            LabeledContent("Estimated Payload") {
                Text(estimatedKilobytes)
            }
        }
        .roundedSection()
    }

    private var hashesSection: some View {
        Group {
            if record.contextHashes.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Hash of top \(record.contextHashes.count) chunks")
                        .font(DSTypography.body)
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        ForEach(record.contextHashes.indices, id: \.self) { index in
                            Text("#\(index + 1): \(record.contextHashes[index])")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(DSColors.secondaryText)
                        }
                    }
                }
                .roundedSection()
            }
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: DSSpacing.sm) {
            Button {
                DSHaptics.selection()
                onDecision(.allowOnce)
            } label: {
                Label("Allow Once", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                DSHaptics.success()
                onDecision(.allowAndRemember)
            } label: {
                Label("Always Allow for \(record.provider.shortName)", systemImage: "shield.checkerboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                DSHaptics.warning()
                onDecision(.deny)
            } label: {
                Label("Deny", systemImage: "xmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    CloudConsentPromptView(
        record: CloudTransmissionRecord(
            provider: .openAI,
            modelName: "gpt-4o-mini",
            promptPreview: "Summarize the quarterly report results for the leadership team...",
            promptCharacterCount: 180,
            contextChunkCount: 3,
            contextHashes: ["abc123", "def456", "789ghi"],
            estimatedBytes: 4096
        ),
        onDecision: { _ in }
    )
}
