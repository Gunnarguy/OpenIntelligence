//
//  Glossary.swift
//  OpenIntelligence
//
//  Every piece of vocabulary the app puts on screen, defined twice: once for someone
//  who has never heard the word, and once for someone who wants the mechanism.
//
//  Why both registers live in one place. The app shows "38 TOPS", "32/batch",
//  "768 search", "16-core ANE", "Chunks" and "Vectors" on the screen a new user reaches
//  ninety seconds after install. Those figures are real and they are the point of the
//  product, but unexplained they read as a wall, and the screen built to earn trust can
//  lose it instead. The fix is not to remove the numbers. It is to make every one of them
//  answer for itself where it already sits.
//
//  Two registers rather than one, because the audience genuinely splits and a single
//  middle register serves neither half. `plain` never uses a term this file defines
//  elsewhere unless it links to it, which `GlossaryTests` enforces. `technical` is free
//  to name types, models and dimensions.
//
//  This is the only definition of these words in the app. Popovers, the glossary screen
//  and the onboarding card all read from here, so a definition cannot drift between
//  surfaces. `HowItWorksView` remains the narrative explanation of the pipeline; this is
//  the reference for individual words, and the two are deliberately not copies.
//
//  Every technical claim below was verified against code on 2026-08-11. Where the app
//  cannot know something, the definition says so rather than rounding up: `tops` states
//  that the figure is a lookup and not a measurement, and `neuralEngine` states that
//  Core ML keeps the scheduling decision. Do not add a speed figure here without a
//  measurement and the hardware it came from.
//

import Foundation

// MARK: - Sections

/// The three questions a user actually has, in the order they have them.
enum GlossarySection: String, CaseIterable, Identifiable, Sendable {
    case pipeline
    case hardware
    case answering

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline: return "What happens to your files"
        case .hardware: return "The words about your device"
        case .answering: return "When an answer gets written"
        }
    }

    var icon: String {
        switch self {
        case .pipeline: return "square.and.arrow.down"
        case .hardware: return "cpu"
        case .answering: return "text.bubble"
        }
    }
}

// MARK: - Term

/// One word, defined in both registers.
struct GlossaryTerm: Sendable, Identifiable, Hashable {
    let id: GlossaryTermID
    let term: String
    let icon: String
    let section: GlossarySection

    /// For someone who has not met the word. No term defined elsewhere in this file may
    /// appear here unless it is also in `seeAlso`, which is what keeps a plain definition
    /// from quietly becoming a technical one.
    let plain: String

    /// For someone who wants the mechanism. Free to name types, models and dimensions.
    let technical: String

    /// Related terms, rendered as tappable rows under the definition.
    let seeAlso: [GlossaryTermID]

    /// Extra words that should find this term in search, for the cases where the label on
    /// screen and the name in the head are not the same word.
    let synonyms: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: GlossaryTerm, rhs: GlossaryTerm) -> Bool { lhs.id == rhs.id }
}

// MARK: - Identifiers

/// The set of defined words.
///
/// Definitions hang off this enum through one exhaustive `switch` rather than living in a
/// dictionary keyed by string. That is deliberate: a call site cannot name a term that
/// does not exist, lookup cannot fail, and adding a case is a compile error until it has
/// both registers written. The previous shape of this problem in the app was a
/// `(title, explanation)` popover whose strings were typed at each of its three call
/// sites, which is exactly how the same word ends up defined two ways.
enum GlossaryTermID: String, CaseIterable, Identifiable, Sendable {
    // What happens to your files
    case words
    case extraction
    case chunk
    case vector
    case index
    case ocr
    case hybridSearch
    case reranking
    case citation
    case rag
    case importTime

    // The words about your device
    case chip
    case neuralEngine
    case tops
    case embedBatch
    case searchBatch
    case unifiedMemory
    case gpuProfile

    // When an answer gets written
    case languageModel
    case token
    case contextWindow
    case onDevice
    case privateCloudCompute
    case temperature

    var id: String { rawValue }
}

// MARK: - Definitions

extension GlossaryTermID {
    var definition: GlossaryTerm {
        switch self {

        // MARK: What happens to your files

        case .words:
            return GlossaryTerm(
                id: self,
                term: "Words",
                icon: "textformat",
                section: .pipeline,
                plain: "How much text came out of your files. It is counted after the app reads them, so a scanned page contributes the words the app could actually make out rather than the words printed on the paper.",
                technical: "Summed `totalWords` across the documents in this import, measured post-extraction. OCR confidence and layout parsing both move this number, which is why it can differ from a word count taken in another app.",
                seeAlso: [.extraction, .ocr, .importTime],
                synonyms: ["word count", "length", "size"]
            )

        case .extraction:
            return GlossaryTerm(
                id: self,
                term: "Extract",
                icon: "doc.text",
                section: .pipeline,
                plain: "Getting the text out of a file. A PDF made on a computer already contains text and is read straight through. A photo or a scan is a picture of text, so the letters have to be recognised first.",
                technical: "PDFKit for text-layer PDFs, Vision for image pages, and format-specific parsers for Office files, code and transcripts. Structure is preserved on the way through: a table arrives as rows and a heading stays a heading rather than dissolving into a paragraph.",
                seeAlso: [.ocr, .chunk, .words],
                synonyms: ["parse", "read", "import", "pdf"]
            )

        case .chunk:
            return GlossaryTerm(
                id: self,
                term: "Chunk",
                icon: "square.split.2x2",
                section: .pipeline,
                plain: "A passage. The app splits each document into pieces small enough to search precisely and large enough to still make sense on their own, then searches the pieces instead of the whole file. A short report might become forty of them.",
                technical: "Sentence-boundary chunking, with an optional semantic pass that places a break where cosine similarity between adjacent sentences drops below a threshold. Each chunk keeps the section and heading it came from, so a retrieved passage still knows where it sat in the document.",
                seeAlso: [.vector, .index, .extraction],
                synonyms: ["passage", "segment", "split", "chunking", "chunks"]
            )

        case .vector:
            return GlossaryTerm(
                id: self,
                term: "Vector",
                icon: "brain.head.profile",
                section: .pipeline,
                plain: "A list of numbers standing for what a passage means. Two passages about the same thing get similar numbers, and that is how the app finds the right paragraph when you did not use the document's exact words.",
                technical: "384 dimensions per passage from MiniLM-L6-v2 through Core ML. Retrieval compares your question's vector against stored passage vectors by cosine similarity, which is the semantic half of the search.",
                seeAlso: [.chunk, .hybridSearch, .neuralEngine],
                synonyms: ["embedding", "embeddings", "vectors", "semantic", "dimension"]
            )

        case .index:
            return GlossaryTerm(
                id: self,
                term: "Index",
                icon: "magnifyingglass",
                section: .pipeline,
                plain: "The searchable copy the app builds once, up front. It is the reason an answer comes back in a moment rather than the app rereading every document each time you ask a question.",
                // Deliberately says "per library" and not "local". Both indexes are
                // per-library, by separate mechanisms: the vector store is one file per
                // container, `vector_database_<containerId>.json`, while FTS5 isolates by a
                // `containerId` column in one database. A library shared through iCloud
                // syncs its index along with it, so a flat "lives locally" claim here would
                // be wrong for exactly the libraries a user is most careful about.
                technical: "Two indexes over the same passages: a vector store for meaning and a SQLite FTS5 table for exact terms. Both are scoped per library, so a query cannot reach a library you do not have open.",
                seeAlso: [.chunk, .hybridSearch, .onDevice],
                synonyms: ["indexing", "database", "store", "search index"]
            )

        case .ocr:
            return GlossaryTerm(
                id: self,
                term: "OCR",
                icon: "eye",
                section: .pipeline,
                plain: "Reading letters off a picture. A scan or a photograph of a page holds no text at all, only an image of text, so the shapes have to be recognised before anything can be searched.",
                technical: "Apple's Vision framework. Pages render at an adaptive 360 to 432 DPI and go through `RecognizeDocumentsRequest`, which reads a page as a document and returns its structure rather than a bag of strings.",
                seeAlso: [.extraction, .words],
                synonyms: ["scan", "scanned", "vision", "recognition", "photo", "image"]
            )

        case .hybridSearch:
            return GlossaryTerm(
                id: self,
                term: "Hybrid search",
                icon: "arrow.triangle.merge",
                section: .pipeline,
                plain: "The app searches two ways at once and merges the results. Meaning finds \"what is the warranty policy\". Exact words find \"SKU 4417-B\". Neither one on its own finds both.",
                technical: "Dense vector similarity and BM25 lexical scoring run in parallel, then merge by reciprocal rank fusion before the shortlist is reranked. The two halves fail differently, which is the reason for keeping both.",
                seeAlso: [.vector, .reranking, .index],
                synonyms: ["bm25", "keyword", "lexical", "rrf", "fusion", "retrieval", "search"]
            )

        case .reranking:
            return GlossaryTerm(
                id: self,
                term: "Reranking",
                icon: "arrow.up.arrow.down",
                section: .pipeline,
                plain: "A second, more careful look at the passages the search turned up, moving the ones that genuinely answer your question to the top. The first pass is fast and rough, so this one only ever sees the shortlist.",
                technical: "A cross-encoder scores your question and a passage together in a single pass, rather than comparing two vectors that were built independently. The shipped model is `ms-marco-TinyBERT-L2-v2` under Core ML.",
                seeAlso: [.hybridSearch, .citation],
                synonyms: ["rerank", "cross-encoder", "ranking", "reorder"]
            )

        case .citation:
            return GlossaryTerm(
                id: self,
                term: "Citation",
                icon: "quote.opening",
                section: .pipeline,
                plain: "The link under an answer back to the passage it came from. Tapping it shows you the real text inside your own document, which is how you check an answer instead of trusting it.",
                technical: "Answers are assembled from retrieved passages and carry the source and position of each. When the retrieved passages do not support an answer, the app reports that rather than writing one anyway.",
                seeAlso: [.rag, .reranking],
                synonyms: ["source", "sources", "reference", "evidence", "cited"]
            )

        case .rag:
            return GlossaryTerm(
                id: self,
                term: "RAG",
                icon: "point.3.filled.connected.trianglepath.dotted",
                section: .pipeline,
                plain: "Retrieval-augmented generation. The app finds the relevant passages in your files first, then asks a language model to answer using only those. The model is not remembering your documents. It is reading pieces handed to it a moment earlier.",
                technical: "Retrieve, rerank, pack, generate. Because the model only ever sees retrieved context, a question with no supporting passage produces an explicit \"not supported\" rather than a fluent guess.",
                seeAlso: [.citation, .languageModel, .contextWindow],
                synonyms: ["retrieval augmented generation", "pipeline", "how it works"]
            )

        case .importTime:
            return GlossaryTerm(
                id: self,
                term: "Time",
                icon: "clock",
                section: .pipeline,
                plain: "How long this import took from start to finish, on this device. It covers reading the files, splitting them up, indexing them and writing the result to storage.",
                technical: "Wall clock from the first document being queued to the last reaching `.complete`. Batch sizes and concurrency are derived from the device, so the same files import at different speeds on different hardware.",
                seeAlso: [.embedBatch, .chip],
                synonyms: ["duration", "elapsed", "speed", "how long"]
            )

        // MARK: The words about your device

        case .chip:
            return GlossaryTerm(
                id: self,
                term: "Chip",
                icon: "cpu",
                section: .hardware,
                plain: "The processor in this device. The app works out which one it is and sizes its own work to match, so it does more per second on newer hardware instead of running the same way everywhere.",
                technical: "Resolved from the `uname` device identifier through a mapping table in `DeviceCapabilityService`, not from a marketing string. Every other figure on this panel is derived from it together with measured RAM.",
                seeAlso: [.neuralEngine, .unifiedMemory, .tops],
                synonyms: ["processor", "silicon", "soc", "a19", "m4", "apple silicon"]
            )

        case .neuralEngine:
            return GlossaryTerm(
                id: self,
                term: "Neural Engine",
                icon: "cpu.fill",
                section: .hardware,
                plain: "A part of the chip that does nothing but machine learning. It is the reason a phone can index a whole book without getting as hot as it would if the main processor did the same work.",
                technical: "16 cores on every Apple Intelligence capable chip. The app asks for it through Core ML's `preferredComputeUnits`, and Core ML makes the final scheduling decision, so this is a stated preference rather than a guarantee that the Neural Engine ran.",
                seeAlso: [.tops, .chip, .vector],
                synonyms: ["ane", "npu", "16-core", "core ml", "coreml"]
            )

        case .tops:
            return GlossaryTerm(
                id: self,
                term: "TOPS",
                icon: "sparkles",
                section: .hardware,
                plain: "Trillions of operations per second. It is a rating for the Neural Engine in this chip, in the way horsepower is a rating for an engine. A higher number means more headroom, not that anything is running at that rate right now.",
                technical: "A published per-chip figure looked up from the device identifier. It is not measured on your device, and entries for unreleased silicon are marked as projections in the source. Apple exposes no live Neural Engine occupancy API, so no app can report real utilisation.",
                seeAlso: [.neuralEngine, .chip],
                synonyms: ["tera operations", "38 tops", "npu", "throughput", "rating"]
            )

        case .embedBatch:
            return GlossaryTerm(
                id: self,
                term: "Embed batch",
                icon: "square.grid.3x3",
                section: .hardware,
                plain: "How many passages get handed to the model in one go. One trip carrying thirty passages beats thirty trips carrying one. This number was chosen for your chip and memory rather than copied from a default.",
                technical: "`embeddingBatchSize` in `DeviceCapabilityService`, resolved from the device tier and scaled by measured RAM on M-series. Larger batches amortise Core ML invocation overhead across more work.",
                seeAlso: [.vector, .searchBatch, .unifiedMemory],
                synonyms: ["batch", "batch size", "32/batch", "per batch"]
            )

        case .searchBatch:
            return GlossaryTerm(
                id: self,
                term: "Search batch",
                icon: "magnifyingglass",
                section: .hardware,
                plain: "How many stored passages get compared against your question at the same time. Doing it in one large block is what lets the app search a whole library in a single pass instead of one passage at a time.",
                technical: "`vectorBatchSize`, the width handed to `vDSP_mmul` for batched cosine similarity in `BNNSVectorDatabase`. Tier-derived and RAM-scaled, and reduced from its original values after Metal command buffer instability at the top setting.",
                seeAlso: [.vector, .embedBatch, .hybridSearch],
                synonyms: ["768 search", "vector batch", "similarity", "vdsp", "accelerate"]
            )

        case .unifiedMemory:
            return GlossaryTerm(
                id: self,
                term: "Unified memory",
                icon: "memorychip",
                section: .hardware,
                plain: "Memory that the processor, the graphics cores and the Neural Engine all share, so work does not have to be copied between them before it can be done. More of it means more of your library can be in flight at once.",
                technical: "Read from `ProcessInfo.physicalMemory`, which is measured rather than inferred from the model name. It scales batch sizes, concurrency ceilings and the budget for full-resolution PDF page images.",
                seeAlso: [.chip, .embedBatch, .gpuProfile],
                synonyms: ["ram", "memory", "gb", "shared memory"]
            )

        case .gpuProfile:
            return GlossaryTerm(
                id: self,
                term: "GPU profile",
                icon: "gauge.with.needle",
                section: .hardware,
                plain: "How hard the app is allowed to push the graphics cores. Higher settings import faster and use more battery. There is also a per-device ceiling it will not cross, because going past it caused crashes.",
                technical: "Four discrete profiles rather than a percentage, because Apple's frameworks keep final hardware scheduling control and a percentage would imply precision the app cannot deliver. `maxSafeGPUAccelerationLevel` clamps the request per form factor and tier.",
                seeAlso: [.unifiedMemory, .chip, .neuralEngine],
                synonyms: ["gpu", "metal", "acceleration", "efficiency", "performance", "maximum"]
            )

        // MARK: When an answer gets written

        case .languageModel:
            return GlossaryTerm(
                id: self,
                term: "Language model",
                icon: "text.bubble",
                section: .answering,
                plain: "The part that turns found passages into sentences. Everything before it is search. It sees your question and the passages the search returned, and nothing else from your library.",
                technical: "Apple's on-device Foundation Model by default, through the FoundationModels framework. Every session it runs is capped at 4,096 tokens, which is why what retrieval selects matters more than the size of the model.",
                seeAlso: [.rag, .contextWindow, .token, .temperature],
                synonyms: ["llm", "model", "foundation model", "apple intelligence", "generation"]
            )

        case .token:
            return GlossaryTerm(
                id: self,
                term: "Token",
                icon: "number",
                section: .answering,
                plain: "The unit a language model reads and writes in, roughly three quarters of a word. It matters because a model can only hold so many at a time, so a limit of 4,096 is a real ceiling on how much can be considered at once.",
                technical: "Apple's on-device model and Private Cloud Compute both cap a session at 4,096 tokens (Apple TN3193). That single budget covers the instructions, the retrieved passages, your question and the answer together.",
                seeAlso: [.contextWindow, .languageModel],
                synonyms: ["tokens", "4096", "budget", "limit"]
            )

        case .contextWindow:
            return GlossaryTerm(
                id: self,
                term: "Context window",
                icon: "rectangle.compress.vertical",
                section: .answering,
                plain: "The most a model can hold in mind at once: instructions, the passages found in your files, your question and its answer, all sharing the same space. When a question needs more than fits, something has to be left out, which is why finding the right passages matters more than having a bigger model.",
                technical: "Fixed at 4,096 tokens for both on-device and Private Cloud Compute sessions (Apple TN3193). `ContextPackingService` selects and truncates retrieved passages to fit that budget before generation begins.",
                seeAlso: [.token, .languageModel, .privateCloudCompute],
                synonyms: ["context", "window", "context length", "4096", "packing"]
            )

        case .onDevice:
            return GlossaryTerm(
                id: self,
                term: "On-device",
                icon: "iphone",
                section: .answering,
                plain: "It happened here, on this phone or Mac. No account and no server. Turn off Wi-Fi and cellular and everything described on this screen still works, apart from the one optional step below.",
                // Scoped to the answer path on purpose. The app does have one other network
                // path, iCloud sync for libraries you deliberately share, and an
                // unqualified "nothing uses the network" would be false for it. This is the
                // same framing `HowItWorksView` uses, verified 2026-08-10.
                technical: "Reading, splitting, embedding, indexing, retrieval and ranking have no network path. The only outbound call in the answer path is Private Cloud Compute, gated on per-request consent. Sharing a library through iCloud is separate, opt in, and not part of answering a question.",
                seeAlso: [.privateCloudCompute, .index, .languageModel],
                synonyms: ["local", "offline", "private", "no server", "no upload", "airplane mode"]
            )

        case .privateCloudCompute:
            return GlossaryTerm(
                id: self,
                term: "Private Cloud Compute",
                icon: "cloud",
                section: .answering,
                plain: "Apple's servers, for the one case where a question needs more room than this device's model has. It is used for the writing step only, one request at a time, and only after you approve that request. Your files are not uploaded. The passages the answer needs are.",
                technical: "`CloudEvidenceMinimizer` bounds the payload to a selected set of source IDs, names, page numbers and passage text. The consent sheet shows the provider, the model, prompt size, context size, chunk count and total estimated bytes before anything leaves. Setting routing to On-Device means this path is never taken.",
                seeAlso: [.onDevice, .contextWindow, .languageModel],
                synonyms: ["pcc", "cloud", "apple", "consent", "routing", "escalate"]
            )

        case .temperature:
            return GlossaryTerm(
                id: self,
                term: "Temperature",
                icon: "thermometer.medium",
                section: .answering,
                plain: "How much the model is allowed to vary its wording. Low keeps answers close to the source and repeatable. High makes them read more freely and less predictably.",
                technical: "Sampling temperature on the generation session. Retrieval and ranking sit entirely upstream and are unaffected by it, so this changes how an answer reads rather than what was found in your files.",
                seeAlso: [.languageModel, .token],
                synonyms: ["sampling", "creativity", "randomness", "top p", "top k"]
            )
        }
    }
}

// MARK: - Registry

enum Glossary {
    /// Every term, in declaration order.
    static let all: [GlossaryTerm] = GlossaryTermID.allCases.map(\.definition)

    /// Terms in one section, in declaration order.
    static func terms(in section: GlossarySection) -> [GlossaryTerm] {
        all.filter { $0.section == section }
    }

    /// Case-insensitive substring match across the term, both registers and the synonyms.
    ///
    /// Searching the technical register too is deliberate. Someone who types "vDSP" or
    /// "BM25" is looking for the word the code uses, and refusing to match it because the
    /// plain definition avoids jargon would defeat the point of writing two registers.
    static func search(_ query: String) -> [GlossaryTerm] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return all }

        return all.filter { term in
            if term.term.lowercased().contains(needle) { return true }
            if term.plain.lowercased().contains(needle) { return true }
            if term.technical.lowercased().contains(needle) { return true }
            return term.synonyms.contains { $0.lowercased().contains(needle) }
        }
    }
}
