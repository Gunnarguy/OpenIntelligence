#!/bin/zsh
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"
BUNDLE_DIR="$BUILD_DIR/OpenIntelligenceEngine-Buyer-Packet"
ZIP_PATH="$BUILD_DIR/OpenIntelligenceEngine-Buyer-Packet.zip"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-OpenIntelligenceEngine}"

function fail() {
  echo "error: $1" >&2
  exit 1
}

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

if [[ -d "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework" ]]; then
  /bin/cp -R "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework" "$BUNDLE_DIR/"
fi

cat > "$BUNDLE_DIR/CONTENTS.txt" <<EOF
OpenIntelligence Engine buyer-safe packet

Included:
- README.md
- INSTALL.md
- API.md
- PACKAGE_SUMMARY.md

Excluded on purpose:
- Internal sales playbooks
- Internal demo playbooks
- Internal build notes

If present, ${FRAMEWORK_NAME}.xcframework is included.
EOF

(cd "$BUILD_DIR" && /usr/bin/zip -qry "$(basename "$ZIP_PATH")" "$(basename "$BUNDLE_DIR")")

echo "Created buyer-safe bundle:"
echo "  $ZIP_PATH"