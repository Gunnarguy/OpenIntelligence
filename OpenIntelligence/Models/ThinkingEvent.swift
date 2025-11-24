import Foundation

/// Represents a single step in the assistant's "thinking" timeline.
/// These events are surfaced in the chat UI so users can see how the
/// RAG pipeline is progressing (embedding, retrieval, gating, etc.).
struct ThinkingEvent: Identifiable, Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case planning
        case embedding
        case retrieval
        case rerank
        case gating
        case context
        case generation
        case fallback
        case warning

        /// Maps each kind to a system icon for quick visual scanning.
        var systemIconName: String {
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
