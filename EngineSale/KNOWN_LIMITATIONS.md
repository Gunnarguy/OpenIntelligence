# Known Limitations

## Current Status

This repo contains real engine code, but it is still a prototype-stage system with meaningful limitations.

## Answer Quality

- Inconsistent answer quality on difficult technical or procedural documents.
- Table, spec-sheet, and procedural fidelity are still weak in some cases.
- Retrieval can miss the right page or chunk even when the answer exists in the corpus.
- Context packing can still drop important evidence before generation.
- Source-support mismatch is possible, especially on broad or technical questions.

## Verification And Citations

- Citations and source review do not guarantee correctness.
- Verification gates reduce risk, but do not turn the system into a guaranteed-accurate QA engine.
- An answer can still look supported while being incomplete, imprecise, or wrong.

## Safety And Suitability

- Not suitable as-is for IFU, medical, legal, safety, clinical, or procedural decision-making.
- Not suitable as-is for diagnosis, treatment, patient guidance, legal advice, or safety-critical instruction.
- No production-grade accuracy claims should be made from the current repo state.

## Benchmarking And Evaluation

- The benchmark harness is early.
- There is no formal third-party evaluation.
- There is no formal compliance, security, or HIPAA review.
- The benchmark tooling is useful for internal regression and buyer pilots, not as audited proof.

## Packaging And Boundary

- The SDK boundary is still evaluation-stage.
- App and engine are still coupled.
- The staged evaluation packet is not the same thing as a finished enterprise SDK.

## Claims Boundary

- Do not claim guaranteed accuracy.
- Do not claim HIPAA compliance.
- Do not claim clinical decision support.
- Do not claim legal or safety readiness.
- Do not claim IFU reliability.
