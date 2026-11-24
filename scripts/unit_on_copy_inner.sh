#!/bin/bash
# Run under the build lock by scripts/unit_on_copy.sh: copy the checkout (outside iCloud) now that the lock is held, then test.
# usage: copy-and-test.sh REPO SRC OUT xcodebuild-args...
REPO="$1"; SRC="$2"; OUT="$3"; shift 3
if [ -n "${OI_UNIT_REF:-}" ]; then
  # A commit instead of the working tree (2026-11-23): to tell whether a failure is older than a change.
  rm -rf "$SRC" && mkdir -p "$SRC" && git -C "$REPO" archive "$OI_UNIT_REF" | tar -x -C "$SRC"
else
  rsync -a --delete --exclude '.git' --exclude '.git.nosync' --exclude 'BenchmarkRuns' --exclude '*.nosync' --exclude 'Growth' "$REPO/" "$SRC/"
fi
xattr -cr "$SRC" 2> /dev/null
if [ -n "${OI_UNIT_REF:-}" ]; then
  echo "[$(date '+%H:%M:%S')] copied commit $(git -C "$REPO" rev-parse --short "$OI_UNIT_REF")" >> "$OUT/summary.txt"
else
  echo "[$(date '+%H:%M:%S')] copied at $(git -C "$REPO" rev-parse --short HEAD) plus $(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') changed paths" >> "$OUT/summary.txt"
fi
exec xcodebuild test -project "$SRC/OpenIntelligence.xcodeproj" "$@"
