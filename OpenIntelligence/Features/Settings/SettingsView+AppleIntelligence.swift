//
//  SettingsView+AppleIntelligence.swift
//  OpenIntelligence
//
//  Part of SettingsView, moved from SettingsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import SwiftUI
import TipKit

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(AppKit)
import AppKit
#endif

extension SettingsView {
    // MARK: - Apple Intelligence Features Card

    /// Count of currently enabled Apple Intelligence features.
    /// Number of the toggleable Apple Intelligence features currently on.
    ///
    /// Counts four, not seven. `enableWritingTools`, `enableSpeechAnalysis` and
    /// `enableTranslation` used to be in this list, so the badge was reporting three
    /// switches that gated nothing as if they were live capability. These four are the
    /// ones with real consumers, and they are the four that still render as switches.
    private var activeAIFeatureCount: Int {
        [
            settings.enableSmartReplies,
            settings.enableContentTagging,
            settings.enableSpotlightIndexing,
            settings.enableBackgroundMaintenance,
        ].filter { $0 }.count
    }

    private var totalAIFeatureCount: Int { 4 }

    /// The selected model in plain words. Citation Scout answers with spans of the passages and writes nothing
    /// (`LLMModelType`: "Extractive only, no generation"); Apple's model can reach Private Cloud Compute only with
    /// the person's consent (Docs/PRIVACY_AND_ROUTING.md).
    var plainModelName: String {
        switch settings.selectedModel {
        case .appleIntelligence: "Apple's model"
        case .onDeviceAnalysis: "Quotes only"
        }
    }

    var plainModelTagline: String {
        switch settings.selectedModel {
        case .appleIntelligence:
            "Writes answers from your documents on this device, and can use Private Cloud Compute when you allow it."
        case .onDeviceAnalysis:
            "Answers with sentences taken word for word from your documents, and no model writes anything."
        }
    }

    @ViewBuilder
    var appleIntelligenceFeaturesCard: some View {
        let badgeColor: Color = activeAIFeatureCount == totalAIFeatureCount ? .green : .orange

        VStack(spacing: 0) {
            // Header
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "apple.intelligence")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }
                // The page's title and the model card above already say "Apple Intelligence" (5.7 UI cleanup).
                Text(settings.showTechnicalDetails ? "Apple Intelligence" : "Features")
                    .font(.headline)
                Spacer()
                Text(settings.showTechnicalDetails ? "\(activeAIFeatureCount)/\(totalAIFeatureCount)" : "\(activeAIFeatureCount) of \(totalAIFeatureCount) on")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DSColors.readable(badgeColor))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(badgeColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(DSSpacing.lg)

            Divider().padding(.horizontal, DSSpacing.lg)

            VStack(spacing: DSSpacing.xxs) {
                // Toggleable features
                aiFeatureToggleRow(
                    icon: "text.bubble.fill",
                    color: .accentColor,
                    title: "Smart Replies",
                    subtitle: settings.showTechnicalDetails ? "Conversational follow-up suggestions" : "Suggested follow-up questions under an answer",
                    isOn: $settings.enableSmartReplies
                )

                aiFeatureToggleRow(
                    icon: "tag.fill",
                    color: .accentColor,
                    title: "Content Tagging",
                    subtitle: settings.showTechnicalDetails ? "LLM-powered topic, action & object tagging" : "Labels each document's topics with Apple's model as it's added",
                    isOn: $settings.enableContentTagging
                )

                aiFeatureToggleRow(
                    icon: "magnifyingglass",
                    color: .accentColor,
                    title: "Spotlight Indexing",
                    subtitle: settings.showTechnicalDetails ? "System-wide search integration" : "Find your documents from Spotlight search",
                    isOn: $settings.enableSpotlightIndexing
                )

                aiFeatureToggleRow(
                    icon: "arrow.clockwise.circle.fill",
                    color: .accentColor,
                    title: "Background Maintenance",
                    subtitle: settings.showTechnicalDetails ? "Scheduled index health checks & Spotlight refresh" : "Checks the search index and refreshes Spotlight on a schedule",
                    isOn: $settings.enableBackgroundMaintenance
                )

                // These three were switches bound to `enableWritingTools`,
                // `enableSpeechAnalysis` and `enableTranslation`. Each key persisted to
                // UserDefaults and had **zero consumers** anywhere in the app, tests or
                // the extension — so flipping them changed nothing at all.
                //
                // The features themselves are real and always on, which is why these are
                // status rows now rather than deletions: Writing Tools ships through
                // `.writingToolsBehavior(.complete)` on the chat composer,
                // `SpeechAnalyzerService` runs inside `DocumentProcessor` for audio and
                // video, and `TranslationService` has live call sites. Removing the claim
                // would have withdrawn something true; removing the control removes
                // something false.
                aiFeatureInfoRow(
                    icon: "pencil.and.outline",
                    color: .secondary,
                    title: "Writing Tools",
                    subtitle: "Summarize, rewrite, proofread"
                )

                // Voice input is the chat field's dictation button (`VoiceDictation`), built in 5.7;
                // through 5.6 this line claimed it with no microphone code in the app. The Mac has the
                // button too since the audio-input entitlement went in (2026-10-14).
                aiFeatureInfoRow(
                    icon: "waveform",
                    color: .secondary,
                    title: "Speech Analysis",
                    subtitle: speechAnalysisSubtitle
                )

                aiFeatureInfoRow(
                    icon: "character.book.closed.fill",
                    color: .secondary,
                    title: "Translation",
                    subtitle: settings.showTechnicalDetails ? "Multilingual document analysis" : "Searches across languages when a library has a translation language set"
                )

                Divider().padding(.horizontal, DSSpacing.lg)

                // Smart Reply count stepper
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "number.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Smart Reply Count")
                            .font(.caption.weight(.medium))
                        Text("Suggestions per response")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: $settings.smartReplyCount, in: 1...5) {
                        Text("\(settings.smartReplyCount)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)

                Divider().padding(.horizontal, DSSpacing.lg)

                // Same as the three above: `enableScreenAwareness` and
                // `enableADM3Visuals` had no consumers, while the App Intents and the
                // Image Playground path they describe are registered and live.
                aiFeatureInfoRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    color: .secondary,
                    title: "Screen Awareness",
                    subtitle: settings.showTechnicalDetails ? "Seamless AppIntents integration via Shortcuts" : "Siri can tell which document or chat is on your screen"
                )

                aiFeatureInfoRow(
                    icon: "photo.on.rectangle.angled",
                    color: .secondary,
                    title: "Image Playground",
                    subtitle: settings.showTechnicalDetails
                        ? "Interactive ADM 3 image creation from document content"
                        : "Create an image from a document's content"
                )

                aiFeatureInfoRow(
                    icon: "lightbulb.max.fill",
                    color: .secondary,
                    title: "App Tips",
                    subtitle: settings.showTechnicalDetails ? "Contextual guidance & onboarding" : "Tips that point out features as you go"
                )

                aiFeatureInfoRow(
                    icon: "text.book.closed.fill",
                    color: .secondary,
                    // "Gazetteer" is NaturalLanguage's name for it (`NLGazetteer`), kept with Technical Details on (5.7).
                    title: settings.showTechnicalDetails ? "Gazetteer" : "Vocabulary",
                    subtitle: settings.showTechnicalDetails ? "Builds domain vocabulary during ingestion" : "Learns the special terms in your documents as they're added"
                )
            }
            .padding(.vertical, DSSpacing.xs)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
     }

    var siriIntegrationCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "siri")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Siri Voice Shortcuts")
                        .font(.headline)
                    Text("Speak directly to Siri without any manual setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(RAGAppShortcutsProvider.appShortcuts.count) shortcuts")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DSColors.readable(.green))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(DSSpacing.lg)

            Divider().padding(.horizontal, DSSpacing.lg)

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Instant Voice Phrases")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.md)

                VStack(spacing: DSSpacing.sm) {
                    #if os(iOS)
                        // Apple's own tip view: it shows the phrase Siri has registered for the
                        // action, in the person's language, so it cannot drift from the provider.
                        SiriTipView(intent: QueryDocumentsIntent())
                    #endif
                    // One row per App Shortcut, with the first phrase it registers
                    // (RAGAppShortcutsProvider). Keep the two in step.
                    shortcutCommandRow(title: "Ask My Documents", phrase: "Ask OpenIntelligence a question")
                    shortcutCommandRow(title: "List Documents", phrase: "List my documents in OpenIntelligence")
                    shortcutCommandRow(title: "Import Status", phrase: "Is OpenIntelligence still importing")
                    shortcutCommandRow(title: "Ask About a Document", phrase: "Ask OpenIntelligence about [Document Name]")
                    shortcutCommandRow(title: "Summarize a Document", phrase: "Summarize [Document Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Compare Two Documents", phrase: "Compare documents in OpenIntelligence")
                    shortcutCommandRow(title: "Ask a Library", phrase: "Ask [Library Name] in OpenIntelligence")
                    shortcutCommandRow(title: "Add a File", phrase: "Add this document to OpenIntelligence")
                    shortcutCommandRow(title: "Save a Web Page", phrase: "Save this page to OpenIntelligence")
                    shortcutCommandRow(title: "Find Passages", phrase: "Find passages in OpenIntelligence")
                }

                Divider().padding(.horizontal, DSSpacing.lg)

                Text(settings.showTechnicalDetails ? "Trust & Hallucination Prevention" : "Answers Are Checked")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, DSSpacing.lg)

                HStack(alignment: .top, spacing: DSSpacing.md) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(settings.showTechnicalDetails ? "Strict Verification Gates" : "The same checks as the chat")
                            .font(.subheadline.weight(.semibold))
                        // The actions ask through `RAGService.query`, the chat's own path and checks. "Needs Verification"
                        // is what `SourceOnlyAnswerService` puts in front of a drafted answer when its check abstains,
                        // with the reason; through 5.6 this said Siri returned a "dialog instead of hallucinating",
                        // which is not what happens (2026-10-20).
                        Text(
                            settings.showTechnicalDetails
                                ? "Siri and Shortcuts ask through RAGService.query, the chat's own pipeline and verification gates. When the source-only check abstains, the answer is prefixed with \"[Needs Verification]\" and its reason (SourceOnlyAnswerService)."
                                : "An answer from Siri or Shortcuts is checked against your documents the same way as one in the chat. When the last check can't back it, the answer starts with \"Needs Verification\" and says why.")
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: false)
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    var shortcutsAutomationCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "square.2.layers.3d")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Shortcuts App Integration")
                        .font(.headline)
                    Text("Custom automations & drag-and-drop actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Self.shortcutActionGroups.reduce(0) { $0 + $1.actions.count }) Actions Available")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(DSSpacing.lg)

            Divider().padding(.horizontal, DSSpacing.lg)

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("App Actions in Shortcuts Library")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.md)

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(Self.shortcutActionGroups, id: \.title) { group in
                        shortcutsActionGroup(title: group.title, actions: group.actions)
                    }
                    #if os(iOS)
                        // Opens the Shortcuts app on this app's actions.
                        ShortcutsLink()
                        #if DEBUG
                            .simultaneousGesture(
                                TapGesture().onEnded { VerificationJournal.record("settings.shortcutsLink") })
                        #endif
                            .shortcutsLinkStyle(.automaticOutline)
                            .frame(maxWidth: .infinity)
                    #endif
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    /// Every action the app gives Shortcuts, by the name Shortcuts shows, with what it does. The
    /// count on the card is the count of this list, and each line is a claim about an action's
    /// code: change both together. "Scan a Document" exists on iPhone and iPad only.
    private static var scanActionForThisPlatform: [String: String] {
        #if os(iOS)
            return ["Scan a Document": "Opens the app on the camera."]
        #else
            return [:]
        #endif
    }

    private static let shortcutActionGroups: [(title: String, actions: [String: String])] = [
        (
            "Add", [
                "Add to Library": "Adds a file, a web page or text to a library you choose.",
                "Add a File": "Adds a file to your active library.",
                "Save a Web Page": "Downloads a page and adds its text to your active library.",
                "Add a Document": "Opens the app on the file picker.",
            ].merging(scanActionForThisPlatform) { current, _ in current }
        ),
        (
            "Ask", [
                "Ask My Documents": "Answers a question from a library, in the mode you pick, and returns the answer with its sources.",
                "Ask About a Document": "Answers a question from one document only, in Standard.",
                "Ask a Library": "Answers a question from one library.",
                "Summarize a Document": "Writes a summary of one document.",
                "Compare Two Documents": "Compares what two documents say about a topic.",
                "Ask About an Image": "Reads the text in an image and answers a question about it.",
                "Search with a Photo": "Reads the text in a photo and asks your library about it.",
                "Check a Claim": "Says whether your active library holds up a sentence, and names the passage it checked.",
            ]
        ),
        (
            "Find and Open", [
                "Find Passages": "Returns the passages that match a search, without writing an answer.",
                "List Documents": "Returns the documents in your libraries, or in one.",
                "List Conversations": "Returns the saved conversations in a library.",
                "Open Library": "Opens the app on a library.",
                "Open Document": "Opens a document's page in its library.",
            ]
        ),
        (
            "Libraries and Conversations", [
                "Create Library": "Creates a library and returns it.",
                "Set Active Library": "Chooses the library that questions and imports use.",
                "Start a Conversation": "Opens the app on a new conversation.",
                "Export Conversation": "Returns a saved conversation as a Markdown, JSON Lines or PDF file.",
                "Delete Documents": "Deletes documents with their passages, after asking.",
            ]
        ),
        (
            "Settings", [
                "Set Answer Mode": "Sets the chat's answer mode: Standard, Deep Think or Maximum.",
                "Get Settings": "Returns the answer mode and the active library.",
            ]
        ),
        (
            "Status", [
                "Check Import Status": "Says whether imports are queued or running.",
                "Get Embedding Model": "Returns the name of the embedding model the active library uses.",
            ]
        ),
    ]

    private func shortcutsActionGroup(title: String, actions: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(actions.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(.caption.bold())
                            .foregroundStyle(DSColors.primaryText)
                            .frame(width: 170, alignment: .leading)
                        Text(actions[key] ?? "")
                            .font(.caption2)
                            .foregroundStyle(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: false)
                        Spacer()
                    }
                }
            }
            .padding(.leading, DSSpacing.sm)
        }
    }

    private func shortcutCommandRow(title: String, phrase: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(DSColors.secondaryText)
                Text("\"\(phrase)\"")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(DSColors.primaryText)
            }
            Spacer()
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = phrase
                #elseif canImport(AppKit)
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(phrase, forType: .string)
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    /// A toggleable Apple Intelligence feature row.
    @ViewBuilder
    private func aiFeatureToggleRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // The title is the switch's name for VoiceOver; `labelsHidden()` keeps it off the screen (5.7).
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(.accentColor)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    DSHaptics.selection()
                }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xs)
    }

    /// An info-only (always active) Apple Intelligence feature row.
    @ViewBuilder
    private func aiFeatureInfoRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Always On")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DSColors.readable(.green))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xs)
    }

}
