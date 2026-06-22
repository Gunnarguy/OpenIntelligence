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
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                Text("Share Item")
                    .font(.headline)
                
                if let url = activityItems.first(where: { $0 is URL }) as? URL {
                    ShareLink(item: url) {
                        Label("Share File", systemImage: "doc.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if let string = activityItems.first(where: { $0 is String }) as? String {
                    ShareLink(item: string) {
                        Label("Share Text", systemImage: "text.alignleft")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("No shareable content found.")
                        .foregroundColor(.secondary)
                }
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(32)
            .frame(width: 300)
        }
    }
#endif

#Preview {
    ActivityView(activityItems: ["Sample shared text from OpenIntelligence"])
}
