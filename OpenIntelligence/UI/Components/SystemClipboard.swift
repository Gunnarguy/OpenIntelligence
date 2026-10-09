//
//  SystemClipboard.swift
//  OpenIntelligence
//

import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Writes plain text to the system clipboard on iPhone, iPad and Mac.
///
/// Four copy actions wrote through `UIPasteboard` inside `#if canImport(UIKit)` with no AppKit
/// branch, so on the Mac they showed "Copied" and wrote nothing. Every copy action goes through
/// here, so a new one cannot leave the Mac out.
enum SystemClipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
