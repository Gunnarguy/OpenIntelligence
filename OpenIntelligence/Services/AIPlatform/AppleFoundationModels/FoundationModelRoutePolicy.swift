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

        // No plan means on device (5.7). Consent is asked only for a plan that requires it
        // (`RAGService.ensureCloudConsentIfNeeded` returns at once when the plan is nil), so a
        // planless request that reached Private Cloud Compute did so without the consent sheet.
        // This branch used to send one there under Hybrid when the prompt was over the device
        // window, and every time with Private Cloud Compute picked in the model picker, even on
        // Don't Allow. Planless callers are a question to a library with no documents,
        // `generateDirectChatResponse` and `DocumentSummaryService`'s fallback when the on-device model
        // is unavailable. A request
        // that should reach Private Cloud Compute has to carry a plan.
        //
        // `DeveloperDiagnosticsHubView` probes this function with a nil plan, so its
        // "Maximum Reasoning" row can only read N/A, and lines reading `type=maximum est=1000` come from it.
        Log.debug(
            "Route (no plan): type=\(queryType) est=\(estimatedContextTokens) -> onDevice",
            category: .llm
        )
        return .onDevice
    }
}
#endif
