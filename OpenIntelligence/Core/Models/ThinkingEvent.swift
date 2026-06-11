import Foundation

/// Represents a single step in the assistant's "thinking" timeline.
/// These events are surfaced in the chat UI so users can see how the
/// RAG pipeline is progressing (embedding, retrieval, gating, etc.).
struct ThinkingEvent: Identifiable, Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        // Core pipeline stages
        case planning
        case embedding
        case retrieval
        case rerank
        case gating
        case context
        case generation
        case fallback
        case warning

        // Advanced RAG techniques (transparency layer)
        case hyde           // Hypothetical Document Embeddings
        case queryRewrite   // Query reformulation/expansion
        case bm25           // Keyword search (Okapi BM25)
        case vectorSearch   // Semantic/neural search
        case rrf            // Reciprocal Rank Fusion
        case mmr            // Maximal Marginal Relevance (diversity)
        case parentDoc      // Parent Document Retrieval (sibling expansion)
        case compression    // Contextual Compression
        case lostInMiddle   // Lost-in-Middle reordering
        case grounding      // Answer grounding verification
        case selfRag        // Self-RAG reflection/critique
        case iterative      // Iterative retrieval refinement
        case agentic        // Agentic orchestration step
        case toolCall       // Function/tool invocation
        case factBank       // FactBank update (Maximum mode)
        case reasoning      // Model-side thinking (e.g. O1/O3 reasoning blocks)

        // AppleRAG Advanced Features
        case verification   // Verification gates (anti-hallucination)
        case graphPack      // Graph-based context packing
        case extractive     // Extractive summarization
        case intentRoute    // Answer intent routing
        case confidence     // Calibrated confidence calculation

        // Creative Features
        case imagePlayground // Image Playground concept extraction pipeline

        /// Maps each kind to a system icon for quick visual scanning.
        nonisolated var systemIconName: String {
            switch self {
            case .planning: return "list.bullet.rectangle"
            case .embedding: return "brain.head.profile"
            case .retrieval: return "magnifyingglass"
            case .rerank: return "arrow.triangle.branch"
            case .gating: return "checkmark.shield"
            case .context: return "square.stack.3d.up"
            case .generation: return "sparkles"
            case .fallback: return "arrow.uturn.backward"
            case .warning: return "exclamationmark.triangle"
            // Advanced techniques
            case .hyde: return "doc.text.magnifyingglass"
            case .queryRewrite: return "pencil.and.outline"
            case .bm25: return "textformat.abc"
            case .vectorSearch: return "cube.transparent"
            case .rrf: return "arrow.triangle.merge"
            case .mmr: return "square.3.layers.3d"
            case .parentDoc: return "doc.on.doc"
            case .compression: return "arrow.down.right.and.arrow.up.left"
            case .lostInMiddle: return "arrow.up.arrow.down"
            case .grounding: return "checkmark.seal"
            case .selfRag: return "arrow.2.circlepath"
            case .iterative: return "repeat"
            case .agentic: return "brain"
            case .toolCall: return "function"
            case .factBank: return "tray.full"
            case .reasoning: return "lightbulb.mind"
            // AppleRAG features
            case .verification: return "checkmark.shield.fill"
            case .graphPack: return "point.3.connected.trianglepath.dotted"
            case .extractive: return "text.quote"
            case .intentRoute: return "arrow.triangle.branch"
            case .confidence: return "chart.bar.fill"
            case .imagePlayground: return "photo.on.rectangle.angled"
            }
        }

        /// Human-readable technique name
        nonisolated var displayName: String {
            switch self {
            case .planning: return "Planning"
            case .embedding: return "Embedding"
            case .retrieval: return "Retrieval"
            case .rerank: return "Re-ranking"
            case .gating: return "Confidence Gate"
            case .context: return "Context Assembly"
            case .generation: return "Generation"
            case .fallback: return "Fallback"
            case .warning: return "Warning"
            case .hyde: return "HyDE"
            case .queryRewrite: return "Query Rewrite"
            case .bm25: return "BM25 (Keyword)"
            case .vectorSearch: return "Vector Search"
            case .rrf: return "RRF Fusion"
            case .mmr: return "MMR Diversity"
            case .parentDoc: return "Parent Doc Expansion"
            case .compression: return "Compression"
            case .lostInMiddle: return "Position Reorder"
            case .grounding: return "Grounding Check"
            case .selfRag: return "Self-RAG"
            case .iterative: return "Iterative Retrieval"
            case .agentic: return "Agentic Step"
            case .toolCall: return "Tool Call"
            case .factBank: return "FactBank"
            case .reasoning: return "Model Reasoning"
            // AppleRAG features
            case .verification: return "Verification Gates"
            case .graphPack: return "Graph Context"
            case .extractive: return "Extractive Summary"
            case .intentRoute: return "Intent Routing"
            case .confidence: return "Confidence Calibration"
            case .imagePlayground: return "Image Playground"
            }
        }

        /// Color for the technique category
        nonisolated var color: String {
            switch self {
            case .planning, .agentic: return "purple"
            case .embedding, .hyde, .vectorSearch: return "blue"
            case .retrieval, .bm25, .queryRewrite: return "green"
            case .rerank, .rrf, .mmr: return "orange"
            case .gating, .grounding, .selfRag: return "teal"
            case .context, .parentDoc, .compression, .lostInMiddle: return "cyan"
            case .generation: return "yellow"
            case .fallback, .iterative: return "pink"
            case .warning: return "red"
            case .toolCall, .factBank: return "indigo"
            case .reasoning: return "purple"
            // AppleRAG features
            case .verification: return "mint"
            case .graphPack: return "purple"
            case .extractive: return "green"
            case .intentRoute: return "blue"
            case .confidence: return "orange"
            case .imagePlayground: return "mint"
            }
        }
    }

    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let title: String
    let detail: String?

    init(kind: Kind, title: String, detail: String? = nil, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

extension Array where Element == ThinkingEvent {
    /// Build a compact, human-readable reasoning trace from granular pipeline events.
    /// This is used when the engine did real work but didn't attach a higher-level
    /// reasoningTrace payload to metadata.
    nonisolated func compactReasoningTrace(maxSteps: Int = 8) -> [String] {
        guard !isEmpty else { return [] }

        let sortedEvents = self.sorted { $0.timestamp < $1.timestamp }
        var steps: [String] = []
        var seen = Set<String>()

        for event in sortedEvents {
            let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDetail = event.detail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty

            guard !trimmedTitle.isEmpty else { continue }

            let entry = "\(event.kind.displayName): \(trimmedTitle)\(trimmedDetail.map { " — \($0)" } ?? "")"
            let key = "\(event.kind.rawValue)|\(trimmedTitle.lowercased())|\((trimmedDetail ?? "").lowercased())"
            guard seen.insert(key).inserted else { continue }

            steps.append(entry)
        }

        guard steps.count > maxSteps else { return steps }

        let headCount = Swift.max(1, maxSteps / 2)
        let tailCount = Swift.max(1, maxSteps - headCount)
        return [String](steps.prefix(headCount)) + [String](steps.suffix(tailCount))
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
