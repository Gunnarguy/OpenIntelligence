import SwiftUI

/// A sleek HUD overlay that visualizes the 7 Verification Gates of the RAG pipeline.
/// The gates light up sequentially as the query is processed. If the pipeline abstains
/// (e.g. fails a gate), that specific gate flashes red to prove active rejection of bad context.
struct VerificationGatesOverlayView: View {
    let events: [ThinkingEvent]

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

    @State private var gates: [VerificationGate] = [
        VerificationGate(id: 1, title: "Intent Formulation", kind: .intentRoute, secondaryKind: .planning),
        VerificationGate(id: 2, title: "Scope Validation", kind: .retrieval, secondaryKind: nil),
        VerificationGate(id: 3, title: "Density Threshold", kind: .vectorSearch, secondaryKind: .bm25),
        VerificationGate(id: 4, title: "RRF Confidence", kind: .rrf, secondaryKind: nil),
        VerificationGate(id: 5, title: "Compression Yield", kind: .compression, secondaryKind: nil),
        VerificationGate(id: 6, title: "Semantic Grounding", kind: .grounding, secondaryKind: .verification),
        VerificationGate(id: 7, title: "Agentic Policy", kind: .agentic, secondaryKind: .gating)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkerboard")
                    .foregroundColor(DSColors.accent)
                Text("Verification Pipeline")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DSColors.primaryText)
                
                Spacer()
                
                if let failureGate = gates.first(where: { if case .failed = $0.status { return true }; return false }) {
                    Text("ABSTAINED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.bottom, 4)

            ForEach(gates) { gate in
                GateRowView(gate: gate)
            }
        }
        .padding(12)
        .background(DSColors.surface.opacity(0.9))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DSColors.accent.opacity(0.3), lineWidth: 1)
        )
        .onChange(of: events.count) { _, _ in
            updateGateStatuses()
        }
        .onAppear {
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
            
            // Check if this gate's event has occurred
            if let index = events.firstIndex(where: { $0.kind == gate.kind || $0.kind == gate.secondaryKind }) {
                // Determine if it failed: look ahead for warnings/fallbacks immediately following
                let subsequentEvents = events[index...]
                if let failureEvent = subsequentEvents.first(where: { $0.kind == .warning || $0.kind == .fallback }) {
                    // Make sure the warning happened before the next gate (or there is no next gate)
                    let nextGateIndex = (i + 1 < newGates.count) ? events.firstIndex(where: { $0.kind == newGates[i+1].kind || $0.kind == newGates[i+1].secondaryKind }) : nil
                    
                    if let nextGateIdx = nextGateIndex, events.firstIndex(of: failureEvent)! < nextGateIdx {
                        newGates[i].status = .failed(reason: failureEvent.title)
                        hasFailed = true
                    } else if nextGateIndex == nil {
                        newGates[i].status = .failed(reason: failureEvent.title)
                        hasFailed = true
                    } else {
                        newGates[i].status = .passed
                    }
                } else {
                    // Check if it's the very last event currently processing
                    if index == events.count - 1 {
                        newGates[i].status = .processing
                    } else {
                        newGates[i].status = .passed
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
                .foregroundColor(textColor)
            
            Spacer()
            
            if case .failed(let reason) = gate.status {
                Text(reason)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch gate.status {
        case .pending:
            Circle()
                .stroke(DSColors.secondaryText.opacity(0.3), lineWidth: 1)
        case .processing:
            Circle()
                .fill(DSColors.accent)
                .overlay(
                    Circle()
                        .stroke(DSColors.accent, lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(0.3)
                )
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
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
    
    return VerificationGatesOverlayView(events: events)
        .padding()
        .background(Color.black)
}
