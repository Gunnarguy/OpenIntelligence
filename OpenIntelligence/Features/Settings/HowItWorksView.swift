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
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @State private var didRequestReplay = false
    /// Read so this screen describes the build the user is actually running. Private Cloud
    /// Compute is compiled out of App Store builds, so the escalation copy below described a
    /// step that cannot happen. Gating on the capability means the wording corrects itself
    /// when PCC does ship rather than needing another edit.
    @State private var deviceCapabilities = DeviceCapabilities()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                noServerCard
                importCard
                askCard
                leavingCard
                vocabularyCard
                replayCard
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
                    detail: "The text comes out of the file. A PDF with a text layer is read directly. Scans, photos and screenshots go through Apple's Vision framework, which reads a page as a document rather than as loose words, so a table arrives as rows instead of a paragraph.",
                    term: .extraction
                )
                stage(
                    number: "2",
                    title: "Chunk",
                    detail: "The text is split into passages small enough to search precisely and large enough to still mean something on their own.",
                    term: .chunk
                )
                stage(
                    number: "3",
                    // Hedged on purpose. Core ML selects compute units at runtime and the
                    // app expresses a preference through `preferredComputeUnits`; it cannot
                    // guarantee the Neural Engine ran. "Where available" is the honest form.
                    title: "Embed",
                    detail: "Each passage is turned into a list of numbers representing what it is about. This runs on this device's Neural Engine where available.",
                    term: .vector
                )
                stage(
                    number: "4",
                    title: "Index",
                    detail: "Both the numbers and the words are stored, because the two find different things. Numbers find \"what is the warranty policy\". Words find \"SKU 4417-B\".",
                    term: .index
                )
            }
        }
    }

    // MARK: - Vocabulary

    /// Points at the word-by-word reference without restating any of it.
    ///
    /// This screen and `GlossaryView` divide the work rather than overlapping: this one
    /// explains the pipeline in order and in prose, that one defines single words out of
    /// order and in two registers. Copying definitions down here is what would put the two
    /// out of step, so each stage above links to its term instead.
    private var vocabularyCard: some View {
        SurfaceCard {
            SectionHeader(icon: "character.book.closed", title: "If a word here is unfamiliar")
            Text("Every term this app puts on screen has a plain definition and a technical one. Tap the information button beside any stage above, or open the full list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                GlossaryView()
            } label: {
                HStack {
                    Text("Plain English")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(DSColors.accent)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                        .fill(DSColors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens definitions for every word the app uses")
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

    /// What actually leaves the device, on the build the user is running.
    ///
    /// The second wording is not a hedge. Private Cloud Compute sits behind
    /// `#if compiler(>=6.4)` in eleven places, and App Store builds are produced by an older
    /// toolchain that compiles those blocks out entirely, so nothing escalates and the app
    /// never asks. Telling the user it might was describing a different build than the one in
    /// their hand.
    private var leavingExplanation: String {
        if deviceCapabilities.supportsPrivateCloudCompute {
            return "Everything above is local, and the writing step normally is too. If a question needs more context than this device's model can hold, the app asks whether to send that single request to Apple's Private Cloud Compute. Apple states it is not retained. You can decline every time, or set routing to On-Device and it will never leave, at the cost of failing on very large questions rather than escalating."
        }
        return "Everything above is local, and so is the writing step, in this version. Support for escalating a single oversized request to Apple's Private Cloud Compute is built and is not enabled in this build, so nothing is sent anywhere and you will not be asked. A question too large for this device's model fails rather than escalating. When that support does enable, it will ask first and you will be able to decline every time."
    }

    private var leavingCard: some View {
        SurfaceCard {
            SectionHeader(icon: "cloud", title: "When anything leaves this device")
            Text("One step can, and only if you allow it.")
                .font(.callout)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            Text(leavingExplanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("The modes are explained in Settings under Intelligence Mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Replay

    /// Puts the first-run walkthrough back.
    ///
    /// `OnboardingStateStore.resetAllOnboarding()` was written with the rest of the
    /// onboarding state machine and had **zero call sites**, so once a user had finished
    /// or skipped the introduction there was no way to see it again short of deleting the
    /// app. This is its first caller. It lives here because someone reading how the app
    /// works is exactly the person who would want the guided version.
    private var replayCard: some View {
        SurfaceCard {
            SectionHeader(icon: "arrow.counterclockwise", title: "Show the introduction again")
            Text("Replays the first-run walkthrough, including the import you can watch happen. Your libraries and documents are not touched.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                DSHaptics.selection()
                didRequestReplay = true
                onboardingStore.resetAllOnboarding()
            } label: {
                HStack {
                    Text("Replay Introduction")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(DSColors.accent)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                        .fill(DSColors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(didRequestReplay)
            .accessibilityHint("Shows the first-run walkthrough again without changing your documents")

            if didRequestReplay {
                Text("The introduction is open behind this screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stage(number: String, title: String, detail: String, term: GlossaryTermID) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(DSColors.accent)
                .frame(width: 22, height: 22)
                .background(DSColors.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DSSpacing.sm) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    GlossaryInfoButton(termID: term, size: .caption)
                    Spacer(minLength: 0)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // `.combine` would swallow the information button, leaving the definition
        // unreachable to VoiceOver while remaining tappable by touch.
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    NavigationStack {
        HowItWorksView()
    }
    .environmentObject(OnboardingStateStore())
}
