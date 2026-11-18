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
    // MARK: - Intelligence Mode

    /// The Intelligence Mode page (5.8): `IntelligenceModeCard`, in the Compute Profile card's style, with the context
    /// window that used to sit on Device & Performance. Replaced a list of 28 techniques shown behind Technical Details
    /// that named four steps no mode runs (HyDE, contextual compression, extractive summarization, cross-document
    /// entity linking) and put Standard-only steps under Deep Think and Maximum; the trace is in the card's header.
    @ViewBuilder
    var retrievalCard: some View {
        // One card on the page (2026-11-16): it was a page card holding a grey section holding this card, three
        // surfaces deep, under a header that repeated the page's title. The panel at the card's top names the mode,
        // and Maximum's daily use on a free plan, which rode in that header's badge, is a line under the card's content.
        SurfaceCard {
            IntelligenceModeCard(
                mode: settings.ragQualityMode.canonical,
                windowTokens: FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true),
                windowDescription: onDeviceWindowDescription,
                modelName: onDeviceModelName,
                cloudWindow: cloudWindowForModeCard,
                deepThinkTarget: Int(DeviceCapabilityService.shared.optimizedAgenticConfig().confidenceThreshold * 100),
                maximumLimit: entitlementStore.hasUnlimitedMaximumMode
                    ? nil
                    : "\(entitlementStore.maximumModeRemainingUses) of \(QuotaPolicy.freeMaximumModeDailyLimit) left",
                privateCloudComputeCompiledIn: DeviceCapabilities.pccRoutingCompiledIn,
                callout: { modeCallout(for: $0) },
                onSelect: { mode in
                    guard canSelectMode(mode) else { return }
                    let previousMode = settings.ragQualityMode.canonical
                    withAnimation(DSAnimations.snappySpring) {
                        settings.ragQualityMode = mode
                    }
                    // Reset Deep Think/Maximum metrics when switching modes
                    // to avoid stale confidence/step counts appearing in the UI
                    if previousMode != mode {
                        ragService.resetDeepThinkLiveMetrics()
                    }
                }
            )

            // The callout keeps two lines in every mode, so the free plan's count is a line of its own.
            if settings.ragQualityMode.canonical == .maximum, !entitlementStore.hasUnlimitedMaximumMode {
                Text("Maximum: \(entitlementStore.maximumModeRemainingUses) of \(QuotaPolicy.freeMaximumModeDailyLimit) runs left today on the free plan.")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.selectedModel == .onDeviceAnalysis {
                // Quotes only is set by the app, not chosen: it is the model when Apple's isn't available here
                // (`SettingsStore` at launch). The line said to choose Apple's model on a page that has no chooser.
                Text("Quotes only, used while Apple's model isn't available on this device, answers in Standard. Deep Think and Maximum need Apple's model to reason.")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What a mode does, in plain words, each a claim about code (traced 2026-11-10). Standard searches again only when
    /// the first search finds little (the retrieval cascade) and withholds an answer that fails its checks. Deep Think's
    /// chain stops at 8 sessions (`AgenticPolicyService`, `min(8, sessionCount + 4)`), and research rounds can follow it.
    /// Maximum's loop stops when its findings stop changing, at 50 sessions at most and fewer when few passages match
    /// (`executeTrueUnlimitedReasoning`); its 0.98 target is unreachable by the code's own comment, so no "98%" here.
    private func modeCallout(for mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .standard:
            return "Checks the answer against your documents, and searches more when the first search is thin. The fastest."
        case .deepThink:
            return "Searches up to 5 phrasings and can build the answer in a chain of sessions, for comparisons and questions that need several passages."
        case .maximum:
            // The daily limit is a How Much tile (5.8), so this stays two lines like the other modes.
            return "After its strongest searches, up to 50 sessions over the passages found, stopping when its findings settle. Usually the slowest."
        default:
            return mode.description
        }
    }

    private func canSelectMode(_ mode: RAGQualityMode) -> Bool {
        guard mode.canonical == .maximum else { return true }
        guard !entitlementStore.canUseMaximumModeNow else { return true }
        planEntryPoint = .maximumModeLimit
        showPlanSheet = true
        return false
    }

}
