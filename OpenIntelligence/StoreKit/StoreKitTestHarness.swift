import Foundation

/// StoreKit test harness temporarily disabled to avoid simulator-only framework linking issues.
/// Re-enable once Apple resolves StoreKitTest framework auto-linking behavior.
@MainActor
enum StoreKitTestHarness {
    static func startIfNeeded() {
        #if DEBUG
        Log.info("StoreKit test harness disabled (linking issues with StoreKitTest framework)", category: .billing)
        #endif
    }
}
