//
//  ModelInfoCard.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
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
            return capabilities.supportsFoundationModels ? Image(systemName: "brain.head.profile") : Image(systemName: "sparkles")
        case .chatGPTExtension:
            return Image(systemName: "bubble.left.and.bubble.right.fill")
        case .onDeviceAnalysis:
            return Image(systemName: "doc.text.magnifyingglass")
        case .openAIDirect:
            return Image(systemName: "key.fill")
        case .ggufLocal:
            return Image(systemName: "doc.badge.gearshape")
        case .coreMLLocal:
            return Image(systemName: "cpu")
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
        case .chatGPTExtension:
            return capabilities.supportsAppleIntelligence
        case .onDeviceAnalysis:
            return true
        case .openAIDirect:
            return true
        case .ggufLocal:
            #if os(iOS)
            // Available when a GGUF model is selected from the registry
            return (UserDefaults.standard.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey) ?? "").isEmpty == false
            #else
            return false
            #endif
        case .coreMLLocal:
            // Core ML is available on Apple platforms; actual usability depends on configured model
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
            return capabilities.appleIntelligenceUnavailableReason ?? capabilities.foundationModelUnavailableReason ?? "Enable Apple Intelligence in Settings"
        case .chatGPTExtension:
            return capabilities.supportsAppleIntelligence ? nil : "Requires Apple Intelligence (iOS 18.1+, A17 Pro+ or M1+)"
        case .onDeviceAnalysis:
            return nil
        case .openAIDirect:
            return nil
        case .ggufLocal:
            #if os(iOS)
            let configured = (UserDefaults.standard.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey) ?? "").isEmpty == false
            return configured ? nil : "Download a model from Model Gallery to enable"
            #else
            return "Available on iOS only"
            #endif
        case .coreMLLocal:
            // Could reflect model configuration status in future
            return nil
        }
    }

    private var features: [String] {
        switch modelType {
        case .appleIntelligence:
            if capabilities.supportsFoundationModels {
                return [
                    "Foundation Models (iOS 26+)",
                    "On-device + Private Cloud Compute",
                    "~3B parameters, 8K context",
                    "Zero data retention",
                    "Works offline for simple queries"
                ]
            }
            return [
                "Apple Intelligence platform",
                "Automatic on-device/cloud routing",
                "Zero data retention (PCC)",
                "No API key needed",
                "Private and secure"
            ]
        case .chatGPTExtension:
            return [
                "System-level ChatGPT integration",
                "User consent per request",
                "Free tier (no OpenAI account)",
                "Routed through Apple's proxy",
                "Zero data retention by Apple"
            ]
        case .onDeviceAnalysis:
            return [
                "Extracts key sentences from documents",
                "NaturalLanguage framework",
                "No AI model required",
                "Works on all devices",
                "100% private, no network"
            ]
        case .openAIDirect:
            return [
                "Bring your own OpenAI API key",
                "Access GPT-5, GPT-4o, and o1",
                "Pay-as-you-go pricing",
                "Full control over usage",
                "Up to 400K context window"
            ]
        case .ggufLocal:
            return [
                "Run quantized GGUF models entirely on-device",
                "Embedded llama.cpp core optimized for Metal/ANE",
                "Zero network usage or external dependencies",
                "Great for Gemma/Qwen 2-4B class models"
            ]
        case .coreMLLocal:
            return [
                "Custom Core ML LLM (.mlpackage)",
                "Accelerated by Neural Engine where available",
                "100% offline inference",
                "Bring your own converted model"
            ]
        }
    }
}
