#!/usr/bin/env bash
set -uo pipefail

# ==============================================================================
# Watch a running quality-matrix run for DEFECT SIGNATURES, per case, as they land.
#
#   scripts/watch_benchmark_defects.sh <results.jsonl> <harness-log> [expected-cases]
#
# Why this exists, and why it watches shapes rather than completion:
#
#   On 2026-08-15 a watcher was attached to a benchmark run that reported only
#   terminal states. A defect was visible in case 1 at minute 4, the on-device
#   model echoing the prompt's own search placeholder, and it went unread until
#   three cases had burned. The correction cycle was a full run, roughly three
#   hours, per fix. Watching for failure SHAPES instead cut that to about
#   twenty-five minutes and caught four separate defects the same afternoon,
#   including a guard that had been applied to only one of two call sites.
#
#   Pair it with a small run. `--limit 6` answers most questions, and the full
#   set only needs to run once the smoke is clean.
#
# Output policy: a line per DEFECTIVE case, a heartbeat every 10 clean cases,
# and every terminal state. Silence means healthy, never "probably still fine",
# because a filter that matches only the happy path is silent through a crash
# and silence then looks identical to progress.
#
# Signatures, each traced to a real defect found by it:
#   PLACEHOLDER-SEARCH  the model echoed "[SEARCH: query]" instead of search terms
#   FORCED-SYNTHESIS    recursive research exhausted its iterations
#   ANSWER-REPLACED     the verification loop overwrote an answer it already had
#   PARSING-ERROR       GeneratedContent.ParsingError, carries the raw model output
#   EMPTY-RESPONSE      a session ended producing nothing
#   DELTA-TOO-LOW       a retry returned semantically identical text
#   VERIFY-STRIKES      Self-RAG gave up after repeated failures
#   BUDGET-STOP         recursive research hit its wall-clock ceiling
#   SHORT-ANSWER        under 400 chars, the marker of a collapsed synthesis
# ==============================================================================

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <results.jsonl> <harness-log> [expected-cases]" >&2
  exit 2
fi

RESULTS="$1"
LOG="$2"
EXPECT="${3:-?}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

seen=0
clean_streak=0

while true; do
  n=$(wc -l < "$RESULTS" 2>/dev/null || echo 0)

  if [[ "$n" -gt "$seen" ]]; then
    out=$(python3 - "$RESULTS" "$seen" <<'PY' 2>/dev/null
import json, re, sys
path, seen = sys.argv[1], int(sys.argv[2])
rows = [json.loads(l) for l in open(path) if l.strip()]
SIGNATURES = [
    ("PLACEHOLDER-SEARCH", r"LLM requested search: query\b"),
    ("FORCED-SYNTHESIS",   r"Reached max iterations"),
    ("ANSWER-REPLACED",    r"Answer replaced"),
    ("PARSING-ERROR",      r"GeneratedContent\.ParsingError"),
    ("EMPTY-RESPONSE",     r"without producing a response|Retry returned an empty"),
    ("DELTA-TOO-LOW",      r"Semantic delta too low"),
    ("VERIFY-STRIKES",     r"Max verification strikes"),
    ("BUDGET-STOP",        r"Time budget of"),
    ("GENERATION-ERROR",   r"GenerationError"),
]
for row in rows[seen:]:
    run = row.get("run") or {}
    score = row.get("score") or {}
    case = row["case_id"][-8:]
    if not run.get("ok"):
        print(f"DEFECT {case}: run failed -- {run.get('error')}")
        continue
    report = run.get("report") or ""
    answer = run.get("answer") or ""
    flags = [name for name, pattern in SIGNATURES if re.search(pattern, report)]
    if len(answer) < 400:
        flags.append(f"SHORT-ANSWER({len(answer)}c)")
    if flags:
        print(
            f"DEFECT {case}: {' '.join(flags)} | {len(answer)}c | "
            f"correct={score.get('correct')} | chunks={run.get('retrieved_chunks')}"
        )
PY
)
    if [[ -n "$out" ]]; then
      echo "$out"
      clean_streak=0
    else
      clean_streak=$(( clean_streak + n - seen ))
      if [[ "$clean_streak" -ge 10 ]]; then
        echo "OK: $n/$EXPECT cases done, last $clean_streak clean (no defect signatures)"
        clean_streak=0
      fi
    fi
    seen=$n
  fi

  if grep -qE "HARNESS_EXIT=|STANDARD_EXIT=" "$LOG" 2>/dev/null; then
    echo "RUN FINISHED: $n/$EXPECT cases in $RESULTS"
    break
  fi
  if grep -qE "Traceback|ModuleNotFound" "$LOG" 2>/dev/null; then
    echo "RUN CRASHED: $(grep -m1 -A2 Traceback "$LOG" | tr '\n' ' ' | cut -c1-180)"
    break
  fi
  # A harness that vanished without recording an exit is a stall, not a finish.
  if ! pgrep -f run_quality_matrix.py >/dev/null 2>&1; then
    sleep 60
    if ! pgrep -f run_quality_matrix.py >/dev/null 2>&1 \
       && ! grep -qE "HARNESS_EXIT=|STANDARD_EXIT=" "$LOG" 2>/dev/null; then
      echo "RUN STALLED: harness gone at $n/$EXPECT with no exit recorded"
      break
    fi
  fi

  sleep 45
done
