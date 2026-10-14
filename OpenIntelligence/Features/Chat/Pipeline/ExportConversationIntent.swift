//
//  ExportConversationIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// The formats "Export Conversation" offers: the chat menu's three (5.7).
@available(iOS 26.0, macOS 26.0, *)
enum ConversationExportFormat: String, AppEnum {
    case markdown
    case jsonLines
    case pdf

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Format")
    static var caseDisplayRepresentations: [ConversationExportFormat: DisplayRepresentation] = [
        .markdown: "Markdown",
        .jsonLines: "JSON Lines",
        .pdf: "PDF",
    ]

    var format: ConversationExporter.Format {
        switch self {
        case .markdown: return .markdown
        case .jsonLines: return .jsonLines
        case .pdf: return .pdf
        }
    }
}

/// Hands a saved conversation to a shortcut as a file, with each answer's sources (5.7). Through
/// 5.6 a conversation could be exported only from the chat's menu. The file is the one the menu
/// writes (`ConversationExporter.data`). This is an action, not an App Shortcut, so it takes no
/// Siri slot.
@available(iOS 26.0, macOS 26.0, *)
struct ExportConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Conversation"
    static var description: IntentDescription = .init(
        "Returns a saved conversation as a Markdown, JSON Lines or PDF file, with each answer's sources.",
        categoryName: "Chat",
        searchKeywords: ["export", "conversation", "chat", "markdown", "pdf", "save", "share"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Conversation")
    var conversation: OIThreadEntity

    @Parameter(title: "Format", default: .markdown)
    var format: ConversationExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$conversation) as \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let id = conversation.id
        guard let thread = await Self.thread(id: id) else {
            throw OIIntentError("That conversation is no longer saved.")
        }
        guard !ConversationExporter.exportable(thread.messages).isEmpty else {
            throw OIIntentError("That conversation has no messages to export.")
        }
        let kind = format.format
        let file = IntentFile(
            data: ConversationExporter.data(messages: thread.messages, title: thread.title, format: kind),
            filename: ConversationExporter.fileName(title: thread.title, format: kind),
            type: kind.contentType)
        Log.info(
            "[Shortcuts] Export Conversation (\(kind.rawValue), \(thread.messages.count) messages)", category: .pipeline
        )
        return .result(
            value: file, dialog: IntentDialog(stringLiteral: "Exported “\(thread.title)” as \(kind.menuTitle)."))
    }

    /// The saved conversation with this id, from whichever library holds it.
    static func thread(id: UUID) -> EvidenceThread? {
        let store = EvidenceThreadStore()
        for library in OILibraryEntityQuery.loadContainers() {
            if let thread = try? store.getThread(id: id, containerId: library.id) { return thread }
        }
        return nil
    }
}
