//
//  SuggestedQuestionsService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 2025.
//
//  Source-first suggested question generation from actual document content.
//  Generates specific, grounded questions that showcase RAG capabilities.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service that generates contextual suggested questions from actual document content.
///
/// **Architecture (v4 — source-first, fail-closed grounding):**
///
/// 1. Select diverse representative chunks across the library (different docs, sections, topics)
/// 2. Generate deterministic questions from specs, procedures, warnings, and definitions
/// 3. Let Apple FM only polish already-grounded drafts when outputs pass strict passage-grounding checks
/// 4. Fail closed — if the library does not yield strong grounded prompts, return none
///
/// **Why this is 10x:**
/// - Questions are generated FROM the actual text, not from loose entity labels
/// - "What is Analysis?" → "What is the fuel tank capacity?"
/// - Diversity is enforced at the chunk selection level, not post-hoc filtering
/// - Cache invalidates on document change, not never
/// - Weak document-shaped prompts are dropped instead of padded with canned fallback chips

#if canImport(FoundationModels)
/// Structured LLM output for suggested question generation.
/// @Generable guarantees a typed [String] array — no numbered-line parsing or regex needed.
/// Constrained sampling enforces the declared schema at the token level.
@available(iOS 26.0, *)
@Generable
struct SuggestedQuestionList: Sendable {
    @Guide(description: "Short, natural, grammatically complete questions someone would actually ask after reading these documents. Each question targets a specific fact, concept, or procedure from the text. Sound casual and direct, like texting a coworker. Every question must be a complete, coherent sentence. Never end with fragments like 'that many?' or list unjoined names like 'Piaget Vygotsky?'.")
    var questions: [String]
}
#endif

actor SuggestedQuestionsService {

    static let shared = SuggestedQuestionsService()

    // MARK: - Types

    /// Category of question for display diversity
    enum QuestionCategory: String, CaseIterable, Sendable, Codable {
        case factRetrieval = "fact"
        case comparison = "compare"
        case summarization = "summarize"
        case procedural = "how"
        case analytical = "analyze"
        case numerical = "numeric"

        /// SF Symbol icon for category badge
        var icon: String {
            switch self {
            case .factRetrieval: return "magnifyingglass"
            case .comparison: return "arrow.left.arrow.right"
            case .summarization: return "doc.text"
            case .procedural: return "list.number"
            case .analytical: return "chart.bar.xaxis"
            case .numerical: return "number"
            }
        }
    }

    /// A generated question with metadata
    struct SuggestedQuestion: Identifiable, Sendable, Codable {
        let id: UUID
        let text: String
        let category: QuestionCategory
        let relevantDocuments: [String]
        let relevantDocumentIds: [UUID]?
        let sourceSections: [String]
        let confidence: Double
        let isLLMGenerated: Bool

        init(
            id: UUID = UUID(),
            text: String,
            category: QuestionCategory,
            relevantDocuments: [String],
            relevantDocumentIds: [UUID]? = nil,
            sourceSections: [String],
            confidence: Double,
            isLLMGenerated: Bool
        ) {
            self.id = id
            self.text = text
            self.category = category
            self.relevantDocuments = relevantDocuments
            self.relevantDocumentIds = relevantDocumentIds
            self.sourceSections = sourceSections
            self.confidence = confidence
            self.isLLMGenerated = isLLMGenerated
        }
    }

    // MARK: - Properties

    var cachedQuestions: [UUID: CachedEntry] = [:]

    /// Cache entry with timestamp for staleness detection
    struct CachedEntry: Sendable {
        let questions: [SuggestedQuestion]
        let documentCount: Int
        let generatedAt: Date
    }

    /// Maximum cache age before regeneration (5 minutes)
    static let cacheMaxAge: TimeInterval = 300

    /// Containers whose template-only bank has already been offered to the model this launch.
    var bankRebuildAttempted: Set<UUID> = []

    /// Documents whose import is writing their questions now; Chat leaves them to it (5.8).
    var ingestionQuestionsInFlight: Set<UUID> = []
    /// Documents Chat is writing questions for now, so a second refresh does not write them again (5.8).
    var questionFillInFlight: Set<UUID> = []
    /// Documents with a finished question run this launch, written or not (5.8).
    var questionFillSettled: Set<UUID> = []
    /// Interrupted question runs per document this launch (5.8).
    var questionFillAttempts: [UUID: Int] = [:]

    /// A bank deserves a second pass when the model can write questions now and never has for
    /// this library. Empty banks are the on-demand path's business, not this one's.
    static func shouldRebuildBank(_ bank: [SuggestedQuestion], modelAvailable: Bool) -> Bool {
        modelAvailable && !bank.isEmpty && !bank.contains(where: \.isLLMGenerated)
    }

    /// The sample documents' filenames as they are stored (matches SampleDocumentManager).
    private static let sampleDocumentFilenames: Set<String> = [
        "OpenIntelligence-Product-Guide.md",
        "RAG-Technical-Architecture.md",
        "Apple-Intelligence-&-Private-Cloud-Compute.md"
    ]

    /// The name each sample is listed under, which is what `relevantDocuments` holds.
    private static let sampleDisplayNames: [String: String] = [
        "OpenIntelligence-Product-Guide.md": "OpenIntelligence Product Guide",
        "RAG-Technical-Architecture.md": "RAG Technical Architecture",
        "Apple-Intelligence-&-Private-Cloud-Compute.md": "Apple Intelligence & Private Cloud Compute",
    ]

    /// The hand-written questions for the sample documents, in the order a new reader meets them.
    /// The owner decided on 2026-09-14 that this set is written by hand, the same on every device,
    /// and never generated (`Docs/ai/DECISIONS.md`). Each question names the sample and the heading
    /// it was written from, which its chip shows, and a test fails when a guide loses that heading:
    /// by 5.7 four of these named headings the rewritten guides no longer had, one of them the
    /// question "How does dynamic model routing work?", which the list no longer asks.
    private static let sampleWorkspaceQuestions: [SuggestedQuestion] = [
        // Product Guide
        SuggestedQuestion(
            text: "Why is OpenIntelligence different from a generic AI chat app?",
            category: .comparison,
            relevantDocuments: ["OpenIntelligence Product Guide"],
            sourceSections: ["What makes OpenIntelligence different?"],
            confidence: 0.97,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "What file formats does OpenIntelligence support?",
            category: .factRetrieval,
            relevantDocuments: ["OpenIntelligence Product Guide"],
            sourceSections: ["What files can OpenIntelligence read?"],
            confidence: 0.97,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "How does the app keep answers grounded in your documents?",
            category: .procedural,
            relevantDocuments: ["OpenIntelligence Product Guide"],
            sourceSections: ["How answers stay grounded"],
            confidence: 0.96,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "What's included in the Free plan versus Pro?",
            category: .comparison,
            relevantDocuments: ["OpenIntelligence Product Guide"],
            sourceSections: ["Plans"],
            confidence: 0.95,
            isLLMGenerated: false
        ),
        // RAG Technical Architecture
        SuggestedQuestion(
            text: "How does OpenIntelligence work around the model's token limit?",
            category: .procedural,
            relevantDocuments: ["RAG Technical Architecture"],
            sourceSections: ["Why retrieval matters"],
            confidence: 0.97,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "What steps does the RAG pipeline follow?",
            category: .procedural,
            relevantDocuments: ["RAG Technical Architecture"],
            sourceSections: ["The pipeline"],
            confidence: 0.96,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "What are the three quality modes?",
            category: .factRetrieval,
            relevantDocuments: ["RAG Technical Architecture"],
            sourceSections: ["Quality modes"],
            confidence: 0.96,
            isLLMGenerated: false
        ),
        // Apple Intelligence & Private Cloud Compute
        SuggestedQuestion(
            text: "When does processing stay on-device, and when does Apple Private Cloud Compute step in?",
            category: .factRetrieval,
            relevantDocuments: ["Apple Intelligence & Private Cloud Compute"],
            sourceSections: ["What stays on the device?"],
            confidence: 0.97,
            isLLMGenerated: false
        ),
        SuggestedQuestion(
            text: "What privacy guarantees does Private Cloud Compute provide?",
            category: .factRetrieval,
            relevantDocuments: ["Apple Intelligence & Private Cloud Compute"],
            sourceSections: ["What is Private Cloud Compute?"],
            confidence: 0.96,
            isLLMGenerated: false
        ),
    ]

    /// The canonical sample filename a stored filename stands for, or nil when it is not a sample.
    ///
    /// Managed storage uniquifies a colliding filename by appending `-2`, `-3` and so on
    /// (`WorkspaceSyncService`), and a sample refresh can leave such a copy behind. Until
    /// 2026-09-14 every check in this file compared filenames exactly, so one
    /// `RAG-Technical-Architecture-2.md` made the library stop being the sample workspace: the
    /// curated questions were skipped and the on-demand template bank took over, which is how the
    /// owner's phone came to show "What is nothing?". Deliberately strict, as in
    /// `SampleDocumentManager.matchesStoredCopy`: only `<stem>-<digits>.<same extension>` matches,
    /// so a user's own `OpenIntelligence-Product-Guide-notes.md` is not a sample.
    static func sampleIdentity(for filename: String) -> String? {
        if sampleDocumentFilenames.contains(filename) { return filename }
        let ext = (filename as NSString).pathExtension
        let candidate = (filename as NSString).deletingPathExtension
        for canonical in sampleDocumentFilenames {
            guard (canonical as NSString).pathExtension == ext else { continue }
            let stem = (canonical as NSString).deletingPathExtension
            guard candidate.hasPrefix(stem + "-") else { continue }
            let suffix = candidate.dropFirst(stem.count + 1)
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) { return canonical }
        }
        return nil
    }

    /// The hand-written questions' text, which tells them from generated ones on screen.
    static let curatedQuestionTexts: Set<String> = Set(sampleWorkspaceQuestions.map(\.text))

    /// The hand-written questions for a library made only of sample documents, canonical or
    /// numbered copies, limited to the samples it holds and in the list's order. nil for an empty
    /// library and for one holding any document of the person's own, which the generator serves.
    ///
    /// Until 5.7 this was all or nothing: the set showed only when all three samples were present,
    /// so a library whose Private Cloud Compute guide had been deleted fell through to the template
    /// generator, which is how "What is nothing?" reached a library of samples. Pure, so tested.
    static func curatedSampleQuestions(forFilenames filenames: [String]) -> [SuggestedQuestion]? {
        guard !filenames.isEmpty else { return nil }
        var present: Set<String> = []
        for filename in filenames {
            guard let identity = sampleIdentity(for: filename),
                  let name = sampleDisplayNames[identity] else { return nil }
            present.insert(name)
        }
        let questions = sampleWorkspaceQuestions.filter { $0.relevantDocuments.allSatisfy(present.contains) }
        return questions.isEmpty ? nil : questions
    }

    // MARK: - Static Fallbacks

}
