# Repository Operating System Setup

**Created At:** 2026-06-27

This document summarizes the installation of the repository operating system layer, which provides a durable task-routing and change-impact control mechanism for Antigravity/Gemini agents.

## Files Created
1. `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md`: Defines task classes, preflight checks, and the rule against auto-proceeding.
2. `Docs/AuditArtifacts/Governance/change_impact_matrix.csv`: A matrix defining allowed scopes, required docs, and testing policies for major subsystems.
3. `Docs/AuditArtifacts/Governance/notion_roadmap_sync_protocol.md`: Rules for when and how to update Notion as a progress mirror, not the source of truth.
4. `Docs/AuditArtifacts/Governance/post_implementation_verification_template.md`: A reusable template for verifying future implementation phases.
5. `Docs/AuditArtifacts/Governance/repository_operating_system_setup.md`: This summary file.

## Files Modified
1. `AGENTS.md`: Added directives requiring agents to read the Task Router playbook before implementations and prohibiting auto-proceed behaviors.
2. `Docs/AgentPlaybooks/README.md`: Registered the new playbook.

## How Future Agents Should Use the Task Router
1. Identify the requested task.
2. Read `07_TASK_ROUTER_AND_CHANGE_CONTROL.md` and classify the task.
3. Consult `change_impact_matrix.csv` to map the target files to risk levels and required verifications.
4. Generate an implementation plan and **stop**.
5. Await the explicit `PROCEED: IMPLEMENT` approval from the user before running any source code edits.

## How Notion Update Decisions Are Made
Notion is updated strictly according to the triggers in `notion_roadmap_sync_protocol.md`. It requires a formally opened phase gate, completed implementation, verified post-implementation check, or explicit release/deferral. Notion updates must always reference repository artifacts as evidence.

## Remaining Limitations
- Local test execution remains constrained by the active developer directory (Command Line Tools vs. Xcode app). Future verifications may still require manual build checks or CI execution until the local environment is reconfigured.
