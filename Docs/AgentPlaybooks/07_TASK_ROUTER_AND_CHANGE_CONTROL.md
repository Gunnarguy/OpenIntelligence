# Task Router and Change Control

This document defines the strict governance rules for any AI agent interacting with the OpenIntelligence repository.
All agents MUST read this document before executing any code changes.

## Task Classes

| Class | Definition | Allowed File Scopes | Required Preflight |
|-------|------------|---------------------|--------------------|
| **docs_only** | Modifying Markdown or text files. | `Docs/**`, `README.md`, `PRIVACY.md` | None |
| **implementation_local** | Adding a new feature that does not touch legacy systems. | Isolated new files only. | Architecture Atlas review. |
| **implementation_high_risk** | Touching `ChatMessage`, Sync, Billing, or Routing. | Target systems + tests. | Impact Matrix review. |
| **refactor** | Modifying existing architecture without adding features. | Isolated to refactor target. | Architecture Atlas review. |
| **bugfix** | Fixing an existing defect. | Target system + tests. | Impact Matrix review. |
| **release** | Preparing a release. | StoreKit, AppStore docs. | Walkthrough verification. |
| **roadmap_update** | Updating Notion or high-level plans. | Notion API. | Verification report. |
| **audit_verification** | Running post-implementation checks. | Read-only. | None. |

## Prohibited File Scopes
- Unless explicitly authorized by the user, agents are **PROHIBITED** from modifying:
  - `project.pbxproj`
  - `.storekit` files
  - `Entitlements`
  - Core Legacy Systems (Chat, Sync, Billing, Routing) during a local implementation.

## Required Stop Conditions
An agent MUST stop execution and request explicit user approval:
1. After generating an Implementation Plan, before making ANY source edits.
2. The user MUST reply with exactly: `PROCEED: IMPLEMENT` to authorize source edits.
3. If forbidden files must be modified to achieve the task.

## Auto-Proceed Prohibition
**AGENTS MAY NOT AUTO-PROCEED.** If a plan is generated, the agent MUST halt, present the plan, and wait for the `PROCEED: IMPLEMENT` command. No exceptions.
