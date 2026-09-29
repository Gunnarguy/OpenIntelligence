# Docs/Archive

Historical one-off reports and agent directives, moved here from the repository
root on 2026-07-28. They are **kept tracked** because other governance documents
(`ZeroRegressionAudit_2026-07/DECISION_LOG.md` and `ZeroRegressionAudit_2026-07/FINAL_REPORT_DRAFT.md`, formerly under `.agent/`, and the risk register, which stays at `.agent/RISK_REGISTER.md`)
cite them as evidence sources — this project does not delete evidence, it files it.

| File | What it was |
| :--- | :--- |
| `INDEPENDENT_VERIFICATION_REPORT.md` | 2026-07-11 independent audit that identified MAIN-1/MAIN-2 (RISK-13/RISK-14) |
| `GEMINI_REMEDIATION_DIRECTIVE.md` | Remediation directive issued to the Gemini agent during the PR audit era |
| `FinalizationOpenIntelligence.md` / `...1b.md` | June 2026 finalization directives, superseded by RepoOS routing |
| `CHANGELOG_2.0_to_5.2.md` | `CHANGELOG.md` sections for versions 2.0 to 5.2, moved verbatim on 2026-09-24 when the file reached 651 KB |
| `agents_AGENTS_md_superseded_2026-09-24.md` | The old `.agents/AGENTS.md`, a drifted copy of the root `AGENTS.md`; that path is now a pointer |
| `geminirules_superseded_2026-09-24.md` | The old `.geminirules` rule set, which contradicted the current rules in four places; that file is now a pointer |
| `ZeroRegressionAudit_2026-07/` | The July 2026 zero-regression PR audit, formerly `.agent/`, archived 2026-09-29: the owner's own directive (`OPENINTELLIGENCE_AUDIT_DIRECTIVE.md`, with its identical-text copy `OPENINTELLIGENCE_PR_DUMP_MASTER_DIRECTIVE.md` kept beside it), the decision log, authorization ledger, test evidence, baselines, matrices and `pr_manifest.json`. `RISK_REGISTER.md` stays at `.agent/` because live files cite RISK-20. DEC-35 in the log was reversed in code; see `Docs/ai/DECISIONS.md`, 2026-09-29 |
| `ARCHITECTURE_v4.1.md` | Formerly `Docs/ARCHITECTURE.md`, the v4.1 component map, archived 2026-09-29; its name matched the live `Docs/ai/ARCHITECTURE.md` |
| `HOW_IT_WORKS_root_overview_v2.0.md` | Formerly the root `HOW_IT_WORKS.md`, a short v2.0-era overview, archived 2026-09-29; `Docs/HOW_IT_WORKS.md` is the maintained walkthrough |
| `STORAGE_AND_PIPELINE_TRACE.md` | Formerly `Docs/Engineering/`, the April 2026 prototype trace, self-labelled superseded; `Docs/Engineering/FULL_SYSTEM_TRACE.md` replaced it |
| `APPLE_DOCUMENT_INTELLIGENCE.md` | Formerly `Docs/Engineering/`, a pre-WWDC 2026 copy of Apple's document APIs, archived 2026-09-29 |
| `RELEASE_NOTES_4.8_DRAFT.md` | Formerly `Docs/`, the spent 4.8 release-notes draft, archived 2026-09-29 (it also took private notes off gunnarguy.me) |
| `06_PHASE_1A_IMPLEMENTATION_PLAN.md` | Formerly `Docs/AgentPlaybooks/`, the Evidence Threads Phase 1A plan; Phases 1A to 1D are complete |
| `change-impact-docs-update.md`, `documentation-reconciliation.md`, `pr-review-docs-gate.md` | Formerly `Docs/AgentPlaybooks/`, one-line aliases of playbooks 03, 02 and 04, archived 2026-09-29 |
| `PRIVACY_summary_2026-02.md` | The root `PRIVACY.md` until 2026-09-29, dated February 2026, with eight statements the code contradicts (listed in roadmap row https://app.notion.com/p/3e949a74d54f81b79775e99953132f98); `PRIVACY.md` now points to the real policy |
| `Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md` (not kept here) | Moved out of the repository on 2026-09-29 into the owner's private workspace, `~/ASC/`, where `scripts/asc_winback_offers.rb` now points |
| `ROADMAP_record_through_2026-09-29.md` | The body of `Docs/ROADMAP.md` until 2026-09-29, written before 5.0; that file is now a pointer to the Notion roadmap |
| `RepoOS_02_AGENT_PROMPT_COMPILER_superseded_2026-09-29.md` | Formerly `Docs/RepoOS/02_AGENT_PROMPT_COMPILER.md`; the RepoOS preflight replaced its prompt templates |

Console dumps formerly at the root (`macosconsole.txt`, `THis.md`,
`DeepThinkConsole&Trace.txt`) were removed from HEAD in the same cleanup; they
remain retrievable from git history (last present at commit `81073c9`) and local
copies live in the untracked `.attic.nosync/`.

## Old paths, for citations inside archived documents

Archived documents are not edited to follow later moves. When one cites a path below, read it at the
new path.

| Old path | Now |
| :--- | :--- |
| `.agent/<file>` (every file except `RISK_REGISTER.md`) | `Docs/Archive/ZeroRegressionAudit_2026-07/<file>` |
| `Docs/ARCHITECTURE.md` | `Docs/Archive/ARCHITECTURE_v4.1.md` |
| `HOW_IT_WORKS.md` (root) | `Docs/Archive/HOW_IT_WORKS_root_overview_v2.0.md` |
| `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md` | `Docs/Archive/STORAGE_AND_PIPELINE_TRACE.md` |
| `Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md` | `Docs/Archive/APPLE_DOCUMENT_INTELLIGENCE.md` |
| `Docs/RELEASE_NOTES_4.8_DRAFT.md` | `Docs/Archive/RELEASE_NOTES_4.8_DRAFT.md` |
| `Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md` | `Docs/Archive/06_PHASE_1A_IMPLEMENTATION_PLAN.md` |
| `Docs/AgentPlaybooks/change-impact-docs-update.md`, `documentation-reconciliation.md`, `pr-review-docs-gate.md` | `Docs/Archive/` under the same names |
| `Docs/ROADMAP.md` sections 0 to 3 (before 2026-09-29) | `Docs/Archive/ROADMAP_record_through_2026-09-29.md` |
| `Docs/RepoOS/02_AGENT_PROMPT_COMPILER.md` | `Docs/Archive/RepoOS_02_AGENT_PROMPT_COMPILER_superseded_2026-09-29.md` |
