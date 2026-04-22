#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/OpenIntelligence-SDK-Package}"
ZIP_PATH="$OUTPUT_DIR/build/OpenIntelligenceEngine-Buyer-Packet.zip"

function fail() {
  echo "error: $1" >&2
  exit 1
}

cd "$REPO_ROOT"

echo "Staging evaluation XCFramework and simulator support..."
/bin/zsh ./scripts/build_engine_evaluation_xcframework.sh

echo "Staging self-contained sample app..."
/bin/zsh ./scripts/stage_sdk_sample_app.sh

echo "Validating SDK package..."
/bin/zsh ./scripts/validate_sdk_package.sh

echo "Building buyer-safe packet..."
/bin/zsh ./scripts/build_sdk_buyer_bundle.sh

[[ -f "$ZIP_PATH" ]] || fail "Buyer packet zip was not created at $ZIP_PATH"

cat <<EOF
Buyer-ready evaluation packet created:
  $ZIP_PATH

Use this packet for:
- founder or design-partner evaluation on a matching Xcode and Swift toolchain
- guided sample import validation

Do not promise yet:
- toolchain-agnostic binary stability
- zero-guidance production SDK handoff
EOF
