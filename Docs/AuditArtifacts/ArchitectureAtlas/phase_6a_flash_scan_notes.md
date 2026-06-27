# Phase 6A Flash Scan Notes

## Audit Overview
A comprehensive documentation scan was executed using a high-velocity reasoning model to cross-reference the repository's markdown guides against verified code pathways and storage configurations. This draft scan focuses on discovering structural, technical, and stylistic deviations from established repository patterns and developer guidelines.

---

## Detailed Pronoun & Style Violations
In accordance with the communication rules, all documentation, changelogs, and release notes must use objective, passive, or purely factual language, avoiding personal pronouns ("I", "we", "our", "us") and informal greetings. The following exact violations were identified during the scan:

1. **[Docs/ARCHITECTURE.md:L9](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/ARCHITECTURE.md#L9)**:
   - *Text*: `"I designed the codebase to expose the entire RAG pipeline..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
2. **[Docs/PRIVACY_AND_ROUTING.md:L13](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/PRIVACY_AND_ROUTING.md#L13)**:
   - *Text*: `"I built OpenIntelligence as a local-first application."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
3. **[Docs/PRIVACY_AND_ROUTING.md:L44](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/PRIVACY_AND_ROUTING.md#L44)**:
   - *Text*: `"I built local user consent dialogs..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
4. **[Docs/RETRIEVAL_PIPELINE.md:L10](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/RETRIEVAL_PIPELINE.md#L10)**:
   - *Text*: `"I built this app to bias responses toward groundedness..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
5. **[Docs/RETRIEVAL_PIPELINE.md:L55](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/RETRIEVAL_PIPELINE.md#L55)**:
   - *Text*: `"I designed the app so that a query is answered..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
6. **[Docs/RETRIEVAL_PIPELINE.md:L60](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/RETRIEVAL_PIPELINE.md#L60)**:
   - *Text*: `"I included diagnostic and telemetry surfaces..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
7. **[Docs/BILLING_AND_LIMITS.md:L12](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/BILLING_AND_LIMITS.md#L12)**:
   - *Text*: `"I define these StoreKit product IDs centrally..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
8. **[Docs/BILLING_AND_LIMITS.md:L47](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/BILLING_AND_LIMITS.md#L47)**:
   - *Text*: `"I implemented a sticky paid-history protection state..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
9. **[Docs/INGESTION_PIPELINE.md:L36](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/INGESTION_PIPELINE.md#L36)**:
   - *Text*: `"I use StructuredDocumentParser.swift to resolve..."`
   - *Rule Violation*: First-person singular pronoun `"I"`.
10. **[CHANGELOG.md:L99](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/CHANGELOG.md#L99)**:
    - *Text*: `"Shoutout to Tim for asking for this."`
    - *Rule Violation*: Informal personal greeting violating objective developer tone.

---

## Detailed Notes on Structural & Technical Contradictions

### CloudKit Sync
- **Claim**: Multiple legacy documentation files state that workspace sync uses CloudKit.
- **Reality**: `WorkspaceSyncService.swift` performs sweeps across local files in `baseDir` and synchronizes them to an iCloud Drive Ubiquity container via metadata queries and file coordination.
- **Resolution Plan**: Rewrite references to sync to describe iCloud Drive file-based syncing. Document how `localOnlyEntryNames` filters out `LocalCache/` from syncing.

### Database Isolation
- **Claim**: Documentation claims separate SQLite database files per library are maintained.
- **Reality**: The codebase establishes a single local SQLite database file with shared tables, isolates queries by the `container_id` column, and isolates vector stores separately per container.
- **Resolution Plan**: Correct all component files to clarify that SQLite relational data is column-isolated, while dense vector files are directory-isolated.

### StoreKit & Keychain
- **Claim**: Product ledger entitlements and quotas are stored securely in `KeychainStorage.swift`.
- **Reality**: Entitlement limits are saved in `UserDefaults` via `@AppStorage` property wrappers. `KeychainStorage` acts as a local-only wrapper for custom API keys.
- **Resolution Plan**: Clarify that entitlement limits are not secured in Keychain. Document `EntitlementStore.swift` UserDefaults keys and fallback/grandfathering mechanics.

### PCC Remote Enclave Execution
- **Claim**: PCC escalation executes queries inside secure remote cloud enclaves.
- **Reality**: PCC execution is simulated locally on the 3B Core model session (`SystemLanguageModel.default`) using a compatibility wrapper in `EngineSDKCompatibility.swift`.
- **Resolution Plan**: Clearly annotate all PCC routing as simulated local-first behavior.

---

## Unknowns Identified
- **StoreKit Receipt Validation Fallback Details**: While local validation check failures are redirected to grandfathered states, the exact receipt verification recovery behavior when StoreKit is completely unavailable is inferred but lacks validation test data.
- **SQLite Performance under Peak Concurrency**: Shared-table database access behavior has not been tested under concurrent indexing tasks across multiple container updates.

---

> **Status Statement**: This Phase 6A documentation scan is draft-only and requires Gemini 3.1 Pro review for final reconciliation.
