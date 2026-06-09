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
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
            DSHaptics.soft()
        } label: {
            HStack(spacing: 8) {
                statusDot
                modelLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model Resolution Details")
                    .font(.headline)
                
                DetailRow(label: "Reason", value: modelResolution.currentState.resolutionReason.displayText)
                DetailRow(label: "Path", value: modelResolution.currentState.executionPath.displayName)
                DetailRow(label: "Model", value: modelResolution.currentState.activeModelName)
                
                Divider()
                
                Text("Transparency is key. This model was selected based on your device capabilities and active routing policy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(width: 280)
        }
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

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var modelLabel: some View {
        HStack(spacing: 4) {
            Text(modelResolution.currentState.executionPath.emoji)
                .font(.caption)
            Text(modelResolution.currentState.activeModelName)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
        }
    }

    private var statusColor: Color {
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
        statusColor.opacity(0.15)
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
