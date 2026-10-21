# OpenIntelligence, edge to edge

> **Documentation status:** Written 2026-09-02 against commit `9c6fcbc`. Every concept name that
> looks like a code identifier was grepped against the Swift tree (115 of 116 found; the one miss is
> noted in module 07). Every number was taken from `Docs/Engineering/FULL_SYSTEM_TRACE.md`, which
> cites its line, or from a grep run while writing the module. Where the 612-term word bank or the
> Opus walkthrough disagrees with source, the module says so and source wins.
> `[evidence_level: code_verified_for_symbols_and_constants, confidence: high; status_labels: artifact_derived, confidence: medium]`
>
> **Corrected 2026-09-29** against the code at `8be003a`. Sentence 12 and the paragraph after the
> twelve sentences said citations carry byte offsets and character ranges, and that the cloud
> payload is shown before consent. Citations carry a chunk, its page and a quote of at most 240
> characters, and the consent sheet shows how much would be sent and why. Sentence 10 now says
> that Always Allow stops the asking. The GPU-profile row in the corrections table is corrected in
> place. The same pass corrected modules 00, 02, 05, 06, 08, 10, 13, 15 and 16; each records what
> changed, with its code lines, in a dated evidence tag.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGStructuredResponse.swift:28-29, 49-50; StructuredAnswer.swift:65-117, 436-440; CloudConsentPromptView.swift:162-184, 199-203; RAGService.swift:2065-2067, 3729-3733]`
>
> **Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress)**, where the
> modules described the agentic loop, tools, routing, packing or checks differently from the code.
> Sentences 9 and 11 below and the corrections table are corrected in place, and modules 00, 03, 06, 07,
> 08, 09, 10, 11, 12, 15 and 16 carry a dated correction after their ladder or on the concept it
> concerns. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, section 19, has the loop with its file
> and line citations. `[evidence_level: code_verified, confidence: high, evidence_source: the file:line
> tags at each correction]`

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
9. Evidence is packed under the token budget: a lookup gets its best passage first (from 5.7, whole up to three fifths of the budget), then the sentences that match the question, and any other question gets the strongest first and last.
10. A post-retrieval plan chooses abstain, deterministic, on-device, or Private Cloud Compute, and only then asks for consent, unless Always Allow has already given it.
11. The model streams an answer with citations, as typed claims when the request fits 3,600 tokens, and nine deterministic gates then label it, abstaining only on a low score or with reliability mode off.
12. What comes back is inspectable: claims, chunk-level citations with page and quote, the completed route, and a trace.

**Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress):** sentence 9 read "strongest first and last", which is the order for every question except a lookup, and sentence 11 read "nine deterministic gates decide what survives". The gates run once, after the answer is written, and label it. Standard abstains only when reliability mode is off (on by default) or their overall score is under the bar, 0.50 or 0.25 for a lookup, and otherwise shows the answer marked Unverified. These sentences are the Standard path. Deep Think and Maximum leave it after sentence 6 for their own front half and loop (module 11), and in the shipped 5.6 their answers get no gates. `[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:14935-14975, :3756-3813 (the lead passage, 5.7), :18766, :16652-16709, :11668, :11578-11594, OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift:495-504, OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift:48-54]`

## The thread through all of it

Every mechanism in this app is one of two things. It keeps the promise, that your documents stay yours: container isolation, local-first, on-device everything, memory-mapped vectors so a phone can hold a library, one outside room used only after retrieval and only with your consent, given on a sheet that shows how much would be sent and why. Or it defends against the danger, that a language model invents: two indexes, a cross-encoder second opinion, a similarity floor, diversity, a recorded budget, exactly two generative stages with nine deterministic gates aimed at them, citations to a chunk, its page and a quote, and a badge that reports what completed rather than what was requested. If you cannot say which of the two a piece serves, you do not understand that piece yet. (Corrected 2026-10-20 against the working tree, `b868fc0` plus the 5.7 work in progress: "exactly two generative stages" is Standard's list, the rewrite of an unclear question and the answer. Every question also gets an on-device planning call, a guided generation that proposes search phrasings and sub-questions and says whether documents are needed, and Deep Think and Maximum make many more model calls. `[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift:202-207, OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift:67-99 and :330-418, OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:11982-11983]`)

## Corrections to the earlier documents, in one place

| Claim as taught | What the source says | Module |
|---|---|---|
| Audio goes through `SpeechAnalyzer` | The branch never compiles. `SFSpeechRecognizer`, on device, 600-second segments. (Corrected 2026-10-20: true through 5.6. From 5.7 `SpeechAnalyzer` with `SpeechTranscriber` runs first and `SFSpeechRecognizer` is the fallback.) | 02, 16 |
| Embeddings run on the Neural Engine | Requested, not placed. Efficiency and Balanced request CPU + Neural Engine; Performance and Maximum request all units; Core ML decides; Core AI exposes nothing. | 05, 15 |
| The GPU profile decides whether vector search uses Metal | It does, with two other conditions: 1,000 vectors and a Metal device. Efficiency and Balanced, the default, keep vector search on the CPU. The profile also gates Core ML units and the MMR matrix. Until 2026-09-29 this row said it does not. | 06, 15 |
| `RecognizeDocumentsRequest` does OCR | It parses structure and tables. `VNRecognizeTextRequest` does OCR. | 02 |
| Page rendering is zero-copy | The PNG round trip is skipped; a full-page bitmap is still allocated. | 02 |
| Maximum's verification bar is 0.98 | 0.80. The 0.98 is the agentic loop's stopping target. (Corrected 2026-10-20: the 0.80 is read only on Standard's abstain path, so no Maximum answer meets it. From 5.7 a Maximum answer is labelled Verified only when all nine gates pass, with Gate A's floor raised to 0.50.) | 00, 11, 12 |
| The advanced on-device model | Executes the default model. No advanced model exists in the SDK. (Corrected 2026-10-20, as `Docs/LIMITATIONS.md` was on 2026-10-05: the app cannot select a model, but the release SDK names the one `default` runs through `SystemLanguageModel.variant`, `.core3` or `.coreAdvanced3`, and the app does not read it.) | 10 |
| Core AI is a fallback | On iOS 27 and macOS 27 it is the default and saved Core ML defaults are migrated. (Corrected 2026-10-20: through 5.6. From 5.7 a new library on iPhone and iPad uses Core ML and only macOS 27 defaults to Core AI, and a saved default naming the other copy is moved to this platform's.) | 05 |
| About six registered tools | Six registered, of twelve defined. This row said ten until 2026-09-29. (Corrected 2026-10-20: and none reaches the model in Deep Think or Maximum, whose every session and synthesis passes `disableTools: true`.) | 10 |
| `NO_RELEVANT_CONTENT` triggers rescue or passthrough | Inside the compressor, yes; the caller in `RAGService` removes the chunk entirely. | 09 |
| Weighted progress has no named constant | It does: `pipelineStageWeights`, extraction 0.52. | 01 |
| TinyBERT reranker name is unverified | It is documented provenance: `cross-encoder/ms-marco-TinyBERT-L2-v2` in the notices file. | 08 |
| Fourteen ingestion stages | Fifteen; the enum also has `paused`. | 01 |
| (Added 2026-10-20) Deep Think searches again every round | Its chain reads windows cut from one retrieval, at most 8 sessions on every device and fewer when the windows run out. Only research rounds after the chain search again, and Maximum's own loop never does. | 11 |
| (Added 2026-10-20) Three ways into the loop | Planner escalation is off while Apple's model writes the answers, so only the mode and Go Deeper start it. | 07, 11 |
| (Added 2026-10-20) HyDE and contextual compression run in Deep Think | Neither runs in any user-selectable mode. | 07, 09 |
| (Added 2026-10-20) MMR λ 0.60, 0.55, 0.50 by mode | Every mode uses the library's λ, 0.6 by default, at least 0.85 for a procedure. In 5.6 MMR got no vectors and removed nothing. | 08 |
| (Added 2026-10-20) Only the final write-up can leave the device | Under the default Hybrid route, the syntheses. With Private Cloud Compute picked in the model picker, the sessions too. | 10, 11 |
| (Added 2026-10-20) The deterministic target skips the model | No plan reaches it today, because no code asks for exact extraction, and one would run on the on-device branch. The answers with no model call come from Deep Think and Maximum's precision shortcut and from Standard's reliability fallback, an extracted value or excerpts alone. | 10 |
| (Added 2026-10-20) The gates decide what survives | They label. Standard abstains only with reliability mode off or a low score. In 5.6 Deep Think and Maximum answers get none. | 12 |
| (Added 2026-10-20) Minimal mode stops the loop, and a step cooldown paces it | Nothing reads the zero agentic steps, `agenticStepCooldownMs` has no caller, and the optimizer's step cooldown delays only Standard's generation. | 15 |
| (Added 2026-10-20) The entity index powers GraphRAG-lite | Nothing fills it. | 03 |

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
