#!/usr/bin/env bash
# Context OS: record which instruction files actually reached the model.
#
# Registered on InstructionsLoaded, which fires once per CLAUDE.md, .claude/rules/*.md or imported
# file as it loads. It answers the question this repository could not previously answer: not "does
# the rule exist" but "did the rule load for the code that was actually edited".
#
# That gap is real and silent. A rule in .claude/rules/ with `paths:` frontmatter loads only when
# Claude touches a matching file. If the glob is wrong, or the file is reached some other way, the
# rule never enters context and nothing anywhere says so. The session then edits retrieval code
# having never seen the retrieval rule, and looks from the outside exactly like a session that read
# it and ignored it. Those two need telling apart before any conclusion about "it is forgetting".
#
# The payload carries more than the file path:
#   memory_type   User | Project | Local | Managed
#   load_reason   session_start | nested_traversal | path_glob_match | include | compact
#   globs         the `paths:` patterns, when the reason is path_glob_match
#   trigger_file_path  the file whose read caused the match
#
# `load_reason` is also what a matcher on this event matches against, so a future hook can watch one
# reason without seeing the rest.
#
# The log is read by .claude/hooks/stop-handoff.sh, which reports any rule that governs a path this
# session changed but never loaded. Read it yourself with scripts/instructions_report.sh.
#
# Exit code is ignored by Claude Code for this event. Never fails anything; every path exits 0.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "${ROOT:-}" ] && [ -d "$ROOT" ] || exit 0

STATE_DIR="$ROOT/.claude/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

HOOK_STDIN="$(cat 2>/dev/null || true)"
[ -n "$HOOK_STDIN" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PAYLOAD="$(mktemp -t oi_instr_hook)" || exit 0
trap 'rm -f "$PAYLOAD"' EXIT
printf '%s' "$HOOK_STDIN" > "$PAYLOAD" 2>/dev/null || exit 0

python3 - "$STATE_DIR" "$PAYLOAD" <<'PY' 2>/dev/null || exit 0
import json, os, sys

state_dir, payload_path = sys.argv[1], sys.argv[2]
try:
    with open(payload_path, encoding="utf-8") as fh:
        payload = json.load(fh)
except Exception:
    sys.exit(0)

if payload.get("hook_event_name") != "InstructionsLoaded":
    sys.exit(0)

# This event is dispatched outside the REPL loop, so session_id can be absent. Falling back to a
# shared file rather than dropping the record: a log nobody can attribute still shows that a rule
# never loaded at all, which is the more serious of the two findings.
session = str(payload.get("session_id") or "nosession")

record = {
    "file": str(payload.get("file_path") or ""),
    "memory_type": str(payload.get("memory_type") or ""),
    "load_reason": str(payload.get("load_reason") or ""),
    "trigger": str(payload.get("trigger_file_path") or ""),
    "globs": payload.get("globs") or [],
    "parent": str(payload.get("parent_file_path") or ""),
}

path = os.path.join(state_dir, "instructions-%s.log" % session)
try:
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, sort_keys=True) + "\n")
except OSError:
    pass
PY
exit 0
