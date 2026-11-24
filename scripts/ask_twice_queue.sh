#!/bin/bash
# A queue of ask-twice runs, unattended (2026-11-23, first used for the 5.9 fixes).
# usage: bash scripts/ask_twice_queue.sh REF TAG "ENV=VAL ..." mode:sampling:repeat [mode:sampling:repeat ...]
#   FIXTURES_FROM=<ref> in the environment passes --fixtures-from to every run.
# Logs to $OI_QUEUE_DIR/queue.log (default ~/Library/Developer/OpenIntelligence-evidence/ask-twice-queue), one .out per
# run, and the tag's report to report-TAG.txt. Run it in a Terminal tab (it survives the session), never with nohup.
# Each step is one ask_twice.py run of REF under --tag TAG, with the extra environment given (for example
# TEST_RUNNER_OI_EVAL_MEMORY=keep). Skips a step that exists and is complete; waits while a game is open or the
# disk is under 10 GiB free; three attempts a step; 30-hour deadline.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF="$1"; TAG="$2"; EXTRA="$3"; shift 3
Q="${OI_QUEUE_DIR:-$HOME/Library/Developer/OpenIntelligence-evidence/ask-twice-queue}"; mkdir -p "$Q"
LOG="$Q/queue.log"
PY="${OI_PYTHON:-$(command -v python3)}"
DEADLINE=$(( $(date +%s) + 30 * 3600 ))
cd "$REPO" || exit 1
[ -n "$REF" ] && [ -n "$TAG" ] || { echo "give the commit and tag" >> "$LOG"; exit 1; }
for kv in $EXTRA; do export "$kv"; done
log() { echo "[$(date '+%m-%d %H:%M:%S')] [$TAG] $*" >> "$LOG"; }
game() { ps -axo comm= | grep -Eq '(World of Warcraft|League of Legends)\.app/Contents/MacOS/'; }
step() {
  local mode=$1 sampling=$2 repeat=$3 tries=0 diskwaits=0 free code
  while :; do
    if "$PY" scripts/ask_twice.py run --mode "$mode" --sampling "$sampling" --repeat "$repeat" --ref "$REF" --tag "$TAG" --dry-run 2> /dev/null | grep -q "exists and is complete"; then
      log "STEP DONE $mode $sampling"; return 0
    fi
    [ "$(date +%s)" -gt "$DEADLINE" ] && { log "STEP SKIPPED $mode $sampling: deadline passed"; return 1; }
    [ "$tries" -ge 3 ] && { log "STEP SKIPPED $mode $sampling: 3 attempts without a complete run"; return 1; }
    if game; then log "WAIT game open ($mode $sampling)"; sleep 300; continue; fi
    free=$(df -g / | awk 'NR==2 {print $4}')
    if [ "${free:-0}" -lt 10 ]; then
      diskwaits=$((diskwaits + 1))
      [ "$diskwaits" -ge 36 ] && { log "STEP SKIPPED $mode $sampling: under 10 GiB free for 6 hours"; return 1; }
      log "WAIT disk ${free} GiB free ($mode $sampling)"; sleep 600; continue
    fi
    log "RUN $mode $sampling repeat=$repeat ref ${REF:0:8} env [$EXTRA]"
    "$HOME/.agents/bin/buildlock" --wait 120 --name "oi ask twice $mode $sampling $TAG" -- \
      "$PY" scripts/ask_twice.py run --mode "$mode" --sampling "$sampling" --repeat "$repeat" --ref "$REF" --tag "$TAG" ${FIXTURES_FROM:+--fixtures-from "$FIXTURES_FROM"} >> "$Q/$mode-$sampling-$TAG.out" 2>&1
    code=$?
    tries=$((tries + 1))
    if [ "$code" -eq 0 ]; then log "RUN ENDED $mode $sampling (exit 0, attempt $tries)"; else log "RUN FAILED $mode $sampling: exit $code (attempt $tries)"; sleep 120; fi
  done
}
export OI_TWICE_MIN_FREE_GIB=10 OI_BENCH_MIN_FREE_GB=10
log "QUEUE START pid $$ ref ${REF:0:8}"
for s in "$@"; do IFS=: read -r m sm r <<< "$s"; step "$m" "$sm" "$r"; done
"$PY" scripts/ask_twice.py report --tag "$TAG" > "$Q/report-$TAG.txt" 2>&1
log "QUEUE DONE"
