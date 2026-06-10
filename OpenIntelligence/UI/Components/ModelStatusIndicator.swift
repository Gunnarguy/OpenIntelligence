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
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button {
            showDetails = true
            DSHaptics.soft()
        } label: {
            HStack(spacing: 6) {
                statusDot
                modelLabel
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.intelligence")
                        .font(.title3)
                        .symbolRenderingMode(.multicolor)
                    Text("Apple Intelligence")
                        .font(.headline)
                    Spacer()
                    if modelResolution.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    DetailRow(label: "Model Selected", value: modelResolution.currentState.selectedType.displayName)
                    
                    DetailRow(label: "Routing Policy", value: modelResolution.currentState.executionPath.displayName)
                    
                    if modelResolution.isProcessing {
                        DetailRow(label: "Active Path", value: "\(modelResolution.currentState.executionPath.emoji) \(modelResolution.currentState.executionPath.displayName) (Active)")
                    } else if let lastPath = modelResolution.lastExecutionPath {
                        DetailRow(label: "Last Query Path", value: "\(lastPath.emoji) \(lastPath.displayName)")
                    }
                    
                    DetailRow(label: "Resolved Model", value: modelResolution.currentState.activeModelName)
                }
                
                Divider()
                
                // Under the hood info
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Under the Hood: Hybrid Routing")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundColor(.blue)
                    }
                    
                    Text("OpenIntelligence dynamically routes queries between your local device and Private Cloud Compute (PCC) based on query complexity, quality mode, and document context size:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        BulletPoint(text: "On-Device (Standard): Processes everyday queries locally. Highly private and offline capable, with a context limit of 4K tokens.")
                        BulletPoint(text: "Private Cloud Compute (PCC): Automatically routes complex reasoning (Deep Think/Maximum modes) or large documents (up to 32K tokens) to secure, stateless cloud enclaves that cryptographically guarantee privacy.")
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                
                Text("Transparency is key. This model was selected based on your device capabilities and active routing policy.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(width: 320)
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
            .frame(width: 6, height: 6)
            .scaleEffect(modelResolution.isProcessing ? pulseScale : 1.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            }
    }

    @ViewBuilder
    private var modelLabel: some View {
        HStack(spacing: 4) {
            Text(modelResolution.currentState.executionPath.emoji)
                .font(.system(size: 10))
            Text(modelResolution.currentState.activeModelName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
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
