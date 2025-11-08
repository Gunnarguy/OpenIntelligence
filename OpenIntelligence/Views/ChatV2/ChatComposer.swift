//
//  ChatComposer.swift
//  OpenIntelligence
//
//  Redesigned ChatV2 composer (scaffold) with auto-growing input and send
//  Created by Cline on 10/28/25.
//

import SwiftUI

struct ChatComposer: View {
    let isProcessing: Bool
    let onSend: (String) -> Void
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                TextField("Message AI...", text: $inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.bubble, style: .continuous)
                            .fill(DSColors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.bubble, style: .continuous)
                            .strokeBorder(
                                isInputFocused ? DSColors.accent.opacity(0.5) : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .focused($isInputFocused)
                    .disabled(isProcessing)
                    .animation(DSAnimations.fastEase, value: isInputFocused)
                
                Button(action: send) {
                    ZStack {
                        Circle()
                            .fill(canSend ? DSColors.accent : Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: isProcessing ? "stop.fill" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
                .animation(DSAnimations.fastEase, value: canSend)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(DSColors.background)
        }
        .onSubmit(send)
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

// MARK: - Preview

#Preview(traits: .sizeThatFitsLayout) {
    ChatComposer(isProcessing: false) { text in
        print("Send: \(text)")
    }
    .padding()
}
