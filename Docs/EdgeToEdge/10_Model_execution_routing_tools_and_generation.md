# Module 10. Model execution, routing, tools, and generation

Sixty-two concepts. Choosing which model answers, building the session, and generating: the plan, the route, the session, the stream, the receipt.

## The ladder

**Like you're five.** After the cards are on the desk, the librarian decides who writes. Usually the writer sitting right there. Sometimes nobody, because there isn't enough. Sometimes a rule can just copy the answer out. And sometimes the pile is too big for the small desk, so she asks if she can carry it to Apple's special room, and shows you exactly which cards she'd carry.

**Like an idiot.** Only after retrieval does the app decide where to generate. Four outcomes: abstain (not enough evidence), deterministic (a rule extracts the answer directly), on-device (Apple's built-in model, the normal case), or Private Cloud Compute (Apple's cloud, built so Apple can't read it either). The cloud is picked only if the evidence doesn't fit locally or the question is genuinely hard, and only if the network is up and you've consented after seeing the exact trimmed payload. Every cloud plan has an on-device fallback. The model streams a typed answer: a list of claims, each with the IDs of the chunks that support it.

**Like less of an idiot.** The plan is an immutable object with a target, a reason, token estimates, a fallback and a policy version. The route policy maps it to a Foundation Models session. The session factory builds the session with instructions, optional tools and an optional saved transcript. Generation uses constrained decoding into `@Generable` types, so the output is a `RAGAnswer` with reasoning, answer, confidence, citations, atomic claims and matched terms, not free text to be parsed. A receipt records what was intended, what was attempted and what completed, so the badge on screen reflects the route that actually ran, not the one you picked in settings.

**Average Joe.** Why route after retrieval? Because before retrieval the app doesn't know how big the evidence is or what exact text would leave the phone, so it can't ask for meaningful consent. Why does "advanced on-device model" exist as an option if there's no such model? Because older settings stored it; the alias now runs the default model and corrects its own telemetry rather than claiming a tier that never ran. Why does the cloud not get a bigger context window? Because Apple's per-session limit is 4,096 tokens for both; the cloud buys a bigger model, not a bigger desk.

**Dot-connector.** Two vocabularies to keep apart. Execution context (automatic, on-device only, prefer cloud, cloud only) is the user's privacy policy. Quality mode is effort. They're independent: Maximum with on-device-only never leaves the phone. Also: the whole cloud apparatus (consent, transmission record, minimised payload, quota state, reasoning level) is labelled Dormant in the word bank because shipped App Store builds have carried zero PCC symbols; the code compiles under Swift 6.4 and iOS 27 but a given build is a build fact, not a source fact. On iOS 26 the route is always on-device.

**Expert.** `ModelExecutionPlanner.makePlan`: abstain when evidence is insufficient; deterministic when an extractor answers; PCC when `capability.canUsePCC && constraints.networkAvailable && (constraints.isForegroundInteractive || constraints.consentGranted) && (!localBudget.fits || complexity.requestsPCC)`, reason local context exceeded or complex synthesis; otherwise on-device with reason network unavailable, consent unavailable or local context fits. Fallback on-device for every cloud plan; stages retrieve (deterministic), synthesise (target), verify (deterministic). Cloud evidence minimiser: chunks in rank order, per-chunk allowance `min(remaining, max(240, maxChars / min(count, 8)))`, prefix-cut. `FoundationModelRoutePolicy`: with a plan, deterministic/on-device/abstain map to on-device and cloud maps to cloud with reasoning none/moderate/deep by mode; without a plan, `core3B` and `advanced20B` aliases force on-device, manual cloud forces cloud, automatic reads the on-device limit from the system model and routes cloud only when the estimate exceeds it and `isPCCAvailable` (Swift 6.4, iOS/macOS 27, entitlement, cloud model available, quota not reached). `FoundationModelSessionFactory`: on-device `SystemLanguageModel.default`, availability guard, session from saved transcript with prewarm when a transcript exists and tools are enabled, else compiled instructions; the advanced route executes the default model and corrects the reported route; cloud creates the PCC model with entitlement and quota guards. `GenerationOptions`: temperature 0.4/0.4/0.3, `maximumResponseTokens` from settings when positive (default 512). `streamResponse` with a continuation-prompt path for partial completions and response-tail trimming after termination. `FoundationModelToolRegistry` registers ten tools: SearchDocuments, ListDocuments, GetDocumentSummary, CountPattern, SearchExactPattern, GetCorpusStats, FindRelatedDocuments, CompareDocuments, RetrieveCorpusEvidence, InspectDocument. PCC suppression: `suppressPCC(for:reason:)` sets `pccSuppressedUntil` after a route failure and the coordinator checks it before planning. `ModelExecutionReceipt` records intended, actual and completed targets, attempts, quota, fallback reason, policy version and timing. Consent choices: allow once, allow and remember, deny.

**Expert's expert.** Corrections to the bank. The tool registry is ten tools, not "approximately six." `CloudTransmissionRecord` and the consent prompt are real, compiled code with a preview; "Dormant" describes shipped reach, not compilation. The on-device model's placement across CPU, GPU and Neural Engine is Apple's decision and unobservable from the app, so any sentence that says where the language model runs is speculation. And the deterministic target is where a surprising share of lookup answers come from: when structured table lookup or pattern extraction succeeds with confidence, the language model is never called, which is both the fastest path and the one with zero hallucination risk.

## Every concept

### @Generable (Core, verified) and @Guide (Core, verified) and Constrained decoding (Core, verified) and Structured generation (Core, verified)
- **Idiot:** the model has to fill in a form, not write an essay.
- **Dot-connector:** typed fields with natural-language guides; decoding restricted to the schema; claims, citations, confidence and refusal become machine-readable without fragile JSON parsing.
- **Expert:** `RAGStructuredResponse` types; `FoundationModelStructuredGenerator`; converted into `StructuredAnswer` before verification.

### Abstain execution target (Core, verified)
- **Idiot:** the plan can be "don't answer."
- **Dot-connector:** no model should turn absent or contradictory evidence into fluent certainty.
- **Expert:** `ModelExecutionPlan` target selected when evidence or authorization fails before execution.

### Active model (Core, verified) and Selected model (Core, verified) and ModelResolutionService (Support, verified)
- **Idiot:** what you asked for versus what actually ran, and the thing that keeps them straight.
- **Dot-connector:** fallback, availability and route policy make them differ; a picker label is not proof.
- **Expert:** `LLMModelType` for selection; resolution state observes settings and `RAGService` and updates the UI.

### AdapterManager (Support, verified)
- **Idiot:** the adapter that picks a model backend.
- **Dot-connector:** decouples the engine from one implementation; carries legacy transitions.
- **Expert:** resolves an `LLMService` before execution.

### advanced20B preference alias (Historical, verified) and core3B preference alias (Historical, verified)
- **Idiot:** old menu names that both mean "on device."
- **Dot-connector:** stored preferences keep resolving without claiming a model Apple doesn't expose.
- **Expert:** canonicalised in `FoundationModelRoutePolicy`; the advanced route executes the default model and reports on-device.

### Apple Foundation Models (Core, verified) and SystemLanguageModel.default (Core, verified) and LanguageModelSession (Core, verified)
- **Idiot:** Apple's built-in writer, and one conversation with it.
- **Dot-connector:** the OS owns availability, updates and hardware scheduling; the app queries capability rather than assuming a parameter count; a session carries instructions, tools, transcript and calls.
- **Expert:** created after route and budget resolution by the session factory; the app cannot place the model on a processor.

### Atomic claim (Core, verified)
- **Idiot:** one fact per sentence.
- **Dot-connector:** verifiable separately; the unit Gate B grades.
- **Expert:** in `RAGAnswer` and `StructuredAnswer`.

### Citation namespace (Core, verified) and Evidence source label (Core, verified)
- **Idiot:** S1 in the text is chip 1 below it, always.
- **Dot-connector:** a cited answer is unsafe if labels can drift between prompt, output, chips and source views.
- **Expert:** assigned by the prompt compiler; validated when the structured response is built; the agentic chain once resolved against the wrong array.

### Cloud consent (Dormant in reach, verified in code) and Cloud transmission record (Dormant in reach, verified) and Minimized cloud payload (Dormant in reach, verified) and PCC quota state (Dormant) and PCC reasoning level (Dormant) and Private Cloud Compute target (Dormant)
- **Idiot:** the whole "outside room" apparatus: ask, record what left, send the minimum, check the meter, pick how hard the cloud thinks.
- **Dot-connector:** consent after the exact payload is known; an audit record of provider, model, preview, counts, hashes, bytes, plan and reason; only selected evidence, never the library; quota available/limit reached/unsupported/unknown; reasoning none/moderate/deep by mode. All real, all compiled, none reachable in a build without PCC symbols.
- **Expert:** `CloudTransmission.swift`, `CloudConsentPromptView`, the minimiser in the planner, `FoundationModelRoute`, `ModelExecutionReceipt`; gated by `isPCCAvailable`.

### Deterministic execution target (Core, verified)
- **Idiot:** a rule copies the answer out; no writer needed.
- **Dot-connector:** when structure already yields the answer, generation adds risk and latency.
- **Expert:** selected after high-confidence extraction; skips the model call.

### DirectRAGAnswer (Conditional, verified) and RAGAnswer (Core, verified) and Reasoning-first field order (Conditional, verified)
- **Idiot:** the form the writer fills in, with a "show your reasoning" box first.
- **Dot-connector:** the smaller form skips reasoning for direct answers; the reasoning field first encourages finding facts before committing.
- **Expert:** `RAGStructuredResponse`.

### Execution attempt (Core, verified), Execution fallback (Core, verified), ModelExecutionReceipt (Core, verified), Route reason (Core, verified), Policy version (Support, verified)
- **Idiot:** the receipt: what was tried, in order, what worked, and why.
- **Dot-connector:** the badge and the debugging both come from the receipt, not from settings; fallback must be explicit.
- **Expert:** attempts appended as calls occur; `policyVersion` on plan and receipt.

### Execution context (Core, verified)
- **Idiot:** your privacy setting.
- **Dot-connector:** automatic, on-device only, prefer cloud, cloud only; independent of quality mode.
- **Expert:** `LLMModel.swift` enum; resolved before planning, enforced again at plan creation.

### Fail-closed routing (Core, verified)
- **Idiot:** if unsure, stay home.
- **Dot-connector:** denied, unknown, unsupported, unavailable or exhausted never becomes a cloud attempt.
- **Expert:** enforced in planning, consent, quota checks and receipt invariants; `RouteEvalMetrics`.

### Foundation Model preference (Core, verified) and InferenceConfig (Core, verified)
- **Idiot:** your model choice, and the bundle of settings every call uses.
- **Dot-connector:** one consistent expression of user and policy intent for all calls in a query, including agentic synthesis.
- **Expert:** preference in `InferenceConfig`; interpreted before session construction.

### Foundation Model tool (Conditional, verified), FoundationModelToolRegistry (Conditional, verified), Registered retrieval tools (Conditional, verified, ten), Tool call (Conditional, verified), Tool-call counter (Support, verified)
- **Idiot:** things the writer is allowed to ask the librarian to do, and a counter so it can't ask forever.
- **Dot-connector:** typed, allowlisted operations keep the model inside local data; schema costs tokens; a query-scoped counter bounds loops.
- **Expert:** ten `Tool` structs in the registry; attached only when the plan allows; `ToolCallCounter`.

### FoundationModelSessionFactory (Core, verified) and Session use case (Core, verified) and Session transcript (Core, verified) and Transcript persistence (Support, verified)
- **Idiot:** the one place sessions are built, labelled by job, with memory that can be saved.
- **Dot-connector:** central construction keeps instructions, tools and routing consistent; different jobs get different instructions; the transcript grows and is reset when the budget requires.
- **Expert:** `FoundationModelTranscriptStore`, `TranscriptPersistenceService`; resume with prewarm when a transcript exists and tools are enabled.

### LLMService (Core, verified) and Local OpenAI-compatible server backend (Conditional, verified)
- **Idiot:** the department that talks to the model; and a developer switch to talk to a local server instead.
- **Dot-connector:** retrieval shouldn't know session details; UI shouldn't own model state; the local server adapter gets the same packed prompt.
- **Expert:** `LLMService` (2,079 lines); `LocalOpenAIServerLLMService`.

### Matched terms (Support, verified)
- **Idiot:** the words the writer says it found.
- **Dot-connector:** a diagnostic, not a truth signal.
- **Expert:** field on `RAGAnswer`.

### Maximum generation tokens (Core, verified), Temperature (Core, verified), Top-p (Support, verified)
- **Idiot:** how long, how random, how narrow.
- **Dot-connector:** output cap bounds latency; low temperature suits exact values; nucleus sampling applies where the backend supports it.
- **Expert:** `maxTokens` default 512 into `maximumResponseTokens`; 0.4/0.4/0.3; `samplingMode .topP`.

### Model availability state (Core, verified)
- **Idiot:** is the writer even here today?
- **Dot-connector:** available, simulator unsupported, unsupported device, Apple Intelligence off, model preparing; fail explicitly, early.
- **Expert:** checked at SDK and query entry in `OpenIntelligenceEngine`.

### ModelExecutionPlan (Core, verified) and Post-retrieval routing (Core, verified)
- **Idiot:** the decision, made after the cards are on the desk.
- **Dot-connector:** a checkable decision based on the exact minimised evidence, not a vague preference.
- **Expert:** immutable; target, reason, estimates, fallback, policy version; created after packing, before consent and execution.

### On-device execution target (Core, verified)
- **Idiot:** the normal case.
- **Dot-connector:** the only generative target in shipping App Store builds.
- **Expert:** `SystemLanguageModel.default` through the session factory.

### Partial stream completion (Core, verified) and Response-tail trimming (Core, tests verified) and Streaming generation (Core, verified) and Time to first token (Support, verified) and Tokens per second (Support, verified)
- **Idiot:** the answer arrives word by word; if it cuts off, keep what's good and tidy the edge; and the stopwatch numbers.
- **Dot-connector:** partial text beats nothing when marked incomplete; trimming removes broken trailing structure; TTFT separates setup from streaming; TPS measures throughput, not quality.
- **Expert:** `RAGService+Streaming`; `ResponseTailTrimmingTests`; recorded in diagnostics.

### PCC suppression cooldown (Support, verified)
- **Idiot:** after the cloud fails, don't keep knocking.
- **Dot-connector:** repeated attempts at an unavailable route waste latency and can loop.
- **Expert:** `suppressPCC(for:reason:)` sets `pccSuppressedUntil`; checked by the coordinator and the orchestrator before planning.

### Prompt compiler (Core, verified)
- **Idiot:** writes the instructions the model reads.
- **Dot-connector:** intent, excerpts, labels, grounding rules, format and route constraints; must stay in sync with citation and verification expectations.
- **Expert:** `FoundationModelPromptCompiler` after packing, before the session request.
