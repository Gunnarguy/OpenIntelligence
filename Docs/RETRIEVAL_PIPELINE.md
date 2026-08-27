# Retrieval Pipeline — source-verified at v4.6, shipped tree is v5.0

> **Documentation status:** Source-verified on 2026-07-15 against v4.6. **Not re-verified since.** iOS/macOS 4.9 is the shipped version, and 4.8–4.9 changed retrieval behavior in ways this document does not yet describe. PCC device/distribution validation remains pending.
> **Known drift as of 2026-08-05** — each of these is in `CHANGELOG.md` under 4.9 but not yet reflected below:
> - Gate E measures query coverage as the better of combined-evidence and best-single-chunk, not the per-chunk maximum.
> - `DomainIsolationService` relaxes only the cross-domain-mixing clause when the retrieved chunks all come from one `documentId`.
> - `executeReasoningChain` retries the user's original wording when a rewrite fuses zero chunks, before any downstream relevance gate judges the library.
> - `makePostRetrievalModelPlan` takes the maximum similarity over the chunk set rather than reading `chunks.first`, which is not the best chunk after MMR, expansion, and Lost-in-the-Middle reordering.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`, plus `CHANGELOG.md` 4.8–4.9 for anything retrieval-related.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

---

## 1. Overview
The retrieval pipeline is the core engineering idea in OpenIntelligence: answers are grounded in user-provided material and expose the exact evidence that influenced them. The app is built to bias responses toward groundedness, showing uncertainty when evidence is weak rather than inventing confident prose.

---

## 2. RAG Retrieval Flow

```mermaid
flowchart TD
    UserQuery[User Query Input] --> QueryPlan[Query Analysis: NER & Expansion]
    QueryPlan --> EmbeddingGen[Generate Query Vector - Core ML]
    GPUProfile[GPU Execution Profile] --> EmbeddingGen
    EmbeddingGen --> HybridSearch[Hybrid Search: FTS5 Lexical + Vector Similarity]
    GPUProfile --> HybridSearch
    HybridSearch --> RRF[Reciprocal Rank Fusion - RRF]
    RRF --> Cutoff{Adaptive Ceiling Cutoff}
    Cutoff --> Rerank[Core ML TinyBERT Reranker / Heuristic Fallback]
    Rerank --> MMR[MMR Diversity Selection]
    GPUProfile --> MMR
    MMR --> ContextExpand[Context Sibling Expansion - ParentDocumentService]
    ContextExpand --> LostInMiddle[Reorder Context - Lost-In-Middle]
    LostInMiddle --> Evidence[Post-Retrieval Evidence + Exact Token Budgets]
    HybridSearch -.-> Trace[[RetrievalTraceCollector - eval runs only, nil in production]]
    RRF -.-> Trace
    Cutoff -.-> Trace
    Rerank -.-> Trace
    Evidence -.-> Trace
    Trace -.-> StageScore[[Per-stage recall@k / MRR / nDCG - RetrievalStageEvaluator]]
    Policy[Persistent Picker Policy: Hybrid / On-Device / PCC] --> ModelRoute
    Evidence --> ModelRoute{ModelExecutionPlanner v2}
    Capability[Signed Entitlement + Availability + Quota + Consent State] --> ModelRoute
    ModelRoute -- Insufficient Evidence --> AbstainRefusal
    ModelRoute -- Local --> LocalLLM[SystemLanguageModel.default]
    ModelRoute -- PCC Candidate --> Minimize[Minimized Cloud Evidence Envelope]
    Minimize --> Consent{Consent Valid?}
    Remembered[Canonical Remembered Consent - No Launch Prompt] --> Consent
    Consent -- Yes --> PCCLLM[PrivateCloudComputeLanguageModel]
    Consent -- No / UI Unavailable --> LocalLLM
    LocalLLM --> Verification[Verification Gates A-I - Negation & Word-Overlap]
    PCCLLM --> Verification
    Verification --> Decision{Critical Gates Pass?}
    Decision -- Yes --> GroundedAnswer[Render Grounded Answer with Citations]
    Decision -- No --> AbstainRefusal[Abstention Refusal Message]
    GroundedAnswer --> RouteBadge[Receipt-backed Route Badge]
```

---

## 3. Pipeline Stages

1. **Import**: Files enter through Apple platform document workflows.
2. **Extraction**: Text, layout, and metadata are extracted.
3. **Chunking**: Chunks are generated with metadata using semantic and structure-aware rules.
4. **Indexing**: Chunks are written into local search (SQLite FTS5) and vector databases ([BNNSVectorDatabase.swift](../OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift)).
5. **Query Analysis & Planning**: Incoming questions are classified, scoped, and prepared for retrieval.
6. **Retrieval**: Candidate chunks are selected from the active library or workspace container.
7. **Reranking and Packing**: Evidence is scored using a local Core ML TinyBERT cross-encoder (with proximity-based heuristic fallback if the model is absent), deduplicated (MMR), expanded with sibling context, and compressed.
8. **Post-Retrieval Model Routing & Generation**: `ModelExecutionPlanner` combines evidence sufficiency and synthesis burden with the captured persistent policy, foreground state, network, signed entitlement, live quota/availability, and SDK token/context budgets. Hybrid chooses per query, On-Device is local-only, and explicit PCC requests cloud but records a truthful local completion when any cloud gate prevents use. Local execution uses `SystemLanguageModel.default`; eligible iOS/macOS 27 synthesis may use native PCC after the exact minimized envelope is consented. iOS/macOS 26 remains local-only. `[evidence_level: code_verified, confidence: high_pending_physical_device_validation, evidence_source: ChatScreen.swift, ModelExecutionPlanner.swift, LLMService.swift, RAGService.swift]`
9. **Fidelity Verification & Receipt**: Responses pass through local verification checks. Route metadata is persisted as a `ModelExecutionReceipt` that separates intended, attempted, actual, fallback, and completed targets. `[evidence_level: code_verified, confidence: high, evidence_source: VerificationGateService.swift, ModelExecutionReceipt.swift, RAGQuery.swift]`
10. **Presentation**: Answers are shown with liquid glass UI indicators, citations, quality gauges, and review affordances.
11. **Continuous Evaluation**: `RAGEvalRunner` runs the cases in `Benchmarks/rag_eval_v1.jsonl` through the live pipeline and scores answer match, retrieval recall, citation precision and abstention.

    **Corrected 2026-08-08.** This item previously read "verified against quality targets (e.g. Recall@5 $\ge 0.85$, Citation Precision $\ge 0.90$) using the native Evaluations harness". Two parts of that were untrue and are withdrawn rather than deleted, so the record shows what was claimed. The `\ge 0.85` recall gate was never met and could not be: `retrievalRecallAt5` returned exactly `0.0` on every run regardless of retrieval quality, because the runner only scored recall when a case supplied `groundTruthChunkIds` and every committed case carries `null` there. And there is no native Evaluations harness: `AppleEvaluationsBridge.swift` is named for Apple's Evaluations framework but imports only `Foundation` and `FoundationModels`. `[evidence_level: code_verified, confidence: exact, evidence_source: AppleEvaluationsBridge.swift imports, Benchmarks/rag_eval_v1.jsonl all 20 records, CHANGELOG.md 4.9]`

12. **Per-stage retrieval measurement** *(added 2026-08-08)*: A `RetrievalTraceCollector` may be attached to a query. It records the rank-ordered output of each retrieval stage, and `RetrievalStageEvaluator` scores recall@1/3/5/10, MRR, nDCG@5/10 and precision@5 **per stage** rather than once at the end.

    Seven stages, in pipeline order: `vector`, `lexical`, `fusion`, `boosted`, `candidates`, `rerank`, `final`. The first five are recorded by `HybridSearchService` in both its search paths; `rerank` is recorded by `RAGService` after `RAGEngine.rerank`, because that is where reranking runs; `final` is recorded at the `queryWithAudit` boundary from the chunks on the response.

    The split matters for attribution. Reranking cannot recover a chunk the first stage never returned, so a single end-of-pipeline number cannot tell a first-stage regression from a reranker regression, and a later stage can mask an earlier one. A recall drop between `boosted` and `candidates` means top-K truncation is too tight; a drop between `candidates` and `rerank` means the cross-encoder demoted the right chunk.

    **That last inference holds only when ground truth credits every document the question requires, and on 2026-08-11 it did not.** `scripts/build_eval_dataset.py` emitted a single-element `expectedCitations` from the manifest's singular `expected_source`, and `scripts/run_quality_matrix.py` passed that one filename to the harness. All five `multi_hop_project_m*` cases ask a two-part question whose halves live in different fixtures, so ranking the *other* required document first scored as a demotion. That produced `rerank` MRR@10 0.972 and `final` 0.917 against a `vector` stage at 1.000, and the arithmetic closed exactly at `(17 + 0.5)/18` and `(15 + 1.5)/18` while all five cases answered correctly. The reranker was not demoting anything. Both scripts now read a plural `expected_sources`, falling back to the singular key, and the manifest carries both filenames for those five cases. **Before attributing a late-stage drop to the reranker, check that every case in play credits all of its required documents.** `[evidence_level: measured+code_verified, confidence: exact, evidence_source: BenchmarkRuns/20260811-133233-matrix/results.json, build_eval_dataset.py, run_quality_matrix.py, tiny_research_suite/manifest.json]`

    The collector is one instance per query, passed explicitly as a defaulted parameter. It is `nil` in production, where the only cost is a nil check per stage. It is deliberately not a shared sink: retrieval runs concurrent child tasks, and a process-wide collector would interleave stages from overlapping queries with no way to separate them. `[evidence_level: code_verified, confidence: exact, evidence_source: RetrievalTraceCollector.swift, HybridSearchService.swift, RAGService.swift, RetrievalStageMetrics.swift]`

13. **Sentence selection, which runs after the last measured stage** *(added 2026-08-13)*: `RAGService.extractRelevantSentences` turns the retrieved chunks into the text the model actually sees. It runs **downstream of `final`**, so none of the seven stage metrics above observe it. A query whose every stage figure is excellent can still reach the model with nothing usable in its context, and on 2026-08-13 one did.

    **What a device log showed.** For "How often must reprocessing occur?" retrieval completed in 88.5ms with 177 candidates, 57 of them found by FTS5 and missed by vector search, and the reranker normalised the top chunk from 0.10 to 0.90 with the correct section in first place. Sentence selection then handed the reasoning chain **67 characters against a 3000+ character budget**: a section label and a filename. Deep Think ran eight sessions over that, its insights degenerated to "[S1] contains a section titled", and the final generation failed to parse. The user's query failed while every retrieval metric was healthy.

    **Two independent causes, both fixed.** Selection kept a sentence only if it contained a query keyword as a raw substring, with no stemming, while FTS5 indexes with `porter unicode61`. Retrieval therefore matched "reprocessed" to a query saying "reprocessing" and selection then discarded those same sentences, leaving only lines carrying the literal token. Separately, a line qualified as a heading only if it contained no digits at all, which rejects every heading in a numbered technical manual ("4 Reprocessing", "4.5.1 Overview"), so no sentence could inherit its section's keywords. Keyword matching is now additive across raw substring and a shared suffix-stripped stem, the digit test applies only after a leading section number is removed, and the section is seeded from `chunk.metadata.sectionTitle` rather than re-derived from raw text. `[evidence_level: measured+code_verified, confidence: exact, evidence_source: iPhone console capture 2026-08-13, app 4.9 build 150, not retained in the repository (root .txt is gitignored: these captures run to several MB and carry container UUIDs and document names); the figures it produced are quoted inline above and in the 2026-08-13 CHANGELOG entry; RAGService.swift extractRelevantSentencesOffMain; DocumentChunk.swift ChunkMetadata.sectionTitle]`

    **Confirmed on device the same day.** A second capture after the fix, on a different question ("What safety protocols are mandatory?"), recorded session contexts of **855, 1468, 850, 242, 252, 252, 242, 899 characters** against the pre-fix 106, 123, 67, 53, 167, 111, 67, 67. The four sessions landing near 242 are the new too-small fallback firing. Insights carried real cited findings rather than "contains a section titled", and no session echoed its system prompt. **The query still failed**, which disproved the assumption that context starvation was contributing to the final parse error: that failure is independent, and is a rate limit. See the 2026-08-13 CHANGELOG entry on escalating backoff. `[evidence_level: measured, confidence: exact, evidence_source: second iPhone console capture 2026-08-13, same caveat on retention]`

    **The general lesson, and it is the same one item 12 records one level up.** Stage metrics measure retrieval, not what the model receives. `AgenticOrchestrator` had a fallback to raw chunk content, but it tested `isEmpty`, and 67 characters of section title is not empty. Guard the layers between retrieval and generation on *usefulness*, not on presence.

---

## 4. Library Isolation
Library and workspace boundaries are critical because retrieval quality depends on scope. The app is designed so that a query is answered strictly against the user-selected document container rather than all files indiscriminately, preventing cross-container leakage.

---

## 5. Diagnostics & Telemetry
Diagnostic and telemetry surfaces are included for inspecting chunks, retrieval quality, answer details, and pipeline behavior. These are engineering tools for iteration and must not be interpreted as validation for regulated or safety-critical workflows.

14. **Citation labels are one namespace, and the response must be able to resolve them** *(added 2026-08-14)*: `RAGEngine.assembleContext` packs chunks until the character budget runs out and labels them `[S1]`...`[S{used}]`. Whatever did not fit is handed to **Needle Rescue**, which runs `extractRelevantSentences` over the dropped chunks and appends the result to the *same* prompt. Rescue previously labelled its sources from `[S1]` again, so one prompt presented two different chunks under the same label. A device trace on 2026-08-14 shows the consequence: four packed sources, then rescue sources numbered from one, and an answer citing `[S5]` and `[S6]`, being the fifth and sixth sources the model had been shown. Those resolved to nothing, because `includedRetrievedChunks` was `orderedCandidates.prefix(actualChunksUsed)` and carried only the packed four.

    Two rules now hold together, and neither works alone. Rescue continues the packed block's numbering through a `labelOffset`, and the chunks rescue contributed are attached to the response. `SentenceExtractionResult.usedSourceIndices` exists to make the second possible; returning only a count is what let the prompt and the response disagree about what a citation meant.

    **The general rule:** anything that puts text in front of the model under a citation label must also put the corresponding chunk in the response. Three separate layers already drop out-of-range citations (`StructuredAnswer.citedEvidence`, the empty-evidence confidence floor, `normalizeStructuredCitations`) and Gate B fails on them. None of that helps, because the answer prose is not validated and it is the only part a reader sees.

15. **The prompt's source array and the response's source array must be the same array** *(added 2026-08-14)*: `RAGEngine.assembleContext` reorders chunks for Lost-in-the-Middle mitigation **before** numbering them, so `[S1]`...`[Sn]` are labels over `front + back.reversed()`, not over the input. Every caller independently rebuilt the citation list as `prefix(used)` of the array it had passed *in*, which is a different set for any query with four or more chunks. `[A,B,C,D]` is presented as `[A,C,D,B]`, so a citation of `[S2]` meant C and resolved to B.

    This was undetectable by every guard in place. Indices were in range, chunks existed, and the citation resolved to a real source. It was simply the wrong one. Five call sites had the same defect, which is the signature of a label related to its chunk by convention rather than by construction.

    `assembleContext` now returns `sources`: the chunks in the exact order their labels were assigned. Callers must use it and must not recompute a prefix. **If you add a stage that puts text in the prompt under a citation label, it must return the chunks it labelled.** Item 14 records the related case where needle rescue appended labelled text whose chunks reached no one.

16. **The right fusion weight is corpus-dependent, and the app can already tell which kind it is facing** *(added 2026-08-14)*: the offline sweep (`Docs/EVALS.md`) found MRR@10 maximised at dense weight 0.00, monotonically. That was measured on `qasper_external_v1`, whose questions were written by readers shown only a title and abstract and therefore reuse the paper's exact vocabulary, which favours the lexical arm. It is a property of the fixture, not of retrieval.

    Device captures on 2026-08-14 show the arms inverting between real libraries. A manuals corpus returned 120 vector + 60 FTS5 with 57 lexical-only hits. A research corpus asked "What is the role of serotonin signaling?" returned **140 vector + 6 FTS5**, and the log explains why: it reports that the keyword `serotonin` hit 51% of chunks and therefore received zero boost. On a corpus where the domain term is on every page, lexical search discriminates nothing and the dense arm is carrying the entire query. Zeroing the dense weight there would sink 140 candidates beneath six.

    **Do not set a single global weight from a single fixture.** `HybridSearchService` already computes per-keyword hit rates and builds `discriminativeKeywords` before fusion runs, so the signal needed to choose a weight per query already exists at the moment the weight is applied. The completion log now reports `unique: N vector-only, M lexical-only` with the weights actually used, which is the evidence any future weight change should be argued from.

17. **Retrieval has a second consumer, and it needs the passage judged rather than the output judged** *(added 2026-08-15)*: `SuggestedQuestionsService` runs the same retrieval and turns the chunks into the questions offered before the user types anything. `buildGroundedPassages` took `chunks.prefix(limit)` with no quality test, so whatever retrieval returned became question material.

    The service already carried five filters, and every one of them inspects the **generated question**: `isJunkString`, `sanitizeGeneratedQuestion`, `isUsableLLMGeneratedQuestion`, `isUsableGeneratedQuestion`, `isStructuralOrMetaQuestion`. A reference list defeats all five at once. It is grammatical, it is dense with capitalised domain nouns, and the question it produces is well formed, so no test applied to the question can separate "What is the role of Neurosci Yagishita Transient?" from a real one. The defect is only visible in the source text.

    `questionSourcePenalty` scores the chunk instead, on citation density, dot leaders, access boilerplate, digit-to-letter ratio, vowel-free token ratio, and absence of sentence enders. It **demotes rather than filters**, because a hard filter returns an empty set for a document that is entirely a reference list or a scanned table, which disables the feature precisely where it is already weakest.

    **Hand-built samples were not enough to get this right, and the corpus run is what corrected it.** The first version passed all nine hand-built cases and still hard-demoted 51 chunks of ordinary body prose out of a 5,425-chunk sample of the real library. Two signals were wrong in a way no synthetic sample exposed. A parenthetical year counted three or more times is the marker of an author-year citation *in running text*, so it fires hardest on the related-work paragraph, which is good question material; a numbered reference list writes `2017;6:e20975` instead, so the signal was evidence **against** a bibliography. And matching author initials as `[A-Z][a-z]{2,}\s+[A-Z]{1,3}[,.]` without requiring the entries to be consecutive matched "Detection DET." and "Twitter PHEME," in any paper whose body is full of acronyms.

    Author detection now requires three consecutive `Surname AB,` entries **with distinct surnames**. The surname test is the part that generalises beyond papers: "Phase A, Phase A, Phase B," is shape-identical to "Correia PA, Lottem E, Banerjee D," and a repeat count cannot separate them, while "Section A, Section B, Section C" and "Option A, Option B, Option C" are ordinary content in manuals, forms and agreements. `[evidence_level: measured, confidence: high, evidence_source: the shipped function extracted verbatim and run over a stratified 5,425-chunk sample of LocalCache/FTS5/fulltext.sqlite; 99.2% score 0 and zero are falsely hard-demoted, while bibliography, numbered references, table of contents, running header and numeric table all still demote hard]`

    The general rule this is an instance of: **item 12's stage metrics stop at `final`, and both known defects since have been downstream of it.** Item 13 was sentence selection, this is question generation. A stage figure cannot tell you that a consumer of the stage output is unusable.

18. **A fixed-size cut over a Lost-in-the-Middle ordering removes the best chunk by construction** *(added 2026-08-17)*: `executeFullRetrievalPipeline` finishes with a Lost-in-the-Middle reorder, and Deep Think's synthesis then truncated what it received. Both stages were defensible alone. Composed, they discarded the single highest-scoring chunk on every query large enough to matter.

    The reorder sorts by score and interleaves: even ranks are appended, odd ranks are inserted at the midpoint. For 85 chunks that yields `[c1, c3, c5, ...]` with **rank 0 at index 42**, so the best chunk sits in the exact middle of the array. `executeSearchStepWithChunks` then rendered `chunks.prefix(10)`, which for 85 chunks is ranks 1, 3, 5 ... 19 and excludes rank 0 outright, and `executeDirectSynthesis` applied `String(searchResults.prefix(3000))` to what was left. The comment above that cut justified 3000 characters against a system prompt it no longer matched.

    Nothing about this was visible. The cut logged nothing, the citations that survived resolved correctly, and Self-RAG scored the result `relevance=70%, citations=1/1, confidence=88%`. The observable symptom was an inversion: on "How does dopamine affect social behavior?" Deep Think answered that the documents provide no evidence, in 202.7s, while Standard assembled 3 chunks and 522 words, fit inside its budget, and answered correctly in 6.7s. `[evidence_level: measured, confidence: exact, evidence_source: device capture Standard+DeepThink+Xcodeconsole.txt 2026-08-16, gitignored per the item 13 retention caveat; figures quoted inline]`

    **Three changes, and the ordering one is the load-bearing one.** Synthesis now packs from the chunks rather than the pre-rendered string, sorted by score with array position as a deterministic tiebreak, so truncation removes the least relevant evidence instead of the most relevant. The budget is derived from `FoundationModelTokenBudget` against the actual system prompt, query and output reserve rather than a hardcoded character count. And every assembly emits one line naming chunks kept, tokens used and chunks dropped, so a future instance of this is readable in a trace instead of inferable from a wrong answer.

    Parent document expansion is now gated on the same budget. It grew an 18-chunk result to 85 immediately before a cut that could hold roughly eight, so it was not neutral: it added nothing that fit and displaced the ranked set that did. Primary matches are never gated, only siblings, because dropping retrieval's own results here would trade one silent loss for another.

    **Rank-ordered packing does not license recomputing the citation list.** Item 15's invariant still binds: the budgeted subset is passed to `generateWithProperConsent` as `sourceChunks` in the order it was labelled, because `[S1]` resolves positionally. Reordering for relevance without carrying the order forward would have swapped one defect for a misattribution. `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.assembleBudgetedEvidence and executeDirectSynthesis; RAGService.swift step 7.5; reorder reproduced directly for n=85]`

    **Not device-verified.** The change is build-verified and passes the 236-test suite, and this path has no test coverage, so the claim that Deep Think stops abstaining on the dopamine query remains unverified until the identical query is re-run on hardware and compared against the saved trace. `[evidence_level: code_verified, confidence: high_pending_device_validation]`

19. **The agentic path was never measured, which is why its recall gap could not be attributed** *(added 2026-08-19)*: item 12 records seven per-stage metrics — `vector`, `lexical`, `fusion`, `boosted`, `candidates`, `rerank`, `final`. Those come from `HybridSearchService` and from `queryWithAudit`. **Deep Think and Maximum reach retrieval through `AgenticOrchestrator`, which calls `executeFullRetrievalPipeline`, and that function took no `trace` parameter at all.**

    The consequence showed up the first time the two modes were benchmarked against each other. Standard reported all seven stages; Deep Think reported exactly one, `final`, recorded downstream from the response.

    | stage | standard r@10 | deep-think r@10 |
    | :--- | :---: | :---: |
    | vector | 0.571 | — |
    | lexical | **0.857** | — |
    | fusion | 0.714 | — |
    | rerank | 0.857 | — |
    | **final** | **1.000** | **0.625** |

    Standard's retrieval is perfect on this set: r@5 and r@10 both 1.000 across seven scored cases. Deep Think finds the gold document 62.5% of the time on the same eight. **That gap is the entire quality difference between the modes**, because `correct == (gold_recall == 1.0)` held in 14 of 15 scored runs — synthesis was right whenever it had the evidence and wrong whenever it did not.

    **Two hypotheses were formed and refuted by reading source within the hour.** That query expansion degrades the lexical arm: false, `searchWithFTS5` searches `originalQuery` and uses expansions only as a fallback when the original returns nothing. That expansion replaces the original query: false for the same reason, and the keyword boost also uses `originalQuery`. A third guess was not attempted. The path is now instrumented instead.

    `executeFullRetrievalPipeline` takes a `trace`, and `queryWithAudit` holds the collector for the query's duration so all nine agentic call sites inherit it without a signature change. That property is diagnostic-only and not concurrency-safe: two overlapping traced queries would share a collector. The harness runs one case at a time and production passes nil, so it cannot arise today; a second concurrent traced query would need a task-local instead.

    **Also confirmed by the same table, and already an open row:** fusion ranks *below* the lexical arm it is fusing, 0.714 against 0.857. The keyword arm alone would have retrieved more than the hybrid did.

    `[evidence_level: measured, confidence: exact_for_the_gap, cause_unattributed_pending_instrumented_run, evidence_source: BenchmarkRuns/paired-retry stage_summaries, 8 cases, pool_limit 10, qasper_external_v1]`

