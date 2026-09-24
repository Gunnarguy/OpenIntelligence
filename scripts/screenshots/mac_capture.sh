#!/bin/zsh
# Captures the Mac listing scenes (APP_DESKTOP) from the unsigned Debug build.
#
# Usage, from the Claude desktop app's Terminal panel (not the agent's Bash tool, see below):
#   zsh scripts/screenshots/mac_capture.sh <raw_out_dir>
# then: python3 scripts/compose_store_screenshots.py <raw_out_dir> <composed_dir>
#
# Why it runs this way (2026-09-23):
# - Screen recording is granted to Claude.app. The agent's Bash tool runs under the disclaimed
#   claude-code helper, where `screencapture` says "could not create image from display". The
#   Terminal panel runs under Claude.app, where it works.
# - The window is placed at 1440x900 points on the built-in 2x display, so a window capture is
#   2880x1800. System Events does the placing; macOS asks once to let Claude control it. The
#   frame below assumes the built-in display sits left of the main one: read `NSScreen.screens`
#   and adjust BUILTIN_ORIGIN if the arrangement changes.
# - `open -g` keeps the app in the background (no focus stolen from a game); it sometimes opens
#   no window, so File > New Window is pressed through System Events until one exists.
# - `screencapture -l` captures one window. A sheet is its own window and is missed; the scenes
#   that open sheets (sources, What's New) did not present in the background, so they are left out.
# - Prerequisite: the Debug app's library holds the three samples (Documents > Import Sample
#   Workspace). If the app freezes on import, see Docs/ai/RUNBOOK.md: evicted iCloud copies in
#   ~/Documents/SampleDocuments block SampleDocumentManager's main-thread read.
set -u
OUT=${1:?usage: mac_capture.sh <raw_out_dir>}
mkdir -p "$OUT"
HERE=${0:A:h}
APP=${APP:-/private/tmp/oi-build-mac/Build/Products/Debug/OpenIntelligence.app}
BIN="$APP/Contents/MacOS/OpenIntelligence"
POS=${POS:-"-1600, 424"}   # top-left of the window in global points, on the built-in display
[[ -x $HERE/.winid ]] || swiftc -O -o "$HERE/.winid" "$HERE/winid.swift"
se() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $1) to $2" >/dev/null 2>&1; }
shoot() { # name seconds args...
  local name=$1 wait=$2; shift 2
  pkill -f "$BIN"; sleep 2
  open -g -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  sleep 5
  local pid=$(pgrep -f "$BIN" | head -1) i
  for i in 1 2 3 4 5 6; do [[ -n $("$HERE/.winid" $pid) ]] && break; se $pid 'click menu item "New Window" of menu "File" of menu bar 1'; sleep 2; done
  se $pid "set position of front window to {$POS}"; se $pid 'set size of front window to {1440, 900}'
  sleep $wait
  local wid=$("$HERE/.winid" $pid | cut -d' ' -f1)
  [[ -z $wid ]] && { echo "$name: no window"; return; }
  screencapture -x -o -l "$wid" "$OUT/mac-$name.png" && echo "$name: $(sips -g pixelWidth -g pixelHeight "$OUT/mac-$name.png" | awk '/pixel/ {printf $2" "}')"
}
shoot answer 20 --screenshot --screenshot-tab chat --screenshot-store answer
shoot refusal 20 --screenshot --screenshot-tab chat --screenshot-store refusal
shoot consent 20 --screenshot --screenshot-tab chat --screenshot-store consent
shoot atlas 25 --screenshot --screenshot-tab atlas
shoot database 15 --screenshot --screenshot-tab database
shoot settings 15 --screenshot --screenshot-tab settings
pkill -f "$BIN"
echo MAC_CAPTURE_DONE
