#!/usr/bin/env bash
set -euo pipefail

SCHEME="OpenIntelligence"
CONFIGURATION="Debug"
BUNDLE_ID="Gunndamental.OpenIntelligence"
OUTPUT_ROOT="Screenshots"
WAIT_SECONDS="2"
STATUS_BAR_MODE="1"
DERIVED_DATA_PATH=""
DEVICE_NAME=""
RUNTIME_PREFERENCE=""

usage() {
	cat <<'EOF'
Usage:
  scripts/take_screenshots.sh prepare --device "<Simulator Device Name>" [options]
  scripts/take_screenshots.sh shot    --device "<Simulator Device Name>" --name "<shot-name>" [options]
  scripts/take_screenshots.sh run     --device "<Simulator Device Name>" --name "<shot-name>" [options]
	scripts/take_screenshots.sh guided  --device "<Simulator Device Name>" --names "<n1 n2 n3>" [options]
	scripts/take_screenshots.sh appstore --device "<Simulator Device Name>" [options]
	scripts/take_screenshots.sh showcase --device "<Simulator Device Name>" [options]

Commands:
  prepare   Boots simulator, builds, installs, launches app.
  shot      Takes a screenshot of the current simulator display.
  run       prepare + waits + shot.
	guided    prepare, then prompts you to capture multiple named shots.
	appstore  Automatically captures a best-practice App Store set.
	showcase  Captures an expanded, feature-rich set (chat hero, sources, viz tabs, settings).

Options:
  --device <name>           Simulator device name (required)
  --name <shot-name>        Screenshot name (required for shot/run)
	--names "<list>"           Space-separated list of shot names (required for guided)
  --scheme <scheme>         Xcode scheme (default: OpenIntelligence)
  --config <cfg>            Build configuration (default: Debug)
  --bundle-id <id>          App bundle id (default: Gunndamental.OpenIntelligence)
  --output-root <dir>       Output root folder (default: Screenshots)
  --wait <seconds>          Wait before screenshot (default: 2)
  --derived-data <path>     DerivedData path (default: auto per run)
  --runtime "iOS 26.2"       Prefer a specific runtime label when multiple match
  --no-status-bar           Do not override simulator status bar
	--no-rebuild              Skip rebuild/install for guided (assumes already installed)

App Store defaults:
	appstore will build once, then relaunch with screenshot args and capture:
		00-launch, 01-chat, 02-documents, 03-visualizations, 04-settings

Examples:
  scripts/take_screenshots.sh prepare --device "iPhone 17 Pro Max"
  # Navigate the app to the desired screen...
  scripts/take_screenshots.sh shot --device "iPhone 17 Pro Max" --name "01-home"

  # One-shot (launch -> wait -> screenshot)
  scripts/take_screenshots.sh run --device "iPhone 17 Pro Max" --name "00-launch"

	# Guided batch (you navigate, press Enter for each capture)
	scripts/take_screenshots.sh guided --device "iPhone 17 Pro Max" --names "01-home 02-chat 03-docs 04-settings"

	# Full auto App Store set
	scripts/take_screenshots.sh appstore --device "iPhone 17 Pro Max"

	# Expanded showcase set
	scripts/take_screenshots.sh showcase --device "iPhone 17 Pro Max"
EOF
}

fail() {
	echo "error: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || fail "Missing command '$1'. Install Xcode Command Line Tools."
}

sanitize_filename() {
	# macOS 'tr' is fine here; keep it simple.
	echo "$1" | tr ' /:' '___' | tr -cd '[:alnum:]_\-.'
}

# Returns UDID for the given device name.
find_udid() {
	local device_name="$1"
	local runtime_pref="$2"

	/usr/bin/python3 - <<'PY'
import json
import os
import subprocess
import sys

device_name = os.environ["DEVICE_NAME"]
runtime_pref = os.environ.get("RUNTIME_PREF") or ""

raw = subprocess.check_output(["xcrun","simctl","list","devices","available","-j"], text=True)
data = json.loads(raw)

devices_by_runtime = data.get("devices", {})

# Filter to iOS runtimes only, and optionally prefer a specific runtime label.
runtime_items = [(rt, devs) for rt, devs in devices_by_runtime.items() if "iOS" in rt]

# Sort runtimes descending (best-effort) so the newest iOS runtime is chosen when ambiguous.
# Runtime keys look like: com.apple.CoreSimulator.SimRuntime.iOS-26-2
# We'll parse numeric parts.
def rt_key(rt: str):
	parts = rt.split(".")[-1].split("-")
	nums = []
	for p in parts:
		try:
			nums.append(int(p))
		except Exception:
			pass
	return nums

runtime_items.sort(key=lambda item: rt_key(item[0]), reverse=True)

candidates = []
for rt, devs in runtime_items:
	for d in devs:
		if d.get("isAvailable") and d.get("name") == device_name:
			candidates.append((rt, d.get("udid")))

if not candidates:
	# Print iOS devices for diagnostics.
	print("", end="")
	print("--- Available iOS simulators ---", file=sys.stderr)
	for rt, devs in runtime_items:
		for d in devs:
			if d.get("isAvailable"):
				print(f"{d.get('name')} ({d.get('udid')}) [{rt}]", file=sys.stderr)
	sys.exit(2)

# If user provided a runtime preference label like "iOS 26.2", try to match it.
if runtime_pref:
	pref_norm = runtime_pref.strip().replace(" ", "")  # "iOS26.2"
	for rt, udid in candidates:
		# crude matching: check that 'iOS-26-2' or similar appears.
		key = rt.split(".")[-1]  # iOS-26-2
		norm = key.replace("-", "")
		if pref_norm.lower().replace(".", "-") in key.lower().replace(" ", "") or pref_norm.lower() in norm.lower():
			print(udid)
			sys.exit(0)

# Default: pick first candidate in sorted runtime order.
print(candidates[0][1])
PY
}

apply_status_bar_overrides() {
	local udid="$1"
	if [[ "$STATUS_BAR_MODE" != "1" ]]; then
		return 0
	fi

	# These overrides help App Store screenshots look consistent.
	# If Apple changes flags, failing here shouldn't block screenshots.
	set +e
	xcrun simctl status_bar "$udid" override \
		--time "9:41" \
		--batteryState charged \
		--batteryLevel 100 \
		--wifiBars 3 \
		--cellularBars 4 \
		--operatorName "" >/dev/null 2>&1
	set -e
}

boot_device() {
	local udid="$1"
	xcrun simctl boot "$udid" >/dev/null 2>&1 || true
	xcrun simctl bootstatus "$udid" -b >/dev/null
	apply_status_bar_overrides "$udid"
}

build_and_install() {
	local udid="$1"
	local derived="$2"

	echo "Building ($SCHEME, $CONFIGURATION) for simulator $udid..."
	xcodebuild \
		-scheme "$SCHEME" \
		-configuration "$CONFIGURATION" \
		-destination "platform=iOS Simulator,id=$udid" \
		-derivedDataPath "$derived" \
		-quiet \
		build

	local products_dir="$derived/Build/Products/${CONFIGURATION}-iphonesimulator"
	local app_path=""

	if [[ -d "$products_dir" ]]; then
		# Prefer a .app matching the scheme name; otherwise pick the first non-test app.
		if [[ -d "$products_dir/${SCHEME}.app" ]]; then
			app_path="$products_dir/${SCHEME}.app"
		else
			app_path=$(find "$products_dir" -maxdepth 1 -type d -name "*.app" ! -name "*Tests*.app" | head -n 1 || true)
		fi
	fi

	[[ -n "$app_path" && -d "$app_path" ]] || fail "Could not locate built .app in $products_dir"
	echo "Installing: $app_path"
	xcrun simctl install "$udid" "$app_path" >/dev/null
}

launch_app() {
	local udid="$1"
	shift
	echo "Launching: $BUNDLE_ID"
	# If already running, terminate first to ensure fresh state.
	xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
	# Pass through additional args (if any) after the bundle id.
	xcrun simctl launch "$udid" "$BUNDLE_ID" "$@" >/dev/null
}

take_screenshot() {
	local udid="$1"
	local device="$2"
	local name="$3"

	local ts
	ts=$(date "+%Y-%m-%d_%H-%M-%S")
	local out_dir="$OUTPUT_ROOT/$ts"
	mkdir -p "$out_dir"

	local device_safe
	device_safe=$(sanitize_filename "$device")
	local name_safe
	name_safe=$(sanitize_filename "$name")

	local out_path="$out_dir/${device_safe}_${name_safe}.png"
	echo "Saving screenshot: $out_path"
	xcrun simctl io "$udid" screenshot "$out_path"
}

take_screenshot_to_dir() {
	local udid="$1"
	local device="$2"
	local name="$3"
	local out_dir="$4"

	mkdir -p "$out_dir"

	local device_safe
	device_safe=$(sanitize_filename "$device")
	local name_safe
	name_safe=$(sanitize_filename "$name")

	local out_path="$out_dir/${device_safe}_${name_safe}.png"
	echo "Saving screenshot: $out_path"
	xcrun simctl io "$udid" screenshot "$out_path"
}

capture_with_args() {
	local udid="$1"
	local device="$2"
	local out_dir="$3"
	local name="$4"
	local wait_seconds="$5"
	shift 5

	launch_app "$udid" "$@"
	echo "Waiting $wait_seconds seconds..."
	sleep "$wait_seconds"
	take_screenshot_to_dir "$udid" "$device" "$name" "$out_dir"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
	usage
	exit 0
fi

COMMAND="$1"
shift

SHOT_NAME=""
SHOT_NAMES=""
SKIP_REBUILD="0"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--device)
			DEVICE_NAME="${2:-}"; shift 2 ;;
		--name)
			SHOT_NAME="${2:-}"; shift 2 ;;
		--names)
			SHOT_NAMES="${2:-}"; shift 2 ;;
		--scheme)
			SCHEME="${2:-}"; shift 2 ;;
		--config)
			CONFIGURATION="${2:-}"; shift 2 ;;
		--bundle-id)
			BUNDLE_ID="${2:-}"; shift 2 ;;
		--output-root)
			OUTPUT_ROOT="${2:-}"; shift 2 ;;
		--wait)
			WAIT_SECONDS="${2:-}"; shift 2 ;;
		--derived-data)
			DERIVED_DATA_PATH="${2:-}"; shift 2 ;;
		--runtime)
			RUNTIME_PREFERENCE="${2:-}"; shift 2 ;;
		--no-status-bar)
			STATUS_BAR_MODE="0"; shift 1 ;;
		--no-rebuild)
			SKIP_REBUILD="1"; shift 1 ;;
		-h|--help)
			usage; exit 0 ;;
		*)
			fail "Unknown arg: $1 (try --help)" ;;
	esac

done

[[ -n "$COMMAND" ]] || { usage; exit 2; }
[[ -n "$DEVICE_NAME" ]] || fail "--device is required"

require_cmd xcrun
require_cmd xcodebuild

export DEVICE_NAME
export RUNTIME_PREF="$RUNTIME_PREFERENCE"

UDID=$(find_udid "$DEVICE_NAME" "$RUNTIME_PREFERENCE") || fail "Simulator device not found: $DEVICE_NAME"

if [[ -z "$DERIVED_DATA_PATH" ]]; then
	DERIVED_DATA_PATH="$(mktemp -d "/tmp/OpenIntelligence-DerivedData.XXXXXX")"
fi

case "$COMMAND" in
	prepare)
		boot_device "$UDID"
		build_and_install "$UDID" "$DERIVED_DATA_PATH"
		launch_app "$UDID"
		echo "Ready. Navigate in the simulator, then run:"
		echo "  scripts/take_screenshots.sh shot --device \"$DEVICE_NAME\" --name \"01-your-screen\""
		;;
	shot)
		[[ -n "$SHOT_NAME" ]] || fail "--name is required for shot"
		boot_device "$UDID"
		take_screenshot "$UDID" "$DEVICE_NAME" "$SHOT_NAME"
		;;
	run)
		[[ -n "$SHOT_NAME" ]] || fail "--name is required for run"
		boot_device "$UDID"
		build_and_install "$UDID" "$DERIVED_DATA_PATH"
		launch_app "$UDID"
		echo "Waiting $WAIT_SECONDS seconds..."
		sleep "$WAIT_SECONDS"
		take_screenshot "$UDID" "$DEVICE_NAME" "$SHOT_NAME"
		;;
	guided)
		[[ -n "$SHOT_NAMES" ]] || fail "--names is required for guided (example: --names '01-home 02-chat')"
		boot_device "$UDID"
		if [[ "$SKIP_REBUILD" != "1" ]]; then
			build_and_install "$UDID" "$DERIVED_DATA_PATH"
		fi
		launch_app "$UDID"
		echo ""
		echo "Guided capture:"
		echo "- Navigate to each screen in the Simulator"
		echo "- Press Enter here to capture the next screenshot"
		echo ""
		for name in $SHOT_NAMES; do
			echo "Next: $name"
			read -r -p "Press Enter to capture '$name'..." _
			take_screenshot "$UDID" "$DEVICE_NAME" "$name"
		done
		echo "Done. Screenshots are under: $OUTPUT_ROOT/"
		;;
	appstore)
		boot_device "$UDID"

		# Wipe app data to ensure clean state (removes persisted chat history)
		echo "Wiping app data for clean screenshots..."
		xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

		build_and_install "$UDID" "$DERIVED_DATA_PATH"

		local_ts=$(date "+%Y-%m-%d_%H-%M-%S")
		out_dir="$OUTPUT_ROOT/appstore_$local_ts"
		echo "Writing App Store screenshots to: $out_dir"

		# 00 - Raw launch (what you already liked)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "00-launch" "$WAIT_SECONDS"

		# 01 - Chat with full demo (conversation + thinking steps + sources)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "01-chat" "5" \
			--screenshot --screenshot-tab chat --screenshot-chat-full --screenshot-import-samples

		# 02 - Documents tab, with bundled samples imported (safe, deterministic)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "02-documents" "5" \
			--screenshot --screenshot-tab documents --screenshot-import-samples

		# 03 - Visualizations tab (also relies on having some docs)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "03-visualizations" "5" \
			--screenshot --screenshot-tab visualizations --screenshot-import-samples

		# 04 - Settings tab (keep it clean; no API keys)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "04-settings" "3" \
			--screenshot --screenshot-tab settings

		echo "Done. Folder: $out_dir"
		;;
	showcase)
		boot_device "$UDID"
		build_and_install "$UDID" "$DERIVED_DATA_PATH"

		local_ts=$(date "+%Y-%m-%d_%H-%M-%S")
		out_dir="$OUTPUT_ROOT/showcase_$local_ts"
		echo "Writing showcase screenshots to: $out_dir"

		# 00 - Launch
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "00-launch" "$WAIT_SECONDS"

		# 01 - Chat hero (starter prompts) - removed --args prefix
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "01-chat-hero" "4" \
			--screenshot --screenshot-tab chat --screenshot-chat-hero --screenshot-import-samples

		# 02 - Chat full demo (conversation + thinking + sources - the showstopper)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "02-chat-full" "5" \
			--screenshot --screenshot-tab chat --screenshot-chat-full --screenshot-import-samples

		# 03 - Chat with thinking steps visible
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "03-chat-thinking" "5" \
			--screenshot --screenshot-tab chat --screenshot-chat-thinking --screenshot-chat-demo --screenshot-import-samples

		# 04 - Chat with sources tray
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "04-chat-sources" "4" \
			--screenshot --screenshot-tab chat --screenshot-chat-sources --screenshot-import-samples

		# 05 - Chat details sheet (retrieved sources expanded)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "05-chat-details" "4" \
			--screenshot --screenshot-tab chat --screenshot-chat-details --screenshot-import-samples

		# 06 - Cloud consent prompt (privacy story)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "06-cloud-consent" "3" \
			--screenshot --screenshot-tab chat --screenshot-cloud-consent

		# 07 - Documents
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "07-documents" "6" \
			--screenshot --screenshot-tab documents --screenshot-import-samples

		# 08 - Visualizations (overview)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "08-visualizations-overview" "6" \
			--screenshot --screenshot-tab visualizations --screenshot-import-samples --screenshot-viz-tab overview

		# 09 - Visualizations (retrieval)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "09-visualizations-retrieval" "6" \
			--screenshot --screenshot-tab visualizations --screenshot-import-samples --screenshot-viz-tab retrieval

		# 10 - Visualizations (clustering)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "10-visualizations-clustering" "6" \
			--screenshot --screenshot-tab visualizations --screenshot-import-samples --screenshot-viz-tab clustering

		# 11 - Settings (execution & privacy)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "11-settings-execution" "3" \
			--screenshot --screenshot-tab settings

		# 12 - Settings (model selector modal)
		capture_with_args "$UDID" "$DEVICE_NAME" "$out_dir" "12-settings-model-selector" "3" \
			--screenshot --screenshot-tab settings --screenshot-settings-model-selector

		echo "Done. Folder: $out_dir"
		;;
	*)
		fail "Unknown command: $COMMAND (expected prepare|shot|run|guided|appstore|showcase)" ;;
esac
