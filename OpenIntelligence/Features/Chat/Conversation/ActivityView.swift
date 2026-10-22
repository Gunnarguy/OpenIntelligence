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
        /// The title and icon the sheet shows above its apps (5.7).
        var preview: ShareSheetPreview? = nil

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(
                activityItems: PreviewedShareItem.items(activityItems, preview: preview),
                applicationActivities: applicationActivities)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {
            // No-op.
        }
    }
#else
    struct ActivityView: View {
        let activityItems: [Any]
        /// The title and icon the share menu shows for the item (5.7).
        var preview: ShareSheetPreview? = nil
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: DSSpacing.xl) {
                Image(systemName: "square.and.arrow.up")
                    .scaledFont(size: 32)
                    .foregroundStyle(DSColors.accent)
                
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
                    if let preview, let icon = ShareSheetPreview.appIcon {
                        ShareLink(item: string, preview: SharePreview(preview.title, icon: Image(nsImage: icon))) {
                            Label("Share Text", systemImage: "text.alignleft")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        ShareLink(item: string) {
                            Label("Share Text", systemImage: "text.alignleft")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Text("No shareable content found.")
                        .foregroundStyle(.secondary)
                }
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(DSSpacing.xxl)
            .frame(width: 300)
        }
    }
#endif

#Preview {
    ActivityView(activityItems: ["Sample shared text from OpenIntelligence"])
}
