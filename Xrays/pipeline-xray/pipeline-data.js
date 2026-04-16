/**
 * Pipeline X-Ray Studio — Inline Data
 * Eliminates fetch() — works from file:// protocol (just double-click index.html).
 * Contains: canonical pipeline model + 2 demo traces.
 */

// ═══════════════════════════════════════════════════════════════
// CANONICAL PIPELINE MODEL (from data/canonical-pipeline.json)
// ═══════════════════════════════════════════════════════════════

const PIPELINE_DATA = {
  version: "1.0",
  name: "OpenIntelligence Pipeline",
  description: "29-step end-to-end RAG pipeline: 6 ingestion + 23 query steps",
  source:
    "Derived from .github/copilot-instructions.md, HOW_IT_WORKS.md, ARCHITECTURE.md, ThinkingEvent.swift, RAGService.swift",
  generatedDate: "2026-03-06",
  hardLimits: {
    embeddingTokens: {
      value: 510,
      unit: "tokens",
      note: "CoreML MiniLM-L6-v2 (512 - CLS/SEP)",
    },
    chunkSize: {
      value: 310,
      unit: "words",
      note: "340 target - 30 for contextual prefix overhead",
    },
    chunkLimit: {
      value: 50000,
      unit: "chunks",
      note: "Supports ~65,000 pages per container",
    },
    llmContext: {
      value: 4096,
      unit: "tokens",
      note: "Apple FM TN3193 on-device limit",
    },
    contextChars: {
      value: 5500,
      unit: "chars",
      note: "~4000 tokens with margin",
    },
    embeddingDim: { value: 384, unit: "dimensions", note: "MiniLM output" },
    ocrDpi: {
      value: 360,
      unit: "dpi",
      note: "5x scale factor for PDF rendering",
    },
    imageDpi: {
      value: 144,
      unit: "dpi",
      note: "2x scale for memory-safe image analysis",
    },
    compressionCap: {
      value: 5,
      unit: "chunks",
      note: "Max chunks sent to LLM compression",
    },
    compressionTimeout: {
      value: 12,
      unit: "seconds",
      note: "Bails early if time runs out",
    },
    generationTimeout: {
      value: 30,
      unit: "seconds",
      note: "Budget for transforms",
    },
    postCompressionCooldown: {
      value: 1,
      unit: "seconds",
      note: "Lets FM rate limits recover",
    },
  },
  modes: {
    standard: {
      label: "Standard",
      sessions: "1",
      description: "Search once, answer once",
      speed: "2-5s",
    },
    deepThink: {
      label: "Deep Think",
      sessions: "4-8",
      description: "Self-RAG 2.0: iterative enrichment",
      speed: "10-30s",
    },
    maximum: {
      label: "Maximum",
      sessions: "8-50",
      description: "Multi-chain parallel + cluster synthesis",
      speed: "30s-2min",
    },
  },
  gates: {
    A: {
      name: "Retrieval Confidence",
      type: "critical",
      action: "abstain",
      description: "Top retrieval score meets threshold",
    },
    B: {
      name: "Evidence Coverage",
      type: "critical",
      action: "abstain",
      description: "Claims cite retrieved chunks",
    },
    C: {
      name: "Numeric Sanity",
      type: "critical",
      action: "abstain",
      description: "Numbers match sources (year/1-10 exemption)",
    },
    D: {
      name: "Contradiction Sweep",
      type: "critical",
      action: "abstain",
      description: "No conflicting evidence across chunks",
    },
    E: {
      name: "Semantic Grounding",
      type: "critical",
      action: "abstain",
      description: "vDSP cosine: response embedding aligned with chunks",
    },
    F: {
      name: "Quote Faithfulness",
      type: "advisory",
      action: "confidence penalty",
      description: "Jaccard abbreviation verification",
    },
    G: {
      name: "Generation Quality",
      type: "advisory",
      action: "confidence penalty",
      description: "Entropy/uniqueness checks catch repetition",
    },
  },
  phases: [
    {
      id: "ingestion",
      label: "INGESTION",
      description: "Document \u2192 Numbers (6 steps)",
      color: "#34d399",
      steps: [
        {
          id: "ingest-parse",
          stepNumber: "1",
          name: "Parse",
          shortName: "Parse",
          phase: "Extract",
          description:
            "Extract text from documents using PDFKit, Vision OCR (360 DPI), or Office ZIP parsing",
          thinkingKinds: [],
          color: "#34d399",
          typicalDuration: "1-30s per page",
          substeps: [
            {
              id: "ingest-parse-phase-neg1",
              name: "PHASE -1: Text Layer Validation",
              description:
                "Jaccard similarity check: PDFKit text vs Vision OCR output. Font-encoded PDFs (Kia, Hyundai) have shifted characters. Threshold < 0.15 = garbled \u2192 full OCR forced. Prevents 93% content loss.",
              color: "#f97316",
            },
            {
              id: "ingest-parse-complexity",
              name: "Page Complexity Analysis",
              description:
                "PageComplexityAnalyzer scores text quality, table presence, numeric density, visual complexity. Tables/numbers \u2192 forced Vision OCR.",
              color: "#34d399",
            },
            {
              id: "ingest-parse-vocab",
              name: "Dynamic Vocabulary Extraction",
              description:
                "PDFKit text mined for acronyms, alphanumeric codes (0W-20, R-134a), CamelCase terms \u2192 Vision customWords.",
              color: "#34d399",
            },
            {
              id: "ingest-parse-preprocessing",
              name: "Adaptive Preprocessing",
              description:
                "1 of 5 GPU-accelerated CIFilter strategies selected per page quality. Minimal (clean digital) \u2192 Maximum (faded microfiche). Concurrent DispatchQueue.",
              color: "#60a5fa",
            },
            {
              id: "ingest-parse-ocr",
              name: "Multi-Candidate Confidence OCR",
              description:
                "Vision returns topCandidates(5) per line. Numeric data requires 90% confidence (vs 85% text). Low-confidence alternatives flagged for verification.",
              color: "#a78bfa",
            },
            {
              id: "ingest-parse-image",
              name: "Memory-Safe Image Analysis",
              description:
                "Post-OCR image/diagram extraction. 5-page batches, 144 DPI (2\u00d7 scale), autoreleasepool cleanup. Parsed results freed first (~100-200MB reclaimed).",
              color: "#f472b6",
            },
          ],
        },
        {
          id: "ingest-chunk",
          stepNumber: "2",
          name: "SemanticChunker",
          shortName: "Chunk",
          phase: "Chunk",
          description:
            "Break documents into \u2264310 word chunks with section detection. Tables preserved as atomic units. ~200 chunks per 50-page document.",
          thinkingKinds: [],
          color: "#60a5fa",
          typicalDuration: "< 1s",
        },
        {
          id: "ingest-entity",
          stepNumber: "3",
          name: "Entity Extraction",
          shortName: "NER",
          phase: "Extract",
          description:
            "NLTagger NER + PascalCase detection extracts named entities per chunk. Feeds EntityIndexService for per-container entity lookup.",
          thinkingKinds: [],
          color: "#34d399",
          typicalDuration: "< 1s",
        },
        {
          id: "ingest-token",
          stepNumber: "4",
          name: "Token Validation",
          shortName: "Validate",
          phase: "Chunk",
          description:
            "BertTokenizer verifies each chunk \u2264510 embedding tokens. Oversized chunks are re-split. Technical text \u2260 1.5 tokens/word.",
          thinkingKinds: [],
          color: "#fbbf24",
          typicalDuration: "< 0.5s",
        },
        {
          id: "ingest-embed",
          stepNumber: "5",
          name: "Embedding",
          shortName: "Embed",
          phase: "Embed",
          description:
            "CoreML MiniLM-L6-v2 converts each chunk \u2192 384-dim vector. GPU compute (.cpuAndGPU) during ingestion frees ANE for OCR.",
          thinkingKinds: ["embedding"],
          color: "#818cf8",
          typicalDuration: "~10ms per chunk",
        },
        {
          id: "ingest-store",
          stepNumber: "6",
          name: "Store",
          shortName: "Index",
          phase: "Index",
          description:
            "HNSW index + FullTextStorage (SQLite FTS5) + EntityIndex. Metal GPU 3-tier shader selection for vector storage.",
          thinkingKinds: [],
          color: "#2dd4bf",
          typicalDuration: "< 2s",
        },
      ],
    },
    {
      id: "query-analysis",
      label: "QUERY ANALYSIS",
      description: "Understand the question (Steps 0-1.6)",
      color: "#a78bfa",
      steps: [
        {
          id: "query-step0",
          stepNumber: "0",
          name: "Corpus Analysis",
          shortName: "Corpus",
          description:
            "Vocabulary cache analysis \u2014 understand what the container knows before searching.",
          thinkingKinds: ["planning"],
          color: "#a78bfa",
          typicalDuration: "< 50ms",
        },
        {
          id: "query-step1",
          stepNumber: "1",
          name: "Query Understanding",
          shortName: "Understand",
          description:
            "Pronoun resolution, NER extraction, query normalization.",
          thinkingKinds: ["planning"],
          color: "#a78bfa",
          typicalDuration: "< 100ms",
        },
        {
          id: "query-step1-5",
          stepNumber: "1.5",
          name: "Query Expansion",
          shortName: "Expand",
          description:
            "Corpus + container vocabulary expansion. Synonyms, related terms, domain-specific alternatives.",
          thinkingKinds: ["queryRewrite"],
          color: "#34d399",
          typicalDuration: "< 200ms",
        },
        {
          id: "query-step1-6",
          stepNumber: "1.6",
          name: "Intent Classification",
          shortName: "Intent",
          description:
            "Classify query as lookup, procedure, compare, or summarize. Drives downstream routing.",
          thinkingKinds: ["intentRoute"],
          color: "#60a5fa",
          typicalDuration: "< 50ms",
        },
      ],
    },
    {
      id: "embedding-routing",
      label: "EMBEDDING & ROUTING",
      description: "Vector representation + routing (Steps 2-2.5)",
      color: "#60a5fa",
      steps: [
        {
          id: "query-step2",
          stepNumber: "2",
          name: "Query Embedding",
          shortName: "Embed",
          description:
            "MiniLM-L6-v2 encodes user query \u2192 384-dim vector for semantic search.",
          thinkingKinds: ["embedding"],
          color: "#60a5fa",
          typicalDuration: "~10ms",
        },
        {
          id: "query-step2-5",
          stepNumber: "2.5",
          name: "RAPTOR-lite Routing",
          shortName: "Route",
          description:
            'Overview/high-level queries \u2192 L1 summary chunks. Specific queries \u2192 detail chunks. Prevents "tell me about everything" from flooding with fragments.',
          thinkingKinds: ["planning"],
          color: "#a78bfa",
          typicalDuration: "< 50ms",
        },
      ],
    },
    {
      id: "retrieval",
      label: "RETRIEVAL",
      description: "Hybrid search (Step 3)",
      color: "#34d399",
      steps: [
        {
          id: "query-step3",
          stepNumber: "3",
          name: "Hybrid Search",
          shortName: "Search",
          description:
            "Vector Search (vDSP cosine) + BM25 (SQLite FTS5) run concurrently via async let. Results fused with RRF. OR: Iterative Retrieval for multi-hop intents.",
          thinkingKinds: ["retrieval", "vectorSearch", "bm25", "rrf"],
          color: "#34d399",
          typicalDuration: "50-200ms",
          substeps: [
            {
              id: "query-step3-vector",
              name: "Vector Search (Semantic)",
              description:
                "vDSP-accelerated cosine similarity. Metal GPU 3-tier shader: Threadgroup (\u22651000) \u2192 SIMD4 (100+) \u2192 Scalar fallback.",
              color: "#60a5fa",
            },
            {
              id: "query-step3-bm25",
              name: "BM25 (Keyword)",
              description:
                "SQLite FTS5 with AND-first queries, OR fallback. Weighted: section_title 10\u00d7, section_path 5\u00d7, content 1\u00d7.",
              color: "#34d399",
            },
            {
              id: "query-step3-rrf",
              name: "Reciprocal Rank Fusion",
              description:
                "Fuse vector + BM25 ranked lists into single ordering. ~50 candidates output.",
              color: "#f97316",
            },
          ],
        },
      ],
    },
    {
      id: "post-retrieval",
      label: "POST-RETRIEVAL",
      description: "Refine candidates (Steps 4-4.9)",
      color: "#f97316",
      steps: [
        {
          id: "query-step4",
          stepNumber: "4",
          name: "Cross-Encoder Rerank",
          shortName: "Rerank",
          description:
            "TinyBERT cross-encoder scores all query-chunk pairs. Concurrent TaskGroup (2-4 predictions by device tier). MLMultiArray bulk dataPointer writes.",
          thinkingKinds: ["rerank"],
          color: "#f97316",
          typicalDuration: "100-500ms",
        },
        {
          id: "query-step4-3",
          stepNumber: "4.3",
          name: "Low-Confidence Filtering",
          shortName: "Filter",
          description:
            "Remove chunks below relevance threshold. Prevents noise from polluting context window.",
          thinkingKinds: ["gating"],
          color: "#2dd4bf",
          typicalDuration: "< 10ms",
        },
        {
          id: "query-step4-4",
          stepNumber: "4.4",
          name: "Multi-Document Representation",
          shortName: "Multi-Doc",
          description:
            "Ensure source diversity \u2014 don't let one document dominate context. Balance chunks across sources.",
          thinkingKinds: ["retrieval"],
          color: "#34d399",
          typicalDuration: "< 10ms",
        },
        {
          id: "query-step4-5",
          stepNumber: "4.5",
          name: "MMR Diversification",
          shortName: "MMR",
          description:
            "Maximal Marginal Relevance (\u03bb=0.6). Reduce redundancy while preserving relevance. Prevents 5 near-identical chunks.",
          thinkingKinds: ["mmr"],
          color: "#f97316",
          typicalDuration: "< 50ms",
        },
        {
          id: "query-step4-6",
          stepNumber: "4.6",
          name: "Parent Document Retrieval",
          shortName: "Parent",
          description:
            "Expand to \u00b15 sibling chunks around top results. Recovers context split across chunk boundaries.",
          thinkingKinds: ["parentDoc"],
          color: "#22d3ee",
          typicalDuration: "< 50ms",
        },
        {
          id: "query-step4-7",
          stepNumber: "4.7",
          name: "Contextual Compression",
          shortName: "Compress",
          description:
            "LLM filters irrelevant content from chunks. Max 5 chunks, fresh session per chunk. 12s budget, 1s cooldown between.",
          thinkingKinds: ["compression"],
          color: "#22d3ee",
          typicalDuration: "2-12s",
        },
        {
          id: "query-step4-9",
          stepNumber: "4.9",
          name: "Graph Context Packing",
          shortName: "Graph",
          description:
            "Token-budget-aware packing via entity graph. Maximizes information density within 5500 char limit.",
          thinkingKinds: ["graphPack"],
          color: "#a78bfa",
          typicalDuration: "< 100ms",
        },
      ],
    },
    {
      id: "context-assembly",
      label: "CONTEXT ASSEMBLY",
      description: "Prepare for generation (Steps 5-5.11)",
      color: "#22d3ee",
      steps: [
        {
          id: "query-step5",
          stepNumber: "5",
          name: "Context Assembly",
          shortName: "Assemble",
          description:
            "Lost-in-Middle reorder: most important chunks at beginning and end. LLMs pay less attention to middle positions.",
          thinkingKinds: ["context", "lostInMiddle"],
          color: "#22d3ee",
          typicalDuration: "< 10ms",
        },
        {
          id: "query-step5-9",
          stepNumber: "5.9",
          name: "Extractive Summarization",
          shortName: "Extract",
          description:
            "For summarize intent: extract key sentences directly from chunks. Avoids LLM hallucination for pure summary requests.",
          thinkingKinds: ["extractive"],
          color: "#34d399",
          typicalDuration: "< 200ms",
          conditional: "summarize intent only",
        },
        {
          id: "query-step5-10",
          stepNumber: "5.10",
          name: "Extractive QA",
          shortName: "QA",
          description:
            "For lookup intent: try to extract answer directly before entering LLM generation. Can short-circuit Deep Think (saves 4-8 sessions).",
          thinkingKinds: ["extractive"],
          color: "#34d399",
          typicalDuration: "< 200ms",
          conditional: "lookup intent only",
        },
        {
          id: "query-step5-11",
          stepNumber: "5.11",
          name: "Topical Relevance Check",
          shortName: "Topical",
          description:
            'Lexical overlap < 20% \u2192 Evidence-First mode. Cautious prompt: "Do NOT fill gaps with assumptions". Forces confidence disclosure.',
          thinkingKinds: ["grounding"],
          color: "#2dd4bf",
          typicalDuration: "< 10ms",
        },
      ],
    },
    {
      id: "generation",
      label: "GENERATION",
      description: "LLM produces answer (Steps 6-6.5)",
      color: "#fbbf24",
      steps: [
        {
          id: "query-step6",
          stepNumber: "6",
          name: "LLM Generation",
          shortName: "Generate",
          description:
            "Apple Foundation Model (~3B params, 3.7-bit quantized). On-device or Private Cloud Compute. ~30 tokens/sec. Streaming output.",
          thinkingKinds: ["generation"],
          color: "#fbbf24",
          typicalDuration: "2-10s",
        },
        {
          id: "query-step6-5",
          stepNumber: "6.5",
          name: "Response Formatting",
          shortName: "Format",
          description:
            "Markdown preservation pipeline. normalizeInlineMarkdown() preprocessor handles Apple FM's single-line markdown concatenation.",
          thinkingKinds: ["generation"],
          color: "#fbbf24",
          typicalDuration: "< 50ms",
        },
      ],
    },
    {
      id: "verification",
      label: "VERIFICATION",
      description: "Anti-hallucination (Steps 7-7.5)",
      color: "#2dd4bf",
      steps: [
        {
          id: "query-step7",
          stepNumber: "7",
          name: "Quality Assessment",
          shortName: "Assess",
          description:
            "Confidence scoring based on retrieval quality, generation coherence, and evidence alignment.",
          thinkingKinds: ["gating"],
          color: "#2dd4bf",
          typicalDuration: "< 100ms",
        },
        {
          id: "query-step7-5",
          stepNumber: "7.5",
          name: "Verification Gates A-G",
          shortName: "Gates",
          description:
            "7-gate anti-hallucination check. Critical (A,B,C,D,E) \u2192 abstain on fail. Advisory (F,G) \u2192 confidence penalty only.",
          thinkingKinds: ["verification", "grounding"],
          color: "#2dd4bf",
          typicalDuration: "< 200ms",
          substeps: [
            {
              id: "gate-a",
              name: "Gate A: Retrieval Confidence",
              description: "Top retrieval score meets threshold",
              type: "critical",
              color: "#ef4444",
            },
            {
              id: "gate-b",
              name: "Gate B: Evidence Coverage",
              description: "Claims cite retrieved chunks",
              type: "critical",
              color: "#ef4444",
            },
            {
              id: "gate-c",
              name: "Gate C: Numeric Sanity",
              description: "Numbers match sources (year/1-10 exemption)",
              type: "critical",
              color: "#ef4444",
            },
            {
              id: "gate-d",
              name: "Gate D: Contradiction Sweep",
              description: "No conflicting evidence across chunks",
              type: "critical",
              color: "#ef4444",
            },
            {
              id: "gate-e",
              name: "Gate E: Semantic Grounding",
              description:
                "vDSP cosine: response embedding aligned with chunks",
              type: "critical",
              color: "#ef4444",
            },
            {
              id: "gate-f",
              name: "Gate F: Quote Faithfulness",
              description: "Jaccard abbreviation verification",
              type: "advisory",
              color: "#fbbf24",
            },
            {
              id: "gate-g",
              name: "Gate G: Generation Quality",
              description: "Entropy/uniqueness checks catch repetition",
              type: "advisory",
              color: "#fbbf24",
            },
          ],
        },
      ],
    },
    {
      id: "output",
      label: "OUTPUT",
      description: "Package & render (Steps 8-10)",
      color: "#818cf8",
      steps: [
        {
          id: "query-step8",
          stepNumber: "8",
          name: "Package Results",
          shortName: "Package",
          description:
            "Assemble final response with metadata, source attribution, and confidence score.",
          thinkingKinds: ["confidence"],
          color: "#818cf8",
          typicalDuration: "< 10ms",
        },
        {
          id: "query-step8-1",
          stepNumber: "8.1",
          name: "Calibrated Confidence",
          shortName: "Calibrate",
          description:
            "Platt scaling converts raw confidence to calibrated probability estimate.",
          thinkingKinds: ["confidence"],
          color: "#818cf8",
          typicalDuration: "< 5ms",
        },
        {
          id: "query-step9",
          stepNumber: "9",
          name: "Response Metadata",
          shortName: "Meta",
          description:
            "Timing, sources, model used, tokens generated, tokens/sec, TTFT, gating decision, retrieval config.",
          thinkingKinds: [],
          color: "#818cf8",
          typicalDuration: "< 5ms",
        },
        {
          id: "query-step10",
          stepNumber: "10",
          name: "Markdown Rendering",
          shortName: "Render",
          description:
            "Block-level parser + inline normalizer. 6 regex patterns for Apple FM output quirks.",
          thinkingKinds: [],
          color: "#818cf8",
          typicalDuration: "< 10ms",
        },
      ],
    },
  ],
  agenticOverlay: {
    description:
      "For Deep Think and Maximum modes, AgenticOrchestrator wraps the query pipeline with multi-session reasoning.",
    steps: [
      {
        id: "agentic-selfrag",
        name: "Self-RAG Check",
        description:
          "Does this question even need documents? (If user asks '2+2', skip retrieval).",
        thinkingKinds: ["selfRag"],
        color: "#2dd4bf",
      },
      {
        id: "agentic-evaluate",
        name: "Evaluate Retrieval Quality",
        description:
          "Check lexical relevance + semantic intent. Excellent \u2192 reasoning. Poor \u2192 graph expansion.",
        thinkingKinds: ["grounding"],
        color: "#2dd4bf",
      },
      {
        id: "agentic-hyde",
        name: "HyDE (Hypothetical Document)",
        description:
          "Generate hypothetical answer, embed it, search with that embedding. Finds answers the original query might miss.",
        thinkingKinds: ["hyde"],
        color: "#60a5fa",
      },
      {
        id: "agentic-iterative",
        name: "Iterative Retrieval",
        description:
          "LLM analyzes gaps \u2192 generates new queries \u2192 retrieves again. 4-8 cycles for Deep Think, 8-50 for Maximum.",
        thinkingKinds: ["iterative", "queryRewrite"],
        color: "#f472b6",
      },
      {
        id: "agentic-accumulate",
        name: "Accumulation Pattern",
        description:
          "Each session's output saved to memory. Next session receives accumulated insights as input. Builds answers larger than any single context window.",
        thinkingKinds: ["agentic", "selfRag"],
        color: "#a78bfa",
      },
      {
        id: "agentic-factbank",
        name: "FactBank (Maximum)",
        description:
          "Maximum mode: parallel Deep Think chains on different document clusters. Results merged via cluster synthesis.",
        thinkingKinds: ["factBank", "agentic"],
        color: "#6366f1",
      },
      {
        id: "agentic-synthesis",
        name: "Final Synthesis",
        description:
          "Combine all session outputs into coherent final answer. Self-RAG 2.0: sessions ADD details, don't second-guess valid answers.",
        thinkingKinds: ["agentic", "generation"],
        color: "#fbbf24",
      },
    ],
  },
  thinkingKindMap: {
    planning: {
      displayName: "Planning",
      color: "#a78bfa",
      icon: "list-bullet",
    },
    embedding: { displayName: "Embedding", color: "#60a5fa", icon: "brain" },
    retrieval: { displayName: "Retrieval", color: "#34d399", icon: "search" },
    rerank: { displayName: "Re-ranking", color: "#f97316", icon: "branch" },
    gating: {
      displayName: "Confidence Gate",
      color: "#2dd4bf",
      icon: "shield",
    },
    context: {
      displayName: "Context Assembly",
      color: "#22d3ee",
      icon: "layers",
    },
    generation: {
      displayName: "Generation",
      color: "#fbbf24",
      icon: "sparkles",
    },
    fallback: { displayName: "Fallback", color: "#f472b6", icon: "undo" },
    warning: { displayName: "Warning", color: "#ef4444", icon: "alert" },
    hyde: { displayName: "HyDE", color: "#60a5fa", icon: "doc-search" },
    queryRewrite: {
      displayName: "Query Rewrite",
      color: "#34d399",
      icon: "pencil",
    },
    bm25: { displayName: "BM25 (Keyword)", color: "#34d399", icon: "text" },
    vectorSearch: {
      displayName: "Vector Search",
      color: "#60a5fa",
      icon: "cube",
    },
    rrf: { displayName: "RRF Fusion", color: "#f97316", icon: "merge" },
    mmr: { displayName: "MMR Diversity", color: "#f97316", icon: "layers-3d" },
    parentDoc: {
      displayName: "Parent Doc Expansion",
      color: "#22d3ee",
      icon: "doc-stack",
    },
    compression: {
      displayName: "Compression",
      color: "#22d3ee",
      icon: "compress",
    },
    lostInMiddle: {
      displayName: "Position Reorder",
      color: "#22d3ee",
      icon: "sort",
    },
    grounding: {
      displayName: "Grounding Check",
      color: "#2dd4bf",
      icon: "checkmark",
    },
    selfRag: { displayName: "Self-RAG", color: "#2dd4bf", icon: "cycle" },
    iterative: {
      displayName: "Iterative Retrieval",
      color: "#f472b6",
      icon: "repeat",
    },
    agentic: {
      displayName: "Agentic Step",
      color: "#a78bfa",
      icon: "brain-full",
    },
    toolCall: { displayName: "Tool Call", color: "#6366f1", icon: "function" },
    factBank: { displayName: "FactBank", color: "#6366f1", icon: "tray" },
    verification: {
      displayName: "Verification Gates",
      color: "#2dd4bf",
      icon: "shield-check",
    },
    graphPack: {
      displayName: "Graph Context",
      color: "#a78bfa",
      icon: "graph",
    },
    extractive: {
      displayName: "Extractive Summary",
      color: "#34d399",
      icon: "quote",
    },
    intentRoute: {
      displayName: "Intent Routing",
      color: "#60a5fa",
      icon: "route",
    },
    confidence: {
      displayName: "Confidence Calibration",
      color: "#f97316",
      icon: "chart",
    },
    imagePlayground: {
      displayName: "Image Playground",
      color: "#2dd4bf",
      icon: "image",
    },
  },
};

// ═══════════════════════════════════════════════════════════════
// DEMO TRACES
// ═══════════════════════════════════════════════════════════════

const DEMO_TRACES = {
  // ─── Standard Mode: Engine Oil Query ───
  standard: `\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
  OPENINTELLIGENCE PIPELINE TRACE
  Generated: 2026-03-06T15:42:18Z
  Message ID: A1B2C3D4-E5F6-7890-ABCD-EF1234567890
  Container: 98765432-ABCD-EF12-3456-789012345678
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550

\u25b6 QUERY
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
What is the recommended engine oil type and capacity for a 2024 model?

\u25b6 RESPONSE (847 chars)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
Based on the owner's manual, the recommended engine oil for the 2024 model is **SAE 0W-20** full synthetic oil meeting API SP or ILSAC GF-6A specifications.

**Engine Oil Capacity:**
- With filter change: **5.1 quarts (4.8 liters)**
- Without filter change: **4.7 quarts (4.4 liters)**

**Important Notes:**
1. Always use the dipstick to verify the oil level after filling
2. Do not overfill \u2014 excess oil can damage the catalytic converter
3. The oil change interval is every 7,500 miles or 12 months under normal conditions
4. For severe driving conditions (frequent short trips, dusty roads, towing), reduce the interval to 5,000 miles

*Source: Owner's Manual, Section 8 \u2014 Maintenance, pp. 287-291*

\u25b6 METADATA
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Model:            Apple Foundation Model (On-Device)
  Quality Mode:     Standard
  Agentic:          NO
  Retrieval Config: Hybrid (Vector + BM25 + RRF) \u2192 Rerank \u2192 MMR
  Retrieval Time:   142ms
  Total Gen Time:   3.8s
  TTFT:             187ms
  Tokens Generated: 218
  Tokens/sec:       28.4
  Gating:           PASS (A\u2713 B\u2713 C\u2713 D\u2713 E\u2713 F\u2713 G\u2713)
  Embedding:        CoreML MiniLM-L6-v2 (384-dim)

\u25b6 THINKING EVENTS (18 events)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  +000000ms [Planning] Analyzing query: "engine oil type and capacity"
  +000012ms [Planning] Intent classified: lookup (direct answer expected)
  +000018ms [Query Rewrite] Expanding query with corpus vocabulary
  +000035ms [Query Rewrite] Expanded: ["engine oil", "SAE 0W-20", "oil capacity", "quarts", "liters", "lubricant"]
  +000042ms [Embedding] Encoding query \u2192 384-dim vector (MiniLM-L6-v2)
  +000053ms [Planning] RAPTOR-lite: routing to detail chunks (specific query)
  +000058ms [Vector Search] Searching 12,847 vectors via Metal GPU (Threadgroup shader)
  +000072ms [BM25 (Keyword)] FTS5 AND-first: "engine" AND "oil" AND "capacity"
  +000089ms [RRF Fusion] Fusing 48 vector + 31 BM25 results \u2192 52 candidates
  +000094ms [Re-ranking] Cross-encoder scoring 52 pairs (TinyBERT, 4 concurrent)
  +000198ms [Re-ranking] Top score: 0.9847 (Section 8 \u2014 Maintenance, p.287)
  +000204ms [Confidence Gate] Low-confidence filter: 52 \u2192 19 candidates
  +000209ms [MMR Diversity] \u03bb=0.6 diversification: 19 \u2192 8 chunks
  +000218ms [Parent Doc Expansion] Expanding \u00b15 siblings for top 3 chunks
  +000231ms [Position Reorder] Lost-in-Middle: placing strongest at start/end
  +000238ms [Context Assembly] Packed 6 chunks into 4,812 chars (within 5,500 limit)
  +000241ms [Generation] Apple FM: streaming 218 tokens @ 28.4 tok/s
  +003812ms [Verification Gates] Gates A-G: all PASS \u2502 Confidence: 0.94

\u25b6 PIPELINE LOG (12 entries)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  [15:42:18.001] queryInternal() started \u2014 Standard mode
  [15:42:18.012] Query expansion: 6 terms added from container vocab
  [15:42:18.053] Query embedded: 384-dim, 11ms
  [15:42:18.058] RAPTOR-lite: detail routing (specific lookup detected)
  [15:42:18.089] Hybrid search complete: 52 RRF candidates in 31ms
  [15:42:18.198] Cross-encoder rerank complete: 104ms, top=0.9847
  [15:42:18.218] Post-retrieval pipeline: filter\u2192MMR\u2192parent\u2192compress in 20ms
  [15:42:18.231] Context packing: 6 chunks, 4812 chars, budget OK
  [15:42:18.238] LLM generation started (Apple FM on-device)
  [15:42:18.425] First token received: TTFT=187ms
  [15:42:21.812] Generation complete: 218 tokens in 3574ms
  [15:42:21.838] Verification gates PASS: A\u2713 B\u2713 C\u2713 D\u2713 E\u2713 F\u2713 G\u2713 (conf=0.94)

\u25b6 RETRIEVED CHUNKS (6 chunks)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  \u2500\u2500 Chunk 1 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       1
  Similarity: 0.9847
  Page:       287
  Section:    Engine Oil Specifications
  Path:       Maintenance > Fluids > Engine Oil
  Structure:  table
  Content:    Engine Oil Type: SAE 0W-20 API SP or ILSAC GF-6A. Oil Capacity (with filter): 5.1 qt (4.8 L). Oil Capacity (without filter): 4.7 qt (4.4 L). Recommended brands: Mobil 1, Castrol EDGE, Pennzoil Platinum. Do not use oils below API SN specification...

  \u2500\u2500 Chunk 2 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       2
  Similarity: 0.9234
  Page:       288
  Section:    Oil Change Procedure
  Path:       Maintenance > Fluids > Engine Oil
  Structure:  paragraph
  Content:    To change the engine oil: 1. Warm the engine to operating temperature. 2. Position the vehicle on a level surface. 3. Remove the drain plug (14mm) and drain completely. 4. Replace the oil filter with a genuine OEM filter (Part #26350-2M000). 5. Install drain plug with new washer, torque to 25-33 ft-lb...

  \u2500\u2500 Chunk 3 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       3
  Similarity: 0.8912
  Page:       289
  Section:    Maintenance Schedule
  Path:       Maintenance > Schedule
  Structure:  table
  Content:    Oil Change Intervals: Normal conditions: 7,500 miles / 12 months. Severe conditions: 5,000 miles / 6 months. Severe conditions include: frequent short trips < 5 miles, dusty/sandy environments, extensive idling, trailer towing, mountainous terrain...

  \u2500\u2500 Chunk 4 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       4
  Similarity: 0.8456
  Page:       291
  Section:    Oil Level Check
  Path:       Maintenance > Fluids > Engine Oil
  Structure:  paragraph
  Content:    Checking oil level: 1. Park vehicle on level ground. 2. Wait 5 minutes after engine shutdown. 3. Remove dipstick, wipe clean, reinsert fully. 4. Remove again and read level. Oil should be between LOW and FULL marks. If below LOW, add 0.5 qt increments...

  \u2500\u2500 Chunk 5 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       5
  Similarity: 0.7823
  Page:       290
  Section:    Oil Warning Indicators
  Path:       Maintenance > Warning Lights
  Structure:  paragraph
  Content:    OIL PRESSURE WARNING: If oil pressure light illuminates while driving, pull over safely and turn off engine immediately. Check oil level. Do not continue driving with low oil pressure \u2014 engine damage will occur within minutes...

  \u2500\u2500 Chunk 6 \u2500\u2500
  Source:     2024_Service_Bulletin_TSB-24-031.pdf
  Rank:       6
  Similarity: 0.7234
  Page:       1
  Section:    Oil Consumption TSB
  Path:       Technical Service Bulletins
  Structure:  paragraph
  Content:    TSB-24-031: Some 2024 models manufactured before VIN cutoff may exhibit higher than normal oil consumption (>1 qt per 3000 miles). Affected units should have piston rings inspected. Warranty extension applies per Campaign 24-V-089...

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
  END OF TRACE
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550`,

  // ─── Deep Think Mode: Brake Pad Comparison ───
  deepThink: `\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
  OPENINTELLIGENCE PIPELINE TRACE
  Generated: 2026-03-06T16:15:42Z
  Message ID: F7E8D9C0-B1A2-3456-7890-ABCDEF123456
  Container: 98765432-ABCD-EF12-3456-789012345678
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550

\u25b6 QUERY
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
Compare the brake pad replacement procedure for front and rear brakes, including any special tools required and torque specifications

\u25b6 RESPONSE (1423 chars)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
Here's a detailed comparison of the front and rear brake pad replacement procedures:

## Front Brake Pads

**Tools Required:**
- 17mm socket for caliper bracket bolts
- C-clamp or brake piston tool for compressing piston
- Brake cleaner spray

**Procedure:**
1. Remove wheel (lug nuts: 80 ft-lb)
2. Remove caliper bracket bolts (torque: 74-88 ft-lb)
3. Slide caliper off rotor, support with wire \u2014 **never let it hang by the brake line**
4. Compress piston fully with C-clamp
5. Install new pads (wear indicator faces inward)
6. Reassemble. Bracket bolts: **74-88 ft-lb**

## Rear Brake Pads

**Tools Required:**
- 14mm socket for caliper bracket bolts
- **Special tool: Brake piston rotation tool** (rear pistons screw in, they do NOT push straight back)
- Brake cleaner spray

**Procedure:**
1. Remove wheel (lug nuts: 80 ft-lb)
2. Remove caliper bracket bolts (torque: 44-58 ft-lb \u2014 lighter than front)
3. Slide caliper off rotor, support with wire
4. **Rotate piston clockwise** while pressing in (requires rotation tool)
5. Install new pads (wear indicator faces inward)
6. Reassemble. Bracket bolts: **44-58 ft-lb**

## Key Differences

| Aspect | Front | Rear |
|--------|-------|------|
| Bracket bolt size | 17mm | 14mm |
| Bracket bolt torque | 74-88 ft-lb | 44-58 ft-lb |
| Piston compression | Push straight in | **Rotate clockwise** |
| Special tool needed | No | Yes (rotation tool) |
| Pad wear rate | Higher (70% of braking) | Lower |

*Sources: Service Manual Chapter 5 (pp. 127-135), TSB-24-BR-012*

\u25b6 METADATA
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Model:            Apple Foundation Model (On-Device)
  Quality Mode:     Deep Think
  Agentic:          YES
  Retrieval Config: Hybrid \u2192 Rerank \u2192 Iterative Retrieval (5 cycles)
  Retrieval Time:   3,847ms
  Total Gen Time:   18.2s
  TTFT:             312ms
  Tokens Generated: 487
  Tokens/sec:       26.8
  Gating:           PASS (A\u2713 B\u2713 C\u2713 D\u2713 E\u2713 F\u2713 G\u2713)
  Embedding:        CoreML MiniLM-L6-v2 (384-dim)
  Tool Calls:       0

\u25b6 THINKING EVENTS (42 events)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  +000000ms [Planning] Analyzing query: "compare brake pad replacement front vs rear"
  +000015ms [Planning] Intent classified: compare (multi-part, needs both sets of data)
  +000022ms [Query Rewrite] Expanding with corpus vocab: ["brake pad", "caliper", "torque", "ft-lb", "piston"]
  +000038ms [Embedding] Encoding query \u2192 384-dim vector
  +000049ms [Planning] RAPTOR-lite: routing to detail chunks (procedure query)
  +000055ms [Vector Search] Searching 12,847 vectors via Metal GPU
  +000071ms [BM25 (Keyword)] FTS5: "brake" AND "pad" AND "replacement"
  +000088ms [RRF Fusion] Fusing results \u2192 67 candidates
  +000095ms [Re-ranking] Cross-encoder scoring 67 pairs (4 concurrent)
  +000312ms [Confidence Gate] Low-confidence filter: 67 \u2192 24 candidates
  +000320ms [MMR Diversity] \u03bb=0.6: 24 \u2192 12 chunks
  +000335ms [Parent Doc Expansion] Expanding \u00b15 siblings for top 5 chunks
  +000398ms [Context Assembly] Initial: 8 chunks, 4,920 chars
  +000410ms [Self-RAG] Evaluating: does initial retrieval cover both front AND rear?
  +000425ms [Self-RAG] Gap detected: rear brake procedure underrepresented (1/8 chunks)
  +000430ms [Agentic Step] Session 1: Initial synthesis \u2014 front brakes well-covered
  +000445ms [Query Rewrite] Generating focused query: "rear brake pad replacement procedure piston rotation tool"
  +001200ms [Iterative Retrieval] Cycle 2: re-searching with rear-focused query
  +001215ms [Vector Search] Searching with refined embedding
  +001228ms [BM25 (Keyword)] FTS5: "rear" AND "brake" AND "piston" AND "rotation"
  +001245ms [RRF Fusion] Cycle 2: 41 new candidates
  +001260ms [Re-ranking] Cross-encoder scoring cycle 2 results
  +001480ms [MMR Diversity] Merging cycle 2 with existing: 16 unique chunks
  +001502ms [Agentic Step] Session 2: Rear brake data now available \u2014 torque specs found
  +001520ms [Self-RAG] Evaluating completeness: front \u2713, rear \u2713, torque \u2713, tools \u2713
  +002100ms [Query Rewrite] Generating focused query: "brake pad torque specifications special tools required"
  +002800ms [Iterative Retrieval] Cycle 3: searching for torque and tool details
  +002815ms [Vector Search] Searching with torque-focused embedding
  +002830ms [BM25 (Keyword)] FTS5: "torque" AND "brake" AND "specification"
  +002950ms [RRF Fusion] Cycle 3: 28 candidates
  +002975ms [Re-ranking] Cycle 3 rerank complete
  +003100ms [Agentic Step] Session 3: Torque specs confirmed \u2014 74-88 front, 44-58 rear
  +003120ms [Self-RAG] All aspects covered: procedure, tools, torque, comparison
  +003200ms [Compression] Compressing 16 \u2192 10 chunks (5 sent to LLM compression)
  +003850ms [Compression] Compression complete: 10 chunks, 5,280 chars
  +003860ms [Grounding Check] Topical relevance: 78% lexical overlap \u2014 standard mode
  +003875ms [Context Assembly] Final: 10 chunks, 5,280 chars (within 5,500 limit)
  +003890ms [Position Reorder] Lost-in-Middle applied
  +003900ms [Generation] Apple FM: streaming 487 tokens @ 26.8 tok/s
  +017800ms [Verification Gates] Gate A: PASS (top=0.9612)
  +017820ms [Verification Gates] Gate C: PASS (numbers verified: 74-88, 44-58, 80, 17mm, 14mm)
  +017850ms [Verification Gates] Gates A-G: all PASS \u2502 Confidence: 0.91

\u25b6 PIPELINE LOG (24 entries)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  [16:15:42.001] queryInternal() started \u2014 Deep Think mode
  [16:15:42.015] Intent: compare \u2014 enabling iterative retrieval
  [16:15:42.022] Query expansion: 5 terms from container vocab
  [16:15:42.049] Query embedded: 384-dim, 11ms
  [16:15:42.088] Hybrid search: 67 RRF candidates in 33ms
  [16:15:42.312] Rerank complete: 224ms, top=0.9612
  [16:15:42.410] Self-RAG check: gap detected (rear brakes underrepresented)
  [16:15:42.430] Agentic session 1: initial front brake synthesis
  [16:15:42.445] Iterative query generated: "rear brake pad replacement procedure..."
  [16:15:43.480] Iterative cycle 2 complete: +41 candidates, 16 unique chunks
  [16:15:43.502] Agentic session 2: rear brake data integrated
  [16:15:43.520] Self-RAG: front \u2713 rear \u2713 torque \u2713 tools \u2014 still need tool confirmation
  [16:15:44.100] Iterative query generated: "brake pad torque specifications..."
  [16:15:44.975] Iterative cycle 3 complete: +28 candidates
  [16:15:45.100] Agentic session 3: torque confirmed, tool confirmed (rotation tool)
  [16:15:45.120] Self-RAG: all 4 aspects covered \u2014 proceeding to compression
  [16:15:45.200] Contextual compression: 5 chunks sent to FM
  [16:15:45.850] Compression complete: 850ms, 16\u219210 chunks, 5280 chars
  [16:15:45.875] Context packing: 10 chunks, 5280 chars, budget OK
  [16:15:45.890] LLM generation started \u2014 Deep Think final synthesis
  [16:15:46.202] First token: TTFT=312ms
  [16:15:59.800] Generation complete: 487 tokens in 13.6s
  [16:15:59.850] Verification gates: all PASS, confidence=0.91
  [16:15:59.860] Deep Think pipeline complete: 3 agentic sessions, 18.2s total

\u25b6 REASONING TRACE (3 sessions)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Session 1: Found comprehensive front brake procedure (Section 5.3, pp.127-130). Front uses 17mm bracket bolts, 74-88 ft-lb torque. Standard C-clamp piston compression. Gap: only 1 chunk mentions rear brakes in passing.
  Session 2: Retrieved rear brake specifics (Section 5.4, pp.131-134). Key difference: rear pistons require ROTATION (clockwise) not push-in. Special rotation tool needed. 14mm bracket bolts, 44-58 ft-lb (lighter than front). TSB-24-BR-012 confirms rotation tool requirement.
  Session 3: Confirmed all torque specifications from Service Manual torque table (p.135). Lug nuts: 80 ft-lb (both). Added wear rate context: front handles 70% of braking force. Comparison table structure planned for response.

\u25b6 RETRIEVED CHUNKS (10 chunks)
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  \u2500\u2500 Chunk 1 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       1
  Similarity: 0.9612
  Page:       127
  Section:    Front Brake Pad Replacement
  Path:       Chapter 5 > Brakes > Front
  Structure:  paragraph
  Content:    Front Brake Pad Replacement Procedure: 1. Raise vehicle and support on jack stands. 2. Remove front wheel. 3. Remove two 17mm caliper bracket bolts. 4. Slide caliper assembly off rotor. CAUTION: Support caliper with wire...

  \u2500\u2500 Chunk 2 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       2
  Similarity: 0.9445
  Page:       131
  Section:    Rear Brake Pad Replacement
  Path:       Chapter 5 > Brakes > Rear
  Structure:  paragraph
  Content:    Rear Brake Pad Replacement Procedure: WARNING \u2014 Rear caliper pistons must be ROTATED clockwise while compressing. Do NOT attempt to push piston straight in \u2014 this will damage the self-adjusting mechanism. Use brake piston rotation tool (SST 0...

  \u2500\u2500 Chunk 3 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       3
  Similarity: 0.9201
  Page:       135
  Section:    Brake System Torque Specifications
  Path:       Chapter 5 > Brakes > Specifications
  Structure:  table
  Content:    Brake System Torque Table: Front caliper bracket: 74-88 ft-lb (100-120 N\u00b7m). Rear caliper bracket: 44-58 ft-lb (60-78 N\u00b7m). Wheel lug nut: 80 ft-lb (108 N\u00b7m). Brake line fitting: 11-13 ft-lb (15-18 N\u00b7m). Bleed screw: 7 ft-lb (10 N\u00b7m)...

  \u2500\u2500 Chunk 4 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       4
  Similarity: 0.8934
  Page:       128
  Section:    Front Brake Pad Replacement (cont.)
  Path:       Chapter 5 > Brakes > Front
  Structure:  paragraph
  Content:    5. Use C-clamp to compress front caliper piston fully. Place old brake pad against piston face to distribute force evenly. 6. Remove old pads. Note position of wear indicator tab \u2014 it must face inward (toward piston)...

  \u2500\u2500 Chunk 5 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       5
  Similarity: 0.8756
  Page:       132
  Section:    Rear Brake Pad Replacement (cont.)
  Path:       Chapter 5 > Brakes > Rear
  Structure:  paragraph
  Content:    4. Using brake piston rotation tool, rotate rear piston CLOCKWISE while applying inward pressure. Piston will thread inward as it rotates. Continue until fully seated. 5. Remove two 14mm caliper bracket bolts (torque on reassembly: 44-58 ft-lb)...

  \u2500\u2500 Chunk 6 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       6
  Similarity: 0.8512
  Page:       133
  Section:    Required Special Tools
  Path:       Chapter 5 > Brakes > Tools
  Structure:  table
  Content:    Special Service Tools \u2014 Brakes: Brake piston rotation tool (SST 09581-11000 or equivalent). Brake fluid tester. Dial indicator for rotor runout. Micrometer for pad/rotor thickness. Note: Generic aftermarket rotation tools available...

  \u2500\u2500 Chunk 7 \u2500\u2500
  Source:     2024_Owners_Manual.pdf
  Rank:       7
  Similarity: 0.8234
  Page:       305
  Section:    Brake System Overview
  Path:       Maintenance > Brakes
  Structure:  paragraph
  Content:    Your vehicle uses ventilated disc brakes on all four wheels. The front brakes are larger and handle approximately 70% of braking force. Rear brakes include an integrated parking brake mechanism. Brake pad thickness should be checked every 15K miles...

  \u2500\u2500 Chunk 8 \u2500\u2500
  Source:     TSB-24-BR-012.pdf
  Rank:       8
  Similarity: 0.7890
  Page:       1
  Section:    Rear Brake Piston Tool Clarification
  Path:       Technical Service Bulletins
  Structure:  paragraph
  Content:    TSB-24-BR-012: Clarification on rear caliper piston compression. Some technicians have reported inability to compress rear pistons using a C-clamp. This is by design \u2014 rear pistons require rotation. Universal brake piston tool kits are acceptable...

  \u2500\u2500 Chunk 9 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       9
  Similarity: 0.7645
  Page:       129
  Section:    Brake Pad Bedding Procedure
  Path:       Chapter 5 > Brakes > Break-In
  Structure:  paragraph
  Content:    After installing new brake pads, perform bedding procedure: 1. Drive at 35 mph. 2. Apply moderate braking to reduce speed to 5 mph. 3. Repeat 6-8 times with 30-second cooling intervals. 4. Drive normally for 100 miles avoiding hard braking...

  \u2500\u2500 Chunk 10 \u2500\u2500
  Source:     2024_Service_Manual.pdf
  Rank:       10
  Similarity: 0.7234
  Page:       134
  Section:    Brake System Bleeding
  Path:       Chapter 5 > Brakes > Bleeding
  Structure:  paragraph
  Content:    Brake system must be bled after any brake line disconnection. Bleeding order: RR \u2192 LR \u2192 RF \u2192 LF (farthest to nearest). Use DOT 4 brake fluid only. Two-person method or vacuum bleeder acceptable. Bleed until no air bubbles visible...

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
  END OF TRACE
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550`,
};
