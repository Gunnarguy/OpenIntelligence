import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// SwiftUI wrapper around `UIActivityViewController` (Share Sheet).
///
/// Used for sharing chat messages and user-generated report payloads.
#if canImport(UIKit)
    struct ActivityView: UIViewControllerRepresentable {
        let activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {
            // No-op.
        }
    }
#else
    struct ActivityView: View {
        let activityItems: [Any]

        var body: some View {
            Text("Sharing is unavailable on this platform.")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
#endif

#Preview {
    ActivityView(activityItems: ["Sample shared text from OpenIntelligence"])
}
