# Buyer Readiness and Evaluation Plan

**Updated**: April 24, 2026
**Scope**: What to show, what to avoid claiming, and how to run a serious evaluation.

## Readiness Verdict

OpenIntelligence is ready for founder-led evaluation conversations. It is not yet ready to be represented as a finished enterprise SDK or regulated healthcare product without additional diligence artifacts.

The right sales motion is:

1. Show the app working on private technical documents.
2. Explain the local-first Apple-native architecture.
3. Run a scoped evaluation on the buyer's documents.
4. Produce an accuracy/privacy/packaging report.
5. Then discuss license, acquisition, or design-partner integration.

## Best Buyer Categories

| Buyer | Why They Care | Best Demo Corpus |
| --- | --- | --- |
| EHR vendors | private chart/policy/document assistance on Apple devices | policy PDFs, care protocols, training docs |
| Medical device sales | offline answers from IFUs/manuals/reimbursement binders | IFUs, product manuals, reimbursement guides |
| Field service | no-reception technical support | service manuals, troubleshooting trees, parts catalogs |
| Legal/compliance | cited source review and local/private handling | policies, contracts, regulations |
| Enterprise knowledge teams | Apple fleet plus private docs | onboarding docs, SOPs, product docs |

## Demo Script

1. Start with a clean library.
2. Import 2-5 buyer-like documents.
3. Show ingestion progress and explain local indexing.
4. Ask an exact-value question.
5. Ask a missing-evidence question and show abstention or gap behavior.
6. Ask a broad summary question.
7. Open citations/source cards.
8. Show library isolation by switching containers.
9. Explain hard limits honestly: 4096-token public FoundationModels session budget, retrieval-first design, no direct PCC server-model claim.

## Evaluation Rubric

| Metric | Target | Why |
| --- | --- | --- |
| Ingestion success | 95%+ on agreed file set | proves format coverage |
| Exact-value accuracy | 90%+ on known-answer questions | critical for manuals/device docs |
| Citation faithfulness | 95%+ cited claims supported by source | trust and diligence |
| Abstention quality | useful gap statement when source missing | safety |
| Container isolation | no cross-library leakage | privacy and workflow |
| Offline behavior | core queries work without developer cloud | product promise |
| Latency | acceptable on buyer target device | deployment viability |

These targets are evaluation goals, not current audited guarantees.

## What To Put In A Buyer Packet

- One-page product summary.
- Architecture diagram.
- Privacy/data-flow note.
- Hard limits note.
- Evaluation plan.
- SDK/API surface summary.
- Sample app instructions.
- Known gaps and next-step roadmap.

## What Not To Put In A Buyer Packet

- Proprietary thresholds and ranking formulas.
- "HIPAA compliant" unless a compliance review has been completed.
- "Clinical decision support" unless regulatory strategy exists.
- "Direct PCC server model" or "65K context" claims.
- "Full GraphRAG" unless implemented and evaluated.
- Consumer pricing as the lead commercial frame.

## Healthcare-Specific Boundary

Safe:

- Document retrieval and cited summarization.
- Policy/manual/IFU lookup.
- Training and sales enablement.
- Administrative workflow assistance.
- Private, local-first handling as a design goal.

Not safe without more work:

- Diagnosis.
- Treatment recommendation.
- Medication instruction generation without source-only controls and clinical review.
- EHR writeback.
- Autonomous patient-facing advice.

## Technical Diligence Gaps

1. Reproducible SDK build from source.
2. Formal eval set and results.
3. Security/privacy architecture note.
4. App Store and SDK privacy manifests reviewed against actual behavior.
5. Performance profile on target devices.
6. Source-code walkthrough of `RAGService`, `DocumentProcessor`, storage, and verification.
7. Clear license/IP inventory for bundled models and packages.

## Suggested 2-Week Pilot

Week 1:

- Select 20-50 documents.
- Define 50 known-answer questions.
- Define 10 missing-evidence questions.
- Ingest on target devices.
- Run exact-value, summary, and comparison scenarios.

Week 2:

- Review failures.
- Tune retrieval/config if appropriate.
- Produce a short report: accuracy, citation faithfulness, failure classes, and integration work.
- Decide between design partner, paid pilot, acquisition discussion, or no-go.
