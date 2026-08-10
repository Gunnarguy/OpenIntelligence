import SwiftUI

/// A sleek HUD overlay that visualizes the 7 Verification Gates of the RAG pipeline.
/// The gates light up sequentially as the query is processed. If the pipeline abstains
/// (e.g. fails a gate), that specific gate flashes red to prove active rejection of bad context.
struct VerificationGatesOverlayView: View {
    let events: [ThinkingEvent]
    var qualityMode: RAGQualityMode? = nil

    // The 7 Gates defined for the visualization
    enum GateStatus: Equatable {
        case pending
        case processing
        case passed
        case failed(reason: String)
    }

    struct VerificationGate: Identifiable {
        let id: Int
        let title: String
        let kind: ThinkingEvent.Kind
        let secondaryKind: ThinkingEvent.Kind?
        var status: GateStatus = .pending
    }

    @State private var gates: [VerificationGate] = []

    private func initialGates() -> [VerificationGate] {
        let mode = qualityMode?.canonical ?? .standard
        switch mode {
        case .standard:
            return [
                VerificationGate(id: 1, title: "Intent Formulation", kind: .intentRoute, secondaryKind: .planning),
                VerificationGate(id: 2, title: "Scope Validation", kind: .retrieval, secondaryKind: .context),
                VerificationGate(id: 3, title: "Data Confidence", kind: .rrf, secondaryKind: .confidence),
                VerificationGate(id: 4, title: "Semantic Grounding", kind: .grounding, secondaryKind: .verification)
            ]
        case .deepThink:
            return [
                VerificationGate(id: 1, title: "Intent Formulation", kind: .intentRoute, secondaryKind: .planning),
                VerificationGate(id: 2, title: "HyDE Generation", kind: .hyde, secondaryKind: .queryRewrite),
                VerificationGate(id: 3, title: "Vector & BM25", kind: .vectorSearch, secondaryKind: .bm25),
                VerificationGate(id: 4, title: "RRF Fusion", kind: .rrf, secondaryKind: nil),
                VerificationGate(id: 5, title: "MMR Diversity", kind: .mmr, secondaryKind: nil),
                VerificationGate(id: 6, title: "Compression", kind: .compression, secondaryKind: nil),
                VerificationGate(id: 7, title: "Semantic Grounding", kind: .grounding, secondaryKind: .verification),
                VerificationGate(id: 8, title: "Agentic Loop", kind: .iterative, secondaryKind: .agentic)
            ]
        case .maximum:
            return [
                VerificationGate(id: 1, title: "Intent Formulation", kind: .intentRoute, secondaryKind: .planning),
                VerificationGate(id: 2, title: "HyDE & Expansion", kind: .hyde, secondaryKind: .queryRewrite),
                VerificationGate(id: 3, title: "Broad Retrieval", kind: .vectorSearch, secondaryKind: .bm25),
                VerificationGate(id: 4, title: "RRF Fusion", kind: .rrf, secondaryKind: nil),
                VerificationGate(id: 5, title: "MMR & Re-rank", kind: .mmr, secondaryKind: .rerank),
                VerificationGate(id: 6, title: "Semantic Grounding", kind: .grounding, secondaryKind: .verification),
                VerificationGate(id: 7, title: "Maximum Confidence", kind: .gating, secondaryKind: .confidence),
                VerificationGate(id: 8, title: "Agentic Policy", kind: .agentic, secondaryKind: .iterative)
            ]
        default:
            return [
                VerificationGate(id: 1, title: "Intent Formulation", kind: .intentRoute, secondaryKind: .planning),
                VerificationGate(id: 2, title: "Scope Validation", kind: .retrieval, secondaryKind: nil),
                VerificationGate(id: 3, title: "RRF Confidence", kind: .rrf, secondaryKind: nil),
                VerificationGate(id: 4, title: "Semantic Grounding", kind: .grounding, secondaryKind: .verification)
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkerboard")
                    .foregroundStyle(DSColors.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Verification Pipeline")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DSColors.primaryText)
                
                Spacer()
                
                if gates.contains(where: { if case .failed = $0.status { return true }; return false }) {
                    Text("ABSTAINED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.gradient)
                        .cornerRadius(4)
                        .transition(.blurReplace)
                }
            }
            .padding(.bottom, 4)

            ForEach(gates) { gate in
                GateRowView(gate: gate)
            }
        }
        .padding(12)
        .background(DSColors.surface.opacity(0.6))
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DSColors.accent.opacity(0.3), lineWidth: 1)
        )
        .onChange(of: events.count) { _, _ in
            updateGateStatuses()
        }
        .onChange(of: qualityMode) { _, _ in
            self.gates = initialGates()
            updateGateStatuses()
        }
        .onAppear {
            if gates.isEmpty {
                self.gates = initialGates()
            }
            updateGateStatuses()
        }
    }

    private func updateGateStatuses() {
        var newGates = gates
        var hasFailed = false
        
        for i in 0..<newGates.count {
            if hasFailed {
                newGates[i].status = .pending
                continue
            }
            
            let gate = newGates[i]
            
            if let index = events.firstIndex(where: { $0.kind == gate.kind || $0.kind == gate.secondaryKind }) {
                // Determine if it failed: look ahead for warnings immediately following
                let subsequentEvents = events[index...]
                
                var nextGateIndex: Int? = nil
                for j in (i + 1)..<newGates.count {
                    if let idx = events.firstIndex(where: { $0.kind == newGates[j].kind || $0.kind == newGates[j].secondaryKind }) {
                        nextGateIndex = idx
                        break
                    }
                }
                
                // If a subsequent gate was reached, this gate definitively passed
                if nextGateIndex != nil {
                    newGates[i].status = .passed
                } else {
                    // No subsequent gate reached yet. Check if a warning caused an abstention.
                    if let failureEvent = subsequentEvents.first(where: { $0.kind == .warning }) {
                        newGates[i].status = .failed(reason: failureEvent.title)
                        hasFailed = true
                    } else {
                        // Check if it's the very last event currently processing
                        if index == events.count - 1 {
                            newGates[i].status = .processing
                        } else {
                            newGates[i].status = .passed
                        }
                    }
                }
            } else {
                newGates[i].status = .pending
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.gates = newGates
        }
    }
}

struct GateRowView: View {
    let gate: VerificationGatesOverlayView.VerificationGate
    
    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 14, height: 14)
            
            Text("Gate \(gate.id): \(gate.title)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor)
            
            Spacer()
            
            if case .failed(let reason) = gate.status {
                Text(reason)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(1)
                    .transition(.blurReplace)
            }
        }
        .sensoryFeedback(trigger: gate.status) { oldValue, newValue in
            if newValue == .passed && oldValue != .passed {
                return .success
            } else if isFailed(newValue) && !isFailed(oldValue) {
                return .error
            }
            return nil
        }
    }
    
    private func isFailed(_ status: VerificationGatesOverlayView.GateStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch gate.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(DSColors.secondaryText.opacity(0.3))
        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(DSColors.accent)
                .symbolEffect(.rotate, options: .repeating)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: gate.status == .passed)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, value: isFailed(gate.status))
        }
    }
    
    private var textColor: Color {
        switch gate.status {
        case .pending: return DSColors.secondaryText.opacity(0.5)
        case .processing: return DSColors.accent
        case .passed: return DSColors.primaryText
        case .failed: return .red
        }
    }
}

#Preview {
    let events = [
        ThinkingEvent(kind: .intentRoute, title: "Intent Resolved"),
        ThinkingEvent(kind: .retrieval, title: "Scopes Loaded"),
        ThinkingEvent(kind: .vectorSearch, title: "Hits Identified"),
        ThinkingEvent(kind: .rrf, title: "RRF Fusion Started"),
        ThinkingEvent(kind: .warning, title: "Insufficient RRF Confidence")
    ]
    
    return VerificationGatesOverlayView(events: events, qualityMode: .deepThink)
        .padding()
        .background(Color.black)
}
