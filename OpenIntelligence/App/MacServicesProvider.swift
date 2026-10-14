//
//  MacServicesProvider.swift
//  OpenIntelligence
//

#if os(macOS)
    import AppKit

    /// The Mac's Services menu (5.7). Select text in any app and choose Ask OpenIntelligence or Add
    /// to OpenIntelligence; select files in Finder and choose Add to OpenIntelligence from Quick
    /// Actions or Services.
    ///
    /// `Info.plist` lists the three under `NSServices`. Each entry's `NSMessage` names a method here,
    /// which the system calls as `<message>:userData:error:` on the main thread.
    final class MacServicesProvider: NSObject {
        static let shared = MacServicesProvider()

        /// The selected text goes into the chat's field, not sent, so it can be read and changed
        /// first.
        @objc func askAboutSelection(
            _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
        ) {
            guard let text = Self.selectedText(on: pasteboard) else {
                error.pointee = "OpenIntelligence received no text." as NSString
                return
            }
            Log.info("[Services] Ask: \(text.count) characters", category: .ui)
            NSApplication.shared.activate()
            Self.showWindowIfNoneIsOpen(link: AppLink.url(for: .chat))
            AppNavigationRequest.post(.ask(text))
        }

        /// The selected text is kept as a note and imported like any file handed to the app.
        @objc func addSelectionToLibrary(
            _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
        ) {
            guard let text = Self.selectedText(on: pasteboard) else {
                error.pointee = "OpenIntelligence received no text." as NSString
                return
            }
            do {
                let note = try PastedContentStaging.storeText(text)
                Log.info("[Services] Add text: \(text.count) characters", category: .ingestion)
                NSApplication.shared.activate()
                Self.showWindowIfNoneIsOpen(link: AppLink.url(for: .documents))
                AppNavigationRequest.post(.importFiles([note]))
            } catch let failure {
                Log.error(
                    "[Services] The text could not be saved: \(failure.localizedDescription)", category: .ingestion)
                error.pointee = "OpenIntelligence couldn't save the text." as NSString
            }
        }

        /// Files selected in Finder, copied into the app off the main actor (a file in iCloud Drive
        /// that is not downloaded is downloaded while it is copied) and imported.
        @objc func addFilesToLibrary(
            _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
        ) {
            let files = Self.fileURLs(on: pasteboard)
            guard !files.isEmpty else {
                error.pointee = "OpenIntelligence received no files." as NSString
                return
            }
            NSApplication.shared.activate()
            Task {
                let staged = await ImportedFileStaging.copyIntoWorkspaceOffMainActor(files)
                Log.info("[Services] Add files: \(staged.count) of \(files.count) copied", category: .ingestion)
                guard !staged.isEmpty else { return }
                Self.showWindowIfNoneIsOpen(link: AppLink.url(for: .documents))
                AppNavigationRequest.post(.importFiles(staged))
            }
        }

        /// With every window closed the app keeps running and a request would wait for a window
        /// nobody opens. Opening one of the app's own links makes SwiftUI open a window for it.
        static func showWindowIfNoneIsOpen(link: URL) {
            guard !NSApplication.shared.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            NSWorkspace.shared.open(link)
        }

        /// The text a service was handed, trimmed, or nil when there is none.
        static func selectedText(on pasteboard: NSPasteboard) -> String? {
            guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return nil }
            return text
        }

        static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
            let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            return (objects as? [URL]) ?? []
        }
    }

    /// Hands the services to the system once the app has launched: "Service requests can arrive
    /// immediately after the service provider is set" (`NSApplication.servicesProvider`).
    final class OpenIntelligenceMacAppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.servicesProvider = MacServicesProvider.shared
        }
    }
#endif
