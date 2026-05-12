#!/usr/bin/env python3
"""Local browser UI for ad hoc RAG benchmark runs.

The studio is only a controller. It saves uploaded files under BenchmarkRuns/,
generates a manifest, and invokes scripts/run_rag_benchmarks.py.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import mimetypes
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from dataclasses import dataclass, field
from email.parser import BytesParser
from email.policy import default as email_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "BenchmarkRuns"
RUNNER = REPO_ROOT / "scripts" / "run_rag_benchmarks.py"
STUDIO_HTML = REPO_ROOT / "Benchmarks" / "studio.html"
MAX_UPLOAD_BYTES = 750 * 1024 * 1024
ALLOWED_QUALITY_MODES = {"standard", "deep-think", "maximum"}
ALLOWED_RUNTIMES = {"mac", "device", "simulator"}
ALLOWED_ENTITLEMENTS = {"lifetime", "pro", "free", "current"}
ALLOWED_PCC = {"allow", "deny", "default"}
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


class StudioError(Exception):
    """Raised for request validation problems."""


def now_id() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return cleaned.strip("-") or "adhoc"


def safe_filename(value: str, fallback: str) -> str:
    name = Path(value or fallback).name
    cleaned = re.sub(r"[^A-Za-z0-9_. -]+", "-", name).strip(" .-")
    return cleaned[:120] or fallback


def unique_path(directory: Path, filename: str) -> Path:
    candidate = directory / filename
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    for index in range(2, 10_000):
        next_candidate = directory / f"{stem}-{index}{suffix}"
        if not next_candidate.exists():
            return next_candidate
    raise StudioError(f"Could not create unique filename for {filename}")


def require_choice(value: str, allowed: set[str], field_name: str) -> str:
    normalized = value.strip().lower()
    if normalized not in allowed:
        raise StudioError(f"Unsupported {field_name}: {value}")
    return normalized


def safe_under_root(root: Path, requested: str) -> Path:
    root_resolved = root.resolve()
    candidate = (root_resolved / requested).resolve()
    if candidate != root_resolved and root_resolved not in candidate.parents:
        raise StudioError("Invalid artifact path")
    return candidate


@dataclass
class StudioJob:
    status: str = "idle"
    run_id: str | None = None
    returncode: int | None = None
    command: list[str] = field(default_factory=list)
    log: list[str] = field(default_factory=list)
    started_at: str | None = None
    finished_at: str | None = None
    manifest_path: str | None = None
    dashboard_url: str | None = None
    results_url: str | None = None
    manifest_url: str | None = None
    error: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "run_id": self.run_id,
            "returncode": self.returncode,
            "command": self.command,
            "log": self.log[-900:],
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "manifest_path": self.manifest_path,
            "dashboard_url": self.dashboard_url,
            "results_url": self.results_url,
            "manifest_url": self.manifest_url,
            "error": self.error,
        }


class StudioState:
    def __init__(self, output_root: Path) -> None:
        self.output_root = output_root
        self.lock = threading.Lock()
        self.job = StudioJob()

    def snapshot(self) -> StudioJob:
        with self.lock:
            return StudioJob(**self.job.__dict__)

    def replace_job(self, job: StudioJob) -> None:
        with self.lock:
            self.job = job

    def append_log(self, text: str) -> None:
        with self.lock:
            self.job.log.append(text)

    def update(self, **kwargs: Any) -> None:
        with self.lock:
            for key, value in kwargs.items():
                setattr(self.job, key, value)


def parse_multipart(headers: Any, body: bytes) -> tuple[dict[str, list[str]], list[dict[str, Any]]]:
    content_type = headers.get("Content-Type", "")
    if "multipart/form-data" not in content_type:
        raise StudioError("Expected multipart/form-data")

    message = BytesParser(policy=email_policy).parsebytes(
        f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode("utf-8") + body
    )
    if not message.is_multipart():
        raise StudioError("Invalid multipart body")

    fields: dict[str, list[str]] = {}
    files: list[dict[str, Any]] = []
    for part in message.iter_parts():
        disposition = part.get("Content-Disposition", "")
        if not disposition:
            continue
        name = part.get_param("name", header="Content-Disposition")
        if not name:
            continue
        filename = part.get_filename()
        payload = part.get_payload(decode=True) or b""
        if filename:
            if payload:
                files.append({"field": name, "filename": filename, "data": payload})
        else:
            charset = part.get_content_charset() or "utf-8"
            fields.setdefault(name, []).append(payload.decode(charset, errors="replace"))
    return fields, files


def first_field(fields: dict[str, list[str]], name: str, default_value: str = "") -> str:
    values = fields.get(name)
    return values[0] if values else default_value


def parse_cases(fields: dict[str, list[str]]) -> list[dict[str, Any]]:
    raw = first_field(fields, "cases_json")
    if not raw:
        raise StudioError("No questions were submitted")
    try:
        cases = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise StudioError(f"Invalid questions payload: {exc}") from exc
    if not isinstance(cases, list):
        raise StudioError("Questions payload must be a list")

    normalized: list[dict[str, Any]] = []
    for index, item in enumerate(cases, start=1):
        if not isinstance(item, dict):
            continue
        query = str(item.get("query", "")).strip()
        if not query:
            continue
        category = require_choice(str(item.get("category", "summary")), ALLOWED_CATEGORIES, "category")
        expected_behavior = require_choice(
            str(item.get("expected_behavior", "answer")),
            ALLOWED_BEHAVIORS,
            "expected behavior",
        )
        pattern = str(item.get("expected_pattern", "")).strip()
        manifest_case: dict[str, Any] = {
            "id": f"adhoc-{index:03d}",
            "category": category,
            "query": query,
            "quality_mode": first_field(fields, "quality_mode", "standard"),
            "input_files": [],
            "expected_answer_patterns": [pattern] if pattern else [],
            "expected_behavior": expected_behavior,
            "source_dataset": "local-ad-hoc",
            "license_note": "User-provided local document. Not committed.",
        }
        normalized.append(manifest_case)

    if not normalized:
        raise StudioError("Add at least one non-empty question")
    return normalized


def create_manifest(
    *,
    fields: dict[str, list[str]],
    files: list[dict[str, Any]],
    output_root: Path,
) -> tuple[str, Path, dict[str, Any]]:
    document_files = [item for item in files if item["field"] == "documents"]
    if not document_files:
        raise StudioError("Add at least one document")

    quality_mode = require_choice(first_field(fields, "quality_mode", "standard"), ALLOWED_QUALITY_MODES, "quality mode")
    timeout_seconds = int(first_field(fields, "timeout_seconds", "420") or "420")
    timeout_seconds = max(30, timeout_seconds)
    label = slug(first_field(fields, "run_label", "adhoc"))
    run_id = f"adhoc-{now_id()}-{label}" if label != "adhoc" else f"adhoc-{now_id()}"
    run_dir = output_root / run_id
    inputs_dir = run_dir / "inputs"
    inputs_dir.mkdir(parents=True, exist_ok=True)

    saved_files: list[Path] = []
    for index, upload in enumerate(document_files, start=1):
        filename = safe_filename(upload["filename"], f"document-{index}.txt")
        destination = unique_path(inputs_dir, filename)
        destination.write_bytes(upload["data"])
        saved_files.append(destination)

    cases = parse_cases(fields)
    input_paths = [str(path) for path in saved_files]
    default_source = saved_files[0].name if len(saved_files) == 1 else None
    for case in cases:
        case["quality_mode"] = quality_mode
        case["input_files"] = input_paths
        if default_source:
            case["expected_source"] = {"filename": default_source, "page": None}

    manifest = {
        "name": f"ad-hoc-{run_id}",
        "description": "Generated by Benchmarks/studio.html through scripts/rag_benchmark_studio.py.",
        "created_at": now_utc(),
        "defaults": {
            "quality_mode": quality_mode,
            "timeout_seconds": timeout_seconds,
        },
        "cases": cases,
    }
    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return run_id, manifest_path, manifest


def runner_command(
    *,
    fields: dict[str, list[str]],
    run_id: str,
    manifest_path: Path,
    output_root: Path,
) -> list[str]:
    runtime = require_choice(first_field(fields, "runtime", "mac"), ALLOWED_RUNTIMES, "runtime")
    entitlement = require_choice(
        first_field(fields, "benchmark_entitlement", "lifetime"),
        ALLOWED_ENTITLEMENTS,
        "benchmark entitlement",
    )
    pcc = require_choice(first_field(fields, "pcc_consent", "allow"), ALLOWED_PCC, "PCC consent")
    timeout_seconds = str(max(30, int(first_field(fields, "timeout_seconds", "420") or "420")))
    command = [
        sys.executable,
        str(RUNNER),
        str(manifest_path),
        "--run-id",
        run_id,
        "--output-dir",
        str(output_root),
        "--runtime",
        runtime,
        "--benchmark-entitlement",
        entitlement,
        "--pcc-consent",
        pcc,
        "--timeout-seconds",
        timeout_seconds,
    ]
    device = first_field(fields, "device").strip()
    if device:
        command.extend(["--device", device])
    return command


def run_job(state: StudioState, command: list[str]) -> None:
    state.append_log("$ " + " ".join(command) + "\n")
    try:
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            state.append_log(line)
        returncode = process.wait()
        state.update(
            status="completed" if returncode == 0 else "failed",
            returncode=returncode,
            finished_at=now_utc(),
        )
    except Exception as exc:  # noqa: BLE001 - keep server alive and show error in UI.
        state.append_log(f"studio error: {exc}\n")
        state.update(status="failed", returncode=-1, finished_at=now_utc(), error=str(exc))


def json_response(handler: BaseHTTPRequestHandler, payload: dict[str, Any], status: int = 200) -> None:
    data = json.dumps(payload, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def text_response(handler: BaseHTTPRequestHandler, text: str, status: int = 200, content_type: str = "text/plain") -> None:
    data = text.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", f"{content_type}; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


class StudioHandler(BaseHTTPRequestHandler):
    server: "StudioServer"

    def log_message(self, format_string: str, *args: Any) -> None:
        print(f"[studio] {self.address_string()} {format_string % args}")

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in {"/", "/studio.html"}:
            self.serve_studio_html()
            return
        if parsed.path == "/api/status":
            json_response(self, {"job": self.server.state.snapshot().to_json()})
            return
        if parsed.path.startswith("/runs/"):
            self.serve_run_artifact(parsed.path.removeprefix("/runs/"))
            return
        text_response(self, "not found\n", status=404)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/api/run":
            text_response(self, "not found\n", status=404)
            return

        if self.server.state.snapshot().status == "running":
            json_response(self, {"error": "A benchmark run is already active."}, status=409)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0:
                raise StudioError("Empty request")
            if length > MAX_UPLOAD_BYTES:
                raise StudioError("Upload is too large for this lightweight local studio")
            fields, files = parse_multipart(self.headers, self.rfile.read(length))
            run_id, manifest_path, _ = create_manifest(
                fields=fields,
                files=files,
                output_root=self.server.state.output_root,
            )
            command = runner_command(
                fields=fields,
                run_id=run_id,
                manifest_path=manifest_path,
                output_root=self.server.state.output_root,
            )
        except (StudioError, ValueError) as exc:
            json_response(self, {"error": str(exc)}, status=400)
            return

        job = StudioJob(
            status="running",
            run_id=run_id,
            command=command,
            started_at=now_utc(),
            manifest_path=str(manifest_path),
            dashboard_url=f"/runs/{urllib.parse.quote(run_id)}/dashboard.html",
            results_url=f"/runs/{urllib.parse.quote(run_id)}/results.json",
            manifest_url=f"/runs/{urllib.parse.quote(run_id)}/manifest.json",
        )
        self.server.state.replace_job(job)
        thread = threading.Thread(target=run_job, args=(self.server.state, command), daemon=True)
        thread.start()
        json_response(self, {"run_id": run_id, "job": job.to_json()})

    def serve_studio_html(self) -> None:
        if not STUDIO_HTML.exists():
            text_response(self, "Benchmarks/studio.html is missing\n", status=500)
            return
        data = STUDIO_HTML.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_run_artifact(self, relative: str) -> None:
        try:
            decoded = urllib.parse.unquote(relative)
            path = safe_under_root(self.server.state.output_root, decoded)
        except StudioError as exc:
            text_response(self, str(exc) + "\n", status=400)
            return
        if not path.exists() or not path.is_file():
            text_response(self, "not found\n", status=404)
            return
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class StudioServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], state: StudioState) -> None:
        super().__init__(server_address, StudioHandler)
        self.state = state


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--open", action="store_true", help="Open the studio in the default browser.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    output_root = Path(args.output_dir).expanduser()
    if not output_root.is_absolute():
        output_root = REPO_ROOT / output_root
    output_root.mkdir(parents=True, exist_ok=True)

    state = StudioState(output_root=output_root)
    server = StudioServer((args.host, args.port), state)
    url = f"http://{args.host}:{args.port}/"
    print(f"RAG Benchmark Studio: {url}")
    print(f"Outputs: {output_root}")
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping studio")
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
