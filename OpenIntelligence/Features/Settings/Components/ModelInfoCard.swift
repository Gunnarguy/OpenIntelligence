//
//  ModelInfoCard.swift
//  OpenIntelligence
//
//  Summarises the capabilities and availability of the currently selected model.
//  Simplified: only Apple Intelligence and On-Device Analysis are supported.
//

import SwiftUI

/// Summarises the capabilities and availability of the currently selected model.
struct ModelInfoCard: View {
    let modelType: LLMModelType
    let capabilities: DeviceCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                icon
                    .font(.title)
                    .foregroundColor(.accentColor)

                Spacer()

                availabilityBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(feature)
                            .font(.caption)
                            .foregroundColor(DSColors.secondaryText)
                    }
                }
            }

            if let reason = unavailabilityReason, !reason.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }

    private var icon: Image {
        switch modelType {
        case .appleIntelligence:
            return capabilities.supportsFoundationModels
                ? Image(systemName: "brain.head.profile")
                : Image(systemName: "sparkles")
        case .onDeviceAnalysis:
            return Image(systemName: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        if isAvailable {
            Text("Available")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(6)
        } else {
            Text("Unavailable")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(6)
        }
    }

    private var isAvailable: Bool {
        switch modelType {
        case .appleIntelligence:
            return capabilities.supportsAppleIntelligence || capabilities.supportsFoundationModels
        case .onDeviceAnalysis:
            return true
        }
    }

    private var unavailabilityReason: String? {
        switch modelType {
        case .appleIntelligence:
            if capabilities.supportsAppleIntelligence || capabilities.supportsFoundationModels {
                return nil
            }
            if capabilities.iOSMajor < 18 {
                return "Requires iOS 18.1 or later"
            }
            return capabilities.appleIntelligenceUnavailableReason
                ?? capabilities.foundationModelUnavailableReason
                ?? "Enable Apple Intelligence in Settings"
        case .onDeviceAnalysis:
            return nil
        }
    }

    private var features: [String] {
        switch modelType {
        case .appleIntelligence:
            if capabilities.supportsFoundationModels {
                return [
                    "Foundation Models (iOS 26+)",
                    "On-device model + PCC server",
                    "4,096 token context window",
                    "Zero data retention",
                    "Works offline for simple queries",
                ]
            }
            return [
                "Apple Intelligence platform",
                "Reliability-first routing (prefers PCC for library queries)",
                "Zero data retention (PCC)",
                "No API key needed",
                "Private and secure",
            ]
        case .onDeviceAnalysis:
            return [
                "Extracts key sentences from documents",
                "NaturalLanguage framework",
                "No AI model required",
                "Works on all devices",
                "100% private, no network",
            ]
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ModelInfoCard(
            modelType: .appleIntelligence,
            capabilities: DeviceCapabilities(
                iOSMajor: 26,
                supportsAppleIntelligence: true,
                appleIntelligenceUnavailableReason: nil,
                supportsFoundationModels: true,
                foundationModelUnavailableReason: nil,
                supportsCoreML: true
            )
        )
        ModelInfoCard(
            modelType: .onDeviceAnalysis,
            capabilities: DeviceCapabilities(
                iOSMajor: 17,
                supportsAppleIntelligence: false,
                appleIntelligenceUnavailableReason: "Device not supported",
                supportsFoundationModels: false,
                foundationModelUnavailableReason: nil,
                supportsCoreML: true
            )
        )
    }
.padding()
}
