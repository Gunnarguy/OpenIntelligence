#!/bin/bash
# Unit test classes on a scratch copy of the checkout (outside iCloud, so codesign works), on a simulator of their own,
# under the machine's build lock (2026-11-23). The copy is made once the lock is held, so it holds every edit made
# while the run waited. Never edit this file while it runs: bash reads a script as it goes.
# usage: bash scripts/unit_on_copy.sh LABEL Class1 Class2 ...   (summary in $OI_QUEUE_DIR/unit-LABEL/summary.txt)
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="$1"; shift
ROOT=/private/tmp/oi-unit
SRC=$ROOT/src; DD=$ROOT/dd
OUT="${OI_QUEUE_DIR:-$HOME/Library/Developer/OpenIntelligence-evidence/ask-twice-queue}/unit-$LABEL"
mkdir -p "$ROOT" "$OUT"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
NAME="OI unit tests"
UDID=$(xcrun simctl list devices | grep "$NAME (" | grep -oE '[0-9A-F-]{36}' | head -1)
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-27[-0-9]*' | head -1)
  UDID=$(xcrun simctl create "$NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")
fi
ONLY=()
for c in "$@"; do ONLY+=("-only-testing:OpenIntelligenceTests/$c"); done
echo "[$(date '+%H:%M:%S')] start $LABEL on $UDID: $*" > "$OUT/summary.txt"
"$HOME/.agents/bin/buildlock" --wait 180 --name "oi unit $LABEL" -- \
  bash "$REPO/scripts/unit_on_copy_inner.sh" "$REPO" "$SRC" "$OUT" -scheme OpenIntelligence \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -jobs 4 \
  -resultBundlePath "$OUT/result-$(date +%H%M%S).xcresult" "${ONLY[@]}" > "$OUT/xcodebuild.log" 2>&1
code=$?
xcrun simctl shutdown "$UDID" 2> /dev/null
{
  echo "[$(date '+%H:%M:%S')] exit $code"
  grep -E "Test Suite '.*' (passed|failed)|Executed [0-9]+ tests|error:|\*\* TEST" "$OUT/xcodebuild.log" | tail -40
  grep -E "XCTAssert|failed \(" "$OUT/xcodebuild.log" | grep -v 'passed' | head -40
} >> "$OUT/summary.txt"
echo "UNIT DONE $LABEL exit $code" >> "$OUT/summary.txt"
