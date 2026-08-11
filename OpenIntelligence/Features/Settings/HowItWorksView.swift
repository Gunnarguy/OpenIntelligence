//
//  HowItWorksView.swift
//  OpenIntelligence
//
//  A permanent, reachable explanation of what the app does with a document and
//  where the work happens.
//
//  Why this exists as a screen rather than onboarding copy: onboarding is seen once,
//  at the moment a user has the least context to absorb it. The questions this answers
//  ("is anything being uploaded", "why did it say it couldn't find that") occur later,
//  and previously had no destination. The app explained itself densely inside Settings
//  and Telemetry, where power users already were, and thinly where a new user actually
//  lands.
//
//  Every claim here was verified against the code on 2026-08-10. Two are deliberately
//  hedged and both are marked below. Do not add a speed figure to this screen without a
//  measurement and the hardware it came from.
//

import SwiftUI

/// Read-only explanation of the pipeline and the on-device boundary.
struct HowItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                noServerCard
                importCard
                askCard
                leavingCard
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("How This Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - There is no server

    private var noServerCard: some View {
        SurfaceCard {
            SectionHeader(icon: "iphone", title: "There is no server")
            Text("Your documents are read, split up, indexed and searched on this device. The app has no backend and no account. Turn off networking entirely and everything here still works except one optional step, described at the bottom.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Import

    private var importCard: some View {
        SurfaceCard {
            SectionHeader(icon: "square.and.arrow.down", title: "When you import something")
            Text("Four things happen, in order.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                stage(
                    number: "1",
                    title: "Extract",
                    detail: "The text comes out of the file. A PDF with a text layer is read directly. Scans, photos and screenshots go through Apple's Vision framework, which reads a page as a document rather than as loose words, so a table arrives as rows instead of a paragraph."
                )
                stage(
                    number: "2",
                    title: "Chunk",
                    detail: "The text is split into passages small enough to search precisely and large enough to still mean something on their own."
                )
                stage(
                    number: "3",
                    // Hedged on purpose. Core ML selects compute units at runtime and the
                    // app expresses a preference through `preferredComputeUnits`; it cannot
                    // guarantee the Neural Engine ran. "Where available" is the honest form.
                    title: "Embed",
                    detail: "Each passage is turned into a list of numbers representing what it is about. This runs on this device's Neural Engine where available."
                )
                stage(
                    number: "4",
                    title: "Index",
                    detail: "Both the numbers and the words are stored, because the two find different things. Numbers find \"what is the warranty policy\". Words find \"SKU 4417-B\"."
                )
            }
        }
    }

    // MARK: - Ask

    private var askCard: some View {
        SurfaceCard {
            SectionHeader(icon: "text.magnifyingglass", title: "When you ask something")
            Text("Your question is searched both ways at once, then a second model reads the passages that came back and reorders them by how well they actually answer what you asked. Only after that does anything get written.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("The answer is assembled from those passages and cites them. When the passages do not support an answer, you are told that instead of given a guess.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Leaving the device

    private var leavingCard: some View {
        SurfaceCard {
            SectionHeader(icon: "cloud", title: "When anything leaves this device")
            Text("One step can, and only if you allow it.")
                .font(.callout)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            Text("Everything above is local, and the writing step normally is too. If a question needs more context than this device's model can hold, the app asks whether to send that single request to Apple's Private Cloud Compute. Apple states it is not retained. You can decline every time, or set routing to On-Device and it will never leave, at the cost of failing on very large questions rather than escalating.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("The modes are explained in Settings under Intelligence Mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stage(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(DSColors.accent)
                .frame(width: 22, height: 22)
                .background(DSColors.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        HowItWorksView()
    }
}
