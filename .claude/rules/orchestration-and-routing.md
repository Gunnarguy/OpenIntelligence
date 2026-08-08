---
paths:
  - "OpenIntelligence/Services/AIPlatform/**"
  - "OpenIntelligence/Services/LLM/**"
  - "OpenIntelligence/Services/RAG/Orchestration/**"
  - "OpenIntelligence/Services/Agentic/**"
---

# Orchestration, model routing, and agentic execution

This is the highest-risk area in the repository. Where a query executes is the app's central
privacy promise to its users.

**Hard-boundary files live here.** `FoundationModelRoutePolicy.swift`,
`FoundationModelSessionFactory.swift`, and `RAGAppIntents.swift` need the user to name the file in
their approval. `EngineSDKCompatibility.swift` too. See `.claude/rules/hard-boundaries.md`.

**Same turn as the code change:**
- `Docs/PRIVACY_AND_ROUTING.md` and Atlas §10 for anything touching routing or consent.
- Atlas service map for orchestration and agentic changes.
- `CHANGELOG.md` under `[Unreleased]`, tagged `**[Orchestration]**` or `**[Shortcuts]**`.

**Verification:** every use of `PrivateCloudComputeLanguageModel` must stay gated behind
`EntitlementChecker`. Confirm with a repo-wide grep, then `bash scripts/build_simulator_smoke.sh`
and the full test suite.

## Known traps in this code

- **Estimating against the wrong target.** `estimateTokens(..., isAppleFMOnDevice:)` selects the
  chars-per-token ratio. Asking "does this fit on device" requires the on-device ratio regardless of
  where the query is allowed to run. Deriving the estimate from the assumed destination made the
  escalation check least likely to fire exactly when escalation was possible.
- **Budgets that are not the budget.** `sessionProgress` used a hardcoded `log(50.0)` denominator,
  correct for Maximum's 50 sessions and wrong for Deep Think's 8, so Deep Think could never reach
  its early-exit gate. Pass the actual session budget.
- **Registered is not declared.** `FoundationModelToolRegistry.createTools` is the only place tools
  reach a `LanguageModelSession`. A tool struct declared in that file and not returned by
  `createTools` does not run. Count the registered set, not the declared set.
- This path has no test coverage. Build-verified and suite-verified is not device-verified, and
  saying so is part of the change.
