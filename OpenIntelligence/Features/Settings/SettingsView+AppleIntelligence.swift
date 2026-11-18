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

    /// The Apple Intelligence features (2026-11-17, in Intelligence Mode's language): the four switches as compact
    /// rows, the reply count under Smart Replies, then the features that are always on as tiles. They were rows of
    /// one size with "Always on" printed at the end of seven of them, and checkboxes on the Mac.
    @ViewBuilder
    var appleIntelligenceFeaturesCard: some View {
        SurfaceCard {
            SettingsSectionHeader(
                icon: "apple.intelligence", title: "Apple Intelligence features",
                badge: "\(activeAIFeatureCount) of \(totalAIFeatureCount) on",
                badgeColor: activeAIFeatureCount == totalAIFeatureCount ? .green : .orange)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                SettingsGroupLabel(text: "YOU CAN TURN OFF")
                aiFeatureToggleRow(
                    icon: "text.bubble.fill",
                    title: "Smart Replies",
                    subtitle: settings.showTechnicalDetails ? "Conversational follow-up suggestions" : "Suggested follow-up questions under an answer",
                    isOn: $settings.enableSmartReplies
                )
                smartReplyCountRow
                aiFeatureToggleRow(
                    icon: "tag.fill",
                    title: "Content Tagging",
                    subtitle: settings.showTechnicalDetails ? "LLM-powered topic, action & object tagging" : "Labels each document's topics with Apple's model as it's added",
                    isOn: $settings.enableContentTagging
                )
                aiFeatureToggleRow(
                    icon: "magnifyingglass",
                    title: "Spotlight Indexing",
                    subtitle: settings.showTechnicalDetails ? "System-wide search integration" : "Find your documents from Spotlight search",
                    isOn: $settings.enableSpotlightIndexing
                )
                aiFeatureToggleRow(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Background Maintenance",
                    subtitle: settings.showTechnicalDetails ? "Scheduled index health checks & Spotlight refresh" : "Checks the search index and refreshes Spotlight on a schedule",
                    isOn: $settings.enableBackgroundMaintenance
                )
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                SettingsGroupLabel(text: "ALWAYS ON")
                // Writing Tools, Speech Analysis and Translation were switches bound to `enableWritingTools`,
                // `enableSpeechAnalysis` and `enableTranslation`, and Screen Awareness and Image Playground to
                // `enableScreenAwareness` and `enableADM3Visuals`. Each key persisted and had **zero consumers**, so
                // flipping them changed nothing. The features themselves are real and always on: Writing Tools ships
                // through `.writingToolsBehavior(.complete)` on the chat composer, `SpeechAnalyzerService` runs inside
                // `DocumentProcessor` for audio and video, `TranslationService` has live call sites, and the App
                // Intents and the Image Playground path are registered and live. Removing the claim would have
                // withdrawn something true; removing the control removed something false.
                SpecTileGrid(columns: 2) {
                    aiFeatureTile(icon: "pencil.and.outline", title: "Writing Tools", subtitle: "Summarize, rewrite, proofread")
                    // Voice input is the chat field's dictation button (`VoiceDictation`), built in 5.7; through 5.6
                    // this line claimed it with no microphone code in the app. The Mac has the button too since the
                    // audio-input entitlement went in (2026-10-14).
                    aiFeatureTile(icon: "waveform", title: "Speech Analysis", subtitle: speechAnalysisSubtitle)
                    aiFeatureTile(
                        icon: "character.book.closed.fill", title: "Translation",
                        subtitle: settings.showTechnicalDetails ? "Multilingual document analysis" : "Searches across languages when a library has a translation language set")
                    aiFeatureTile(
                        icon: "rectangle.inset.filled.and.person.filled", title: "Screen Awareness",
                        subtitle: settings.showTechnicalDetails ? "App Intents integration via Shortcuts" : "Siri can tell which document or chat is on your screen")
                    aiFeatureTile(
                        icon: "photo.on.rectangle.angled", title: "Image Playground",
                        subtitle: settings.showTechnicalDetails ? "Image Playground, seeded with document content" : "Create an image from a document's content")
                    aiFeatureTile(
                        icon: "lightbulb.max.fill", title: "App Tips",
                        subtitle: settings.showTechnicalDetails ? "Contextual guidance & onboarding" : "Tips that point out features as you go")
                    aiFeatureTile(
                        icon: "text.book.closed.fill",
                        // "Gazetteer" is NaturalLanguage's name for it (`NLGazetteer`), kept with Technical Details on (5.7).
                        title: settings.showTechnicalDetails ? "Gazetteer" : "Vocabulary",
                        subtitle: settings.showTechnicalDetails ? "Builds domain vocabulary during ingestion" : "Learns the special terms in your documents as they're added")
                }
            }
        }
    }

    /// How many suggestions Smart Replies shows, under its switch; dimmed while Smart Replies is off.
    private var smartReplyCountRow: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "arrow.turn.down.right")
                .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .semibold)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text("Suggestions per answer")
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
            Spacer(minLength: DSSpacing.sm)
            Stepper(value: $settings.smartReplyCount, in: 1...5) {
                Text("\(settings.smartReplyCount)")
                    .scaledFont(size: 12, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.readable(.accentColor))
            }
            .fixedSize()
            .accessibilityLabel("Smart Reply suggestions per answer")
            .accessibilityValue("\(settings.smartReplyCount)")
        }
        .padding(.leading, DSSpacing.lg)
        .disabled(!settings.enableSmartReplies)
        .opacity(settings.enableSmartReplies ? 1 : 0.45)
    }

    /// The Siri & Shortcuts page (2026-11-16): the panel, the phrases to say, one Open in Shortcuts button, then every
    /// action folded. It was two cards: this one, with the phrase count in a pill and again in the panel, and a
    /// Shortcuts card whose two-column table of every action repeated phrases above it (Add a File, Save a Web Page).
    var siriIntegrationCard: some View {
        let actionCount = Self.shortcutActionGroups.reduce(0) { $0 + $1.actions.count }
        return SurfaceCard {
            // What Siri and Shortcuts can do, counted from the same lists the rows below are drawn from (5.8).
            SettingsStatusPanel(
                symbol: "siri", title: "Works without setup", badge: "No setup", badgeColor: .green,
                blocks: [
                    .init(
                        symbol: "waveform", name: "Voice phrases", color: .purple,
                        figure: "\(RAGAppShortcutsProvider.appShortcuts.count)", share: nil, caption: "say them to Siri"),
                    .init(
                        symbol: "square.2.layers.3d", name: "Actions", color: .blue,
                        figure: "\(actionCount)", share: nil, caption: "in Shortcuts"),
                    .init(
                        symbol: "checkmark.shield", name: "Checked", color: .green, figure: "Yes", share: nil,
                        caption: "same as chat"),
                ]
            )

            SectionHeader(icon: "waveform", title: "Say to Siri")

            VStack(spacing: DSSpacing.sm) {
                #if os(iOS)
                    // Apple's own tip view: it shows the phrase Siri has registered for the
                    // action, in the person's language, so it cannot drift from the provider.
                    SiriTipView(intent: QueryDocumentsIntent())
                #endif
                // One row per App Shortcut, with the first phrase it registers
                // (RAGAppShortcutsProvider). Keep the two in step.
                shortcutCommandRow(symbol: "questionmark.bubble", title: "Ask My Documents", phrase: "Ask OpenIntelligence a question")
                shortcutCommandRow(symbol: "list.bullet", title: "List Documents", phrase: "List my documents in OpenIntelligence")
                shortcutCommandRow(symbol: "arrow.down.circle", title: "Import Status", phrase: "Is OpenIntelligence still importing")
                shortcutCommandRow(symbol: "doc.text.magnifyingglass", title: "Ask About a Document", phrase: "Ask OpenIntelligence about [Document Name]")
                shortcutCommandRow(symbol: "text.alignleft", title: "Summarize a Document", phrase: "Summarize [Document Name] in OpenIntelligence")
                shortcutCommandRow(symbol: "square.split.2x1", title: "Compare Two Documents", phrase: "Compare documents in OpenIntelligence")
                shortcutCommandRow(symbol: "books.vertical", title: "Ask a Library", phrase: "Ask [Library Name] in OpenIntelligence")
                shortcutCommandRow(symbol: "plus.circle", title: "Add a File", phrase: "Add this document to OpenIntelligence")
                shortcutCommandRow(symbol: "safari", title: "Save a Web Page", phrase: "Save this page to OpenIntelligence")
                shortcutCommandRow(symbol: "text.magnifyingglass", title: "Find Passages", phrase: "Find passages in OpenIntelligence")
            }

            #if os(iOS)
                // Opens the Shortcuts app on this app's actions: the page's one button.
                ShortcutsLink()
                #if DEBUG
                    .simultaneousGesture(
                        TapGesture().onEnded { VerificationJournal.record("settings.shortcutsLink") })
                #endif
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            #endif

            // Every action, folded: the phrases above are the ones people use, and this list is for building a
            // shortcut. It was a table open on the page, 27 rows long.
            FoldedDetails(title: "All \(actionCount) actions in Shortcuts") {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(Self.shortcutActionGroups, id: \.title) { group in
                        shortcutsActionGroup(title: group.title, actions: group.actions)
                    }
                }
            }

            Divider()

            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(settings.showTechnicalDetails ? "Strict Verification Gates" : "The same checks as the chat")
                        .font(.subheadline.weight(.medium))
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(DSColors.secondaryText)
            
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(actions.keys.sorted(), id: \.self) { key in
                    // Name over description (2026-11-16): a fixed 170-point name column left the descriptions a
                    // narrow strip on an iPhone.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(key)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColors.primaryText)
                        Text(actions[key] ?? "")
                            .font(.caption)
                            .foregroundStyle(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// One phrase: what it does, then the words to say, with a copy button. The action leads, in the label
    /// color, and the phrase sits under it in the system font (5.8; it was a grey title over a monospaced
    /// quotation, which read as a list of code).
    private func shortcutCommandRow(symbol: String, title: String, phrase: String) -> some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.pill, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                Text("\u{201C}\(phrase)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DSSpacing.sm)
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
            .accessibilityLabel("Copy the phrase for \(title)")
        }
    }

    /// A switch, as a compact row in Intelligence Mode's type: the symbol, the name, one line under it.
    @ViewBuilder
    private func aiFeatureToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(isOn.wrappedValue ? Color.primary : Color.secondary)
                Text(subtitle)
                    .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DSSpacing.sm)
            // The title is the switch's name for VoiceOver; `labelsHidden()` keeps it off the screen (5.7). A switch
            // on the Mac too, where a toggle defaults to a checkbox.
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                #if os(macOS)
                    .controlSize(.small)
                #endif
                .tint(.accentColor)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    DSHaptics.selection()
                }
        }
    }

    /// A feature that is always on, as a tile (`AlwaysOnFeatureTile`).
    private func aiFeatureTile(icon: String, title: String, subtitle: String) -> some View {
        AlwaysOnFeatureTile(icon: icon, title: title, subtitle: subtitle)
    }

}

/// A feature that is always on, as a tile on the neutral fill every Settings block uses. Its own view, so it reads the
/// colour scheme itself: a pushed Settings page is drawn from a copy of `SettingsView` whose environment is fixed at push.
private struct AlwaysOnFeatureTile: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Text(Image(systemName: icon)).foregroundStyle(Color.accentColor)) \(title)")
                .scaledFont(size: 11, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip + 2, style: .continuous)
                .fill(SettingsStatusPanel.blockFill(dark: colorScheme == .dark))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), always on. \(subtitle)")
    }
}
