//
//  SharePreviewItem.swift
//  OpenIntelligence
//

import LinkPresentation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// What a share sheet shows above its apps for something the app shares: a title and the app's
/// icon (5.7).
///
/// Through 5.6 the header of a shared answer showed the answer's first line beside a generic text
/// icon, and Share the App showed a bare App Store address.
struct ShareSheetPreview: Equatable {
    let title: String
    /// The address named under the title. Only the header uses it; the items are shared as given.
    var url: URL?

    /// A shared answer. Its text already ends with the App Store link.
    static let answer = ShareSheetPreview(title: AnswerShareFormatter.attribution, url: nil)

    /// Share the App, in Settings.
    static let app = ShareSheetPreview(title: "OpenIntelligence", url: OpenIntelligenceLinks.sharedAppStoreURL)

    #if canImport(UIKit)
        /// The app's icon as the Home Screen shows it, from the bundle's primary icon.
        static var appIcon: UIImage? {
            guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
                let primary = icons["CFBundlePrimaryIcon"] as? [String: Any]
            else { return nil }
            let names =
                (primary["CFBundleIconFiles"] as? [String] ?? []).reversed()
                + [primary["CFBundleIconName"] as? String].compactMap { $0 }
            return names.lazy.compactMap { UIImage(named: $0) }.first
        }

        /// Metadata the share sheet reads for its header.
        func linkMetadata() -> LPLinkMetadata {
            let metadata = LPLinkMetadata()
            metadata.title = title
            if let url {
                metadata.originalURL = url
                metadata.url = url
            }
            if let icon = Self.appIcon {
                metadata.iconProvider = NSItemProvider(object: icon)
            }
            return metadata
        }
    #else
        static var appIcon: NSImage? { NSApplication.shared.applicationIconImage }
    #endif
}

#if canImport(UIKit)
    /// One shared item with the header a `ShareSheetPreview` describes. The item itself goes to
    /// every app unchanged.
    final class PreviewedShareItem: NSObject, UIActivityItemSource {
        let item: Any
        let preview: ShareSheetPreview

        init(_ item: Any, preview: ShareSheetPreview) {
            self.item = item
            self.preview = preview
        }

        func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
            item
        }

        func activityViewController(
            _: UIActivityViewController, itemForActivityType _: UIActivity.ActivityType?
        ) -> Any? {
            item
        }

        func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
            preview.linkMetadata()
        }

        /// The items a share sheet is given: the first carries the header, the rest go as they are.
        static func items(_ items: [Any], preview: ShareSheetPreview?) -> [Any] {
            guard let preview, let first = items.first else { return items }
            return [PreviewedShareItem(first, preview: preview)] + items.dropFirst()
        }
    }
#endif
