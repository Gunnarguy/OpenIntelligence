#!/usr/bin/env bash
# Deep Think benchmark pilot.
#
# Purpose: get a real per-case rate for `deep-think` mode, which has never been
# benchmarked. Every run in BenchmarkRuns/ is `modes: ["standard"]`, so there is no
# baseline and no timing history for the mode that the 2026-08-18 reasoning-chain
# session cap actually changes.
#
# This is a MEASUREMENT of cost, not of quality. Three cases cannot say anything about
# accuracy. It exists so the full paired run can be estimated instead of guessed at:
# standard mode took 1h52m and 2h52m for 25 cases, and deep-think does 5-8 generations
# per query where standard does one.
#
# Constraints, both learned the hard way and recorded in Docs/ai/RUNBOOK.md:
#   - Nothing else may build or run while this measures. It has cost 20 minutes of
#     misdiagnosis twice.
#   - PCC is silently unavailable from agent shells, hence `--pcc deny`. Keep it that
#     way for comparability even when running by hand.
set -euo pipefail

APP="${APP:-/private/tmp/oi-mac-pilot/Build/Products/Debug/OpenIntelligence.app}"
LIMIT="${LIMIT:-3}"
MODES="${MODES:-deep-think}"
# Deep Think took 279s for one query on device. The harness default of 600s per run
# would truncate a slow case and silently under-report, so it is raised here.
TIMEOUT="${TIMEOUT:-1800}"
POOL="${POOL:-10}"

if [ ! -d "$APP" ]; then
  echo "error: no app at $APP" >&2
  echo "build it with:" >&2
  echo "  cd /private/tmp/oi-src && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \\" >&2
  echo "    xcodebuild -scheme OpenIntelligence -destination 'platform=macOS' -configuration Debug \\" >&2
  echo "    -derivedDataPath /private/tmp/oi-mac-pilot -skipPackagePluginValidation \\" >&2
  echo "    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build" >&2
  exit 1
fi

echo "Deep Think pilot"
echo "  app     : $APP"
echo "  cases   : $LIMIT   modes: $MODES   pool: $POOL docs   timeout: ${TIMEOUT}s/run"
echo "  started : $(date '+%H:%M:%S')"
echo
echo "Do not build, test or run anything else until this finishes."
echo

START=$(date +%s)
python3 scripts/run_quality_matrix.py \
  --app "$APP" \
  --modes "$MODES" \
  --pcc deny \
  --limit "$LIMIT" \
  --pool-limit "$POOL" \
  --timeout "$TIMEOUT"
END=$(date +%s)

ELAPSED=$(( END - START ))
PER_CASE=$(( ELAPSED / LIMIT ))
echo
echo "───────────────────────────────────────────────"
echo "pilot wall clock : ${ELAPSED}s  ($(( ELAPSED / 60 ))m)"
echo "per case         : ${PER_CASE}s"
echo "25 cases would be: $(( PER_CASE * 25 / 60 ))m  (~$(( PER_CASE * 25 / 3600 ))h)"
echo "a PAIRED run     : $(( PER_CASE * 50 / 3600 ))h   (before + after the session cap)"
echo "───────────────────────────────────────────────"
echo "Newest run dir:"
ls -1dt BenchmarkRuns/*/ | head -1
