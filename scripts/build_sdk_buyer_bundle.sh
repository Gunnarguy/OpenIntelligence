#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"
BUNDLE_DIR="$BUILD_DIR/OpenIntelligenceEngine-Buyer-Packet"
ZIP_PATH="$BUILD_DIR/OpenIntelligenceEngine-Buyer-Packet.zip"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-OpenIntelligenceEngine}"
PROJECT_FILE="${PROJECT_FILE:-OpenIntelligence.xcodeproj/project.pbxproj}"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"

function fail() {
  echo "error: $1" >&2
  exit 1
}

function detect_release_line() {
  local project_file="$1"
  if [[ -f "$project_file" ]]; then
    /usr/bin/grep -m 1 'MARKETING_VERSION = ' "$project_file" | /usr/bin/sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | /usr/bin/tr -d '[:space:]'
  fi
}

function has_find_any() {
  local path="$1"
  shift

  for pattern in "$@"; do
    if /usr/bin/find "$path" -name "$pattern" -print -quit 2>/dev/null | /usr/bin/grep -q .; then
      return 0
    fi
  done

  return 1
}

function bool_string() {
  if [[ "$1" -eq 0 ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

RELEASE_LINE="${RELEASE_LINE:-$(detect_release_line "$PROJECT_FILE")}"
[[ -n "$RELEASE_LINE" ]] || RELEASE_LINE="unknown"

[[ -d "$OUTPUT_DIR" ]] || fail "SDK packet not found at $OUTPUT_DIR"

mkdir -p "$BUILD_DIR"
rm -rf "$BUNDLE_DIR" "$ZIP_PATH"
mkdir -p "$BUNDLE_DIR"

copy_required() {
  local path="$1"
  [[ -f "$path" ]] || fail "Missing required file: $path"
  /bin/cp "$path" "$BUNDLE_DIR/"
}

copy_required "$OUTPUT_DIR/README.md"
copy_required "$OUTPUT_DIR/INSTALL.md"
copy_required "$OUTPUT_DIR/API.md"
copy_required "$OUTPUT_DIR/PACKAGE_SUMMARY.md"

if [[ -f "$OUTPUT_DIR/START_HERE.md" ]]; then
  /bin/cp "$OUTPUT_DIR/START_HERE.md" "$BUNDLE_DIR/"
fi

if [[ -d "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework" ]]; then
  /bin/cp -R "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework" "$BUNDLE_DIR/"
fi

if [[ -d "$OUTPUT_DIR/EvaluationSupport" ]]; then
  /bin/cp -R "$OUTPUT_DIR/EvaluationSupport" "$BUNDLE_DIR/"
fi

if [[ -d "$OUTPUT_DIR/SampleApp" ]]; then
  /bin/cp -R "$OUTPUT_DIR/SampleApp" "$BUNDLE_DIR/"
fi

has_source_package=1
if [[ -f "Package.swift" ]]; then
  has_source_package=0
fi

has_source_sample=1
if [[ -d "Samples/SourceSDKHost" && -f "Samples/SourceSDKHost/SourceSDKHost.xcodeproj/project.pbxproj" ]]; then
  has_source_sample=0
fi

has_source_validation=1
if [[ -f "scripts/validate_source_sdk_package.sh" && -f "scripts/validate_source_sdk_consumer_flow.sh" ]]; then
  has_source_validation=0
fi

has_source_docs=1
if [[ -f "$OUTPUT_DIR/START_HERE.md" && -f "$OUTPUT_DIR/INSTALL.md" && -f "$OUTPUT_DIR/API.md" && -f "$OUTPUT_DIR/PACKAGE_SUMMARY.md" ]]; then
  has_source_docs=0
fi

has_swiftinterface=1
if has_find_any "$XCFRAMEWORK_PATH" '*.swiftinterface'; then
  has_swiftinterface=0
fi

has_embedding_model=1
if has_find_any "$XCFRAMEWORK_PATH" 'EmbeddingModel.mlmodelc' 'EmbeddingModel.mlpackage'; then
  has_embedding_model=0
fi

has_reranker_model=1
if has_find_any "$XCFRAMEWORK_PATH" 'ReRankerModel.mlmodelc' 'ReRankerModel.mlpackage'; then
  has_reranker_model=0
fi

has_embedding_vocab=1
if has_find_any "$XCFRAMEWORK_PATH" 'embedding_vocab.json'; then
  has_embedding_vocab=0
fi

has_reranker_vocab=1
if has_find_any "$XCFRAMEWORK_PATH" 'reranker_vocab.json'; then
  has_reranker_vocab=0
fi

has_privacy_manifest=1
if has_find_any "$XCFRAMEWORK_PATH" 'PrivacyInfo.xcprivacy'; then
  has_privacy_manifest=0
fi

source_sdk_lane_ready=1
if [[ $has_source_package -eq 0 && $has_source_sample -eq 0 && $has_source_validation -eq 0 && $has_source_docs -eq 0 ]]; then
  source_sdk_lane_ready=0
fi

cat > "$BUNDLE_DIR/ARTIFACT_STATUS.txt" <<EOF
OpenIntelligence Engine artifact status

Built from repo release line: $RELEASE_LINE

Hard truth:
- root source SDK package present in private repo: $(bool_string $has_source_package)
- repo-side source consumer sample present: $(bool_string $has_source_sample)
- repo-side source consumer validation path present: $(bool_string $has_source_validation)
- source-distributed design-partner SDK lane ready: $(if [[ $source_sdk_lane_ready -eq 0 ]]; then echo "yes, with private repo access and assisted integration"; else echo "not proven"; fi)
- docs-only self-serve source SDK ready: no
- staged XCFramework present: $(if [[ -d "$XCFRAMEWORK_PATH" ]]; then echo "yes"; else echo "no"; fi)
- required model resources bundled in staged XCFramework: $(if [[ $has_embedding_model -eq 0 && $has_reranker_model -eq 0 && $has_embedding_vocab -eq 0 && $has_reranker_vocab -eq 0 ]]; then echo "yes"; else echo "no"; fi)
- packaged privacy manifest present: $(bool_string $has_privacy_manifest)
- evaluation compiler support included: $(if [[ -d "$OUTPUT_DIR/EvaluationSupport" ]]; then echo "yes"; else echo "no"; fi)
- packet-local sample host app included: $(if [[ -d "$OUTPUT_DIR/SampleApp" ]]; then echo "yes"; else echo "no"; fi)
- module-stable swiftinterface files present: $(bool_string $has_swiftinterface)
- packet classification: $(if [[ $has_swiftinterface -eq 0 ]]; then echo "module-stable candidate"; else echo "evaluation-only"; fi)
- self-serve commercial SDK ready: $(if [[ $has_swiftinterface -eq 0 ]]; then echo "not yet verified"; else echo "no"; fi)

Why the answer is still no:
- the commercial lane today is the source-distributed SDK path in the private repo, not the staged XCFramework
- this buyer packet is currently built by the evaluation path
- the evaluation XCFramework is created with BUILD_LIBRARY_FOR_DISTRIBUTION=NO and allow-internal-distribution
- stable commercial archive is still blocked by swift-transformers interface verification during BUILD_LIBRARY_FOR_DISTRIBUTION=YES packaging

Public engine facade source:
- OpenIntelligence/SDK/OpenIntelligenceEngine.swift
EOF

cat > "$BUNDLE_DIR/SOURCE_SDK_STATUS.txt" <<EOF
OpenIntelligence source SDK status

Primary commercial lane today:
- private source-distributed SDK with assisted integration

What exists right now in the private engine repo:
- root Package.swift: $(bool_string $has_source_package)
- canonical source consumer sample: $(bool_string $has_source_sample)
- repo-side source validation scripts: $(bool_string $has_source_validation)
- buyer-facing packet docs describing the source lane: $(bool_string $has_source_docs)

Canonical repo-side validation path:
1. ./scripts/validate_source_sdk_package.sh
2. Samples/SourceSDKHost/build_sample_app.sh
3. Samples/SourceSDKHost/run_smoke_tests.sh
4. or ./scripts/validate_source_sdk_consumer_flow.sh

Honest sales wording:
- source-distributed design-partner SDK
- private repo access
- assisted integration

Do not promise:
- docs-only no-guidance self-serve SDK
- sealed stable binary SDK
- toolchain-agnostic binary handoff
EOF

cat > "$BUNDLE_DIR/CONTENTS.txt" <<EOF
OpenIntelligence Engine buyer-safe packet

Built from repo release line: $RELEASE_LINE

Included:
- ARTIFACT_STATUS.txt
- SOURCE_SDK_STATUS.txt
- START_HERE.md
- README.md
- INSTALL.md
- API.md
- PACKAGE_SUMMARY.md
- SampleApp/

Excluded on purpose:
- Internal sales playbooks
- Internal demo playbooks
- Internal build notes

If present, ${FRAMEWORK_NAME}.xcframework is included.
If present, EvaluationSupport/ is included for same-toolchain evaluation imports.
If present, SampleApp/ is included as a packet-local evaluation host app.
Read ARTIFACT_STATUS.txt first if you need the direct yes/no status of this packet.
EOF

(cd "$BUILD_DIR" && /usr/bin/zip -qry "$(basename "$ZIP_PATH")" "$(basename "$BUNDLE_DIR")")

echo "Created buyer-safe bundle:"
echo "  $ZIP_PATH"
