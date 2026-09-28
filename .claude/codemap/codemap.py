#!/usr/bin/env python3
"""codemap: a feature index and knowledge graph kept in the repository, with its checker.

Standard library only. The map lives in a directory (default docs/ai/codemap) holding
config.json, features/<id>.json (one slice per feature) and generated INDEX.md, DRIFT.md
and UNMAPPED.md. Slices cite evidence as a path plus a `match` string copied from one
line of that file; `check` re-finds every match, so a slice that no longer describes the
code fails loudly instead of misleading the next agent.

Commands
  find WORDS        rank features by name, alias, purpose and node ids
  owner PATH        which features own or share a file
  refs SYMBOL       live: where a symbol is declared and which files mention it
  check [ID...]     validate slices against the working tree (exit 1 when broken)
  affected [--since REV]  features whose files changed since their slice was stamped
  derive [ID...]    regenerate each slice's mechanical layer (declarations, type references, tests)
  review [ID...]    print each curated edge beside the line it cites, to judge the claim
  orphans           types no chain of type references reaches from the app entry point
  refresh [ID...]   derive, stamp and index in one step (no ids: every slice whose files changed)
  hook EVENT        automation: `edit PATH` (kit fast-check), `stop [--agent codex]` (Stop hook), `pre-commit` (git, warns)
  stamp ID...       after re-verifying a slice: refresh line hints, blob hashes, revision
  index             regenerate INDEX.md, DRIFT.md and UNMAPPED.md from the slices
  unmapped          source files no slice claims, with the evidence for each
  inventory [--json]  every source file: target, declarations, markers, references
"""

from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

VERSION = "1.1.0"
SLICE_SCHEMA = "codemap/1"
CONFIG_SCHEMA = "codemap-config/1"
MAP_DIR_CANDIDATES = ("docs/ai/codemap", "Docs/ai/codemap", ".codemap")

NODE_KINDS = {
    "view", "view_model", "service", "model", "function", "state", "persistence",
    "integration", "config", "test", "util", "intent", "resource", "entry",
}
EDGE_TYPES = {"renders", "calls", "reads", "writes", "configures", "depends_on", "tested_by"}
STATUSES = {"VERIFIED", "INFERRED", "UNKNOWN"}
DOC_STATUSES = {"CONFIRMED", "CONTRADICTED", "STALE", "UNVERIFIED"}
FILE_ROLES = {"primary", "shared", "test"}
DERIVED_EDGE_CAP = 40
USE_EDGES = {"calls", "renders", "reads", "writes", "configures"}
DECLARATION_LINE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|static|nonisolated|"
    r"override|mutating|indirect)\s+)*(?:func|class|struct|enum|protocol|actor|extension|init)\b")


# ---------------------------------------------------------------- repository helpers

def run_git(root: Path, *args: str, check: bool = True) -> str:
    proc = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=60)
    if check and proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def repo_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                             text=True, check=True).stdout.strip()
        return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd()


def head_revision(root: Path) -> str:
    return run_git(root, "rev-parse", "--short", "HEAD").strip()


def blob_hash(path: Path) -> str:
    """Same value as `git hash-object PATH` (no filters)."""
    data = path.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def today() -> str:
    return _dt.date.today().isoformat()


def norm_ws(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


# ---------------------------------------------------------------- configuration

class Map:
    def __init__(self, root: Path, map_dir: Path, config: dict):
        self.root = root
        self.dir = map_dir
        self.config = config
        self.features_dir = map_dir / "features"

    def slices(self) -> list[tuple[Path, dict]]:
        out = []
        if not self.features_dir.is_dir():
            return out
        for path in sorted(self.features_dir.glob("*.json")):
            try:
                out.append((path, json.loads(path.read_text())))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}: invalid JSON: {exc}")
        return out


def open_map(explicit: str | None) -> Map:
    root = repo_root()
    candidates = [explicit] if explicit else list(MAP_DIR_CANDIDATES)
    for cand in candidates:
        d = (root / cand) if cand else None
        if d and (d / "config.json").is_file():
            cfg = json.loads((d / "config.json").read_text())
            if cfg.get("schema") != CONFIG_SCHEMA:
                raise SystemExit(f"{d / 'config.json'}: schema must be {CONFIG_SCHEMA}")
            return Map(root, d, cfg)
    raise SystemExit("No codemap config found (looked for " + ", ".join(
        f"{c}/config.json" for c in candidates) + "). Run from inside the repository.")


# ---------------------------------------------------------------- Swift scanning

RAW_OPEN = re.compile(r'(#*)("""|")')
TYPE_RE = re.compile(
    r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*'
    r'(?:(?:public|private|fileprivate|internal|open|final|indirect|package|nonisolated)\s+)*'
    r'(class|struct|enum|protocol|actor|extension)\s+([A-Za-z_][\w.]*)(.*)$')
FUNC_RE = re.compile(r'\bfunc\s+([A-Za-z_]\w*|[^\s(<]+)\s*(?:<[^>{]*>)?\s*\(')
WRAPPER_RE = re.compile(
    r'@(State|StateObject|ObservedObject|EnvironmentObject|Environment|Binding|Published|'
    r'AppStorage|SceneStorage|FocusState|Bindable|Query|UIApplicationDelegateAdaptor)\b'
    r'(\([^)]*\))?\s+(?:(?:private|fileprivate|public|internal|static|nonisolated)\s+)*(?:var|let)\s+(\w+)')
IDENT_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")
NOT_TYPE_NAMES = {"func", "var", "let", "init", "subscript", "deinit", "override", "static", "final"}
AMBIGUOUS_TYPE_NAMES = {
    "CodingKeys", "Coordinator", "State", "Result", "Error", "Category", "Level", "Kind",
    "Metrics", "Page", "Reply", "Transport", "Connection", "Authentication", "Buffer",
    "Template", "Endpoint", "Exposure", "Group", "Filter", "DB", "Tab", "Style", "Mode",
}


def strip_swift(src: str) -> tuple[str, list[tuple[int, str]]]:
    """Blank out comments and string literal contents, keeping newlines and code inside
    string interpolations. Returns (code, [(line, string_value)])."""
    out = list(src)
    strings: list[tuple[int, str]] = []
    n = len(src)
    i = 0
    line = 1
    # contexts: ["code", paren_depth] or ["str", hashes, multiline, start_line, buffer]
    stack: list[list] = [["code", 0]]

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        ctx = stack[-1]
        c = src[i]
        if ctx[0] == "code":
            if c == "\n":
                line += 1
                i += 1
                continue
            if src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
                continue
            if src.startswith("/*", i):
                depth, j = 1, i + 2
                while j < n and depth:
                    if src.startswith("/*", j):
                        depth, j = depth + 1, j + 2
                    elif src.startswith("*/", j):
                        depth, j = depth - 1, j + 2
                    else:
                        if src[j] == "\n":
                            line += 1
                        j += 1
                blank(i, j)
                i = j
                continue
            m = RAW_OPEN.match(src, i)
            if m and (c == '"' or c == "#"):
                stack.append(["str", len(m.group(1)), m.group(2) == '"""', line, []])
                blank(i, m.end())
                i = m.end()
                continue
            if c == "(":
                ctx[1] += 1
            elif c == ")":
                if len(stack) > 1 and ctx[1] == 0:
                    stack.pop()  # end of a string interpolation
                    blank(i, i + 1)
                    i += 1
                    continue
                ctx[1] -= 1
            i += 1
            continue

        _, hashes, multi, sline, buf = ctx
        esc = "\\" + "#" * hashes
        if src.startswith(esc, i):
            k = i + len(esc)
            if k < n and src[k] == "(":
                blank(i, k + 1)
                buf.append("{}")
                stack.append(["code", 0])
                i = k + 1
                continue
            if k < n and src[k] == "\n":
                line += 1
            buf.append(src[k:k + 1])
            blank(i, k + 1)
            i = k + 1
            continue
        close = ('"""' if multi else '"') + "#" * hashes
        if src.startswith(close, i):
            blank(i, i + len(close))
            i += len(close)
            strings.append((sline, "".join(buf)))
            stack.pop()
            continue
        if c == "\n":
            line += 1
            if not multi:  # unterminated single-line literal: recover
                strings.append((sline, "".join(buf)))
                stack.pop()
                i += 1
                continue
        else:
            out[i] = " "
        buf.append(c)
        i += 1
    return "".join(out), strings


def scan_swift(text: str) -> dict:
    code, strings = strip_swift(text)
    lines = code.split("\n")
    raw_lines = text.split("\n")
    strings_by_line: dict[int, list[str]] = {}
    for ln, val in strings:
        strings_by_line.setdefault(ln, []).append(val)

    types, funcs, wrappers, markers = [], [], [], []
    type_stack: list[tuple[str, int]] = []  # (name, depth at which its body opened)
    pending: str | None = None
    depth = 0
    main_pending = False
    owners: list[str | None] = [None]  # owners[i]: outermost type (or extended type) around line i
    for idx, ln_code in enumerate(lines, start=1):
        stripped = ln_code.strip()
        parent = type_stack[-1][0] if type_stack else None
        owner_before = type_stack[0][0] if type_stack else None
        if stripped.startswith("@main"):
            main_pending = True
        m = TYPE_RE.match(ln_code)
        if m and m.group(2) not in NOT_TYPE_NAMES:
            kind, name, rest = m.group(1), m.group(2), m.group(3)
            conforms = []
            head = rest.split("{", 1)[0].split(" where ", 1)[0]
            if ":" in head:
                conforms = [p.strip().split("<")[0] for p in head.split(":", 1)[1].split(",") if p.strip()]
            types.append({"name": name, "kind": kind, "line": idx, "parent": parent, "conforms": conforms})
            if main_pending and kind in ("struct", "class"):
                markers.append({"marker": "@main", "line": idx})
                main_pending = False
            for proto in conforms:
                if proto in ("AppIntent", "AppShortcutsProvider", "AppEntity", "WidgetBundle", "Widget"):
                    markers.append({"marker": proto, "line": idx})
            pending = name
        for fm in FUNC_RE.finditer(ln_code):
            funcs.append({"name": fm.group(1), "line": idx, "parent": parent})
        for wm in WRAPPER_RE.finditer(ln_code):
            key = (strings_by_line.get(idx) or [None])[0] if wm.group(1) in ("AppStorage", "SceneStorage") else None
            wrappers.append({"wrapper": wm.group(1), "name": wm.group(3), "line": idx, "key": key})
        if stripped.startswith(("#if", "#elseif")):
            markers.append({"marker": stripped.split("//")[0].strip(), "line": idx})
        raw = raw_lines[idx - 1] if idx - 1 < len(raw_lines) else ""
        for token in ("NSClassFromString", "#selector", "@objc", "forResource:"):
            if token in ln_code or (token == "forResource:" and token in raw):
                markers.append({"marker": token, "line": idx})
        for ch in ln_code:
            if ch == "{":
                depth += 1
                if pending is not None:
                    type_stack.append((pending, depth))
                    pending = None
            elif ch == "}":
                if type_stack and type_stack[-1][1] == depth:
                    type_stack.pop()
                depth -= 1
        owners.append(owner_before or (type_stack[0][0] if type_stack else None))

    refs: dict[str, int] = {}
    for idx, ln_code in enumerate(lines, start=1):
        for im in IDENT_RE.finditer(ln_code):
            refs.setdefault(im.group(1), idx)

    endpoints, keys = [], []
    for ln, val in strings:
        if "/v1/" in val or val.startswith("v1/") or "://" in val:
            endpoints.append({"line": ln, "value": val[:160]})
        raw = raw_lines[ln - 1] if 0 < ln <= len(raw_lines) else ""
        if any(t in raw for t in ("forKey", "AppStorage", "kSecAttrService", "kSecAttrAccount", "UserDefaults")):
            keys.append({"line": ln, "value": val[:120]})
    return {"types": types, "funcs": funcs, "wrappers": wrappers, "markers": markers,
            "refs": refs, "endpoints": endpoints, "keys": keys, "code": code, "owners": owners}


# ---------------------------------------------------------------- Xcode target membership

def parse_pbxproj(path: Path) -> dict:
    """Map targets to synchronized folders (minus exceptions) and explicit source names."""
    text = path.read_text(errors="replace")

    def section(name: str) -> str:
        m = re.search(rf"/\* Begin {name} section \*/(.*?)/\* End {name} section \*/", text, re.S)
        return m.group(1) if m else ""

    def objects(sec: str) -> dict[str, str]:
        return {m.group(1): m.group(2) for m in
                re.finditer(r"([0-9A-F]{24}) /\*[^*]*\*/ = \{(.*?)\n\t\t\};", sec, re.S)}

    targets = {}
    phases_sources = {oid: re.findall(r"/\* ([^*]+?) in Sources \*/", body)
                      for oid, body in objects(section("PBXSourcesBuildPhase")).items()}
    phases_resources = {oid: re.findall(r"/\* ([^*]+?) in Resources \*/", body)
                        for oid, body in objects(section("PBXResourcesBuildPhase")).items()}
    groups = {}
    for oid, body in objects(section("PBXFileSystemSynchronizedRootGroup")).items():
        pm = re.search(r"path = \"?([^\";]+)\"?;", body)
        groups[oid] = {"path": pm.group(1) if pm else None,
                       "exceptions": re.findall(r"([0-9A-F]{24}) /\*", body.split("exceptions", 1)[1])
                       if "exceptions" in body else []}
    exceptions = {}
    for oid, body in objects(section("PBXFileSystemSynchronizedBuildFileExceptionSet")).items():
        mem = re.search(r"membershipExceptions = \((.*?)\);", body, re.S)
        tgt = re.search(r"target = ([0-9A-F]{24})", body)
        exceptions[oid] = {"files": [f.strip().strip('"') for f in (mem.group(1).split(",") if mem else []) if f.strip()],
                           "target": tgt.group(1) if tgt else None}
    for oid, body in objects(section("PBXNativeTarget")).items():
        nm = re.search(r"\bname = \"?([^\";]+)\"?;", body)
        name = nm.group(1) if nm else oid
        phase_ids = re.findall(r"([0-9A-F]{24}) /\* \w+ \*/", body.split("buildPhases", 1)[1].split(");", 1)[0]) \
            if "buildPhases" in body else []
        sync_ids = re.findall(r"([0-9A-F]{24})", body.split("fileSystemSynchronizedGroups", 1)[1].split(");", 1)[0]) \
            if "fileSystemSynchronizedGroups" in body else []
        sources, resources = set(), set()
        for pid in phase_ids:
            sources.update(phases_sources.get(pid, []))
            resources.update(phases_resources.get(pid, []))
        sync = []
        for gid in sync_ids:
            g = groups.get(gid)
            if not g or not g["path"]:
                continue
            excluded = []
            for eid in g["exceptions"]:
                e = exceptions.get(eid)
                if e and e["target"] == oid:
                    excluded.extend(e["files"])
            sync.append({"path": g["path"], "excluded": excluded})
        targets[name] = {"sources": sources, "resources": resources, "sync": sync}
    return targets


def target_membership(m: Map, files: list[str]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {f: [] for f in files}
    proj = m.config.get("xcodeproj")
    if proj and (m.root / proj / "project.pbxproj").is_file():
        targets = parse_pbxproj(m.root / proj / "project.pbxproj")
        for f in files:
            base = os.path.basename(f)
            for tname, t in targets.items():
                hit = False
                for s in t["sync"]:
                    prefix = s["path"].rstrip("/") + "/"
                    if f.startswith(prefix):
                        hit = f[len(prefix):] not in s["excluded"]
                if not hit and (base in t["sources"] or base in t["resources"]):
                    hit = True
                if hit:
                    result[f].append(tname)
    elif (m.root / "Package.swift").is_file():
        for f in files:
            parts = f.split("/")
            if len(parts) > 2 and parts[0] in ("Sources", "Tests"):
                result[f].append(parts[1])
    return result


# ---------------------------------------------------------------- inventory

class Inventory:
    def __init__(self, m: Map):
        self.m = m
        cfg = m.config
        self.source_ext = tuple(cfg.get("source_extensions", [".swift"]))
        self.resource_ext = tuple(cfg.get("resource_extensions", []))
        self.ignore = cfg.get("ignore", [])
        self.files: dict[str, dict] = {}
        self.raw: dict[str, list[str]] = {}
        roots = [(r, "source") for r in cfg.get("source_roots", [])] + \
                [(r, "test") for r in cfg.get("test_roots", [])]
        for root_rel, area in roots:
            base = m.root / root_rel
            if not base.exists():
                continue
            for dirpath, dirnames, filenames in os.walk(base):
                rel_dir = os.path.relpath(dirpath, m.root)
                keep_dirs = []
                for d in dirnames:
                    rel = os.path.join(rel_dir, d)
                    if self._ignored(rel, d):
                        continue
                    if "." in d and d.endswith(self.resource_ext):
                        self.files[rel] = {"path": rel, "area": area, "kind": "resource"}
                        continue
                    keep_dirs.append(d)
                dirnames[:] = keep_dirs
                for fn in filenames:
                    rel = os.path.join(rel_dir, fn)
                    if self._ignored(rel, fn):
                        continue
                    if fn.endswith(self.source_ext):
                        kind = "source"
                    elif fn.endswith(self.resource_ext) or any(fnmatch.fnmatch(fn, p) for p in cfg.get("resource_globs", [])):
                        kind = "resource"
                    else:
                        kind = "other"
                    self.files[rel] = {"path": rel, "area": area, "kind": kind}
        membership = target_membership(m, list(self.files))
        for rel, info in self.files.items():
            info["targets"] = membership.get(rel, [])
            if info["kind"] == "source" and rel.endswith(".swift"):
                text = (m.root / rel).read_text(errors="replace")
                self.raw[rel] = text.split("\n")
                info["lines"] = len(self.raw[rel])
                info["scan"] = scan_swift(text)
        self._build_refs()

    def _ignored(self, rel: str, name: str) -> bool:
        return any(fnmatch.fnmatch(name, p) or fnmatch.fnmatch(rel, p) for p in self.ignore)

    def _build_refs(self) -> None:
        self.declared: dict[str, list[str]] = {}
        self.decl_line: dict[tuple[str, str], dict] = {}
        for rel, info in self.files.items():
            for t in info.get("scan", {}).get("types", []):
                if t["kind"] != "extension" and t["parent"] is None and t["name"] not in AMBIGUOUS_TYPE_NAMES:
                    self.declared.setdefault(t["name"], []).append(rel)
                    self.decl_line[(rel, t["name"])] = t
        self.inbound: dict[str, set[str]] = {rel: set() for rel in self.files}
        self.outbound: dict[str, dict[str, str]] = {rel: {} for rel in self.files}
        for rel, info in self.files.items():
            for name in info.get("scan", {}).get("refs", {}):
                for decl_file in self.declared.get(name, []):
                    if decl_file != rel:
                        self.inbound[decl_file].add(rel)
                        self.outbound[rel].setdefault(decl_file, name)
        # Files that only extend other types are reached through their members, not a type name.
        for rel, info in self.files.items():
            scan = info.get("scan")
            if not scan or any(t["kind"] != "extension" and t["parent"] is None for t in scan["types"]):
                continue
            members = {f["name"] for f in scan["funcs"] if len(f["name"]) >= 6 and f["name"].isidentifier()}
            members |= {t["name"] for t in scan["types"] if t["parent"] and len(t["name"]) >= 6}
            if not members:
                continue
            pattern = re.compile(r"\b(" + "|".join(sorted(map(re.escape, members))) + r")\b")
            for other, oinfo in self.files.items():
                if other != rel and "scan" in oinfo and pattern.search(oinfo["scan"]["code"]):
                    self.inbound[rel].add(other)

    def swift_files(self) -> list[str]:
        return sorted(r for r, i in self.files.items() if "scan" in i)

    def unique_decl(self, name: str) -> str | None:
        files = self.declared.get(name, [])
        return files[0] if len(files) == 1 else None


# ---------------------------------------------------------------- slice helpers

def all_nodes(sl: dict) -> list[dict]:
    return list(sl.get("nodes", [])) + list((sl.get("derived") or {}).get("nodes", []))


def all_edges(sl: dict) -> list[dict]:
    return list(sl.get("edges", [])) + list((sl.get("derived") or {}).get("edges", []))


def split_ref(end: str, local_ids: set[str], features: set[str]) -> tuple[str, str | None, str]:
    """Classify an edge endpoint: local node, feature:<id>, <feature>#<node>, or bad."""
    if end in local_ids:
        return "local", None, end
    if end.startswith("feature:"):
        return "feature", end[len("feature:"):], ""
    if "#" in end:
        feat, _, node = end.partition("#")
        return "node", feat, node
    if ":" in end:
        feat, _, node = end.partition(":")
        if feat in features:  # older form <feature>:<node>
            return "node", feat, node
    return "bad", None, end


def iter_evidence(sl: dict):
    """Yield (kind, owner_label, evidence_dict) for every citation in a slice."""
    for node in all_nodes(sl):
        if node.get("path") and node.get("match"):
            yield "node", node.get("id", "?"), node
    for edge in all_edges(sl):
        label = f"{edge.get('from')} -{edge.get('type')}-> {edge.get('to')}"
        for ev in edge.get("evidence", []) or []:
            yield "edge", label, ev
    for doc in sl.get("docs", []):
        ev = doc.get("evidence")
        if isinstance(ev, dict) and ev.get("path") and ev.get("match"):
            yield "doc-code", f"{doc.get('path')} :: {doc.get('section', '')}", ev
        if doc.get("quote"):
            yield "doc-quote", f"{doc.get('path')} :: {doc.get('section', '')}", {"path": doc.get("path"), "match": doc["quote"]}


def find_match(root: Path, rel: str, match: str, hint: int | None, cache: dict) -> int | None:
    """Return the 1-based line where `match` occurs (whitespace-insensitive), nearest the hint."""
    if rel not in cache:
        p = root / rel
        cache[rel] = [norm_ws(x) for x in p.read_text(errors="replace").split("\n")] if p.is_file() else None
    lines = cache[rel]
    if lines is None or not match:
        return None
    needle = norm_ws(match)
    hits = [i + 1 for i, text in enumerate(lines) if needle in text]
    if not hits:
        return None
    if hint:
        return min(hits, key=lambda h: abs(h - hint))
    return hits[0]


class Finding:
    def __init__(self, level: str, feature: str, what: str, detail: str):
        self.level, self.feature, self.what, self.detail = level, feature, what, detail

    def as_dict(self) -> dict:
        return {"level": self.level, "feature": self.feature, "what": self.what, "detail": self.detail}


def load_all(m: Map):
    slices = m.slices()
    all_ids = {str(sl.get("id", p.stem)) for p, sl in slices}
    node_index = {}
    for p, sl in slices:
        for node in all_nodes(sl):
            node_index[(str(sl.get("id", p.stem)), node.get("id"))] = node
    return slices, all_ids, node_index


def claimed_paths(slices) -> dict[str, list[tuple[str, str]]]:
    owners: dict[str, list[tuple[str, str]]] = {}
    for p, sl in slices:
        for f in sl.get("files", []):
            owners.setdefault(f.get("path"), []).append((str(sl.get("id", p.stem)), f.get("role")))
    return owners


def validate_slice(m: Map, path: Path, sl: dict, all_ids: set[str], node_index: dict, cache: dict) -> list[Finding]:
    fid = str(sl.get("id", path.stem))
    out: list[Finding] = []
    features = all_ids | set(m.config.get("features", []))

    def add(level, what, detail):
        out.append(Finding(level, fid, what, detail))

    if sl.get("schema") != SLICE_SCHEMA:
        add("error", "schema", f"schema is {sl.get('schema')!r}, expected {SLICE_SCHEMA}")
    if fid != path.stem:
        add("error", "schema", f"id {fid!r} does not match file name {path.stem!r}")
    for key in ("name", "purpose", "revision", "verified_on"):
        if not sl.get(key):
            add("error", "schema", f"missing {key}")
    for f in sl.get("files", []):
        p = m.root / f.get("path", "")
        if f.get("role") not in FILE_ROLES:
            add("error", "schema", f"file {f.get('path')}: role must be one of {sorted(FILE_ROLES)}")
        if not p.exists():
            add("error", "missing-path", f"{f.get('path')} does not exist")
        elif p.is_file() and f.get("blob") and blob_hash(p) != f["blob"]:
            add("warn", "changed", f"{f['path']} changed since the slice was stamped")
    local_ids: set[str] = set()
    kinds: dict[str, str] = {}
    for node in all_nodes(sl):
        nid = node.get("id")
        if not nid:
            add("error", "schema", "node without id")
            continue
        if nid in local_ids:
            add("error", "schema", f"duplicate node id {nid}")
        local_ids.add(nid)
        kinds[nid] = node.get("kind", "")
        if node.get("kind") not in NODE_KINDS:
            add("error", "schema", f"node {nid}: kind {node.get('kind')!r} not in {sorted(NODE_KINDS)}")
        if node.get("status") not in STATUSES:
            add("error", "schema", f"node {nid}: status {node.get('status')!r}")
        if node.get("status") == "VERIFIED" and not (node.get("path") and node.get("match")):
            add("error", "evidence", f"node {nid} is VERIFIED without path and match")
    for nid in sl.get("entry_points", []):
        if nid not in local_ids:
            add("error", "dangling", f"entry point {nid} is not a node in this slice")
    for edge in all_edges(sl):
        label = f"{edge.get('from')} -{edge.get('type')}-> {edge.get('to')}"
        if edge.get("type") not in EDGE_TYPES:
            add("error", "schema", f"edge {label}: type not in {sorted(EDGE_TYPES)}")
        if edge.get("status") not in STATUSES:
            add("error", "schema", f"edge {label}: status {edge.get('status')!r}")
        if edge.get("status") == "VERIFIED" and not edge.get("evidence"):
            add("error", "evidence", f"edge {label} is VERIFIED without evidence")
        if edge.get("type") == "tested_by" and kinds.get(edge.get("from", "")) == "test":
            add("error", "direction", f"edge {label}: tested_by points from the tested code to the test")
        if edge.get("status") == "VERIFIED" and edge.get("type") in USE_EDGES:
            for ev in edge.get("evidence") or []:
                if DECLARATION_LINE.match(ev.get("match", "")):
                    add("warn", "weak-evidence", f"edge {label}: cites a declaration, not a use: {ev.get('match', '')[:70]!r}")
        for end in (edge.get("from"), edge.get("to")):
            if not end or end == "?":
                continue
            kind, feat, node = split_ref(end, local_ids, features)
            if kind == "feature" and feat not in features:
                add("error", "dangling", f"edge {label}: unknown feature {feat}")
            elif kind == "node" and (feat, node) not in node_index:
                if feat in all_ids:
                    add("error", "dangling", f"edge {label}: slice {feat} has no node {node}")
                elif feat in features:
                    add("warn", "dangling", f"edge {label}: slice {feat} is not written yet")
                else:
                    add("error", "dangling", f"edge {label}: unknown feature {feat}")
            elif kind == "bad":
                add("error", "dangling", f"edge {label}: {end} is not a node in this slice "
                                         f"(cross-slice links are feature:<id> or <feature>#<node>)")
    for doc in sl.get("docs", []):
        if doc.get("status") not in DOC_STATUSES:
            add("error", "schema", f"doc {doc.get('path')}: status {doc.get('status')!r}")
        if doc.get("path") and not (m.root / doc["path"]).exists():
            add("error", "missing-path", f"doc {doc['path']} does not exist")
    for related in sl.get("related", []):
        if related not in features:
            add("warn", "dangling", f"related feature {related} does not exist")
    for kind, owner, ev in iter_evidence(sl):
        rel = ev.get("path", "")
        if not (m.root / rel).is_file():
            add("error", "missing-path", f"{kind} {owner}: {rel} does not exist")
            continue
        line = find_match(m.root, rel, ev.get("match", ""), ev.get("line"), cache)
        if line is None:
            level = "warn" if kind == "doc-quote" else "error"
            add(level, "broken-evidence", f"{kind} {owner}: {rel} does not contain {ev.get('match')!r}")
        elif ev.get("line") and line != ev["line"]:
            add("info", "moved", f"{kind} {owner}: {rel} line {ev['line']} -> {line}")
    return out


def dump_slice(sl: dict) -> str:
    """One key per line; every object in a list on its own line, so diffs stay small."""
    def one(v) -> str:
        return json.dumps(v, ensure_ascii=False, separators=(", ", ": "))

    out = ["{"]
    keys = list(sl.keys())
    for i, key in enumerate(keys):
        val = sl[key]
        comma = "," if i < len(keys) - 1 else ""
        if isinstance(val, list) and val and all(isinstance(x, dict) for x in val):
            out.append(f"  {one(key)}: [")
            out += [f"    {one(x)}" + ("," if j < len(val) - 1 else "") for j, x in enumerate(val)]
            out.append(f"  ]{comma}")
        elif isinstance(val, dict) and any(isinstance(v, list) for v in val.values()):
            out.append(f"  {one(key)}: {{")
            sub = list(val.keys())
            for j, k in enumerate(sub):
                v = val[k]
                c2 = "," if j < len(sub) - 1 else ""
                if isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
                    out.append(f"    {one(k)}: [")
                    out += [f"      {one(x)}" + ("," if q < len(v) - 1 else "") for q, x in enumerate(v)]
                    out.append(f"    ]{c2}")
                else:
                    out.append(f"    {one(k)}: {one(v)}{c2}")
            out.append(f"  }}{comma}")
        else:
            out.append(f"  {one(key)}: {one(val)}{comma}")
    out.append("}")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- derived layer

def classify(t: dict, rel: str) -> str:
    conf = set(t.get("conforms", []))
    name = t["name"]
    if "XCTestCase" in conf or rel.split("/", 1)[0].endswith("Tests"):
        return "test"
    if conf & {"View", "UIViewRepresentable", "UIViewControllerRepresentable"}:
        return "view"
    if name.endswith("ViewModel") or (conf & {"ObservableObject"} and not name.endswith(("Service", "Store"))):
        return "view_model"
    if conf & {"App"}:
        return "entry"
    if t["kind"] == "protocol":
        return "model"
    if re.search(r"(Service|Store|Manager|Repository|Client|Runner|Session|Provider|Hub|Pipeline|Monitor|Logger|"
                 r"Authorization|Authentication|Execution|DOM)$", name):
        return "service"
    if re.search(r"(Utils|Utilities|Helper|Detector|Summarizer|Validation|Pagination|Indexing|Codec)$", name):
        return "util"
    return "model"


def snippet(raw: str, name: str) -> str:
    text = raw.strip()
    if len(text) <= 150:
        return text
    i = max(0, text.find(name))
    return text[max(0, i - 60):i + len(name) + 60].strip()


def derive_slice(inv: Inventory, sl: dict, primary_owner: dict[str, str], wanted_ids: set[str] | None = None) -> dict:
    fid = sl.get("id")
    prim = [f["path"] for f in sl.get("files", []) if f.get("role") == "primary" and f.get("path", "").endswith(".swift")]
    curated = {n.get("id") for n in sl.get("nodes", [])}
    dnodes: dict[str, dict] = {}
    for rel in prim:
        info = inv.files.get(rel)
        if not info or "scan" not in info:
            continue
        for t in info["scan"]["types"]:
            if t["kind"] == "extension" or t["parent"] is not None or t["name"] in curated:
                continue
            dnodes[t["name"]] = {"id": t["name"], "kind": classify(t, rel), "path": rel, "line": t["line"],
                                 "match": snippet(inv.raw[rel][t["line"] - 1], t["name"]), "status": "VERIFIED",
                                 "note": "declaration"}
    local = curated | set(dnodes)

    def target_for(name: str, from_file: str) -> str | None:
        decl = inv.unique_decl(name)
        if not decl or decl == from_file:
            return None
        if name in local and decl in prim:
            return name
        other = primary_owner.get(decl)
        if other and other != fid:
            return f"{other}#{name}"
        return None

    internal: dict = {}
    external: dict = {}
    for rel in prim:
        info = inv.files.get(rel)
        if not info or "scan" not in info:
            continue
        code_lines = info["scan"]["code"].split("\n")
        owners = info["scan"]["owners"]
        for idx, ln in enumerate(code_lines, start=1):
            owner = owners[idx] if idx < len(owners) else None
            if not owner:
                continue
            src = owner if owner in local else None
            if src is None:
                owner_file = inv.unique_decl(owner)
                other = primary_owner.get(owner_file) if owner_file else None
                src = f"{other}#{owner}" if other and other != fid else None
            if src is None:
                continue
            for name in sorted(set(IDENT_RE.findall(ln))):
                if name == owner:
                    continue
                tgt = target_for(name, rel)
                if not tgt or tgt == src:
                    continue
                bucket = internal if tgt in local else external
                if (src, tgt) not in bucket:
                    bucket[(src, tgt)] = {"from": src, "type": "depends_on", "to": tgt, "status": "INFERRED",
                                          "evidence": [{"path": rel, "line": idx, "match": snippet(inv.raw[rel][idx - 1], name)}],
                                          "note": "type reference"}
    tests: dict = {}
    prim_types = set(dnodes) | {n.get("id") for n in sl.get("nodes", []) if n.get("path") in prim}
    prim_types = {t for t in prim_types if t and not t.startswith("test:") and re.fullmatch(r"[A-Z]\w+", t)}
    for rel, info in sorted(inv.files.items()):
        if info.get("area") != "test" or "scan" not in info:
            continue
        cls = next((t["name"] for t in info["scan"]["types"] if "XCTestCase" in t.get("conforms", [])), None)
        if not cls:
            continue
        code_lines = info["scan"]["code"].split("\n")
        for name in sorted(prim_types):
            pat = re.compile(rf"\b{re.escape(name)}\b")
            idx = next((i for i, ln in enumerate(code_lines, start=1) if pat.search(ln)), None)
            if idx is None:
                continue
            tid = f"test:{cls}"
            decl = inv.decl_line.get((rel, cls))
            if tid not in dnodes and tid not in curated and decl:
                dnodes[tid] = {"id": tid, "kind": "test", "path": rel, "line": decl["line"],
                               "match": snippet(inv.raw[rel][decl["line"] - 1], cls), "status": "VERIFIED",
                               "note": "test case"}
            if tid in dnodes or tid in curated:
                tests[(name, tid)] = {"from": name, "type": "tested_by", "to": tid, "status": "INFERRED",
                                      "evidence": [{"path": rel, "line": idx, "match": snippet(inv.raw[rel][idx - 1], name)}],
                                      "note": "test mentions the type"}
    # Cross-feature references collapse to one edge per (source, other feature).
    grouped: dict = {}
    for (src, tgt), edge in external.items():
        other, _, name = tgt.partition("#")
        key = (src, other)
        if key not in grouped:
            grouped[key] = dict(edge, to=f"feature:{other}", note=f"via {name}")
        elif name not in grouped[key]["note"]:
            names = grouped[key]["note"][4:].split(", ")
            if len(names) < 4:
                grouped[key]["note"] += f", {name}"
    edges = list(internal.values()) + list(tests.values()) + list(grouped.values())
    kept = edges[:DERIVED_EDGE_CAP]
    used = {e["from"] for e in kept} | {e["to"] for e in kept} | set(sl.get("entry_points", []))
    used |= {end for e in sl.get("edges", []) for end in (e.get("from"), e.get("to")) if end}
    used |= wanted_ids or set()  # nodes other slices link to as <this-feature>#<node>
    nodes = [n for n in dnodes.values() if n["id"] in used]
    for n in nodes:
        n.pop("note", None)
    for e in kept:
        if e.get("note") in ("type reference", "test mentions the type"):
            e.pop("note")
    return {"generated_by": f"codemap {VERSION} derive: declarations, type references and test mentions; edges are INFERRED",
            "nodes": nodes, "edges": kept, "edges_omitted": max(0, len(edges) - DERIVED_EDGE_CAP)}


def cmd_derive(m: Map, args) -> int:
    inv = Inventory(m)
    slices, _, _ = load_all(m)
    primary_owner = {}
    for p, sl in slices:
        for f in sl.get("files", []):
            if f.get("role") == "primary":
                primary_owner[f.get("path")] = str(sl.get("id", p.stem))
    wanted = set(args.ids or [])
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        if (wanted and fid not in wanted) or sl.get("index") is False:
            continue
        wanted_nodes = {end.partition("#")[2] for _, other in slices for e in other.get("edges", [])
                        for end in (e.get("from", ""), e.get("to", "")) if end.startswith(fid + "#")}
        sl["derived"] = derive_slice(inv, sl, primary_owner, wanted_nodes)
        p.write_text(dump_slice(sl))
        d = sl["derived"]
        print(f"{fid}: {len(d['nodes'])} derived nodes, {len(d['edges'])} derived edges"
              + (f" ({d['edges_omitted']} over the cap of {DERIVED_EDGE_CAP} omitted)" if d["edges_omitted"] else ""))
    return 0


# ---------------------------------------------------------------- commands

def cmd_check(m: Map, args) -> int:
    slices, all_ids, node_index = load_all(m)
    cache: dict = {}
    wanted = set(args.ids or [])
    findings: list[Finding] = []
    head = head_revision(m.root)
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        if wanted and fid not in wanted:
            continue
        findings.extend(validate_slice(m, p, sl, all_ids, node_index, cache))
        rev = sl.get("revision")
        if rev:
            ok = subprocess.run(["git", "-C", str(m.root), "cat-file", "-e", f"{rev}^{{commit}}"],
                                capture_output=True).returncode == 0
            if not ok:
                findings.append(Finding("warn", fid, "revision", f"revision {rev} is not in this repository"))
            else:
                behind = run_git(m.root, "rev-list", "--count", f"{rev}..HEAD").strip()
                if behind != "0":
                    findings.append(Finding("info", fid, "revision", f"stamped at {rev}, {behind} commits behind {head}"))
    if not wanted:
        inv = Inventory(m)
        owners = claimed_paths(slices)
        notes = m.config.get("unmapped_notes", {})
        for f in sorted(inv.files):
            if f not in owners and inv.files[f]["kind"] != "other" and f not in notes:
                findings.append(Finding("warn", "-", "unmapped", f"{f} is not claimed by any slice or listed in unmapped_notes"))
    counts = {lvl: sum(1 for f in findings if f.level == lvl) for lvl in ("error", "warn", "info")}
    if args.json:
        print(json.dumps({"head": head, "counts": counts, "findings": [f.as_dict() for f in findings]}, indent=2))
    else:
        for f in findings:
            if args.verbose or f.level != "info":
                print(f"{f.level.upper():5} {f.feature:26} {f.what:16} {f.detail}")
        print(f"codemap check at {head}: {len(slices)} slices, {counts['error']} errors, "
              f"{counts['warn']} warnings, {counts['info']} notes" + ("" if args.verbose else " (-v shows notes)"))
    return 1 if counts["error"] else 0


def changed_since(m: Map, rev: str) -> set[str]:
    changed = set(filter(None, run_git(m.root, "diff", "--name-only", rev, check=False).split("\n")))
    changed |= set(filter(None, run_git(m.root, "ls-files", "--others", "--exclude-standard", check=False).split("\n")))
    return changed


def removed_symbols_note(m: Map, rev: str, rel: str) -> str:
    if not rel.endswith(".swift"):
        return ""
    old = subprocess.run(["git", "-C", str(m.root), "show", f"{rev}:{rel}"], capture_output=True, text=True)
    new_path = m.root / rel
    if old.returncode != 0:
        return "  (new file)"
    if not new_path.is_file():
        return "  (deleted)"
    old_scan = scan_swift(old.stdout)
    new_scan = scan_swift(new_path.read_text(errors="replace"))
    before = {t["name"] for t in old_scan["types"]} | {f["name"] for f in old_scan["funcs"]}
    after = {t["name"] for t in new_scan["types"]} | {f["name"] for f in new_scan["funcs"]}
    gone, new = sorted(before - after), sorted(after - before)
    parts = []
    if gone:
        parts.append("removed: " + ", ".join(gone[:8]) + (" ..." if len(gone) > 8 else ""))
    if new:
        parts.append("added: " + ", ".join(new[:8]) + (" ..." if len(new) > 8 else ""))
    return ("  (" + "; ".join(parts) + ")") if parts else ""


def cmd_affected(m: Map, args) -> int:
    """Slices the code has moved away from since stamping, and new files no slice claims.

    A listed file counts when its content differs from the recorded blob; a citation counts when its line is
    gone. With --since REV, every slice that lists or cites a file changed since REV counts instead.
    """
    slices, _, _ = load_all(m)
    revs = {args.since} if args.since else {sl.get("revision") for _, sl in slices if sl.get("revision")}
    changed: set[str] = set()
    for rev in revs:
        changed |= changed_since(m, rev)
    rev_of = {str(sl.get("id", p.stem)): args.since or sl.get("revision") for p, sl in slices}
    if args.since:
        stale: dict[str, list[tuple[str, str]]] = {}
        for p, sl in slices:
            files = {f.get("path") for f in sl.get("files", [])}
            cited = {ev.get("path") for _, _, ev in iter_evidence(sl)}
            hits = sorted(x for x in (files | cited) & changed if x)
            if hits:
                stale[str(sl.get("id", p.stem))] = [(h, f"changed since {args.since}") for h in hits]
    else:
        listed = {f.get("path", "") for _, sl in slices for f in sl.get("files", [])}
        stale = stale_slices_for(m, slices, listed | changed)
    for fid, items in sorted(stale.items()):
        print(f"{fid}:")
        for path, why in dict.fromkeys(items):
            note = removed_symbols_note(m, rev_of[fid], path) if rev_of.get(fid) and why.startswith("changed") else ""
            print(f"    {path}: {why}{note}")
    new = unclaimed_new(m, slices, changed)
    if new:
        print("changed files no slice claims:")
        for f in new:
            print(f"    {f}")
    if not stale and not new:
        print("no slice is affected")
    return 0


def cmd_stamp(m: Map, args) -> int:
    slices, all_ids, node_index = load_all(m)
    head = head_revision(m.root)
    rc = 0
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        if fid not in args.ids:
            continue
        cache: dict = {}
        errors = [f for f in validate_slice(m, p, sl, all_ids, node_index, cache) if f.level == "error"]
        if errors:
            rc = 1
            print(f"{fid}: not stamped, {len(errors)} errors:")
            for f in errors:
                print(f"    {f.what}: {f.detail}")
            continue
        for _, _, ev in iter_evidence(sl):
            line = find_match(m.root, ev["path"], ev.get("match", ""), ev.get("line"), cache)
            if line and "line" in ev:
                ev["line"] = line
        for f in sl.get("files", []):
            fp = m.root / f["path"]
            if fp.is_file():
                f["blob"] = blob_hash(fp)
        sl["revision"] = head
        sl["verified_on"] = today()
        p.write_text(dump_slice(sl))
        print(f"{fid}: stamped at {head}")
    for fid in sorted(set(args.ids) - all_ids):
        rc = 1
        print(f"{fid}: no such slice")
    return rc


def cmd_find(m: Map, args) -> int:
    slices, _, _ = load_all(m)
    words = [w.lower() for w in re.findall(r"[\w.+-]+", " ".join(args.words)) if len(w) > 1]
    weights = {"name": 3, "aliases": 3, "purpose": 1, "nodes": 1}
    scored = []
    for p, sl in slices:
        if sl.get("index") is False:
            continue
        fields = {
            "name": sl.get("name", ""), "aliases": " ".join(sl.get("aliases", [])),
            "purpose": sl.get("purpose", ""),
            "nodes": " ".join(n.get("id", "") + " " + n.get("path", "") for n in all_nodes(sl)),
        }
        score = sum(weights[f] for w in words for f, text in fields.items() if w in text.lower())
        if score:
            scored.append((score, str(sl.get("id", p.stem)), sl.get("name", ""), p))
    for score, fid, name, p in sorted(scored, reverse=True)[:args.limit]:
        print(f"{score:3}  {fid:26} {name}  ->  {p.relative_to(m.root)}")
    if not scored:
        print("no feature matched; read INDEX.md or try `refs <Symbol>`")
    return 0


def cmd_owner(m: Map, args) -> int:
    slices, _, _ = load_all(m)
    owners = claimed_paths(slices)
    target = os.path.normpath(args.path)
    hits = owners.get(target, [])
    if not hits:
        cited = sorted({str(sl.get("id", p.stem)) for p, sl in slices
                        for _, _, ev in iter_evidence(sl) if ev.get("path") == target})
        print(f"{target}: no slice claims it" + (f"; cited by {', '.join(cited)}" if cited else ""))
        notes = m.config.get("unmapped_notes", {})
        if target in notes:
            print(f"unmapped note: {notes[target]}")
        return 1
    for fid, role in hits:
        print(f"{fid:26} {role}")
    return 0


def cmd_refs(m: Map, args) -> int:
    inv = Inventory(m)
    sym = args.symbol
    word = re.compile(rf"\b{re.escape(sym)}\b")
    decls, uses = [], []
    for rel in inv.swift_files():
        scan = inv.files[rel]["scan"]
        for t in scan["types"]:
            if t["name"] == sym:
                decls.append(f"{rel}:{t['line']}  {t['kind']} {sym}" + (f" (in {t['parent']})" if t["parent"] else ""))
        for fn in scan["funcs"]:
            if fn["name"] == sym:
                decls.append(f"{rel}:{fn['line']}  func {sym}" + (f" (in {fn['parent']})" if fn["parent"] else ""))
        count, first = 0, None
        for i, text in enumerate(scan["code"].split("\n"), start=1):
            if word.search(text):
                count += 1
                first = first or i
        if count:
            uses.append((rel, first, count))
    print(f"declarations of {sym}:")
    for d in decls or ["(none found by the scanner)"]:
        print(f"  {d}")
    print(f"files mentioning {sym} (comments and strings excluded):")
    for rel, first, count in uses:
        print(f"  {rel}:{first}  x{count}")
    return 0


def unreachable_types(inv: Inventory) -> list[dict]:
    """Top-level source types that no path of type references reaches from an app entry point.

    Edges come from references inside a type's body (extensions count for the extended type).
    References in previews and at file scope do not make anything reachable. A mention is not a
    use, so this over-approximates reachability: what it reports unreachable is a strong lead."""
    graph: dict[str, set[str]] = {}
    roots: set[str] = set()
    for rel, info in inv.files.items():
        scan = info.get("scan")
        if not scan or info.get("area") != "source":
            continue
        for t in scan["types"]:
            if t["parent"] is None and t["kind"] != "extension" and t["name"] in inv.declared:
                graph.setdefault(t["name"], set())
        for mk in scan["markers"]:
            if mk["marker"] in ("@main", "AppIntent", "AppShortcutsProvider", "WidgetBundle"):
                owner = scan["owners"][mk["line"]] if mk["line"] < len(scan["owners"]) else None
                decl = next((t["name"] for t in scan["types"] if t["line"] == mk["line"]), owner)
                if decl:
                    roots.add(decl)
        for idx, ln in enumerate(scan["code"].split("\n"), start=1):
            owner = scan["owners"][idx] if idx < len(scan["owners"]) else None
            if not owner:
                continue
            if owner not in inv.declared:
                # An extension of a framework type (View, UIImage, String) is callable from anywhere.
                owner = f"(extension {owner})"
                roots.add(owner)
            for name in IDENT_RE.findall(ln):
                if name != owner and name in inv.declared:
                    graph.setdefault(owner, set()).add(name)
    seen, stack = set(roots), list(roots)
    while stack:
        for nxt in graph.get(stack.pop(), ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    out = []
    for name in sorted(set(graph) - seen):
        if name.startswith("(extension "):
            continue
        for rel in inv.declared.get(name, []):
            if inv.files[rel].get("area") == "source":
                t = inv.decl_line[(rel, name)]
                users = sorted(o for o, refs in graph.items() if name in refs and o != name)
                out.append({"type": name, "path": rel, "line": t["line"], "mentioned_by": users[:5]})
    return out


def cmd_orphans(m: Map, args) -> int:
    inv = Inventory(m)
    rows = unreachable_types(inv)
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0
    for r in rows:
        by = f"  (mentioned only by {', '.join(r['mentioned_by'])})" if r["mentioned_by"] else ""
        print(f"{r['path']}:{r['line']}  {r['type']}{by}")
    print(f"{len(rows)} types unreachable from the app entry point by type references")
    return 0


def cmd_review(m: Map, args) -> int:
    """Print each curated edge next to the line it cites, for a reader to judge the claim."""
    slices, _, _ = load_all(m)
    wanted = set(args.ids or [])
    count = 0
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        if wanted and fid not in wanted:
            continue
        for e in sl.get("edges", []):
            count += 1
            ev = (e.get("evidence") or [{}])[0]
            text, where = "", ""
            if ev.get("path") and (m.root / ev["path"]).is_file():
                lines = (m.root / ev["path"]).read_text(errors="replace").split("\n")
                line = find_match(m.root, ev["path"], ev.get("match", ""), ev.get("line"), {}) or ev.get("line") or 0
                text = lines[line - 1].strip()[:120] if 0 < line <= len(lines) else "(line out of range)"
                where = f"{os.path.basename(ev['path'])}:{line}"
            flag = "  DECLARATION" if DECLARATION_LINE.match(text) and e.get("type") in USE_EDGES else ""
            print(f"{fid[:16]:16} {e.get('status', '?')[:4]} {e.get('from', '')[:36]:36} {e.get('type', '')[:10]:10} "
                  f"{e.get('to', '')[:36]:36} | {where} {text}{flag}")
    print(f"{count} curated edges")
    return 0


def unmapped_rows(m: Map, inv: Inventory, slices) -> list[dict]:
    owners = claimed_paths(slices)
    notes = m.config.get("unmapped_notes", {})
    rows = []
    for rel in sorted(inv.files):
        info = inv.files[rel]
        if rel in owners or info["kind"] == "other":
            continue
        scan = info.get("scan", {})
        top = [t["name"] for t in scan.get("types", []) if t["parent"] is None and t["kind"] != "extension"]
        rows.append({
            "path": rel, "kind": info["kind"], "targets": info.get("targets", []),
            "lines": info.get("lines"), "types": top[:6],
            "inbound_files": len(inv.inbound.get(rel, ())),
            "markers": sorted({mk["marker"] for mk in scan.get("markers", [])})[:6],
            "note": notes.get(rel, ""),
        })
    return rows


def cmd_unmapped(m: Map, args) -> int:
    inv = Inventory(m)
    slices, _, _ = load_all(m)
    rows = unmapped_rows(m, inv, slices)
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    for r in rows:
        print(f"{r['path']}  [{', '.join(r['targets']) or 'no target'}]  inbound={r['inbound_files']}  "
              f"types={','.join(r['types']) or '-'}  {('note: ' + r['note']) if r['note'] else ''}")
    print(f"{len(rows)} files not claimed by any slice")
    return 0


def cmd_inventory(m: Map, args) -> int:
    inv = Inventory(m)
    if args.json:
        dump = {}
        for rel, info in sorted(inv.files.items()):
            entry = {k: v for k, v in info.items() if k != "scan"}
            scan = info.get("scan")
            if scan:
                entry["types"] = [f"{t['kind']} {t['name']}@{t['line']}" + (f" in {t['parent']}" if t["parent"] else "")
                                  for t in scan["types"]]
                entry["funcs"] = [f"{f['name']}@{f['line']}" for f in scan["funcs"]]
                entry["wrappers"] = [f"@{w['wrapper']} {w['name']}@{w['line']}" + (f" key={w['key']}" if w["key"] else "")
                                     for w in scan["wrappers"]]
                entry["markers"] = [f"{mk['marker']}@{mk['line']}" for mk in scan["markers"]]
                entry["endpoints"] = [f"{e['value']}@{e['line']}" for e in scan["endpoints"]]
                entry["uses_files"] = sorted(inv.outbound.get(rel, {}))
                entry["used_by_files"] = sorted(inv.inbound.get(rel, ()))
            dump[rel] = entry
        print(json.dumps(dump, indent=1))
        return 0
    swift = inv.swift_files()
    by_target: dict[str, int] = {}
    for info in inv.files.values():
        for t in info.get("targets") or ["(none)"]:
            by_target[t] = by_target.get(t, 0) + 1
    print(f"{len(inv.files)} files ({len(swift)} Swift, "
          f"{sum(inv.files[r]['lines'] for r in swift)} lines); by target: "
          + ", ".join(f"{k} {v}" for k, v in sorted(by_target.items())))
    no_inbound = [r for r in swift if not inv.inbound.get(r) and inv.files[r]["area"] == "source"]
    print(f"Swift sources whose top-level types no other file mentions: {len(no_inbound)}")
    for r in no_inbound:
        mk = sorted({x['marker'] for x in inv.files[r]['scan']['markers']})
        print(f"  {r}" + (f"  markers: {', '.join(mk)}" if mk else ""))
    return 0


# ---------------------------------------------------------------- automation
#
# `hook edit` is the Context OS kit's post-edit fast check (.claude/fast-check), `hook stop` is a Claude Code
# Stop hook (.claude/settings.json) and `hook pre-commit` is a git hook (.githooks/pre-commit). A listed
# file is stale when its content differs from the blob `stamp` recorded; a citation is stale when its
# match text is no longer in its file.

def citations_by_path(slices) -> dict[str, list[tuple[str, str, dict]]]:
    """{path: [(slice id, label, evidence)]}; the label starts with "derived " for the mechanical layer."""
    out: dict[str, list[tuple[str, str, dict]]] = {}
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        d = sl.get("derived") or {}
        derived = {id(n) for n in d.get("nodes", [])} | {id(ev) for e in d.get("edges", []) for ev in e.get("evidence") or []}
        for kind, owner, ev in iter_evidence(sl):
            tag = "derived " if id(ev) in derived else ""
            out.setdefault(ev.get("path", ""), []).append((fid, f"{tag}{kind} {owner}", ev))
    return out


def stale_slices_for(m: Map, slices, paths: set[str]) -> dict[str, list[tuple[str, str]]]:
    """Among `paths`, what no longer matches the map: {slice id: [(path, reason)]}."""
    cache: dict = {}
    stale: dict[str, list[tuple[str, str]]] = {}
    for p, sl in slices:
        fid = str(sl.get("id", p.stem))
        for f in sl.get("files", []):
            rel = f.get("path", "")
            if rel not in paths:
                continue
            full = m.root / rel
            if not full.exists():
                stale.setdefault(fid, []).append((rel, "deleted"))
            elif full.is_file() and f.get("blob") and blob_hash(full) != f["blob"]:
                stale.setdefault(fid, []).append((rel, "changed since stamped"))
    for rel, cited in sorted(citations_by_path(slices).items()):
        if rel not in paths:
            continue
        for fid, label, ev in cited:
            if find_match(m.root, rel, ev.get("match", ""), ev.get("line"), cache) is None:
                stale.setdefault(fid, []).append((rel, f"citation no longer matches ({label})"))
    return stale


def inventory_key(m: Map, rel: str) -> str | None:
    """The path `inventory` lists for `rel` (the file, or its resource bundle directory), or None."""
    cfg = m.config
    roots = [r.rstrip("/") for r in cfg.get("source_roots", []) + cfg.get("test_roots", [])]
    if not any(rel.startswith(r + "/") for r in roots):
        return None
    src = tuple(cfg.get("source_extensions", [".swift"]))
    res = tuple(cfg.get("resource_extensions", []))
    ignore = cfg.get("ignore", [])
    parts = rel.split("/")
    for i, part in enumerate(parts):
        sub = "/".join(parts[: i + 1])
        if any(fnmatch.fnmatch(part, g) or fnmatch.fnmatch(sub, g) for g in ignore):
            return None
        if i < len(parts) - 1 and "." in part and part.endswith(res):
            return sub
    name = parts[-1]
    if name.endswith(src) or name.endswith(res) or any(fnmatch.fnmatch(name, g) for g in cfg.get("resource_globs", [])):
        return rel
    return None


def unclaimed_new(m: Map, slices, paths: set[str]) -> list[str]:
    """Source or resource files among `paths` that no slice lists and unmapped_notes does not explain."""
    owners = claimed_paths(slices)
    notes = m.config.get("unmapped_notes", {})
    keys = {inventory_key(m, p) for p in paths}
    return sorted(k for k in keys if k and (m.root / k).exists() and k not in owners and k not in notes)


def git_paths(m: Map, *args: str) -> set[str]:
    return {x for x in run_git(m.root, *args, check=False).split("\0") if x}


def worktree_changes(m: Map) -> set[str]:
    """Uncommitted paths: modified, staged, deleted and untracked; a rename counts as both sides."""
    out = run_git(m.root, "status", "--porcelain", "-z", "--no-renames", "-uall", check=False)
    return {entry[3:] for entry in out.split("\0") if len(entry) > 3}


def outside_map(m: Map, paths: set[str]) -> set[str]:
    map_rel = str(m.dir.relative_to(m.root)) + "/"
    return {x for x in paths if not x.startswith((".claude/", map_rel))}


def changed_in_session(m: Map, session_id: str) -> set[str]:
    """Commits since the session's baseline plus uncommitted changes. The baseline is the Context OS kit's
    .claude/.state/session-<id>.baseline (line head=<sha>); without one, only uncommitted changes count."""
    changed = worktree_changes(m)
    base = m.root / ".claude" / ".state" / f"session-{session_id}.baseline"
    head = ""
    if session_id and base.is_file():
        head = next((ln[5:].strip() for ln in base.read_text().splitlines() if ln.startswith("head=")), "")
    if head and subprocess.run(["git", "-C", str(m.root), "cat-file", "-e", f"{head}^{{commit}}"],
                               capture_output=True, timeout=60).returncode == 0:
        changed |= git_paths(m, "diff", "--name-only", "-z", "--no-renames", head, "HEAD")
    return outside_map(m, changed)


def stale_lines(stale: dict[str, list[tuple[str, str]]], limit: int = 4) -> list[str]:
    lines = []
    for fid, items in sorted(stale.items()):
        uniq = list(dict.fromkeys(f"{path} {why}" for path, why in items))
        more = f" (+{len(uniq) - limit} more)" if len(uniq) > limit else ""
        lines.append(f"- {fid}: " + "; ".join(uniq[:limit]) + more)
    return lines


def hook_edit(m: Map, rel: str) -> int:
    """After an Edit or Write: exit 1 with a message when the edit broke the map, else 0 and silent."""
    rel = os.path.normpath(rel) if rel else ""
    if not rel:
        return 0
    script = m.config.get("script", "scripts/codemap.py")
    features_rel = str(m.features_dir.relative_to(m.root)) + "/"
    slices, all_ids, node_index = load_all(m)
    if rel.startswith(features_rel) and rel.endswith(".json"):
        for p, sl in slices:
            if str(p.relative_to(m.root)) != rel:
                continue
            errors = [f for f in validate_slice(m, p, sl, all_ids, node_index, {}) if f.level == "error"]
            if errors:
                print(f"codemap: {rel} has {len(errors)} error(s):")
                for f in errors[:10]:
                    print(f"  {f.what}: {f.detail}")
                print(f"Fix them (errors in `derived` clear when refresh regenerates it), then run: "
                      f"python3 {script} refresh {p.stem}")
                return 1
        return 0
    cited = citations_by_path(slices).get(rel)
    if not cited:
        return 0
    cache: dict = {}
    broken = [(fid, label, ev) for fid, label, ev in cited
              if find_match(m.root, rel, ev.get("match", ""), ev.get("line"), cache) is None]
    if not broken:
        return 0
    ids = sorted({fid for fid, _, _ in broken})
    print(f"codemap: {rel} no longer contains {len(broken)} line(s) that the feature map cites:")
    for fid, label, ev in broken[:8]:
        print(f"  {fid}: {label}: {ev.get('match', '')[:80]!r}")
    if len(broken) > 8:
        print(f"  ... {len(broken) - 8} more")
    if all(label.startswith("derived ") for _, label, _ in broken):
        print(f"Only the mechanical layer is affected. When the change is done, run: python3 {script} refresh {' '.join(ids)}")
    else:
        print(f"When the change is done, update those slices in {features_rel} (re-cite, change or remove the node, "
              f"edge or docs entry), then run: python3 {script} refresh {' '.join(ids)}")
    return 1


def hook_stop(m: Map, agent: str = "claude") -> int:
    """Stop hook (Claude Code, or Codex with agent="codex"): once per state, name the slices this session made stale."""
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    if data.get("stop_hook_active"):
        return 0
    sid = re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("session_id") or ""))
    changed = changed_in_session(m, sid)
    if not changed:
        return 0
    slices, _, _ = load_all(m)
    stale = stale_slices_for(m, slices, changed)
    new = unclaimed_new(m, slices, changed)
    if not stale and not new:
        return 0
    state_dir = m.root / ".claude" / ".state"
    state_dir.mkdir(parents=True, exist_ok=True)
    fingerprint = hashlib.sha1(json.dumps([sorted(stale.items()), new]).encode()).hexdigest()
    sentinel = state_dir / f"codemap-{sid or 'no-session'}.asked"
    if sentinel.is_file() and sentinel.read_text().strip() == fingerprint:
        return 0
    sentinel.write_text(fingerprint + "\n")
    script = m.config.get("script", "scripts/codemap.py")
    features_rel = str(m.features_dir.relative_to(m.root))
    lines = [f"Codemap upkeep (automatic): this session changed code that the feature map in {m.dir.relative_to(m.root)} describes."]
    lines += stale_lines(stale)
    if new:
        lines.append("- new files no slice claims: " + ", ".join(new[:10]) + (f" (+{len(new) - 10} more)" if len(new) > 10 else ""))
    lines.append(
        f"If the task is finished: for each slice listed, read what changed and update {features_rel}/<id>.json (fix, add, "
        "rename or remove nodes, edges and docs entries; every citation is a path, a line and a match copied from one "
        "line of that file); give each new file to a slice's `files` or explain it in `unmapped_notes` in "
        f"{m.dir.relative_to(m.root)}/config.json; then run `python3 {script} refresh"
        + (" " + " ".join(sorted(stale)) if stale else "") + "`. The map changes belong in the same commit as the "
        "code whenever that commit is made; this is not a request to commit. A slice whose content is still right "
        "only needs the refresh. If the task is still in progress, say so and stop; this "
        "reminder returns when the code changes again.")
    text = "\n".join(lines)
    if agent == "codex":  # Codex continues the turn with `reason` as the next prompt
        print(json.dumps({"decision": "block", "reason": text}))
    else:  # Claude Code: non-error feedback that continues the conversation
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": text}}))
    return 0


def hook_precommit(m: Map) -> int:
    """git pre-commit, warning only: name the slices the staged changes made stale. Never blocks a commit."""
    staged = outside_map(m, git_paths(m, "diff", "--cached", "--name-only", "-z", "--no-renames"))
    if not staged:
        return 0
    slices, _, _ = load_all(m)
    stale = stale_slices_for(m, slices, staged)
    new = unclaimed_new(m, slices, staged)
    if stale or new:
        script = m.config.get("script", "scripts/codemap.py")
        msg = ["codemap: this commit changes code the feature map describes (a warning; the commit goes ahead)."]
        msg += stale_lines(stale)
        if new:
            msg.append("- new files no slice claims: " + ", ".join(new[:10]))
        msg.append(f"Update those slices, then run: python3 {script} refresh" + ("" if not stale else " " + " ".join(sorted(stale))))
        print("\n".join(msg), file=sys.stderr)
    return 0


def cmd_hook(m: Map, args) -> int:
    """Only `edit` on a broken map returns non-zero; nothing here may fail a session or a commit."""
    try:
        if args.event == "edit":
            return hook_edit(m, args.path or os.environ.get("FILE", ""))
        if args.event == "stop":
            return hook_stop(m, args.agent)
        return hook_precommit(m)
    except SystemExit as exc:  # a slice with invalid JSON
        if args.event == "edit":
            print(f"codemap: {exc}")
            return 1
        print(f"codemap hook {args.event}: {exc}", file=sys.stderr)
        return 0
    except Exception as exc:
        print(f"codemap hook {args.event} skipped: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 0


def cmd_refresh(m: Map, args) -> int:
    """derive, stamp and index in one step. With no ids: every slice whose files or citations no longer match."""
    slices, all_ids, _ = load_all(m)
    ids = list(args.ids or [])
    unknown = [i for i in ids if i not in all_ids]
    if unknown:
        print("no slice named " + ", ".join(unknown))
        return 1
    if not ids:
        paths = {f.get("path", "") for _, sl in slices for f in sl.get("files", [])} | set(citations_by_path(slices))
        ids = sorted(stale_slices_for(m, slices, paths))
        if not ids:
            print("every slice matches the code; nothing to stamp")
            return cmd_index(m, None)
        print("refreshing " + " ".join(ids))
    cmd_derive(m, argparse.Namespace(ids=ids))
    rc = cmd_stamp(m, argparse.Namespace(ids=ids))
    cmd_index(m, None)
    return rc


# ---------------------------------------------------------------- generated documents

def md_escape(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def cmd_index(m: Map, _args) -> int:
    slices, _, _ = load_all(m)
    inv = Inventory(m)
    head = head_revision(m.root)
    revs = sorted({str(sl.get("revision", "?")) for _, sl in slices})
    script = m.config.get("script", "scripts/codemap.py")
    lines = [
        "# Feature index",
        "",
        f"Generated by `python3 {script} index` from `features/*.json` at {head}; do not edit by hand. "
        f"Slices were verified at {', '.join(revs)}.",
        "",
        "Use: find the feature below, open only its slice, confirm the cited lines in the live code, then edit. "
        f"`python3 {script} find <words>` ranks features, `owner <path>` names a file's feature, "
        "`refs <Symbol>` lists live references, and `check` reports stale citations.",
        "",
        "| Feature | Also called | What it is | Start at |",
        "|---|---|---|---|",
    ]
    for p, sl in sorted(slices, key=lambda x: str(x[1].get("id", ""))):
        if sl.get("index") is False:
            continue
        node_by_id = {n.get("id"): n for n in all_nodes(sl)}
        starts = []
        for nid in sl.get("entry_points", [])[:2]:
            n = node_by_id.get(nid)
            if n and n.get("path"):
                starts.append(f"`{os.path.basename(n['path'])}`")
        aliases = ", ".join(sl.get("aliases", [])[:8])
        lines.append(f"| [{sl.get('id')}](features/{p.name}) | {md_escape(aliases)} | "
                     f"{md_escape(sl.get('purpose', ''))} | {' '.join(dict.fromkeys(starts))} |")
    rows = unmapped_rows(m, inv, slices)
    drift = [(str(sl.get("id")), d) for _, sl in slices for d in sl.get("docs", [])
             if d.get("status") in ("CONTRADICTED", "STALE")]
    lines += ["", f"Not mapped to a feature: {len(rows)} files, see [UNMAPPED.md](UNMAPPED.md). "
              f"Documents that disagree with the code: {len(drift)} claims, see [DRIFT.md](DRIFT.md).", ""]
    (m.dir / "INDEX.md").write_text("\n".join(lines))

    up = "../" * len(m.dir.relative_to(m.root).parts)
    d_lines = [
        "# Documentation drift",
        "",
        f"Generated by `python3 {script} index` from the `docs` entries of each slice at {head}. "
        "Code is the evidence for current behavior, tests and builds for verified behavior, and these "
        "documents for intended design. A row means the two sides disagree; it does not say which one "
        "should change. Canonical documents are not rewritten to hide a row.",
        "",
        "| Status | Document | Claim | What the code shows | Feature |",
        "|---|---|---|---|---|",
    ]
    order = {"CONTRADICTED": 0, "STALE": 1}
    for fid, d in sorted(drift, key=lambda x: (order[x[1]["status"]], x[1].get("path", ""))):
        ev = d.get("evidence") or {}
        code = f"`{ev.get('path')}:{ev.get('line', '')}`" if ev.get("path") else ""
        where = f"[{d.get('path')}]({up}{d.get('path')})" + (f", {md_escape(d.get('section', ''))}" if d.get("section") else "")
        d_lines.append(f"| {d['status']} | {where} | {md_escape(d.get('claim', ''))} | "
                       f"{md_escape(d.get('note', ''))} {code} | {fid} |")
    confirmed = sum(1 for _, sl in slices for d in sl.get("docs", []) if d.get("status") == "CONFIRMED")
    unverified = sum(1 for _, sl in slices for d in sl.get("docs", []) if d.get("status") == "UNVERIFIED")
    d_lines += ["", f"Also checked: {confirmed} claims confirmed by the code, {unverified} not checkable from code.", ""]
    (m.dir / "DRIFT.md").write_text("\n".join(d_lines))

    u_lines = [
        "# Unmapped and possibly orphaned files",
        "",
        f"Generated by `python3 {script} index` at {head}. Source files no slice claims. `Inbound` counts other "
        "files that mention one of the file's top-level types (comments and strings excluded); zero is a lead, "
        "not proof. The finding records what was checked: target membership, conditional compilation, SwiftUI "
        "navigation, runtime registration and resources. Nothing listed here has been deleted.",
        "",
        "| File | Target | Lines | Inbound | Markers | Finding |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        u_lines.append(f"| `{r['path']}` | {', '.join(r['targets']) or 'none'} | {r['lines'] or '-'} | "
                       f"{r['inbound_files'] if r['kind'] == 'source' else '-'} | {md_escape(', '.join(r['markers']))} | "
                       f"{md_escape(r['note'] or 'not yet investigated')} |")
    orphans = unreachable_types(inv)
    notes = m.config.get("orphan_notes", {})
    u_lines += [
        "",
        "## Types no chain of references reaches from the app entry point",
        "",
        f"From `python3 {script} orphans`: starting at `@main` (and App Intents), follow every type named inside a "
        "reachable type's body; extensions of framework types count as reachable. Previews and tests do not make a "
        "type reachable. A mention is not a use, so this list is a floor: everything in it is unreferenced by "
        "reachable code, and some reachable-looking code may still be dead.",
        "",
        "| Type | Declared at | Mentioned only by | Finding |",
        "|---|---|---|---|",
    ]
    for o in orphans:
        u_lines.append(f"| `{o['type']}` | `{o['path']}:{o['line']}` | {', '.join(o['mentioned_by']) or '-'} | "
                       f"{md_escape(notes.get(o['type'], ''))} |")
    u_lines.append("")
    (m.dir / "UNMAPPED.md").write_text("\n".join(u_lines))
    print(f"wrote INDEX.md ({len(slices)} slices), DRIFT.md ({len(drift)} rows), UNMAPPED.md ({len(rows)} files)")
    return 0


# ---------------------------------------------------------------- entry point

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="codemap", description=(__doc__ or "codemap").split("\n\n")[0])
    ap.add_argument("--map", help="map directory relative to the repository root")
    ap.add_argument("--version", action="version", version=f"codemap {VERSION}")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("find")
    p.add_argument("words", nargs="+")
    p.add_argument("--limit", type=int, default=5)
    p = sub.add_parser("owner")
    p.add_argument("path")
    p = sub.add_parser("refs")
    p.add_argument("symbol")
    p = sub.add_parser("check")
    p.add_argument("ids", nargs="*")
    p.add_argument("--json", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    p = sub.add_parser("affected")
    p.add_argument("--since")
    p = sub.add_parser("derive")
    p.add_argument("ids", nargs="*")
    p = sub.add_parser("review")
    p.add_argument("ids", nargs="*")
    p = sub.add_parser("orphans")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("refresh")
    p.add_argument("ids", nargs="*")
    p = sub.add_parser("hook")
    p.add_argument("event", choices=["edit", "stop", "pre-commit"])
    p.add_argument("path", nargs="?")
    p.add_argument("--agent", choices=["claude", "codex"], default="claude")
    p = sub.add_parser("stamp")
    p.add_argument("ids", nargs="+")
    sub.add_parser("index")
    p = sub.add_parser("unmapped")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("inventory")
    p.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if args.cmd == "hook":
        try:
            m = open_map(args.map)
        except (Exception, SystemExit):  # no map in this checkout: nothing to keep up
            return 0
    else:
        m = open_map(args.map)
    handler = {
        "find": cmd_find, "owner": cmd_owner, "refs": cmd_refs, "check": cmd_check,
        "affected": cmd_affected, "derive": cmd_derive, "review": cmd_review, "orphans": cmd_orphans,
        "stamp": cmd_stamp, "index": cmd_index, "refresh": cmd_refresh, "hook": cmd_hook,
        "unmapped": cmd_unmapped, "inventory": cmd_inventory,
    }[args.cmd]
    return handler(m, args)


if __name__ == "__main__":
    sys.exit(main())
