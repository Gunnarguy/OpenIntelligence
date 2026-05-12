#!/usr/bin/env python3
"""Run local RAG benchmark manifests through DebugRAGValidationHarness.

This is intentionally an outside controller. The Swift app still performs
ingestion, querying, report writing, and trace writing through the debug
validation harness.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import webbrowser
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO_ROOT / "Benchmarks" / "rag_validation_sample.json"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "BenchmarkRuns"
DEFAULT_PROJECT = REPO_ROOT / "OpenIntelligence.xcodeproj"
DEFAULT_SCHEME = "OpenIntelligence"
DEFAULT_CONFIGURATION = "Debug"
DEFAULT_BUNDLE_ID = "Gunndamental.OpenIntelligence"
DEFAULT_TIMEOUT_SECONDS = 300
DEFAULT_BUILD_TIMEOUT_SECONDS = 900
DEFAULT_RUNTIME = "mac"
DEFAULT_SIMULATOR_BUILD_DESTINATION = "generic/platform=iOS Simulator"
DEFAULT_DEVICE_BUILD_DESTINATION = "generic/platform=iOS"
DEFAULT_MAC_BUILD_DESTINATION = "platform=macOS,variant=Mac Catalyst"
DEFAULT_DERIVED_DATA_ROOT = Path("/tmp/openintelligence-rag-bench")
DEFAULT_PCC_CONSENT = "allow"
DEFAULT_BENCHMARK_ENTITLEMENT = "lifetime"
DEFAULT_APP_REFRESH_FILE_LIMIT = 0
DEFAULT_MAC_BUILD_METHOD = "scheme"
DEVICE_STORAGE_PREFIX = "Library/Application Support/OpenIntelligenceRAGBenchmark"
DEVICE_INPUT_PREFIX = "Documents/OpenIntelligenceRAGBenchmarkInputs"
MAC_BENCHMARK_ENTRYPOINT = (
    REPO_ROOT / "OpenIntelligence" / "App" / "OpenIntelligenceMacBenchmarkApp.swift"
)
MAC_BENCHMARK_EXCLUDED_SOURCES = "OpenIntelligenceApp.swift ContentView.swift BackgroundTaskService.swift IngestionLiveActivityAttributes.swift IngestionLiveActivityService.swift"

ALLOWED_CATEGORIES = {
    "exact_value",
    "table_spec",
    "missing_evidence",
    "lost_in_middle",
    "multi_hop",
    "summary",
    "retrieval_only",
}
ALLOWED_BEHAVIORS = {"answer", "abstain"}
QUALITY_MODE_ALIASES = {
    "standard": "standard",
    "deepthink": "deep-think",
    "deep-think": "deep-think",
    "deep_think": "deep-think",
    "agentic": "deep-think",
    "maximum": "maximum",
    "max": "maximum",
}

DEFAULT_ABSTAIN_PATTERNS = [
    r"(?i)\bnot enough (information|evidence|context)\b",
    r"(?i)\binsufficient (information|evidence|context)\b",
    r"(?i)\b(cannot|can't) determine\b",
    r"(?i)\bnot (found|provided|available|specified|stated)\b",
    r"(?i)\bdoes not contain\b",
    r"(?i)\bno (evidence|source|support)\b",
    r"(?i)\bi (do not|don't) know\b",
]


class BenchmarkError(Exception):
    """Raised for manifest or runner setup problems."""


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def run_id() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def ensure_text_output(value: str | bytes | bytearray | memoryview | None) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, memoryview):
        return value.tobytes().decode("utf-8", errors="replace")
    return bytes(value).decode("utf-8", errors="replace")


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return cleaned.strip("-") or "case"


def rel(path: Path, base: Path) -> str:
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def resolve_repo_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path


def input_file_identity(path: Path) -> str:
    resolved_root = REPO_ROOT.resolve()
    resolved_path = path.resolve(strict=False)
    try:
        return str(resolved_path.relative_to(resolved_root))
    except ValueError:
        return str(resolved_path)


def staged_case_input_name(case: dict[str, Any], input_file: Path) -> str:
    matching_names = [
        path for path in case["input_files"] if path.name.casefold() == input_file.name.casefold()
    ]
    if len(matching_names) <= 1:
        return input_file.name

    suffix = input_file.suffix
    stem = slug(input_file.stem or "input")
    digest = hashlib.sha1(input_file_identity(input_file).encode("utf-8")).hexdigest()[:10]
    return f"{stem}-{digest}{suffix}"


def case_file_entries(case: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "path": str(path),
            "display": rel(path, REPO_ROOT),
            "exists": path.exists(),
        }
        for path in case["input_files"]
    ]


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except json.JSONDecodeError as exc:
        raise BenchmarkError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(manifest, dict):
        raise BenchmarkError("Manifest root must be a JSON object")
    if not isinstance(manifest.get("cases"), list):
        raise BenchmarkError("Manifest must contain a cases array")
    return manifest


def normalize_quality_mode(raw: Any, default: str) -> str:
    value = str(raw or default).strip().lower()
    if value not in QUALITY_MODE_ALIASES:
        allowed = ", ".join(sorted(set(QUALITY_MODE_ALIASES.values())))
        raise BenchmarkError(f"Unsupported quality_mode '{raw}'. Use one of: {allowed}")
    return QUALITY_MODE_ALIASES[value]


def normalize_patterns(raw: Any, field_name: str = "expected_answer_patterns") -> list[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, list) and all(isinstance(item, str) for item in raw):
        return raw
    raise BenchmarkError(f"{field_name} must be a string array")


def resolve_input_files(raw_files: Any) -> list[Path]:
    if not isinstance(raw_files, list) or not all(isinstance(item, str) for item in raw_files):
        raise BenchmarkError("input_files must be an array of file paths")
    return [resolve_repo_path(item) for item in raw_files]


def normalize_expected_source(case: dict[str, Any]) -> dict[str, Any]:
    source = case.get("expected_source") or {}
    if not isinstance(source, dict):
        raise BenchmarkError("expected_source must be an object when provided")

    filename = source.get("filename", case.get("expected_source_filename"))
    page = source.get("page", case.get("expected_source_page"))
    if filename is not None and not isinstance(filename, str):
        raise BenchmarkError("expected_source.filename must be a string or null")
    if page is not None and not isinstance(page, (str, int)):
        raise BenchmarkError("expected_source.page must be a string, number, or null")
    return {"filename": filename, "page": str(page) if page is not None else None}


def normalize_case(
    raw: dict[str, Any],
    index: int,
    defaults: dict[str, Any],
    timeout_override: int | None,
) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise BenchmarkError(f"Case {index + 1} must be a JSON object")

    case_id = str(raw.get("id", "")).strip()
    if not case_id:
        raise BenchmarkError(f"Case {index + 1} is missing id")

    category = str(raw.get("category", "")).strip()
    if category not in ALLOWED_CATEGORIES:
        allowed = ", ".join(sorted(ALLOWED_CATEGORIES))
        raise BenchmarkError(f"Case '{case_id}' has unsupported category '{category}'. Allowed: {allowed}")

    query = str(raw.get("query", "")).strip()
    if not query:
        raise BenchmarkError(f"Case '{case_id}' is missing query")

    expected_behavior = str(raw.get("expected_behavior", "answer")).strip().lower()
    if expected_behavior not in ALLOWED_BEHAVIORS:
        raise BenchmarkError(f"Case '{case_id}' has unsupported expected_behavior '{expected_behavior}'")

    timeout = int(
        timeout_override
        if timeout_override is not None
        else raw.get("timeout_seconds", defaults.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))
    )
    if timeout < 1:
        raise BenchmarkError(f"Case '{case_id}' timeout_seconds must be positive")

    input_files = resolve_input_files(raw.get("input_files", []))
    return {
        "id": case_id,
        "safe_id": slug(case_id),
        "category": category,
        "query": query,
        "quality_mode": normalize_quality_mode(
            raw.get("quality_mode", defaults.get("quality_mode")),
            str(defaults.get("quality_mode", "standard")),
        ),
        "input_files": input_files,
        "missing_files": [path for path in input_files if not path.exists()],
        "expected_behavior": expected_behavior,
        "expected_answer_patterns": normalize_patterns(raw.get("expected_answer_patterns")),
        "abstain_patterns": normalize_patterns(raw.get("abstain_patterns"), "abstain_patterns")
        or DEFAULT_ABSTAIN_PATTERNS,
        "expected_source": normalize_expected_source(raw),
        "source_dataset": raw.get("source_dataset"),
        "license_note": raw.get("license_note"),
        "timeout_seconds": timeout,
        "skip_ingest": bool(raw.get("skip_ingest", False)),
    }


def normalize_cases(manifest: dict[str, Any], timeout_override: int | None = None) -> list[dict[str, Any]]:
    defaults = manifest.get("defaults", {})
    if not isinstance(defaults, dict):
        raise BenchmarkError("defaults must be an object when provided")
    return [normalize_case(raw, index, defaults, timeout_override) for index, raw in enumerate(manifest["cases"])]


def run_command(
    command: list[str],
    *,
    log_path: Path | None = None,
    timeout: int | None = None,
    check: bool = True,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    started = now_utc()
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    try:
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired as exc:
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            stdout = ensure_text_output(exc.stdout)
            stderr = ensure_text_output(exc.stderr)
            with log_path.open("a", encoding="utf-8") as fh:
                fh.write(f"$ {' '.join(command)}\n")
                fh.write(f"started_at={started}\n")
                fh.write(f"timed_out_at={now_utc()}\n")
                fh.write(f"timeout_seconds={timeout}\n\n")
                if stdout:
                    fh.write("STDOUT\n")
                    fh.write(stdout)
                    fh.write("\n")
                if stderr:
                    fh.write("STDERR\n")
                    fh.write(stderr)
                    fh.write("\n")
        raise BenchmarkError(f"Command timed out after {timeout}s: {' '.join(command)}") from exc
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(f"$ {' '.join(command)}\n")
            fh.write(f"started_at={started}\n")
            fh.write(f"finished_at={now_utc()}\n")
            fh.write(f"exit_code={completed.returncode}\n\n")
            if completed.stdout:
                fh.write("STDOUT\n")
                fh.write(completed.stdout)
                fh.write("\n")
            if completed.stderr:
                fh.write("STDERR\n")
                fh.write(completed.stderr)
                fh.write("\n")
    if check and completed.returncode != 0:
        tail = completed.stderr[-2000:] or completed.stdout[-2000:]
        raise BenchmarkError(f"Command failed ({completed.returncode}): {' '.join(command)}\n{tail}")
    return completed


def find_simulator(device_hint: str | None) -> dict[str, Any]:
    result = run_command(["xcrun", "simctl", "list", "devices", "available", "-j"])
    data = json.loads(result.stdout)
    devices: list[dict[str, Any]] = []
    for runtime, runtime_devices in data.get("devices", {}).items():
        if not isinstance(runtime_devices, list):
            continue
        for device in runtime_devices:
            if not device.get("isAvailable", True):
                continue
            name = str(device.get("name", ""))
            if "iPhone" not in name and "iPad" not in name:
                continue
            entry = dict(device)
            entry["runtime"] = runtime
            devices.append(entry)

    if not devices:
        raise BenchmarkError("No available iOS Simulator devices found")

    if device_hint:
        hint = device_hint.lower()
        for device in devices:
            if hint in str(device.get("udid", "")).lower() or hint in str(device.get("name", "")).lower():
                return device
        raise BenchmarkError(f"No available simulator matched --device '{device_hint}'")

    booted = [device for device in devices if device.get("state") == "Booted"]
    if booted:
        return booted[0]
    iphones = [device for device in devices if "iPhone" in str(device.get("name", ""))]
    return iphones[0] if iphones else devices[0]


def boot_simulator(device: dict[str, Any], run_dir: Path) -> None:
    udid = str(device["udid"])
    if device.get("state") != "Booted":
        run_command(["xcrun", "simctl", "boot", udid], log_path=run_dir / "simulator.log", check=False)
    run_command(["xcrun", "simctl", "bootstatus", udid, "-b"], log_path=run_dir / "simulator.log")


def devicectl_json(command: list[str], json_path: Path, *, log_path: Path | None = None) -> dict[str, Any]:
    if json_path.exists():
        json_path.unlink()
    run_command(command + ["--json-output", str(json_path)], log_path=log_path)
    try:
        return json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BenchmarkError(f"Could not read devicectl JSON output at {json_path}") from exc


def device_name(device: dict[str, Any]) -> str:
    return str(device.get("deviceProperties", {}).get("name") or device.get("name") or "")


def device_udid(device: dict[str, Any]) -> str:
    return str(device.get("hardwareProperties", {}).get("udid") or "")


def device_identifier(device: dict[str, Any]) -> str:
    return str(device.get("identifier") or device_udid(device) or device_name(device))


def is_connected_ios_device(device: dict[str, Any]) -> bool:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    properties = device.get("deviceProperties", {})
    if hardware.get("platform") != "iOS":
        return False
    if hardware.get("reality") != "physical":
        return False
    if hardware.get("deviceType") not in {"iPhone", "iPad"}:
        return False
    return connection.get("tunnelState") == "connected" or properties.get("ddiServicesAvailable") is True


def find_physical_device(device_hint: str | None, run_dir: Path) -> dict[str, Any]:
    json_path = run_dir / "devicectl_devices.json"
    data = devicectl_json(
        ["xcrun", "devicectl", "list", "devices"],
        json_path,
        log_path=run_dir / "device.log",
    )
    devices = [
        device
        for device in data.get("result", {}).get("devices", [])
        if isinstance(device, dict) and is_connected_ios_device(device)
    ]
    if not devices:
        raise BenchmarkError("No connected physical iPhone or iPad was found by devicectl")

    if device_hint:
        hint = device_hint.lower()
        for device in devices:
            values = [
                device_identifier(device),
                device_udid(device),
                device_name(device),
                str(device.get("hardwareProperties", {}).get("serialNumber") or ""),
                str(device.get("hardwareProperties", {}).get("marketingName") or ""),
            ]
            if any(hint in value.lower() for value in values):
                return device
        raise BenchmarkError(f"No connected physical device matched --device '{device_hint}'")

    iphones = [device for device in devices if device.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
    return iphones[0] if iphones else devices[0]


def default_derived_data_path(run_dir: Path) -> Path:
    return DEFAULT_DERIVED_DATA_ROOT / "DerivedData"


def resolve_derived_data_path(args: argparse.Namespace, run_dir: Path) -> Path:
    if args.derived_data:
        path = Path(args.derived_data).expanduser()
        if not path.is_absolute():
            path = REPO_ROOT / path
        return path
    return default_derived_data_path(run_dir)


def is_resource_fork_error(exc: BenchmarkError) -> bool:
    text = str(exc).lower()
    return "resource fork" in text or "finder information" in text or "detritus" in text


def is_timeout_error(exc: BenchmarkError) -> bool:
    return str(exc).startswith("Command timed out after")


def xcodebuild_env() -> dict[str, str]:
    # Avoid copying Finder/resource fork metadata from synced folders into the .app.
    return {"COPYFILE_DISABLE": "1"}


def build_destination(args: argparse.Namespace) -> str:
    if args.destination:
        return args.destination
    if args.runtime == "mac":
        return DEFAULT_MAC_BUILD_DESTINATION
    if args.runtime == "device":
        return DEFAULT_DEVICE_BUILD_DESTINATION
    return DEFAULT_SIMULATOR_BUILD_DESTINATION


def build_sdk(args: argparse.Namespace) -> str:
    if args.runtime == "mac":
        return "macosx"
    return "iphoneos" if args.runtime == "device" else "iphonesimulator"


def product_platform_suffix(args: argparse.Namespace) -> str:
    if args.runtime == "mac":
        return "maccatalyst"
    return "iphoneos" if args.runtime == "device" else "iphonesimulator"


def product_dir_names(args: argparse.Namespace) -> list[str]:
    if args.runtime == "mac":
        return [args.configuration, f"{args.configuration}-maccatalyst"]
    return [f"{args.configuration}-{product_platform_suffix(args)}"]


def uses_mac_app_only_build_method(args: argparse.Namespace) -> bool:
    return args.runtime == "mac" and args.mac_build_method == "app-only"


def mac_benchmark_project_path(args: argparse.Namespace, run_dir: Path) -> Path:
    source_project = Path(args.project).expanduser()
    return REPO_ROOT / f"{source_project.stem}MacBench-{run_dir.name}.xcodeproj"


def write_mac_benchmark_entrypoint() -> Path:
    content = """#if targetEnvironment(macCatalyst)
import SwiftUI

@main
struct OpenIntelligenceMacBenchmarkApp: App {
    init() {
        #if DEBUG
        DebugRAGValidationHarness.runHeadlessIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Text(\"OpenIntelligence Mac Benchmark\")
        }
    }
}
#endif
"""
    MAC_BENCHMARK_ENTRYPOINT.write_text(content, encoding="utf-8")
    return MAC_BENCHMARK_ENTRYPOINT


def patch_mac_benchmark_project(project_path: Path, original_project_name: str) -> None:
    pbxproj_path = project_path / "project.pbxproj"
    text = pbxproj_path.read_text(encoding="utf-8")

    replacements = [
        "\t\tF0A100012F1A000100AA1001 /* OpenIntelligenceLiveActivities.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = F0A100022F1A000100AA1001 /* OpenIntelligenceLiveActivities.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\n",
        "\t\t\t\tF0A100072F1A000100AA1001 /* Embed App Extensions */,\n",
        "\t\t\t\tF0A100152F1A000100AA1001 /* PBXTargetDependency */,\n",
        "\t\tF0A100142F1A000100AA1001 /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = B0D565D62E98AC50001274A2 /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = F0A100102F1A000100AA1001;\n\t\t\tremoteInfo = OpenIntelligenceLiveActivities;\n\t\t};\n",
        '\t\tF0A100072F1A000100AA1001 /* Embed App Extensions */ = {\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\tF0A100012F1A000100AA1001 /* OpenIntelligenceLiveActivities.appex in Embed App Extensions */,\n\t\t\t);\n\t\t\tname = "Embed App Extensions";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n',
        "\t\tF0A100152F1A000100AA1001 /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = F0A100102F1A000100AA1001 /* OpenIntelligenceLiveActivities */;\n\t\t\ttargetProxy = F0A100142F1A000100AA1001 /* PBXContainerItemProxy */;\n\t\t};\n",
    ]

    for snippet in replacements:
        text = text.replace(snippet, "")

    debug_marker = "\t\t\t\tCURRENT_PROJECT_VERSION = 32;\n\t\t\t\tDERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO;\n"
    debug_replacement = (
        "\t\t\t\tCURRENT_PROJECT_VERSION = 32;\n"
        f'\t\t\t\t"EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]" = "{MAC_BENCHMARK_EXCLUDED_SOURCES}";\n'
        "\t\t\t\tDERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO;\n"
    )
    text = text.replace(debug_marker, debug_replacement, 1)

    pbxproj_path.write_text(text, encoding="utf-8")

    for scheme_path in project_path.glob("xcshareddata/xcschemes/*.xcscheme"):
        scheme_text = scheme_path.read_text(encoding="utf-8")
        scheme_text = scheme_text.replace(
            f"container:{original_project_name}",
            f"container:{project_path.name}",
        )
        scheme_path.write_text(scheme_text, encoding="utf-8")


def prepare_benchmark_project(args: argparse.Namespace, run_dir: Path) -> Path:
    source_project = Path(args.project).expanduser()
    if not uses_mac_app_only_build_method(args):
        return source_project

    temp_project = mac_benchmark_project_path(args, run_dir)
    shutil.rmtree(temp_project, ignore_errors=True)
    shutil.copytree(source_project, temp_project)
    patch_mac_benchmark_project(temp_project, source_project.name)
    return temp_project


def prepare_benchmark_sources(args: argparse.Namespace) -> list[Path]:
    if not uses_mac_app_only_build_method(args):
        return []
    return [write_mac_benchmark_entrypoint()]


def cleanup_benchmark_project(
    args: argparse.Namespace, project_path: Path, source_paths: list[Path]
) -> None:
    if uses_mac_app_only_build_method(args):
        shutil.rmtree(project_path, ignore_errors=True)
        for source_path in source_paths:
            try:
                source_path.unlink()
            except FileNotFoundError:
                pass


def build_command(
    args: argparse.Namespace, derived_data: Path, project_path: Path
) -> list[str]:
    command = [
        "xcodebuild",
        "-project",
        str(project_path),
        "-scheme",
        args.scheme,
        "-configuration",
        args.configuration,
        "-destination",
        build_destination(args),
        "-sdk",
        build_sdk(args),
        "-derivedDataPath",
        str(derived_data),
        "build",
    ]
    if args.runtime == "mac":
        command.insert(-1, "EFFECTIVE_PLATFORM_NAME_MAC_CATALYST_USE_DISTINCT_BUILD_DIR=NO")
    return command


def find_app(args: argparse.Namespace, derived_data: Path) -> Path | None:
    for product_dir_name in product_dir_names(args):
        app_path = derived_data / "Build" / "Products" / product_dir_name / f"{args.app_name}.app"
        if app_path.exists():
            return app_path

    products_dir = derived_data / "Build" / "Products"
    candidates = sorted(products_dir.glob(f"*/{args.app_name}.app"))
    return candidates[0] if candidates else None


def log_tail(path: Path, limit: int = 4000) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return text[-limit:]


def app_executable_path(args: argparse.Namespace, app_path: Path) -> Path:
    if args.runtime == "mac":
        return app_path / "Contents" / "MacOS" / args.app_name
    return app_path / args.app_name


def app_bundle_ready(args: argparse.Namespace, app_path: Path | None) -> bool:
    if app_path is None or not app_path.exists():
        return False
    if not app_executable_path(args, app_path).exists():
        return False
    if not (app_path / "_CodeSignature" / "CodeResources").exists():
        return False
    if args.runtime in {"device", "mac"}:
        return True
    verification = subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(app_path)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
    )
    return verification.returncode == 0


def app_bundle_updated_after(app_path: Path | None, start_time: float) -> bool:
    if app_path is None:
        return False
    try:
        return app_path.stat().st_mtime >= start_time
    except OSError:
        return False


def stop_process(process: subprocess.Popen[Any]) -> int | None:
    if process.poll() is not None:
        return process.returncode
    process.terminate()
    try:
        return process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        return process.wait(timeout=10)


def run_xcodebuild_until_app_ready(
    args: argparse.Namespace,
    derived_data: Path,
    log_path: Path,
    project_path: Path,
) -> None:
    command = build_command(args, derived_data, project_path)
    env = os.environ.copy()
    env.update(xcodebuild_env())
    started = now_utc()
    log_path.parent.mkdir(parents=True, exist_ok=True)

    with log_path.open("a", encoding="utf-8") as fh:
        fh.write(f"$ {' '.join(command)}\n")
        fh.write(f"started_at={started}\n")
        fh.flush()
        start_wall = time.time()
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            env=env,
            stdout=fh,
            stderr=subprocess.STDOUT,
            text=True,
        )
        start = time.monotonic()
        while True:
            returncode = process.poll()
            if returncode is not None:
                fh.write(f"\nfinished_at={now_utc()}\n")
                fh.write(f"exit_code={returncode}\n\n")
                fh.flush()
                if returncode != 0:
                    raise BenchmarkError(f"Command failed ({returncode}): {' '.join(command)}\n{log_tail(log_path)}")
                return

            app_path = find_app(args, derived_data)
            if app_bundle_updated_after(app_path, start_wall) and app_bundle_ready(args, app_path):
                returncode = stop_process(process)
                fh.write(f"\napp_bundle_ready_at={now_utc()}\n")
                fh.write(f"terminated_xcodebuild_exit_code={returncode}\n")
                fh.write("Continuing because the signed app bundle is ready.\n\n")
                fh.flush()
                return

            if time.monotonic() - start > args.build_timeout_seconds:
                returncode = stop_process(process)
                fh.write(f"\ntimed_out_at={now_utc()}\n")
                fh.write(f"timeout_seconds={args.build_timeout_seconds}\n")
                fh.write(f"terminated_xcodebuild_exit_code={returncode}\n\n")
                fh.flush()
                if app_bundle_ready(args, find_app(args, derived_data)):
                    return
                raise BenchmarkError(f"Command timed out after {args.build_timeout_seconds}s: {' '.join(command)}")

            time.sleep(2)


def build_app(args: argparse.Namespace, destination: str, run_dir: Path) -> Path:
    derived_data = resolve_derived_data_path(args, run_dir)
    log_path = run_dir / "xcodebuild.log"
    project_path = prepare_benchmark_project(args, run_dir)
    source_paths = prepare_benchmark_sources(args)

    try:
        if not args.skip_build:
            try:
                print(f"Building app for {build_destination(args)}", flush=True)
                print(f"DerivedData: {derived_data}", flush=True)
                run_xcodebuild_until_app_ready(
                    args, derived_data, log_path, project_path
                )
            except BenchmarkError as exc:
                app_path = find_app(args, derived_data)
                if is_timeout_error(exc) and app_path is not None:
                    with log_path.open("a", encoding="utf-8") as fh:
                        fh.write(
                            "\nBuild command timed out after producing an app bundle. "
                            "Continuing because xcodebuild can hang in device-pruning after the app exists.\n\n"
                        )
                    print(
                        "Build command timed out after producing OpenIntelligence.app; continuing.",
                        flush=True,
                    )
                    return app_path
                fallback = default_derived_data_path(run_dir)
                if is_resource_fork_error(exc) and derived_data != fallback:
                    with log_path.open("a", encoding="utf-8") as fh:
                        fh.write(
                            "\nRetrying with unsynced DerivedData under /tmp after resource-fork codesign failure.\n\n"
                        )
                    derived_data = fallback
                    print(f"Retrying build for {build_destination(args)}", flush=True)
                    print(f"DerivedData: {derived_data}", flush=True)
                    run_xcodebuild_until_app_ready(
                        args, derived_data, log_path, project_path
                    )
                else:
                    raise

        app_path = find_app(args, derived_data)
        if app_path is not None:
            return app_path
        raise BenchmarkError(f"Built app not found under {derived_data}")
    finally:
        cleanup_benchmark_project(args, project_path, source_paths)


def install_app(device_udid: str, app_path: Path, run_dir: Path) -> None:
    run_command(["xcrun", "simctl", "install", device_udid, str(app_path)], log_path=run_dir / "simulator.log")


def uninstall_app(device_udid: str, bundle_id: str, run_dir: Path) -> None:
    run_command(["xcrun", "simctl", "uninstall", device_udid, bundle_id], log_path=run_dir / "simulator.log", check=False)


def install_app_on_physical_device(device_ref: str, app_path: Path, run_dir: Path) -> None:
    run_command(
        ["xcrun", "devicectl", "device", "install", "app", "--device", device_ref, str(app_path)],
        log_path=run_dir / "device.log",
    )


def uninstall_app_from_physical_device(device_ref: str, bundle_id: str, run_dir: Path) -> None:
    run_command(
        ["xcrun", "devicectl", "device", "uninstall", "app", "--device", device_ref, bundle_id],
        log_path=run_dir / "device.log",
        check=False,
    )


def mac_app_container_root(bundle_id: str) -> Path:
    return Path.home() / "Library" / "Containers" / bundle_id / "Data"


def mac_app_executable(app_path: Path) -> Path:
    return app_path / "Contents" / "MacOS" / app_path.stem


def extract_mac_container_root(output: str) -> Path | None:
    for line in output.splitlines():
        prefix = "[RAGValidation] Storage: "
        if prefix not in line:
            continue

        storage_path = Path(line.split(prefix, 1)[1].strip())
        for candidate in [storage_path, *storage_path.parents]:
            if candidate.name == "Data":
                return candidate
    return None


def discover_mac_runtime_container_root(
    *,
    app_path: Path,
    bundle_id: str,
    run_dir: Path,
    pcc_consent: str,
    benchmark_entitlement: str,
) -> Path | None:
    probe_case_dir = run_dir / "mac_container_probe"
    probe_stdout = probe_case_dir / "mac_probe_stdout.log"
    probe_stderr = probe_case_dir / "mac_probe_stderr.log"
    probe_case_dir.mkdir(parents=True, exist_ok=True)

    command = [
        str(mac_app_executable(app_path)),
        "--rag-validation",
        "--rag-validation-query",
        "container probe",
        "--rag-validation-storage",
        f"{DEVICE_STORAGE_PREFIX}/mac-container-probe/storage",
        "--rag-validation-quality",
        "standard",
        "--rag-validation-skip-ingest",
    ]
    if pcc_consent != "default":
        command.extend(["--rag-validation-pcc-consent", pcc_consent])
    if benchmark_entitlement != "current":
        command.extend(["--rag-validation-entitlement", benchmark_entitlement])

    stdout = ""
    stderr = ""
    try:
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            timeout=20,
        )
        stdout = completed.stdout or ""
        stderr = completed.stderr or ""
    except subprocess.TimeoutExpired as exc:
        stdout = ensure_text_output(exc.stdout)
        stderr = ensure_text_output(exc.stderr)
    finally:
        probe_stdout.write_text(stdout, encoding="utf-8")
        probe_stderr.write_text(stderr, encoding="utf-8")
        quit_mac_app(bundle_id)

    return extract_mac_container_root(stdout + "\n" + stderr)


def quit_mac_app(bundle_id: str) -> None:
    subprocess.run(
        ["osascript", "-e", f'tell application id "{bundle_id}" to quit'],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def refresh_app_install(
    args: argparse.Namespace,
    *,
    target_info: dict[str, Any],
    app_path: Path,
    run_dir: Path,
    reason: str,
) -> None:
    message = f"Refreshing app install: {reason}"
    print(message, flush=True)
    with (run_dir / "runner_events.log").open("a", encoding="utf-8") as fh:
        fh.write(f"{now_utc()} {message}\n")

    if args.runtime == "device":
        device_ref = str(target_info["identifier"])
        uninstall_app_from_physical_device(device_ref, args.bundle_id, run_dir)
        install_app_on_physical_device(device_ref, app_path, run_dir)
    elif args.runtime == "mac":
        container_root = Path(
            target_info.get("container_root") or mac_app_container_root(args.bundle_id)
        )
        shutil.rmtree(container_root / "Documents" / "OpenIntelligenceRAGBenchmarkInputs", ignore_errors=True)
        shutil.rmtree(
            container_root / "Library" / "Application Support" / "OpenIntelligenceRAGBenchmark",
            ignore_errors=True,
        )
    else:
        device_udid = str(target_info["udid"])
        uninstall_app(device_udid, args.bundle_id, run_dir)
        install_app(device_udid, app_path, run_dir)


def launch_case(
    case: dict[str, Any],
    *,
    device_udid: str,
    bundle_id: str,
    case_dir: Path,
    pcc_consent: str,
    benchmark_entitlement: str,
) -> dict[str, Any]:
    storage_dir = case_dir / "storage"
    output_dir = storage_dir / "ValidationOutput"
    report_path = output_dir / "rag_validation_report.txt"
    trace_path = output_dir / "pipeline_trace.log"
    stdout_path = case_dir / "simctl_stdout.log"
    stderr_path = case_dir / "simctl_stderr.log"
    case_dir.mkdir(parents=True, exist_ok=True)
    storage_dir.mkdir(parents=True, exist_ok=True)

    command = [
        "xcrun",
        "simctl",
        "launch",
        "--terminate-running-process",
        device_udid,
        bundle_id,
        "--rag-validation",
        "--rag-validation-query",
        case["query"],
        "--rag-validation-storage",
        str(storage_dir),
        "--rag-validation-quality",
        case["quality_mode"],
    ]
    input_arg = ",".join(str(path) for path in case["input_files"])
    if input_arg:
        command.extend(["--rag-validation-files", input_arg])
    if case["skip_ingest"]:
        command.append("--rag-validation-skip-ingest")
    if pcc_consent != "default":
        command.extend(["--rag-validation-pcc-consent", pcc_consent])
    if benchmark_entitlement != "current":
        command.extend(["--rag-validation-entitlement", benchmark_entitlement])

    run_command(["xcrun", "simctl", "terminate", device_udid, bundle_id], check=False)
    start = time.monotonic()
    completed = run_command(command, check=False)
    stdout_path.write_text(completed.stdout or "", encoding="utf-8")
    stderr_path.write_text(completed.stderr or "", encoding="utf-8")

    timed_out = False
    while not report_path.exists():
        if time.monotonic() - start > case["timeout_seconds"]:
            timed_out = True
            break
        time.sleep(1)

    latency = time.monotonic() - start
    run_command(["xcrun", "simctl", "terminate", device_udid, bundle_id], check=False)
    return {
        "launcher": "simctl",
        "launch_returncode": completed.returncode,
        "latency_seconds": round(latency, 3),
        "timed_out": timed_out,
        "report_path": report_path if report_path.exists() else None,
        "trace_path": trace_path if trace_path.exists() else None,
        "stdout_path": stdout_path,
        "stderr_path": stderr_path,
    }


def device_case_paths(run_id_value: str, case: dict[str, Any]) -> dict[str, str]:
    safe_id = case["safe_id"]
    return {
        "input_dir": f"{DEVICE_INPUT_PREFIX}/{run_id_value}/{safe_id}",
        "storage_dir": f"{DEVICE_STORAGE_PREFIX}/{run_id_value}/{safe_id}/storage",
        "output_dir": f"{DEVICE_STORAGE_PREFIX}/{run_id_value}/{safe_id}/storage/ValidationOutput",
    }


def copy_case_inputs_to_device(
    case: dict[str, Any],
    *,
    device_ref: str,
    bundle_id: str,
    input_dir: str,
    case_dir: Path,
) -> list[str]:
    if not case["input_files"]:
        return []

    device_paths: list[str] = []
    for input_file in case["input_files"]:
        staged_name = staged_case_input_name(case, input_file)
        destination = f"{input_dir}/{staged_name}"
        command = [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "to",
            "--device",
            device_ref,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            bundle_id,
            "--source",
            str(input_file),
            "--destination",
            destination,
        ]
        run_command(command, log_path=case_dir / "device.log")
        device_paths.append(destination)
    return device_paths


def copy_device_artifact(
    *,
    device_ref: str,
    bundle_id: str,
    source: str,
    destination_dir: Path,
    log_path: Path,
) -> Path | None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination_path = destination_dir / Path(source).name
    if destination_path.exists():
        destination_path.unlink()
    completed = run_command(
        [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            device_ref,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            bundle_id,
            "--source",
            source,
            "--destination",
            str(destination_path),
        ],
        log_path=log_path,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return destination_path if destination_path.exists() else None


def copy_case_inputs_to_mac(
    case: dict[str, Any], *, container_root: Path, input_dir: str
) -> list[str]:
    if not case["input_files"]:
        return []

    destination_root = container_root / input_dir
    destination_root.mkdir(parents=True, exist_ok=True)

    mac_paths: list[str] = []
    for input_file in case["input_files"]:
        staged_name = staged_case_input_name(case, input_file)
        destination = destination_root / staged_name
        shutil.copy2(input_file, destination)
        mac_paths.append(f"{input_dir}/{staged_name}")
    return mac_paths


def copy_mac_artifact(
    *,
    container_root: Path,
    relative_output_dir: str,
    filename: str,
    local_output_dir: Path,
) -> Path | None:
    source = container_root / relative_output_dir / filename
    if not source.exists():
        return None
    local_output_dir.mkdir(parents=True, exist_ok=True)
    destination = local_output_dir / filename
    shutil.copy2(source, destination)
    return destination


def launch_case_on_mac(
    case: dict[str, Any],
    *,
    run_id_value: str,
    app_path: Path,
    bundle_id: str,
    container_root: Path,
    case_dir: Path,
    pcc_consent: str,
    benchmark_entitlement: str,
) -> dict[str, Any]:
    storage_dir = case_dir / "storage"
    output_dir = storage_dir / "ValidationOutput"
    stdout_path = case_dir / "mac_open_stdout.log"
    stderr_path = case_dir / "mac_open_stderr.log"
    case_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    relative_paths = device_case_paths(run_id_value, case)
    mac_input_files = copy_case_inputs_to_mac(
        case,
        container_root=container_root,
        input_dir=relative_paths["input_dir"],
    )

    command = [
        str(mac_app_executable(app_path)),
        "--rag-validation",
        "--rag-validation-query",
        case["query"],
        "--rag-validation-storage",
        relative_paths["storage_dir"],
        "--rag-validation-quality",
        case["quality_mode"],
    ]
    if mac_input_files:
        command.extend(["--rag-validation-files", ",".join(mac_input_files)])
    if case["skip_ingest"]:
        command.append("--rag-validation-skip-ingest")
    if pcc_consent != "default":
        command.extend(["--rag-validation-pcc-consent", pcc_consent])
    if benchmark_entitlement != "current":
        command.extend(["--rag-validation-entitlement", benchmark_entitlement])

    start = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            timeout=case["timeout_seconds"],
        )
        stdout = completed.stdout or ""
        stderr = completed.stderr or ""
        returncode = completed.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        stdout = ensure_text_output(exc.stdout)
        stderr = ensure_text_output(exc.stderr)
        returncode = -1
    latency = time.monotonic() - start
    stdout_path.write_text(stdout, encoding="utf-8")
    stderr_path.write_text(stderr, encoding="utf-8")
    quit_mac_app(bundle_id)

    report_path = copy_mac_artifact(
        container_root=container_root,
        relative_output_dir=relative_paths["output_dir"],
        filename="rag_validation_report.txt",
        local_output_dir=output_dir,
    )
    trace_path = copy_mac_artifact(
        container_root=container_root,
        relative_output_dir=relative_paths["output_dir"],
        filename="pipeline_trace.log",
        local_output_dir=output_dir,
    )

    return {
        "launcher": "mac-executable",
        "launch_returncode": returncode,
        "latency_seconds": round(latency, 3),
        "timed_out": timed_out,
        "report_path": report_path,
        "trace_path": trace_path,
        "stdout_path": stdout_path,
        "stderr_path": stderr_path,
    }


def launch_case_on_physical_device(
    case: dict[str, Any],
    *,
    run_id_value: str,
    device_ref: str,
    bundle_id: str,
    case_dir: Path,
    pcc_consent: str,
    benchmark_entitlement: str,
) -> dict[str, Any]:
    storage_dir = case_dir / "storage"
    output_dir = storage_dir / "ValidationOutput"
    stdout_path = case_dir / "devicectl_stdout.log"
    stderr_path = case_dir / "devicectl_stderr.log"
    device_log_path = case_dir / "device.log"
    case_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    relative_paths = device_case_paths(run_id_value, case)
    device_input_files = copy_case_inputs_to_device(
        case,
        device_ref=device_ref,
        bundle_id=bundle_id,
        input_dir=relative_paths["input_dir"],
        case_dir=case_dir,
    )

    command = [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        device_ref,
        "--terminate-existing",
        "--console",
        "--timeout",
        str(case["timeout_seconds"]),
        bundle_id,
        "--rag-validation",
        "--rag-validation-query",
        case["query"],
        "--rag-validation-storage",
        relative_paths["storage_dir"],
        "--rag-validation-quality",
        case["quality_mode"],
    ]
    if device_input_files:
        command.extend(["--rag-validation-files", ",".join(device_input_files)])
    if case["skip_ingest"]:
        command.append("--rag-validation-skip-ingest")
    if pcc_consent != "default":
        command.extend(["--rag-validation-pcc-consent", pcc_consent])
    if benchmark_entitlement != "current":
        command.extend(["--rag-validation-entitlement", benchmark_entitlement])

    start = time.monotonic()
    completed = run_command(command, log_path=device_log_path, check=False)
    latency = time.monotonic() - start
    stdout_path.write_text(completed.stdout or "", encoding="utf-8")
    stderr_path.write_text(completed.stderr or "", encoding="utf-8")

    report_path = copy_device_artifact(
        device_ref=device_ref,
        bundle_id=bundle_id,
        source=f"{relative_paths['output_dir']}/rag_validation_report.txt",
        destination_dir=output_dir,
        log_path=device_log_path,
    )
    trace_path = copy_device_artifact(
        device_ref=device_ref,
        bundle_id=bundle_id,
        source=f"{relative_paths['output_dir']}/pipeline_trace.log",
        destination_dir=output_dir,
        log_path=device_log_path,
    )

    return {
        "launcher": "devicectl",
        "launch_returncode": completed.returncode,
        "latency_seconds": round(latency, 3),
        "timed_out": report_path is None and latency >= case["timeout_seconds"],
        "report_path": report_path,
        "trace_path": trace_path,
        "stdout_path": stdout_path,
        "stderr_path": stderr_path,
    }


def parse_report(report_path: Path | None) -> dict[str, Any]:
    if report_path is None or not report_path.exists():
        return {
            "text": "",
            "status_failed": False,
            "error": "",
            "response": "",
            "confidence": None,
            "retrieved_chunk_count": None,
            "sources": [],
        }

    text = report_path.read_text(encoding="utf-8", errors="replace")
    confidence = None
    retrieved_chunk_count = None
    confidence_match = re.search(r"^Confidence:\s*([0-9]+(?:\.[0-9]+)?)\s*$", text, re.MULTILINE)
    if confidence_match:
        confidence = float(confidence_match.group(1))
    chunk_match = re.search(r"^Retrieved Chunks:\s*(\d+)\s*$", text, re.MULTILINE)
    if chunk_match:
        retrieved_chunk_count = int(chunk_match.group(1))

    response = ""
    error = ""
    error_match = re.search(r"^Error:\s*(.+)$", text, re.MULTILINE)
    if error_match:
        error = error_match.group(1).strip()

    response_match = re.search(r"^Response:\n(.*?)(?:\n\nRETRIEVED CHUNKS|\Z)", text, re.MULTILINE | re.DOTALL)
    if response_match:
        response = response_match.group(1).strip()

    sources: list[dict[str, Any]] = []
    source_pattern = re.compile(
        r"^- rank=(?P<rank>\d+)\s+sim=(?P<sim>[0-9.]+)\s+page=(?P<page>\S+)\s+source=(?P<source>.+)$",
        re.MULTILINE,
    )
    for match in source_pattern.finditer(text):
        sources.append(
            {
                "rank": int(match.group("rank")),
                "similarity": float(match.group("sim")),
                "page": match.group("page"),
                "source": match.group("source").strip(),
            }
        )

    return {
        "text": text,
        "status_failed": bool(re.search(r"^Status:\s*FAILED\s*$", text, re.MULTILINE)),
        "error": error,
        "response": response,
        "confidence": confidence,
        "retrieved_chunk_count": retrieved_chunk_count,
        "sources": sources,
    }


def any_pattern_matches(patterns: list[str], text: str) -> bool | None:
    if not patterns:
        return None
    return any(re.search(pattern, text or "") is not None for pattern in patterns)


def normalized_source_filename(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    parsed = urllib.parse.urlparse(raw)
    source_path = urllib.parse.unquote(parsed.path if parsed.scheme else raw)
    return Path(source_path).name.casefold()


def source_matches(expected_source: dict[str, Any], sources: list[dict[str, Any]]) -> bool | None:
    expected_filename = expected_source.get("filename")
    expected_page = expected_source.get("page")
    if not expected_filename and not expected_page:
        return None
    for source in sources:
        source_file_ok = True
        page_ok = True
        if expected_filename:
            expected_basename = normalized_source_filename(expected_filename)
            source_basename = normalized_source_filename(source.get("source", ""))
            source_file_ok = source_basename == expected_basename
        if expected_page:
            page_ok = str(source.get("page")) == str(expected_page)
        if source_file_ok and page_ok:
            return True
    return False


def empty_metrics() -> dict[str, Any]:
    return {"confidence": None, "retrieved_chunk_count": None, "latency_seconds": None}


def case_result_base(case: dict[str, Any], case_dir: Path, status: str) -> dict[str, Any]:
    return {
        "id": case["id"],
        "query": case["query"],
        "category": case["category"],
        "input_files": case_file_entries(case),
        "quality_mode": case["quality_mode"],
        "expected_behavior": case["expected_behavior"],
        "expected_source": case["expected_source"],
        "source_dataset": case.get("source_dataset"),
        "license_note": case.get("license_note"),
        "status": status,
        "passed": False,
        "failure_reasons": [],
        "metrics": empty_metrics(),
        "score": {"answer_matched": None, "expected_source_found": None, "abstention_detected": None},
        "artifacts": {"case_dir": str(case_dir), "report": None, "trace": None, "stdout": None, "stderr": None},
        "response_preview": "",
        "retrieved_sources": [],
    }


def score_case(
    case: dict[str, Any],
    launch: dict[str, Any] | None,
    case_dir: Path,
    skipped_reason: str | None = None,
) -> dict[str, Any]:
    if skipped_reason:
        result = case_result_base(case, case_dir, "skipped")
        result["failure_reasons"] = [skipped_reason]
        return result

    assert launch is not None
    report = parse_report(launch["report_path"])
    answer_matched = any_pattern_matches(case["expected_answer_patterns"], report["response"])
    abstention_detected = any_pattern_matches(case["abstain_patterns"], report["response"])
    expected_source_found = source_matches(case["expected_source"], report["sources"])

    failure_reasons: list[str] = []
    if launch["launch_returncode"] != 0:
        launcher = launch.get("launcher", "launcher")
        failure_reasons.append(f"{launcher} launch returned {launch['launch_returncode']}")
    if launch["timed_out"]:
        failure_reasons.append("timed out waiting for rag_validation_report.txt")
    if launch["report_path"] is None:
        failure_reasons.append("validation report was not written")
    if report["status_failed"]:
        if report["error"]:
            failure_reasons.append(f"validation report status is FAILED: {report['error']}")
        else:
            failure_reasons.append("validation report status is FAILED")

    if case["expected_behavior"] == "answer":
        if answer_matched is False:
            failure_reasons.append("expected answer pattern did not match response")
        if expected_source_found is False:
            failure_reasons.append("expected source was not found in retrieved chunks")
    elif abstention_detected is not True:
        failure_reasons.append("expected abstention was not detected")

    passed = not failure_reasons
    result = case_result_base(case, case_dir, "passed" if passed else "failed")
    result.update(
        {
            "passed": passed,
            "failure_reasons": failure_reasons,
            "metrics": {
                "confidence": report["confidence"],
                "retrieved_chunk_count": report["retrieved_chunk_count"],
                "latency_seconds": launch["latency_seconds"],
            },
            "score": {
                "answer_matched": answer_matched,
                "expected_source_found": expected_source_found,
                "abstention_detected": abstention_detected,
            },
            "artifacts": {
                "case_dir": str(case_dir),
                "report": str(launch["report_path"]) if launch["report_path"] else None,
                "trace": str(launch["trace_path"]) if launch["trace_path"] else None,
                "stdout": str(launch["stdout_path"]),
                "stderr": str(launch["stderr_path"]),
            },
            "response_preview": report["response"][:500],
            "retrieved_sources": report["sources"],
        }
    )
    return result


def pending_case_result(case: dict[str, Any], case_dir: Path) -> dict[str, Any]:
    return case_result_base(case, case_dir, "pending")


def summarize(results: list[dict[str, Any]]) -> dict[str, int]:
    passed = sum(1 for item in results if item["status"] == "passed")
    failed = sum(1 for item in results if item["status"] == "failed")
    skipped = sum(1 for item in results if item["status"] == "skipped")
    pending = sum(1 for item in results if item["status"] == "pending")
    return {
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "pending": pending,
        "scored": passed + failed,
    }


def markdown_bool(value: Any) -> str:
    if value is True:
        return "yes"
    if value is False:
        return "no"
    return "-"


def write_results_json(path: Path, run_data: dict[str, Any]) -> None:
    path.write_text(json.dumps(run_data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_summary_md(path: Path, manifest_path: Path, run_data: dict[str, Any]) -> None:
    summary = run_data["summary"]
    lines = [
        "# OpenIntelligence RAG Benchmark Summary",
        "",
        f"- Run ID: `{run_data['run_id']}`",
        f"- Manifest: `{manifest_path}`",
        f"- Started: `{run_data['started_at']}`",
        f"- Finished: `{run_data['finished_at']}`",
        f"- Passed: {summary['passed']}/{summary['scored']} scored cases",
        f"- Failed: {summary['failed']}",
        f"- Skipped: {summary['skipped']}",
        "",
        "## Cases",
        "",
        "| Status | ID | Category | Mode | Answer | Source | Abstain | Confidence | Chunks | Latency | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |",
    ]
    for result in run_data["cases"]:
        metrics = result["metrics"]
        score = result["score"]
        confidence = metrics["confidence"]
        confidence_text = f"{confidence:.2f}" if isinstance(confidence, (int, float)) else "-"
        chunks = metrics["retrieved_chunk_count"]
        chunks_text = str(chunks) if chunks is not None else "-"
        latency = metrics["latency_seconds"]
        latency_text = f"{latency:.2f}s" if isinstance(latency, (int, float)) else "-"
        notes = "; ".join(result["failure_reasons"]) if result["failure_reasons"] else "-"
        lines.append(
            "| {status} | `{id}` | {category} | {mode} | {answer} | {source} | {abstain} | {confidence} | {chunks} | {latency} | {notes} |".format(
                status=result["status"],
                id=result["id"],
                category=result["category"],
                mode=result["quality_mode"],
                answer=markdown_bool(score["answer_matched"]),
                source=markdown_bool(score["expected_source_found"]),
                abstain=markdown_bool(score["abstention_detected"]),
                confidence=confidence_text,
                chunks=chunks_text,
                latency=latency_text,
                notes=notes.replace("|", "\\|"),
            )
        )
    lines.extend(["", "## Artifacts", "", "Each case directory contains the harness report, pipeline trace when available, and launch logs."])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def skipped_missing_input_messages(results: list[dict[str, Any]], limit: int = 5) -> list[str]:
    messages: list[str] = []
    for result in results:
        if result.get("status") != "skipped":
            continue
        reason = "; ".join(result.get("failure_reasons") or [])
        if "missing input files:" not in reason:
            continue
        messages.append(f"{result.get('id')}: {reason}")
        if len(messages) >= limit:
            break
    return messages


def html_text(value: Any) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def artifact_href(path_value: str | None, dashboard_dir: Path) -> str | None:
    if not path_value:
        return None
    rel_path = os.path.relpath(Path(path_value), start=dashboard_dir).replace(os.sep, "/")
    return urllib.parse.quote(rel_path, safe="/")


def artifact_link(path_value: str | None, label: str, dashboard_dir: Path) -> str:
    href = artifact_href(path_value, dashboard_dir)
    if not href:
        return '<span class="muted">missing</span>'
    return f'<a href="{html_text(href)}">{html_text(label)}</a>'


def format_number(value: Any, digits: int = 2) -> str:
    return f"{value:.{digits}f}" if isinstance(value, (int, float)) else "-"


def case_status_rank(status: str) -> int:
    return {"pending": 0, "skipped": 1, "failed": 2, "passed": 3}.get(status, 0)


def find_previous_results(output_root: Path, run_dir: Path) -> dict[str, Any] | None:
    if not output_root.exists():
        return None
    candidates = [
        candidate / "results.json"
        for candidate in output_root.iterdir()
        if candidate.is_dir() and candidate.name not in {run_dir.name, "latest"} and (candidate / "results.json").exists()
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    try:
        return json.loads(candidates[0].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def compare_to_previous(
    current_results: list[dict[str, Any]],
    previous_data: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not previous_data:
        return None
    previous_cases = {
        item.get("id"): item
        for item in previous_data.get("cases", [])
        if isinstance(item, dict) and item.get("id")
    }
    changes: dict[str, list[dict[str, Any]]] = {
        "improved": [],
        "regressed": [],
        "unchanged": [],
        "newly_failing": [],
        "newly_passing": [],
    }
    for current in current_results:
        if current.get("status") == "pending":
            continue
        previous = previous_cases.get(current.get("id"))
        previous_status = previous.get("status") if previous else "missing"
        current_status = current.get("status", "missing")
        if current_status == previous_status:
            bucket = "unchanged"
        elif current_status == "passed" and previous_status != "passed":
            bucket = "newly_passing"
        elif current_status == "failed" and previous_status != "failed":
            bucket = "newly_failing"
        elif case_status_rank(str(current_status)) > case_status_rank(str(previous_status)):
            bucket = "improved"
        else:
            bucket = "regressed"
        changes[bucket].append({"id": current.get("id"), "from": previous_status, "to": current_status})
    return {"previous_run_id": previous_data.get("run_id"), "changes": changes}


def build_dashboard_html(
    run_data: dict[str, Any],
    *,
    dashboard_dir: Path,
    previous_data: dict[str, Any] | None,
    refresh_seconds: int | None,
) -> str:
    summary = run_data["summary"]
    scored = summary["scored"]
    pass_rate = (summary["passed"] / scored * 100.0) if scored else 0.0
    refresh_tag = f'<meta http-equiv="refresh" content="{int(refresh_seconds)}">\n' if refresh_seconds else ""

    def stat_card(label: str, value: Any, extra_class: str = "") -> str:
        return f'<div class="stat {html_text(extra_class)}"><div class="stat-value">{html_text(value)}</div><div class="stat-label">{html_text(label)}</div></div>'

    case_rows: list[str] = []
    for case in run_data["cases"]:
        metrics = case.get("metrics", {})
        artifacts = case.get("artifacts", {})
        files = case.get("input_files", [])
        file_items = "".join(
            f'<li class="{"missing-file" if not item.get("exists") else ""}">{html_text(item.get("display") or item.get("path"))}</li>'
            for item in files
        ) or '<li class="muted">none</li>'
        sources = case.get("retrieved_sources", [])
        source_items = "".join(
            "<li>"
            f'<span class="source-rank">#{html_text(source.get("rank"))}</span> '
            f'{html_text(source.get("source"))} '
            f'<span class="muted">page {html_text(source.get("page"))}, sim {html_text(source.get("similarity"))}</span>'
            "</li>"
            for source in sources
        ) or '<li class="muted">none</li>'
        links = " ".join(
            [
                artifact_link(artifacts.get("report"), "report", dashboard_dir),
                artifact_link(artifacts.get("trace"), "trace", dashboard_dir),
                artifact_link(artifacts.get("stdout"), "stdout", dashboard_dir),
                artifact_link(artifacts.get("stderr"), "stderr", dashboard_dir),
            ]
        )
        latency = metrics.get("latency_seconds")
        latency_text = f"{latency:.2f}s" if isinstance(latency, (int, float)) else "-"
        chunks = metrics.get("retrieved_chunk_count")
        chunks_text = str(chunks) if chunks is not None else "-"
        status = case.get("status", "unknown")
        failure_reason = "; ".join(case.get("failure_reasons") or []) or "-"
        open_attr = "open" if status == "failed" else ""
        case_rows.append(
            f"""
            <details class="case-card status-{html_text(status)}" {open_attr}>
              <summary>
                <span class="pill {html_text(status)}">{html_text(status)}</span>
                <span class="case-id">{html_text(case.get("id"))}</span>
                <span class="case-meta">{html_text(case.get("category"))} - {html_text(case.get("quality_mode"))}</span>
              </summary>
              <div class="case-grid">
                <div>
                  <h3>Query</h3>
                  <p>{html_text(case.get("query"))}</p>
                  <h3>Input Files</h3>
                  <ul>{file_items}</ul>
                  <h3>Expected</h3>
                  <p>{html_text(case.get("expected_behavior"))}</p>
                  <h3>Dataset</h3>
                  <p>{html_text(case.get("source_dataset") or "local")}</p>
                  <p class="muted">{html_text(case.get("license_note") or "")}</p>
                </div>
                <div>
                  <h3>Metrics</h3>
                  <dl>
                    <dt>Confidence</dt><dd>{html_text(format_number(metrics.get("confidence")))}</dd>
                    <dt>Retrieved Chunks</dt><dd>{html_text(chunks_text)}</dd>
                    <dt>Latency</dt><dd>{html_text(latency_text)}</dd>
                  </dl>
                  <h3>Artifacts</h3>
                  <p class="artifact-links">{links}</p>
                </div>
                <div class="wide">
                  <h3>Failure Reason</h3>
                  <p class="failure-text">{html_text(failure_reason)}</p>
                  <h3>Response Preview</h3>
                  <pre>{html_text(case.get("response_preview", ""))}</pre>
                  <h3>Retrieved Sources</h3>
                  <ul>{source_items}</ul>
                </div>
              </div>
            </details>
            """
        )

    comparison = compare_to_previous(run_data["cases"], previous_data)
    compare_html = '<p class="muted">No previous results.json found in this output directory.</p>'
    if comparison:
        changes = comparison["changes"]

        def change_list(name: str) -> str:
            items = changes.get(name, [])
            if not items:
                return '<li class="muted">none</li>'
            return "".join(
                f'<li><code>{html_text(item["id"])}</code>: {html_text(item["from"])} -> {html_text(item["to"])}</li>'
                for item in items
            )

        compare_html = f"""
          <p>Previous run: <code>{html_text(comparison.get("previous_run_id"))}</code></p>
          <div class="compare-grid">
            <section><h3>Improved</h3><ul>{change_list("improved")}</ul></section>
            <section><h3>Regressed</h3><ul>{change_list("regressed")}</ul></section>
            <section><h3>Unchanged</h3><ul>{change_list("unchanged")}</ul></section>
            <section><h3>Newly Failing</h3><ul>{change_list("newly_failing")}</ul></section>
            <section><h3>Newly Passing</h3><ul>{change_list("newly_passing")}</ul></section>
          </div>
        """

    status_class = "has-failures" if summary["failed"] else "all-clear"
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  {refresh_tag}<title>OpenIntelligence RAG Benchmark {html_text(run_data["run_id"])}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #f7f7f4;
      --panel: #ffffff;
      --text: #1f2528;
      --muted: #667075;
      --border: #d9dedb;
      --pass: #16794c;
      --fail: #b3261e;
      --skip: #806000;
      --pending: #4b6475;
      --link: #0b63ce;
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{ --bg: #111416; --panel: #1b2023; --text: #edf1f2; --muted: #a5b0b5; --border: #343c40; --link: #8dbdff; }}
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; background: var(--bg); color: var(--text); font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    main {{ max-width: 1180px; margin: 0 auto; padding: 28px; }}
    h1 {{ margin: 0 0 4px; font-size: 28px; }}
    h2 {{ margin: 28px 0 12px; font-size: 18px; }}
    h3 {{ margin: 0 0 6px; font-size: 13px; text-transform: uppercase; color: var(--muted); letter-spacing: .04em; }}
    a {{ color: var(--link); }}
    pre {{ white-space: pre-wrap; overflow-wrap: anywhere; border: 1px solid var(--border); border-radius: 6px; padding: 10px; margin: 0; }}
    .muted {{ color: var(--muted); }}
    .topline {{ display: flex; justify-content: space-between; gap: 16px; align-items: start; margin-bottom: 20px; }}
    .run-state {{ padding: 8px 10px; border-radius: 6px; border: 1px solid var(--border); background: var(--panel); }}
    .run-state.has-failures {{ border-color: var(--fail); }}
    .run-state.all-clear {{ border-color: var(--pass); }}
    .stats {{ display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 10px; }}
    .stat {{ background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 14px; }}
    .stat-value {{ font-size: 24px; font-weight: 700; }}
    .stat-label {{ color: var(--muted); }}
    .stat.fail .stat-value {{ color: var(--fail); }}
    .stat.pass .stat-value {{ color: var(--pass); }}
    .case-card {{ background: var(--panel); border: 1px solid var(--border); border-radius: 8px; margin: 12px 0; overflow: hidden; }}
    .case-card.status-failed {{ border-color: var(--fail); box-shadow: inset 4px 0 0 var(--fail); }}
    .case-card.status-passed {{ box-shadow: inset 4px 0 0 var(--pass); }}
    .case-card.status-skipped {{ box-shadow: inset 4px 0 0 var(--skip); }}
    .case-card.status-pending {{ box-shadow: inset 4px 0 0 var(--pending); }}
    summary {{ cursor: pointer; display: flex; gap: 12px; align-items: center; padding: 12px 14px; }}
    summary::-webkit-details-marker {{ display: none; }}
    .pill {{ border-radius: 999px; padding: 3px 9px; color: white; font-size: 12px; font-weight: 700; min-width: 70px; text-align: center; }}
    .pill.passed {{ background: var(--pass); }}
    .pill.failed {{ background: var(--fail); }}
    .pill.skipped {{ background: var(--skip); }}
    .pill.pending {{ background: var(--pending); }}
    .case-id {{ font-weight: 700; }}
    .case-meta {{ color: var(--muted); margin-left: auto; }}
    .case-grid {{ display: grid; grid-template-columns: 1.1fr .8fr; gap: 18px; padding: 0 14px 16px; }}
    .case-grid .wide {{ grid-column: 1 / -1; }}
    dl {{ display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; margin: 0; }}
    dt {{ color: var(--muted); }}
    dd {{ margin: 0; font-weight: 600; }}
    ul {{ margin: 0; padding-left: 18px; }}
    .missing-file, .failure-text {{ color: var(--fail); }}
    .failure-text {{ font-weight: 600; }}
    .artifact-links {{ display: flex; flex-wrap: wrap; gap: 10px; }}
    .source-rank {{ font-weight: 700; }}
    .compare-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 12px; }}
    .compare-grid section {{ background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 12px; }}
    @media (max-width: 760px) {{
      main {{ padding: 18px; }}
      .topline {{ display: block; }}
      .stats {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .case-grid {{ grid-template-columns: 1fr; }}
      .case-meta {{ display: none; }}
    }}
  </style>
</head>
<body>
<main>
  <div class="topline">
    <div>
      <h1>RAG Benchmark Dashboard</h1>
      <div class="muted">Run <code>{html_text(run_data["run_id"])}</code> - {html_text(run_data.get("started_at"))}</div>
    </div>
    <div class="run-state {status_class}">
      Current run: <strong>{html_text(run_data["run_id"])}</strong><br>
      Last update: <span class="muted">{html_text(run_data.get("finished_at") or "running")}</span>
    </div>
  </div>
  <section class="stats">
    {stat_card("Total Cases", summary["total"])}
    {stat_card("Passed", summary["passed"], "pass")}
    {stat_card("Failed", summary["failed"], "fail")}
    {stat_card("Skipped", summary["skipped"])}
    {stat_card("Pending", summary.get("pending", 0))}
    {stat_card("Pass Rate", f"{pass_rate:.1f}%")}
  </section>
  <section><h2>Compare To Previous Run</h2>{compare_html}</section>
  <section><h2>Cases</h2>{''.join(case_rows)}</section>
</main>
</body>
</html>
"""


def write_latest_dashboard(output_root: Path, run_dir: Path) -> Path:
    latest_dir = output_root / "latest"
    latest_dir.mkdir(parents=True, exist_ok=True)
    target = os.path.relpath(run_dir / "dashboard.html", start=latest_dir).replace(os.sep, "/")
    href = urllib.parse.quote(target, safe="/")
    latest_dashboard = latest_dir / "dashboard.html"
    latest_dashboard.write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url={html_text(href)}">
  <title>Latest OpenIntelligence RAG Benchmark</title>
</head>
<body>
  <p>Latest benchmark dashboard: <a href="{html_text(href)}">{html_text(target)}</a></p>
</body>
</html>
""",
        encoding="utf-8",
    )
    return latest_dashboard


def write_dashboard(
    path: Path,
    run_data: dict[str, Any],
    previous_data: dict[str, Any] | None,
    refresh_seconds: int | None,
) -> None:
    path.write_text(
        build_dashboard_html(
            run_data,
            dashboard_dir=path.parent,
            previous_data=previous_data,
            refresh_seconds=refresh_seconds,
        ),
        encoding="utf-8",
    )


def write_run_outputs(
    *,
    run_dir: Path,
    output_root: Path,
    manifest_path: Path,
    run_data: dict[str, Any],
    previous_data: dict[str, Any] | None,
    refresh_seconds: int | None,
) -> dict[str, Path]:
    results_path = run_dir / "results.json"
    summary_path = run_dir / "summary.md"
    dashboard_path = run_dir / "dashboard.html"
    run_data["dashboard_path"] = str(dashboard_path)
    write_results_json(results_path, run_data)
    write_summary_md(summary_path, manifest_path, run_data)
    write_dashboard(dashboard_path, run_data, previous_data, refresh_seconds)
    latest_dashboard = write_latest_dashboard(output_root, run_dir)
    return {
        "results": results_path,
        "summary": summary_path,
        "dashboard": dashboard_path,
        "latest_dashboard": latest_dashboard,
    }


def open_dashboard(path: Path) -> None:
    webbrowser.open(path.resolve().as_uri())


def dry_run_results(cases: list[dict[str, Any]], run_dir: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for case in cases:
        case_dir = run_dir / "cases" / case["safe_id"]
        if case["missing_files"]:
            missing = ", ".join(rel(path, REPO_ROOT) for path in case["missing_files"])
            results.append(score_case(case, None, case_dir, skipped_reason=f"missing input files: {missing}"))
        else:
            results.append(score_case(case, None, case_dir, skipped_reason="dry run"))
    return results


def pending_results(cases: list[dict[str, Any]], start_index: int, run_dir: Path) -> list[dict[str, Any]]:
    return [pending_case_result(case, run_dir / "cases" / case["safe_id"]) for case in cases[start_index:]]


def build_run_data(
    *,
    args: argparse.Namespace,
    manifest: dict[str, Any],
    manifest_path: Path,
    run_id_value: str,
    run_dir: Path,
    started_at: str,
    finished_at: str | None,
    target_info: dict[str, Any] | None,
    results: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "run_id": run_id_value,
        "manifest_path": str(manifest_path),
        "manifest_name": manifest.get("name"),
        "started_at": started_at,
        "finished_at": finished_at,
        "summary": summarize(results),
        "configuration": {
            "project": str(Path(args.project).expanduser()),
            "scheme": args.scheme,
            "configuration": args.configuration,
            "bundle_id": args.bundle_id,
            "runtime": args.runtime,
            "target": target_info,
            "simulator": target_info if args.runtime == "simulator" else None,
            "physical_device": target_info if args.runtime == "device" else None,
            "dry_run": args.dry_run,
            "watch_dashboard": args.watch_dashboard,
            "derived_data": str(resolve_derived_data_path(args, run_dir)),
            "build_timeout_seconds": args.build_timeout_seconds,
            "pcc_consent": args.pcc_consent,
            "benchmark_entitlement": args.benchmark_entitlement,
            "app_refresh_file_limit": args.app_refresh_file_limit,
        },
        "cases": results,
    }


def run_benchmark(args: argparse.Namespace) -> int:
    manifest_path = resolve_repo_path(args.manifest)
    manifest = load_manifest(manifest_path)
    cases = normalize_cases(manifest, args.timeout_seconds)

    output_root = resolve_repo_path(args.output_dir)
    this_run_id = args.run_id or run_id()
    run_dir = output_root / this_run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    started_at = now_utc()
    runnable_cases = [case for case in cases if not case["missing_files"]]
    previous_data = find_previous_results(output_root, run_dir)
    refresh_seconds = args.watch_dashboard if args.watch_dashboard else None
    dashboard_opened = False

    if args.dry_run:
        target_info = None
        results = dry_run_results(cases, run_dir)
        finished_at = now_utc()
        run_data = build_run_data(
            args=args,
            manifest=manifest,
            manifest_path=manifest_path,
            run_id_value=this_run_id,
            run_dir=run_dir,
            started_at=started_at,
            finished_at=finished_at,
            target_info=target_info,
            results=results,
        )
        output_paths = write_run_outputs(
            run_dir=run_dir,
            output_root=output_root,
            manifest_path=manifest_path,
            run_data=run_data,
            previous_data=previous_data,
            refresh_seconds=refresh_seconds,
        )
    else:
        target_info = None
        app_path: Path | None = None
        files_since_refresh = 0
        results: list[dict[str, Any]] = []
        initial_run_data = build_run_data(
            args=args,
            manifest=manifest,
            manifest_path=manifest_path,
            run_id_value=this_run_id,
            run_dir=run_dir,
            started_at=started_at,
            finished_at=None,
            target_info=target_info,
            results=pending_results(cases, 0, run_dir),
        )
        output_paths = write_run_outputs(
            run_dir=run_dir,
            output_root=output_root,
            manifest_path=manifest_path,
            run_data=initial_run_data,
            previous_data=previous_data,
            refresh_seconds=refresh_seconds,
        )
        if args.open_dashboard and refresh_seconds:
            open_dashboard(output_paths["dashboard"])
            dashboard_opened = True

        if runnable_cases:
            if args.runtime == "device":
                physical_device = find_physical_device(args.device, run_dir)
                target_info = {
                    "name": device_name(physical_device),
                    "identifier": device_identifier(physical_device),
                    "udid": device_udid(physical_device),
                    "model": physical_device.get("hardwareProperties", {}).get("marketingName"),
                    "runtime": physical_device.get("hardwareProperties", {}).get("platform"),
                }
                print(f"Using physical device: {target_info['name']} ({target_info['model']})", flush=True)
                app_path = build_app(args, "", run_dir)
                install_app_on_physical_device(str(target_info["identifier"]), app_path, run_dir)
            elif args.runtime == "mac":
                target_info = {
                    "name": "My Mac",
                    "udid": None,
                    "runtime": "macOS",
                    "variant": "Mac Catalyst",
                    "build_method": args.mac_build_method,
                }
                print(
                    f"Using this Mac: Mac Catalyst debug build ({args.mac_build_method} build method)",
                    flush=True,
                )
                app_path = build_app(args, "", run_dir)
                container_root = discover_mac_runtime_container_root(
                    app_path=app_path,
                    bundle_id=args.bundle_id,
                    run_dir=run_dir,
                    pcc_consent=args.pcc_consent,
                    benchmark_entitlement=args.benchmark_entitlement,
                )
                if container_root is None:
                    raise BenchmarkError(
                        "Could not determine the Mac benchmark app container root"
                    )
                target_info["container_root"] = str(container_root)
            else:
                simulator = find_simulator(args.device)
                target_info = {
                    "name": simulator.get("name"),
                    "udid": simulator.get("udid"),
                    "runtime": simulator.get("runtime"),
                }
                print(f"Using simulator: {target_info['name']}", flush=True)
                destination = f"platform=iOS Simulator,id={simulator['udid']}"
                boot_simulator(simulator, run_dir)
                app_path = build_app(args, destination, run_dir)
                install_app(str(simulator["udid"]), app_path, run_dir)

        for index, case in enumerate(cases):
            case_dir = run_dir / "cases" / case["safe_id"]
            if case["missing_files"]:
                missing = ", ".join(rel(path, REPO_ROOT) for path in case["missing_files"])
                results.append(score_case(case, None, case_dir, skipped_reason=f"missing input files: {missing}"))
            else:
                assert target_info is not None
                assert app_path is not None
                case_file_count = len(case["input_files"])
                if (
                    args.app_refresh_file_limit > 0
                    and files_since_refresh > 0
                    and files_since_refresh + case_file_count > args.app_refresh_file_limit
                ):
                    refresh_app_install(
                        args,
                        target_info=target_info,
                        app_path=app_path,
                        run_dir=run_dir,
                        reason=(
                            f"next case would exceed {args.app_refresh_file_limit} "
                            f"fixture files in this install ({files_since_refresh}+{case_file_count})"
                        ),
                    )
                    files_since_refresh = 0

                if args.runtime == "device":
                    launch = launch_case_on_physical_device(
                        case,
                        run_id_value=this_run_id,
                        device_ref=str(target_info["identifier"]),
                        bundle_id=args.bundle_id,
                        case_dir=case_dir,
                        pcc_consent=args.pcc_consent,
                        benchmark_entitlement=args.benchmark_entitlement,
                    )
                elif args.runtime == "mac":
                    launch = launch_case_on_mac(
                        case,
                        run_id_value=this_run_id,
                        app_path=app_path,
                        bundle_id=args.bundle_id,
                        container_root=Path(str(target_info["container_root"])),
                        case_dir=case_dir,
                        pcc_consent=args.pcc_consent,
                        benchmark_entitlement=args.benchmark_entitlement,
                    )
                else:
                    launch = launch_case(
                        case,
                        device_udid=str(target_info["udid"]),
                        bundle_id=args.bundle_id,
                        case_dir=case_dir,
                        pcc_consent=args.pcc_consent,
                        benchmark_entitlement=args.benchmark_entitlement,
                    )
                results.append(score_case(case, launch, case_dir))
                files_since_refresh += case_file_count

            partial_run_data = build_run_data(
                args=args,
                manifest=manifest,
                manifest_path=manifest_path,
                run_id_value=this_run_id,
                run_dir=run_dir,
                started_at=started_at,
                finished_at=None,
                target_info=target_info,
                results=results + pending_results(cases, index + 1, run_dir),
            )
            output_paths = write_run_outputs(
                run_dir=run_dir,
                output_root=output_root,
                manifest_path=manifest_path,
                run_data=partial_run_data,
                previous_data=previous_data,
                refresh_seconds=refresh_seconds,
            )

        finished_at = now_utc()
        run_data = build_run_data(
            args=args,
            manifest=manifest,
            manifest_path=manifest_path,
            run_id_value=this_run_id,
            run_dir=run_dir,
            started_at=started_at,
            finished_at=finished_at,
            target_info=target_info,
            results=results,
        )
        output_paths = write_run_outputs(
            run_dir=run_dir,
            output_root=output_root,
            manifest_path=manifest_path,
            run_data=run_data,
            previous_data=previous_data,
            refresh_seconds=refresh_seconds,
        )

    if args.open_dashboard and not dashboard_opened:
        open_dashboard(output_paths["dashboard"])

    print(f"Benchmark run: {run_dir}")
    print(f"Results: {output_paths['results']}")
    print(f"Summary: {output_paths['summary']}")
    print(f"Dashboard: {output_paths['dashboard']}")
    print(f"Latest dashboard: {output_paths['latest_dashboard']}")
    print("Passed {passed}/{scored} scored cases, failed {failed}, skipped {skipped}".format(**run_data["summary"]))
    if run_data["summary"]["scored"] == 0 and run_data["summary"]["skipped"]:
        if args.dry_run:
            print("Dry run only; no benchmark cases were executed.")
        else:
            print("No benchmark cases actually ran because every runnable case was skipped.")
            missing_messages = skipped_missing_input_messages(run_data["cases"])
            if missing_messages:
                print("Missing input files from the manifest:")
                for message in missing_messages:
                    print(f"  - {message}")
                print("Add local documents under Benchmarks/Fixtures/ or edit the manifest input_files paths.")
    return 1 if run_data["summary"]["failed"] else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--run-id", default=None)
    parser.add_argument("--project", default=str(DEFAULT_PROJECT))
    parser.add_argument("--scheme", default=DEFAULT_SCHEME)
    parser.add_argument("--configuration", default=DEFAULT_CONFIGURATION)
    parser.add_argument(
        "--runtime",
        choices=["simulator", "device", "mac"],
        default=DEFAULT_RUNTIME,
        help="Run on an iOS Simulator, connected physical iPhone/iPad, or this Mac through Mac Catalyst.",
    )
    parser.add_argument(
        "--destination",
        default=None,
        help=(
            "Override xcodebuild build destination. Defaults to "
            f"{DEFAULT_SIMULATOR_BUILD_DESTINATION!r} for simulator and "
            f"{DEFAULT_DEVICE_BUILD_DESTINATION!r} for device and "
            f"{DEFAULT_MAC_BUILD_DESTINATION!r} for mac."
        ),
    )
    parser.add_argument(
        "--derived-data",
        default=None,
        help="DerivedData path. Defaults to /tmp/openintelligence-rag-bench/DerivedData.",
    )
    parser.add_argument(
        "--build-timeout-seconds",
        type=int,
        default=DEFAULT_BUILD_TIMEOUT_SECONDS,
        help="Stop xcodebuild if it has not finished by this timeout.",
    )
    parser.add_argument(
        "--mac-build-method",
        choices=["scheme", "app-only"],
        default=DEFAULT_MAC_BUILD_METHOD,
        help=(
            "Mac runtime only: keep the default scheme build, or use a benchmark-only "
            "temporary project copy that detaches the Live Activities extension from the app target."
        ),
    )
    parser.add_argument("--app-name", default=DEFAULT_SCHEME)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--device", default=os.environ.get("OPENINTELLIGENCE_BENCHMARK_DEVICE"))
    parser.add_argument(
        "--pcc-consent",
        choices=["allow", "deny", "default"],
        default=DEFAULT_PCC_CONSENT,
        help="Preset Apple PCC consent for benchmark launches. Use 'default' to keep normal app prompting.",
    )
    parser.add_argument(
        "--benchmark-entitlement",
        choices=["lifetime", "pro", "free", "current"],
        default=DEFAULT_BENCHMARK_ENTITLEMENT,
        help=(
            "DEBUG-only entitlement preset for benchmark launches. Defaults to "
            "lifetime so benchmark suites do not hit free-tier document limits."
        ),
    )
    parser.add_argument(
        "--app-refresh-file-limit",
        type=int,
        default=DEFAULT_APP_REFRESH_FILE_LIMIT,
        help=(
            "Uninstall/reinstall the app after this many fixture files have been "
            "ingested in the current install. Use 0 to disable."
        ),
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--open-dashboard", action="store_true")
    parser.add_argument(
        "--watch-dashboard",
        nargs="?",
        const=5,
        type=int,
        default=0,
        help="Add auto-refresh to dashboard.html, defaulting to 5 seconds when no value is provided",
    )
    parser.add_argument("--timeout-seconds", type=int, default=None, help="Override timeout_seconds for every case")
    args = parser.parse_args(argv)
    if args.timeout_seconds is not None:
        args.timeout_seconds = max(1, args.timeout_seconds)
    if args.watch_dashboard is not None:
        args.watch_dashboard = max(0, args.watch_dashboard)
    args.build_timeout_seconds = max(1, args.build_timeout_seconds)
    args.app_refresh_file_limit = max(0, args.app_refresh_file_limit)
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        return run_benchmark(args)
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        return 130
    except BenchmarkError as exc:
        print(f"benchmark error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
