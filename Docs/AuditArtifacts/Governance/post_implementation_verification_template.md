# Post-Implementation Verification Template

**Date:** YYYY-MM-DD
**Feature/Phase:** [Feature Name or Phase]
**Verified By:** [Agent or Developer Name]

## 1. Executive Summary
- **Verdict:** [COMMIT_READY | COMMIT_READY_WITH_CAUTIONS | NOT_READY]
- **Evidence Level:** [High/Medium/Low]
- **Confidence:** [Strong/Moderate/Weak]
- **Summary:** [1-2 sentences summarizing the state of the implementation]

## 2. Changed Files Matrix
| File | Status | Allowed By Gate | Notes |
|------|--------|-----------------|-------|
| `path/to/file` | [Added/Modified/Deleted] | [Yes/No] | [Reasoning] |

## 3. Forbidden File Check
List any forbidden files checked and their modification status. If any were unexpectedly modified, explain why and flag as NOT_READY unless explicitly authorized.

## 4. Coupling Check
Verify that the new code is decoupled from legacy systems, if required. Include the commands used to check (e.g., `grep_search`).

## 5. Storage Path Check
Verify any file system storage paths align with architecture atlas rules (e.g., avoiding Documents or iCloud unless intended).

## 6. Test Results
Summarize the results of running tests or the existence of standalone test scripts.

## 7. Build Results
Summarize `xcodebuild test` results. If tests were skipped, explain why.

## 8. Remaining Cautions
List any technical debt, edge cases, or potential risks identified during the audit.

## 9. Final Commit Recommendation
Provide the final decision on whether the changes should be committed and pushed.
