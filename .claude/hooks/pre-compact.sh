#!/usr/bin/env bash
# Context OS: PreCompact checkpoint.
#
# Writes a machine-local snapshot of git state so the facts survive compaction, and warns the user
# when STATE.md has drifted from the working tree. It never blocks compaction: a context system that
# stalls compaction until the window fails is worse than one that writes a good checkpoint and lets
# it proceed.
#
# SessionStart replays the checkpoint when it fires again with source=compact.
#
# Never fails a session. Every failure path exits 0.

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
TRIGGER="$(hook_field trigger)"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

HEAD_SHA="$(git rev-parse --short HEAD 2>/dev/null)"
[ -n "$HEAD_SHA" ] || HEAD_SHA="unknown"
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="unknown"

# -uall so this agrees with the fingerprint and the session brief. Without it a whole new directory
# of files collapses to one `?? Dir/` entry and the checkpoint understates the work.
PORCELAIN="$(git status --porcelain -uall -- . ':(exclude).claude/.state' 2>/dev/null)"
DIRTY_N="$(count_lines "$PORCELAIN")"
[ -n "$DIRTY_N" ] || DIRTY_N=0

CKPT="$STATE_DIR/precompact-$SESSION_ID.md"
{
  echo "Checkpoint before ${TRIGGER:-unknown} compaction"
  echo "Branch $BRANCH at $HEAD_SHA, $DIRTY_N working-tree entries."
  printf '%s\n' "$PORCELAIN" | head -12
} > "$CKPT" 2>/dev/null || true

# Warn only when there is uncommitted work that STATE.md predates.
#
# Paths come from `-z` output so there is no C-quoting to unquote and no ambiguity from spaces.
# Anything that is not a plain file (a deletion, a rename's source, a submodule) cannot be stat'd;
# those count as STALE rather than being skipped, because "I could not check" is not "it is fine".
STALE=0
if [ "$DIRTY_N" -gt 0 ]; then
  if [ ! -f "$STATE_MD" ]; then
    STALE=1
  else
    STATE_MTIME="$(mtime_of "$STATE_MD")"
    NEWEST=0
    while IFS= read -r -d '' entry; do
      f="${entry:3}"
      if [ -f "$f" ]; then
        m="$(mtime_of "$f")"
        [ "$m" -gt "$NEWEST" ] 2>/dev/null && NEWEST="$m"
      else
        STALE=1
      fi
    done < <(git status --porcelain -z -uall -- . ':(exclude).claude/.state' 2>/dev/null)
    [ "$NEWEST" -gt "$STATE_MTIME" ] 2>/dev/null && STALE=1
  fi
fi

if [ "$STALE" -eq 1 ]; then
  printf '%s\n' '{"systemMessage":"Docs/ai/STATE.md is older than the uncommitted work in this tree. Compaction is proceeding; run the project-handoff skill afterwards so a fresh session can continue."}'
else
  echo "Checkpoint written to $CKPT"
fi
exit 0
