#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="OpenIntelligence"
BUNDLE_ID="Gunndamental.OpenIntelligence"
ARTIFACT_DIR="${OPENINTELLIGENCE_AUDIT_ARTIFACT_DIR:-$ROOT_DIR/.generation-audit}"
DERIVED_DATA_PATH="${OPENINTELLIGENCE_AUDIT_DERIVED_DATA:-$ARTIFACT_DIR/DerivedData}"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild.log"
INSTALL_LOG="$ARTIFACT_DIR/install.log"
LAUNCH_LOG="$ARTIFACT_DIR/launch.log"
REPORT_JSON="${OPENINTELLIGENCE_AUDIT_REPORT:-$ARTIFACT_DIR/openintelligence_generation_audit.json}"
DEVICE_SELECTOR="${OPENINTELLIGENCE_AUDIT_DEVICE:-}"

mkdir -p "$ARTIFACT_DIR"

resolve_connected_device() {
  python3 - "$DEVICE_SELECTOR" <<'PY'
import re
import subprocess
import sys

selector = (sys.argv[1] or "").strip().lower()
raw = subprocess.check_output(["xcrun", "devicectl", "list", "devices"], text=True, stderr=subprocess.STDOUT)

devices = []
for line in raw.splitlines():
    if not line.strip():
        continue
    if line.startswith("Name") or line.startswith("---"):
        continue
    if "coredevice" not in line and "iPhone" not in line and "iPad" not in line and "Watch" not in line:
        continue
    parts = re.split(r"\s{2,}", line.strip())
    if len(parts) < 5:
        continue
    name, hostname, identifier, state, model = parts[:5]
    devices.append({
        "name": name,
        "hostname": hostname,
        "identifier": identifier,
        "state": state,
        "model": model,
    })

connected = [
    device for device in devices
    if device["state"].startswith("connected")
]

if selector:
    filtered = [
        device for device in connected
        if selector in device["name"].lower()
        or selector in device["identifier"].lower()
        or selector in device["model"].lower()
    ]
    connected = filtered

iphones = [device for device in connected if "iphone" in device["model"].lower()]
chosen = iphones[0] if iphones else (connected[0] if connected else None)
if not chosen:
    raise SystemExit(1)

print(chosen["identifier"])
print(chosen["name"])
print(chosen["model"])
PY
}

mapfile -t DEVICE_INFO < <(resolve_connected_device)
if [[ ${#DEVICE_INFO[@]} -lt 3 ]]; then
  echo "error: no connected physical iPhone found for generation audit" >&2
  echo "Use ./scripts/build_simulator_smoke.sh for a compile-only simulator check." >&2
  exit 1
fi

DEVICE_ID="${DEVICE_INFO[0]}"
DEVICE_NAME="${DEVICE_INFO[1]}"
DEVICE_MODEL="${DEVICE_INFO[2]}"

echo "Running generation audit on connected device"
echo "Device: $DEVICE_NAME ($DEVICE_MODEL)"
echo "Identifier: $DEVICE_ID"

echo "Building debug app for physical device"
xcodebuild \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >"$BUILD_LOG" 2>&1

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/OpenIntelligence.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  echo "build log: $BUILD_LOG" >&2
  exit 1
fi

echo "Installing app on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >"$INSTALL_LOG" 2>&1

echo "Launching audit mode"
set +e
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --console \
  "$BUNDLE_ID" \
  -OPENINTELLIGENCE_RUN_GENERATION_AUDIT >"$LAUNCH_LOG" 2>&1
LAUNCH_EXIT=$?
set -e

python3 - "$LAUNCH_LOG" "$REPORT_JSON" "$LAUNCH_EXIT" <<'PY'
import json
import pathlib
import re
import sys

launch_log = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
launch_exit = int(sys.argv[3])

text = launch_log.read_text(errors="ignore") if launch_log.exists() else ""
match = re.search(r"GENERATION_AUDIT_REPORT_BEGIN\s*(\{.*?\})\s*GENERATION_AUDIT_REPORT_END", text, re.S)
if not match:
    print("error: generation audit markers were not found in device launch output", file=sys.stderr)
    print(f"launch log: {launch_log}", file=sys.stderr)
    if launch_exit != 0:
        print(f"device launch exit code: {launch_exit}", file=sys.stderr)
    raise SystemExit(2)

report = json.loads(match.group(1))
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

print(f"Audit report written to {report_path}")
print(f"Overall result: {'PASS' if report.get('passed') else 'FAIL'}")
print(f"Passed scenarios: {report.get('passedScenarioCount', 0)}")
print(f"Failed scenarios: {report.get('failedScenarioCount', 0)}")

for scenario in report.get('scenarios', []):
    scenario_status = 'PASS' if scenario.get('passed') else 'FAIL'
    print(f"- {scenario_status}: {scenario.get('name')}")
    for assertion in scenario.get('assertions', []):
        prefix = '  ok ' if assertion.get('passed') else '  xx '
        print(f"{prefix}{assertion.get('label')}: {assertion.get('details')}")

if not report.get('passed'):
    raise SystemExit(1)
PY

echo "Generation audit passed"
echo "Build log: $BUILD_LOG"
echo "Install log: $INSTALL_LOG"
echo "Launch log: $LAUNCH_LOG"
