#!/usr/bin/env python3
"""Lightweight heuristic scanner for accidental secrets.

Usage:
    python3 scripts/secret_scan.py [path]

- Scans text files for common API key signatures (OpenAI, AWS, generic API_KEY literals).
- Skips binary files and directories listed in IGNORE_DIRS.
- Exits with zero when no issues are found, otherwise prints matches and exits 1.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Directories we can safely skip on every run
IGNORE_DIRS = {
    ".git",
    "build",
    "DerivedData",
    "Tests.xcresult",
    "xcuserdata",
    "__pycache__",
    "node_modules",
}

# File extensions that are typically binary or generated
BINARY_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".pdf",
    ".xcassets",
    ".xcarchive",
    ".ipa",
    ".zip",
    ".bin",
    ".dylib",
}

# Patterns for suspicious secrets
PATTERNS = {
    "openai_key": re.compile(r"sk-[A-Za-z0-9]{20,}"),
    "aws_access": re.compile(r"AKIA[0-9A-Z]{16}"),
    "google_api": re.compile(r"AIza[0-9A-Za-z\-_]{35}"),
    "generic_api": re.compile(r"api[_-]?key\s*[:=]\s*[\"']?[A-Za-z0-9_\-]{16,}[\"']?", re.IGNORECASE),
    "private_key": re.compile(r"-----BEGIN (?:RSA|EC|PRIVATE) KEY-----"),
}


def is_binary(path: Path) -> bool:
    if path.suffix in BINARY_EXTENSIONS:
        return True
    try:
        with path.open("rb") as handle:
            chunk = handle.read(1024)
        return b"\0" in chunk
    except OSError:
        return True


def scan_file(path: Path) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return findings
    except OSError:
        return findings

    for name, pattern in PATTERNS.items():
        for match in pattern.findall(text):
            findings.append((name, match if isinstance(match, str) else match[0]))
    return findings


def should_skip(path: Path) -> bool:
    parts = set(part for part in path.parts)
    return bool(parts & IGNORE_DIRS)


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan repository for accidental secrets")
    parser.add_argument("root", nargs="?", default=".", help="Directory to scan")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"error: path {root} does not exist", file=sys.stderr)
        return 2

    findings_count = 0
    for path in root.rglob("*"):
        if path.is_dir():
            if path.name in IGNORE_DIRS:
                # Skip entire directory tree
                for _ in path.rglob("*"):
                    pass
            continue
        if should_skip(path):
            continue
        if is_binary(path):
            continue
        matches = scan_file(path)
        for name, value in matches:
            findings_count += 1
            preview = value[:60].replace("\n", " ")
            print(f"{path}: [{name}] {preview}")

    if findings_count == 0:
        print("✅ secret_scan: no sensitive tokens discovered")
        return 0

    print(f"❌ secret_scan: found {findings_count} potential secret(s)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
