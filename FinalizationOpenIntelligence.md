Expert Role

Repository operating-system architect, implementation-gate auditor, and documentation/roadmap governance designer.

Objective

Evaluate the Phase 1A result you pasted, identify any remaining risk before committing it, and give you the missing governance layer that makes Antigravity/Gemini reliably know:

* what files to inspect
* what files it may change
* what files it must not change
* what docs must be updated
* when Notion must be updated
* when to stop and ask for approval

Reasoning

Based on the pasted output, Phase 1A looks directionally correct, but I would not call it complete-complete until you run a post-implementation verification gate.

The good signs:

Signal	Assessment
It read the finalized governance docs first	Good
It produced an implementation plan	Good
It claims it only added isolated Evidence Thread files	Good
It claims it avoided ChatMessage, sync, SQLite, PCC, App Intents, billing	Good
It generated a walkthrough artifact	Good
It ran a standalone automated test script	Good, but insufficient alone

The one yellow flag:

Concern	Why it matters
“Auto-proceeded with Implementation Plan”	Your governance model was supposed to require explicit human approval before source edits. If Antigravity auto-clicked or auto-continued after plan generation, that is a process-control gap. It may be acceptable if you had auto-proceed enabled intentionally, but it violates the spirit of the gate.

So the implementation may be technically fine, but your control system still needs one more layer: a deterministic repository operating protocol.

Answer

1. How this looks

Verdict: likely good, but not yet commit-safe until verified.

I would classify the Phase 1A state as:

Area	Status	Confidence
Governance sequence	Strong	0.90
Phase 1A scope discipline	Looks strong	0.82
Source isolation	Claimed, must verify	0.75
Test validity	Partial	0.65
Commit readiness	Not yet	0.70
Need for post-implementation audit	Yes	0.95

The implementation sounds like it did the right thing: add an isolated EvidenceThread model and local JSON store without touching legacy chat, sync, SQLite, PCC, billing, or App Intents.

But the phrase “standalone test script” is not enough. Before committing, you need to verify:

1. The app still compiles.
2. The new files are included in the intended target.
3. The tests are actually integrated or at least reproducible.
4. No forbidden files changed.
5. The documentation gate reflects implementation completion.

⸻

2. Immediate post-implementation checks

Run these before committing.

Check changed files

git status --porcelain
git diff --name-only

Expected changed files should be limited to something like:

OpenIntelligence/Core/Models/EvidenceThread.swift
OpenIntelligence/Services/Storage/EvidenceThreadStore.swift
OpenIntelligenceTests/...EvidenceThread...Tests.swift
Docs/AuditArtifacts/Implementation/...
Docs/AuditArtifacts/FinalReview/...

If any of these changed, stop and review manually:

OpenIntelligence/Core/Models/ChatMessage.swift
OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift
OpenIntelligence/Services/Storage/SQLiteFullTextService.swift
OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift
OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift
OpenIntelligence/Features/Chat/...
OpenIntelligence/Features/AppIntents/...
OpenIntelligence/Services/Billing/...
*.xcodeproj/project.pbxproj
*.storekit
*.entitlements

Check forbidden edits directly

git diff -- \
  OpenIntelligence/Core/Models/ChatMessage.swift \
  OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift \
  OpenIntelligence/Services/Storage/SQLiteFullTextService.swift \
  OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift \
  OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift \
  OpenIntelligence/Services/Billing/EntitlementStore.swift

Expected: no output.

Search for illegal coupling

rg -n "ChatMessage|WorkspaceSyncService|SQLiteFullTextService|BNNSVectorDatabase|FoundationModelRoutePolicy|RAGAppIntents|EntitlementStore" \
  OpenIntelligence/Core/Models/EvidenceThread.swift \
  OpenIntelligence/Services/Storage/EvidenceThreadStore.swift

Expected: no hits, unless only in comments explaining non-dependency. Ideally no hits.

Verify storage path

rg -n "LocalCache|EvidenceThreads|Application Support|Documents" \
  OpenIntelligence/Core/Models/EvidenceThread.swift \
  OpenIntelligence/Services/Storage/EvidenceThreadStore.swift

Expected:

* LocalCache/EvidenceThreads
* no base Documents directory
* no iCloud/ubiquity path

Check for sync leakage

rg -n "ubiquity|NSMetadataQuery|NSFileCoordinator|NSUbiquityIdentityDidChange|iCloud|CloudKit" \
  OpenIntelligence/Core/Models/EvidenceThread.swift \
  OpenIntelligence/Services/Storage/EvidenceThreadStore.swift

Expected: no implementation dependency.

⸻

3. Build/test verification

A standalone script is useful, but you need one real build-level check.

Run whatever command matches your repo. Examples:

xcodebuild -list

Then one of:

xcodebuild test \
  -scheme OpenIntelligence \
  -destination 'platform=macOS'

or:

xcodebuild test \
  -scheme OpenIntelligence \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

If the project uses Xcode 16/26 synchronized groups, new files may compile without touching project.pbxproj. If not, the new Swift files may exist on disk but not be part of the app/test target. That is the main technical issue to catch.

Minimum test expectations

Test	Required
EvidenceThread encodes/decodes without data loss	Yes
EvidenceThreadStore.saveThread writes to expected local path	Yes
getThread returns exact saved thread	Yes
listThreads(containerId:) scopes by container ID	Yes
deleteThread removes only the target thread	Yes
Store does not import or invoke sync/SQLite/chat/PCC/billing	Yes
Atomic write behavior is present or explicitly deferred	Prefer yes

⸻

4. The missing system: make Antigravity “always know what to do”

You need one more governance layer. Right now you have an architecture atlas, final gates, and phase-specific plans. What you still need is a task router plus change-impact matrix plus Notion sync protocol.

Add these files:

Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md
Docs/AuditArtifacts/Governance/change_impact_matrix.csv
Docs/AuditArtifacts/Governance/notion_roadmap_sync_protocol.md
Docs/AuditArtifacts/Governance/post_implementation_verification_template.md

This gives Antigravity a durable decision tree.

⸻

5. Prompt: Phase 1A Post-Implementation Verification Gate

Run this now before committing.

You are operating inside the public Gunnarguy/OpenIntelligence repository, not OpenIntelligence-Engine.
Role:
You are an independent post-implementation auditor for Phase 1A Evidence Threads.
Mission:
Verify that the completed Evidence Threads Phase 1A implementation obeys the final implementation gate and is safe to commit.
Hard constraints:
1. Do not modify Swift source files unless you find a compile-breaking issue in the new Phase 1A files only.
2. Do not modify existing app source files.
3. Do not modify ChatMessage.swift.
4. Do not modify WorkspaceSyncService.swift.
5. Do not modify SQLiteFullTextService.swift.
6. Do not modify BNNSVectorDatabase.swift.
7. Do not modify FoundationModelRoutePolicy.swift.
8. Do not modify CloudConsentPromptView.swift.
9. Do not modify RAGAppIntents.swift.
10. Do not modify EntitlementStore.swift.
11. Do not modify StoreKit configs, entitlements, or project settings unless target membership is strictly required, and if it is required, explain why before changing.
12. Do not implement Phase 1B.
13. Do not add iCloud sync.
14. Do not add App Intents.
15. Do not add billing gates.
16. Do not add PCC/routing changes.
17. Do not run destructive git commands.
Required files to read:
1. AGENTS.md
2. GEMINI.md
3. Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md
4. Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md
5. Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md
6. Docs/AuditArtifacts/FinalReview/final_post_delta_repair_readiness_gate.md
7. Docs/AuditArtifacts/FinalReview/final_implementation_gate.md
8. The Phase 1A Implementation Plan artifact
9. The Phase 1A Walkthrough artifact
10. New EvidenceThread source files
11. New EvidenceThread tests or standalone verification scripts
Verification tasks:
1. List all changed files with git status and git diff --name-only.
2. Confirm only allowed files were added or modified.
3. Confirm forbidden files were not modified.
4. Confirm EvidenceThread does not depend on ChatMessage.
5. Confirm EvidenceThreadStore does not depend on WorkspaceSyncService, SQLiteFullTextService, BNNSVectorDatabase, FoundationModelRoutePolicy, RAGAppIntents, or EntitlementStore.
6. Confirm storage path is Application Support / LocalCache / EvidenceThreads / <containerId> / <threadId>.json.
7. Confirm the implementation does not use iCloud, CloudKit, NSMetadataQuery, NSFileCoordinator, App Intents, StoreKit, or PCC routing.
8. Confirm atomic writes or clearly document if atomic write is deferred.
9. Confirm tests cover serialization, save, load, list-by-container, and delete.
10. Run the available standalone test script.
11. Run the strongest available build/test command for this repo, or explain exactly why it could not be run.
12. Produce a commit-readiness verdict.
Required commands:
Use safe commands only.
Run:
git status --porcelain
git diff --name-only
git diff -- OpenIntelligence/Core/Models/ChatMessage.swift OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift OpenIntelligence/Services/Storage/SQLiteFullTextService.swift OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift OpenIntelligence/Services/Billing/EntitlementStore.swift
rg -n "ChatMessage|WorkspaceSyncService|SQLiteFullTextService|BNNSVectorDatabase|FoundationModelRoutePolicy|CloudConsentPromptView|RAGAppIntents|EntitlementStore" OpenIntelligence/Core/Models/EvidenceThread.swift OpenIntelligence/Services/Storage/EvidenceThreadStore.swift
rg -n "ubiquity|NSMetadataQuery|NSFileCoordinator|NSUbiquityIdentityDidChange|iCloud|CloudKit|StoreKit|AppIntent|PrivateCloudCompute|PCC" OpenIntelligence/Core/Models/EvidenceThread.swift OpenIntelligence/Services/Storage/EvidenceThreadStore.swift
rg -n "LocalCache|EvidenceThreads|Documents" OpenIntelligence/Core/Models/EvidenceThread.swift OpenIntelligence/Services/Storage/EvidenceThreadStore.swift
xcodebuild -list
If a valid scheme is known, run the best available xcodebuild test command.
Required output:
Create:
Docs/AuditArtifacts/Implementation/phase_1a_post_implementation_verification.md
Report format:
1. Executive Summary:
   - COMMIT_READY
   - COMMIT_READY_WITH_CAUTIONS
   - NOT_READY
2. Changed files matrix:
   - file
   - status
   - allowed_by_gate yes/no
   - notes
3. Forbidden file check.
4. Coupling check.
5. Storage path check.
6. Test results.
7. Build results.
8. Remaining cautions.
9. Final commit recommendation.
10. evidence_level and confidence for every major conclusion.
Stop condition:
Stop after verification. Do not commit automatically.

⸻

6. Prompt: Add the repository operating system layer

Run this after the post-implementation check, either before or after the Phase 1A commit. This is what makes the repo “always know what to do.”

You are operating inside the public Gunnarguy/OpenIntelligence repository, not OpenIntelligence-Engine.
Role:
You are a repository operating-system architect and documentation governance designer.
Mission:
Create a durable task-routing and change-impact control layer so future Antigravity/Gemini agents always know what files to inspect, what files may be changed, what files are prohibited, what documentation must be updated, and when the Notion roadmap database must be updated.
Hard constraints:
1. Do not modify Swift source files.
2. Do not modify tests.
3. Do not modify Xcode project files.
4. Do not modify StoreKit configs or entitlements.
5. Do not run destructive git commands.
6. This is a documentation/governance-only task.
Required files to read:
1. AGENTS.md
2. GEMINI.md
3. Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md
4. Docs/AgentPlaybooks/03_CHANGE_IMPACT_DOC_UPDATE.md
5. Docs/AgentPlaybooks/04_PR_GOVERNANCE_REVIEW.md
6. Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
7. Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md
8. Docs/AuditArtifacts/FinalReview/final_post_delta_repair_readiness_gate.md
9. Docs/AuditArtifacts/FinalReview/final_implementation_gate.md
10. Docs/AuditArtifacts/Implementation/phase_1a_post_implementation_verification.md, if it exists
Create these new governance files:
1. Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md
2. Docs/AuditArtifacts/Governance/change_impact_matrix.csv
3. Docs/AuditArtifacts/Governance/notion_roadmap_sync_protocol.md
4. Docs/AuditArtifacts/Governance/post_implementation_verification_template.md
File 1: 07_TASK_ROUTER_AND_CHANGE_CONTROL.md
Must define:
- task classes:
  - docs_only
  - implementation_local
  - implementation_high_risk
  - refactor
  - bugfix
  - release
  - roadmap_update
  - audit_verification
- required preflight checks for each class
- allowed file scopes
- prohibited file scopes
- required documentation updates
- required tests
- required stop conditions
- when to ask the user for explicit approval
- rule that implementation may not auto-proceed after plan unless the user explicitly says PROCEED
File 2: change_impact_matrix.csv
Must include columns:
- changed_path_glob
- subsystem
- risk_level
- required_docs_to_read
- docs_to_update_if_changed
- tests_required
- forbidden_without_approval
- notion_update_required
- evidence_level_required
- confidence_required
- verification_command
- notes
Include rows for at least:
- OpenIntelligence/Core/Models/**
- OpenIntelligence/Services/Storage/**
- OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift
- OpenIntelligence/Services/Billing/**
- OpenIntelligence/Services/AIPlatform/**
- OpenIntelligence/Services/LLM/**
- OpenIntelligence/Services/RAG/**
- OpenIntelligence/Features/Chat/**
- OpenIntelligence/Features/**/AppIntents*
- OpenIntelligence/Services/VectorStore/**
- Docs/**
- README.md
- PRIVACY.md
- HOW_IT_WORKS.md
- StoreKit configs
- .xcodeproj/project.pbxproj
- Entitlements files
File 3: notion_roadmap_sync_protocol.md
Must define:
- Notion is a planning mirror, not the source of truth for architecture.
- Git/docs are the source of truth.
- Notion must be updated only after:
  1. phase gate opened
  2. implementation completed
  3. verification completed
  4. feature released or deferred
- Required Notion properties:
  - Feature
  - Repo
  - Phase
  - Status
  - Gate State
  - Risk Class
  - Last Verified SHA
  - Source of Truth Doc
  - Implementation Artifact
  - Verification Artifact
  - Docs Updated
  - Tests Passing
  - Next Action
  - Blockers
- Status values:
  - Backlog
  - Ready for Planning
  - Planned
  - Implementation In Progress
  - Verification Required
  - Verified
  - Blocked
  - Shipped
  - Deferred
- Rules for when Notion must not be updated.
- Required evidence links back to repo artifacts.
File 4: post_implementation_verification_template.md
Must provide a reusable verification template for future phases.
Also update:
1. AGENTS.md
   - Add a directive to read Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md before any implementation or roadmap update task.
   - Add a directive that agents must not auto-proceed from planning to implementation without explicit user approval.
2. Docs/AgentPlaybooks/README.md
   - Add the new playbook.
Required output:
Create Docs/AuditArtifacts/Governance/repository_operating_system_setup.md summarizing:
- files created
- files modified
- how future agents should use the task router
- how Notion update decisions are made
- remaining limitations
Stop condition:
Stop after creating the governance layer. Do not implement additional app features.

⸻

7. Notion roadmap protocol: exact policy

Your Notion database should not become the source of truth for architecture. It should become the planning and progress mirror.

Recommended Notion database schema

Property	Type	Purpose
Feature	Title	Human-readable task/feature
Repo	Select	OpenIntelligence, OpenIntelligence-Engine, etc.
Phase	Select	Governance, Phase 1A, Phase 1B, etc.
Status	Select	Backlog, Planned, In Progress, Verification Required, Verified, Shipped, Blocked
Gate State	Select	READY, PARTIAL, NO-GO
Risk Class	Select	Low, Medium, High, Critical
Last Verified SHA	Text	Git commit hash
Source of Truth Doc	URL/Text	Link/path to canonical doc
Implementation Artifact	URL/Text	Link/path to walkthrough
Verification Artifact	URL/Text	Link/path to verification report
Docs Updated	Checkbox	Whether docs were updated
Tests Passing	Checkbox	Whether tests passed
Next Action	Text	Exact next move
Blockers	Text	Current blockers
Owner	Person/Text	You or agent
Last Synced	Date	Roadmap sync timestamp

When to update Notion

Event	Update Notion?
Idea captured	Yes
Governance gate says READY	Yes
Implementation starts	Yes
Implementation completes	Yes
Verification completes	Yes
Commit created	Yes
Release shipped	Yes
Minor local wording change	No
Exploratory audit with no decision	Usually no
Failed experiment	Yes, if it changes roadmap priority

⸻

8. Commit strategy

Do not squash all of this into one commit if you can avoid it.

Use at least two commits.

Commit 1: Governance repair and final gate

git add AGENTS.md GEMINI.md Docs README.md PRIVACY.md HOW_IT_WORKS.md CHANGELOG.md
git commit -m "chore(governance): finalize post-repair Phase 1A architecture gate"

Commit 2: Phase 1A implementation

After post-implementation verification:

git add \
  OpenIntelligence/Core/Models/EvidenceThread.swift \
  OpenIntelligence/Services/Storage/EvidenceThreadStore.swift \
  OpenIntelligenceTests \
  Docs/AuditArtifacts/Implementation
git commit -m "feat(evidence-threads): add local-only Phase 1A JSON store"

If the test files are elsewhere, adjust the path. Do not blindly git add ..

Commit 3: Repository operating system layer

git add \
  AGENTS.md \
  Docs/AgentPlaybooks \
  Docs/AuditArtifacts/Governance
git commit -m "chore(governance): add task router and roadmap sync protocol"

⸻

9. What it needs most

The thing you are describing - “always know exactly what to do and what files to change” - requires three durable mechanisms:

Mechanism	Why it matters
Task router	Classifies the work before any edits
Change-impact matrix	Maps changed files to required docs/tests/Notion updates
Post-implementation verification gate	Prevents silent drift after code changes

Right now you have strong architecture docs and phase gates. Add those three, and the repo becomes much closer to self-governing.

Bottom line

The Phase 1A result sounds promising. The next correct move is:

1. Run the Phase 1A Post-Implementation Verification Gate.
2. Commit governance and implementation separately.
3. Add the Task Router + Change Impact Matrix + Notion Roadmap Sync Protocol.
4. Use those files as mandatory preflight for every future Antigravity task.

The only process issue I would fix immediately is the auto-proceed behavior. For future implementation phases, require the exact phrase:

PROCEED: IMPLEMENT

No exact phrase, no source edits.
