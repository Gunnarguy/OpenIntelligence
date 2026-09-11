---
name: diagnose-before-claiming
description: Use before stating the cause of any defect, before shipping a fix for a bug whose mechanism has not been observed, and before reporting that something is broken, missing, dead, or unreachable. Also use when a stack trace, a log excerpt, a grep result, or a code fragment is about to become the basis for a conclusion. Triggers on "the problem is", "this is caused by", "that file has no", "X is never called", "it's broken", and on any fix written without first reproducing the failure.
---

# Diagnose before claiming

This exists because of 2026-09-10, when four causes were named from evidence that could not
support them, in one session, costing several rebuild cycles and a stretch of the user's patience.
The failure was never "did not grep". Greps were run constantly. The failure was **stopping at the
first plausible explanation without checking whether the evidence could rule out the others.**

## The rule

Before writing a cause into a message, a commit, a doc or a roadmap row, answer three questions:

1. **What are the competing explanations?** Name at least two. If only one comes to mind, that is a
   sign of not having looked, not of certainty.
2. **Can what I am holding rule any of them out?** If the same evidence is consistent with every
   candidate, it is not evidence for a conclusion. It is a hypothesis.
3. **Is there one cheap signal that would separate them?** If yes, get it **before** doing anything
   expensive. A question to the user costs one turn. A build costs ten minutes and may prove
   nothing.

A fix shipped without reproducing the failure is a guess with a commit hash. Say so in the commit
if it comes to that, and never say "fixed" for something never observed failing.

## The four shapes this keeps taking

### A partial signal treated as a whole one

A **stack trace records where execution stopped, never what failed.** It cannot distinguish
`Int(nan)` from an integer overflow from a breakpoint. On 2026-09-10 four traces were analysed
across several turns; the decisive evidence was the one line of console text above the trace, and
when it finally arrived it showed no error at all. The app was paused at a stale breakpoint in
`Breakpoints_v2.xcbkptlist`, which one read of that file would have found in seconds.

Ask: does this artefact contain the answer at all, or only the location?

### An instrument that cannot see the whole thing

A regex capped at 1200 characters truncated a `PBXNativeTarget` block, the
`packageProductDependencies` line fell outside the window, and its absence was reported as the
target not declaring the dependency. A Notion row and a STATE.md handoff were both written on it.
The target had declared it correctly the entire time.

Ask: could my tool have seen the thing whose absence I am reporting? Verify the negative by a
second method before publishing it. For "X has no call sites", grep the symbol, then separately
check indirect dispatch: protocol conformance, factories, registries, string-keyed lookup,
notification names, URL hosts, App Intents, `@Environment`.

### A transient reported as a steady state

iCloud sync was declared broken from a snapshot taken about thirty seconds after a first launch.
It converged on its own shortly after. Bootstrap, migration, indexing and sync all pass through
states that look like bugs.

Ask: is this thing still running? Sample twice, separated in time, before calling a mid-flight
state a defect.

### A fragment generalised to the mechanism

The routing policy's Hybrid branch was quoted as though it were the whole router, producing a
confident and wrong claim that PCC only fires on context overflow. Two branches above it handle
the explicit user preference, which is what the picker actually uses.

Ask: am I looking at the whole function? Read `switch` statements top to bottom. The branch that
matters is often the one that returns before the one being read.

## Cheap decisive signals, in rough order of value

| Situation | The signal that actually settles it |
|---|---|
| A crash or a pause | The error line above the trace, or `bt` at the `(lldb)` prompt. Not the trace. |
| "It crashes on device" | Is there a crash report? No report plus a clean log means it did not crash. |
| "This code is dead" | Grep excluding its own file and `#Preview`, **then** check indirect dispatch |
| "The build is stuck" | Object-file count and compiler processes. Elapsed time proves nothing. |
| "The build is slow" | Is Xcode open? It holds the build database and a CLI build waits on it, forever. |
| "Sync is broken" | Sample twice, minutes apart |
| "The API does not have X" | Sweep every `.swiftinterface` in the SDK. See `apple-api-truth`. |
| "This claim in the UI is false" | Find the call site. See `oi-claim-audit` before removing anything. |
| A wrong number on screen | Compare the count at each stage, source to display. The first drop is the bug. |

## Shell traps that manufacture false evidence

- `cmd; echo "done"` prints "done" when `cmd` failed. Use `&&`. On 2026-09-10 this reported an app
  bundle as deleted when every file had failed with `Permission denied`.
- A pipeline through `grep` writes nothing until something matches, so an empty log file looks like
  a hung process and is not one.
- `zsh` does not word-split unquoted variables the way `bash` does, and `--include=*.swift` needs
  quoting or it is glob-expanded before `grep` sees it.
- Counting braces or parentheses to check syntax is meaningless; they occur inside strings and
  comments. Use `swiftc -parse`.

## When the evidence is not available

Say which claim is unverified and what would settle it. `[evidence_level: inferred]` exists for
this. A row that says "unverified lead, here is how to test it" is worth more than a confident
wrong cause, and far more than a fix for a bug nobody has seen fail.
