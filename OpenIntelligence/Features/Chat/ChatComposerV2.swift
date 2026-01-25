//
//  ChatComposerV2.swift
//  OpenIntelligence
//
//  Modern composer with glass morphism, action buttons, and fluid animations
//

import PhotosUI
import SwiftUI

struct ChatComposerV2: View {
    let isProcessing: Bool
    let onSend: (String) -> Void
    let onStop: (() -> Void)?
    let onAttach: (([URL]) -> Void)?

    /// Combined send with attachments - processes attachments BEFORE sending query
    /// If provided, this is used instead of separate onAttach + onSend calls
    let onSendWithAttachments: ((String, [URL]) -> Void)?

    /// Callback for Vision Capture (advanced camera with live OCR)
    var onVisionCapture: (() -> Void)? = nil

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var textHeight: CGFloat = 40

    // Attachment state
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        return (hasText || hasAttachments) && !isProcessing
    }

    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview row
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            AttachmentPreviewChip(attachment: attachment) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                }
                                DSHaptics.light()
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.primary.opacity(0.02))
            }

            // Subtle top divider
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 12) {
                // Text input with glass effect
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .lineLimit(1...8)
                        .font(.system(size: 16))
                        .focused($isInputFocused)
                        .disabled(isProcessing)
                        .padding(.vertical, 12)
                        .padding(.leading, 16)

                    // Attachment button with menu
                    if !isProcessing {
                        AttachmentMenuButton(
                            onSelectDocument: {
                                showDocumentPicker = true
                                DSHaptics.selection()
                            },
                            onSelectPhoto: {
                                showPhotoPicker = true
                                DSHaptics.selection()
                            },
                            onTakePhoto: {
                                showCamera = true
                                DSHaptics.selection()
                            },
                            onVisionCapture: onVisionCapture,
                            isCameraAvailable: isCameraAvailable
                        )
                        .padding(.trailing, 12)
.padding(.bottom, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    isInputFocused ? DSColors.accent.opacity(0.4) : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )
                .animation(.easeOut(duration: 0.15), value: isInputFocused)

                // Send / Stop button
                Button(action: isProcessing ? (onStop ?? {}) : send) {
                    ZStack {
                        Circle()
                            .fill(buttonBackground)
                            .frame(width: 44, height: 44)

                        if isProcessing {
                            // Stop icon
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white)
                                .frame(width: 14, height: 14)
                        } else {
                            // Send arrow
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isProcessing)
                .scaleEffect(canSend || isProcessing ? 1.0 : 0.9)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .onSubmit(send)
.sheet(isPresented: $showDocumentPicker) {
    ExtendedDocumentPicker { urls in
        handlePickedFiles(urls, type: .document)
    }
}
.sheet(isPresented: $showPhotoPicker) {
    PhotoPicker { urls in
        handlePickedFiles(urls, type: .photo)
    }
}
.fullScreenCover(isPresented: $showCamera) {
    CameraPicker { url in
        if let url = url {
            handlePickedFiles([url], type: .camera)
        }
    }
    .ignoresSafeArea()
}
    }

    private var buttonBackground: some ShapeStyle {
        if isProcessing {
            return AnyShapeStyle(Color.red.opacity(0.9))
        } else if canSend {
            return AnyShapeStyle(DSColors.accent)
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.3))
        }
    }

    private func handlePickedFiles(_ urls: [URL], type: ChatAttachment.AttachmentType) {
        for url in urls {
            let thumbnail = generateThumbnail(for: url)
            let attachment = ChatAttachment(url: url, type: type, thumbnail: thumbnail)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pendingAttachments.append(attachment)
            }
        }
        DSHaptics.success()
    }

    private func send() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = pendingAttachments.map { $0.url }
        let hasAttachments = !urls.isEmpty

        // Determine the final query text
        let finalQuery: String
        if !query.isEmpty {
            finalQuery = query
        } else if hasAttachments {
            // Default prompt when only attachments are provided
            finalQuery = "Analyze the attached content and summarize the key information."
        } else {
            return // Nothing to send
        }

        // Use combined callback if available (preferred - waits for attachments)
        if let onSendWithAttachments = onSendWithAttachments {
            onSendWithAttachments(finalQuery, urls)
        } else {
            // Legacy path: fire attachments separately (race condition prone)
            if hasAttachments {
                onAttach?(urls)
            }
            onSend(finalQuery)
        }

        // Clear state
        pendingAttachments.removeAll()
        inputText = ""
        isInputFocused = false
        DSHaptics.selection()
    }
}

// MARK: - Convenience initializers

extension ChatComposerV2 {
    /// Legacy initializer for backward compatibility (no attachment support)
    init(isProcessing: Bool, onSend: @escaping (String) -> Void, onStop: (() -> Void)?) {
        self.isProcessing = isProcessing
        self.onSend = onSend
        self.onStop = onStop
        self.onAttach = nil
        self.onSendWithAttachments = nil
    }

    /// Standard initializer with separate attachment handling (legacy)
    init(
        isProcessing: Bool,
        onSend: @escaping (String) -> Void,
        onStop: (() -> Void)?,
        onAttach: (([URL]) -> Void)?
    ) {
        self.isProcessing = isProcessing
        self.onSend = onSend
        self.onStop = onStop
        self.onAttach = onAttach
        self.onSendWithAttachments = nil
    }

    /// Preferred initializer: combined send with attachments (waits for processing)
    init(
        isProcessing: Bool,
        onSend: @escaping (String) -> Void,
        onStop: (() -> Void)?,
        onSendWithAttachments: @escaping (String, [URL]) -> Void
    ) {
        self.isProcessing = isProcessing
        self.onSend = onSend
        self.onStop = onStop
        self.onAttach = nil
        self.onSendWithAttachments = onSendWithAttachments
    }
}

#Preview {
    VStack {
        Spacer()
        ChatComposerV2(
            isProcessing: false,
            onSend: { _ in },
            onStop: nil,
            onSendWithAttachments: { query, urls in
                print("Query: \(query), Attachments: \(urls.count)")
            }
        )
    }
    .background(DSColors.background)
}
