//
//  BackendHealthDiagnosticsView.swift
//  OpenIntelligence
//
//  Simplified diagnostics for active backend health.
//  Shows availability reasons for Apple Foundation Models.
//

import SwiftUI

struct BackendHealthDiagnosticsView: View {
    @ObservedObject var ragService: RAGService

    @State private var appleFMStatus: String = "Unknown"
    @State private var appleFMColor: Color = .secondary
    @State private var isChecking = false

    var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // Overview
                    overviewCard

                    // Apple Foundation Models diagnostics
                    appleFMCard

                    // On-Device Analysis diagnostics
                    onDeviceAnalysisCard
                }
                .padding(DSSpacing.lg)
            }
        }
        .navigationTitle("Backend Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await checkAppleFMAvailability() }
        }
    }

    // MARK: - Overview Card

    @ViewBuilder
    private var overviewCard: some View {
        SurfaceCard {
            SectionHeader(icon: "info.circle", title: "Overview")
            LabeledContent("Active Backend", value: ragService.llmService.modelName)
            SectionFooter("Shows the backend currently used by the chat pipeline.")
        }
    }

    // MARK: - Apple FM Card

    @ViewBuilder
    private var appleFMCard: some View {
        SurfaceCard {
            SectionHeader(icon: "brain.head.profile", title: "Apple Intelligence")

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.sm) {
                    Circle()
                        .fill(appleFMColor)
                        .frame(width: 10, height: 10)
                    Text(appleFMStatus)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        Task { await checkAppleFMAvailability() }
                    } label: {
                        if isChecking {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Check")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isChecking)
                }

                // Capabilities summary
                let capabilities = RAGService.checkDeviceCapabilities()
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    capabilityRow(
                        label: "Foundation Models",
                        available: capabilities.supportsFoundationModels
                    )
                    capabilityRow(
                        label: "Private Cloud Compute",
                        available: capabilities.supportsFoundationModels
                    )
                }
            }

            SectionFooter("Apple Intelligence runs on-device with attested, stateless Private Cloud Compute for complex queries.")
        }
    }

    // MARK: - On-Device Analysis Card

    @ViewBuilder
    private var onDeviceAnalysisCard: some View {
        SurfaceCard {
            SectionHeader(icon: "doc.text.magnifyingglass", title: "On-Device Analysis")

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.sm) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Available")
                        .font(.subheadline)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    capabilityRow(label: "NLTagger Analysis", available: true)
                    capabilityRow(label: "Extractive QA", available: true)
                    capabilityRow(label: "Keyword Extraction", available: true)
                }
            }

            SectionFooter("On-Device Analysis uses NaturalLanguage framework for extractive question answering without a neural LLM.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func capabilityRow(label: String, available: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption)
                .foregroundStyle(available ? .green : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func checkAppleFMAvailability() async {
        isChecking = true
        defer { isChecking = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let fm = AppleFoundationLLMService()
            if fm.isAvailable {
                appleFMStatus = "Available"
                appleFMColor = .green
            } else if let reason = fm.unavailabilityReason {
                appleFMStatus = reason
                appleFMColor = .orange
            } else {
                appleFMStatus = "Unavailable (unknown reason)"
                appleFMColor = .red
            }
            return
        }
        appleFMStatus = "Requires iOS 26"
        appleFMColor = .secondary
        #else
        appleFMStatus = "FoundationModels SDK not available"
        appleFMColor = .secondary
        #endif
    }
}

#Preview {
    NavigationView {
        BackendHealthDiagnosticsView(ragService: RAGService())
    }
}
