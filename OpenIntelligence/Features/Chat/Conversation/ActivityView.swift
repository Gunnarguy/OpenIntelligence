import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif
#if os(macOS)
    import AppKit
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
            let controller = UIActivityViewController(
                activityItems: PreviewedShareItem.items(activityItems, preview: preview),
                applicationActivities: applicationActivities)
            // Where the share went (5.8 journal): Apple's activity id, or "thirdParty" for another app's (its id names
            // an app the person has), and whether a picture was in it.
            if VerificationJournal.isEnabled {
                let items = activityItems.count
                let png = activityItems.contains { ($0 as? URL)?.pathExtension.lowercased() == "png" }
                controller.completionWithItemsHandler = { activity, completed, _, error in
                    let id = activity?.rawValue
                    VerificationJournal.record(
                        "share.sheet", error != nil ? .failed : completed ? .ok : .cancelled,
                        ["activity": id.map { $0.hasPrefix("com.apple.") ? $0 : "thirdParty" } ?? "none",
                            "items": "\(items)", "png": "\(png)"])
                }
            }
            return controller
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

#if os(macOS)
    /// Apple's share menu at the pointer, in the window in front (5.8 Mac redesign). A Mac shares from a menu next to
    /// what is shared; the app opened a sheet holding one large Share button, so sharing took a sheet, a click and a
    /// dismissal.
    @MainActor
    enum MacSharing {
        static func present(_ items: [Any]) {
            guard let window = NSApp.keyWindow, let view = window.contentView, !items.isEmpty else { return }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: NSRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
            VerificationJournal.record("share.sheet", ["mac": "picker", "items": "\(items.count)"])
        }
    }

    /// A Save panel over the window for a file the app wrote, such as an exported conversation (5.8 Mac redesign): a
    /// Mac app saves an export where the person picks, where the app showed a sheet with a Share File button.
    @MainActor
    enum MacSavePanel {
        static func save(_ file: URL) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.lastPathComponent
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let destination = panel.url else {
                    VerificationJournal.record("export.saved", .cancelled, [:])
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: file, to: destination)
                    VerificationJournal.record("export.saved", .ok, ["ext": destination.pathExtension])
                } catch {
                    Log.error("[MacSavePanel] Save failed: \(error.localizedDescription)", category: .ui)
                    VerificationJournal.record("export.saved", .failed, ["ext": destination.pathExtension])
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { finish(response) } }
            } else {
                panel.begin { response in MainActor.assumeIsolated { finish(response) } }
            }
        }
    }
#endif

extension View {
    /// The share sheet on iPhone and iPad, and Apple's share menu at the pointer on a Mac (5.8), for whatever `item`
    /// is set to.
    func shareSheet<Item: Identifiable>(
        item: Binding<Item?>,
        items: @escaping (Item) -> [Any],
        preview: @escaping (Item) -> ShareSheetPreview? = { _ in nil }
    ) -> some View {
        #if os(macOS)
            onChange(of: item.wrappedValue?.id) { _, _ in
                guard let value = item.wrappedValue else { return }
                item.wrappedValue = nil
                MacSharing.present(items(value))
            }
        #else
            sheet(item: item) { value in
                ActivityView(activityItems: items(value), preview: preview(value))
            }
        #endif
    }
}
