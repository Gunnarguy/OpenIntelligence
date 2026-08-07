//
//  FoundationModelRoutePolicy.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelRoutePolicy {
    
    enum QueryType {
        case exactLookup
        case standard
        case deepThink
        case maximum
    }

    static func determineRoute(
        queryType: QueryType,
        estimatedContextTokens: Int,
        config: InferenceConfig
    ) -> AppleFoundationModelRoute {
        if let plan = config.modelExecutionPlan {
            // A post-plan consent/quota failure may force the approved local
            // fallback while retaining the original plan for route telemetry.
            if config.executionContext == .onDeviceOnly,
               plan.fallback.target == .onDevice {
                return .onDevice
            }
            switch plan.synthesisTarget {
            case .deterministic, .onDevice, .abstain:
                return .onDevice
            case .privateCloudCompute:
                let reasoning: PCCReasoningLevel
                switch queryType {
                case .exactLookup, .standard: reasoning = .none
                case .deepThink: reasoning = .moderate
                case .maximum: reasoning = .deep
                }
                return .privateCloudCompute(reasoning: reasoning)
            }
        }
        
        // 1. Check for manual user override
        switch config.fmPreference.canonical {
        case .core3B, .advanced20B:
            return .onDevice
        case .privateCloudCompute:
            return .privateCloudCompute(reasoning: queryType == .standard ? .none : .deep)
        case .automatic:
            break // Fall through to dynamic hybrid routing
        }
        
        let pccAllowed = config.allowPrivateCloudCompute

        // Read the real on-device window rather than assuming 4096. This path is only
        // reached when no `ModelExecutionPlan` is attached; when one is, the switch
        // above returns from the plan, which is built with exact `model.tokenCount(for:)`
        // budgets. `contextSize(isAppleFMOnDevice:)` returns
        // `SystemLanguageModel.default.contextSize` on iOS/macOS 26+ and falls back to
        // the same 4096 this used to hardcode, so the fallback behavior is unchanged
        // and a device reporting a larger window now gets to use it.
        //
        // Callers must estimate `estimatedContextTokens` with the on-device chars/token
        // ratio, since this compares against an on-device limit. See `LLMService`.
        let onDeviceLimit = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)

        // The planless branch is otherwise invisible on device: `planID: "direct"` is posted in
        // the `ActiveModelRouteResolved` userInfo but every observer drops it, and `onDeviceLimit`
        // is never emitted. Without both, a device log showing an estimate next to a PCC route
        // cannot be attributed to this branch or checked against the threshold it actually
        // compared with, which is why the 4521-against-4096 log was inconclusive.
        //
        // Note `DeveloperDiagnosticsHubView` probes this function with a synthetic 1000 tokens and
        // a nil plan, so lines reading `type=maximum est=1000` come from that view, not a query.
        Log.debug(
            "Route (no plan): type=\(queryType) est=\(estimatedContextTokens) "
            + "onDeviceLimit=\(onDeviceLimit) pccAllowed=\(pccAllowed)",
            category: .llm
        )

        switch queryType {
        case .exactLookup:
            return .onDevice
            
        case .standard:
            if estimatedContextTokens > onDeviceLimit && pccAllowed && isPCCAvailable() {
                return .privateCloudCompute(reasoning: .none)
            }
            return .onDevice
            
        case .deepThink:
            // 1. If it's too big, send to PCC
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                if isPCCAvailable() {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            
            // 2. Prioritize local advanced model when the context fits
            return .onDevice
            
        case .maximum:
            // 1. If it's too big, send to PCC
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                if isPCCAvailable() {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            
            // 2. Prioritize local advanced model when the context fits
            return .onDevice
        }
    }
    
    private static func isPCCAvailable() -> Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            guard EntitlementChecker.hasEntitlement(EntitlementChecker.privateCloudComputeKey) else {
                return false
            }
            let pcc = FoundationModels.PrivateCloudComputeLanguageModel()
            return pcc.isAvailable && !pcc.quotaUsage.isLimitReached
        }
        #endif
        return false
    }
}
#endif
