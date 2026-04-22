#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-OpenIntelligenceEngine}"

missing=0

function check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "ok  $path"
  else
    echo "miss $path"
    missing=1
  fi
}

echo "Validating SDK package scaffold..."

check_path "$OUTPUT_DIR/README.md"
check_path "$OUTPUT_DIR/INSTALL.md"
check_path "$OUTPUT_DIR/API.md"
check_path "$OUTPUT_DIR/PACKAGE_SUMMARY.md"
check_path "$OUTPUT_DIR/START_HERE.md"
check_path "$OUTPUT_DIR/Internal/BUILD_NOTES.md"
check_path "$OUTPUT_DIR/Internal/SELLING_PLAYBOOK.md"
check_path "$OUTPUT_DIR/Internal/DEMO_PLAYBOOK.md"
check_path "SDK_BOUNDARY_AUDIT.md"
check_path "scripts/build_sdk_buyer_bundle.sh"
check_path "scripts/prepare_engine_buyer_packet.sh"
check_path "scripts/build_engine_xcframework.sh"
check_path "scripts/build_engine_evaluation_host.sh"
check_path "scripts/stage_sdk_sample_app.sh"
check_path "scripts/validate_sdk_package.sh"
check_path "$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"
check_path "$OUTPUT_DIR/EvaluationSupport/iphonesimulator"
check_path "$OUTPUT_DIR/EvaluationSupport/iphoneos"
check_path "$OUTPUT_DIR/SampleApp/EngineEvaluationHost.xcodeproj"
check_path "$OUTPUT_DIR/SampleApp/build_sample_app.sh"
check_path "$OUTPUT_DIR/SampleApp/DEMO_SCRIPT.md"

if [[ $missing -ne 0 ]]; then
  cat <<EOF

Package validation failed.

Interpretation:
- documentation scaffold exists only if listed as ok
- the actual binary package is not complete until ${FRAMEWORK_NAME}.xcframework exists

EOF
  exit 1
fi

cat <<EOF

Package validation passed.

The documentation scaffold exists and the XCFramework artifact is present.
You should still perform:
- import validation in a sample app
- physical-device runtime validation on an Apple Intelligence-capable iPhone, iPad, or Mac

EOF
