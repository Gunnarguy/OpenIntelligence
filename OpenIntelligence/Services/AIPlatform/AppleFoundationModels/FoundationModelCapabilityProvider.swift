import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
protocol FoundationModelCapabilityProviding: Sendable {
    func snapshot() async -> FoundationModelCapabilitySnapshot
}

@available(iOS 26.0, macOS 26.0, *)
struct LiveFoundationModelCapabilityProvider: FoundationModelCapabilityProviding {
    func snapshot() async -> FoundationModelCapabilitySnapshot {
        let localModel = SystemLanguageModel.default
        let localAvailable: Bool
        if case .available = localModel.availability {
            localAvailable = true
        } else {
            localAvailable = false
        }

        #if targetEnvironment(simulator)
        return FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: localAvailable,
            onDeviceContextSize: localModel.contextSize,
            supportsPCC: false,
            hasPCCEntitlement: false,
            pccAvailable: false,
            pccQuota: .unsupported,
            pccContextSize: nil,
            source: .sdkExact,
            unavailabilityReason: "PCC is unavailable in Simulator"
        )
        #else
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            let entitlement = EntitlementChecker.hasEntitlement(EntitlementChecker.privateCloudComputeKey)
            guard entitlement else {
                return FoundationModelCapabilitySnapshot(
                    supportsOnDevice: true,
                    onDeviceAvailable: localAvailable,
                    onDeviceContextSize: localModel.contextSize,
                    supportsPCC: true,
                    hasPCCEntitlement: false,
                    pccAvailable: false,
                    pccQuota: .unknown,
                    pccContextSize: nil,
                    source: .sdkExact,
                    unavailabilityReason: "Signed PCC entitlement is missing"
                )
            }

            let pcc = FoundationModels.PrivateCloudComputeLanguageModel()
            let quota: PCCQuotaState
            switch pcc.quotaUsage.status {
            case let .belowLimit(state):
                quota = state.isApproachingLimit ? .approachingLimit : .belowLimit
            case .limitReached:
                quota = .limitReached
            @unknown default:
                quota = .unknown
            }
            let available: Bool
            let reason: String?
            switch pcc.availability {
            case .available:
                available = true
                reason = nil
            case let .unavailable(unavailableReason):
                available = false
                reason = String(describing: unavailableReason)
            }
            let pccContextSize = try? await pcc.contextSize
            return FoundationModelCapabilitySnapshot(
                supportsOnDevice: true,
                onDeviceAvailable: localAvailable,
                onDeviceContextSize: localModel.contextSize,
                supportsPCC: true,
                hasPCCEntitlement: true,
                pccAvailable: available,
                pccQuota: quota,
                pccContextSize: pccContextSize,
                source: pccContextSize == nil ? .sdkPartial : .sdkExact,
                unavailabilityReason: reason
            )
        }
        #endif

        return FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: localAvailable,
            onDeviceContextSize: localModel.contextSize,
            supportsPCC: false,
            hasPCCEntitlement: false,
            pccAvailable: false,
            pccQuota: .unsupported,
            pccContextSize: nil,
            source: .sdkExact,
            unavailabilityReason: "PCC requires iOS/macOS 27"
        )
        #endif
    }
}
#endif
