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
    @State private var didRequestTour = false
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
                guideCard
                replayCard
            }
            .padding(DSSpacing.lg)
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

            // The four stages at a glance, lit left to right in the order they run (5.8).
            SettingsStatusPanel(
                symbol: "square.and.arrow.down", title: "Import", badge: "On this device", badgeColor: .green,
                blocks: [
                    .init(symbol: "doc.text.viewfinder", name: "Extract", color: .blue, figure: "1", share: 0.25, caption: "reads the text"),
                    .init(symbol: "scissors", name: "Chunk", color: .purple, figure: "2", share: 0.5, caption: "splits it up"),
                    .init(symbol: "function", name: "Embed", color: .orange, figure: "3", share: 0.75, caption: "into numbers"),
                    .init(symbol: "tray.full", name: "Index", color: .green, figure: "4", share: 1, caption: "stores both"),
                ])

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
                    detail: "Each passage is turned into a list of numbers representing what it is about. This runs on this device, on the Neural Engine or the GPU depending on the library's embedding option.",
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
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(DSColors.accent)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: DSSpacing.tapTarget)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens definitions for every word the app uses")
        }
    }

    // MARK: - Where things are

    /// The less obvious controls, to find again after their tips are gone (the tour's rebuild, 2026-11-13). Each line
    /// was written from its control's code.
    private static let guideEntries: [(symbol: String, title: String, text: String)] = {
        var entries: [(symbol: String, title: String, text: String)] = [
            ("sidebar.left", "Your conversations",
                "Every conversation in a library is kept with its sources. The sidebar in Chat lists them, so you can pick one up again."),
            ("ellipsis.circle", "New chat and export",
                "The menu at the top of Chat starts a new conversation, exports or clears this one, and turns on Technical Details."),
        ]
        #if os(iOS)
            entries.append(("apple.intelligence", "Rework an answer",
                "The Apple Intelligence button in Chat turns the last answer into key facts, steps, plain English, or what it's missing."))
        #endif
        entries += [
            ("mic", "Say it instead",
                "The microphone in the question box types your words as you speak. Nothing is sent until you send it."),
            ("paperclip", "Attach a file",
                "A file attached in Chat is imported into this library, so later questions can use it too."),
            ("globe.americas", "The Atlas",
                "Passages that mean similar things sit close together, so you can see what your documents cover."),
            ("mic.circle", "Siri and Shortcuts",
                "Siri and Shortcuts can ask a question, search your documents and add to a library without opening the app."),
        ]
        return entries
    }()

    private var guideCard: some View {
        SurfaceCard {
            SectionHeader(icon: "map", title: "Where things are")
            Text("Small tips point these out as you go; here they are in one place.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                ForEach(Self.guideEntries, id: \.title) { entry in
                    HStack(alignment: .top, spacing: DSSpacing.md) {
                        Image(systemName: entry.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColors.accent)
                            .frame(width: 22, height: 22)
                            .background(DSColors.accent.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Ask

    private var askCard: some View {
        SurfaceCard {
            SectionHeader(icon: "text.magnifyingglass", title: "When you ask something")
            // The same four steps the two paragraphs below describe, in order (5.8).
            SettingsStatusPanel(
                symbol: "text.magnifyingglass", title: "Ask", badge: "On this device", badgeColor: .green,
                blocks: [
                    .init(symbol: "magnifyingglass", name: "Search", color: .blue, figure: "1", share: 0.25, caption: "two ways"),
                    .init(symbol: "arrow.up.arrow.down", name: "Rerank", color: .purple, figure: "2", share: 0.5, caption: "best first"),
                    .init(symbol: "text.bubble", name: "Answer", color: .orange, figure: "3", share: 0.75, caption: "with sources"),
                    .init(symbol: "checkmark.shield", name: "Check", color: .green, figure: "4", share: 1, caption: "or says so"),
                ])
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
    /// Private Cloud Compute is compiled in only with Swift 6.4 (`#if compiler(>=6.4)`) and runs only on iOS
    /// and macOS 27 (`supportsPrivateCloudCompute`), so there are three cases. Corrected 2026-10-15: the first
    /// named only the question too large for the device and said the app always asks, and the other two said
    /// a question too large for the device fails; `ModelExecutionPlanner` also sends a Deep Think or Maximum
    /// answer drawn from more than one document, "Allow without asking" doesn't ask, and an answer too large
    /// for the device is retried on it with fewer, shorter passages (`usedOverflowRetry`).
    private var leavingExplanation: String {
        if deviceCapabilities.supportsPrivateCloudCompute {
            return "Everything above is local, and the writing step usually is too. With Hybrid in the model picker, an answer goes to Apple's Private Cloud Compute when its passages don't fit in this device's model, and a Deep Think or Maximum answer when it draws on more than one document; with Private Cloud Compute chosen there, every answer does. Settings, Model & Privacy decides whether the app asks you first, sends without asking, or never sends. Apple states it keeps nothing after answering. With On-Device chosen, or Never use in Settings, nothing leaves, and an answer too large for this device's model is written from fewer, shorter passages."
        }
        if DeviceCapabilities.pccRoutingCompiledIn {
            return "Everything above is local, and so is the writing step. Private Cloud Compute needs iOS or macOS 27, so on this version nothing is sent anywhere and you won't be asked. An answer too large for this device's model is written from fewer, shorter passages."
        }
        return "Everything above is local, and so is the writing step. Private Cloud Compute isn't in this build, so nothing is sent anywhere and you won't be asked. An answer too large for this device's model is written from fewer, shorter passages."
    }

    private var leavingCard: some View {
        SurfaceCard {
            SectionHeader(icon: "cloud", title: "When anything leaves this device")
            Text("One step can, and only if you allow it.")
                .font(.callout)
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
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(DSColors.accent)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: DSSpacing.tapTarget)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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

            // Every screen's tips, again (5.8). They come back one at a time as each screen is used.
            Button {
                DSHaptics.selection()
                didRequestTour = true
                Task { await Tour.showAgain() }
            } label: {
                HStack {
                    Text("Show Me Around")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "hand.point.up.left")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(DSColors.accent)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: DSSpacing.tapTarget)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(didRequestTour)
            .accessibilityHint("Shows the tips on each screen again, one at a time, as you use it")

            if didRequestTour {
                Text("The tips come back one at a time as you use each screen.")
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

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
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
