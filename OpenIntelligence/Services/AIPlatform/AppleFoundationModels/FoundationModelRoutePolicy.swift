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
        
        // 1. Check for manual user override
        switch config.fmPreference {
        case .core3B:
            return .onDevice
        case .advanced20B:
            return .onDeviceAdvanced
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
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                return .privateCloudCompute(reasoning: .none)
            } else {
                return .onDevice
            }
            
        case .deepThink:
            // 1. If it's too big, send to PCC
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            
            // 2. Prioritize local advanced model when the context fits
            if #available(iOS 27.0, macOS 27.0, *) {
                return .onDeviceAdvanced
            }
            
            // 3. Fallback to PCC for older OS if allowed
            if pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .moderate)
                }
            }
            return .onDeviceAdvanced
            
        case .maximum:
            // 1. If it's too big, send to PCC
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            
            // 2. Prioritize local advanced model when the context fits
            if #available(iOS 27.0, macOS 27.0, *) {
                return .onDeviceAdvanced
            }
            
            // 3. Fallback to PCC for older OS if allowed
            if pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            return .onDeviceAdvanced
        }
    }
}
#endif
