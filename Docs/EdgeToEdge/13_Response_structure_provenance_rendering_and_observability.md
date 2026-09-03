# Module 13. Response structure, provenance, rendering, and observability

Thirty-five concepts. What comes back and how you can inspect it: typed answers, citations to character ranges, the route badge, and the trace that records every stage.

## The ladder

**Like you're five.** The answer comes back with little sticky notes on every sentence that jump to the exact line on the exact card. There's a label saying where the writer sat. And there's a diary of everything the librarian did, in case something looks wrong.

**Like an idiot.** The response is not a string. It's a structured answer: claims with evidence IDs, evidence records with a page and a short quote, a refuse flag, a missing-information list, the answer type. Citations map to character ranges in the source because ingestion recorded offsets. The badge shows which model completed the answer, from the receipt. The diagnostics show how many chunks were found, kept, dropped and packed. A trace log on disk records every stage with timings.

**Like less of an idiot.** Two layers. Internally `RAGResponse` carries answer text, retrieved chunks, confidence, abstention, reasoning trace, metadata and diagnostics; `StructuredAnswer` is the durable claim-oriented contract between generation, verification, storage and rendering. Externally the SDK exposes `OIQueryResult`, `OICitation` and `OIQueryProgressEvent` so other clients get the same provenance without the app's SwiftUI types. Evidence quotes are capped around 240 characters. Everything is persisted into a per-library evidence thread. Observability comes from typed `ThinkingEvent`s for the live UI, `TelemetryCenter` events, os-signposts for Instruments, an audit snapshot per query, a retrieval trace collector for evaluation, and the pipeline trace file.

**Average Joe.** Why so much plumbing around the answer? Because an answer you can't audit is a guess with good typography. Every piece here exists so that a wrong answer can be traced to the stage that produced it: was it extraction, retrieval, packing or generation? The feature flags on the audit snapshot record what actually ran, because configured capability is not executed capability.

**Dot-connector.** The route badge reads from the execution receipt, not the model picker, because a PCC plan can fall back to on-device and the badge must show the fallback. The hardware HUD's Neural Engine pulse is synthetic: there is no public API for Neural Engine occupancy, so the display shows activity around compute-heavy stages, not a measurement. And the pipeline trace log rotates, which is why a long capture needs `tail -F` into an archive before you start.

**Expert.** `StructuredAnswer`: refusal state, answer type (lookup, table lookup, procedure, compare, summarise, investigate, compute, findings, refused), text, atomic claims with verdicts, evidence records (ID, page, quote ≤ ~240 chars, document, section path), missing information, debug data; built from deterministic extraction or structured generation; sanitised before display. `EvidenceThreadStore` persists threads. `GroundedAnswerView`, `SourceChipsView`, `RetrievalSourcesTray`, `UnifiedMetricsBar`, `TimingBreakdownView`, `ContextUsageIndicator`, `ThinkingStreamView`, `ResponseDetailsView`, `EnhancedCodeBlock`, `MarkdownRenderer`. `RAGAuditSnapshot` with feature flags (rewrite, expansion, HyDE, iterative, routing, summaries, parent, corrective, compression, graph packing, cascade, multi-vector, unlimited reasoning), score distribution, candidate counts, context budget, route, recursive metrics, `acceptanceOverride`. `RetrievalTraceCollector` records vector, lexical, fusion, boosted, candidate, rerank and final stages for evaluation. `PipelineSignposts`; `TelemetryCenter`; `HardwareTelemetryState`; `PipelineTraceExporter` and `scripts/pull_trace.sh`; the trace file is `pipeline_trace.log` in the app container's Documents folder. `ResponseTransformService` and `WritingToolsService` for post-answer rewriting without re-entering retrieval.

**Expert's expert.** The audit snapshot once carried a fabricated `top_similarity` of exactly 0.7 on every row of a Deep Think run because it was hardcoded rather than measured; observability that lies is worse than none, and it is why the feature flags and score distributions are checked against the retrieval trace in evaluation. The evidence quote cap is also a privacy choice: 240 characters is enough to inspect and small enough not to leak a document into a stored thread.

## Every concept

### Enhanced code block (Conditional, verified) and Markdown renderer (Core, verified)
- **Idiot:** code looks like code; lists look like lists.
- **Dot-connector:** technical answers lose meaning as one plain string.
- **Expert:** `MarkdownRenderer` block-aware; `EnhancedCodeBlock` with language labels and copy.

### Evidence ID (Core, verified), Evidence record (Core, verified), Evidence quote cap (Core, verified), Inline citation (Core, verified), Source chip (Core, verified)
- **Idiot:** the sticky notes and the tappable sources under the answer.
- **Dot-connector:** a stable ID under the human-readable number; a record with page, quote, document, section; quotes capped near 240 characters; citations sit next to the claim; chips open the actual passage.
- **Expert:** `StructuredAnswer` evidence model; `SourceChipsView`, `RetrievalSourcesTray`.

### Evidence-thread persistence (Core, verified)
- **Idiot:** the conversation is saved.
- **Dot-connector:** a verified answer stays reproducible after the query task ends.
- **Expert:** `EvidenceThreadStore` after finalisation, before idle.

### Execution-route metadata (Core, verified)
- **Idiot:** the badge that says where the writer sat.
- **Dot-connector:** from execution evidence, not the picker.
- **Expert:** initialised at runtime resolution, finalised from `ModelExecutionReceipt`.

### Grounded answer view (Core, verified)
- **Idiot:** the answer screen.
- **Dot-connector:** grounding visible at the point you read the claim.
- **Expert:** `GroundedAnswerView` consuming the verified structured response.

### Hardware telemetry pulse (Support, verified as synthetic)
- **Idiot:** the little lights that blink when the phone is working hard.
- **Dot-connector:** makes invisible local computation legible; not a measurement.
- **Expert:** `HardwareTelemetryState` emitted around compute stages; consumed by the Motherboard HUD; Neural Engine utilisation is not observable.

### OICitation (Core, verified), OIEngine (Core, verified), OIQueryProgressEvent (Support, verified), OIQueryResult (Core, verified)
- **Idiot:** the version of all this that other apps can use.
- **Dot-connector:** a stable boundary above the 19,000-line orchestrator; the same provenance and route truth as the first-party UI.
- **Expert:** `SDK/OpenIntelligenceEngine.swift`.

### Pipeline signpost (Support, verified), Pipeline trace (Support, verified), PipelineTraceExporter (Support, verified)
- **Idiot:** the diary, and the way to share it.
- **Dot-connector:** Instruments measures stage latency from signposts without parsing logs; the trace is the reproducible artefact for device-only failures.
- **Expert:** `PipelineSignposts`; `pipeline_trace.log` in the container Documents; exporter plus `scripts/pull_trace.sh`.

### RAG audit feature flags (Support, verified) and RAGAuditSnapshot (Support, verified)
- **Idiot:** a checklist of what actually ran, and the full conditions of the run.
- **Dot-connector:** configured is not executed.
- **Expert:** assembled as stages complete in `RAGService`.

### RAGResponse (Core, verified), Response metadata (Core, verified), StructuredAnswer (Core, verified), Structured answer type (Core, verified), Refuse flag (Core, verified)
- **Idiot:** the answer object and its labels.
- **Dot-connector:** richer than a string so verification, UI, SDK and evaluation agree on what happened; the refuse flag is machine-readable, not inferred from wording.
- **Expert:** `RAGQuery.swift`, `StructuredAnswer.swift`.

### Response transformation (Conditional, verified) and Writing Tools integration (Conditional, verified)
- **Idiot:** rewrite or summarise the answer afterwards.
- **Dot-connector:** presentation changes that never re-enter retrieval and never replace provenance silently.
- **Expert:** `ResponseTransformService`; `WritingToolsService` as an explicit user action.

### Retrieval diagnostics (Support, verified), RetrievalLogEntry (Support, verified), RetrievalTraceCollector (Support, verified)
- **Idiot:** the numbers behind the search, and the exact lists at each stage.
- **Dot-connector:** counts can't show whether the right chunk survived; stage traces preserve identity and order.
- **Expert:** diagnostics on `RAGStructuredResponse`; the collector records seven stages for evaluation and is discarded after scoring.

### TelemetryCenter (Support, verified), Thinking stream (Support, verified), Timing breakdown (Support, verified), Token-budget metadata (Core, verified), Unified metrics bar (Support, verified)
- **Idiot:** the dashboards.
- **Dot-connector:** typed events decoupled from UI; live progress without raw reasoning; retrieval versus generation time; why evidence was compressed or omitted; one place for the operating evidence.
- **Expert:** `TelemetryCenter`, `ThinkingStreamView`, `TimingBreakdownView`, `ContextUsageIndicator`, `UnifiedMetricsBar` (4,669 lines).
