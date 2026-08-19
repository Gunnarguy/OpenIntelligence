#!/usr/bin/env bash
# Context OS: SessionStart brief.
#
# Prints a bounded orientation brief to stdout, which Claude Code injects as context, and records a
# fingerprint of the repository so the Stop hook can tell whether this session changed anything.
# Read-only with respect to the repository; the only writes are under .claude/.state/, which is
# gitignored.
#
# Never fails a session. Every failure path exits 0 with less output.

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
SOURCE="$(hook_field source)"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

# Unborn HEAD: `git rev-parse --abbrev-ref HEAD` prints "HEAD" to stdout AND exits 128, so a
# `|| echo unknown` fallback appends a second line rather than replacing anything.
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="$(git rev-parse --short HEAD 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="unknown"
HEAD_SHA="$(git rev-parse --short HEAD 2>/dev/null)"
[ -n "$HEAD_SHA" ] || HEAD_SHA="unknown"
HEAD_SUBJ="$(git log -1 --pretty=%s 2>/dev/null | cut -c1-72)"

# Distinguish "git says the tree is clean" from "git failed and told us nothing". This repository
# lives in iCloud, where .git corruption has already happened once, and reporting a corrupt repo as
# clean is worse than reporting nothing.
if PORCELAIN="$(git status --porcelain -uall -- . ':(exclude).claude/.state' 2>/dev/null)"; then
  GIT_OK=1
else
  GIT_OK=0
  PORCELAIN=""
fi
DIRTY_N="$(count_lines "$PORCELAIN")"
[ -n "$DIRTY_N" ] || DIRTY_N=0

# Baseline for the Stop hook, written once per session.
#
# Not rewritten if it already exists: SessionStart fires again mid-session on compact, and on
# resume/clear/fork, with the SAME session_id. Overwriting would reset the baseline to the current
# state and make every change made before that point invisible to the Stop hook, which is precisely
# the work most likely to need a handoff.
BASELINE="$STATE_DIR/session-$SESSION_ID.baseline"
if [ ! -f "$BASELINE" ] && [ "$GIT_OK" -eq 1 ]; then
  {
    echo "fingerprint=$(repo_fingerprint)"
    echo "state_mtime=$(mtime_of "$STATE_MD")"
  } > "$BASELINE" 2>/dev/null || true
fi

echo "OpenIntelligence session brief (source: ${SOURCE:-unknown})"
echo "Branch $BRANCH at $HEAD_SHA  ${HEAD_SUBJ:-}"

case "$(git rev-parse --git-dir 2>/dev/null)" in
  *"/worktrees/"*) echo "This is a linked git worktree, not the primary checkout. One writer per checkout." ;;
esac

if [ "$GIT_OK" -eq 0 ]; then
  echo "Working tree: git state unavailable. Do NOT assume it is clean; run scripts/check_icloud_conflicts.sh."
elif [ "$DIRTY_N" -eq 0 ]; then
  echo "Working tree clean."
else
  echo "Working tree: $DIRTY_N entries."
  printf '%s\n' "$PORCELAIN" | head -8 | sed 's/^/  /'
  [ "$DIRTY_N" -gt 8 ] && echo "  ... $((DIRTY_N - 8)) more"
fi

if [ -f "$STATE_MD" ]; then
  # First whitespace-delimited token only. Taking the whole remainder of the line and stripping the
  # spaces out of it made any trailing prose part of the sha, so an explanatory clause added to that
  # line on 2026-08-19 turned a mild drift note into "names a commit not in this repository", which
  # reads like a corrupt or foreign checkout. The line may carry prose after the sha.
  STATE_COMMIT="$(sed -n 's/^Last verified commit:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$STATE_MD" | head -1)"
  STATE_UPDATED="$(sed -n 's/^Updated:[[:space:]]*//p' "$STATE_MD" | head -1)"
  echo "STATE.md updated ${STATE_UPDATED:-unknown}, recorded commit ${STATE_COMMIT:-none}."
  # Resolve both sides through git before comparing. A string compare of a full sha in STATE.md
  # against `rev-parse --short` always differs, which printed "HEAD has moved 0 commits" — a
  # self-contradiction injected into every session.
  if [ -n "$STATE_COMMIT" ]; then
    RESOLVED="$(git rev-parse --verify --quiet "${STATE_COMMIT}^{commit}" 2>/dev/null)"
    CURRENT="$(git rev-parse --verify --quiet HEAD 2>/dev/null)"
    if [ -z "$RESOLVED" ]; then
      echo "  STALE: STATE.md names commit $STATE_COMMIT, which is not in this repository."
    elif [ "$RESOLVED" != "$CURRENT" ]; then
      # Count only commits that changed something other than STATE.md itself. A handoff cannot record
      # the sha of the commit containing it, and follow-up docs-only edits land after that, so a
      # well-maintained handoff always trails HEAD without anything it describes having drifted.
      # This generalises the hard-coded "exactly one behind" exemption it replaces: what matters is
      # whether anything the document describes has changed, not how many commits went by.
      #
      # :(top) rather than a bare `.` because both pathspecs would otherwise resolve against the
      # working directory. The `cd "$ROOT"` above makes them equivalent here today; anchoring to the
      # repository root states the intent without depending on that.
      BEHIND="$(git rev-list --count "$RESOLVED..HEAD" -- ':(top)' ':(top,exclude)Docs/ai/STATE.md' 2>/dev/null)"
      [ -n "$BEHIND" ] && [ "$BEHIND" -gt 0 ] 2>/dev/null &&
        echo "  STALE: $BEHIND commit(s) since STATE.md was written changed something other than STATE.md. Trust git over STATE.md."
    fi
  fi
  awk '/^## Objective/{f=1;next} /^## /{f=0} f && NF' "$STATE_MD" 2>/dev/null | head -3 | sed 's/^/  Objective: /'
  awk '/^## Exact Next Action/{f=1;next} /^## /{f=0} f && NF' "$STATE_MD" 2>/dev/null | head -5 | sed 's/^/  Next: /'
  awk '/^## Blockers/{f=1;next} /^## /{f=0} f && NF' "$STATE_MD" 2>/dev/null | head -3 | sed 's/^/  Blocker: /'
else
  echo "Docs/ai/STATE.md is missing. Run the project-handoff skill to create it."
fi

# Replay this session's PreCompact checkpoint after a compaction restart.
CKPT="$STATE_DIR/precompact-$SESSION_ID.md"
if [ "$SOURCE" = "compact" ] && [ -f "$CKPT" ]; then
  echo "Pre-compaction checkpoint:"
  head -16 "$CKPT" | sed 's/^/  /'
fi

echo "Read Docs/ai/STATE.md before substantive work. Load other docs only as the task needs them."
exit 0
