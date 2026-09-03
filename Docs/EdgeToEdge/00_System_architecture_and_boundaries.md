# Module 00. System architecture and boundaries

Fourteen concepts. This module is the walls, the rooms, and the house rules. Nothing here does work by itself; everything here is a rule that every other module obeys.

## The ladder

**Like you're five.** You have a box of your own papers. The box lives inside your phone and only you have the key. You can ask the box a question and it finds the page that answers it and points at the exact line. If the answer isn't in the box, it says "not in here" instead of making something up. Nothing ever leaves the box unless it asks you first and shows you what it wants to take out.

**Like an idiot.** It's a private search engine plus a writer, for your own files, that runs on the phone instead of on someone's server. The search part finds the right pages. The writer part turns them into an answer. The search part can't lie because it's just math. The writer part can lie, so there's a bouncer that checks every sentence against the pages before you see it. That's the whole app: find, write, check, and never phone home without asking.

**Like less of an idiot.** The category name is retrieval-augmented generation. Retrieve first, generate second. Retrieval is deterministic: same question, same evidence, every time, no imagination involved. Generation is a language model and can invent. So the design puts the model in a very small room: it only ever sees the evidence the retrieval found, it has to cite that evidence for every claim, and nine rule-based checks run on its output. Each of your libraries is a sealed container so one library's documents can never answer another's question. And the only thing that can ever leave the phone is the final write-up, to Apple's Private Cloud Compute, after you've seen the payload and said yes.

**Average Joe.** Three modes turn the same machine up or down: Standard is one pass, Deep Think and Maximum loop. The whole pipeline is built as a library target so it can be tested without the app's screens, billing, or platform glue. The reason the deterministic-versus-generative split matters so much is that it tells you where bullshit can enter: exactly two places, when the app rewrites your question and when it writes the answer. Everything else is a calculator.

**Dot-connector.** Here's the pattern to carry into every later module. Every mechanism in this app is one of two things: it keeps the promise (your data stays yours) or it defends against the danger (the model invents). Container isolation, local-first, on-device everything, consent-gated cloud: promise. Two indexes, reranker, floors, budget, gates, citations, honest route badge: danger. If you can't say which of the two a piece serves, you don't understand that piece yet. Also notice what the quality modes actually are: not a temperature knob but a coherent bundle of numbers (candidate breadth, similarity floors, iteration caps, confidence bars) resolved once at query start so no screen can quietly use contradictory values.

**Expert.** The engine is `RAGService` internally and `OIEngine` at the SDK boundary, built as the `OpenIntelligenceEngine` SwiftPM target with App, Features, UI, Billing and a handful of platform files excluded. Every store filters by container UUID before a candidate can enter ranking or generation: FTS rows, vector stores, entity lookups, documents, threads, queries. The runtime coordinator resolves quality mode, PCC eligibility, adaptive config, query profile and the agentic decision before any search runs. Standard uses initial top-K 30, similarity floor 0.28, MMR λ 0.60, confidence bar 0.50; Deep Think 35 / 0.25 / 0.55 / 0.60; Maximum 50 / 0.20 / 0.50 / 0.80. Generation temperature 0.4 / 0.4 / 0.3. Only the final synthesis can leave the device, through a post-retrieval execution plan with an on-device fallback attached to every cloud plan.

**Expert's expert.** Three things people get wrong at this layer. First, "local-first" is a constraint applied before every pipeline choice, not a stage; it is why exact vector scan over an mmap replaced any hosted vector database and why the context budget is a hard number instead of a hope. Second, the mode confidence bar for Maximum was 0.98 until it turned out to be unreachable and every Maximum answer failed verification; it is 0.80 now, and the 0.98 you will see elsewhere is the agentic loop's stopping target, a different number for a different job. Third, the status vocabulary the word bank uses (Core, Conditional, Support, Dormant, Future, Historical) is an audit layer, not a runtime type; there is no enum in the app that says "Dormant". Treat it as a reading aid that was checked against source on 2026-09-01, with the corrections listed per module in this document.

## Every concept

### Container isolation (Core, verified)
- **Idiot:** each library is its own locked room. A question in room A cannot see papers in room B.
- **Dot-connector:** every table and every vector store carries the container's UUID, and every read filters on it before ranking sees a candidate. That is also what makes deleting or rebuilding one library safe: the filter is the blast radius.
- **Expert:** enforced in `SQLiteFullTextService` (container column on shared tables), `VectorStoreRouter` (one store instance per container file) and `EntityIndexService`. It is a shared-schema-with-scoping design, not one SQLite file per library; the tradeoff is simpler migrations against a filter that must never be forgotten in a new query.

### Deep Think mode (Conditional, verified)
- **Idiot:** the "try harder" setting. It searches more than once and thinks in between.
- **Dot-connector:** it flips on query rewriting, expansion, HyDE, iterative retrieval and the agentic orchestrator, and it raises the verification bar. You pay in time and heat for a better shot at multi-part questions.
- **Expert:** resolved by `QueryRuntimeCoordinator` into an agentic decision of `.agentic`; the orchestrator's `default` profile is 5 steps, 0.85 confidence target, escalation below 0.35. Retrieval floor 0.25, MMR λ 0.55, mode confidence 0.60, reasoning chain 4 sessions, PCC reasoning level moderate if the cloud is chosen.

### Deterministic stage (Core, verified)
- **Idiot:** a calculator step. Same input, same answer, can't make things up.
- **Dot-connector:** extraction, chunking, search, fusion, rerank, packing, route authorization, the gates, citation mapping. These are where the app's honesty lives, because they cannot hallucinate.
- **Expert:** `ModelExecutionPlan` types its three stages as retrieve (deterministic), synthesise (the chosen target), verify (deterministic). Keeping retrieval and verification deterministic is the design decision that lets the gates be trusted more than the writer.

### Engine status vocabulary (Support, not a runtime symbol)
- **Idiot:** the labels Core, Conditional, Support, Dormant, Future, Historical. They tell you whether a thing actually runs.
- **Dot-connector:** a repo this size has scaffolds, reserved enums and dead branches that look alive. The labels stop you from learning a blueprint as if it were a gear.
- **Expert:** an audit overlay, not code. Anchored loosely to `Docs/SHIPPED_CAPABILITIES.json` and the changelog. Verified this week: one label is wrong (the Neural Engine is "requested", not "Core"), one item is missing from Dormant (the `SpeechAnalyzer` branch), and Core AI should read Conditional-becoming-default on the 27 systems.

### Generative stage (Core, verified)
- **Idiot:** the step where the AI writes words. The only step that can bullshit you.
- **Dot-connector:** there are two: rewriting your question and writing the answer. Both happen after evidence is chosen and before the gates. Everything around them is armor.
- **Expert:** `LLMService` and `FoundationModelStructuredGenerator`. Structured generation with `@Generable` makes the output typed claims with evidence IDs, which is what makes Gate B (every claim cites) mechanically checkable instead of a vibe.

### Ingestion pipeline (Core, verified)
- **Idiot:** what happens when you drop a file in. Read it, cut it up, file it, done, once.
- **Dot-connector:** every later answer is bounded by what ingestion preserved. A fact that got truncated, scrambled or filed under the wrong identity here is unrecoverable by any amount of clever retrieval. That is why ingestion has more checks than retrieval does.
- **Expert:** `DocumentProcessor` under `RAGService.runIngestionLoop`, serial per document, stages queued through complete, with the document-level full text written to FTS before chunking and the chunk rows written after embedding. Detailed in module 01 and `Docs/INGESTION_PIPELINE.md`.

### Knowledge container / library (Core, verified)
- **Idiot:** a library. A named bucket of documents with its own settings.
- **Dot-connector:** it is the isolation boundary and also the unit of embedding configuration, which matters because two libraries can legitimately use different embedding providers and their vectors must never be compared.
- **Expert:** `KnowledgeContainer` (model) and `ContainerService`. Its UUID scopes every downstream read and write, its fingerprint pins the vector space, and its sync mode decides whether iCloud reconciliation touches it.

### Local-first (Core, verified)
- **Idiot:** it all happens on your phone. Not on a server.
- **Dot-connector:** the phrase is a list, not a slogan: documents, full text, embeddings, indexes, retrieval, packing and verification all run on the device. The one exception is the final answer, which may go to Private Cloud Compute after consent. That exception is the entire cloud story.
- **Expert:** the constraint that forced the architecture: memory-mapped exact vector scan instead of a hosted ANN service, a 4,096-token on-device window as the packing budget, and a planner that only reaches for the cloud when the local budget does not fit or the complexity asks for it. `Docs/PRIVACY_AND_ROUTING.md` is the canonical statement.

### Maximum mode (Conditional, verified)
- **Idiot:** the "spend everything" setting. Widest search, most thinking, strictest checking.
- **Dot-connector:** it enters the agentic loop immediately and keeps going until it is confident, stalls, times out or hits the cap. Missing evidence costs more than waiting, so it prefers gathering.
- **Expert:** initial top-K 50, floor 0.20, MMR λ 0.50, mode confidence 0.80. The unlimited reasoning path targets 0.98, caps at 50 sessions scaled to three chunks per session, disables tools inside sessions to stop overflow, and stops on target, saturation, cancellation or cap. Correction to the bank: the "highest verification threshold" is 0.80, not 0.98; 0.98 is the loop target.

### OpenIntelligence engine (Core, verified)
- **Idiot:** the machine. Files in, cited answers out.
- **Dot-connector:** one owner for the whole contract, so ingestion, storage, retrieval, generation and verification cannot each be locally right and jointly wrong about IDs, dimensions, budgets or citation numbering.
- **Expert:** `RAGService` (19,000 lines, the mega-orchestrator) internally, `OIEngine` in `SDK/OpenIntelligenceEngine.swift` at the boundary. The SwiftPM target `OpenIntelligenceEngine` builds this without the app shell.

### Quality mode (Core, verified)
- **Idiot:** Standard, Deep Think, Maximum. A dial.
- **Dot-connector:** not a temperature knob. One dial changes candidate breadth, floors, expansion, iteration, session count, confidence requirement and memory depth together, so the pipeline stays coherent.
- **Expert:** `RAGQualityMode` holds the bundle; `QueryRuntimeCoordinator.resolveContext` resolves it once at query start. The numbers are in the ladder above and verified in the trace.

### Query pipeline (Core, verified)
- **Idiot:** what happens when you ask a question. Understand, find, pick, write, check.
- **Dot-connector:** its job is to turn a whole library into a small evidence packet that fits the model and can be audited afterwards. Every stage cuts candidates; the diagnostics record what each cut dropped.
- **Expert:** `RAGService.queryInternal` after the coordinator: vocabulary, understanding, embedding (cache-aware), hybrid search, fusion, rerank, floor, MMR, expansion, compression, packing, plan, route, session, stream, gates, response. Module 07 to 13 walk it stage by stage.

### Retrieval-augmented generation (Core, verified)
- **Idiot:** look it up, then write it up.
- **Dot-connector:** the model cannot hold your library and does not know your documents; retrieval supplies the facts and the citations, generation supplies the readable sentence. Keeping the two apart is what makes "cite every claim" possible.
- **Expert:** begins after ingestion produced the two indexes; spans query understanding through verification. The app's specific flavour is post-retrieval routing: where to generate is decided after the evidence exists, from its real size and sensitivity.

### Standard mode (Core, verified)
- **Idiot:** the normal setting. One pass, fast.
- **Dot-connector:** it still does the non-negotiables: hybrid retrieval, rerank, MMR, citations, generation, gates. What it skips is the loop.
- **Expert:** top-K 30, floor 0.28, λ 0.60, confidence 0.50, temperature 0.4, single `LanguageModelSession`. A Standard query can still become agentic through planner escalation, which is the third of the three agentic paths.
