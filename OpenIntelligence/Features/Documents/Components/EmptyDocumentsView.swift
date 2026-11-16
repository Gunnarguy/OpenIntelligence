//
//  EmptyDocumentsView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct EmptyDocumentsView: View {
    let isImportingSamples: Bool
    let hasImportedSamples: Bool
    let isAtDocumentLimit: Bool
    let documentLimit: Int
    let statusMessage: String?
    let onImportSamples: () -> Void
    let onPickFiles: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
                // Hero icon with liquid gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.12),
                                    Color.accentColor.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .glassCircleEffectHelper()

                    Image(systemName: "doc.viewfinder.fill")
                        .scaledFont(size: 44, weight: .bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.accentColor.opacity(0.2), radius: 8, x: 0, y: 3)
                }
                .padding(.top, DSSpacing.lg)

                VStack(spacing: DSSpacing.xs) {
                    Text("No Documents Yet")
                        .font(DSTypography.title)
                        .foregroundStyle(.primary)

                    Text("Start with files that keep their structure")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.xl)
                }

                if isAtDocumentLimit {
                    // The words in the label color and the orange in the icon and the tint, as on the other tinted
                    // chips (5.7): the readable orange on its own tint measured 4.43 to 1 on the Mac.
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DSColors.readable(.orange))
                        Text("Limit of \(documentLimit) documents reached.")
                    }
                    .font(DSTypography.caption.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                }

                VStack(spacing: DSSpacing.sm) {
                    Button(action: {
                        DSHaptics.medium()
                        onPickFiles()
                    }) {
                        Label("Add Your Documents", systemImage: "tray.and.arrow.down")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DSSpacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                    Button(action: {
                        DSHaptics.light()
                        onImportSamples()
                    }) {
                        HStack {
                            if isImportingSamples {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, DSSpacing.xxs)
                            }
                            // Primary text on the gray button: the button's own gray label "failed" the audit.
                            Text(hasImportedSamples ? "Re-import Samples" : "Import Sample Workspace")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DSColors.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.xxs)
                    }
                    .buttonStyle(.bordered)
                    .tint(DSColors.primaryText)
                    .disabled(isImportingSamples)

                    if let statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                .padding(.horizontal, DSSpacing.xxs)

                // Features
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    DocumentFeatureRow(
                        icon: "doc.on.doc.fill",
                        title: "Multiple Formats",
                        description: "PDF, Office, text, images, and transcripts"
                    )

                    DocumentFeatureRow(
                        icon: "bolt.ring.closed",
                        // Was "Fast Local Processing": no measurement backs "fast" (5.8 premium pass).
                        title: "Processed on This Device",
                        description: "Reading, splitting and indexing run here"
                    )

                    DocumentFeatureRow(
                        icon: "lock.shield.fill",
                        // Was "Content never leaves your device for processing", which an answer sent to Private Cloud
                        // Compute, with the person's permission, contradicts (5.8 premium pass).
                        title: "Private by Design",
                        description: "Import, indexing and search need no network"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.lg)
                // The app's card (`SurfaceCard`'s fill and shadow), not a material of its own (5.8 premium pass).
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.surface)
                        .shadow(color: .black.opacity(0.04), radius: DSSpacing.sm, x: 0, y: DSSpacing.xs)
                )
                .padding(.horizontal, DSSpacing.xs)
                
                Text("PDFs, DOCX/XLSX/PPTX, TXT/MD, CSV, images, and transcripts import cleanly. Legacy formats and dense scientific tables may need conversion first.")
                    .font(DSTypography.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DSColors.secondaryText)
                    .padding(.horizontal, DSSpacing.xl)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, DSSpacing.lg)
    }
}

struct DocumentFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.accentColor)
            }
            .glassCircleEffectHelper()

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(DSTypography.body.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)

                Text(description)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ScrollView {
        EmptyDocumentsView(
            isImportingSamples: false,
            hasImportedSamples: false,
            isAtDocumentLimit: false,
            documentLimit: 25,
            statusMessage: nil,
            onImportSamples: {},
            onPickFiles: {}
        )
    }
}
