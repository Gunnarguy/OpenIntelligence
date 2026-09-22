#!/bin/bash
#
# Tests for .claude/hooks/stop-handoff.sh.
#
# Drives the real hook against a throwaway git repository that this script builds under $TMPDIR, so
# the result cannot depend on where this checkout's HEAD is, on what it has uncommitted, or on what
# its .claude/.state holds. The only files read from the checkout are the ones under test: the hook,
# the helpers it sources or calls (.claude/hooks/, scripts/required_docs.sh,
# scripts/instructions_report.sh) and the path-scoped rules in .claude/rules/. Nothing in the
# checkout is written.
#
# The fixture has two commits and a clean tree. The first holds copies of those files and a
# Docs/ai/STATE.md. The second adds one Swift file under OpenIntelligence/Services/Document/, a path
# with required documents and a governing rule (ingestion-and-indexing.md), and nothing else. A
# baseline at the first commit is therefore a session that changed Swift and none of its documents,
# whatever the real repository has done since. The RepoOS router is not copied, so
# required_docs.sh answers from its own table.
#
# Why a fixture (2026-09-21). The first version pointed its baselines at a real commit: the newest
# of the last 80 whose diff to HEAD held Swift under Services/. As HEAD moved, that range came to
# hold the documents its Swift required, because this repository commits them together, so the
# documentation case failed while the hook was right. The same drift left no Services/Document/
# file in the range, so the InstructionsLoaded case lost the path it depends on. And the hook unions
# `git status` into what a session touched, so every uncommitted doc edit in the checkout counted too.
#
# Each case asserts on the hook's JSON output: an empty stdout means "did not block", a
# `decision: block` payload means it asked, and the reason text says which obligations it found.
#
# Run: bash scripts/test_stop_handoff.sh

set -uo pipefail

CHECKOUT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
HOOK="$CHECKOUT/.claude/hooks/stop-handoff.sh"

# ROOT is the fixture: the project directory the hook sees. It is the physical path because
# instructions_report.sh relativises logged files against `git rev-parse --show-toplevel`, which
# resolves /var to /private/var; a log written with the other spelling reads as nothing loaded.
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test_stop_handoff.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT
ROOT="$(cd "$ROOT" && pwd -P)" || exit 1
export CLAUDE_PROJECT_DIR="$ROOT"
STATE_DIR="$ROOT/.claude/.state"

PASS=0
FAIL=0

fixture_git() {
  git -C "$ROOT" -c user.name=test_stop_handoff -c user.email=test_stop_handoff@invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

build_fixture() {
  mkdir -p "$ROOT/.claude" "$ROOT/scripts" "$ROOT/Docs/ai" "$STATE_DIR" &&
    cp -R "$CHECKOUT/.claude/hooks" "$ROOT/.claude/hooks" &&
    cp -R "$CHECKOUT/.claude/rules" "$ROOT/.claude/rules" &&
    cp -p "$CHECKOUT/scripts/required_docs.sh" "$CHECKOUT/scripts/instructions_report.sh" "$ROOT/scripts/" &&
    printf '.claude/.state/\n' > "$ROOT/.gitignore" &&
    printf '# STATE\n\nFixture for scripts/test_stop_handoff.sh.\n' > "$ROOT/Docs/ai/STATE.md" &&
    git -c init.defaultBranch=main init -q "$ROOT" &&
    fixture_git add .gitignore .claude/hooks .claude/rules scripts Docs &&
    fixture_git commit -q -m "fixture: the hook's helpers and rules, no source" &&
    mkdir -p "$ROOT/OpenIntelligence/Services/Document" &&
    printf 'struct StopHandoffFixture {}\n' > "$ROOT/OpenIntelligence/Services/Document/StopHandoffFixture.swift" &&
    fixture_git add OpenIntelligence &&
    fixture_git commit -q -m "fixture: one Swift change under Services/Document/, none of its documents"
}
build_fixture || { echo "cannot build the fixture repository at $ROOT" >&2; exit 1; }
cd "$ROOT" || exit 1

# The commit before the Swift change, so a baseline pointing at it makes the hook see a session that
# changed source and nothing else.
SWIFT_BASE="$(fixture_git rev-parse HEAD~1)" || exit 1

# new_session <name> <head> <state_mtime> <fingerprint>
#
# Sets the global $id rather than printing it, so it is never called in a subshell. The first version
# was called as `id="$(new_session ...)"`, its bookkeeping never reached the parent, and the cleanup
# trap left eight baseline files and a receipt in the real .claude/.state/ after every run. All state
# now lives in the fixture, which the trap deletes whole.
new_session() {
  id="test-$1"
  local head="$2" mtime="$3" fp="$4"
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

# --- the InstructionsLoaded addendum ---------------------------------------
#
# The fixture's commit range changes a file under Services/Document/, which .claude/rules/
# ingestion-and-indexing.md governs. A log that does not mention that rule should produce the
# addendum; a log that does should not; and no log at all should stay silent, because an absent log
# means the hook was never registered rather than that nothing loaded.
new_session instr-missing "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
echo '{"file":"'"$ROOT"'/CLAUDE.md","load_reason":"session_start","memory_type":"Project","trigger":"","globs":[],"parent":""}' > "$STATE_DIR/instructions-$id.log"
check "$id" blocked "a rule governing the changed code that never loaded is reported" "ingestion-and-indexing.md"

new_session instr-present "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
echo '{"file":"'"$ROOT"'/.claude/rules/ingestion-and-indexing.md","load_reason":"path_glob_match","memory_type":"Project","trigger":"x","globs":[],"parent":""}' > "$STATE_DIR/instructions-$id.log"
out="$(run_hook "$id")"
if printf '%s' "$out" | grep -q "ingestion-and-indexing.md"; then
  FAIL=$((FAIL + 1)); echo "  FAIL  a rule that did load is not reported as missing"
else
  PASS=$((PASS + 1)); echo "  ok    a rule that did load is not reported as missing"
fi

new_session instr-nolog "$SWIFT_BASE" "$FUTURE" "definitely-not-the-current-fingerprint"
rm -f "$STATE_DIR/instructions-$id.log"
out="$(run_hook "$id")"
if printf '%s' "$out" | grep -q "never appear in the InstructionsLoaded log"; then
  FAIL=$((FAIL + 1)); echo "  FAIL  a session with no log is silent about unloaded rules"
else
  PASS=$((PASS + 1)); echo "  ok    a session with no log is silent about unloaded rules"
fi

new_session no-baseline-head "" "$FUTURE" "definitely-not-the-current-fingerprint"
check "$id" blocked "a pre-2026-08-28 baseline still asks for the handoff" "Docs/ai/STATE.md was not updated"
out="$(run_hook "$id")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
