# Notion Roadmap Sync Protocol

Notion is a planning and progress mirror for OpenIntelligence. **It is NOT the source of truth for architecture.** The source of truth is always the Git repository and the Markdown files in `Docs/`.

## When to Update Notion
Notion MUST ONLY be updated in the following events:
1. A new feature idea is captured (Status: Backlog).
2. A Governance phase gate says READY (Status: Planned).
3. Implementation starts (Status: Implementation In Progress).
4. Implementation completes (Status: Verification Required).
5. Verification completes (Status: Verified).
6. A Commit is created and a release is shipped (Status: Shipped).
7. A feature is explicitly deferred (Status: Deferred) or blocked (Status: Blocked).

## When NOT to Update Notion
- Do NOT update Notion for minor local wording changes, typos, or README updates.
- Do NOT update Notion during exploratory audits where no final decision is made.

## Required Notion Properties
When updating a Notion roadmap entry, the following properties MUST be set:
- **Feature:** Human-readable task/feature title.
- **Repo:** Target repository (e.g., OpenIntelligence).
- **Phase:** The current governance phase (e.g., Phase 1A, Governance).
- **Status:** Backlog, Planned, Implementation In Progress, Verification Required, Verified, Blocked, Shipped, Deferred.
- **Gate State:** READY, PARTIAL, NO-GO.
- **Risk Class:** Low, Medium, High, Critical.
- **Last Verified SHA:** The Git commit hash of the verified state.
- **Source of Truth Doc:** Link/path to the canonical architecture document.
- **Implementation Artifact:** Link/path to the walkthrough.
- **Verification Artifact:** Link/path to the verification report.
- **Docs Updated:** Checkbox.
- **Tests Passing:** Checkbox.
- **Next Action:** Exact next move.
- **Blockers:** Current blockers, if any.
- **Owner:** The agent or human responsible.
- **Last Synced:** Roadmap sync timestamp.
