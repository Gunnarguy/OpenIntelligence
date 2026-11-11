#!/bin/zsh
# Records the extraction-fidelity set and the olmOCR-Bench sample once per compute profile on one build (2026-11-11).
SIM=FD71D24F-3C3D-44BC-8431-BDEE8BA07902
OUT=/private/tmp/oi-bench-profiles; mkdir -p $OUT
XCTESTRUN=$(ls -t /private/tmp/oi-test-build/Build/Products/*.xctestrun | head -1)
xcrun simctl shutdown $SIM 2>/dev/null; xcrun simctl erase $SIM; xcrun simctl boot $SIM 2>/dev/null
gtimeout 300 xcrun simctl bootstatus $SIM -b > /dev/null 2>&1
run() { # set dir list label profile
  local dir=$1 list=$2 label=$3 profile=$4
  echo "== $label $(date +%H:%M)"
  local extra=""; [ -n "$list" ] && extra="TEST_RUNNER_OI_FIDELITY_LIST=$list"
  env TEST_RUNNER_OI_FIDELITY_DIR=$dir TEST_RUNNER_OI_FIDELITY_LABEL=$label TEST_RUNNER_OI_COMPUTE_PROFILE=$profile $extra \
    gtimeout 5400 xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$SIM" \
    -only-testing:OpenIntelligenceTests/ExtractionFidelityRecorder > $OUT/$label.log 2>&1
  echo "exit $? $(grep -E 'Executed [0-9]+ test' $OUT/$label.log | tail -1)"
}
for p in balanced performance maximum; do run /private/tmp/oi-fidelity/pdfs "" prof-$p $p; done
for p in balanced performance maximum; do run /private/tmp/olmocr-bench "/private/tmp/olmocr-bench/run160.txt" prof160-$p $p; done
xcrun simctl shutdown $SIM
echo done $(date +%H:%M)
