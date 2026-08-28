#!/bin/bash
#
# Tests for .claude/hooks/stop-handoff.sh.
#
# Drives the real hook with synthetic session baselines under .claude/.state/, which is gitignored
# scratch space the hooks own. Nothing in the repository is modified. Each case asserts on the
# hook's JSON output: an empty stdout means "did not block", a `decision: block` payload means it
# asked, and the reason text says which obligations it found.
#
# Run: bash scripts/test_stop_handoff.sh

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1
export CLAUDE_PROJECT_DIR="$ROOT"
HOOK="$ROOT/.claude/hooks/stop-handoff.sh"
STATE_DIR="$ROOT/.claude/.state"
mkdir -p "$STATE_DIR"

PASS=0
FAIL=0
SESSIONS=()
cleanup() { for s in ${SESSIONS[@]+"${SESSIONS[@]}"}; do rm -f "$STATE_DIR/session-$s.baseline" "$STATE_DIR/handoff-$s.done" "$STATE_DIR/notion-$s.receipts"; done; }
trap cleanup EXIT

# A commit whose diff to HEAD contains Swift under Services/, so a baseline pointing at it makes the
# hook see a session that changed source. Chosen dynamically: hardcoding a sha would rot.
SWIFT_BASE="$(for c in $(git log --format=%H -80); do
  if git diff --name-only "$c" HEAD 2>/dev/null | grep -qE 'OpenIntelligence/Services/.*\.swift$'; then echo "$c"; break; fi
done)"
if [ -z "$SWIFT_BASE" ]; then
  echo "cannot test: no commit in the last 80 has Swift changes against HEAD" >&2
  exit 1
fi

# new_session <name> <head> <state_mtime> <fingerprint>
#
# Sets the global $id rather than printing it. The first version was called as `id="$(new_session
# ...)"`, which runs the function in a SUBSHELL, so its `SESSIONS+=(...)` never reached the parent
# and the cleanup trap deleted nothing. Eight baseline files and a receipt were left behind in
# .claude/.state/ after every run.
new_session() {
  id="test-$1"
  local head="$2" mtime="$3" fp="$4"
  SESSIONS+=("$id")
  rm -f "$STATE_DIR/handoff-$id.done" "$STATE_DIR/notion-$id.receipts"
  {
    echo "fingerprint=$fp"
    echo "state_mtime=$mtime"
    echo "head=$head"
  } > "$STATE_DIR/session-$id.baseline"
}

run_hook() {
  printf '{"session_id":"%s","hook_event_name":"Stop"}' "$1" | bash "$HOOK" 2>/dev/null
}

# check <session> <blocked|quiet> <name> [<substring required in the reason>]
check() {
  local id="$1" expect="$2" name="$3" must="${4:-}" out reason ok=1
  out="$(run_hook "$id")"
  if [ "$expect" = "quiet" ]; then
    [ -n "$out" ] && ok=0
  else
    printf '%s' "$out" | grep -q '"decision"' || ok=0
    if [ -n "$must" ]; then
      reason="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("reason",""))' 2>/dev/null)"
      printf '%s' "$reason" | grep -qF "$must" || ok=0
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS + 1)); printf '  ok    %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$name"; printf '%s\n' "$out" | sed 's/^/          /'
  fi
}

CURRENT_FP="$(
  . "$ROOT/.claude/hooks/lib.sh"
  repo_fingerprint
)"
HEAD_SHA="$(git rev-parse HEAD)"
FUTURE=9999999999
PAST=1

echo "stop-handoff.sh"

new_session unchanged "$HEAD_SHA" "$FUTURE" "$CURRENT_FP"
check "$id" quiet "a session that changed nothing is never blocked"

new_session handoff-only "$HEAD_SHA" "$FUTURE" "definitely-not-the-current-fingerprint"
check "$id" blocked "a changed session with a stale STATE.md is asked for a handoff" "Docs/ai/STATE.md was not updated"

new_session state-written "$HEAD_SHA" "$PAST" "definitely-not-the-current-fingerprint"
sed -i '' "s/^state_mtime=.*/state_mtime=$PAST/" "$STATE_DIR/session-$id.baseline"
out="$(run_hook "$id")"
if printf '%s' "$out" | grep -q "STATE.md was not updated"; then
  FAIL=$((FAIL + 1)); echo "  FAIL  a session that wrote STATE.md is not asked for a handoff"
else
  PASS=$((PASS + 1)); echo "  ok    a session that wrote STATE.md is not asked for a handoff"
fi

new_session docs "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
check "$id" blocked "a session that changed Swift without its docs is told which docs" "Source changed but these documents did not"

new_session roadmap "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
check "$id" blocked "a session that changed Swift with no Notion write is asked for the roadmap" "no Notion write was recorded"

new_session receipted "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
echo '{"tool":"mcp__x__notion-update-page","database":"openintelligence-roadmap"}' > "$STATE_DIR/notion-$id.receipts"
out="$(run_hook "$id")"
if printf '%s' "$out" | grep -q "no Notion write was recorded"; then
  FAIL=$((FAIL + 1)); echo "  FAIL  a recorded Notion write drops the roadmap obligation"
else
  PASS=$((PASS + 1)); echo "  ok    a recorded Notion write drops the roadmap obligation"
fi

new_session once "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
run_hook "$id" > /dev/null
check "$id" quiet "the block fires at most once per session"

new_session no-baseline-head "" "$FUTURE" "definitely-not-the-current-fingerprint"
check "$id" blocked "a pre-2026-08-28 baseline still asks for the handoff" "Docs/ai/STATE.md was not updated"
out="$(run_hook "$id")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
