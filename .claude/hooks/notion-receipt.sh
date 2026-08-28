#!/usr/bin/env bash
# Context OS: record a receipt when a Notion write actually lands.
#
# Registered on PostToolUse against the Notion MCP write tools. PostToolUse fires only after a tool
# returns without erroring -- a failure goes to PostToolUseFailure instead -- so reaching this hook
# already means the call was made and did not throw. That is the property the receipt records, and
# it is the one thing "did you update Notion?" could never establish by asking.
#
# Three things a receipt deliberately is NOT:
#
#   * Not a read. Only the write tools are matched, so querying the roadmap leaves no receipt. The
#     skill's whole point is that reading the board is not the same as recording work on it.
#   * Not proof the right row moved. `notion-update-page` takes a page URL, not a database, so for
#     an update the database is usually unknowable from the payload alone. The receipt says
#     `database=unconfirmed` in that case rather than implying more than it saw.
#   * Not a gate. Nothing here blocks anything. The Stop hook reads these files and asks a question;
#     a receipt's absence is a prompt, never a refusal.
#
# Never fails a tool call. Every path exits 0.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "${ROOT:-}" ] && [ -d "$ROOT" ] || exit 0

STATE_DIR="$ROOT/.claude/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

HOOK_STDIN="$(cat 2>/dev/null || true)"
[ -n "$HOOK_STDIN" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# The payload goes through a temp file, not a pipe. `python3 - <<PY` takes its PROGRAM from the
# heredoc, which claims stdin, so a piped payload arrives at an already-exhausted sys.stdin and
# every call silently parsed nothing. That is the failure this whole receipt system exists to catch,
# so it would have been a fitting way to ship it broken.
PAYLOAD="$(mktemp -t oi_notion_hook)" || exit 0
trap 'rm -f "$PAYLOAD"' EXIT
printf '%s' "$HOOK_STDIN" > "$PAYLOAD" 2>/dev/null || exit 0

python3 - "$STATE_DIR" "$PAYLOAD" <<'PY' 2>/dev/null || exit 0
import json, os, sys

# The OpenIntelligence roadmap, hardcoded for the same reason the notion-roadmap skill hardcodes it:
# other databases in this workspace have similar-looking rows and locating it by search has already
# produced a wrong answer once.
DATABASE = "37f49a74-d54f-81b7-9424-dae1288c0043"
DATA_SOURCE = "37f49a74-d54f-81b0-92d9-000bce5e05fa"

state_dir, payload_path = sys.argv[1], sys.argv[2]
try:
    with open(payload_path, encoding="utf-8") as fh:
        payload = json.load(fh)
except Exception:
    sys.exit(0)

session = str(payload.get("session_id") or "unknown")
tool = str(payload.get("tool_name") or "")
if "notion" not in tool.lower():
    sys.exit(0)

blob = json.dumps(
    {"i": payload.get("tool_input"), "r": payload.get("tool_response")},
    default=str,
)

# Both ids share a prefix and differ only in one segment, so either one appearing is enough to say
# this write touched the roadmap database rather than some other Notion page.
database = (
    "openintelligence-roadmap"
    if (DATABASE in blob or DATA_SOURCE in blob)
    else "unconfirmed"
)

def find(*keys):
    """Value for the first of `keys` that appears anywhere in the payload.

    Keys are tried in the order given rather than "first key found while walking", so a nested
    Notion block id can never stand in for the page reference the caller actually passed.
    """
    for key in keys:
        stack = [payload.get("tool_input"), payload.get("tool_response")]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                for k, v in node.items():
                    if k == key and isinstance(v, (str, int, float)) and str(v).strip():
                        return str(v)
                    stack.append(v)
            elif isinstance(node, list):
                stack.extend(node)
    return ""

record = {
    "tool": tool,
    "database": database,
    "page": find("page_url", "page_id", "url", "pageId")[:200],
    "status": find("Status", "status")[:60],
    "target_release": find("Target Release", "target_release")[:40],
}

path = os.path.join(state_dir, "notion-%s.receipts" % session)
try:
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, sort_keys=True) + "\n")
except OSError:
    pass
PY
exit 0
