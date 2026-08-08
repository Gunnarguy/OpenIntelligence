#!/usr/bin/env bash
# Context OS: Stop-hook safety net.
#
# Asks for one handoff pass when the repository changed during a session but Docs/ai/STATE.md was
# left untouched. It is a safety net, not the workflow: the project-handoff skill is the workflow.
#
# Four guards against blocking a session it should not block:
#   1. The SessionStart fingerprint. Identical means nothing changed, so a read-only or
#      question-only session is never blocked.
#   2. STATE.md's mtime. If the session already wrote a handoff, there is nothing to ask for.
#   3. A once-per-session sentinel, plus the `stop_hook_active` field when the installed version
#      supplies it. Blocking happens at most once, so no loop is possible.
#   4. If the sentinel cannot be written, do not block at all, because guard 3 would be unarmed.
#
# Known limitation: the fingerprint is repository-wide, so it cannot tell this session's changes
# from a concurrent session's or an external process's. A second session editing the tree can make
# a read-only session ask for a handoff. The prompt is worded so that answering "not mine" is a
# valid one-line response. Fixing this properly needs a per-session edit ledger from a PostToolUse
# hook; that costs a hook firing on every write, which is not obviously worth it for one wrong
# prompt per concurrent session.
#
# Never fails a session. Every failure path exits 0 without blocking.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "${ROOT:-}" ] && [ -d "$ROOT" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib.sh" 2>/dev/null || exit 0

STATE_DIR="$ROOT/.claude/.state"
STATE_MD="$ROOT/Docs/ai/STATE.md"
mkdir -p "$STATE_DIR" 2>/dev/null || true

HOOK_STDIN="$(cat 2>/dev/null || true)"
SESSION_ID="$(hook_field session_id)"
[ -n "$SESSION_ID" ] || exit 0

# Guard 3a: the installed version already told us we are inside a stop-hook continuation.
case "$HOOK_STDIN" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# Guard 3b: our own once-per-session sentinel.
SENTINEL="$STATE_DIR/handoff-$SESSION_ID.done"
[ -f "$SENTINEL" ] && exit 0

# Guard 1: no baseline means we cannot prove work happened, so do not block.
BASELINE="$STATE_DIR/session-$SESSION_ID.baseline"
[ -f "$BASELINE" ] || exit 0
BASE_FP="$(sed -n 's/^fingerprint=//p' "$BASELINE" | head -1)"
BASE_STATE_MTIME="$(sed -n 's/^state_mtime=//p' "$BASELINE" | head -1)"
case "$BASE_STATE_MTIME" in '' | *[!0-9]*) BASE_STATE_MTIME=0 ;; esac

NOW_FP="$(repo_fingerprint)"
# An empty fingerprint on either side means git could not answer. Cannot prove work, so do not block.
[ -n "$BASE_FP" ] && [ -n "$NOW_FP" ] || exit 0
[ "$NOW_FP" = "$BASE_FP" ] && exit 0

# Guard 2: STATE.md was written during this session, so the handoff already happened.
[ "$(mtime_of "$STATE_MD")" -gt "$BASE_STATE_MTIME" ] 2>/dev/null && exit 0

# Guard 4: without a sentinel there is no loop protection, so blocking would risk a loop.
touch "$SENTINEL" 2>/dev/null || exit 0
[ -f "$SENTINEL" ] || exit 0

REASON="The repository changed during this session but Docs/ai/STATE.md was not updated, so a fresh session could not continue from it. Run the project-handoff skill now: record the objective, what was verified and by which command, any blocker, and one exact next action. If the change was trivial, or another session or process made it, or a handoff is genuinely unnecessary, say so in one line and stop. This check fires at most once per session."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$REASON" '{decision:"block", reason:$r}' 2>/dev/null && exit 0
fi
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
