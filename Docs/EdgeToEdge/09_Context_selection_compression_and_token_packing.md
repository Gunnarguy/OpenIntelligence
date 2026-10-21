# Module 09. Context selection, compression, and token packing

Twenty-seven concepts. Deciding what the model actually reads: a hard token budget, an order that fights the model's blind spot, and optional compression.

## The ladder

**Like you're five.** The writer's desk is small. Only so many cards fit. The librarian puts the best cards first and last, because the writer doesn't look at the middle of the pile very carefully. If a card has a lot of useless words on it, she can cross out the useless bits so more cards fit.

**Like an idiot.** The on-device model can see about 4,000 tokens total. Instructions, your question, the conversation so far, and space for the answer all come out of that. What's left is the evidence budget. The packer fills it with the best chunks, strongest first and last, and records which chunks didn't fit. Optionally, a model call strips each chunk down to only the sentences that matter, which costs time and is used mainly in Deep Think.

**Like less of an idiot.** The budget is an explicit equation: model context minus system prompt minus tool schemas minus question minus conversation minus a safety reserve minus reserved output tokens. Base context is 4,096; the default evidence budget is 3,200; the safety reserve is 256; the app estimates 1.4 characters per token on device. Since iOS 26 the real window is read from the system model at runtime and can be larger. The packer allocates in priority order: core hits, then parents, then neighbours, then graph hops, with intent-specific rules (procedures keep sequence, comparisons keep both sides). Contextual compression uses a fresh Foundation Models session per chunk, rejects any "compression" that came back longer than the original, strips echoed question text, and passes chunks through untouched on any failure.

**Average Joe.** Why is the budget so paranoid? Because the model's limit is hard: overflow is a failure, not a warning. A budget that's right on average is wrong on the day the tokenizer estimate is low. Why put the best evidence at both ends? Because language models measurably underuse the middle of a long prompt, and there's a fixture in the benchmark suite that puts the answer in the middle to prove it. Why sleep one second after compressing? So the Foundation Models rate budget recovers before the real generation call.

**Dot-connector.** Two things that surprise people. First, compression can remove a chunk entirely: if the model answers with the sentinel "NO_RELEVANT_CONTENT," the orchestration layer drops that chunk rather than keeping a stub, because with only a few chunks fitting, a 400-character stub competes with real evidence. The compression service itself has a rescue path, but the caller in `RAGService` chooses removal. Second, "trimmed" is recorded: the IDs of chunks that didn't fit go onto the audit snapshot, and the retrieval diagnostics can show them. That is the difference between a silent drop and a visible one.

**Expert.** `FoundationModelTokenBudget`: base 4,096, default evidence budget 3,200, safety reserve 256, chars-per-token 1.4 on device and 2.5 for the cloud estimate; reads `SystemLanguageModel.default.contextSize` when available. `ContextPackingService` selects core, parent, neighbour and graph-hop allocations under `availableContextTokens`, applies intent-specific packing and the lost-in-the-middle reorder, and records trimmed chunk IDs and skipped sibling counts. `ContextualCompressionService`: target ratio configurable, passthrough on short chunk, unavailable model, failure, timeout or unsafe output; expansion guard rejects ratio > 1.0; query-echo stripping; `NO_RELEVANT_CONTENT` sentinel; `effectiveContent` with information-density rescue inside the service; a fresh session per chunk; a batch time budget. `RAGService` drops chunks the compressor marked irrelevant, then sleeps one second. Mode gating via `usesContextualCompression`, mainly Deep Think. `FoundationModelPromptCompiler` turns the packet into instructions and prompt with S1, S2 source labels.

**Expert's expert.** The word bank says the sentinel "triggers information-dense source rescue or passthrough." Inside the service that is true; at the call site in `RAGService` the chunk is removed, with a comment explaining why. Both are real; the caller wins for what the model sees. The tool-schema overhead is only counted when tools are attached, which is why Maximum's inner sessions disable tools: schema tokens plus tool output tokens were part of what overflowed. And the 4,096 figure is Apple's per-session limit for both on-device and PCC (Technote 3193, cited in `LLMModel.swift`), so the cloud route does not buy a bigger window; it buys a bigger model.

**Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress):** five statements in the ladder above do not hold for the current code. The window is the one the device reports: 4,096 on the owner's iPhone 16 Pro Max and 8,192 on his Mac, and the app assumes 32,768 for Private Cloud Compute (a hard-coded fallback and the figure Apple documents, while the route planner reads the window PCC reports), so the cloud route does buy a bigger window. Standard's evidence budget is not a fixed 3,200. It is computed for each question as the window less 120 tokens, the system prompt, the question and an output reserve of 150 to 300, times 0.88, at 1.4 characters a token, capped at 10,000 characters, which came to 3,190 tokens, about 4,470 characters, on that iPhone on 2026-10-16. When Hybrid can reach Private Cloud Compute, the first pass is sized for 32,768 tokens at 2.5 characters a token instead, capped at 45,000 characters. The 3,200 is `ContextPackingService`'s default, which its one caller overrides, and that caller is graph packing for investigate, compare and findings questions only, so the packer described above is not what packs most answers. "Strongest first and last" is the order for every intent except a lookup, which gets retrieval's best passage first (from 5.7, whole up to three fifths of the budget), then the sentences that match the question from every candidate, and a procedure, which keeps document order. For other intents the reorder runs over all candidates before the budget cut, so with room for about 3, ranks 1, 3 and 5 are packed and rank 2 is neither packed nor rescued (read in the code, not run). And contextual compression runs in no user-selectable mode: its only call is in Standard's pipeline behind a mode flag that is false for Standard and true only for Deep Think, which never reaches that step, so neither the compression call nor the one-second sleep happens. Tools are off in every Deep Think and Maximum session, not only Maximum's. `[evidence_level: code_verified, measured for the 3,190, confidence: high, evidence_source: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift:25-40, OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:14784-14838, :14532-14543, :3746-3747, :14558-14590, :14935-14975, :15035, :14320-14326, :14406, OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift:495-504, :569-600, :773-790, OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift:60, OpenIntelligence/Core/Models/RAGQualityMode.swift:277-284, OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift:5313]`

## Every concept

### 4,096-token on-device limit (Core, verified)
- **Idiot:** the desk holds about four thousand tokens.
- **Dot-connector:** a naive top-20 chunk set plus prompt and schema overflows; everything upstream exists to choose what fits.
- **Expert:** `contextLength` 4,096 per TN3193, on device and PCC alike; real window read at runtime. **Corrected 2026-10-20:** the window the code uses on device is `SystemLanguageModel.default.contextSize` (4,096 on the owner's iPhone, 8,192 on his Mac), and for PCC the app assumes 32,768 (hard-coded, while the route planner reads the window PCC reports), so the two are not alike (`FoundationModelTokenBudget.swift:25-40`, `RAGService.swift:18509-18521`).

### Available context tokens (Core, verified)
- **Idiot:** what's left for evidence after everything else.
- **Dot-connector:** the actual capacity the packer may spend.
- **Expert:** the input constraint to `ContextPackingService`.

### Compression expansion guard (Core, verified)
- **Idiot:** if "compressing" made it longer, the model was making things up; throw it away.
- **Dot-connector:** expansion means paraphrase or hallucination instead of extraction.
- **Expert:** ratio > 1.0 rejected, original passed through; `ContextualCompressionService.swift:141`.

### Compression passthrough (Core, verified)
- **Idiot:** when in doubt, keep the original.
- **Dot-connector:** compression is an optimisation and must never be a single point of evidence loss.
- **Expert:** on short chunk, unavailable model, failure, time expiry, unsafe output.

### Compression ratio (Conditional, verified)
- **Idiot:** how much smaller it got.
- **Dot-connector:** measures whether the call saved context.
- **Expert:** compressed tokens over original; target configurable (0.3 keeps 30%).

### Compression time budget (Core, verified)
- **Idiot:** a stopwatch for the whole compression batch.
- **Dot-connector:** many model calls dominate latency; when time is up, remaining chunks pass through.
- **Expert:** batch-level wall clock in the service.

### Context window (Core, verified)
- **Idiot:** everything the model can see at once.
- **Dot-connector:** instructions, tools, evidence, conversation and output framing all share it.
- **Expert:** enforced immediately before model execution.

### ContextPackingService (Core, verified)
- **Idiot:** the desk arranger.
- **Dot-connector:** chooses and orders core hits, parents, siblings, graph neighbours and compressed content under the ceiling; rank alone can't solve budget, diversity, sequence and support.
- **Expert:** after retrieval and expansion, before prompt compilation. **Corrected 2026-10-20:** its one caller is graph packing for investigate, compare and findings questions, which passes its own budget. Other answers are packed by `RAGEngine.assembleContext` or, for a lookup, by sentence selection (`RAGService.swift:14558-14590`, `:14935-14975`).

### Contextual compression (Conditional, verified)
- **Idiot:** cross out the useless sentences.
- **Dot-connector:** density matters in a 4,096-token window; mainly Deep Think.
- **Expert:** Foundation Models extraction of query-relevant sentences with exact wording preserved; `usesContextualCompression` by mode. **Corrected 2026-10-20:** in the working tree no user-selectable mode reaches it, so read it as Dormant (`RAGService.swift:14320-14326`, `:14406`).

### Core evidence chunk (Core, verified)
- **Idiot:** the must-keep cards.
- **Dot-connector:** strongest direct evidence survives before any context around it is bought.
- **Expert:** selected first; parents, neighbours, hops compete for the remainder.

### Evidence packet (Core, verified)
- **Idiot:** the final stack handed to the writer.
- **Dot-connector:** the boundary between retrieval and generation; defines what the model is allowed to know.
- **Expert:** produced by packing, consumed by the prompt compiler and verification.

### Fresh compression session (Core, verified)
- **Idiot:** a new conversation for each card.
- **Dot-connector:** carrying the transcript across chunks overflows after a few calls.
- **Expert:** session reset before each chunk in a batch.

### Graph-hop allocation (Conditional, verified)
- **Idiot:** a little space saved for related-but-not-direct cards.
- **Dot-connector:** graph evidence can complete an answer but ranks lower than the anchor.
- **Expert:** lowest priority after core, parent and neighbours.

### Information-density rescue (Core, verified)
- **Idiot:** if compression found nothing, grab the sentences with numbers and names.
- **Dot-connector:** taking the first characters blindly loses a spec buried mid-passage.
- **Expert:** `CompressionResult.effectiveContent` inside the service; note the caller may drop the chunk instead.

### Intent-specific packing (Core, verified)
- **Idiot:** pack a recipe differently from a comparison.
- **Dot-connector:** the same top chunks shouldn't be arranged identically for every answer shape.
- **Expert:** resolved inside `ContextPackingService` from answer intent.

### Lost-in-the-Middle mitigation (Core, verified)
- **Idiot:** best cards first and last.
- **Dot-connector:** models underuse the middle of long prompts; a synthetic fixture tests this.
- **Expert:** applied after selection, before prompt assembly; note the reorder interleaves the ranked set, so downstream code must not assume rank order. **Corrected 2026-10-20:** a lookup skips the reorder, and for other intents it runs over every candidate before the budget cut, so rank 2 lands last and is cut when only about 3 passages fit (`RAGEngine.swift:495-504`, `:773-790`).

### Neighbor allocation (Core, verified)
- **Idiot:** space for the cards next door.
- **Dot-connector:** procedures and definitions cross chunk boundaries.
- **Expert:** after parents, by intent and remaining capacity.

### NO_RELEVANT_CONTENT sentinel (Conditional, verified)
- **Idiot:** the model's way of saying "this card is useless for this question."
- **Dot-connector:** a fixed string is easier to detect than free-form language.
- **Expert:** the compressor marks `wasMarkedIrrelevant`; `RAGService` drops the chunk entirely.

### Parent allocation (Core, verified)
- **Idiot:** space for the paragraph around a hit.
- **Dot-connector:** a precise hit can be uninterpretable without its defining context.
- **Expert:** after core, before graph expansion.

### Query-echo stripping (Core, verified)
- **Idiot:** remove the question if the model parroted it back.
- **Dot-connector:** an echoed question fools later keyword scoring.
- **Expert:** applied to compression output before ratio and relevance checks.

### Question-token cost (Core, verified)
- **Idiot:** your question takes up desk space too.
- **Dot-connector:** a long multi-part question leaves less room and can trigger decomposition.
- **Expert:** measured before capacity is determined.

### Reserved output tokens (Core, verified) and Maximum generation tokens (see module 10)
- **Idiot:** save room for the answer.
- **Dot-connector:** packing to the ceiling leaves no room to write.
- **Expert:** subtracted before evidence selection; default `maxTokens` 512.

### Safety-token reserve (Core, verified)
- **Idiot:** a little extra margin.
- **Dot-connector:** tokenizer estimates and framework wrappers vary; a budget right on average is unsafe under a hard limit.
- **Expert:** 256 tokens.

### Source sentence selection (Core, verified)
- **Idiot:** pick the exact sentences that answer.
- **Dot-connector:** the right chunk still buries the answer among unrelated prose.
- **Expert:** in extractive summarisation, compression, source-only answering and rescue.

### System-prompt overhead (Core, verified)
- **Idiot:** the instructions take space.
- **Dot-connector:** grounding rules and output format are necessary and must be counted.
- **Expert:** counted before evidence capacity.

### Token budget (Core, verified)
- **Idiot:** the whole accounting.
- **Dot-connector:** character or chunk counts aren't enough; capacity is consumed by tokens across every component.
- **Expert:** `FoundationModelTokenBudget`; computed before packing, rechecked before the session call.

### Tool-schema overhead (Conditional, verified)
- **Idiot:** describing the tools to the model costs space.
- **Dot-connector:** capability competes with evidence.
- **Expert:** included only when tools are attached; subtracted before packing.
