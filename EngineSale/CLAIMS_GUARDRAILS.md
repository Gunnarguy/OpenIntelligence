# Claims Guardrails

## Safe To Say

- live iOS app and codebase exist
- Apple-native document-intelligence prototype exists
- local-first document indexing exists
- full-text and vector retrieval exist
- source review exists
- benchmark harness exists
- early App Store and IAP signal exists
- this repo is a substantial prototype and codebase head start

## Say Only With Caveats

- offline or private behavior: say local-first, not universally offline for every execution path
- Apple Foundation Models usage: say where available through the public Apple path, not as a custom server-model capability
- SDK or evaluation package: say staged evaluation artifact, not finished enterprise SDK
- benchmark results: say internal or pilot evaluation results, not audited accuracy proof
- medical-device-adjacent workflows: only as prototype evaluation on documents, not operational truth
- local AI: say local indexing and local-first behavior, not universal no-network execution for every mode
- citations: say source review aid, not proof of correctness
- verification: say risk-reduction layer, not guarantee layer

## Do Not Claim

- guaranteed accuracy
- HIPAA compliance
- clinical decision support
- diagnostic assistance
- medical, legal, safety, or IFU readiness
- finished enterprise SDK
- full GraphRAG
- direct PCC server-model access
- 65K Apple Foundation Models context for third-party apps
- that citations prove correctness
- that the app replaces expert review
