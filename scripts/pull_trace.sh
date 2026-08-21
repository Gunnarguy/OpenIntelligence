#!/usr/bin/env bash
#
# Pull pipeline_trace.log off a connected iPhone or a booted simulator.
#
# `LoggingConfiguration.swift` has told readers to run this script since the file logger was
# written. The script did not exist. That is the failure this repo keeps repeating in a new costume:
# a documented route to evidence that quietly goes nowhere, discovered only when someone needs the
# evidence. Written 2026-08-21 after an audit of what a device trace can actually deliver.
#
# Read this before trusting what you pull:
#
#   * The trace file is a SUBSET of the Xcode console, not a superset. Both are written by the same
#     `Log.log()` call, but the file is filtered to six categories (pipeline, llm, retrieval,
#     ingestion, embedding, pipelineTrace) while the console is filtered to none. The formatted step
#     boxes (`pipelineStep`, `pipelineHeader`, `pipelineComplete`, `section`, `box`) are
#     console-only and never reach this file. If you have the Mac attached, the console is strictly
#     better; this script is for when you do not.
#   * Only the `▶ QUERY:` / `◀ QUERY COMPLETE:` separators exist here and not in the console.
#   * A Release or TestFlight build writes NOTHING. `_fileLogEnabled`, the `.error` default level,
#     the empty category set and `#if DEBUG` are four independent gates and all are closed. If this
#     script returns an empty or stale file, check the build configuration before anything else.
#   * `pipeline_trace.prev.log` is fetched too when present. Rotation happens on the first log line
#     after launch, so the session you care about is often in `.prev` rather than the live file —
#     relaunching the app to go and share the trace is exactly what rotates it.
#
# Usage:
#   scripts/pull_trace.sh                 # auto-detect: device first, then booted simulator
#   scripts/pull_trace.sh --simulator     # force simulator
#   scripts/pull_trace.sh --device        # force physical device
#   scripts/pull_trace.sh --out DIR       # destination (default: Xrays/)

set -euo pipefail

BUNDLE_ID="Gunndamental.OpenIntelligence"
DEVELOPER_DIR_DEFAULT="/Applications/Xcode-beta.app/Contents/Developer"
OUT_DIR="Xrays"
MODE="auto"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --simulator) MODE="simulator"; shift ;;
        --device)    MODE="device"; shift ;;
        --out)       OUT_DIR="$2"; shift 2 ;;
        -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-$DEVELOPER_DIR_DEFAULT}"
mkdir -p "$OUT_DIR"

stamp() { date +%Y%m%d-%H%M%S; }

report() {
    local path="$1"
    if [[ -s "$path" ]]; then
        printf '  %s  (%s, %s lines)\n' "$path" \
            "$(du -h "$path" | cut -f1)" "$(wc -l < "$path" | tr -d ' ')"
    else
        printf '  %s  (EMPTY — see the Release-build note at the top of this script)\n' "$path"
    fi
}

pull_simulator() {
    local udid container dest
    udid=$(xcrun simctl list devices booted -j 2>/dev/null \
        | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for v in d.values() for x in v if x.get("state")=="Booted"),""))')
    [[ -n "$udid" ]] || return 1
    container=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null) || return 1
    local found=1
    for name in pipeline_trace.log pipeline_trace.prev.log; do
        if [[ -f "$container/Documents/$name" ]]; then
            dest="$OUT_DIR/$(stamp)-sim-$name"
            cp "$container/Documents/$name" "$dest"
            report "$dest"
            found=0
        fi
    done
    return $found
}

pull_device() {
    local udid dest
    udid=$(xcrun devicectl list devices -j /dev/stdout 2>/dev/null \
        | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
ds=d.get("result",{}).get("devices",[])
print(next((x["identifier"] for x in ds
            if x.get("connectionProperties",{}).get("tunnelState") in ("connected","available")), ""))' 2>/dev/null) || return 1
    [[ -n "$udid" ]] || return 1
    local found=1
    for name in pipeline_trace.log pipeline_trace.prev.log; do
        dest="$OUT_DIR/$(stamp)-device-$name"
        if xcrun devicectl device copy from --device "$udid" \
                --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
                --source "Documents/$name" --destination "$dest" >/dev/null 2>&1; then
            report "$dest"
            found=0
        fi
    done
    return $found
}

echo "Pulling pipeline trace (bundle: $BUNDLE_ID)"

case "$MODE" in
    simulator) pull_simulator || { echo "No booted simulator with the app installed." >&2; exit 1; } ;;
    device)    pull_device    || { echo "No connected device, or the app is not installed on it." >&2; exit 1; } ;;
    auto)
        if pull_device; then :;
        elif pull_simulator; then :;
        else
            cat >&2 <<'EOF'
Found no trace on a device or a booted simulator.

Check, in this order:
  1. Is the build Debug? A Release or TestFlight build writes no trace at all.
  2. Has the app actually ingested or queried since launch? The file is created lazily,
     on the first log line in one of the six file-logged categories.
  3. Is the device unlocked and trusted, or the simulator booted?

With UIFileSharingEnabled set (2026-08-21) you can also get the file without this script:
Files app -> On My iPhone -> OpenIntelligence -> pipeline_trace.log.
EOF
            exit 1
        fi
        ;;
esac

echo "Done. Remember: the Xcode console is a superset of this file when you have the Mac attached."
