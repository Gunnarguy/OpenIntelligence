#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_FILE="$ROOT_DIR/SourceSDKHost.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenIntelligenceEngine-SourceSDKHost-Tests}"
REGENERATE_PROJECT="${REGENERATE_PROJECT:-0}"

function detect_destination() {
  local device

  if [[ -n "${DESTINATION:-}" ]]; then
    echo "$DESTINATION"
    return 0
  fi

  for device in "iPhone 17 Pro Max" "iPhone 17 Pro" "iPhone 16 Pro Max" "iPhone 16 Pro"; do
    if xcrun simctl list devices available | grep -q "$device"; then
      echo "platform=iOS Simulator,name=$device"
      return 0
    fi
  done

  device=$(xcrun simctl list devices available | grep -oE 'iPhone [^(]+' | head -1 | xargs)
  if [[ -n "$device" ]]; then
    echo "platform=iOS Simulator,name=$device"
    return 0
  fi

  echo "error: could not find an available iPhone simulator destination" >&2
  return 1
}

DESTINATION_RESOLVED="$(detect_destination)"

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

/usr/bin/xcodebuild \
  -quiet \
  -project "$PROJECT_FILE" \
  -scheme SourceSDKHost \
  -destination "$DESTINATION_RESOLVED" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test

echo "Source SDK smoke tests succeeded."
echo "Destination: $DESTINATION_RESOLVED"