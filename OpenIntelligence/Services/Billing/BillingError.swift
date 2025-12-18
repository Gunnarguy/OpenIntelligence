import Foundation

/// Billing-specific error wrapper so UI can surface friendly messages.
struct BillingError: LocalizedError {
    enum Reason {
        case productUnavailable
        case purchaseInProgress
        case verificationFailed
        case storeKitError(Error)
        case unknown
    }

    let product: BillingProduct
    let reason: Reason
    let underlyingError: Error?

    init(product: BillingProduct, reason: Reason, underlyingError: Error? = nil) {
        self.product = product
        self.reason = reason
        self.underlyingError = underlyingError
    }

    var errorDescription: String? {
        switch reason {
        case .productUnavailable:
            return "That product isn't available right now."
        case .purchaseInProgress:
            return "A purchase is already in progress for this product."
        case .verificationFailed:
            return "We couldn't verify the App Store receipt."
        case let .storeKitError(error):
            return Self.userFacingStoreKitMessage(for: error)
        case .unknown:
            return "Something went wrong during the purchase."
        }
    }
}

// MARK: - StoreKit/NSError decoding

private extension BillingError {
    /// StoreKit frequently wraps the actionable error inside one or more layers of NSError
    /// (e.g. ASDErrorDomain → underlying AMSErrorDomain). Surfacing the right message makes
    /// debugging sandbox/account permission issues much faster.
    static func userFacingStoreKitMessage(for error: Error) -> String {
        let resolved = resolveInnermostNSError(from: error as NSError)

        // StoreKit/AMS commonly nests the real message inside AMSServerPayload.
        if let payloadMessage = extractAMSServerPayloadMessage(from: resolved), !payloadMessage.isEmpty {
            return payloadMessage
        }

        // Prefer Apple-provided UI messages when available.
        if let customerMessage = resolved.userInfo["customerMessage"] as? String, !customerMessage.isEmpty {
            return customerMessage
        }
        if let debugDescription = resolved.userInfo[NSDebugDescriptionErrorKey] as? String, !debugDescription.isEmpty {
            // This is often the only string that contains the true reason.
            return debugDescription
        }
        if let description = resolved.userInfo["AMSDescription"] as? String, !description.isEmpty {
            return description
        }

        // Sandbox purchase permission failures can otherwise collapse into "Unable to Complete Request".
        if isSandboxPurchaseNotAuthorized(resolved) {
            return "This Apple Account isn't authorized to make in-app purchases in Sandbox right now. Check the Sandbox tester permissions in App Store Connect (or use Xcode's StoreKit Configuration for local purchases)."
        }

        return resolved.localizedDescription
    }

    /// Attempts to extract a user-facing message from the AMSServerPayload userInfo.
    /// Observed payload shape (as NSDictionary):
    /// - customerMessage: String
    /// - dialog: { message: String, explanation: String }
    static func extractAMSServerPayloadMessage(from error: NSError) -> String? {
        guard let payload = error.userInfo["AMSServerPayload"] else { return nil }

        // The payload is typically an NSDictionary.
        if let dict = payload as? [String: Any] {
            return messageFrom(payloadDictionary: dict)
        }
        if let dict = payload as? NSDictionary {
            var swiftDict: [String: Any] = [:]
            for (key, value) in dict {
                if let key = key as? String {
                    swiftDict[key] = value
                }
            }
            return messageFrom(payloadDictionary: swiftDict)
        }

        // Some OS versions may serialize as JSON-ish data or string. Try best-effort parsing.
        if let data = payload as? Data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return messageFrom(payloadDictionary: obj)
        }
        if let string = payload as? String {
            // Last resort: attempt to pick out the obvious substring.
            if let range = string.range(of: "not authorized", options: [.caseInsensitive, .diacriticInsensitive]) {
                // Return a small window around the match.
                let start = string.index(range.lowerBound, offsetBy: -min(40, string.distance(from: string.startIndex, to: range.lowerBound)), limitedBy: string.startIndex) ?? string.startIndex
                let end = string.index(range.upperBound, offsetBy: min(80, string.distance(from: range.upperBound, to: string.endIndex)), limitedBy: string.endIndex) ?? string.endIndex
                return String(string[start ..< end])
            }
        }

        return nil
    }

    static func messageFrom(payloadDictionary dict: [String: Any]) -> String? {
        if let message = dict["customerMessage"] as? String, !message.isEmpty {
            return message
        }
        if let dialog = dict["dialog"] as? [String: Any] {
            if let message = dialog["message"] as? String, !message.isEmpty {
                return message
            }
            if let explanation = dialog["explanation"] as? String, !explanation.isEmpty {
                return explanation
            }
        }
        if let dialog = dict["dialog"] as? NSDictionary {
            if let message = dialog["message"] as? String, !message.isEmpty {
                return message
            }
            if let explanation = dialog["explanation"] as? String, !explanation.isEmpty {
                return explanation
            }
        }
        return nil
    }

    static func resolveInnermostNSError(from error: NSError) -> NSError {
        var current = error
        var safetyCounter = 0
        while safetyCounter < 8 {
            safetyCounter += 1
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = next
        }
        return current
    }

    static func isSandboxPurchaseNotAuthorized(_ error: NSError) -> Bool {
        // Observed:
        // - ASDErrorDomain Code=500 with underlying AMSErrorDomain Code=305
        // - AMSServerPayload contains "You are not authorized..." (Sandbox)
        if error.domain == "AMSErrorDomain", error.code == 305 { return true }

        if let debugDescription = error.userInfo[NSDebugDescriptionErrorKey] as? String {
            if debugDescription.localizedCaseInsensitiveContains("not authorized") {
                return true
            }
            if debugDescription.localizedCaseInsensitiveContains("Sandbox") {
                return true
            }
        }

        return false
    }
}
