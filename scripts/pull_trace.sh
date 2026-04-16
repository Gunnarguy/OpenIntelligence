#!/bin/bash
# scripts/pull_trace.sh
#
# Pull pipeline trace logs from a connected iPhone to Xrays/ for debugging.
# Works with devices connected via USB running the debug build.
#
# Usage:
#   ./scripts/pull_trace.sh              # Auto-find device, pull latest trace
#   ./scripts/pull_trace.sh --list       # List available devices
#   ./scripts/pull_trace.sh --tail 50    # Pull and show last 50 lines
#   ./scripts/pull_trace.sh --clear      # Clear the trace on device
#
# The trace file is written by LoggingConfiguration's file logger,
# capturing pipeline/llm/retrieval categories automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Xrays"
BUNDLE_ID="com.gunnar.OpenIntelligence"
TRACE_FILE="pipeline_trace.log"
PREV_FILE="pipeline_trace.prev.log"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Find connected device
find_device() {
    # Try xcrun devicectl first (Xcode 16+)
    if command -v xcrun &>/dev/null; then
        local device_id
        device_id=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | head -1 | awk '{print $NF}' | tr -d '()')
        if [[ -n "$device_id" ]]; then
            echo "$device_id"
            return 0
        fi
    fi

    # Fallback: pymobiledevice3 or idevice_id
    if command -v idevice_id &>/dev/null; then
        idevice_id -l 2>/dev/null | head -1
        return $?
    fi

    return 1
}

# Pull file from device app container
pull_from_device() {
    local filename="$1"
    local output_path="$2"

    # Method 1: xcrun devicectl (Xcode 16+)
    if command -v xcrun &>/dev/null; then
        # Get the app container path
        echo -e "${CYAN}Pulling $filename via devicectl...${NC}"
        xcrun devicectl device copy from \
            --device "$(find_device)" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            "Documents/$filename" \
            "$output_path" 2>/dev/null && return 0
    fi

    # Method 2: Use Xcode's device support via open container
    # Fallback for older Xcode versions
    echo -e "${YELLOW}devicectl copy failed, trying alternative...${NC}"

    # Method 3: Check if running on Simulator (files directly accessible)
    local sim_data="$HOME/Library/Developer/CoreSimulator/Devices"
    if [[ -d "$sim_data" ]]; then
        local found
        found=$(find "$sim_data" -path "*/Documents/$filename" -newer "$output_path" 2>/dev/null | head -1)
        if [[ -z "$found" ]]; then
            found=$(find "$sim_data" -path "*/Documents/$filename" 2>/dev/null | head -1)
        fi
        if [[ -n "$found" ]]; then
            echo -e "${GREEN}Found in Simulator: $found${NC}"
            cp "$found" "$output_path"
            return 0
        fi
    fi

    return 1
}

# Main
case "${1:-pull}" in
    --list)
        echo -e "${CYAN}Connected devices:${NC}"
        xcrun devicectl list devices 2>/dev/null || echo "No devices found. Is a device connected via USB?"
        ;;

    --tail)
        LINES="${2:-50}"
        pull_from_device "$TRACE_FILE" "$OUTPUT_DIR/$TRACE_FILE"
        echo -e "\n${CYAN}Last $LINES lines of pipeline trace:${NC}\n"
        tail -n "$LINES" "$OUTPUT_DIR/$TRACE_FILE"
        ;;

    --clear)
        echo -e "${YELLOW}Note: Clear the trace by restarting the app or deleting Documents/$TRACE_FILE${NC}"
        echo -e "The file auto-rotates at 500KB."
        ;;

    pull|*)
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  OpenIntelligence Pipeline Trace Pull${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        echo ""

        DEVICE=$(find_device 2>/dev/null || true)
        if [[ -z "$DEVICE" ]]; then
            echo -e "${YELLOW}No physical device found. Checking Simulator...${NC}"
        else
            echo -e "${GREEN}Device: $DEVICE${NC}"
        fi

        # Pull main trace
        if pull_from_device "$TRACE_FILE" "$OUTPUT_DIR/$TRACE_FILE"; then
            SIZE=$(wc -c < "$OUTPUT_DIR/$TRACE_FILE" | tr -d ' ')
            LINES=$(wc -l < "$OUTPUT_DIR/$TRACE_FILE" | tr -d ' ')
            echo -e "${GREEN}✓ Pulled $TRACE_FILE ($SIZE bytes, $LINES lines)${NC}"
            echo -e "  → ${OUTPUT_DIR/$PROJECT_DIR\//}/$TRACE_FILE"
        else
            echo -e "${RED}✗ Could not pull $TRACE_FILE${NC}"
            echo -e "${YELLOW}  Make sure:${NC}"
            echo -e "  1. Device is connected via USB"
            echo -e "  2. App was built and run in Debug mode"
            echo -e "  3. At least one query has been made"
            echo -e "  4. Xcode 16+ is installed (for devicectl)"
            exit 1
        fi

        # Try to pull previous log too
        if pull_from_device "$PREV_FILE" "$OUTPUT_DIR/$PREV_FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ Also pulled $PREV_FILE (previous rotation)${NC}"
        fi

        echo ""
        echo -e "${GREEN}Done! Read the trace at:${NC}"
        echo -e "  Xrays/$TRACE_FILE"
        echo ""
        ;;
esac
