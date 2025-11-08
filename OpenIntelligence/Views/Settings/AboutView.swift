import SwiftUI

/// Presents product metadata and device-specific capability information.
struct AboutView: View {
    @State private var deviceCapabilities = DeviceCapabilities()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // App Info
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About OpenIntelligence")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenIntelligence")
                                .font(.title.bold())
                            Text("Privacy-First RAG Application")
                                .foregroundColor(.secondary)
                            Text("Version 0.1.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    // Your Device
                    SurfaceCard {
                        SectionHeader(icon: "cpu", title: "Your Device")
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Device Chip", value: deviceCapabilities.deviceChip.rawValue)
                            LabeledContent("iOS Version", value: deviceCapabilities.iOSVersion)
                            LabeledContent("Performance", value: deviceCapabilities.deviceChip.performanceRating)
                            LabeledContent("AI Tier", value: deviceCapabilities.deviceTier.description)
                        }
                    }

                    // AI Capabilities
                    SurfaceCard {
                        SectionHeader(icon: "brain.head.profile", title: "AI Capabilities")
                        VStack(alignment: .leading, spacing: 8) {
                            capabilityRow(title: "Apple Intelligence", condition: deviceCapabilities.supportsAppleIntelligence)
                            capabilityRow(title: "Foundation Models", condition: deviceCapabilities.supportsFoundationModels)
                            capabilityRow(title: "Private Cloud Compute", condition: deviceCapabilities.supportsPrivateCloudCompute)
                            capabilityRow(title: "Writing Tools", condition: deviceCapabilities.supportsWritingTools)
                        }
                    }

                    // Features
                    SurfaceCard {
                        SectionHeader(icon: "star.circle.fill", title: "Features")
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "doc.text.fill", title: "Document Processing", description: "Import PDFs, text files, and more")
                            FeatureRow(icon: "cpu", title: "On-Device Processing", description: "OCR, chunking, and embeddings run locally")
                            FeatureRow(icon: "brain", title: "Multiple AI Pathways", description: "Foundation Models, OpenAI, or extractive QA")
                            FeatureRow(icon: "lock.shield.fill", title: "Privacy First", description: "Your data stays on your device by default")
                        }
                    }

                    // Technology
                    SurfaceCard {
                        SectionHeader(icon: "gearshape.2.fill", title: "Technology")
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("RAG Pipeline", value: "Semantic search + LLM")
                            LabeledContent("Embeddings", value: "NLEmbedding (512-dim)")
                            LabeledContent("Vector Store", value: "In-memory cosine similarity")
                            LabeledContent("Minimum iOS", value: "18.0")
                            LabeledContent("Optimized for", value: "iOS 26.0+")
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            DispatchQueue.main.async {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
    }

    private func capabilityRow(title: String, condition: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: condition ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(condition ? .green : .secondary)
        }
    }
}
