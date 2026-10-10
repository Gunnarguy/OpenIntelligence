//
//  RedeemCodeEntry.swift
//  OpenIntelligence
//

import StoreKit
import SwiftUI

/// What came back from Apple's offer-code sheet.
nonisolated enum RedeemCodeOutcome: Equatable, Sendable {
    /// A code was redeemed and Apple handed back its transaction (iOS 27 and macOS 27).
    case redeemed
    /// The sheet closed. On iOS 26 and macOS 26 Apple does not say whether a code was redeemed.
    case closed
    case cancelled
    case failed(String)

    /// The line to show the person, or nil when there is nothing to say.
    var message: String? {
        switch self {
        case .redeemed: return "Your code was redeemed."
        case .closed, .cancelled: return nil
        case .failed(let reason): return "The code was not redeemed. \(reason)"
        }
    }

    /// Whether the app reads the App Store's entitlements again. Only after a redemption Apple
    /// handed back: when the sheet merely closed, nothing is known to have changed, and a redeemed
    /// transaction reaches the app through the `Transaction.updates` listener anyway.
    var readsEntitlementsAgain: Bool {
        self == .redeemed
    }

    init(error: Error) {
        if let storeError = error as? StoreKitError, case .userCancelled = storeError {
            self = .cancelled
        } else {
            self = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// Presents Apple's sheet for redeeming an offer code made in App Store Connect.
///
/// From iOS 27 and macOS 27 through `offerCodeRedemption(options:isPresented:onCompletion:)`, which
/// hands back the transaction the redemption produced. Before that through the call it replaces,
/// whose result only says the sheet was shown; the transaction then arrives through
/// `Transaction.updates`, which `StoreKitBillingService` already listens to.
private struct RedeemCodeSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onFinished: (RedeemCodeOutcome) -> Void

    func body(content: Content) -> some View {
        #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *) {
                content.offerCodeRedemption(options: [], isPresented: $isPresented) { result in
                    switch result {
                    case .success: onFinished(.redeemed)
                    case .failure(let error): onFinished(RedeemCodeOutcome(error: error))
                    }
                }
            } else {
                olderSheet(content)
            }
        #else
            olderSheet(content)
        #endif
    }

    private func olderSheet(_ content: Content) -> some View {
        content.offerCodeRedemption(isPresented: $isPresented) { result in
            switch result {
            case .success: onFinished(.closed)
            case .failure(let error): onFinished(RedeemCodeOutcome(error: error))
            }
        }
    }
}

extension View {
    func redeemCodeSheet(isPresented: Binding<Bool>, onFinished: @escaping (RedeemCodeOutcome) -> Void) -> some View {
        modifier(RedeemCodeSheet(isPresented: isPresented, onFinished: onFinished))
    }
}
