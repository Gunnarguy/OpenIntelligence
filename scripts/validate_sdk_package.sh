#!/bin/zsh
set -euo pipefail

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
check_path "$OUTPUT_DIR/BUILD_NOTES.md"
check_path "$OUTPUT_DIR/PACKAGE_SUMMARY.md"
check_path "SDK_BOUNDARY_AUDIT.md"
check_path "scripts/build_engine_xcframework.sh"
check_path "scripts/validate_sdk_package.sh"
check_path "$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"

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
- physical-device runtime validation for Apple Intelligence behavior

EOF
