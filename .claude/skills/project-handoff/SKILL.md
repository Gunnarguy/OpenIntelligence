---
name: project-handoff
description: Write the cross-session handoff into Docs/ai/STATE.md so a fresh conversation can continue without this transcript. Use before ending substantive work, when the objective materially changes, when the Stop hook asks for a handoff, and before a planned compaction. Also use when the user says "hand off", "wrap up", "save state", "update STATE", or "I'm stopping here".
---

# Project handoff

Produce a `Docs/ai/STATE.md` that a fresh session can act on with no other input. Overwrite stale
execution detail rather than appending. Target under 150 lines.

## Steps

1. **Establish ground truth from git, not from memory.**

   ```bash
   git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD && git status --porcelain && git log --oneline -5
   ```

2. **Name one objective.** What is actually being attempted, in one or two sentences. If the
   objective changed during the session, record the current one and delete the old.

3. **Record what is verified and how.** Every entry in the Verification section is
   `command -> result`, and only for commands you ran and read the output of. If the working tree
   has not been built, say that. Never write a test result you did not observe.

4. **Record the working set.** Each file that matters to continuation, with one line on why. Include
   uncommitted files. A fresh session should know which files to open before touching anything.

5. **Record blockers and unknowns with a verification path.** Not "the FTS5 path might need
   restructuring" but "`searchWithFTS5` accepts `trace:` and records nothing; verify by reading it
   from line 873 and locating the equivalent of each canonical stage." A blocker a fresh session
   cannot act on is a worry, not a blocker.

6. **Move durable rationale out.** A decision whose reasoning cannot be reconstructed from the code
   belongs in `Docs/ai/DECISIONS.md` with date, context, decision, alternatives, rationale, and
   consequences. A newly verified command belongs in `Docs/ai/RUNBOOK.md`. Do not leave either in
   `STATE.md`, which gets overwritten.

7. **Write exactly one next action**, concrete enough to execute without asking a question. Name the
   file and the change, or the command and what its output would decide.

   If the objective is finished, say so rather than inventing a new one. Set Status to what shipped,
   and make Exact Next Action either the next objective you were actually told about, or:

   ```markdown
   ## Exact Next Action
   None. The previous objective is complete and verified. There is no active objective; ask the user
   what to pick up, or take a roadmap item from the Notion database.
   ```

   A fabricated next action is worse than an honest idle state, because the next session will act
   on it.

8. **Check that the repo-required updates happened.** If code changed this session, the doc updates
   in `.agents/rules/01-docs-and-notion-sync.md` and any Notion roadmap row are part of the task,
   not part of the handoff. Do them, or record them as an explicit blocker.

9. **Read the file back cold.** Re-read the `STATE.md` you just wrote as if you had never seen this
   conversation. Can you name the objective, open the right files, and execute the next action
   without a single question? Anything that only makes sense because you remember the session is a
   defect: a pronoun with no referent, a "the fix" with no antecedent, a file named without a path.
   Fix those before you stop. This is the only check that catches a handoff that reads well and is
   useless.

## Structure

```markdown
# Current State

Updated: YYYY-MM-DD
Branch/worktree: ...
Last verified commit: <short sha>

## Objective
## Status
## Completed
## Active Constraints
## Working Set
## Verification
## Blockers / Unknowns
## Exact Next Action
```

`Last verified commit:` must be the short SHA on its own, because the SessionStart hook parses that
line to detect drift.

## Do not

Paste conversation summaries. Repeat architecture that already lives in `Docs/ai/ARCHITECTURE.md` or
the Atlas. Record work that does not affect continuation. Claim completion for work that only
compiles in principle.
