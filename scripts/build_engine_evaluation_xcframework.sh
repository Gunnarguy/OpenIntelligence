#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

PROJECT="${PROJECT:-OpenIntelligence.xcodeproj}"
TARGET="${TARGET:-OpenIntelligenceEngine}"
OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build/evaluation}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$TARGET}"
SUPPORT_DIR="$OUTPUT_DIR/EvaluationSupport"
SIM_SUPPORT_DIR="$SUPPORT_DIR/iphonesimulator"
DEVICE_SUPPORT_DIR="$SUPPORT_DIR/iphoneos"
DEVICE_DERIVED_DATA_DIR="$BUILD_DIR/DerivedData-iphoneos"
SIM_DERIVED_DATA_DIR="$BUILD_DIR/DerivedData-iphonesimulator"
PROJECT_FILE="$PROJECT/project.pbxproj"
SHARED_SCHEME_PATH="$PROJECT/xcshareddata/xcschemes/${TARGET}.xcscheme"
BUYER_PACKET_DIR="${BUYER_PACKET_DIR:-$OUTPUT_DIR/build/${FRAMEWORK_NAME}-Buyer-Packet}"
BUYER_XCFRAMEWORK_PATH="$BUYER_PACKET_DIR/${FRAMEWORK_NAME}.xcframework"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"
DEVICE_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphoneos.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphonesimulator.xcarchive"
CLEAN_DIR="$BUILD_DIR/clean-xcframework-inputs"
DEVICE_BUILD_PRODUCTS="$DEVICE_DERIVED_DATA_DIR/Build/Intermediates.noindex/ArchiveIntermediates/$TARGET/BuildProductsPath/Release-iphoneos"
SIM_BUILD_PRODUCTS="$SIM_DERIVED_DATA_DIR/Build/Intermediates.noindex/ArchiveIntermediates/$TARGET/BuildProductsPath/Release-iphonesimulator"
BUILD_MODE_FILE="$BUILD_DIR/build-mode.txt"

function fail() {
  echo "error: $1" >&2
  exit 1
}

function has_buildable_engine_target() {
  [[ -f "$PROJECT_FILE" ]] || return 1
  [[ -f "$SHARED_SCHEME_PATH" ]] || return 1
  /usr/bin/grep -Fq "Build configuration list for PBXNativeTarget \"$TARGET\"" "$PROJECT_FILE"
}

function best_effort_remove_path() {
  local path="$1"

  [[ -e "$path" ]] || return 0

  /bin/chmod -R u+w "$path" 2>/dev/null || true
  /bin/rm -rf "$path" 2>/dev/null || true
}

function stage_simulator_support() {
  setopt local_options null_glob

  if [[ ! -d "$SIM_BUILD_PRODUCTS" ]]; then
    if [[ -d "$SIM_SUPPORT_DIR" ]]; then
      return 0
    fi
    fail "Simulator build products not found at $SIM_BUILD_PRODUCTS"
  fi

  rm -rf "$SIM_SUPPORT_DIR"
  mkdir -p "$SIM_SUPPORT_DIR"

  local copied_support=0

  echo "Staging simulator support modules..."
  for artifact_path in "$SIM_BUILD_PRODUCTS"/*.swiftmodule "$SIM_BUILD_PRODUCTS"/*.bundle; do
    [[ -e "$artifact_path" ]] || continue
    /bin/cp -R "$artifact_path" "$SIM_SUPPORT_DIR/"
    copied_support=1
  done

  if [[ -d "$SIM_BUILD_PRODUCTS/PackageFrameworks" ]]; then
    mkdir -p "$SIM_SUPPORT_DIR/PackageFrameworks"
    for artifact_path in "$SIM_BUILD_PRODUCTS"/PackageFrameworks/*; do
      [[ -e "$artifact_path" ]] || continue
      /bin/cp -R "$artifact_path" "$SIM_SUPPORT_DIR/PackageFrameworks/"
    done
  fi

  [[ $copied_support -eq 1 ]] || fail "No simulator support modules were found at $SIM_BUILD_PRODUCTS"
}

function stage_device_support() {
  setopt local_options null_glob

  if [[ -d "$DEVICE_BUILD_PRODUCTS" ]]; then
    rm -rf "$DEVICE_SUPPORT_DIR"
    mkdir -p "$DEVICE_SUPPORT_DIR"

    local copied_support=0

    echo "Staging device support modules..."
    for artifact_path in "$DEVICE_BUILD_PRODUCTS"/*.swiftmodule "$DEVICE_BUILD_PRODUCTS"/*.bundle; do
      [[ -e "$artifact_path" ]] || continue
      /bin/cp -R "$artifact_path" "$DEVICE_SUPPORT_DIR/"
      copied_support=1
    done

    if [[ -d "$DEVICE_BUILD_PRODUCTS/PackageFrameworks" ]]; then
      mkdir -p "$DEVICE_SUPPORT_DIR/PackageFrameworks"
      for artifact_path in "$DEVICE_BUILD_PRODUCTS"/PackageFrameworks/*; do
        [[ -e "$artifact_path" ]] || continue
        /bin/cp -R "$artifact_path" "$DEVICE_SUPPORT_DIR/PackageFrameworks/"
      done
    fi

    [[ $copied_support -eq 1 ]] || fail "No device support modules were found at $DEVICE_BUILD_PRODUCTS"
    return
  fi

  if [[ -d "$DEVICE_SUPPORT_DIR" ]]; then
    return 0
  fi

  [[ -d "$SIM_SUPPORT_DIR" ]] || fail "Simulator support must be staged before generating device compatibility modules"

  mkdir -p "$DEVICE_SUPPORT_DIR"
  mkdir -p "$BUILD_DIR"
  local stub_source="$BUILD_DIR/device-support-stub.swift"
  : > "$stub_source"

  local generated_support=0

  echo "Generating device compatibility modules from simulator support module names..."
  for module_dir in "$SIM_SUPPORT_DIR"/*.swiftmodule; do
    [[ -d "$module_dir" ]] || continue

    local module_name="${module_dir##*/}"
    module_name="${module_name%.swiftmodule}"

    mkdir -p "$DEVICE_SUPPORT_DIR/${module_name}.swiftmodule"
    xcrun --sdk iphoneos swiftc \
      -target arm64-apple-ios26.0 \
      -parse-as-library \
      -emit-module \
      -module-name "$module_name" \
      "$stub_source" \
      -o "$DEVICE_SUPPORT_DIR/${module_name}.swiftmodule/arm64-apple-ios.swiftmodule"

    generated_support=1
  done

  for artifact_path in "$SIM_SUPPORT_DIR"/*.bundle; do
    [[ -e "$artifact_path" ]] || continue
    /bin/cp -R "$artifact_path" "$DEVICE_SUPPORT_DIR/"
  done

  mkdir -p "$DEVICE_SUPPORT_DIR/PackageFrameworks"

  [[ $generated_support -eq 1 ]] || fail "Unable to generate any device compatibility modules from $SIM_SUPPORT_DIR"
}

function stage_from_existing_artifacts() {
  mkdir -p "$OUTPUT_DIR"

  if [[ -d "$BUYER_XCFRAMEWORK_PATH" ]]; then
    echo "Restoring evaluation XCFramework from buyer packet..."
    rm -rf "$XCFRAMEWORK_PATH"
    /bin/cp -R "$BUYER_XCFRAMEWORK_PATH" "$OUTPUT_DIR/"
  elif [[ -d "$XCFRAMEWORK_PATH" ]]; then
    echo "Reusing existing evaluation XCFramework at $XCFRAMEWORK_PATH"
  else
    fail "No restorable evaluation XCFramework found. Checked $BUYER_XCFRAMEWORK_PATH and $XCFRAMEWORK_PATH"
  fi

  if [[ -d "$BUYER_PACKET_DIR/EvaluationSupport" ]]; then
    echo "Restoring evaluation compiler support from buyer packet..."
    rm -rf "$SUPPORT_DIR"
    /bin/cp -R "$BUYER_PACKET_DIR/EvaluationSupport" "$OUTPUT_DIR/"
  fi

  stage_simulator_support
  stage_device_support

  printf 'restored\n' > "$BUILD_MODE_FILE"

  cat <<EOF
Staged evaluation XCFramework from existing on-disk artifacts:
  $XCFRAMEWORK_PATH

Important:
- The OpenIntelligenceEngine target or shared scheme is not available in $PROJECT
- This path restores the last known buyer packet and simulator support artifacts
- It does not produce a fresh SDK build
- Device compile support is generated from compatibility stubs if native iphoneos support artifacts are unavailable
- Consumers should use a matching Xcode and Swift toolchain generation
- Compiler support artifacts are staged at $SIM_SUPPORT_DIR
- Device compatibility artifacts are staged at $DEVICE_SUPPORT_DIR
EOF
}

function build_from_project() {
  mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

  best_effort_remove_path "$DEVICE_ARCHIVE"
  best_effort_remove_path "$SIM_ARCHIVE"
  best_effort_remove_path "$CLEAN_DIR"
  best_effort_remove_path "$DEVICE_DERIVED_DATA_DIR"
  best_effort_remove_path "$SIM_DERIVED_DATA_DIR"

  local common_args=(
    -project "$PROJECT"
    -scheme "$TARGET"
    SKIP_INSTALL=NO
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )

  echo "Archiving evaluation iOS device slice..."
  xcodebuild archive \
    "${common_args[@]}" \
    -derivedDataPath "$DEVICE_DERIVED_DATA_DIR" \
    -destination "generic/platform=iOS" \
    -archivePath "$DEVICE_ARCHIVE" || return 1

  echo "Archiving evaluation iOS simulator slice..."
  xcodebuild archive \
    "${common_args[@]}" \
    -derivedDataPath "$SIM_DERIVED_DATA_DIR" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$SIM_ARCHIVE" || return 1

  mkdir -p "$CLEAN_DIR/device" "$CLEAN_DIR/sim"

  echo "Preparing clean XCFramework inputs..."
  /usr/bin/ditto --noextattr --noqtn \
    "$DEVICE_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework" || return 1
  /usr/bin/ditto --noextattr --noqtn \
    "$SIM_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework" || return 1

  /bin/rm -rf \
    "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework/swift-transformers" \
    "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework/swift-transformers" \
    "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework/.gitignore" \
    "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework/.gitignore"

  stage_simulator_support || return 1
  stage_device_support || return 1

  echo "Creating evaluation XCFramework..."
  best_effort_remove_path "$XCFRAMEWORK_PATH"
  xcodebuild -create-xcframework \
    -allow-internal-distribution \
    -framework "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework" \
    -framework "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework" \
    -output "$XCFRAMEWORK_PATH" || return 1

  printf 'fresh\n' > "$BUILD_MODE_FILE"

  cat <<EOF
Created evaluation XCFramework:
  $XCFRAMEWORK_PATH

Important:
- This build uses BUILD_LIBRARY_FOR_DISTRIBUTION=NO
- Treat it as a founder/design-partner evaluation artifact
- Consumers should use a matching Xcode and Swift toolchain generation
- Compiler support artifacts are staged at $SIM_SUPPORT_DIR
- Device compatibility artifacts are staged at $DEVICE_SUPPORT_DIR
EOF
}

[[ -d "$PROJECT" ]] || fail "Project not found at $PROJECT"

if has_buildable_engine_target; then
  if ! ( build_from_project ); then
    echo "warning: fresh evaluation build failed; restoring the last known good staged evaluation artifact" >&2
    stage_from_existing_artifacts
  fi
else
  stage_from_existing_artifacts
fi
