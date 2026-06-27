# Change Impact Document Update Workflow

This playbook defines the maintenance workflow for keeping documentation in sync after code changes or PR merges.

## Workflow Steps
1. **Analyze Diff**: Run `git diff --name-only main...HEAD` (or the equivalent target branch diff).
2. **Identify Changed Files**: Extract the list of modified source files.
3. **Map to Cross-Reference**: Cross-reference the changed files against `documentation_cross_reference.csv` (or the Architecture Atlas).
4. **Identify Impacted Docs**: Determine which markdown files document the modified subsystems or components.
5. **Update Only Impacted Docs**: Modify the identified documentation files to reflect the new code reality. 
6. **No-Docs-Needed Justification**: If the code changes do not impact architectural or product documentation (e.g., simple bug fixes, localized UI tweaks), write a clear justification stating why no doc updates are needed.
7. **Evidence & Confidence**: Include the required `evidence_level` and `confidence` scores for all documentation impact decisions.
