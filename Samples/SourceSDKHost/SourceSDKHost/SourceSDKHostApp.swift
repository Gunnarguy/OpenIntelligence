import SwiftUI

@main
struct SourceSDKHostApp: App {
    var body: some Scene {
        WindowGroup {
            if SourceSDKHostRuntime.isRunningSmokeHarness {
                SourceSDKSmokeHarnessView()
            } else {
                ContentView()
            }
        }
    }
}
