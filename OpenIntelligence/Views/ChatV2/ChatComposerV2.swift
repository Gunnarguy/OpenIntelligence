//
//  ChatComposerV2.swift
//  OpenIntelligence
//
//  Modern composer with glass morphism, action buttons, and fluid animations
//

import SwiftUI

struct ChatComposerV2: View {
    let isProcessing: Bool
    let onSend: (String) -> Void
    let onStop: (() -> Void)?
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var textHeight: CGFloat = 40
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
                    
                    // Attachment hint (future feature)
                    if inputText.isEmpty && !isProcessing {
                        Button(action: {}) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .disabled(true) // Future feature
                        .opacity(0.5)
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
    
    private func send() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isProcessing else { return }
        onSend(query)
        inputText = ""
        isInputFocused = false
        DSHaptics.selection()
    }
}

#Preview {
    VStack {
        Spacer()
        ChatComposerV2(isProcessing: false, onSend: { _ in }, onStop: nil)
    }
    .background(DSColors.background)
}
