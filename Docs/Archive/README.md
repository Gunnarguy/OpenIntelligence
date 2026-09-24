# Docs/Archive

Historical one-off reports and agent directives, moved here from the repository
root on 2026-07-28. They are **kept tracked** because other governance documents
(`.agent/DECISION_LOG.md`, `.agent/FINAL_REPORT_DRAFT.md`, the risk register)
cite them as evidence sources — this project does not delete evidence, it files it.

| File | What it was |
| :--- | :--- |
| `INDEPENDENT_VERIFICATION_REPORT.md` | 2026-07-11 independent audit that identified MAIN-1/MAIN-2 (RISK-13/RISK-14) |
| `GEMINI_REMEDIATION_DIRECTIVE.md` | Remediation directive issued to the Gemini agent during the PR audit era |
| `FinalizationOpenIntelligence.md` / `...1b.md` | June 2026 finalization directives, superseded by RepoOS routing |
| `CHANGELOG_2.0_to_5.2.md` | `CHANGELOG.md` sections for versions 2.0 to 5.2, moved verbatim on 2026-09-24 when the file reached 651 KB |
| `agents_AGENTS_md_superseded_2026-09-24.md` | The old `.agents/AGENTS.md`, a drifted copy of the root `AGENTS.md`; that path is now a pointer |
| `geminirules_superseded_2026-09-24.md` | The old `.geminirules` rule set, which contradicted the current rules in four places; that file is now a pointer |

Console dumps formerly at the root (`macosconsole.txt`, `THis.md`,
`DeepThinkConsole&Trace.txt`) were removed from HEAD in the same cleanup; they
remain retrievable from git history (last present at commit `81073c9`) and local
copies live in the untracked `.attic.nosync/`.
