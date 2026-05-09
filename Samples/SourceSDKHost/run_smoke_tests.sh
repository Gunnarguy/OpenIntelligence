#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_FILE="$ROOT_DIR/SourceSDKHost.xcodeproj"
BUILD_SCRIPT="$ROOT_DIR/build_sample_app.sh"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenIntelligenceEngine-SourceSDKHost}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/SourceSDKHost.app"
BUNDLE_ID="${BUNDLE_ID:-Gunndamental.SourceSDKHost}"
SMOKE_RESULT_FILENAME="${SMOKE_RESULT_FILENAME:-source-sdk-smoke-result.json}"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-60}"
REGENERATE_PROJECT="${REGENERATE_PROJECT:-0}"

function parse_destination_id() {
  if [[ -z "${DESTINATION:-}" ]]; then
    return 1
  fi

  local parsed
  parsed="$(echo "$DESTINATION" | sed -n 's/.*id=\([^,]*\).*/\1/p' | xargs)"
  [[ -n "$parsed" ]] || return 1
  echo "$parsed"
}

function parse_destination_name() {
  if [[ -z "${DESTINATION:-}" ]]; then
    return 1
  fi

  local parsed
  parsed="$(echo "$DESTINATION" | sed -n 's/.*name=\([^,]*\).*/\1/p' | xargs)"
  [[ -n "$parsed" ]] || return 1
  echo "$parsed"
}

function detect_device_name() {
  local device

  if device="$(parse_destination_name 2>/dev/null)"; then
    echo "$device"
    return 0
  fi

  for device in "iPhone 17 Pro Max" "iPhone 17 Pro" "iPhone 16 Pro Max" "iPhone 16 Pro"; do
    if xcrun simctl list devices available | grep -q "$device"; then
      echo "$device"
      return 0
    fi
  done

  device=$(xcrun simctl list devices available | grep -oE 'iPhone [^(]+' | head -1 | xargs)
  if [[ -n "$device" ]]; then
    echo "$device"
    return 0
  fi

  echo "error: could not find an available iPhone simulator destination" >&2
  return 1
}

function detect_device_id() {
  local device_name="$1"
  local parsed_id

  if parsed_id="$(parse_destination_id 2>/dev/null)"; then
    echo "$parsed_id"
    return 0
  fi

  parsed_id="$(xcrun simctl list devices available | grep "$device_name (" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')"
  if [[ -n "$parsed_id" ]]; then
    echo "$parsed_id"
    return 0
  fi

  echo "error: could not resolve simulator device ID for $device_name" >&2
  return 1
}

DEVICE_NAME_RESOLVED="$(detect_device_name)"
DEVICE_ID_RESOLVED="$(detect_device_id "$DEVICE_NAME_RESOLVED")"
DESTINATION_RESOLVED="${DESTINATION:-platform=iOS Simulator,name=$DEVICE_NAME_RESOLVED}"

function terminate_app() {
  xcrun simctl terminate "$DEVICE_ID_RESOLVED" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

trap terminate_app EXIT

if [[ "$REGENERATE_PROJECT" == "1" || ! -d "$PROJECT_FILE" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required only when regenerating $PROJECT_FILE" >&2
    exit 1
  fi

  echo "Regenerating sample project from $PROJECT_SPEC..."
  xcodegen generate --spec "$PROJECT_SPEC" >/dev/null
else
  echo "Using committed sample project at $PROJECT_FILE"
fi

if [[ "$REGENERATE_PROJECT" == "1" || ! -d "$APP_PATH" ]]; then
  echo "Building sample app for smoke harness..."
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH" DESTINATION="$DESTINATION_RESOLVED" REGENERATE_PROJECT="$REGENERATE_PROJECT" "$BUILD_SCRIPT"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built sample app not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_ID_RESOLVED" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID_RESOLVED" -b
xcrun simctl uninstall "$DEVICE_ID_RESOLVED" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID_RESOLVED" "$APP_PATH"

APP_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID_RESOLVED" "$BUNDLE_ID" data)"
RESULT_FILE="$APP_CONTAINER/Library/Caches/$SMOKE_RESULT_FILENAME"
rm -f "$RESULT_FILE"

echo "Launching smoke harness in simulator..."
if ! SIMCTL_CHILD_SOURCE_SDK_SMOKE_TEST_MODE=1 xcrun simctl launch --terminate-running-process "$DEVICE_ID_RESOLVED" "$BUNDLE_ID" >/dev/null; then
  echo "error: failed to launch SourceSDKHost smoke harness." >&2
  exit 1
fi

typeset -i elapsed=0
while [[ ! -f "$RESULT_FILE" && $elapsed -lt $SMOKE_TIMEOUT_SECONDS ]]; do
  sleep 1
  elapsed+=1
done

if [[ ! -f "$RESULT_FILE" ]]; then
  echo "error: Source SDK smoke harness timed out after ${SMOKE_TIMEOUT_SECONDS}s." >&2
  echo "---- recent simulator logs ----" >&2
  xcrun simctl spawn "$DEVICE_ID_RESOLVED" log show --style compact --last 5m --predicate 'process == "SourceSDKHost"' | tail -n 200 >&2 || true
  exit 1
fi

SUCCESS_RAW="$(plutil -extract success raw -o - "$RESULT_FILE" 2>/dev/null || echo false)"
MESSAGE_RAW="$(plutil -extract message raw -o - "$RESULT_FILE" 2>/dev/null || echo "Source SDK smoke harness completed.")"

if [[ "$SUCCESS_RAW" != "true" && "$SUCCESS_RAW" != "1" ]]; then
  echo "error: Source SDK smoke harness reported failure." >&2
  cat "$RESULT_FILE" >&2
  exit 1
fi

echo "Source SDK smoke tests succeeded."
echo "$MESSAGE_RAW"
echo "Destination: $DESTINATION_RESOLVED"
echo "Result file: $RESULT_FILE"
echo "Device ID: $DEVICE_ID_RESOLVED"
