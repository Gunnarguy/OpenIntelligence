# OpenIntelligence, edge to edge

> **Documentation status:** Written 2026-09-02 against commit `9c6fcbc`. Every concept name that
> looks like a code identifier was grepped against the Swift tree (115 of 116 found; the one miss is
> noted in module 07). Every number was taken from `Docs/Engineering/FULL_SYSTEM_TRACE.md`, which
> cites its line, or from a grep run while writing the module. Where the 612-term word bank or the
> Opus walkthrough disagrees with source, the module says so and source wins.
> `[evidence_level: code_verified_for_symbols_and_constants, confidence: high; status_labels: artifact_derived, confidence: medium]`

This is every one of the 612 concepts in the word bank, in pipeline order, explained at more than one level, with what was verified and what was corrected. It is the document you asked for so you never have to do this again. You will turn it into audio; it is written to be read aloud, so identifiers are kept to the expert rungs and every module opens with plain language.

## How it is built

Seventeen modules, the same seventeen the word bank uses, in the order the app runs. Each module has two parts.

**The ladder.** Seven rungs, the whole module at each depth:

1. Like you're five.
2. Like an idiot.
3. Like less of an idiot.
4. Average Joe.
5. Dot-connector: the person who is good at connecting things and doesn't know this yet.
6. Expert.
7. Expert's expert: the numbers, the code, the hazards, the corrections.

**Every concept.** Each of the module's concepts, with its status label from the word bank and a verification note, at three rungs: idiot, dot-connector, expert. Seven rungs per concept would have been four thousand paragraphs of the same sentence reworded; three is where the information actually changes.

The status labels are the word bank's audit vocabulary, not a runtime type: **Core** runs on the default path; **Conditional** runs in some modes or for some inputs; **Support** is diagnostics and evaluation; **Dormant** is in the source and on no shipping path; **Future** is a reserved name; **Historical** is superseded and misleading if taught as current. "Verified" after a status means the symbol was found in the Swift tree or the constant was read from source this week.

## The whole thing in twelve sentences

1. A file is enqueued as a durable ticket and processed one document at a time.
2. Its text is extracted by type: text layer, 360 DPI OCR, structured table parsing, XML, CSV, or on-device speech.
3. The text is cut into chunks of at most 310 words, validated at 430 tokens by the real tokenizer, each with a contextual prefix.
4. Each chunk becomes a normalised 384-dimension vector, on Core ML or Core AI, with the compute units requested by the GPU profile.
5. Chunks are written to SQLite FTS5 and to a memory-mapped vector file; summaries and entities are derived on top.
6. A question is profiled and planned first: intent, complexity, mode, and whether it is agentic.
7. Vector search and BM25 run in parallel and are fused with reciprocal rank fusion at k = 60.
8. A cross-encoder reranks the shortlist; a similarity floor and maximal marginal relevance cut it; neighbours are added.
9. Evidence is packed under the real token budget, strongest first and last.
10. A post-retrieval plan chooses abstain, deterministic, on-device, or Private Cloud Compute, and only then asks for consent.
11. The model streams a typed answer with citations; nine deterministic gates decide what survives.
12. What comes back is inspectable: claims, byte-offset citations, the completed route, and a trace.

## The thread through all of it

Every mechanism in this app is one of two things. It keeps the promise, that your documents stay yours: container isolation, local-first, on-device everything, memory-mapped vectors so a phone can hold a library, one outside room used only after retrieval with a shown payload and your consent. Or it defends against the danger, that a language model invents: two indexes, a cross-encoder second opinion, a similarity floor, diversity, a recorded budget, exactly two generative stages with nine deterministic gates aimed at them, citations to character ranges, and a badge that reports what completed rather than what was requested. If you cannot say which of the two a piece serves, you do not understand that piece yet.

## Corrections to the earlier documents, in one place

| Claim as taught | What the source says | Module |
|---|---|---|
| Audio goes through `SpeechAnalyzer` | The branch never compiles. `SFSpeechRecognizer`, on device, 600-second segments. | 02, 16 |
| Embeddings run on the Neural Engine | Requested, not placed. Efficiency and Balanced request CPU + Neural Engine; Performance and Maximum request all units; Core ML decides; Core AI exposes nothing. | 05, 15 |
| The GPU profile decides whether vector search uses Metal | It does not. The switch is 1,000 vectors and a Metal device. The profile gates Core ML units and the MMR matrix. | 06, 15 |
| `RecognizeDocumentsRequest` does OCR | It parses structure and tables. `VNRecognizeTextRequest` does OCR. | 02 |
| Page rendering is zero-copy | The PNG round trip is skipped; a full-page bitmap is still allocated. | 02 |
| Maximum's verification bar is 0.98 | 0.80. The 0.98 is the agentic loop's stopping target. | 00, 11, 12 |
| The advanced on-device model | Executes the default model. No advanced model exists in the SDK. | 10 |
| Core AI is a fallback | On iOS 27 and macOS 27 it is the default and saved Core ML defaults are migrated. | 05 |
| About six registered tools | Ten. | 10 |
| `NO_RELEVANT_CONTENT` triggers rescue or passthrough | Inside the compressor, yes; the caller in `RAGService` removes the chunk entirely. | 09 |
| Weighted progress has no named constant | It does: `pipelineStageWeights`, extraction 0.52. | 01 |
| TinyBERT reranker name is unverified | It is documented provenance: `cross-encoder/ms-marco-TinyBERT-L2-v2` in the notices file. | 08 |
| Fourteen ingestion stages | Fifteen; the enum also has `paused`. | 01 |

## The modules

| Module | Concepts | File |
|---|---|---|
| 00 System architecture and boundaries | 14 | `00_System_architecture_and_boundaries.md` |
| 01 Ingestion control, identity, and lifecycle | 19 | `01_Ingestion_control_identity_and_lifecycle.md` |
| 02 File extraction and document understanding | 52 | `02_File_extraction_and_document_understanding.md` |
| 03 Document analysis, adaptation, and derived knowledge | 15 | `03_Document_analysis_adaptation_and_derived_knowledge.md` |
| 04 Chunking and tokenizer integrity | 21 | `04_Chunking_and_tokenizer_integrity.md` |
| 05 Embeddings and vector semantics | 33 | `05_Embeddings_and_vector_semantics.md` |
| 06 Lexical indexing, SQLite, and vector persistence | 49 | `06_Lexical_indexing_SQLite_and_vector_persistence.md` |
| 07 Query understanding, intent, and execution planning | 45 | `07_Query_understanding_intent_and_execution_planning.md` |
| 08 Retrieval, fusion, reranking, and evidence expansion | 60 | `08_Retrieval_fusion_reranking_and_evidence_expansion.md` |
| 09 Context selection, compression, and token packing | 27 | `09_Context_selection_compression_and_token_packing.md` |
| 10 Model execution, routing, tools, and generation | 62 | `10_Model_execution_routing_tools_and_generation.md` |
| 11 Agentic, recursive, and multi-session reasoning | 40 | `11_Agentic_recursive_and_multi_session_reasoning.md` |
| 12 Verification, grounding, confidence, and abstention | 40 | `12_Verification_grounding_confidence_and_abstention.md` |
| 13 Response structure, provenance, rendering, and observability | 35 | `13_Response_structure_provenance_rendering_and_observability.md` |
| 14 Evaluation, benchmarks, and quality measurement | 31 | `14_Evaluation_benchmarks_and_quality_measurement.md` |
| 15 Device adaptation, compute, background work, sync, and product limits | 44 | `15_Device_adaptation_compute_background_work_sync_and_product_limits.md` |
| 16 Dormant, future, superseded, and commonly misnamed mechanisms | 25 + 1 | `16_Dormant_future_superseded_and_commonly_misnamed_mechanisms.md` |

`EDGE_TO_EDGE_FULL.md` beside this file is all seventeen concatenated, for one paste.

`VERIFICATION-2026-09-05.md` beside it is the re-check against HEAD `d28f1b1` three days later: what still holds, two anchors that moved, and one count corrected (registered tools are six).

## Sources

- `Docs/Engineering/FULL_SYSTEM_TRACE.md`, the execution trace with file:line for every number here.
- `Docs/Research/AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md`, the 612-term word bank; all 153 source paths it cites exist.
- `Docs/Research/HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt`, the reasons.
- `Docs/STUDY_GUIDE.md`, the course with checklists and quizzes; `Docs/Audio/`, the five-pass spoken version.
