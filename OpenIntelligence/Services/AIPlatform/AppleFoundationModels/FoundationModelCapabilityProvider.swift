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
        // The window the answer is planned against keeps its last real reading (5.8, 2026-11-19). `contextSize` reads 0
        // while the model is unavailable, which it is for an app in the background, and the plan then sized the answer
        // for no window at all: on the owner's iPhone "How many bags are allowed per person?" asked as he left was
        // written from a cut-down context through the one-value path and answered "$200 per person" (the insurance
        // table's baggage-delay row), where the same question in front answered "one checked bag per person, plus one
        // carry-on and one personal item" from the same 13 passages (11:23:48 and 11:25:55).
        let onDeviceContextSize = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
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
            onDeviceContextSize: onDeviceContextSize,
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
                    onDeviceContextSize: onDeviceContextSize,
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
                onDeviceContextSize: onDeviceContextSize,
                supportsPCC: true,
                hasPCCEntitlement: true,
                pccAvailable: available,
                pccQuota: quota,
                pccContextSize: pccContextSize,
                source: pccContextSize == nil ? .sdkPartial : .sdkExact,
                unavailabilityReason: reason
            )
        }
        // This build has Private Cloud Compute and the system is older than 27. Through 5.6 this
        // case fell through to the sentence below, so Settings on iOS 26 said the build was compiled
        // without it (5.7).
        #if os(macOS)
        let reasonWithoutPCC = "Private Cloud Compute needs macOS 27"
        #else
        let reasonWithoutPCC = "Private Cloud Compute needs iOS 27 or iPadOS 27"
        #endif
        #else
        let reasonWithoutPCC = "This build was compiled without Private Cloud Compute (requires Xcode 27)"
        #endif

        return FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: localAvailable,
            onDeviceContextSize: onDeviceContextSize,
            supportsPCC: false,
            hasPCCEntitlement: false,
            pccAvailable: false,
            pccQuota: .unsupported,
            pccContextSize: nil,
            source: .sdkExact,
            // Names the build when the compiler gate removed PCC from this binary, and the system
            // when the build has it and the system is too old (`reasonWithoutPCC` above).
            unavailabilityReason: reasonWithoutPCC
        )
        #endif
    }
}
#endif
