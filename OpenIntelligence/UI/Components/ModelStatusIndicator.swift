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
                    Text(preference.displayName).tag(preference)
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
            Text(cleanModelName(modelResolution.currentState.activeModelName))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.primary)
            if settings.fmPreference == .automatic {
                HStack(spacing: 3) {
                    Text(modelResolution.currentState.executionPath.emoji)
                        .font(.system(size: 8.5))
                    Text(modelResolution.currentState.executionPath.displayName)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func cleanModelName(_ name: String) -> String {
        if settings.fmPreference != .automatic {
            return settings.fmPreference.displayName
        }

        if name.contains("Apple Intel") || name.contains("Apple Intelligence") {
            return "Apple Intelligence"
        }
        if name.contains("On-Device Analysis") {
            return "On-Device Analysis"
        }
        return name
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
            return .green
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
