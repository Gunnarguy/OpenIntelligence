#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-Partner-Packet}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"
BUNDLE_DIR="$BUILD_DIR/OpenIntelligence-Partner-Packet"
ZIP_PATH="$BUILD_DIR/OpenIntelligence-Partner-Packet.zip"

function fail() {
  echo "error: $1" >&2
  exit 1
}

copy_required() {
  local path="$1"
  [[ -f "$path" ]] || fail "Missing required file: $path"
  /bin/cp "$path" "$BUNDLE_DIR/"
}

[[ -d "$OUTPUT_DIR" ]] || fail "Partner packet not found at $OUTPUT_DIR"

mkdir -p "$BUILD_DIR"
rm -rf "$BUNDLE_DIR" "$ZIP_PATH"
mkdir -p "$BUNDLE_DIR"

copy_required "$OUTPUT_DIR/README.md"
copy_required "$OUTPUT_DIR/CURRENT_COMMITMENTS.md"
copy_required "$OUTPUT_DIR/DATA_BOUNDARIES.md"
copy_required "$OUTPUT_DIR/EVALUATION_PROCESS.md"
copy_required "$OUTPUT_DIR/PRICING.md"
copy_required "$OUTPUT_DIR/DESIGN_PARTNER_OFFER.md"

cat > "$BUNDLE_DIR/CONTENTS.txt" <<EOF
OpenIntelligence partner packet

Included:
- README.md
- CURRENT_COMMITMENTS.md
- DATA_BOUNDARIES.md
- EVALUATION_PROCESS.md
- PRICING.md
- DESIGN_PARTNER_OFFER.md

Excluded on purpose:
- FOUNDER_SALES_RUNBOOK.md
- OUTREACH.md
- TARGET_ACCOUNT_FRAMEWORK.md

Pair this packet with:
- output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip
EOF

(cd "$BUILD_DIR" && /usr/bin/zip -qry "$(basename "$ZIP_PATH")" "$(basename "$BUNDLE_DIR")")

echo "Created partner packet bundle:"
echo "  $ZIP_PATH"
