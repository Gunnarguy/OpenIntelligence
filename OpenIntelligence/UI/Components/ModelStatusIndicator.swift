//
//  ModelStatusIndicator.swift
//  OpenIntelligence
//
//  Simplified model status indicator for Apple Intelligence and On-Device Analysis.
//

import SwiftUI

/// Compact model status indicator for the app header
struct ModelStatusIndicator: View {
    @EnvironmentObject private var modelResolution: ModelResolutionService
    @EnvironmentObject private var settings: SettingsStore
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Menu {
            Picker("Model Preference", selection: $settings.fmPreference) {
                ForEach(FoundationModelPreference.availableCases) { preference in
                    if preference == .privateCloudCompute {
                        #if canImport(FoundationModels)
                        let hasEntitlement = EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
                        #else
                        let hasEntitlement = false
                        #endif
                        
                        if hasEntitlement {
                            pickerLabel(for: preference).tag(preference)
                        } else {
                            Text("\(preference.pickerDisplayName) (Requires Entitlement)")
                                .tag(preference)
                                .disabled(true)
                        }
                    } else {
                        pickerLabel(for: preference).tag(preference)
                    }
                }
            }
        } label: {
            // Structurally identical to `QualityModeQuickPicker`'s label: a 20pt circled
            // icon, a two-line VStack, then a chevron, at the same spacing and padding.
            //
            // Matching only the capsule was not enough. On a device where Apple
            // Intelligence is available the status is `.ready`, the second line was
            // omitted, and this pill collapsed to one line while the quality pill beside
            // it stayed at two — so the two controls were visibly different heights. The
            // simulator hid that, because there the status is always `.unavailable` and
            // the second line was always present.
            HStack(spacing: DSSpacing.xs) {
                statusIcon
                modelLabel
                // This control opened a menu with nothing to say so, while the quality
                // pill beside it carried a chevron. Two adjacent controls, one of which
                // looked tappable.
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            // Matches the quality pill: same capsule, same material, same padding scale,
            // same muted tint strength. This was a RoundedRectangle(8) with 14/6 padding
            // and a flat tint next to a Capsule with 10/6 padding and a stroke.
            .glassEffect(.regular.tint(statusColor.opacity(0.18)).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model routing")
        .accessibilityValue("\(settings.fmPreference.pickerDisplayName), \(statusText)")
        .accessibilityHint("Choose whether answers run on device, in Private Cloud Compute, or automatically")
    }

    private func pickerLabel(for preference: FoundationModelPreference) -> some View {
        Label(preference.pickerDisplayName, systemImage: preferenceIcon(for: preference))
    }

    private struct DetailRow: View {
        let label: String
        let value: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private struct BulletPoint: View {
        let text: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 4) {
                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The quality pill's circled-glyph treatment, so the two controls are the same
    /// height and read as one family. Replaces an 8pt dot, which was both a different
    /// shape from its neighbour and — before `statusText` existed — the only encoding of
    /// state on the control.
    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.14))
                .frame(width: 20, height: 20)
            Image(systemName: preferenceIcon(for: settings.fmPreference))
                .font(.system(size: 10, weight: .semibold))
        }
        .scaleEffect(modelResolution.isProcessing ? pulseScale : 1.0)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }

    @ViewBuilder
    private var modelLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(settings.fmPreference.pickerDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            // The second line is unconditional. It carries the live route while a query
            // runs, and otherwise a short description of where this preference sends
            // work. Making it conditional is what let the pill collapse to one line and
            // stop matching the quality pill beside it.
            //
            // It also gives `statusColor` a non-colour rendering. A dot alone said
            // something was wrong without saying what, and said nothing at all to anyone
            // who cannot separate red from green, because the label above names the
            // selected *preference*, never the *status*.
            if modelResolution.isProcessing {
                Text("Using \(modelResolution.currentState.executionPath.displayName)")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(statusText)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The pill's second line when no query is running.
    ///
    /// `.ready` is the common case on a capable device, so it needs a caption that is
    /// worth reading rather than a redundant "Ready" — these describe where each
    /// preference actually sends work, which is the thing the one-word names elide.
    private var statusText: String {
        switch modelResolution.currentState.status {
        case .loading: return "Preparing"
        case .unavailable: return "Unavailable"
        case .ready:
            switch settings.fmPreference.canonical {
            case .automatic: return "Auto-routed"
            case .core3B, .advanced20B: return "Local only"
            case .privateCloudCompute: return "Larger context"
            }
        }
    }

    private func preferenceIcon(for preference: FoundationModelPreference) -> String {
        switch preference.canonical {
        case .automatic: return "arrow.triangle.branch"
        case .core3B, .advanced20B: return "iphone.gen3"
        case .privateCloudCompute: return "cloud.fill"
        }
    }

    private var statusColor: Color {
        if modelResolution.isProcessing {
            switch modelResolution.currentState.executionPath {
            case .onDevice:
                return .green
            case .privateCloudCompute:
                return .blue
            default:
                return .purple
            }
        }
        switch modelResolution.currentState.status {
        case .ready:
            switch settings.fmPreference.canonical {
            case .automatic: return .purple
            case .core3B, .advanced20B: return .green
            case .privateCloudCompute: return .blue
            }
        case .loading:
            return .blue
        case .unavailable:
            return .red
        }
    }

    // `backgroundColor` was removed with the flat RoundedRectangle fill; the glass
    // treatment takes `statusColor` as a tint directly.
}

/// Expanded model selector with quick actions
struct ModelQuickSelector: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showSelector = false
    let deviceCapabilities: DeviceCapabilities

    var body: some View {
        Button {
            showSelector = true
        } label: {
            HStack(spacing: 10) {
                modelIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.selectedModel.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSelector) {
            QuickModelPickerSheet()
        }
    }

    @ViewBuilder
    private var modelIcon: some View {
        Image(systemName: settings.selectedModel.iconName)
            .font(.title2)
            .foregroundColor(iconColor)
            .frame(width: 40, height: 40)
            .background(iconColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconColor: Color {
        switch settings.selectedModel {
        case .appleIntelligence: return .blue
        case .onDeviceAnalysis: return .orange
        }
    }

    private var statusText: String {
        switch settings.selectedModel {
        case .appleIntelligence:
            return deviceCapabilities.supportsFoundationModels ? "Ready" : "Preparing..."
        case .onDeviceAnalysis:
            return "Ready"
        }
    }
}

/// Quick model picker sheet
struct QuickModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @State private var deviceCapabilities = DeviceCapabilities()

    var body: some View {
        NavigationStack {
            List {
                Section("Available Models") {
                    modelRow(for: .appleIntelligence)
                    modelRow(for: .onDeviceAnalysis)
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
    }

    @ViewBuilder
    private func modelRow(for type: LLMModelType) -> some View {
        let isSelected = settings.selectedModel == type
        let isAvailable = type == .onDeviceAnalysis || deviceCapabilities.supportsFoundationModels

        Button {
            if isAvailable {
                settings.selectedModel = type
                DSHaptics.success()
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.iconName)
                    .font(.title3)
                    .foregroundColor(isAvailable ? .accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .foregroundColor(isAvailable ? .primary : .secondary)
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .disabled(!isAvailable)
    }
}

#Preview {
    let rag = RAGService()
    let settings = SettingsStore(ragService: rag)
    let resolution = ModelResolutionService(ragService: rag, settingsStore: settings)
    return VStack(spacing: 20) {
        ModelStatusIndicator()
        ModelQuickSelector(deviceCapabilities: DeviceCapabilities())
    }
    .padding()
    .environmentObject(settings)
    .environmentObject(resolution)
}
