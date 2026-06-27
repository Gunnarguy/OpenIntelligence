# Superseding Evidence Protocol

This protocol overrides all other instructions. It defines the strict requirements for how agents gather, classify, and present information about the codebase.

## Absolute Prohibitions
- **NO** destructive commands (`git reset --hard`, `git clean`, `rm -rf`, etc.).
- **NO** implementation changes during audit/governance phases.
- **NO** modifications to forbidden files (Swift source, tests, StoreKit configs, routing/sync implementations) during audit phases.
- **NO** presenting conceptual summaries as exact code linkages.
- **NO** self-verification of your own outputs.

## Evidence and Confidence Requirements
Every architectural claim, linkage, or documentation update must be tagged with an evidence level and a confidence value.

### Allowed Evidence Levels:
- `code_verified`: The exact symbol or code path was found in the `.swift` source via read or script.
- `grep_verified`: The symbol was found via a textual search across the repository.
- `artifact_derived`: The claim is based on a previously generated audit artifact (CSV/Markdown).
- `doc_claim_only`: The claim exists in current documentation, but has not been verified in code.
- `inferred`: The linkage is logically deduced from surrounding context but lacks direct synchronous invocation.
- `conceptual`: A high-level description of an architectural pattern without specific symbol mapping.
- `unknown`: The source of the claim cannot be determined.

### Allowed Confidence Values:
- `exact`: 100% verified exact symbol match and functional linkage.
- `high`: Verified asynchronous or delegated linkage, or highly reliable grep match.
- `medium`: Inferred behavior or dependency based on strong contextual clues.
- `low`: Speculative linkage or reliance on outdated documentation.
- `conceptual`: Not applicable to exact code; represents a design pattern.
- `unknown`: Confidence cannot be established.

### Required Reporting Columns
When generating CSVs or tabular data regarding architecture, include these columns:
- `evidence_level`
- `confidence`
- `evidence_source` (e.g., file path, doc name, prior artifact)
- `evidence_command_or_file` (e.g., `grep_search`, `DocumentProcessor.swift`)
- `verification_notes` (Explanation of how the claim was verified or why it is inferred)

## Checklists
### Phase-Start Checklist
1. Identify the allowed and forbidden files for the current phase.
2. Read required playbooks and canonical docs.
3. Formulate the evidence gathering strategy (static analysis scripts, grep searches).

### Phase-End Checklist
1. Verify all generated artifacts adhere to the Evidence Protocol.
2. Ensure no forbidden files were modified.
3. Check `git status --porcelain` to ensure clean state outside allowed artifacts.
4. Stop execution and prompt user for review.

## Error Handling
- **When uncertain:** Mark confidence as `low` or `unknown`. Do not guess exact symbol names.
- **When a previous artifact contains hallucinated symbols:** Correct the artifact immediately. Do not propagate the hallucination. Use code search to find the real symbol, or mark the relationship as `conceptual` if no exact symbol exists.
