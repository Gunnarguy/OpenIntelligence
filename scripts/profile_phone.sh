#!/bin/bash
# Time Profiler on the owner's iPhone while the app is running, to name what holds the main thread.
#
#   bash scripts/profile_phone.sh [seconds]        (default 90)
#
# Start it, then do the slow thing on the phone (rebuild a library, open Chat while it runs). When the time is up
# the trace is saved outside the repository and the heaviest main-thread frames are printed.
# Needs: the phone unlocked, on the Mac's Wi-Fi, OpenIntelligence (a development build) open in front.
set -euo pipefail
SECONDS_TO_RECORD="${1:-90}"
DEVICE="${OI_PHONE_UDID:-00008140-001130DA1863C01C}"
OUT="$HOME/Library/Developer/OpenIntelligence-evidence/profile-$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$OUT"
FREE=$(df -g / | awk 'NR==2 {print $4}')
[ "$FREE" -lt 9 ] && { echo "only $FREE GB free; a trace needs about 1 GB"; exit 1; }
echo "Recording $SECONDS_TO_RECORD s on the phone. Do the slow thing now."
xcrun xctrace record --template 'Time Profiler' --device "$DEVICE" --attach OpenIntelligence \
    --time-limit "${SECONDS_TO_RECORD}s" --output "$OUT/phone.trace" --no-prompt
echo "Saved $OUT/phone.trace"
xcrun xctrace export --input "$OUT/phone.trace" --toc > "$OUT/toc.xml" 2>/dev/null || true
xcrun xctrace export --input "$OUT/phone.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$OUT/time-profile.xml" 2>/dev/null || true
echo "Exported the samples to $OUT/time-profile.xml ($(wc -c < "$OUT/time-profile.xml" 2>/dev/null || echo 0) bytes)."
echo "Open the trace in Instruments, or hand this folder to the agent to read the main thread's heaviest frames."
