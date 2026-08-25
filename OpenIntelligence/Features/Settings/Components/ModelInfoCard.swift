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
            // PCC lines are gated on `supportsPrivateCloudCompute`, not on
            // `supportsFoundationModels`. They used to be gated on the latter, which is a
            // different question: Foundation Models works on this toolchain while PCC is
            // compiled out of it, so an App Store build satisfied the old condition and told
            // the user it had a "PCC server" it does not contain.
            //
            // The 2026-08-21 claim audit corrected the App Store description, the promotional
            // text and the README for exactly this, and did not reach in-app copy.
            if capabilities.supportsFoundationModels {
                var lines = ["Foundation Models (iOS 26+)"]
                lines.append(
                    capabilities.supportsPrivateCloudCompute
                        ? "On-device model + PCC server"
                        : "On-device model, runs entirely on this device"
                )
                lines.append(contentsOf: [
                    "4,096 token context window",
                    "Zero data retention",
                    "Works offline for simple queries",
                ])
                return lines
            }
            var lines = ["Apple Intelligence platform"]
            if capabilities.supportsPrivateCloudCompute {
                // See the note in SettingsStore.executionSummary: routing is on-device
                // first, with PCC as the escalation for prompts that do not fit.
                lines.append(contentsOf: [
                    "On-device first, escalating to PCC only when a prompt is too large",
                    "Zero data retention (PCC)",
                ])
            } else {
                lines.append("Runs on this device; Private Cloud Compute is not enabled in this build")
            }
            lines.append(contentsOf: [
                "No API key needed",
                "Private and secure",
            ])
            return lines
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
