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
        let onDeviceLimit = 4096
        
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
