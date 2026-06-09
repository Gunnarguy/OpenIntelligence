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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                Text("Visual Evidence")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(metadata.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .opacity(0.5)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(metadata.ocrWordCount)")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                    Text("OCR Words")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                
                if metadata.barcodeCount > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(metadata.barcodeCount)")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                        Text("Barcodes")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                }
                
                if !metadata.detectedObjects.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(metadata.detectedObjects.count)")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                        Text("Objects")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                }
            }
            
            if !ocrText.isEmpty {
                Text(ocrText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Material.thin)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
