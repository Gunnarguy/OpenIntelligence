#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BUYER_PACKET_ZIP="$REPO_ROOT/output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip"
PARTNER_PACKET_ZIP="$REPO_ROOT/output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip"

function fail() {
  echo "error: $1" >&2
  exit 1
}

cd "$REPO_ROOT"

echo "Preparing current-source buyer packet..."
/bin/zsh ./scripts/prepare_engine_buyer_packet.sh

echo "Preparing partner packet bundle..."
/bin/zsh ./scripts/build_partner_packet_bundle.sh

[[ -f "$BUYER_PACKET_ZIP" ]] || fail "Buyer packet zip was not created at $BUYER_PACKET_ZIP"
[[ -f "$PARTNER_PACKET_ZIP" ]] || fail "Partner packet zip was not created at $PARTNER_PACKET_ZIP"

cat <<EOF
Sale packets ready:
  $BUYER_PACKET_ZIP
  $PARTNER_PACKET_ZIP

Operator docs:
  EngineSale/SALE_OPERATING_SYSTEM.md
  EngineSale/INBOUND_MESSAGE_TEMPLATES.md
  EngineSale/HANDOFF_CHECKLIST.md

Default sequence:
1. Use the first-reply template
2. Qualify the buyer and pick the lane
3. Use NDA before non-public sharing
4. Send the packet zips after seriousness is confirmed
5. Use the handoff checklist if it becomes a real sale
EOF
