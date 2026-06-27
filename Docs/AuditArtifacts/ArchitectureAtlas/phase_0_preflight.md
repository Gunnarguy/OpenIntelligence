# OpenIntelligence Architecture Atlas - Phase 0 Preflight

## Task Information
- **Task Name**: OpenIntelligence Repository Cartographer and Architecture Governance Setup (Phase 0)

## Repository State
- **Current Branch**: `main`
- **Latest Commit Hash**: `bf3a931a7b68552b20f384f0f19bf08fc33138e5`
- **Latest Commit Message**: `chore: Bump iOS version to 4.4 and macOS version to 1.5, preserving 4.3.1 changelog`
- **Working Tree Status**: Dirty

### Exact `git status --porcelain` Output
```text
 M Docs/ARCHITECTURE.md
 M Docs/AppleIntelligenceTransitionPlan.md
 M Docs/BILLING_AND_LIMITS.md
 M Docs/INGESTION_PIPELINE.md
 M Docs/PRIVACY_AND_ROUTING.md
 M Docs/RETRIEVAL_PIPELINE.md
 M README.md
 M WHATS_NEW.md
?? Docs/AuditArtifacts/
?? Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
?? Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md
?? Docs/FULL_REPO_EVIDENCE_THREADS_ARCHITECTURE_AUDIT.md
?? Docs/FULL_REPO_EVIDENCE_THREADS_AUDIT_VERIFICATION.md
?? Docs/FULL_REPO_LINE_BY_LINE_AUDIT.md
?? Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT.md
?? Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT_V2.md
```

## Security & Governance Guardrails

### Allowed Output Paths
- `Docs/AuditArtifacts/ArchitectureAtlas/`
- `Docs/AuditArtifacts/DocumentationGovernance/`
- `Docs/AgentPlaybooks/`
- `Docs/`
- `AGENTS.md` (in appropriate later phase)
- `GEMINI.md` (in appropriate later phase)

### Forbidden Paths
- Any `.swift` file
- Any test source file
- Any StoreKit configuration file
- Any routing/PCC implementation file
- Any sync implementation file
- Any billing/entitlement implementation file
- Any App Intent implementation file
- Any Xcode project or capability file
- `ChatMessage.swift`
- `ChatScreen.swift`
- `EvidenceThread.swift`
- `EvidenceThreadStore.swift`

### Explicit Code Modification Statements
- **CRITICAL RULE**: NO APP SOURCE MAY BE MODIFIED during this governance mapping workflow.
- **CRITICAL RULE**: EVIDENCE THREADS MUST NOT BE IMPLEMENTED during this architecture/governance workflow.

## Operational Playbook

### Phase Workflow
- Complete **only** the requested phase.
- Write that phase's artifacts.
- Stop and wait for the exact string command `NEXT PHASE: Phase X` to proceed. Do not automatically advance.
- Halt and revert any forbidden file modification immediately, resulting in a phase failure.

### Recommended Sub-Agent Plan
1. **Inventory Agent**: Maps files, docs, scripts, and configs.
2. **Swift Entity Agent**: Catalogs services, views, view models, models, and functions.
3. **Storage/Sync Agent**: Analyzes persistence, LocalCache, baseDir, iCloud, and WorkspaceSyncService.
4. **Routing/PCC Agent**: Analyzes Apple Foundation Models, PCC, consent, token limits, and App Intent risk.
5. **Billing/App Intents Agent**: Analyzes StoreKit, entitlements, quotas, shortcuts, and background intents.
6. **Documentation Agent**: Updates README, architecture docs, Apple docs, research docs, and audit docs.
7. **Adversarial Reviewer Agent**: Challenges conclusions to identify missed files/components and disprove assumptions.

### Recommended Model-Use Plan
- **Gemini 3.5 Flash**: Use for broad extraction, inventories, repetitive scans, CSV creation, and first-pass documentation classification.
- **Gemini 3.1 Pro (High Reasoning)**: Use for architecture synthesis, risk decisions, contradiction resolution, canonical decisions, and final review. (Default for all tasks if sub-agents cannot be spawned).

### Exact Commands Run
```bash
git status --porcelain
git branch --show-current
git log -1 --format="%H"
git log -1 --format="%B"
```
