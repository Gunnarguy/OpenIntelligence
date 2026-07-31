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
            HStack(spacing: 10) {
                statusDot
                modelLabel
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .scaleEffect(modelResolution.isProcessing ? pulseScale : 1.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            }
    }

    @ViewBuilder
    private var modelLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(settings.fmPreference.pickerDisplayName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.primary)
            // Only the live route appears here. The static "what this setting means"
            // line was removed: Hybrid, On-Device, and PCC explain themselves, and
            // the pill is too narrow for a sentence — all three descriptions
            // ellipsized ("Chooses the best route pe…"). The selector above is a
            // native Menu/Picker, which renders Labels only, so there is nowhere a
            // subtitle would fit; `pickerDetail` was deleted rather than left unused.
            if modelResolution.isProcessing {
                HStack(spacing: 3) {
                    Text(modelResolution.currentState.executionPath.emoji)
                        .font(.system(size: 8.5))
                    Text("Using \(modelResolution.currentState.executionPath.displayName)")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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

    private var backgroundColor: Color {
        statusColor.opacity(modelResolution.isProcessing ? 0.25 : 0.15)
    }
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
