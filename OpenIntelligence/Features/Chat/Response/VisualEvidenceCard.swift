//
//  VisualEvidenceCard.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import SwiftUI

struct VisualEvidenceCard: View {
    let metadata: VisualEvidenceMetadata
    let ocrText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "eye.fill")
                    .font(.subheadline)
                    .foregroundStyle(DSColors.accent)
                Text("Visual Evidence")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                Spacer()
                Text(metadata.timestamp, style: .time)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.secondaryText)
            }
            
            Divider()
                .opacity(0.5)
            
            HStack(spacing: DSSpacing.xl) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("\(metadata.ocrWordCount)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.primaryText)
                    Text("OCR Words")
                        .font(.caption2)
                        .foregroundStyle(DSColors.secondaryText)
                        .textCase(.uppercase)
                }
                
                if metadata.barcodeCount > 0 {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("\(metadata.barcodeCount)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(DSColors.primaryText)
                        Text("Barcodes")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                            .textCase(.uppercase)
                    }
                }
                
                if !metadata.detectedObjects.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("\(metadata.detectedObjects.count)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(DSColors.primaryText)
                        Text("Objects")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                            .textCase(.uppercase)
                    }
                }
            }
            
            if !ocrText.isEmpty {
                Text(ocrText)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(3)
                    .padding(.top, DSSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .stroke(DSColors.border, lineWidth: 0.5)
        )
        .padding(.horizontal, DSSpacing.lg)
    }
}
