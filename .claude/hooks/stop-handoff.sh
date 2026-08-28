#!/usr/bin/env bash
# Context OS: Stop-hook closeout net.
#
# Asks, at most once per session, for the obligations this session incurred and did not discharge:
#
#   1. A handoff. The repository changed and Docs/ai/STATE.md was left untouched, so a fresh session
#      could not continue from it.
#   2. Documentation. Source changed and the specific documents that source requires were not
#      touched. Resolved by scripts/required_docs.sh, the same table the pre-commit hook enforces,
#      so the two cannot disagree. This catches what pre-commit cannot: work that was never
#      committed.
#   3. The roadmap. Source changed and no Notion WRITE was recorded this session.
#      .claude/hooks/notion-receipt.sh writes a receipt on PostToolUse for the Notion write tools,
#      so this is evidence of an action, not a memory of intending one. A query leaves no receipt,
#      which is the point: reading the board is not recording work on it.
#
# It is a net, not the workflow. The project-handoff and notion-roadmap skills are the workflow.
#
# Four guards against blocking a session it should not block:
#   1. The SessionStart fingerprint. Identical means nothing changed, so a read-only or
#      question-only session is never blocked.
#   2. Per-obligation evidence. Each is dropped the moment the work it asks for is visible.
#   3. A once-per-session sentinel, plus the `stop_hook_active` field when the installed version
#      supplies it. Blocking happens at most once, so no loop is possible.
#   4. If the sentinel cannot be written, do not block at all, because guard 3 would be unarmed.
#
# Known limitation, unchanged: the fingerprint and the changed-path list are repository-wide, so
# they cannot separate this session's edits from a concurrent session's or an external process's. A
# second session editing the tree can make a read-only session see obligations. The prompt is worded
# so that answering "not mine" is a valid one-line response.
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
RESOLVER="$ROOT/scripts/required_docs.sh"
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
BASE_HEAD="$(sed -n 's/^head=//p' "$BASELINE" | head -1)"
case "$BASE_STATE_MTIME" in '' | *[!0-9]*) BASE_STATE_MTIME=0 ;; esac

NOW_FP="$(repo_fingerprint)"
# An empty fingerprint on either side means git could not answer. Cannot prove work, so do not block.
[ -n "$BASE_FP" ] && [ -n "$NOW_FP" ] || exit 0
[ "$NOW_FP" = "$BASE_FP" ] && exit 0

# ---------------------------------------------------------------------------
# What this session touched.
#
# The union of everything committed since the session's baseline HEAD and everything still dirty.
# A file that was already dirty when the session opened is included, which over-reports slightly;
# that is the safe direction for a prompt, and cheaper than a per-tool edit ledger.
#
# `head=` was added to the baseline on 2026-08-28. Sessions whose baseline predates it get the
# handoff question only, because without a baseline commit there is no honest way to say which paths
# this session touched.
# ---------------------------------------------------------------------------
CHANGED_PATHS=""
if [ -n "$BASE_HEAD" ] && git rev-parse --verify --quiet "${BASE_HEAD}^{commit}" >/dev/null 2>&1; then
  CHANGED_PATHS="$(
    {
      git diff --name-only "$BASE_HEAD" HEAD -- . ':(exclude).claude/.state' 2>/dev/null
      git status --porcelain -z -uall -- . ':(exclude).claude/.state' 2>/dev/null |
        tr '\0' '\n' | sed -n 's/^..[[:space:]]//p'
    } | sort -u
  )"
fi

touched() { printf '%s\n' "$CHANGED_PATHS" | grep -qxF "$1"; }

OBLIGATIONS=()

# --- 1. Handoff -------------------------------------------------------------
if ! { [ "$(mtime_of "$STATE_MD")" -gt "$BASE_STATE_MTIME" ]; } 2>/dev/null; then
  OBLIGATIONS+=("Docs/ai/STATE.md was not updated. Run the project-handoff skill: the objective, what was verified and by which command, any blocker, and one exact next action.")
fi

# --- 2. Documentation -------------------------------------------------------
MISSING_DOCS=""
if [ -n "$CHANGED_PATHS" ] && [ -x "$RESOLVER" ]; then
  REQUIREMENTS="$(printf '%s\n' "$CHANGED_PATHS" | bash "$RESOLVER" 2>/dev/null)" || REQUIREMENTS=""
  if [ -n "$REQUIREMENTS" ]; then
    while IFS= read -r doc; do
      [ -n "$doc" ] || continue
      touched "$doc" || MISSING_DOCS="$MISSING_DOCS $doc"
    done < <(printf '%s\n' "$REQUIREMENTS" | awk -F'\t' '$1 == "required" { print $2 }' | sort -u)
  fi
fi
if [ -n "$MISSING_DOCS" ]; then
  OBLIGATIONS+=("Source changed but these documents did not:$MISSING_DOCS. The mapping is .agents/rules/01-docs-and-notion-sync.md. Update them, or say in one line why this change does not touch what they describe.")
fi

# --- 3. Roadmap -------------------------------------------------------------
SOURCE_CHANGED=no
[ -n "$CHANGED_PATHS" ] && printf '%s\n' "$CHANGED_PATHS" | grep -qE '\.swift$' && SOURCE_CHANGED=yes
RECEIPTS="$STATE_DIR/notion-$SESSION_ID.receipts"
if [ "$SOURCE_CHANGED" = "yes" ] && [ ! -s "$RECEIPTS" ]; then
  OBLIGATIONS+=("Source changed and no Notion write was recorded this session. Use the notion-roadmap skill: set the row this work tracks to In Progress or Completed, or file one. If this was a refactor or a fix no row tracks, say so in one line. New findings default to Future Backlog; the active release is scope-frozen.")
fi

[ "${#OBLIGATIONS[@]}" -gt 0 ] || exit 0

# Guard 4: without a sentinel there is no loop protection, so blocking would risk a loop.
touch "$SENTINEL" 2>/dev/null || exit 0
[ -f "$SENTINEL" ] || exit 0

REASON="Closeout check, fired once per session. This session changed the repository and left the following open:"
i=0
for o in "${OBLIGATIONS[@]}"; do
  i=$((i + 1))
  REASON="$REASON
$i. $o"
done
REASON="$REASON

If another session or an external process made these changes, or the change was trivial, say so in one line and stop."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$REASON" '{decision:"block", reason:$r}' 2>/dev/null && exit 0
fi
python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]}))' "$REASON" 2>/dev/null && exit 0
exit 0
