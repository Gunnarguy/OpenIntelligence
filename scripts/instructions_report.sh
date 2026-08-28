#!/bin/bash
#
# What instruction files loaded this session, and which ones should have but did not.
#
# Reads the log written by .claude/hooks/instructions-loaded.sh. Repository-relative paths to
# consider are read from stdin, one per line; with no stdin it uses the current working tree.
#
#   bash scripts/instructions_report.sh                  # human summary for the newest session
#   bash scripts/instructions_report.sh --session <id>   # a specific session
#   bash scripts/instructions_report.sh --unloaded       # just the rules that never loaded
#
# The second question is the one worth asking. A rule in .claude/rules/ with `paths:` frontmatter
# enters context only when Claude touches a matching file. If the glob is wrong, or the file was
# reached some way that did not trigger a match, the rule never loads and nothing says so. From the
# outside that is indistinguishable from a session that read the rule and ignored it. This tells
# them apart.
#
# A caveat this cannot resolve on its own: the log only covers loads that happened after the hook
# was registered, and a rule loaded inside a subagent is not recorded against this session. Treat an
# "unloaded" line as a question to check, not a proven miss.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0

STATE_DIR="$REPO_ROOT/.claude/.state"
SESSION=""
MODE="summary"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session) SESSION="${2:-}"; shift 2 ;;
    --unloaded) MODE="unloaded"; shift ;;
    *) shift ;;
  esac
done

if [ -n "$SESSION" ]; then
  LOG="$STATE_DIR/instructions-$SESSION.log"
else
  LOG="$(ls -t "$STATE_DIR"/instructions-*.log 2>/dev/null | head -1)"
fi

PATHS="$(cat 2>/dev/null || true)"
if [ -z "$PATHS" ]; then
  PATHS="$(git status --porcelain -uall -- . ':(exclude).claude/.state' 2>/dev/null |
    sed -n 's/^...//p' | sed 's/.* -> //')"
fi

command -v python3 >/dev/null 2>&1 || exit 0

# The path list goes through a file, not a pipe. `python3 - <<PY` takes its PROGRAM from the
# heredoc, which claims stdin, so a piped list arrives at an exhausted sys.stdin and every path
# silently vanishes. The first version of this script reported "0 changed paths" for every input.
PATHS_FILE="$(mktemp -t oi_instr_paths)" || exit 0
trap 'rm -f "$PATHS_FILE"' EXIT
printf '%s\n' "$PATHS" > "$PATHS_FILE"

python3 - "${LOG:-}" "$REPO_ROOT" "$MODE" "$PATHS_FILE" <<'PY'
import json, os, re, sys

log_path, repo_root, mode, paths_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(paths_file, encoding="utf-8") as fh:
    changed = [p.strip() for p in fh.read().splitlines() if p.strip()]

def glob_to_regex(pattern):
    """Translate a Claude Code `paths:` glob to a regex.

    `**` crosses directory separators, `*` does not. `**/` is optional so that `**/*.storekit`
    matches a file at the repository root as well as a nested one.
    """
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?"); i += 3
        elif pattern.startswith("**", i):
            out.append(".*"); i += 2
        elif pattern[i] == "*":
            out.append("[^/]*"); i += 1
        elif pattern[i] == "?":
            out.append("[^/]"); i += 1
        else:
            out.append(re.escape(pattern[i])); i += 1
    return re.compile("^" + "".join(out) + "$")

def rule_globs():
    """Every .claude/rules/*.md with `paths:` frontmatter, mapped to its patterns."""
    rules = {}
    rules_dir = os.path.join(repo_root, ".claude", "rules")
    for name in sorted(os.listdir(rules_dir)) if os.path.isdir(rules_dir) else []:
        if not name.endswith(".md"):
            continue
        full = os.path.join(rules_dir, name)
        try:
            lines = open(full, encoding="utf-8").read().splitlines()
        except OSError:
            continue
        if not lines or lines[0].strip() != "---":
            continue
        try:
            end = lines.index("---", 1)
        except ValueError:
            continue
        patterns, in_paths = [], False
        for line in lines[1:end]:
            if line.startswith("paths:"):
                in_paths = True
            elif in_paths and line.lstrip().startswith("- "):
                patterns.append(line.lstrip()[2:].strip().strip('"').strip("'"))
            elif in_paths and line.strip() and not line.startswith(" "):
                in_paths = False
        if patterns:
            rules[os.path.join(".claude", "rules", name)] = patterns
    return rules

loaded = []
if log_path and os.path.isfile(log_path):
    for line in open(log_path, encoding="utf-8"):
        try:
            loaded.append(json.loads(line))
        except ValueError:
            pass

def rel(p):
    return os.path.relpath(p, repo_root) if p.startswith(repo_root) else p

loaded_files = {rel(r.get("file", "")) for r in loaded}

rules = rule_globs()
expected = {}
for rule, patterns in rules.items():
    regexes = [glob_to_regex(p) for p in patterns]
    hits = [c for c in changed if any(rx.match(c) for rx in regexes)]
    if hits:
        expected[rule] = hits

unloaded = {r: h for r, h in expected.items() if r not in loaded_files}

if mode == "unloaded":
    # No log at all means the hook was not registered for this session, not that nothing loaded.
    # Without this guard every matching rule reads as "never loaded" for every session that predates
    # the hook, which is the loudest possible way to say nothing.
    if not log_path or not os.path.isfile(log_path):
        sys.exit(0)
    for rule in sorted(unloaded):
        print(rule)
    sys.exit(0)

if not log_path or not os.path.isfile(log_path):
    print("No InstructionsLoaded log found. The hook records one only for sessions that ran with")
    print("it registered in .claude/settings.json.")
else:
    print("Instruction files loaded (%s):" % os.path.basename(log_path))
    for r in loaded:
        line = "  %-16s %-8s %s" % (r.get("load_reason", ""), r.get("memory_type", ""), rel(r.get("file", "")))
        if r.get("trigger"):
            line += "\n%s triggered by %s" % (" " * 28, rel(r["trigger"]))
        print(line)
    if not loaded:
        print("  (none)")

print()
print("Path-scoped rules matching the %d changed path(s):" % len(changed))
if not expected:
    print("  (none match)")
for rule in sorted(expected):
    status = "LOADED    " if rule in loaded_files else "NOT LOADED"
    print("  %s %s" % (status, rule))
    for h in expected[rule][:3]:
        print("             matched %s" % h)
    if len(expected[rule]) > 3:
        print("             ... and %d more" % (len(expected[rule]) - 3))

if unloaded:
    print()
    print("A rule governing code this session changed did not load. Either its `paths:` globs are")
    print("wrong, or the file was reached without triggering a match. Check before concluding the")
    print("rule was read and ignored.")
PY
