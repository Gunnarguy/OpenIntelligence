//
//  DocumentQuotaBanner.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct DocumentQuotaBanner: View {
    let currentCount: Int
    let limit: Int
    let tierName: String
    let addOnPacks: Int
    let onUpgrade: () -> Void

    private var remaining: Int { max(limit - currentCount, 0) }
    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(currentCount) / Double(limit), 1)
    }
    private var isNearLimit: Bool { progress >= 0.8 }
    private var isAtLimit: Bool { progress >= 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Document Quota")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(currentCount)/\(limit)")
                    .font(.caption)
                    .foregroundStyle(isAtLimit ? .orange : .secondary)
            }

            ProgressView(value: progress)
                .tint(isAtLimit ? .orange : isNearLimit ? .yellow : Color.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                if isAtLimit {
                    Label("Quota reached. Upgrade or remove documents to keep importing.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if isNearLimit {
                    Label("Almost full. Reserve your next tier before you hit the wall.", systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                } else {
                    Text("\(remaining) imports left on your \(tierName) plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if addOnPacks > 0 {
                let bonusDocs = addOnPacks * QuotaPolicy.addOnDocumentIncrement
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("Legacy document-pack bonus: +\(bonusDocs) docs")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("Your previous document-pack purchases are still applied, but document packs are no longer sold in-app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    TelemetryCenter.emitBillingEvent(
                        "Quota banner upgrade CTA tapped",
                        metadata: [
                            "currentCount": String(currentCount),
                            "limit": String(limit),
                            "progress": String(format: "%.1f", progress * 100)
                        ]
                    )
                    onUpgrade()
                } label: {
                    Label(isAtLimit ? "Upgrade Now" : "Explore Plans", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(isAtLimit || isNearLimit ? .borderedProminent : .borderedProminent)
                .tint(isAtLimit || isNearLimit ? nil : .gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColors.background.opacity(0.9))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
        )
        .onAppear {
            if isAtLimit {
                TelemetryCenter.emitBillingEvent(
                    "Quota hit",
                    severity: .warning,
                    metadata: [
                        "tier": tierName,
                        "limit": String(limit),
                        "currentCount": String(currentCount)
                    ]
                )
            }
        }
    }
}

#Preview {
    DocumentQuotaBanner(
        currentCount: 23,
        limit: 25,
        tierName: "Free",
        addOnPacks: 0,
        onUpgrade: {}
    )
    .padding()
}
