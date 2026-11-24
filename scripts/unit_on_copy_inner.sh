#!/bin/bash
# Run under the build lock by scripts/unit_on_copy.sh: copy the checkout (outside iCloud) now that the lock is held, then test.
# usage: copy-and-test.sh REPO SRC OUT xcodebuild-args...
REPO="$1"; SRC="$2"; OUT="$3"; shift 3
rsync -a --delete --exclude '.git' --exclude '.git.nosync' --exclude 'BenchmarkRuns' --exclude '*.nosync' --exclude 'Growth' "$REPO/" "$SRC/"
xattr -cr "$SRC" 2> /dev/null
echo "[$(date '+%H:%M:%S')] copied at $(git -C "$REPO" rev-parse --short HEAD) plus $(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') changed paths" >> "$OUT/summary.txt"
exec xcodebuild test -project "$SRC/OpenIntelligence.xcodeproj" "$@"
