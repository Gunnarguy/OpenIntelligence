#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-OpenIntelligenceEngine}"
PROJECT_FILE="${PROJECT_FILE:-OpenIntelligence.xcodeproj/project.pbxproj}"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"

missing=0

function detect_release_line() {
  local project_file="$1"
  if [[ -f "$project_file" ]]; then
    /usr/bin/grep -m 1 'MARKETING_VERSION = ' "$project_file" | /usr/bin/sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | /usr/bin/tr -d '[:space:]'
  fi
}

RELEASE_LINE="${RELEASE_LINE:-$(detect_release_line "$PROJECT_FILE")}"
[[ -n "$RELEASE_LINE" ]] || RELEASE_LINE="unknown"

function check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "ok  $path"
  else
    echo "miss $path"
    missing=1
  fi
}

function check_find_any() {
  local label="$1"
  shift

  for pattern in "$@"; do
    if /usr/bin/find "$XCFRAMEWORK_PATH" -name "$pattern" -print -quit 2>/dev/null | /usr/bin/grep -q .; then
      echo "ok  $label"
      return 0
    fi
  done

  echo "miss $label"
  missing=1
}

function has_swiftinterface() {
  /usr/bin/find "$XCFRAMEWORK_PATH" -name '*.swiftinterface' -print -quit 2>/dev/null | /usr/bin/grep -q .
}

echo "Validating SDK package scaffold for release line $RELEASE_LINE..."

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
check_path "$XCFRAMEWORK_PATH"
check_path "$OUTPUT_DIR/EvaluationSupport/iphonesimulator"
check_path "$OUTPUT_DIR/EvaluationSupport/iphoneos"
check_path "$OUTPUT_DIR/SampleApp/EngineEvaluationHost.xcodeproj"
check_path "$OUTPUT_DIR/SampleApp/build_sample_app.sh"
check_path "$OUTPUT_DIR/SampleApp/DEMO_SCRIPT.md"

if [[ -d "$XCFRAMEWORK_PATH" ]]; then
  check_find_any "packaged EmbeddingModel resource" "EmbeddingModel.mlmodelc" "EmbeddingModel.mlpackage"
  check_find_any "packaged ReRankerModel resource" "ReRankerModel.mlmodelc" "ReRankerModel.mlpackage"
  check_find_any "packaged embedding vocabulary" "embedding_vocab.json"
  check_find_any "packaged reranker vocabulary" "reranker_vocab.json"
  check_find_any "packaged privacy manifest" "PrivacyInfo.xcprivacy"
fi

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

Current evaluation packet alignment: release line $RELEASE_LINE.

The documentation scaffold exists and the XCFramework artifact is present.
Required engine resources are bundled inside the staged XCFramework.

Artifact truth:
- built packet type: $(if has_swiftinterface; then echo "module-stable candidate"; else echo "evaluation-only"; fi)
- module-stable swiftinterface files present: $(if has_swiftinterface; then echo "yes"; else echo "no"; fi)
- self-serve commercial SDK ready: $(if has_swiftinterface; then echo "not yet verified"; else echo "no"; fi)

You should still perform:
- import validation in a sample app
- physical-device runtime validation on an Apple Intelligence-capable iPhone, iPad, or Mac
- buyer-packet regeneration after any future public release

EOF
