#if DEBUG && canImport(StoreKitTest) && !os(iOS)
import Foundation
import StoreKitTest

/// Lightweight helper that keeps the StoreKit local testing session alive for the app lifetime.
/// Debug builds load `StoreKitConfiguration.storekit` so the billing UI has predictable data without
/// depending on App Store Connect.
@MainActor
enum StoreKitTestHarness {
    private static var session: SKTestSession?

    /// Starts the StoreKit test session once per launch.
    /// Safe to call multiple times; subsequent invocations are ignored.
    static func startIfNeeded() {
        guard session == nil else { return }
        guard let url = Bundle.main.url(forResource: "StoreKitConfiguration", withExtension: "storekit") else {
            Log.warning("StoreKit configuration file missing from bundle", category: .billing)
            TelemetryCenter.emitBillingEvent(
                "StoreKit test session missing config",
                severity: .warning,
                metadata: ["file": "StoreKitConfiguration.storekit"]
            )
            return
        }

        do {
            let testSession = try SKTestSession(contentsOf: url)
            testSession.disableDialogs = true
            testSession.clearTransactions()
            testSession.resetToDefaultState()
            session = testSession
            Log.info("StoreKit test session ready", category: .billing)
            TelemetryCenter.emitBillingEvent("StoreKit test session ready")
        } catch {
            Log.error("Failed to start StoreKit test session: \(error.localizedDescription)", category: .billing)
            TelemetryCenter.emitBillingEvent(
                "StoreKit test session failed",
                severity: .error,
                metadata: ["reason": error.localizedDescription]
            )
        }
    }
}
#else
@MainActor
enum StoreKitTestHarness {
    static func startIfNeeded() {
        Log.warning("StoreKit test harness unavailable on this platform", category: .billing)
    }
}
#endif
