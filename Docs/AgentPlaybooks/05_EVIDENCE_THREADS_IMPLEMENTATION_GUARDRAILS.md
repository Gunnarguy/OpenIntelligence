# Evidence Threads Implementation Guardrails

This playbook defines the specific boundaries and constraints for implementing the "Evidence Threads" feature.

## Strict Implementation Constraints
- **NO Implementation without Approval**: Do not write Swift code until the Architecture Atlas and Canonical Docs are fully reviewed and approved by the user.
- **Phase 1A Storage**: Must use local on-device store only.
- **Storage Location**: Prefer isolated local files under `LocalCache/EvidenceThreads/` if supported by the atlas. Do NOT use the base `Documents/` directory for thread storage.
- **NO iCloud Sync**: Sync is strictly forbidden in Phase 1.
- **NO StoreKit Integration**: Billing/Entitlement changes are forbidden in Phase 1.
- **NO App Intents**: Siri shortcut integration is forbidden in Phase 1.
- **NO PCC/Routing Changes**: Modifications to the `FoundationModelRoutePolicy` or privacy boundaries are forbidden in Phase 1.
- **NO Destructive Migrations**: Do not drop or wipe existing SQLite tables or Vectura indices to support Evidence Threads.
- **NO Streaming-Token Disk Writes**: Do not write individual LLM tokens to disk during generation to avoid I/O thrashing.
- **ChatMessage Immutability**: Do not modify the existing `ChatMessage` model unless strictly proven necessary and approved by the user.
