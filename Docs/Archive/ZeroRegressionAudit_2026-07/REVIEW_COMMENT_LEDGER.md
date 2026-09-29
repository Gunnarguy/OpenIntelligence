# OpenIntelligence Review Comment Ledger

## Fetch Status
*   **First attempt (2026-07-11):** FAILED — `HTTP 401: Bad credentials` (recorded in DEC-05).
*   **Completed (2026-07-13):** `gh` is now authenticated (account Gunnarguy). Comments and reviews fetched for all open PRs #26–#68 (TE-14). `[evidence_level: code_verified, confidence: exact]`

## Global Findings
*   **Zero human review threads exist on any open PR.** Every comment/review is from a generated reviewer: `google-labs-jules` (greeting bot), `sourcery-ai`, `copilot-pull-request-reviewer`, `chatgpt-codex-connector`.
*   Sourcery and Codex hit rate limits on #40–#45 and #63–#68 ("reached your weekly rate limit" / "reached your Codex usage limits") — those PRs have no substantive generated review either.
*   Per the master directive, generated reviewers never outrank code evidence. No disposition in `pr_manifest.json` was changed on the basis of a generated comment.

## Classification of Substantive Generated Comments
| PR | Reviewer | Substance | Classification | Reconciliation with code evidence |
| :-- | :-- | :-- | :-- | :-- |
| #27 | Sourcery | Suggest extracting identifier validation | STYLE_ONLY | Superseded by closed-enum reimplementation plan (DEC-19) |
| #28 | Sourcery | "found 1 issue" | SUMMARY_ONLY | No change; equivalence verified independently |
| #33 | Sourcery | Notes double traversal of `results` | ACTIONABLE | Matches REWORK: benchmark the allocation claim |
| #34 | Sourcery/Codex | Flag behavior differences in new scanner | ACTIONABLE | Matches REWORK: tab-acceptance behavior change independently confirmed |
| #37 | Sourcery | Scalar-type inference only covers float32/16 | ACTIONABLE | Already the core of the REWORK rationale |
| #39 | Sourcery | 2 issues in statement reuse | ACTIONABLE | Matches missing step/reset error handling finding |
| #49 | Sourcery | "vDSP ties these functions to Apple platforms" | STYLE_ONLY | Not the operative concern (overlay→C-API downgrade is) |
| #51 | Sourcery/Codex | Edge case in `has(_:)` | ACTIONABLE | Folded into the edge-case test matrix requirement |
| #53 | Sourcery | Interpolating unescaped literals into regex | ACTIONABLE | Independently recorded (escape-literals strategy) |
| #55 | Sourcery | `ensureColumnExists` validation gaps | ACTIONABLE | Matches raw-`definition` finding |
| #56 | Sourcery | "keep a more descriptive separator" | INCORRECT | Benchmark evidence, not opinion, decides; disposition CLOSE stands |
| #57 | Sourcery | `try!` on precompiled regexes | ACTIONABLE | Independently recorded in REWORK requirements |
| #59 | Sourcery/Codex | Fallback denominator skew | ACTIONABLE | Matches composite-metric REWORK |
| #61 | Sourcery | cBLAS concerns | ACTIONABLE | Folded into consolidation benchmark plan |
| #62 | Sourcery | Questions unconditional zero return | ACTIONABLE | Matches false-rejection SUPERSEDE rationale |
| #63 | Sourcery | "Consider awaiting both" / concurrency notes | ACTIONABLE | Matches sizing-policy/cancellation SUPERSEDE rationale |
| #66 | Sourcery | 1 issue on persistence | ACTIONABLE | CLOSE on privacy grounds regardless |
| #67 | Sourcery | Duplicated buffer-clear logic | ACTIONABLE | Folded into clean-reimplementation requirements |
| #68 | Sourcery | 1 issue on expansion regeneration | ACTIONABLE | Matches reuse-existing-expansions REWORK |
| all | Jules bot | "reporting for duty" greetings | SUMMARY_ONLY | Ignored |
| all | Copilot | "Pull request overview" restatements | SUMMARY_ONLY | Ignored (descriptions are not evidence) |

## Historical Assertions (2026-07-11)
*   **PR #54:** `.advanced` unsupported in Xcode 27 SDK — remains BLOCKED (TE-02).
*   **PR #66:** privacy regression — disposition CLOSE (DEC-27).
