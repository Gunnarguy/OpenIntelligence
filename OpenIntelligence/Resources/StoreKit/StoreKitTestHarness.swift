import Foundation

/// Public demo build keeps the StoreKit harness as an intentional no-op.
@MainActor
enum StoreKitTestHarness {
    static func startIfNeeded() {
        // Intentionally disabled in the public demo snapshot.
    }
}
