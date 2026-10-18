//
//  ScanIntoLibraryIntent.swift
//  OpenIntelligence
//
//  Scan a page into a library from the Lock Screen (5.7).
//

#if os(iOS)
    import AppIntents
    import Foundation

    /// The "Scan into Library" control (5.7): it opens OpenIntelligence's capture extension (`OpenIntelligenceCapture`)
    /// from the Lock Screen, Control Center or the Action button, without unlocking. A photo taken there waits in the
    /// app's own data container, and the app adds it to the library that is open the next time it's in front
    /// (`LockedCaptureImport`). Apple's guide says a `CameraCaptureIntent` belongs in the app, the control's extension
    /// and the capture extension, so this file is compiled into all three ("Creating a camera experience for the Lock
    /// Screen", developer.apple.com, read 2026-10-17).
    @available(iOS 18.0, *)
    struct ScanIntoLibraryIntent: CameraCaptureIntent {
        static let title: LocalizedStringResource = "Scan into Library"
        static let description = IntentDescription(
            "Opens OpenIntelligence's camera without unlocking. The page you take is added to the library you have open the next time you open the app.")

        /// What the intent does when the system runs it in the app, which it does when the device isn't locked: Apple's
        /// guide has the control launch the capture extension "when the device is locked" and the intent's perform
        /// "deep link to the capture experience in your app". The app sets it at launch to open its own scanner, as
        /// "Scan Document" does; the extensions leave it unset (review of 2026-10-17).
        @MainActor static var openCaptureInApp: (() -> Void)?

        @MainActor
        func perform() async throws -> some IntentResult {
            Self.openCaptureInApp?()
            return .result()
        }
    }
#endif
