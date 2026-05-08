#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAMPLE_BUILD_SCRIPT="$REPO_ROOT/Samples/SourceSDKHost/build_sample_app.sh"
SAMPLE_TEST_SCRIPT="$REPO_ROOT/Samples/SourceSDKHost/run_smoke_tests.sh"

cd "$REPO_ROOT"

echo "Step 1/3: validating source SDK package..."
./scripts/validate_source_sdk_package.sh

echo
echo "Step 2/3: validating package consumer sample app..."
"$SAMPLE_BUILD_SCRIPT"

echo
echo "Step 3/3: running package consumer smoke tests..."
"$SAMPLE_TEST_SCRIPT"

echo
echo "Source SDK consumer flow validation passed."
