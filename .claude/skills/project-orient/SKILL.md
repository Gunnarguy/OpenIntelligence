---
name: project-orient
description: Reconstruct the minimum repository context needed for a specific task in OpenIntelligence, without pulling the documentation set into the main conversation. Use at the start of a broad, unfamiliar, or cross-subsystem task, when resuming work you did not start, or when the user says "get up to speed", "where are we", "what's the state of X", or "orient yourself".
---

# Project orientation

Return a compact, task-specific briefing. Not a repository encyclopedia.

## Steps

1. **Read `Docs/ai/STATE.md` first.** It is the handoff. Then check it against git, because git
   wins:

   ```bash
   git rev-parse --short HEAD && git status --porcelain && git log --oneline -5
   ```

   If `Last verified commit:` in STATE.md is behind HEAD, say so in the briefing and treat STATE.md
   as a lead rather than a fact.

2. **Route the task.** This tells you which docs are binding before you read anything else.

   ```bash
   python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<the user's request>" --path <path>
   ```

   Read the release as three fields, not one: `version` is what new work targets, `state` is
   `shipped` or `in_development`, and `last_shipped` is already out. If `version` comes back as
   `unreleased`, the next version has not been named; stop and ask rather than picking one.

3. **Delegate the breadth.** For anything requiring a sweep across subsystems, naming conventions,
   or call sites, use an Explore subagent so the intermediate file dumps stay out of this
   conversation. Ask it for conclusions and file paths, not excerpts.

4. **Read only the route's `read_first_docs`,** plus at most one of `Docs/ai/ARCHITECTURE.md`,
   `Docs/ai/PROJECT.md`, or `Docs/ai/DECISIONS.md` if the task needs it. Do not read the
   documentation set by default. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` supersedes any
   other doc that contradicts it.

5. **Resolve conflicts against code.** Docs in this repository have drifted from the app before, in
   both directions. When a doc and the source disagree, the source is the fact and the doc is a bug
   to fix in the same task.

## Return

Six short sections, nothing else:

- **Objective** as you now understand it, and whether it supersedes the one in STATE.md.
- **Relevant architecture**, a few sentences.
- **Files likely involved**, with one line each on why.
- **Constraints**, including any hard-boundary file in the path and whether the implementation gate
  applies.
- **Risks**, meaning what would break silently if this is done wrong.
- **Recommended next action**, one concrete step.

If something material is unknown, say `Unknown: ...` and give the exact command or file that would
settle it. Do not fill a gap with a plausible guess.
