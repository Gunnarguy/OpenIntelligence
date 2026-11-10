//
//  SettingsView+Modes.swift
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
    // MARK: - Generation Tuning Card

    @ViewBuilder
    private var generationTuningCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.below.square.filled.and.square")
                    .foregroundStyle(Color.accentColor)
                Text("Generation Tuning")
                    .font(.headline)
                Spacer()
            }

            Text("Customize how the AI responds to your questions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // System Prompt
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    Label("System Prompt", systemImage: "text.quote")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    // Reset button inline
                    if settings.systemPrompt != "You are a helpful assistant." {
                        Button {
                            withAnimation(DSAnimations.fastEase) {
                                settings.systemPrompt = "You are a helpful assistant."
                            }
                        } label: {
                            Text("Reset")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("You are a helpful assistant...", text: $settings.systemPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
                    .font(.caption)

                Text("Instructions given to the AI before each conversation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Retrieval Card Helpers

    private var modeAccentColor: Color {
        modeColor(for: settings.ragQualityMode.canonical)
    }

    private var modeHeaderIcon: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "flame.fill"
        case .deepThink: return "brain.head.profile.fill"
        default: return "bolt.circle.fill"
        }
    }

    private var modeHeaderTitle: String {
        switch settings.ragQualityMode.canonical {
        case .maximum: return "Maximum Highlights"
        case .deepThink: return "Deep Think Highlights"
        default: return "Standard Highlights"
        }
    }

    // MARK: - Retrieval Card

    @ViewBuilder
    var retrievalCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(Color.accentColor)
                Text("Intelligence Mode")
                    .font(.headline)
                Spacer()
            }

            Text("Choose how OpenIntelligence processes your questions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Mode Picker - Standard vs Deep Think
            VStack(spacing: DSSpacing.md) {
                ForEach(RAGQualityMode.userVisibleCases, id: \.id) { mode in
                    intelligenceModeRow(mode: mode, isSelected: settings.ragQualityMode.canonical == mode)
                        .onTapGesture {
                            guard canSelectMode(mode) else { return }
                            let previousMode = settings.ragQualityMode.canonical
                            withAnimation(DSAnimations.snappySpring) {
                                settings.ragQualityMode = mode
                            }
                            DSHaptics.selection()

                            // Reset Deep Think/Maximum metrics when switching modes
                            // to avoid stale confidence/step counts appearing in the UI
                            if previousMode != mode {
                                ragService.resetDeepThinkLiveMetrics()
                            }
                        }
                }
            }

            if settings.selectedModel == .onDeviceAnalysis {
                Text("Quotes only answers in Standard. Deep Think and Maximum need Apple's model to reason, so they run when you choose it under Apple Intelligence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The step-by-step list is the pipeline's own vocabulary, so it waits behind Technical Details (5.7 UI
            // cleanup); its lines are claims about code all the same (.claude/rules/user-facing-copy.md).
            if !settings.showTechnicalDetails {
                Text("Technical Details, in Appearance, lists the techniques behind the selected mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
            Divider()

            // Mode-specific features
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: modeHeaderIcon)
                        .foregroundStyle(modeAccentColor)
                        .font(.caption)
                    Text(modeHeaderTitle)
                        .font(.subheadline.weight(.medium))
                }

                // Data-driven feature list — avoids stack overflow from
                // 25+ inline featureRow calls generating a massive generic type.
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(currentModeFeatures) { feature in
                        if feature.isDivider {
                            Divider()
                                .padding(.vertical, DSSpacing.xs)
                        } else if feature.isWarning {
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(feature.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, DSSpacing.xs)
                        } else {
                            featureRow(icon: feature.icon, label: feature.label, description: feature.desc, color: feature.color)
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
            .background(modeAccentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            .animation(DSAnimations.fastEase, value: settings.ragQualityMode)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Feature List Data Model

    /// Lightweight value type for data-driven feature rows.
    /// Using ForEach with Identifiable items instead of 25+ inline @ViewBuilder
    /// calls prevents the compiler from generating a massive nested generic
    /// type, which was causing a stack overflow (___chkstk_darwin crash).
    private struct FeatureItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let desc: String
        let color: Color
        var isDivider: Bool = false
        var isWarning: Bool = false

        static func divider(id: String) -> FeatureItem {
            FeatureItem(id: id, icon: "", label: "", desc: "", color: .clear, isDivider: true)
        }

        static func warning(id: String, text: String) -> FeatureItem {
            FeatureItem(id: id, icon: "exclamationmark.triangle.fill", label: text, desc: "", color: .orange, isWarning: true)
        }
    }

    /// Build the feature list as data, not views.
    private var currentModeFeatures: [FeatureItem] {
        var items: [FeatureItem] = []

        // Common features (all modes)
        // "1,000x faster" was an unmeasured multiplier with no benchmark behind it, the
        // same class of claim as the `≈65 tok/s` figure removed from the capability card.
        // The algorithmic change is real; the number was never measured.
        items.append(.init(id: "fast-dedup", icon: "bolt.fill", label: "O(N) Fast Deduplication", desc: "Linear-time evidence dedup, so large libraries stay fast", color: .green))
        items.append(.init(id: "native-embed", icon: "cpu.fill", label: "Native Embeddings", desc: "MiniLM sentence embeddings on device, through Core ML or Core AI", color: .green))
        items.append(.init(id: "contextual-embed", icon: "doc.badge.gearshape", label: "Contextual Embeddings", desc: "Document title + section baked into every vector", color: .green))
        items.append(.init(id: "table-extract", icon: "tablecells", label: "Smart Table Extraction", desc: "iOS 26 Vision API preserves tables with captions", color: .green))
        items.append(.init(id: "entity-link", icon: "link", label: "Cross-Document Entity Linking", desc: "Global entity index finds related info across library", color: .green))
        items.append(.init(id: "parent-doc", icon: "doc.on.doc", label: "Parent Document Retrieval", desc: "Expands chunk window ±5 for full paragraph context", color: .green))
        items.append(.init(id: "query-understand", icon: "lightbulb", label: "Query Understanding", desc: "NLTagger resolves pronouns, NER extracts key entities", color: .green))
        items.append(.init(id: "hybrid-rrf", icon: "arrow.triangle.merge", label: "Hybrid Search + RRF", desc: "Vector + BM25 keyword search with Reciprocal Rank Fusion", color: .green))
        // The model name is documented provenance, not a guess. `ReRankerModel.mlpackage/Manifest.json`
        // declares no model family (a Core ML packaging artifact never carries one);
        // `THIRD_PARTY_NOTICES.md` binds the bundled artifact to its source, since 5.8
        // `ibm-granite/granite-embedding-reranker-english-r2` (Apache 2.0), which replaced
        // `cross-encoder/ms-marco-TinyBERT-L2-v2`. Check that file before changing the name.
        items.append(.init(id: "cross-encoder", icon: "arrow.up.arrow.down", label: "Cross-Encoder Reranking", desc: "IBM Granite cross-encoder scores query-document relevance on the Neural Engine", color: .green))
        items.append(.init(id: "mmr", icon: "shuffle", label: "MMR Diversification", desc: "Maximal Marginal Relevance for diverse results", color: .green))
        items.append(.init(id: "lost-middle", icon: "arrow.left.arrow.right", label: "Lost-in-Middle Mitigation", desc: "Best evidence at start AND end of context window", color: .green))
        items.append(.init(id: "raptor", icon: "tree", label: "RAPTOR-lite Summaries", desc: "Document-level summaries route overview queries", color: .green))
        // Only for the modes that use it: Standard never runs HyDE (`RAGQualityMode.usesHyDE`) (5.7).
        if settings.ragQualityMode.usesHyDE {
            items.append(.init(id: "hyde", icon: "sparkles", label: "HyDE Query Expansion", desc: "LLM generates hypothetical doc, embedded for cosine retrieval", color: .green))
        }

        // Deep Think only: Standard and Maximum keep the passages whole (`RAGQualityMode.usesContextualCompression`) (5.7).
        if settings.ragQualityMode.usesContextualCompression {
            items.append(.init(id: "compression", icon: "text.redaction", label: "Contextual Compression", desc: "LLM extracts query-relevant sentences from chunks", color: settings.ragQualityMode.usesAgenticOrchestrator ? .purple : .accentColor))
        }

        // Deep Think + Maximum shared
        if settings.ragQualityMode.usesAgenticOrchestrator {
            items.append(.divider(id: "div-agentic"))
            // "Dynamic Profiles" and "Model Judges" were listed here but neither
            // exists: `FoundationModelDynamicProfileRegistry` has zero call sites,
            // and there is no judge implementation anywhere in `Services/`. This
            // list is shown to users as what the active mode is doing, so an
            // unimplemented row is a false claim, not a roadmap teaser. Both are
            // tracked on the roadmap; re-add each one when it actually runs.
            if DeviceCapabilities.pccRoutingCompiledIn {
                items.append(.init(id: "pcc-escalation", icon: "cloud.lock.fill", label: "Private Cloud Compute", desc: "An answer too large for this device, or a Deep Think or Maximum answer from more than one document, can be written on Apple's servers with your permission", color: .purple))
            }
            items.append(.init(id: "native-spotlight", icon: "magnifyingglass", label: "Spotlight Indexing", desc: "Your documents are indexed into Apple Core Spotlight", color: .purple))
            items.append(.init(id: "intent-route", icon: "signpost.right.and.left", label: "Intent Routing", desc: "Classifies query as lookup/procedure/compare/summarize", color: .purple))
            items.append(.init(id: "multi-query", icon: "magnifyingglass.circle.fill", label: "Multi-Query Expansion", desc: "LLM generates diverse search queries for broader retrieval", color: .purple))
            items.append(.init(id: "graph-expand", icon: "point.3.connected.trianglepath.dotted", label: "2-Hop Graph Expansion", desc: "Entity-based traversal finds related chunks", color: .purple))
            items.append(.init(id: "recursive-loop", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Recursive Research Loop", desc: "Autonomous [SEARCH:]/[ANSWER] protocol until confident", color: .purple))
            items.append(.init(id: "verify-gates", icon: "checkmark.seal.fill", label: "Verification Gates A–I", desc: "9-stage anti-hallucination checks before answering (Confidence, Coverage, Numeric, Contradiction, Semantic, Quote, Quality, Completeness, Isolation)", color: .purple))
            items.append(.init(id: "confidence-cal", icon: "function", label: "Confidence Calibration", desc: "Sigmoid-calibrated scores from rerank + margin + evidence count", color: .purple))
            items.append(.init(id: "extract-summary", icon: "text.line.first.and.arrowtriangle.forward", label: "Extractive Summarization", desc: "Sentence selection via bi-encoder for summarize intent", color: .purple))
            items.append(.init(id: "graph-pack", icon: "rectangle.compress.vertical", label: "Graph Context Packing", desc: "Optimal token budget allocation across evidence", color: .purple))
            // Deep Think's chain stops at 8 sessions (`AgenticPolicyService`); the step count this line showed was the
            // orchestrator's, and it described Maximum with Deep Think's numbers. Maximum has its own line below (5.7).
            if !settings.ragQualityMode.isUnlimitedMode {
                items.append(.init(id: "orchestrator", icon: "brain.head.profile", label: "Agentic Orchestrator", desc: "Up to 8 sessions, aiming for \(Int(DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold * 100))% confidence on this device", color: .purple))
            }
            // No tool line here since 2026-10-14. It read "4 Tool Functions" while
            // `FoundationModelToolRegistry.createTools` registers six, and neither number
            // was true of these modes: every model call Deep Think and Maximum make passes
            // `disableTools: true` (the fourteen `generateWithProperConsent` calls in
            // `AgenticOrchestrator`, the chain sessions through `disableToolsForSession`),
            // so no tool reaches the model in them. Re-add a line when one does.
            items.append(.init(id: "iterative-ret", icon: "arrow.trianglehead.2.clockwise.rotate.90", label: "Iterative Retrieval", desc: "Retrieve → assess gaps → refine query → retrieve more", color: .purple))
        }

        // Maximum-exclusive
        if settings.ragQualityMode.isUnlimitedMode {
            items.append(.divider(id: "div-maximum"))
            if entitlementStore.hasUnlimitedMaximumMode {
                items.append(.init(id: "maximum-access", icon: "infinity", label: "Unlimited Maximum", desc: "No daily cap on your current plan", color: .orange))
            } else {
                items.append(.init(id: "maximum-access", icon: "calendar", label: "Maximum on Free", desc: "\(entitlementStore.maximumModeRemainingUses) of \(QuotaPolicy.freeMaximumModeDailyLimit) uses left today", color: .orange))
            }
            items.append(.init(id: "exhaustive", icon: "wand.and.stars", label: "Exhaustive Synthesis", desc: "Final pass synthesizes all session insights", color: .orange))
            // Was "200K+ Token Budget — 50 sessions × 4K". That multiplies out to a number
            // that reads like a context window and is not one: Maximum runs up to 50
            // *separate* 4K windows, it never holds 200K at once. The 50 is also a ceiling
            // rather than a typical run — `AgenticConfig.unlimited`'s own comment says
            // thermal will stop it first, and 4.9 added convergence stopping specifically
            // so it exits once it stops learning. Describe the mechanism, not a product.
            items.append(.init(id: "token-budget", icon: "cpu", label: "Up to 50 Sessions", desc: "Each gets a fresh window of the on-device model; stops early once it converges", color: .orange))
            items.append(.warning(id: "max-warning", text: "Can take several minutes. Use for complex research tasks."))
        } else if !settings.ragQualityMode.usesAgenticOrchestrator {
            items.append(.init(id: "conv-memory", icon: "brain.head.profile", label: "Conversation Memory", desc: "Remembers context across turns", color: .green))
        }

        return items
    }

    @ViewBuilder
    private func intelligenceModeRow(mode: RAGQualityMode, isSelected: Bool) -> some View {
        let accent = modeColor(for: mode)

        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 42, height: 42)
                    Image(systemName: mode.icon)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    // Plain by default; the pipeline's own words with Technical Details on (5.7).
                    Text(settings.showTechnicalDetails ? mode.description : plainModeSummary(for: mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }

            Text(modeCallout(for: mode))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: DSSpacing.xs) {
                ForEach(modeBadges(for: mode), id: \.self) { badge in
                    modeBadge(text: badge, color: accent)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(isSelected ? accent.opacity(0.08) : Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .stroke(isSelected ? accent.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func modeColor(for mode: RAGQualityMode) -> Color {
        switch mode.canonical {
        case .standard: return .accentColor
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .accentColor
        }
    }

    /// What a mode is for, in plain words, under its name (5.7 UI cleanup). Technical Details shows `description`.
    private func plainModeSummary(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard: return "Quick answers to everyday questions"
        case .deepThink: return "For comparisons and harder questions"
        case .maximum: return "For the hardest questions"
        default: return mode.displayName
        }
    }

    /// What a mode does, in plain words (5.7 UI cleanup), each a claim about code. Standard checks its answer with the
    /// verification gates and searches again only when the first search finds little (the retrieval cascade); it skips
    /// the source-only check when the gates pass, so it does not run "every check". Deep Think's reasoning chain stops at
    /// 8 sessions (`AgenticPolicyService`, `min(8, sessionCount + 4)`), but research rounds can follow it, so its badge
    /// names no number; its precision lookup answers without the gates, so it has no "checks" badge. Maximum's loop, when retrieval is good enough to
    /// reach it, stops when its findings stop changing, at 50 sessions at most and fewer when few passages match
    /// (`executeTrueUnlimitedReasoning`); its 0.98 target is unreachable by the code's own comment, so no "98%" here.
    private func modeCallout(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard:
            return "Searches your documents and checks the answer against them, searching again only when the first search finds little. The fastest mode."
        case .deepThink:
            return "Can search several times and build the answer in steps, for comparisons and questions that need more than one passage."
        case .maximum:
            let work = "Can make up to 50 passes over your documents, fewer when only a few passages match, and stops when its findings stop changing."
            if entitlementStore.hasUnlimitedMaximumMode {
                return "\(work) Slowest, with no daily limit on your plan."
            }
            return "\(work) Slowest. Free plans get \(QuotaPolicy.freeMaximumModeDailyLimit) a day, and you have \(entitlementStore.maximumModeRemainingUses) left today."
        default:
            return mode.description
        }
    }

    private func modeBadges(for mode: RAGQualityMode) -> [String] {
        switch mode.canonical {
        case .standard:
            return ["Fastest", "Checks its answer", "Best for lookups"]
        case .deepThink:
            return ["Several passes", "Best for analysis"]
        case .maximum:
            if entitlementStore.hasUnlimitedMaximumMode {
                return ["No daily limit", "Up to 50 passes", "Slowest"]
            }
            return ["\(QuotaPolicy.freeMaximumModeDailyLimit) a day", "\(entitlementStore.maximumModeRemainingUses) left today", "Up to 50 passes"]
        default:
            return []
        }
    }

    private func canSelectMode(_ mode: RAGQualityMode) -> Bool {
        guard mode.canonical == .maximum else { return true }
        guard !entitlementStore.canUseMaximumModeNow else { return true }
        planEntryPoint = .maximumModeLimit
        showPlanSheet = true
        return false
    }

    @ViewBuilder
    private func modeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func featureRow(icon: String, label: String, description: String, color: Color = .green) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(label)
                    .font(.caption.weight(.medium))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
