//
//  WhatsNewView.swift
//  OpenIntelligence
//
//  Shown once after an update, listing what changed.
//

import SwiftUI

struct WhatsNewView: View {
    let release: WhatsNewRelease
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    header

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        ForEach(release.items) { item in
                            row(for: item)
                        }
                    }

                    // Says out loud what the app claims to do, on the one screen where
                    // a user is deciding whether the update is worth their attention.
                    Text("Every answer still comes from your own documents, with citations you can tap.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .padding(.top, DSSpacing.xs)
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background)
            .navigationTitle("What's New")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Version \(release.version)")
                .font(DSTypography.chip)
                .foregroundStyle(.tint)
            Text(release.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DSColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for item: WhatsNewRelease.Item) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DSColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewView(
        release: WhatsNewStore.releases["4.8"]!,
        onDismiss: {}
    )
}
