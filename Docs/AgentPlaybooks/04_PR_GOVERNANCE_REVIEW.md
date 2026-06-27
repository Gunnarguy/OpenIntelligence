# PR Governance Review

This playbook outlines the mandatory checks an agent must perform when reviewing a Pull Request before it can be merged.

## Pre-Merge Checklist
- **Forbidden File Changes**: Did the PR modify files it shouldn't have (e.g., modifying StoreKit configs during a UI task)?
- **Missing Doc Updates**: Did the PR alter a major subsystem without updating the corresponding canonical documentation?
- **Architecture Drift**: Does the PR introduce new patterns that violate the established `OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`?
- **Unverified Claims**: Does the PR description or associated documentation contain claims that lack `evidence_level` backing?
- **Stale Canonical Docs**: Are there canonical docs that are now out of sync with the PR?
- **Missing Tests/QA**: Are critical new pathways lacking unit test coverage?
- **High-Risk Integrations**: Scrutinize any changes to StoreKit, iCloud Sync, PCC/Routing, or App Intents. Ensure they handle edge cases (e.g., deadlocks, lack of consent).
- **Destructive Migration Risks**: Does the PR introduce schema changes to SQLite/FTS or Vectura without a safe migration path?
