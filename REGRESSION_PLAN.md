# Regression Plan

This is the minimum regression plan for the current answer-engine logic.
Its purpose is to prove that the new routing and verification logic improves answer quality without over-constraining the app.

## Goal

Validate the three core answer lanes:

1. Direct extraction
2. Constrained synthesis
3. Grounded abstention

The plan should be run before the next release and before any buyer-facing demo that depends on engine trust behavior.

## Test Lanes

### Lane 1: Exact Extraction

Use questions where the answer should be copied or tightly paraphrased from source.

Examples:
- timing
- dose
- route of administration
- sample size
- p-value
- exact count
- exact capacity/specification

Expected behavior:
- deterministic extraction path engages
- answer is short and direct
- no recursive reasoning needed
- no unrelated competing values are surfaced unless truly ambiguous
- answer cites the exact supporting source

Failure signals:
- answer includes nearby but irrelevant values
- answer is marked ambiguous when one clear answer exists
- answer adds interpretation not requested
- answer lacks precise source support

### Lane 2: Procedure / Manual QA

Use operational or instructional documents.

Examples:
- what does this button do
- how do I replace the filter
- what happens if I open the valve early
- what is the cleaning procedure

Expected behavior:
- no scientific-domain logic should interfere
- answer stays grounded in the manual
- procedural questions preserve ordered steps when present
- behavioral questions answer the outcome first instead of forcing a long list

Failure signals:
- over-abstention
- scientific-domain warnings on normal manuals
- answer over-summarizes instead of preserving procedure
- answer is chopped down too aggressively by claim verification

### Lane 3: Compare / Investigate / Findings

Use queries that require integration across sections or documents.

Examples:
- compare option A vs option B
- what factors affect failure rate
- what did the study find about X
- summarize the main findings

Expected behavior:
- synthesis lane engages
- answer integrates multiple excerpts
- answer stays narrower than generic chat
- citations remain attached to factual claims

Failure signals:
- answer becomes extractive and incomplete when synthesis is needed
- answer is too terse to cover both sides of a comparison
- document-summary or multi-hop logic degrades specificity
- source-only verification removes too much of a good synthesis answer

### Lane 4: Unsupported Question / Abstention

Ask questions the document set does not support.

Examples:
- ask about a topic not present in the documents
- ask for a value not contained in the retrieved evidence
- ask a cross-domain question against thin evidence

Expected behavior:
- app refuses or clearly states that support is insufficient
- unsupported claims are dropped
- answer does not bluff

Failure signals:
- plausible but unsupported answer
- fake citations
- weak answer presented with unjustified confidence

### Lane 5: Citation Integrity

Use any lane above, but inspect citation behavior directly.

Expected behavior:
- every factual answer is source-backed
- citations map to real retrieved evidence
- no out-of-range source indices
- quote snippets actually match presented evidence

Failure signals:
- missing citations
- fake or malformed `[S#]` references
- evidence tray preview does not match the quote used for support

### Lane 6: Scientific Literature Strict Mode

Use experimental literature where mixed-domain contamination is a real risk.

Examples:
- dose/timing/route questions in animal studies
- questions where in vitro and in vivo values coexist
- control-group questions

Expected behavior:
- strict scientific-domain behavior activates only when appropriate
- cross-domain contamination is rejected
- exact experimental values win over nearby unrelated values

Failure signals:
- in vitro values support in vivo claims
- unrelated time expressions cause false ambiguity
- scientific-domain logic remains active on non-scientific documents

## Minimum Scenario Count

Recommended minimum before release:

- 5 exact extraction scenarios
- 4 procedure/manual scenarios
- 4 synthesis scenarios
- 3 unsupported-question scenarios
- 3 citation-integrity inspections
- 4 scientific-literature strict-mode scenarios

Minimum total: 23 scenarios

## What To Record For Each Scenario

1. Document set used
2. User question
3. Expected lane
4. Expected disposition:
   direct answer / synthesized answer / abstain
5. Expected key facts or refusal reason
6. Whether citations are required
7. Actual result
8. Pass / fail
9. Notes on weird behavior

## Release Gate

The next update should not rely on "it feels better."

The release gate should be:

1. No false-supported answers on the canonical extraction set
2. No fake citations on the citation-integrity set
3. Procedure/manual questions remain usable after the new verifier logic
4. Unsupported questions abstain cleanly
5. Scientific strict mode improves literature QA without degrading ordinary document QA

## Diligence Use

This plan is also useful for buyer conversations.

It demonstrates that the engine is not just a bundle of heuristics.
It has a defined validation surface:
- exact extraction
- synthesis
- abstention
- citation integrity
- domain control

