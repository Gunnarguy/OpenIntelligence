# /finalize — Close out a feature (docs → Notion → verify → commit → push)

Autonomous release-engineering pipeline. Run when the user says "finalize", "close out", or "finish" a feature — or proactively offer it when a feature's code work is done. Execute steps 1–5 without pausing; pause exactly once before step 6.

## 1. Analyze the diff
`git status --porcelain`, `git diff`, `git diff --cached`. Classify the change into architectural tag(s): `[Ingestion]` `[Chunking]` `[Indexing]` `[Retrieval]` `[Orchestration]` `[Shortcuts]` `[UI]` `[General]`.
Abort with a report if the diff touches any hard-boundary file from `.agents/rules/00-repoos-routing.md` that the user did not explicitly approve.

## 2. Update documentation
Call `/update-docs`.

## 3. Sync Notion roadmap
Call `/sync-notion`.

## 4. Verify (gate — do not proceed on failure)
1. `bash scripts/build_simulator_smoke.sh` — must succeed warning-free (AGENTS.md rule 14).
2. Run the `required_tests` from the matching row of `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`.
3. `python3 scripts/secret_scan.py` on newly added files.
If anything fails: stop, report, do not commit.

## 5. Stage & commit — EXPLICIT PATHS ONLY
1. NEVER `git add .` — the working tree may contain logs (`Ingestion.txt`, `build_output.txt`), research notes, and unreviewed `project.pbxproj` churn that must not ride along.
2. `git add <each changed source file> <each updated doc>` — list every path explicitly.
3. Confirm with `git status --porcelain` that only intended paths are staged; nothing from the forbidden list (`project.pbxproj`, `*.storekit`, `*.entitlements`, `*.log`, `*.txt` logs) unless the user named it.
4. `git commit -m "feat([Tag]): <summary>"` (or `fix(...)`/`docs(...)` as appropriate), tag matching step 1.

## 6. Push (single confirmation point)
Show the user: commit hash, files committed, docs updated, Notion row(s) touched, build/test results. Then ask ONE question: "Push to `<branch>` and trigger Xcode Cloud? (yes/no)". On yes: `git push origin <current branch>`, then confirm the feature is closed out. On no: leave the commit local and stop.
