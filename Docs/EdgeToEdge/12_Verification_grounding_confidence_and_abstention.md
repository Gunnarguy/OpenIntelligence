# Module 12. Verification, grounding, confidence, and abstention

Forty concepts. The nine checks: deterministic gates that decide whether the generated answer is allowed to stand, and what the app says when it isn't.

## The ladder

**Like you're five.** After the writer finishes, a very grumpy checker reads every sentence and asks: is this actually on one of the cards? Does this number match? Is this even about the same thing? Anything that isn't on a card gets crossed out. If too much is crossed out, the phone says "I don't have enough to answer that" instead of guessing.

**Like an idiot.** The model can invent. So after it writes, nine rule-based checks run in a fixed order. A: was the search even confident? B: does every claim cite something? C: do the numbers exist in the sources? D: do the sources contradict each other? E: does the answer's meaning stay close to its evidence? F: are quotes real? G: is the output usable? H: does it answer the whole question? I: is the evidence from the right domain? Failed claims are removed or marked unsupported. If too little survives, the app abstains.

**Like less of an idiot.** The gates work on a structured answer: atomic claims with evidence IDs, which is what makes B mechanically checkable. Some gates are critical: retrieval confidence, numeric sanity and semantic grounding can each force abstention alone. Gate E is the interesting one: it embeds the answer and compares it with its best source chunk; below 0.50 the answer is semantically ungrounded. Confidence is then calibrated from retrieval scores, gate results and session depth, and compared against a mode-dependent bar. Fidelity is a separate number: how well the cited sources support the visible text, shown as Source-Locked, Partially Supported or Not Enough Evidence. Touchy queries (medical, legal, financial, safety, dosage) raise the bars.

**Average Joe.** Why is confidence different from fidelity? Because they answer different questions. Confidence is "how sure are we overall." Fidelity is "does the text on screen match the sources it cites." A confident answer with low fidelity is exactly the failure the gates exist to catch. Why is "not found" checked too? Because saying something isn't in the documents is itself a claim, and it should not be issued after a shallow miss. And why calibrate at all? Because raw scores from different stages live on different scales and are overconfident; the displayed percentage is a heuristic policy, not a proven probability.

**Dot-connector.** Where the gates sit: after a draft answer and before it is accepted, sanitised, or replaced. A source-only fallback can construct an extractive answer from source sentences when generative grounding fails, which is why "abstain" isn't the only alternative to a bad answer. An answer-replacement guard stops a later stage from swapping a strong extractive answer for a weaker generated one. And domain isolation runs on claim-evidence pairs so shared words across medicine, law and engineering can't create false support.

**Expert.** `VerificationGateService`, an actor. Config: `tauNormal` 0.40 (lowered from 0.55 because keyword-heavy queries carry low semantic scores even when BM25 found the right content), `tauTouchy` 0.55, margin `mu` 0.03, semantic grounding 0.50; touchy categories medical, legal, financial, safety, dosage, drug, medication; strict profile 0.65, 0.75, 0.10, 0.60 with regulatory and compliance added. Gate A: top rerank score ≥ tau and top-one minus top-two ≥ mu. Gate B: each claim cites at least one evidence ID; verdicts supported, partial, unsupported. Gate C: numbers must appear in the candidate set, using the full set rather than the packed context because the model may cite a trimmed chunk; numeric-unit checks compare units and qualifiers. Gate D: contradiction sweep including negation indicators. Gate E: response embedding versus best source, plus topical alignment and relative grounding. Gate F: quote spans exist at the attributed location. Gate G: empty, malformed, repetitive, truncated. Gate H: facets versus claims and missing fields. Gate I: `DomainIsolationService`, with a scientific-domain claim check. `ConfidencePolicyService` resolves thresholds and calibration parameters (slope, intercept, penalties, conservative set) per intent, touchy status and mode; `ConfidenceCalibrationService` applies them; mode bars 0.50, 0.60, 0.80. `SourceOnlyAnswerService` builds extractive fallbacks and verifies absence assertions.

**Expert's expert.** The bar for Maximum was 0.98 until every Maximum answer failed verification; it is 0.80. The `tauNormal` history (0.55 to 0.40) is the same lesson from the other side: a bar tuned to one query shape starves another. Gate E is the one gate that costs an inference, and its 0.50 floor is a cosine on the same 384-dimension space the retrieval uses, so a library embedded with a different provider changes what "grounded" means. And the calibration caveat is not decoration: no held-out outcome frequencies have been collected, so an on-screen 80% is a policy output, and saying otherwise in an interview would be the kind of claim this app was built to refuse.

## Every concept

### Absence assertion (Core, verified)
- **Idiot:** "it's not in here" has to be earned.
- **Dot-connector:** not-found is a factual claim; it needs broad retrieval and search checks behind it.
- **Expert:** verified before final abstention wording in `SourceOnlyAnswerService`; `AbsenceAssertionTests`.

### Abstention (Core, verified) and Abstention threshold (Core, verified)
- **Idiot:** the app says no rather than guessing, and the bar for that gets higher in the harder modes.
- **Dot-connector:** a valid no-answer outcome is what stops every retrieval miss from becoming a hallucination.
- **Expert:** before generation, after a critical gate fails, after failed refinement, or at calibration; threshold from `ConfidencePolicyService`, stricter for touchy queries and higher modes.

### Answer replacement guard (Core, verified)
- **Idiot:** don't replace a good answer with a worse one.
- **Dot-connector:** multi-stage pipelines can regress after producing a correct extractive answer.
- **Expert:** evaluated when agentic, source-only or formatting paths propose a replacement; `AnswerReplacementGuardTests`.

### Bibliography penalty (Core, verified)
- **Idiot:** the reference list doesn't count as an answer.
- **Dot-connector:** it contains the query terms and the author names and states none of the findings.
- **Expert:** `ReferenceListDetector` output applied during retrieval or verification; `BibliographyPenaltyTests`.

### Calibration caveat (Core, documented) and Calibration parameters (Core, verified) and Confidence calibration (Core, verified) and Confidence policy (Core, verified)
- **Idiot:** the confidence number is adjusted to be more careful, and it's still not a real probability.
- **Dot-connector:** slope, intercept, penalties and a conservative set, chosen per intent, touchy status and mode; applied after verification; never validated against outcome frequencies.
- **Expert:** `ConfidencePolicyService` picks, `ConfidenceCalibrationService` applies; `Docs/EVALS.md` records the caveat.

### Claim verification verdict (Core, verified), Supported claim (Core, verified), Partially supported claim (Core, verified), Unsupported claim (Core, verified)
- **Idiot:** every sentence gets a grade: yes, partly, no.
- **Dot-connector:** one global confidence hides which assertions are reliable; partial keeps useful content while lowering trust; unsupported must not survive on plausibility.
- **Expert:** produced by Gate B, stored per claim on `StructuredAnswer`; unsupported triggers removal, refinement or abstention.

### Critical gate (Core, verified)
- **Idiot:** some checks can fail the whole answer on their own.
- **Dot-connector:** retrieval confidence, numeric sanity, semantic grounding.
- **Expert:** critical status interpreted when gate results are combined.

### DomainIsolationService (Core, verified) and Gate I: Domain Isolation (Core, verified) and Scientific-domain claim check (Conditional, verified)
- **Idiot:** don't let a car manual "support" a medical claim because both say "pressure."
- **Dot-connector:** classifies claim and evidence domains and blocks incompatible support; research text gets special handling for methods, results and bibliography language.
- **Expert:** runs after evidence mapping, before final verdicts; can remove or abstain on contaminated claims.

### Evidence-first mode (Core, verified) and Source-only verification (Core, verified) and SourceOnlyAnswerService (Core, verified)
- **Idiot:** the sources are the boss; the writer only rearranges them.
- **Dot-connector:** reverses generate-then-find-citations; the answer must be reconstructible from source sentences; when generation fails, an extractive answer beats a guess.
- **Expert:** resolved before generation by `GroundedAnswerPolicy`; `SourceOnlyAnswerService` builds or validates from source sentences and may replace a failed generative answer before abstention.

### Fidelity (Core, verified), Source-Locked (Core, verified), Partially Supported (Core, verified), Not Enough Evidence (Core, verified)
- **Idiot:** the badge: fully backed, partly backed, not enough.
- **Dot-connector:** fidelity is source support specifically, distinct from confidence; the three states expose mixed support instead of one green badge.
- **Expert:** `SourceFidelityStatus` derived after verification.

### Gate A: Retrieval Confidence (Core, verified)
- **Idiot:** was the search good enough to answer from at all?
- **Dot-connector:** no phrasing compensates for an evidence set that never found the answer.
- **Expert:** top rerank ≥ tau (0.40 or 0.55), margin ≥ 0.03; critical.

### Gate B: Evidence Coverage (Core, verified)
- **Idiot:** does every sentence point at a card?
- **Dot-connector:** an answer can cite globally while individual claims float.
- **Expert:** decomposes into claims; assigns verdicts.

### Gate C: Numeric Sanity (Core, verified) and Numeric-unit verification (Core, verified)
- **Idiot:** the numbers, with their units, must be in the sources.
- **Dot-connector:** 5 mg and 5 mL are not the same; "maximum" versus "typical" changes the claim; a digit change inverts meaning.
- **Expert:** checked against the full candidate set; critical.

### Gate D: Contradiction Sweep (Core, verified)
- **Idiot:** do the sources disagree with each other or with the answer?
- **Dot-connector:** a high-similarity source can still contradict another.
- **Expert:** includes negation-indicator checks; contributes to confidence or abstention.

### Gate E: Semantic Grounding (Core, verified)
- **Idiot:** does the answer mean what the sources mean?
- **Dot-connector:** token overlap misses paraphrased fabrication; embedding comparison catches drift.
- **Expert:** response embedding versus best source, floor 0.50, plus topical alignment and relative grounding; critical; one inference.

### Gate F: Quote Faithfulness (Core, verified) and Quote-span verification (Core, verified)
- **Idiot:** if it's in quotes, it had better be there.
- **Dot-connector:** a fake quote with a real citation is worse than an uncited paraphrase.
- **Expert:** spans checked at the attributed location or an accepted normalised match; abbreviation cross-contamination handled.

### Gate G: Generation Quality (Core, verified)
- **Idiot:** is the output even usable?
- **Dot-connector:** grounded but truncated or malformed still fails as a response.
- **Expert:** empty, malformed, repetitive, truncated checks over the structure.

### Gate H: Answer Completeness (Core, verified) and Missing-information list (Core, verified)
- **Idiot:** did it answer the whole question, and what's missing?
- **Dot-connector:** partial coverage presented as complete misleads; naming the gap makes a refusal useful.
- **Expert:** facets versus claims; `missing` populated during extraction, completeness and `StructuredAnswer` construction.

### Precision lock (Conditional, verified)
- **Idiot:** when the exact value is nailed, don't let the writer touch it.
- **Dot-connector:** paraphrase degrades exact values.
- **Expert:** triggered by extractive scoring thresholds before synthesis; `EvidenceScoringPolicyService` and `SourceOnlyAnswerService`.

### Raw confidence (Core, verified)
- **Idiot:** the unadjusted score.
- **Dot-connector:** an internal signal from model output, retrieval scores, claim support or extraction strength; not a probability.
- **Expert:** passed to calibration and UI mapping.

### Reliability mode (Core, verified)
- **Idiot:** the "be careful" setting.
- **Dot-connector:** favours grounded fallback, verification and explicit uncertainty over permissive output.
- **Expert:** read by `QueryRuntimeCoordinator`.

### Verification configuration (Core, verified) and VerificationGateService (Core, verified)
- **Idiot:** the rulebook and the checker.
- **Dot-connector:** one centralised threshold bundle so no answer path uses a contradictory standard; the checker is the final enforcement boundary.
- **Expert:** 0.40 / 0.55 / 0.03 / 0.50 default; strict 0.65 / 0.75 / 0.10 / 0.60; an actor that runs after the draft and before acceptance, sanitisation or replacement.
