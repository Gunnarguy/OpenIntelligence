//
//  CaptureViewfinder.swift
//  OpenIntelligenceCapture
//
//  Scan a page into a library from the Lock Screen (5.7).
//

import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The capture extension's screen (5.7): the camera, a new one after each saved page and after Cancel, and a line that
/// says how many pages wait for the app.
struct CaptureScreen: View {
    let session: LockedCameraCaptureSession
    /// A new picker after each saved page and after Cancel. The picker otherwise stays on the page it showed, so a second
    /// Use Photo after a cancelled unlock saved the same page twice, and Cancel, with no presenter to dismiss the
    /// picker, did nothing (review of 2026-10-17).
    @State private var picker = 0
    @State private var saved = 0

    var body: some View {
        CaptureViewfinder(session: session) { didSave in
            if didSave { saved += 1 }
            picker += 1
        }
        .id(picker)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if saved > 0 {
                Text(
                    saved == 1
                        ? "Page saved. It's added to your library when you open OpenIntelligence."
                        : "\(saved) pages saved. They're added to your library when you open OpenIntelligence."
                )
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 56)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
            }
        }
    }
}

/// The camera: Apple's `UIImagePickerController`, which handles the hardware buttons the way a capture extension has
/// to or the system ends it soon after launch (developer.apple.com, "Creating a camera experience for the Lock
/// Screen", read 2026-10-17). Photos only. Use Photo writes a JPEG to the session's folder and asks the system to open
/// the app, which asks to unlock first; the app adds the page to the library that is open.
struct CaptureViewfinder: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    /// Called when a page was saved (true) or the picker was cancelled (false); the screen then shows a new picker.
    let onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let session: LockedCameraCaptureSession
        private let onFinished: (Bool) -> Void

        init(session: LockedCameraCaptureSession, onFinished: @escaping (Bool) -> Void) {
            self.session = session
            self.onFinished = onFinished
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                onFinished(false)
                return
            }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = session.sessionContentURL.appendingPathComponent("Scan \(stamp).jpg")
            do {
                try data.write(to: file, options: .atomic)
            } catch {
                onFinished(false)
                return
            }
            onFinished(true)
            let session = session
            Task {
                // Unlocks first if the device is locked; a failure leaves the page waiting for the next time the app
                // is opened.
                try? await session.openApplication(
                    for: NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinished(false)
        }
    }
}
