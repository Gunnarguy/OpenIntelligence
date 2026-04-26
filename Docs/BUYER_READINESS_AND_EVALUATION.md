# Buyer Readiness and Evaluation

**Updated**: April 25, 2026
**Scope**: What to show, what not to claim, and how to run a serious technical evaluation from the current repo.

## Current Status

OpenIntelligence is ready for founder-led technical evaluation, code walkthroughs, and buyer diligence.

It is not ready to be represented as:

- a finished enterprise SDK
- a regulated-use document QA system
- a validated medical, legal, safety, or IFU workflow engine

The right motion today is:

1. Show the engine behavior on real documents.
2. Explain what is reusable and what is still app-specific.
3. Walk through the codebase and benchmark harness.
4. Run a scoped evaluation on buyer documents.
5. Only then discuss license, handoff, acquisition, or design-partner work.

## What A Serious Buyer Should Understand Up Front

- There is real engine code in the repo, not just a thin demo app.
- The SDK facade exists, but it is an evaluation-stage boundary around app-coupled internals.
- The benchmark harness is real and useful, but early.
- The output packet under `output/OpenIntelligence-SDK-Package/` is evaluation collateral, not proof of a finished enterprise packaging pipeline.
- Consumer app monetization is separate from engine value.

## Best-Fit Buyers Right Now

Best fits:

- teams exploring private document QA on Apple devices
- field-service, manuals, and support-document workflows
- enterprise knowledge or compliance teams that want local-first behavior
- buyers interested in licensing, acqui-hiring, or codebase transfer rather than turnkey SDK procurement

Possible fits only with careful caveats:

- regulated-adjacent teams evaluating manuals, policies, training material, or internal reference documents

Poor fits:

- teams that need a finished self-serve SDK now
- teams that need a cross-platform cloud API instead of embedded Apple-native logic
- teams that need audited accuracy, compliance, or decision-support readiness

## What To Show In A Real Evaluation

Show these in order:

1. A short live ingest and query demo against clear source documents.
2. The engine inventory and claims guardrails in `EngineSale/`.
3. The storage and retrieval architecture at a practical level.
4. The benchmark harness and a sample run artifact.
5. The staged evaluation packet in `output/OpenIntelligence-SDK-Package/`.

Be explicit that the live app demo is showing engine behavior through the current app UI. It is not proof that the consumer app UI is the commercial SDK product.

## Recommended Evaluation Rubric

Treat these as evaluation goals, not current guarantees:

| Metric                   | Why it matters                          | Current interpretation                             |
| ------------------------ | --------------------------------------- | -------------------------------------------------- |
| Ingestion success        | Proves format coverage                  | Must be measured on the buyer corpus               |
| Exact-value accuracy     | Critical for manuals and spec sheets    | Early strength, but not audited                    |
| Citation/source support  | Helps users inspect evidence            | Useful, but not a guarantee of correctness         |
| Abstention quality       | Prevents bluffing when evidence is weak | Important current behavior to test                 |
| Container isolation      | Prevents bleed between document sets    | Implemented in storage design, should be validated |
| Local-first behavior     | Central to the engine story             | Validate on target hardware and execution mode     |
| Latency on buyer devices | Determines deployment viability         | Must be measured on real target devices            |

## What To Send First

For an early serious buyer, send:

- `EngineSale/ENGINE_PITCH.md`
- `EngineSale/ENGINE_INVENTORY.md`
- `EngineSale/KNOWN_LIMITATIONS.md`
- `EngineSale/CLAIMS_GUARDRAILS.md`

Then, if the buyer is still serious:

- the staged evaluation packet in `output/OpenIntelligence-SDK-Package/`
- the partner packet in `output/OpenIntelligence-Partner-Packet/`
- a guided benchmark or live demo plan

## What Not To Claim

Do not claim any of the following from the current repo state:

- finished enterprise SDK
- HIPAA compliance
- clinical decision support
- diagnostic assistance
- legal or safety readiness
- reliable IFU/procedural decision support
- full GraphRAG
- direct PCC server-model access
- Apple Foundation Models embeddings
- benchmarked production-grade accuracy

## Regulated-Use Boundary

Safe current framing:

- internal document exploration
- policy/manual lookup
- training and support workflows
- source review and evidence inspection
- local-first technical evaluation

Unsafe current framing:

- diagnosis
- treatment recommendations
- medication or patient instruction generation
- autonomous legal or safety guidance
- IFU or procedural truth engine

## Suggested Pilot Shape

Week 1:

- select a narrow document set
- define known-answer questions
- define missing-evidence questions
- run ingestion and query tests on real target hardware

Week 2:

- review failure classes
- inspect source-support mismatches
- measure latency and abstention behavior
- decide whether this is a design-partner fit, source-code handoff fit, or no-go

## Readiness Verdict

This repo is ready to support serious technical evaluation and buyer diligence.

It is not ready to be sold as a finished enterprise SDK or a regulated-use answer system.
