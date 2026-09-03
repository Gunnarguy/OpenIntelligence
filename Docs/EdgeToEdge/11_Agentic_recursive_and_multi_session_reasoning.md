# Module 11. Agentic, recursive, and multi-session reasoning

Forty concepts. Thinking in loops: when one pass is not enough, plan, search, read, take notes, search again, write, check.

## The ladder

**Like you're five.** For a hard question, the librarian doesn't grab one pile and write. She makes a plan, looks, writes down what she found on a notepad, decides what's still missing, looks again, and only writes the answer when the notepad has enough. She has a timer, and she stops when it rings.

**Like an idiot.** Deep Think and Maximum run the whole search-and-read pipeline in a loop. Each round: pick a sub-question, search, read the results, add facts to a notebook, ask "is that enough?" If not, rewrite the question or split it and go again. It stops when it's confident, when new rounds find nothing new, when 180 seconds are up, or when it hits a hard cap on rounds. All the thinking happens on the phone. Only the final write-up can go to the cloud, with the same consent as always.

**Like less of an idiot.** The on-device model has a 4,096-token window and it's a small model. It cannot answer a multi-hop question in one shot. So the orchestrator works in sessions, each a fresh window, and carries a FactBank between them: atomic, source-backed facts with provenance, deduplicated, instead of the raw transcript. Escalation into the loop is decided by measured retrieval quality against a profile threshold, not by guessing complexity up front. There are four profiles with a step cap, a confidence target and an escalation threshold each. The loop has named phases (planning, searching, expanding, analyzing, synthesizing, refining, reformulating, verifying) that the UI shows as thinking events.

**Average Joe.** Why the notebook instead of just remembering the conversation? Because remembering the conversation is exactly what overflowed: the transcript carried between sessions hit 4,521 tokens on a 4,096 limit and the final draft failed. Why disable tools inside Maximum's sessions? Same reason: tool schemas cost tokens and tool outputs land in the transcript. Why a wall clock? Because thermal will stop a phone before the maths does, and the source says so in a comment.

**Dot-connector.** Three things to hold together. First, the loop reuses module 08 for every search; nothing new happens at retrieval, only more of it, driven by evidence gaps. Second, there are two call sites for recursive research with different iteration caps (five and three), and the only way to know which ran is the denominator in the log's iteration counter; guarding one of them is not guarding both. Third, the loop's stopping target (0.98 for unlimited) is a different number from the mode's verification bar (0.80 for Maximum): one says when to stop searching, the other says whether the answer may stand.

**Expert.** `AgenticConfig` profiles: fast (2 steps, 0.70 confidence, escalate below 0.25), default (5, 0.85, 0.35), thorough (8, 0.95, 0.45), unlimited (50, 0.98, 0.50). Retrieval quality is scored after each expansion; lexical relevance under 0.10 with an invalid semantic intent is a hard exit; semantic mismatch downgrades to moderate through `AgenticPolicyService`. `executeRecursiveResearch`: default max iterations 7, time budget 180 s, per-iteration decision over accumulated context with actions search or answer; call sites pass 5 (fallback on a reasoning miss) and 3 (verification-loop retry). Reasoning chain sessions: light 3, standard 4, deep 5, unlimited 50, each a 4,096-token window; rotating contexts with stride equal to chunks per session. True unlimited reasoning: target 0.98, max 50 sessions scaled to the evidence pool at three chunks per session, FactBank decomposition into subquestions, running synthesis, termination on target, saturation, cancellation or cap, tools disabled inside sessions. Internal calls set `executionContext = .onDeviceOnly`, `allowPrivateCloudCompute = false`, temperature 0.7. Final synthesis goes through `generateWithProperConsent`, which calls the post-retrieval planner. Memory turn limit by mode: roughly 5, 10, 20. Conversation memory summarises older turns.

**Expert's expert.** Recorded hazards in the source, all now fixed but worth knowing because they are the shape of what goes wrong here: citations resolved against the wrong array for the life of the chain; a shorter re-ordered list turning citations past its end into dangling references; a fabricated 0.70 match score hardcoded on the audit snapshot rather than measured, confirmed as exactly 0.7 on all 82 rows of one Deep Think run; the lost-in-middle reorder that interleaves the ranked set so the array reaching the chain is not in rank order. The bank's "Self-RAG" is a design label, not a distinct service; the behaviour is the critique and refine phases plus the gates. And "standard reasoning chain" means a bounded multi-step path inside some Standard answers that does not invoke the full orchestrator; it is easy to mistake for the agentic loop in logs.

## Every concept

### Agentic configuration (Conditional, verified)
- **Idiot:** the rules of the loop: how many rounds, how confident, how long.
- **Dot-connector:** an open-ended model loop needs deterministic bounds for battery, heat and quota.
- **Expert:** `AgenticConfig` resolved from mode, device policy and user action before the first step.

### Agentic phase (Conditional, verified) and ThinkingEvent (Support, verified) and Reasoning trace (Support, verified)
- **Idiot:** the loop tells you what it's doing: planning, searching, reading, writing.
- **Dot-connector:** explicit phases make the loop observable and let policy control what's legal next; typed events keep the UI honest without parsing logs.
- **Expert:** `ThinkingEvent` with phase, title, detail, counters, confidence; emitted through the SDK.

### AgenticOrchestrator (Conditional, verified)
- **Idiot:** the loop's brain.
- **Dot-connector:** planning, repeated retrieval, assessment, reformulation, fact accumulation, synthesis, refinement, verification.
- **Expert:** 8,780 lines; replaces the single-pass path in Deep Think, Maximum, forced and escalated runs.

### Analyzing phase (Conditional, verified)
- **Idiot:** read what you found.
- **Dot-connector:** extract facts, resolve sources, name what's missing; quantity is not completeness.
- **Expert:** after retrieval and expansion; decides synthesise, reformulate or search again.

### ChainLink (Conditional, verified)
- **Idiot:** a small note passed from one round to the next.
- **Dot-connector:** reasoning, condensed insight, next focus, cumulative confidence; a bounded state instead of a transcript.
- **Expert:** structured output in `RAGStructuredResponse`; produced by one session, consumed by the next.

### Convergence (Conditional, verified) and Evidence-driven stopping (Core, verified)
- **Idiot:** stop when nothing new is turning up.
- **Dot-connector:** coverage, confidence, novelty, contradictions and improvement decide, not a fixed count.
- **Expert:** `AgenticPolicyService` after each pass; can end the loop before the cap.

### Conversation summary (Conditional, verified) and ConversationMemoryService (Conditional, verified) and Memory turn limit (Core, verified)
- **Idiot:** the app remembers the gist of the chat so far, up to a point.
- **Dot-connector:** follow-ups need prior entities and constraints; the whole history would eat the window; roughly 5, 10 or 20 turns by mode, older ones summarised.
- **Expert:** consulted before rewriting, updated after answers; limits in `RAGQualityMode`.

### Coverage map (Conditional, verified)
- **Idiot:** a checklist of the question's parts.
- **Dot-connector:** the loop needs a concrete definition of "done."
- **Expert:** updated after each fact-analysis pass, checked before synthesis.

### Critique step (Conditional, verified) and Refining phase (Conditional, verified) and Self-RAG (Conditional, design label)
- **Idiot:** read your own draft, find the weak spots, fix them.
- **Dot-connector:** targeted repair beats restarting; this is what the bank calls Self-RAG.
- **Expert:** after synthesis, before refinement or abstention; can precede another verification pass.

### Default, Fast, Thorough, Unlimited agentic profiles (Conditional, verified)
- **Idiot:** four gears.
- **Dot-connector:** fast 2 steps, default 5, thorough 8, unlimited 50; confidence targets 0.70, 0.85, 0.95, 0.98; escalation floors 0.25, 0.35, 0.45, 0.50.
- **Expert:** `AgenticConfig` in `AgenticOrchestrator`; unlimited carries the "thermal will stop us first" comment.

### Evidence gap (Conditional, verified)
- **Idiot:** the specific thing still missing.
- **Dot-connector:** naming the gap makes the next search targeted.
- **Expert:** from evidence assessment; becomes the next reformulation or subquery.

### EvidenceThread (Core, verified)
- **Idiot:** a saved conversation, per library.
- **Dot-connector:** the user-visible thread persists separately from transient model sessions.
- **Expert:** `EvidenceThread` model, `EvidenceThreadStore`; loaded before memory processing.

### Expanding phase (Conditional, verified)
- **Idiot:** pull in the neighbours.
- **Dot-connector:** the first hit is usually an anchor, not the whole answer.
- **Expert:** parents, siblings, cross-references, entities, graph neighbours, broader candidates.

### Fact (Conditional, verified), Fact deduplication (Conditional, verified), Fact provenance (Conditional, verified), FactBank (Conditional, verified)
- **Idiot:** the notebook, one fact per line, each with where it came from, no repeats.
- **Dot-connector:** atomic facts can be deduplicated, checked for contradictions and mapped to sources; repeats raise confidence instead of consuming state; the bank is what makes fresh sessions possible.
- **Expert:** initialised after planning, updated after analysis, consumed by final synthesis; provenance reused for citations.

### Hard session cap (Core, verified)
- **Idiot:** an absolute maximum number of rounds.
- **Dot-connector:** protects battery, heat, latency, quota and cancellation even if convergence never comes.
- **Expert:** checked before each session; 50 for unlimited, scaled to the pool.

### LLM call count (Support, verified) and Reasoning-chain token total (Support, verified)
- **Idiot:** how many times the model was asked, and how many tokens that cost in total.
- **Dot-connector:** one 4,096 window per session says nothing about the whole answer's cost.
- **Expert:** accumulated in `RAGService`, stored in audit metadata.

### Planning phase (Conditional, verified)
- **Idiot:** decide what to look for before looking.
- **Dot-connector:** searching before defining requirements finds relevant passages that still don't answer.
- **Expert:** first phase; identifies subquestions and an initial strategy.

### ReasonedInsight (Conditional, verified) and ReasonedSynthesis (Conditional, verified)
- **Idiot:** the note from a reading round, and the final write-up.
- **Dot-connector:** insight: analysis, one key point, discovered terms, confidence. Synthesis: key points, confidence, sources, reconciled rather than concatenated.
- **Expert:** structured types in `RAGStructuredResponse`.

### Reasoning session (Conditional, verified)
- **Idiot:** one fresh conversation with the model, for one job.
- **Dot-connector:** fresh sessions avoid overflow and separate assessment from answer writing.
- **Expert:** one `LanguageModelSession` per objective; sequential or conditional.

### Recursive RAG (Conditional, verified)
- **Idiot:** several small searches and reads instead of one giant one.
- **Dot-connector:** many 4,096-token sessions can collectively read more than one can, if only condensed state moves forward.
- **Expert:** begins after planning, ends with synthesis over accumulated state; `executeRecursiveResearch` with its two call sites.

### Reformulating phase (Conditional, verified)
- **Idiot:** ask it differently.
- **Dot-connector:** repeating a failed search can't find a new neighbourhood.
- **Expert:** after gap analysis, before a new search pass.

### Searching phase (Conditional, verified)
- **Idiot:** go look.
- **Dot-connector:** hybrid retrieval for the current sub-question; grounded before claims.
- **Expert:** module 08's pipeline invoked per sub-question.

### Standard reasoning chain (Conditional, verified)
- **Idiot:** a little bit of structured thinking inside a normal answer.
- **Dot-connector:** bounded, no open-ended retrieval loop; easy to mistake for the agentic path in logs.
- **Expert:** in `RAGService` after context selection, before verification.

### Synthesizing phase (Conditional, verified)
- **Idiot:** write the answer.
- **Dot-connector:** only after coverage or stopping policy says there's enough.
- **Expert:** consumes the FactBank; goes through the post-retrieval plan.

### Verifying phase (Conditional, verified)
- **Idiot:** check it.
- **Dot-connector:** more model calls don't make an answer trustworthy; the gates still run.
- **Expert:** `VerificationGateService` after synthesis or refinement; can trigger repair or abstention.
