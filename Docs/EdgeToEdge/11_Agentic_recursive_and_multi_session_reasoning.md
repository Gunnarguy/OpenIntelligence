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

**Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress):** the ladder above describes a loop that does not run that way, in plain words first.

**In plain words, corrected.** The librarian pulls one pile of cards, once, at the start. She does not go back to the shelves between rounds. Each round she reads the next few cards from that same pile, writes a short note, and starts the next round with a clean desk and her notes. She stops when the pile runs out, or when she is sure, has covered every part of the question and is learning nothing new, all at once. Only after she has written a draft, and only if it leaves parts of the question open, does she go back to the shelves, for a few short trips with a 3-minute timer. For a question that asks for one exact value, she may copy the value straight from the source and never start the rounds at all.

**What the code does.** The loop starts because the person chose Deep Think or Maximum or pressed Go Deeper. Planner escalation is off while Apple's model writes the answers. An on-device planning call, a guided generation with a heuristic plan as its fallback, decides whether documents are needed. A lookup can be answered by the extractor before any session, with no model call of its own and no gates. Retrieval runs once, before the sessions: up to 5 search phrasings each go through module 08's pipeline, fused into 20 passages, graded, widened by cross-reference resolution and graded again, and only an excellent or good grade enters a chain (moderate gets one synthesis, and low first tries speculative candidates, the best of which can be the answer). Deep Think's chain cuts every session's window from that one pool before session 1, 4 passages on a 4,096-token window and up to 7 on 8,000 or more, sized from the window the device reports where the OS can count tokens, with extracted sentences as the fallback. It runs at most 8 sessions on every device, and fewer when the pool runs out of distinct windows (5 for 20 passages). It stops then, or before a session from the fifth when confidence, sub-question coverage and novelty exhaustion all clear at once, or when the model writes ANSWER COMPLETE or NOT FOUND IN DOCUMENTS from the second session, or when a session still fails after its retries. The 180 seconds bound only the research rounds after the chain, and nothing in the loop reads the thermal state. Sessions carry PRIOR FINDINGS (up to 1,200 characters), STILL UNANSWERED (up to 3 open sub-questions) and a SESSION OBJECTIVE, and the FactBank's text reaches a prompt only in Maximum. Tools are off in every Deep Think and Maximum session and synthesis. Under the default Hybrid route the sessions are pinned to the device and the syntheses can be planned to Private Cloud Compute, and with Private Cloud Compute picked in the model picker the sessions can go too. Deep Think does not use the four profiles: it takes the device's configuration (A17 Pro 5 steps and 0.85, A18 8 and 0.90, A19 10 and 0.92, the ultra tier 12 to 32 by memory and 0.95, where the ultra tier is a Mac from the M2 or the M1 Ultra, an iPad Pro from the M2 or an iPhone from the A20), and Maximum takes unlimited. Maximum's own loop reads 3 unread passages a session and never searches again, because its re-retrieval branch cannot be reached. The helper calls run at temperature 0.7, and the sessions at the adaptive profile's temperature or 0.5. Self-RAG is real code (`runVerificationLoop`): a lexical relevance score and a citation score (a citation counts when its passage holds at least 30 percent of the words of 4 or more letters in the 50 characters before it), with no model call, and at most 2 retries through research, since the third retry verdict ends it. It does not run when research has replaced the synthesis. The nine gates do not run on these answers in the shipped 5.6, and from 5.7 they set the label only, Verified when all nine pass. The standard reasoning chain runs only with the developer setting `forceReasoningChain` on, and it then runs Deep Think's chain on the `fast` configuration. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, section 19, has every number with its file and line. `[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift:297-305 and :3527-3545 (the planning call), :521-536 (cross-references), :544-1143, :1043-1069 (speculative candidates), :1916-2260, :2892, :3786-4012, :4163-4232 (citations), :779 and :798 (research returns before the check), :5003-5318, :5313-5512 (retries and a failed session), :5521-5531, :6706-6807, :8205-8245, :9063-9117, :9123-9248, OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift:67-99, OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift:294-332, OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:10561-10737, :10863-10871, :11238-11262, :15949-16002, OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift:202-229, OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift:1096-1488 (the tier tables)]`

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
- **Expert:** structured output in `RAGStructuredResponse`; produced by one session, consumed by the next. **Corrected 2026-10-20:** the type is defined and referenced nowhere, so read it as Dormant. What crosses sessions is the prose of earlier insights (`Core/Models/RAGStructuredResponse.swift:278`).

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
- **Expert:** after synthesis, before refinement or abstention; can precede another verification pass. **Corrected 2026-10-20:** the critique, a word check with no model call, runs only on the path for a question that needs no documents (`AgenticOrchestrator.swift:3463` and `:3548-3590`). Self-RAG is a real check, `runVerificationLoop` with `verifySelfRAG`, lexical and with no model call (`:3786-4000`).

### Default, Fast, Thorough, Unlimited agentic profiles (Conditional, verified)
- **Idiot:** four gears.
- **Dot-connector:** fast 2 steps, default 5, thorough 8, unlimited 50; confidence targets 0.70, 0.85, 0.95, 0.98; escalation floors 0.25, 0.35, 0.45, 0.50.
- **Expert:** `AgenticConfig` in `AgenticOrchestrator`; unlimited carries the "thermal will stop us first" comment. **Corrected 2026-10-20:** only unlimited drives a mode (Maximum). Deep Think takes `DeviceCapabilityService.optimizedAgenticConfig()` instead, default and thorough drive no mode, and fast runs only on a device without Apple Intelligence and in Standard's developer-forced chain (`RAGService.swift:10863-10871`, `DeviceCapabilityService.swift:1046-1047`, `AgenticOrchestrator.swift:9068`).

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
- **Expert:** parents, siblings, cross-references, entities, graph neighbours, broader candidates. **Corrected 2026-10-20:** the entity index is never filled. The agentic "graph expansion", for a moderate or low pool only, asks the model to name up to 3 entities and searches each (`AgenticOrchestrator.swift:487-502`, `:2524-2595`).

### Fact (Conditional, verified), Fact deduplication (Conditional, verified), Fact provenance (Conditional, verified), FactBank (Conditional, verified)
- **Idiot:** the notebook, one fact per line, each with where it came from, no repeats.
- **Dot-connector:** atomic facts can be deduplicated, checked for contradictions and mapped to sources; repeats raise confidence instead of consuming state; the bank is what makes fresh sessions possible.
- **Expert:** initialised after planning, updated after analysis, consumed by final synthesis; provenance reused for citations. **Corrected 2026-10-20:** in Deep Think the bank is never put into a prompt. It holds at most 1,500 characters and decides coverage, novelty and stopping, and the final synthesis reads the findings instead. Only Maximum reads the bank into its running answers and final synthesis (`AgenticOrchestrator.swift:6081`, `:7292`, `:7352`, `:5879-5951`).

### Hard session cap (Core, verified)
- **Idiot:** an absolute maximum number of rounds.
- **Dot-connector:** protects battery, heat, latency, quota and cancellation even if convergence never comes.
- **Expert:** checked before each session; 50 for unlimited, scaled to the pool. **Corrected 2026-10-20:** for Deep Think the cap is min(8, sessions + 4), which is 8 on every device, and the distinct windows usually end it first (`AgenticPolicyService.swift:304`, `AgenticOrchestrator.swift:5150`).

### LLM call count (Support, verified) and Reasoning-chain token total (Support, verified)
- **Idiot:** how many times the model was asked, and how many tokens that cost in total.
- **Dot-connector:** one 4,096 window per session says nothing about the whole answer's cost. **Corrected 2026-10-20:** the window is the one the device reports, 4,096 on the owner's iPhone and 8,192 on his Mac.
- **Expert:** accumulated in `RAGService`, stored in audit metadata.

### Planning phase (Conditional, verified)
- **Idiot:** decide what to look for before looking.
- **Dot-connector:** searching before defining requirements finds relevant passages that still don't answer.
- **Expert:** first phase; identifies subquestions and an initial strategy.

### ReasonedInsight (Conditional, verified) and ReasonedSynthesis (Conditional, verified)
- **Idiot:** the note from a reading round, and the final write-up.
- **Dot-connector:** insight: analysis, one key point, discovered terms, confidence. Synthesis: key points, confidence, sources, reconciled rather than concatenated.
- **Expert:** structured types in `RAGStructuredResponse`. **Corrected 2026-10-20:** both are defined and referenced nowhere, so read them as Dormant. The syntheses write plain text.

### Reasoning session (Conditional, verified)
- **Idiot:** one fresh conversation with the model, for one job.
- **Dot-connector:** fresh sessions avoid overflow and separate assessment from answer writing.
- **Expert:** one `LanguageModelSession` per objective; sequential or conditional.

### Recursive RAG (Conditional, verified)
- **Idiot:** several small searches and reads instead of one giant one.
- **Dot-connector:** many 4,096-token sessions can collectively read more than one can, if only condensed state moves forward.
- **Expert:** begins after planning, ends with synthesis over accumulated state; `executeRecursiveResearch` with its two call sites. **Corrected 2026-10-20:** the research rounds run only after Deep Think's chain, on an excellent pool whose coverage fell short or whose answer reads like a miss, and in the Self-RAG retries. Maximum never runs them (`AgenticOrchestrator.swift:685-791`, `:3855`).

### Reformulating phase (Conditional, verified)
- **Idiot:** ask it differently.
- **Dot-connector:** repeating a failed search can't find a new neighbourhood.
- **Expert:** after gap analysis, before a new search pass.

### Searching phase (Conditional, verified)
- **Idiot:** go look.
- **Dot-connector:** hybrid retrieval for the current sub-question; grounded before claims.
- **Expert:** module 08's pipeline invoked per sub-question. **Corrected 2026-10-20:** it is invoked once per search phrasing before the sessions, up to 5, and again only in research rounds. Sessions do not search.

### Standard reasoning chain (Conditional, verified)
- **Idiot:** a little bit of structured thinking inside a normal answer.
- **Dot-connector:** bounded, no open-ended retrieval loop; easy to mistake for the agentic path in logs.
- **Expert:** in `RAGService` after context selection, before verification. **Corrected 2026-10-20:** it runs only when the developer setting `forceReasoningChain` is on, off by default, and it then runs Deep Think's chain on the `fast` configuration (`RAGService.swift:15949-16002`, `AgenticOrchestrator.swift:9063-9117`).

### Synthesizing phase (Conditional, verified)
- **Idiot:** write the answer.
- **Dot-connector:** only after coverage or stopping policy says there's enough.
- **Expert:** consumes the FactBank; goes through the post-retrieval plan. **Corrected 2026-10-20:** Deep Think's synthesis reads the sessions' findings (at most 3,000 characters) and, on the device, no passages, and Maximum's reads the FactBank and recent insights. Both go through the post-retrieval plan, and a PCC plan adds an envelope minimized from the passages, at most 12,000 characters (`AgenticOrchestrator.swift:5939-5947`, `:7432`, `:9283-9303`).

### Verifying phase (Conditional, verified)
- **Idiot:** check it.
- **Dot-connector:** more model calls don't make an answer trustworthy; the gates still run.
- **Expert:** `VerificationGateService` after synthesis or refinement; can trigger repair or abstention. **Corrected 2026-10-20:** on Deep Think and Maximum answers the gates do not run in the shipped 5.6. From 5.7 they run once after the loop and set the label only, Verified when all nine pass with Gate A's floor raised by the mode: no repair, no abstention (`RAGService.swift:11238-11262`, `:18205-18253`, `ConfidencePolicyService.swift:26-46`).
