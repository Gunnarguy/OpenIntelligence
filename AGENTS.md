# Universal Agent Instructions

This is the top-level universal instruction file for any autonomous agent operating in the OpenIntelligence repository.

**CRITICAL DIRECTIVES FOR ALL AGENTS:**

1. Read `GEMINI.md` if running in Gemini/Antigravity.
2. Read `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` before any audit, docs, or implementation work.
3. Read `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` if it exists.
4. Read `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` if it exists.
5. Read the specific playbook for the task at hand (found in `Docs/AgentPlaybooks/`).
6. **Never** modify app source code during audit/governance phases.
7. **Never** run destructive git commands without explicit user approval.
8. **Never** present conceptual relationships as exact code linkages.
9. **Always** include `evidence_level` and `confidence` for architecture/doc claims.
10. **Stop** after the requested phase and wait for explicit verification and instructions before proceeding.
11. **Phase 1A Implementation:** If performing Phase 1A Evidence Threads implementation, you must strictly follow `Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md`.
