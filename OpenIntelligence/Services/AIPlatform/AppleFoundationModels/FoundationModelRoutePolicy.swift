//
//  FoundationModelRoutePolicy.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 16.0, *)
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
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            if pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .moderate)
                }
            }
            return .onDevice
            
        case .maximum:
            if estimatedContextTokens > onDeviceLimit && pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            if pccAllowed {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable && !pcc.quotaUsage.isLimitReached {
                    return .privateCloudCompute(reasoning: .deep)
                }
            }
            return .onDevice
        }
    }
}
#endif
