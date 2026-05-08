#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAMPLE_BUILD_SCRIPT="$REPO_ROOT/Samples/SourceSDKHost/build_sample_app.sh"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required for source SDK consumer flow validation" >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "Step 1/2: validating source SDK package..."
./scripts/validate_source_sdk_package.sh

echo
echo "Step 2/2: validating package consumer sample app..."
"$SAMPLE_BUILD_SCRIPT"

echo
echo "Source SDK consumer flow validation passed."
