#!/bin/bash
# Grade the app's answers in Standard, Deep Think and Maximum, overnight, in the iOS 27 Simulator on this Mac.
#
#   bash scripts/bench_answer_modes.sh                  # all three modes, then a Standard run with the test's model
#   bash scripts/bench_answer_modes.sh deepThink        # one mode
#
# What it does, in order (added 2026-11-11; the testing-routes skill says why this route and not the cloud):
#   1. Waits while World of Warcraft or League of Legends is running, checking every 5 minutes, so a run never takes
#      the Mac during a game (a game in front also runs timers about 14 times slow, which would spoil the timings).
#   2. Copies HEAD out of the repository (git archive), patches it with scripts/sim_model_copy.py so the app's own
#      model service answers in the Simulator, as on a phone, and syncs it by content into /private/tmp/oi-eval-src.
#   3. Builds the tests once (two jobs) into /private/tmp/oi-eval-dd: the first time a full build, later only what
#      changed.
#   4. Makes a fresh simulator, "OI answer eval", iPhone 17 Pro, iOS 27.0: nothing of the owner's is on it.
#   5. Runs AnswerQualityEvaluationTests once per mode: 20 questions over the tiny research suite, graded by Apple's
#      Evaluations model judge against reference answers. Standard takes minutes; Deep Think and Maximum hours.
#   6. Writes BenchmarkRuns/<date>-answer-modes/: <mode>.log (everything), <mode>.txt (the evaluation's own lines:
#      each question's mode, seconds and answer, then the score) and SUMMARY.md. Shuts the simulator down.
# Nothing touches the owner's libraries: the test makes and removes a library of its own on that simulator.
# Keeps the Mac awake while it runs (caffeinate). Stop it with Ctrl-C; the simulator is shut down either way.

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC=/private/tmp/oi-eval-src
DD=/private/tmp/oi-eval-dd
SIM_NAME="OI answer eval"
STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="$REPO/BenchmarkRuns/$STAMP-answer-modes"
if [ $# -gt 0 ]; then MODES=("$@"); else MODES=(standard deepThink maximum standard:test); fi
VERSION="$(grep -m1 -oE '^## [0-9]+\.[0-9]+(\.[0-9]+)?' "$REPO/CHANGELOG.md" | cut -c4-)"

mkdir -p "$OUT"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/SUMMARY.md.progress"; }

game_running() { pgrep -f 'World of Warcraft.app/Contents/MacOS|League of Legends.app/Contents/MacOS' > /dev/null; }
while game_running && [ "${OI_BENCH_IGNORE_GAMES:-0}" != 1 ]; do
  log "A game is running; waiting for it to close (checking every 5 minutes)."
  sleep 300
done
if pgrep -x xcodebuild > /dev/null; then
  log "Another xcodebuild is running; one at a time on this Mac. Stopping."
  exit 1
fi
FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
if [ "${FREE_GB:-0}" -lt 15 ]; then
  log "Only ${FREE_GB} GB free on the internal disk; the build and simulator need about 15. Stopping."
  exit 1
fi

UDID=""
cleanup() {
  if [ -n "$UDID" ]; then xcrun simctl shutdown "$UDID" > /dev/null 2>&1; fi
  [ -n "${CAFFEINATE_PID:-}" ] && kill "$CAFFEINATE_PID" 2> /dev/null
}
trap cleanup EXIT
caffeinate -dimsu -w $$ &
CAFFEINATE_PID=$!

log "Copying HEAD $(git -C "$REPO" rev-parse --short HEAD) out of the repository and patching it."
STAGE=/private/tmp/oi-eval-stage
rm -rf "$STAGE" && mkdir -p "$STAGE" "$SRC"
git -C "$REPO" archive HEAD | tar -x -C "$STAGE" || { log "git archive failed"; exit 1; }
python3 "$REPO/scripts/sim_model_copy.py" "$STAGE" | tee -a "$OUT/build.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { log "Patching failed; the line above names the switch that moved."; exit 1; }
# By content, so files that did not change keep their dates and the next run's build is incremental.
rsync -a --checksum --delete "$STAGE/" "$SRC/"

# A new simulator for every run (simulators here are deleted between sessions without notice).
for old in $(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}'); do
  xcrun simctl delete "$old" > /dev/null 2>&1
done
UDID=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0) \
  || { log "Could not create the simulator"; exit 1; }
log "Simulator $UDID. Building the tests (two jobs)."

START_BUILD=$(date +%s)
(cd "$SRC" && xcodebuild build-for-testing -project OpenIntelligence.xcodeproj -scheme OpenIntelligence \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -jobs 2 MARKETING_VERSION="$VERSION" -quiet) \
  >> "$OUT/build.log" 2>&1
if [ $? -ne 0 ]; then
  log "The build failed; the end of $OUT/build.log says why."
  tail -20 "$OUT/build.log"
  exit 1
fi
log "Built in $(( ($(date +%s) - START_BUILD) / 60 )) minutes."

xcrun simctl boot "$UDID" > /dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1

{
  echo "# Answer quality by mode, $STAMP"
  echo
  echo "Commit $(git -C "$REPO" rev-parse --short HEAD), version $VERSION, iOS 27.0 Simulator (iPhone 17 Pro, read as an A18 Pro),"
  echo "patched copy (scripts/sim_model_copy.py), 20 cases of Benchmarks/rag_eval_v1.jsonl, graded by Apple's Evaluations model judge."
  echo "\"app\" is the app's own model service, the phone's path; \"test\" is the test's own model, the path of the 2026-10-21 runs (0.3)."
  echo
  echo "| Mode | Model | Correct | Answered | Refused | Minutes | Result |"
  echo "|---|---|---|---|---|---|---|"
} > "$OUT/SUMMARY.md"

for entry in "${MODES[@]}"; do
  mode="${entry%%:*}"
  model=app
  [ "$entry" != "$mode" ] && model="${entry#*:}"
  name="$mode-$model"
  log "Running $mode with the $model model."
  START=$(date +%s)
  env_model=()
  [ "$model" = app ] && env_model=(TEST_RUNNER_OI_EVAL_MODEL=app)
  env TEST_RUNNER_OI_MODEL_EVALS=1 TEST_RUNNER_OI_EVAL_MODE="$mode" ${env_model[@]+"${env_model[@]}"} \
    xcodebuild test-without-building -project "$SRC/OpenIntelligence.xcodeproj" -scheme OpenIntelligence \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
    -only-testing:OpenIntelligenceTests/AnswerQualityEvaluationTests > "$OUT/$name.log" 2>&1
  status=$?
  minutes=$(( ($(date +%s) - START) / 60 ))
  grep -a '\[AnswerQualityEvaluation\]' "$OUT/$name.log" > "$OUT/$name.txt"
  correct=$(grep -aoE 'correct: [0-9.-]+' "$OUT/$name.txt" | tail -1 | cut -d' ' -f2)
  answered=$(grep -ac '\] answered ' "$OUT/$name.txt")
  refused=$(grep -ac '\] refused ' "$OUT/$name.txt")
  result=$([ $status -eq 0 ] && echo passed || echo "failed (exit $status)")
  echo "| $mode | $model | ${correct:-none} | $answered | $refused | $minutes | $result |" >> "$OUT/SUMMARY.md"
  log "$mode ($model): correct ${correct:-none}, $answered answered, $refused refused, $minutes minutes, $result."
done

echo >> "$OUT/SUMMARY.md"
echo "Each question's answer and seconds: <mode>-<model>.txt. Full output: <mode>-<model>.log." >> "$OUT/SUMMARY.md"
log "Done. $OUT/SUMMARY.md"
cat "$OUT/SUMMARY.md"
