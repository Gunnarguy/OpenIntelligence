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
    /// `kind` names what was copied in the development journal (5.8, `clipboard.copy`): "answer" or "question".
    /// On the Mac the clipboard is read back, so the row "Copy on an answer does nothing on the Mac" closes on the
    /// write itself. On iPhone it isn't read: reading the clipboard can show the paste prompt.
    static func copy(_ text: String, kind: String? = nil) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
            let readBack = "notChecked"
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let readBack = VerificationJournal.isEnabled
                ? "\(NSPasteboard.general.string(forType: .string) == text)" : "notChecked"
        #endif
        if let kind {
            VerificationJournal.record(
                "clipboard.copy", ["kind": kind, "chars": "\(text.count)", "readBack": readBack])
        }
    }
}
