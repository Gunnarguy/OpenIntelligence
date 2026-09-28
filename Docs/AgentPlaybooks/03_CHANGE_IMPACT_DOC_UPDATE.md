# Change Impact Document Update Workflow

This playbook defines the maintenance workflow for keeping documentation in sync after code changes or PR merges.

## Workflow Steps
1. **Analyze Diff**: Run `git diff --name-only main...HEAD` (or the equivalent target branch diff).
2. **Identify Changed Files**: Extract the list of modified source files.
3. **Map to Cross-Reference**: Cross-reference the changed files against `documentation_cross_reference.csv` (or the Architecture Atlas).
4. **Identify Impacted Docs**: Determine which markdown files document the modified subsystems or components.
5. **Update Only Impacted Docs**: Modify the identified documentation files to reflect the new code reality. 
6. **No-Docs-Needed Justification**: A written justification does not replace the documents the pre-commit hook requires: `scripts/enforce_docs_hook.sh` fails a commit whose staged Swift lacks the documents `scripts/required_docs.sh` names for its paths. A justification is for changes outside those paths only. `[evidence_level: code_verified, confidence: high, evidence_source: scripts/required_docs.sh, scripts/enforce_docs_hook.sh, corrected 2026-09-28]`
7. **Evidence & Confidence**: Include the required `evidence_level` and `confidence` scores for all documentation impact decisions.
