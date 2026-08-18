//
//  SourceChipsView.swift
//  OpenIntelligence
//
//  Compact chips that summarize retrieved sources with similarity percent.
//  Polished with staggered animations, quality indicators, and modern styling.
//  Created by Cline on 10/28/25.
//

import SwiftUI

struct SourceChipsView: View {
    let chunks: [RetrievedChunk]
    let onTap: () -> Void
    
    /// Stagger animation for chips appearing
    @State private var appearedCount: Int = 0
    
    private var topChips: [ChipData] {
        let top = chunks.prefix(6) // show up to 6 chips
        return top.enumerated().map { (i, c) in
            let pct = max(0, min(1, Double(c.similarityScore)))
            return ChipData(
                index: i + 1,
                percent: pct,
                tint: similarityColor(pct),
                sourceName: c.sourceDocument,
                quality: qualityTier(pct)
            )
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(Array(topChips.enumerated()), id: \.element.id) { index, chip in
                    SourceChip(chip: chip, onTap: onTap)
                        .opacity(index < appearedCount ? 1.0 : 0.0)
                        .offset(x: index < appearedCount ? 0 : 20)
                        .animation(
                            DSAnimations.snappySpring.delay(Double(index) * 0.05),
                            value: appearedCount
                        )
                }
                
                // "More" indicator if truncated
                if chunks.count > 6 {
                    MoreChip(remaining: chunks.count - 6, onTap: onTap)
                        .opacity(appearedCount >= topChips.count ? 1.0 : 0.0)
                        .animation(
                            DSAnimations.snappySpring.delay(0.35),
                            value: appearedCount
                        )
                }
            }
            .padding(.vertical, DSSpacing.xxs)
        }
        .onAppear {
            // Stagger chip appearance
            withAnimation {
                appearedCount = topChips.count + 1
            }
        }
        .accessibilityLabel("Retrieved \(chunks.count) sources")
    }
    
    // MARK: - Helpers
    
    private func similarityColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.65 { return .orange }
        if score >= 0.5 { return .yellow }
        return .red
    }
    
    private func qualityTier(_ score: Double) -> String {
        if score >= 0.8 { return "High" }
        if score >= 0.65 { return "Good" }
        if score >= 0.5 { return "Fair" }
        return "Low"
    }
}

// MARK: - Individual Chip

private struct SourceChip: View {
    let chip: ChipData
    let onTap: () -> Void
    
    
    var body: some View {
        Button(action: {
            DSHaptics.light()
            onTap()
        }) {
            HStack(spacing: DSSpacing.xxs) {
                // Quality dot indicator
                Circle()
                    .fill(chip.tint)
                    .frame(width: 5, height: 5)
                
                // Source label
                Text("#\(chip.index)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(chip.tint)
                
                // Similarity percentage
                Text("\(Int(chip.percent * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DSColors.secondaryText)
            }
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DSColors.chipBackground(for: chip.tint))
            )
            .overlay(
                Capsule()
                    .strokeBorder(chip.tint.opacity(0.25), lineWidth: 0.5)
            )
        }
        // Press feedback comes from the ButtonStyle, not from a zero-duration long-press
        // gesture. These chips sit in a horizontal ScrollView, and a SwiftUI gesture attached
        // there competes with UIKit's scroll pan with no way to arbitrate between them: a press
        // that drifts a few points either scrolls or registers, unpredictably. `ButtonStyle`
        // reads `configuration.isPressed` from the button's own recognizer, which UIKit already
        // arbitrates against the scroll view, so scrolling wins until the press resolves.
        //
        // Same defect and same fix as the library chips in `ContainerPicker`. The visual is
        // unchanged: identical 0.95 scale and 0.1s easeInOut.
        .buttonStyle(SourceChipPressStyle())
        .accessibilityLabel("Source \(chip.index), \(chip.quality) match at \(Int(chip.percent * 100)) percent")
    }
}

// MARK: - Press Feedback

/// Scale-on-press for the source chips, driven by the button's own recognizer.
///
/// Exists so the chips do not need a gesture of their own. See the note at the call site: a
/// SwiftUI gesture inside a horizontal ScrollView cannot be arbitrated against the scroll pan,
/// and a ButtonStyle gets that arbitration from UIKit for free.
private struct SourceChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - More Chip

private struct MoreChip: View {
    let remaining: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            DSHaptics.light()
            onTap()
        }) {
            HStack(spacing: 3) {
                Text("+\(remaining)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(DSColors.accent)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DSColors.chipBackground(for: DSColors.accent))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(remaining) more sources, tap to view all")
    }
}

// MARK: - Data Model

private struct ChipData: Identifiable {
    let id = UUID()
    let index: Int
    let percent: Double
    let tint: Color
    let sourceName: String
    let quality: String
}

// MARK: - Preview

#Preview {
    let dummyChunks: [RetrievedChunk] = (0..<5).map { i in
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(),
                content: "Lorem ipsum \(i)",
                embedding: [],
                metadata: ChunkMetadata(chunkIndex: i, startPosition: 0, endPosition: 10)
            ),
            similarityScore: Float(0.5 + Double(i) * 0.1),
            rank: i,
            sourceDocument: "Doc \(i)",
            pageNumber: i + 1
        )
    }
    return SourceChipsView(chunks: dummyChunks) {}
        .padding()
}
