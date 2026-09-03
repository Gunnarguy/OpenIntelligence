# Module 07. Query understanding, intent, and execution planning

Forty-five concepts. Understanding the question before searching: what kind of answer is wanted, how hard it is, and what plan to run.

## The ladder

**Like you're five.** Before the librarian goes looking, she reads your question twice and asks herself: does this person want one fact, or the whole story? Is this easy or hard? Then she decides how much running around to do.

**Like an idiot.** The app profiles your question before it searches. Lookup, table lookup, procedure, comparison, summary, investigation, computation, findings: each wants different evidence and a different-shaped answer. It rates complexity, decides whether this is a one-pass job or a loop, may clean up your question, may expand it with the library's own vocabulary, and may write an imaginary answer just to search with. All of that gets resolved once, up front, into a plan.

**Like less of an idiot.** Two objects matter. `QueryProfile` describes the question: word count, entities, answer intent, search intent, routing class, complexity. `QueryExecutionPlan` says what the engine will do about it: direct or decomposed, tools or not, escalate to agentic or not, which response strategy. The runtime coordinator resolves both plus quality mode, PCC eligibility and adaptive configuration before any search runs. There are exactly three ways a run becomes agentic: the mode is Deep Think or Maximum, the user pressed Go Deeper, or the planner escalated a Standard query. A `GroundedAnswerPolicy` then decides whether the answer should be extracted by rules, extracted by a tightly constrained prompt, or synthesised with citations.

**Average Joe.** Why rewrite the question? Users type short, vague, conversational questions ("what about the other one?") and the index was built from long, specific text. A standalone rewrite resolves the pronouns from conversation memory. HyDE has the model write a plausible answer passage and searches with that, because passages land near passages on the map and questions don't; it's off in Standard on purpose, because a hypothetical can poison exact lookups. Corpus vocabulary expansion uses words that actually exist in your library instead of a generic thesaurus that would drag in unrelated meanings.

**Dot-connector.** Two things people conflate. Query complexity (trivial, standard, complex, agentic) is about how much work is justified; answer intent is about the shape of the result. A trivial lookup and a trivial summary get different packing. Also: "touchy" is decided here in policy terms but consumed in module 12, where it raises the retrieval-confidence bar from 0.40 to 0.55. And the semantic query cache lives in module 05's territory but is checked here, before embedding, keyed on the normalised question.

**Expert.** `QueryRuntimeCoordinator.resolveContext` is the first call in `queryInternal`: reads `SettingsStore` (summaries, HyDE, rewriting, compression flags), resolves `RAGQualityMode`, computes `AgenticDecision` (`.agentic`, `.forcedAgentic`, `.plannerEscalated`, none), checks the PCC suppression cooldown, builds `AdaptivePipelineConfig`. `QueryProfileService` builds the profile; `QueryComplexityAnalyzer` scores length, conjunctions, comparisons, reasoning markers, entities and intent; `QueryEnhancementService` classifies intent and expands; `QueryRewriterService` rewrites standalone; `HyDEService` generates the hypothetical only when `usesHyDE` is true (false in Standard); `ContainerVocabularyService` reads `documents_vocab`; `QueryRouterService` decides overview versus detail and hands overview to `RAPTORSummaryRouter`; `SpecificationExtractor` pulls the primary entity and descriptive keywords for spec-heavy questions; `GroundedAnswerPolicy` picks deterministic extraction, direct-extraction prompting, constrained synthesis or source-only verification.

**Expert's expert.** The rewrite and HyDE are the two generative steps before retrieval, and they can both mislead: a rewrite that drops a qualifier retrieves the wrong thing confidently. That is why the original user message is never replaced in the conversation, only the effective search string. The planner-escalation path is also the one most likely to surprise a user who chose Standard, because it changes the run from one pass to a loop without a mode change on screen; the diagnostics record it as `plannerEscalated`. And "Subquestion" is the one concept in the whole bank whose name does not appear as an identifier in code; the behaviour exists inside the orchestrator's decomposition under other names.

## Every concept

### Agentic query (Conditional, verified)
- **Idiot:** a question that takes several rounds of looking and thinking.
- **Dot-connector:** discovery, gap assessment, reformulation and synthesis that can't be planned in one shot.
- **Expert:** routed into `AgenticOrchestrator` after the coordinator resolves the plan; module 11.

### Answer intent (Core, verified)
- **Idiot:** what shape of answer you want.
- **Dot-connector:** lookup, table lookup, procedure, comparison, summary, investigation, computation, findings; it steers boosts, expansion, extraction, packing, prompting and verification.
- **Expert:** inferred by `QueryEnhancementService`; represented in `StructuredAnswer`.

### Compare intent (Core, verified)
- **Idiot:** "which is better, A or B?"
- **Dot-connector:** needs balanced evidence for each side and explicit dimensions, not one top passage.
- **Expert:** drives decomposition, source diversity, packing, and the comparison structured type.

### Complex query (Conditional, verified)
- **Idiot:** a big question.
- **Dot-connector:** more candidates and context; may be decomposed or escalated.
- **Expert:** `QueryComplexityAnalyzer`.

### Compute intent (Conditional, verified)
- **Idiot:** "add these up for me."
- **Dot-connector:** retrieve exact operands, keep units, and mark the calculation as derived, not sourced.
- **Expert:** explicit in the structured answer contract.

### Constrained-synthesis prompt mode (Core, verified)
- **Idiot:** write it in your own words, but every sentence must point at a source.
- **Dot-connector:** procedures, comparisons and explanations need composition, still bounded by retrieved context.
- **Expert:** `GroundedAnswerPolicy` after packing, before structured generation.

### Container vocabulary expansion (Conditional, verified)
- **Idiot:** use the library's own words to widen the search.
- **Dot-connector:** corpus-native terms are safer than a generic thesaurus.
- **Expert:** `ContainerVocabularyService` over `documents_vocab`, Step 0 and enhancement.

### Cross-reference query (Conditional, verified)
- **Idiot:** the answer is on the page the first page points to.
- **Dot-connector:** manuals answer with "see page X"; the graph follows the arrow.
- **Expert:** graph or page repair after the first candidates expose the reference; `EvidenceScoringPolicyService`, `GraphIndexService`.

### Decomposed execution (Conditional, verified)
- **Idiot:** split the big question into small ones.
- **Dot-connector:** one embedding for a multi-clause question averages away parts and retrieves half an answer.
- **Expert:** `QueryExecutionPlannerService` plus the orchestrator; sub-answers accumulate before synthesis.

### Descriptive keyword (Core, verified)
- **Idiot:** the word that says which property you want: "capacity," "dosage."
- **Dot-connector:** the entity says which thing; the descriptive keyword says which attribute.
- **Expert:** `SpecificationExtractor` scoring of lexical hits, table keys and extraction candidates.

### Direct execution (Core, verified)
- **Idiot:** one question, one pass.
- **Dot-connector:** minimum latency when decomposition isn't needed.
- **Expert:** the default plan; stays Standard unless mode or policy says otherwise.

### Direct-extraction prompt mode (Conditional, verified)
- **Idiot:** copy the answer out, don't rephrase it.
- **Dot-connector:** for lookup-style questions where rules couldn't decide, minimise paraphrase.
- **Expert:** `GroundedAnswerPolicy` and the prompt compiler for extractive-first intents.

### Entity extraction from query (Core, verified)
- **Idiot:** notice the names and numbers in your question.
- **Dot-connector:** the primary entity decides which record you mean.
- **Expert:** `QueryEnhancementService` and `SpecificationExtractor` before search.

### Findings intent (Conditional, verified)
- **Idiot:** "what did the studies find?"
- **Dot-connector:** research aggregation with attribution, not a topical answer.
- **Expert:** influences planning, source-only verification and structured output.

### Forced agentic execution (Conditional, verified as `.forcedAgentic`)
- **Idiot:** you pressed Go Deeper.
- **Dot-connector:** user-requested extra search and reasoning even after the planner chose Standard.
- **Expert:** overrides at `QueryRuntimeCoordinator` resolution.

### GroundedAnswerPolicy (Core, verified)
- **Idiot:** the rule for how careful the answer has to be.
- **Dot-connector:** deterministic extraction, direct-extraction prompt, constrained synthesis, source-only verification; exact lookups don't get needlessly generated.
- **Expert:** resolved after intent classification, before extraction or generation.

### HyDE (Conditional, verified) and Hypothetical document (Conditional, verified)
- **Idiot:** write a fake answer, search with it, throw it away.
- **Dot-connector:** a passage lands near passages; a short question doesn't. The hypothetical is a probe, never evidence.
- **Expert:** `HyDEService`; `usesHyDE` is false in Standard "to prevent hypothetical hallucinations from poisoning exact lookups."

### Investigate intent (Conditional, verified)
- **Idiot:** "dig into this."
- **Dot-connector:** multiple threads and relationships; raises complexity and may trigger the loop.
- **Expert:** enhancement plus the planner.

### Keyword search intent (Core, verified)
- **Idiot:** you typed a part number.
- **Dot-connector:** exact terms matter; lexical candidates and lower extraction thresholds get more weight.
- **Expert:** `QueryProfileService` and `RetrievalPolicyService`.

### Lookup intent (Core, verified)
- **Idiot:** "what's the torque spec?"
- **Dot-connector:** precision, exact identifiers, structured extraction, low tolerance for synthesis.
- **Expert:** routes preferentially through deterministic or extractive paths.

### Overview query (Conditional, verified)
- **Idiot:** "what's this document about?"
- **Dot-connector:** summary chunks represent whole-document themes better than incidental detail.
- **Expert:** `QueryRouterService` to `RAPTORSummaryRouter`.

### Planner escalation (Conditional, verified as `.plannerEscalated`)
- **Idiot:** the app decided your easy setting wasn't enough.
- **Dot-connector:** complexity, not the mode label, controls the work; the third agentic path.
- **Expert:** resolved by the coordinator before retrieval; recorded in diagnostics.

### Primary entity (Core, verified)
- **Idiot:** the main thing your question is about.
- **Dot-connector:** "1688" beats a similar spec for a similar product; used as an override in extraction.
- **Expert:** `SpecificationExtractor`.

### Procedure intent (Core, verified)
- **Idiot:** "how do I do this, step by step?"
- **Dot-connector:** needs neighbours in order; raises sibling and parent expansion; packs in sequence.
- **Expert:** enhancement plus `RetrievalPolicyService`.

### Query complexity (Core, verified)
- **Idiot:** easy, normal, hard, or "this needs the loop."
- **Dot-connector:** trivial, standard, complex, agentic, from length, conjunctions, comparisons, reasoning markers, entities and intent.
- **Expert:** `QueryComplexityAnalyzer` before adaptive configuration and path selection.

### Query decomposition (Conditional, verified)
- **Idiot:** break it into pieces.
- **Dot-connector:** separate probes reduce averaging and make missing coverage visible.
- **Expert:** in the orchestrator and the planner before iterative retrieval; feeds the FactBank.

### Query expansion (Conditional, verified)
- **Idiot:** add synonyms and related words.
- **Dot-connector:** the document may use a term you don't know or an acronym you spelled out.
- **Expert:** `QueryEnhancementService` after profile and rewrite; extra lexical or semantic searches before fusion.

### Query normalization (Core, verified)
- **Idiot:** tidy up spaces, punctuation and case.
- **Dot-connector:** stable comparison for the cache and the heuristics.
- **Expert:** immediately after submission in `QueryProfileService` and `RAGService`.

### Query rewriting (Conditional, verified)
- **Idiot:** rephrase the question so a search engine likes it.
- **Dot-connector:** conversational phrasing lowers both lexical and dense quality; the rewrite is a generative step and can drop a qualifier.
- **Expert:** `QueryRewriterService` after profiling and conversation context, before embedding.

### Query variation (Conditional, verified)
- **Idiot:** try asking it a different way.
- **Dot-connector:** issued after weak or repetitive retrieval in the loop.
- **Expert:** orchestrator plus `RetrievalPolicyService` after evidence assessment finds a gap.

### QueryExecutionPlan (Core, verified)
- **Idiot:** the decision about what to do.
- **Dot-connector:** direct or decomposed, tools, escalation, response strategy. The profile describes; the plan acts.
- **Expert:** `QueryExecutionPlannerService`, before Standard or agentic execution begins.

### QueryProfile (Core, verified)
- **Idiot:** everything the app figured out about your question.
- **Dot-connector:** one coherent interpretation consumed everywhere instead of independent reclassification.
- **Expert:** `QueryProfileService`; consumed by retrieval, packing, extraction and orchestration policy.

### Response strategy (Core, verified)
- **Idiot:** how the answer will be produced.
- **Dot-connector:** deterministic extraction, constrained synthesis, extractive summarisation, agentic synthesis; falls back when a path lacks confidence.
- **Expert:** `GroundedAnswerPolicy` and the planner.

### Routing classification (Core, verified)
- **Idiot:** direct, cross-topic, overview.
- **Dot-connector:** search architecture responds to the shape of the need, not just the words.
- **Expert:** `QueryRouterService` into `QueryProfile`; consumed by parent expansion and planning.

### Search intent (Core, verified) and Semantic search intent (Core, verified)
- **Idiot:** should the app match words or meaning?
- **Dot-connector:** a model number leans lexical; a paraphrased concept leans dense; hybrid always keeps both.
- **Expert:** `QueryProfileService`; changes weights, routes and thresholds.

### Specification-heavy query (Conditional, verified)
- **Idiot:** you want an exact number or code.
- **Dot-connector:** structured and numeric boosts, stricter unit verification, spec sniper, corrective retrieval.
- **Expert:** `SpecificationExtractor` and `EvidenceScoringPolicyService`.

### Standalone rewrite (Conditional, verified)
- **Idiot:** "it" becomes "the 1688 camera head."
- **Dot-connector:** retrieval can't see the conversation unless it's folded into the query; the original message is kept.
- **Expert:** `QueryRewriterService` with `ConversationMemoryService`.

### State-lookup query (Conditional, verified)
- **Idiot:** "what does the flashing orange light mean?"
- **Dot-connector:** the answer is a pairing of state and meaning; generic similarity picks the wrong row.
- **Expert:** `EvidenceScoringPolicyService` colour/state anchors.

### Subquestion (Conditional, behaviour verified, identifier not)
- **Idiot:** one small piece of a big question.
- **Dot-connector:** coverage and stopping measured per requirement, not by answer length.
- **Expert:** decomposition in `AgenticOrchestrator` and `AgenticPolicyService`; the only bank concept with no matching identifier name.

### Summarize intent (Core, verified)
- **Idiot:** "give me the gist."
- **Dot-connector:** coverage and low redundancy over one strong hit; can route to summary chunks or extractive sentences.
- **Expert:** `QueryRouterService` and `ExtractiveSummarizationService`.

### Table-lookup intent (Core, verified)
- **Idiot:** the answer is in a cell.
- **Dot-connector:** flattened prose finds the right table and the wrong cell; structured lookup keeps the relationship.
- **Expert:** `SpecificationExtractor` structured-row path before generative fallback.

### Touchy query (Core, verified)
- **Idiot:** medical, legal, money, safety, dosage.
- **Dot-connector:** a wrong critical number costs more than a missing adjective; thresholds go up.
- **Expert:** categories medical, legal, financial, safety, dosage, drug, medication; tau rises to 0.55; strict adds regulatory and compliance.

### Trivial query (Core, verified)
- **Idiot:** an easy one.
- **Dot-connector:** smaller candidate set, skip HyDE and iteration; expensive stages on easy lookups add latency for nothing.
- **Expert:** `QueryComplexityAnalyzer` plus `AdaptivePipelineOptimizer` minimum configuration.
