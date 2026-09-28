#!/usr/bin/env python3
"""Build a navigable map of the OpenIntelligence repository, with an accuracy status for every
document, derived from the repository itself. Read-only: it runs git and reads files, and it refuses
to write inside the repository.

    python3 .claude/skills/repo-map/scripts/build_map.py --out "${TMPDIR:-/tmp}/oi-repo-map/data.json"

Then `render.py` puts the result into the page. See ../SKILL.md.

Every status is computed from evidence the page shows next to it: references that no longer
resolve, code that changed after the document was last edited, a version in the header that lags
the shipped one, or a location or marker that says the file is a record of the past. Prose cannot be
checked, and a document with too few checkable references is reported as unchecked, not as fine.
"""

from __future__ import annotations

import collections
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import argparse

_ap = argparse.ArgumentParser(description="Survey the repository for the Repo Map page (read-only).")
_ap.add_argument("--root", default=None, help="repository root (default: the git top level of the working directory)")
_ap.add_argument("--out", required=True, help="where to write the survey JSON; must be outside the repository")
_args = _ap.parse_args()
_top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=_args.root or os.getcwd(),
                      capture_output=True, text=True).stdout.strip()
ROOT = Path(_args.root or _top).resolve()
OUT = Path(_args.out).resolve()
if OUT == ROOT or ROOT in OUT.parents:
    sys.exit(f"refusing to write {OUT}: output must be outside the repository ({ROOT})")
OUT.parent.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / "scripts"))
import verify_doc_claims as vdc  # noqa: E402  reuse the repo's own claim patterns and Swift helpers

vdc.ROOT = ROOT


def git(*args: str, timeout: int = 300) -> str:
    return subprocess.run(["gtimeout", str(timeout), "git", *args], cwd=ROOT,
                          capture_output=True, text=True).stdout


HEAD = git("rev-parse", "HEAD").strip()
# GitHub links need a commit GitHub has. An unpushed HEAD is surveyed, and linked at the newest
# commit it shares with origin.
_remote = git("remote", "get-url", "origin").strip()
_m = re.search(r"github\.com[:/]([^/]+/[^/.]+)", _remote)
REPO_SLUG = _m.group(1) if _m else "Gunnarguy/OpenIntelligence"
LINK_SHA = HEAD if git("branch", "-r", "--contains", HEAD).strip() else \
    (git("merge-base", HEAD, "origin/main").strip() or HEAD)
TODAY = dt.date.today()
tracked = [p for p in git("ls-files").splitlines() if p]
tracked_set = set(tracked)
by_base: dict[str, list[str]] = collections.defaultdict(list)
for p in tracked:
    by_base[os.path.basename(p)].append(p)

# ---------------------------------------------------------------- history
hist: dict[str, list[tuple[str, str, str]]] = collections.defaultdict(list)  # path -> [(date, sha, subject)] newest first
cur = None
for line in git("log", "--format=@@%h|%ad|%s", "--date=short", "--name-only").splitlines():
    if line.startswith("@@"):
        h, d, s = line[2:].split("|", 2)
        cur = (d, h, s)
    elif line.strip() and cur:
        hist[line.strip()].append(cur)
ever_paths = set(hist)
ever_bases = {os.path.basename(p) for p in ever_paths}

# Type names declared at any tagged release, to tell "a type this repo removed" from "an Apple type".
ever_types: set[str] = set()
for tag in git("tag").split() + ["HEAD"]:
    out = git("grep", "-h", "-o", "-E", r"(class|struct|enum|actor|protocol) [A-Z][A-Za-z0-9_]+", tag, "--", "*.swift")
    ever_types.update(m.split()[1] for m in out.splitlines() if " " in m)

# A name the repo once declared and no longer does may now come from Apple's SDK (a shim retired when
# the SDK shipped the real type) or from a package dependency. Those are not removals.
def external_types(names: set[str]) -> set[str]:
    if not names:
        return set()
    dev = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    roots = [f"{dev}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks",
             f"{dev}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks",
             str(ROOT / ".build/checkouts")]
    files = []
    for r in roots:
        if os.path.isdir(r):
            files += [str(q) for q in Path(r).rglob("*.swiftinterface") if "arm64" in q.name] + \
                     [str(q) for q in Path(r).rglob("*.swift") if "/.build/checkouts/" in str(q)]
    pat = r"(class|struct|enum|actor|protocol|typealias) (" + "|".join(sorted(names)) + r")\b"
    found = set()
    for i in range(0, len(files), 400):
        out = subprocess.run(["grep", "-h", "-o", "-E", pat, *files[i:i + 400]], capture_output=True, text=True).stdout
        found.update(m.split()[1] for m in out.splitlines() if " " in m)
    return found


shipped = json.loads((ROOT / "Docs/SHIPPED_VERSION.json").read_text())
SHIPPED_TXT = json.dumps(shipped)
live_versions = sorted({v for v in re.findall(r'"(\d+\.\d+(?:\.\d+)?)"', SHIPPED_TXT)},
                       key=lambda v: [int(x) for x in v.split(".")])
LIVE = live_versions[-1] if live_versions else "0"


def vkey(v: str) -> list[int]:
    return [int(x) for x in re.findall(r"\d+", v)][:3]


# ---------------------------------------------------------------- engine target membership
pkg = (ROOT / "Package.swift").read_text()
seg = pkg[pkg.index('name: "OpenIntelligenceEngine",\n            dependencies'):]
ENGINE_EX = re.findall(r'"([^"]+)"', seg[seg.index("exclude:"):seg.index("sources:")])
ENGINE_SRC = re.findall(r'"([^"]+)"', seg[seg.index("sources:"):seg.index("resources:")])


def in_engine(rel: str) -> bool:
    if not rel.startswith("OpenIntelligence/"):
        return False
    r = rel[len("OpenIntelligence/"):]
    inside = any(r == s or r.startswith(s + "/") for s in ENGINE_SRC)
    return inside and not any(r == e or r.startswith(e + "/") for e in ENGINE_EX)


# ---------------------------------------------------------------- Swift model
SW = {p: s for p, s in vdc.swift_sources().items() if p in tracked_set}
TOP = re.compile(
    r"^(?:@[\w.]+(?:\([^)\n]*\))?\s+)*(?:(?:public|internal|private|fileprivate|open|final|nonisolated|indirect|package)\s+)*"
    r"(class|struct|enum|actor|protocol)\s+([A-Z]\w*)([^{\n]*)", re.M)
ANYDECL = re.compile(r"\b(?:class|struct|enum|actor|protocol|typealias)\s+([A-Z]\w*)")
IDENT = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")
SYSTEM_ENTRY = re.compile(r"\b(AppIntent|AppShortcutsProvider|AppEntity|AppEnum|EntityQuery|EntityStringQuery|"
                          r"Widget|WidgetBundle|ControlWidget|PreviewProvider|XCTestCase|ActivityAttributes|"
                          r"TransientAppEntity|AppIntentsPackage|UIApplicationDelegate|NSApplicationDelegate)\b")


def strip_comments(s: str) -> str:
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    return re.sub(r"//[^\n]*", " ", s)


def swift_kind(p: str) -> str:
    if "/swift-transformers/" in p:
        return "vendored"
    if p.startswith("OpenIntelligenceTests/"):
        return "test"
    if p.startswith("OpenIntelligenceLiveActivities/"):
        return "widget"
    return "app"


def file_blurb(src: str) -> str:
    """First meaningful comment: a /// doc comment on the first top-level type, else a header comment."""
    m = TOP.search(src)
    if m:
        before = src[: m.start()].rstrip().splitlines()
        doc = []
        for ln in reversed(before):
            t = ln.strip()
            if t.startswith("///"):
                doc.append(t.lstrip("/").strip())
            elif t.startswith("@") and not doc:
                continue
            else:
                break
        if doc:
            return " ".join(reversed(doc))[:220]
    for ln in src.splitlines()[:40]:
        t = ln.strip()
        if not t.startswith("//"):
            if t and not t.startswith("import") and not t.startswith("#"):
                break
            continue
        body = t.lstrip("/").strip()
        if not body or body.endswith(".swift") or "Created by" in body or "Copyright" in body \
                or body in ("OpenIntelligence", "OpenIntelligenceTests") or body.startswith("MARK"):
            continue
        return body[:220]
    return ""


TOPCHUNK = re.compile(r"^(?:@[\w.]+(?:\([^)\n]*\))?\s+)*((?:(?:public|internal|private|fileprivate|open|final|nonisolated|package)\s+)*)"
                      r"(extension|class|struct|enum|actor|protocol)\b([^{\n]*)", re.M)
MEMBER = re.compile(r"\b(?:func|var|let|case)\s+([a-zA-Z_]\w{3,})")
COMMON = {"body", "init", "description", "hash", "encode", "decode", "id", "value", "title", "name", "content"}


def extension_members(clean: str, own: set[str]) -> set[str]:
    """Member names declared in the file's non-private top-level extensions of types declared elsewhere.
    An extension of the file's own type (a delegate conformance, a factory) does not make the file
    used by anyone else, so it is skipped."""
    marks = list(TOPCHUNK.finditer(clean))
    names = set()
    for i, m in enumerate(marks):
        if m.group(2) != "extension" or re.search(r"\b(private|fileprivate)\b", m.group(1)):
            continue
        target = re.match(r"\s*([A-Za-z_][\w.]*)", m.group(3))
        if not target or target.group(1).split(".")[0] in own:
            continue
        end = marks[i + 1].start() if i + 1 < len(marks) else len(clean)
        names.update(n for n in MEMBER.findall(clean[m.end():end]) if n not in COMMON and len(n) >= 6)
    return names


all_ids: dict[str, set[str]] = {}
idents: dict[str, set[str]] = {}
swift_info: dict[str, dict] = {}
declared_now: set[str] = set()
for p, src in SW.items():
    clean = strip_comments(src)
    idents[p] = set(IDENT.findall(clean))
    all_ids[p] = set(re.findall(r"\b[a-zA-Z_]\w*\b", clean))
    declared_now.update(ANYDECL.findall(clean))
    tops = [(m.group(2), m.group(1), m.group(3)) for m in TOP.finditer(clean)]
    swift_info[p] = {
        "kind": swift_kind(p),
        "types": [t[0] for t in tops],
        "decl": {t[0]: t[1] for t in tops},
        "entry_types": {t[0] for t in tops if SYSTEM_ENTRY.search(t[2])},
        "system_entry": bool(re.search(r"^\s*@main\b", clean, re.M)) or any(SYSTEM_ENTRY.search(t[2]) for t in tops),
        "blurb": file_blurb(src),
        "ext_members": extension_members(clean, {t[0] for t in tops}),
    }

EXTERNAL = external_types(ever_types - declared_now)
CODE_NAMES = set().union(*idents.values())
# A type the code still names (from a package, say) is not removed, whoever declares it.
REMOVED_TYPES = ever_types - declared_now - EXTERNAL - CODE_NAMES

# who references each file's top-level types
ident_files: dict[str, set[str]] = collections.defaultdict(set)
for p, ids in idents.items():
    for i in ids:
        ident_files[i].add(p)
for p, info in swift_info.items():
    refs_app, refs_test = set(), set()
    for t in info["types"]:
        for q in ident_files.get(t, ()):
            if q == p:
                continue
            (refs_test if swift_kind(q) == "test" else refs_app).add(q)
    for name in info["ext_members"]:
        for q, ids in all_ids.items():
            if q != p and name in ids:
                (refs_test if swift_kind(q) == "test" else refs_app).add(q)
    own_clean = strip_comments(SW[p])
    unused_types = [t for t in info["types"]
                    if t not in info["entry_types"]
                    and not any(q != p and t in idents[q] for q in idents)
                    and len(re.findall(r"\b" + re.escape(t) + r"\b", own_clean)) <= 1]
    info["unused_types"] = unused_types if (refs_app or refs_test) else []
    info["used_by"] = sorted(refs_app)
    info["tested_by"] = sorted(refs_test)
    if info["kind"] in ("app", "widget") and info["types"] and not info["system_entry"]:
        info["use"] = "orphan" if not refs_app and not refs_test else ("test-only" if not refs_app else "used")
    else:
        info["use"] = "n/a"

# ---------------------------------------------------------------- areas and features from ARCHITECTURE.md
arch = (ROOT / "Docs/ai/ARCHITECTURE.md").read_text()


def table_rows(text: str, header_start: str) -> list[list[str]]:
    i = text.index(header_start)
    rows = []
    for ln in text[i:].splitlines()[2:]:
        if not ln.startswith("|"):
            break
        rows.append([c.strip() for c in ln.strip().strip("|").split(" | ")])
    return rows


AREAS = []
for cells in table_rows(arch, "| Area | Source | Owning document |"):
    area, source, owner = cells[0], cells[1], cells[-1]
    paths = [x.rstrip("/") for x in re.findall(r"`([^`]+/)`", source)]
    AREAS.append({"name": area, "paths": paths, "owner": owner.replace("`", "")})
FEATURES = []
for cells in table_rows(arch, "| Owner says | Entry file(s) | Key symbol(s) |"):
    say, entry, syms = cells[0], cells[1], cells[-1]
    files = []
    for f in re.findall(r"`([^`]+\.swift)`", entry + " " + syms):
        cand = f if f.startswith("OpenIntelligence") else "OpenIntelligence/" + f
        if cand in tracked_set:
            files.append(cand)
        elif os.path.basename(f) in by_base:
            files.extend(by_base[os.path.basename(f)])
    FEATURES.append({"name": say, "files": sorted(set(files)),
                     "symbols": sorted(set(re.findall(r"`([A-Za-z_][\w.]*(?:\([^`]*\))?)`", syms)))[:14],
                     "source": "Docs/ai/ARCHITECTURE.md, \"If the owner says...\""})


def area_of(p: str) -> str:
    best, blen = "", 0
    for a in AREAS:
        for ap in a["paths"]:
            if (p == ap or p.startswith(ap + "/")) and len(ap) > blen:
                best, blen = a["name"], len(ap)
    return best


# ---------------------------------------------------------------- documents
TEST_DATA = ("Docs/TestDocuments/", "Benchmarks/Fixtures/", "Benchmarks/ResearchFixtures/")
HISTORY_DIRS = ("Docs/Archive/", "Docs/AuditArtifacts/", "Docs/AUDIT/", ".agent/", "Xrays/")
AGENT_DIRS = (".claude/", ".agents/", ".codex/", "Docs/AgentPlaybooks/", "Docs/RepoOS/", "Docs/ai/")
AGENT_ROOT = {"CLAUDE.md", "AGENTS.md", "GEMINI.md", "HANDOFF.md", ".geminirules"}
PRODUCT = {"README.md", "CHANGELOG.md", "WHATS_NEW.md", "PRIVACY.md", "HOW_IT_WORKS.md", "LICENSE",
           "THIRD_PARTY_NOTICES.md", "Docs/RELEASE_NOTES.md", "Docs/USER_CHANGELOG.md", "Docs/ROADMAP.md",
           "Docs/DEMO.md", "Docs/LIMITATIONS.md", "Docs/HOW_IT_WORKS.md", "Docs/README.md",
           "Docs/RELEASE_NOTES_4.8_DRAFT.md", "Docs/STUDY_GUIDE.md"}
HIST_MARK = re.compile(
    r"(?i)(\bthis (?:document|doc|file|page|report|audit|plan|ledger|guide) (?:is|was) (?:now |kept as |retained as )?(?:a )?"
    r"(?:historical|superseded|archived|deprecated|obsolete|frozen|record|snapshot)"
    r"|\bsuperseded by\b|\bhistorical record\b|\bkept for history\b|\bno longer (?:maintained|current|accurate|used)\b"
    r"|^\W*status\W*:\W*(?:historical|superseded|archived|deprecated|obsolete|frozen)\b)", re.M)
HEADER_VERSION = re.compile(r"(?i)\b(?:version|release|shipped|live|current|updated|as of|for|v)\W{0,3}v?(\d\.\d{1,2})(?:\.\d+)?\b")
BARE_SWIFT = re.compile(r"(?<![\w/.+-])([A-Z][A-Za-z0-9_+]*\.swift)\b")  # "+" is part of names like RAGService+Streaming.swift
BARE_DOC = re.compile(r"(?<![\w/.-])([A-Za-z0-9_.-]+\.md)\b")
BARE_TYPE = re.compile(r"`([A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+)`")
# A missing name in a sentence that says it is gone is history, not a dead link: "replacing legacy
# pure-Swift `BertTokenizer`", "(that document no longer exists; noted 2026-08-27)". The context is
# the table cell for a table row, otherwise the sentence within its paragraph. A paragraph was too
# wide: an unrelated "Replaced" three bullets away excused an example file that never existed.
HIST_CONTEXT = re.compile(
    r"(?i)\b(legacy|replac(?:ed|ing|ement)|removed|deleted|retired|dropped|superseded|deprecated|formerly|"
    r"previously|renamed|no longer (?:exists?|used|in)|never (?:created|built|existed|written|committed|implemented))\b")


def passages(lines: list[str], token: str) -> list[str]:
    out = []
    for i, ln in enumerate(lines):
        if token not in ln:
            continue
        if ln.lstrip().startswith("|"):
            out.extend(cell for cell in ln.split("|") if token in cell)
            continue
        a = i
        while a > 0 and lines[a - 1].strip():
            a -= 1
        b = i
        while b + 1 < len(lines) and lines[b + 1].strip():
            b += 1
        para = " ".join(x.strip() for x in lines[a:b + 1])
        out.extend(sent for sent in re.split(r"(?<=[.!?])\s+(?=[A-Z`*(\[-])", para) if token in sent)
    return out


SWIFTUI_MODIFIERS = {"init", "task", "onAppear", "onDisappear", "onChange", "onReceive", "sheet", "body", "refreshable",
                     "toolbar", "environment", "overlay", "background", "alert", "fullScreenCover", "navigationDestination"}
RELEASE_LOGS = {"CHANGELOG.md", "Docs/RELEASE_NOTES.md", "Docs/USER_CHANGELOG.md", "WHATS_NEW.md",
                "OpenIntelligence/Resources/VersionHistory.md"}


def doc_category(p: str) -> str | None:
    if p.startswith(TEST_DATA) or p.startswith("Benchmarks/") and not p.endswith("README.md"):
        return None
    if "/swift-transformers/" in p:
        return None
    if p in RELEASE_LOGS:
        return "Release logs"
    if p.startswith("fastlane/") or p.startswith("InAppEvents/") or p.startswith("Docs/Release/"):
        return "Store and release copy"
    if p.startswith("Docs/Archive/"):
        return "Archive"
    if p.startswith(HISTORY_DIRS) or re.search(r"(?i)audit", os.path.basename(p)) and p.startswith("Docs/"):
        return "Audits and snapshots"
    if p in AGENT_ROOT or p.startswith(AGENT_DIRS) or p.startswith(".github/"):
        return "Agent instructions"
    if p in PRODUCT:
        return "Product and release"
    if p.startswith("Docs/Audio/"):
        return "Study guides and audio"
    if p.startswith("BenchmarkRuns/") or p == "Benchmarks/README.md":
        return "Benchmarks"
    if p.startswith("Docs/") or p.endswith(".md"):
        return "Architecture and subsystems"
    return None


docs_paths = [p for p in tracked if p.endswith((".md", ".txt")) and doc_category(p)]

# inbound references: which tracked text files name each document
TEXT_EXT = (".md", ".txt", ".py", ".sh", ".json", ".csv", ".yml", ".yaml", ".swift", ".rb", ".html")
mentions: dict[str, set[str]] = collections.defaultdict(set)
NAME_TOKEN = re.compile(r"[A-Za-z0-9_./-]+\.(?:md|txt)\b")
for p in tracked:
    if not p.endswith(TEXT_EXT):
        continue
    try:
        text = (ROOT / p).read_text(errors="ignore")
    except OSError:
        continue
    for tok in set(NAME_TOKEN.findall(text)):
        mentions[tok.lstrip("./")].add(p)
        mentions["@base:" + os.path.basename(tok)].add(p)


def inbound(p: str) -> list[str]:
    who = set(mentions.get(p, set()))
    base = os.path.basename(p)
    if len(by_base.get(base, [])) == 1 and base not in ("README.md", "SKILL.md", "STATE.md"):
        who |= mentions.get("@base:" + base, set())
    who.discard(p)
    return sorted(who)


swift_len = {p: s.count("\n") + 1 for p, s in SW.items()}


def resolve_swift(name: str) -> list[str]:
    return [p for p in by_base.get(name, []) if p.endswith(".swift")]


def commits_after(path: str, date: str) -> list[tuple[str, str, str]]:
    return [c for c in hist.get(path, []) if c[0] > date]


docs = []
for p in docs_paths:
    text = (ROOT / p).read_text(errors="ignore")
    lines = text.splitlines()
    title = next((ln.lstrip("#").strip() for ln in lines if ln.startswith("# ")), "") or \
        next((ln.strip() for ln in lines if ln.strip()), "")[:120]
    summary = ""
    seen_title = False
    for ln in lines:
        t = ln.strip()
        if t.startswith("# "):
            seen_title = True
            continue
        if not t or t.startswith(("<!--", "![", "[!", "|", "```", "---", "#", ">", "<")) or t.startswith("`[evidence"):
            continue
        if seen_title or not lines[0].startswith("# "):
            summary = re.sub(r"[*_`]", "", t)[:240]
            break

    ok, broken = [], []
    cited_swift: set[str] = set()
    line_starts = [0]
    for ln in lines:
        line_starts.append(line_starts[-1] + len(ln) + 1)

    def ignored(pos: int) -> bool:
        import bisect
        i = bisect.bisect_right(line_starts, pos) - 1
        return 0 <= i < len(lines) and "verify-doc-claims: ignore" in lines[i]

    def note(kind: str, ref: str, good: bool, why: str = "") -> None:
        (ok if good else broken).append({"kind": kind, "ref": ref, "why": why})

    for m in vdc.PATH_CLAIM.finditer(text):
        rel = m.group(1).rstrip(".,;:")
        if ignored(m.start()) or rel.startswith(vdc.PATH_EXEMPT_PREFIXES) or vdc.is_machine_local(rel):
            continue
        tail = text[m.end(): m.end() + 1]
        if tail in "<{*" or rel.endswith("-") or "*" in rel:
            continue
        # "`.agents/rules/01` wins": shorthand for a real file that starts with it
        exists = (ROOT / rel).exists() or any(t.startswith(rel) and t[len(rel):len(rel) + 1] in "-_." for t in tracked)
        # `OpenIntelligenceTests/SomeTests` is xcodebuild's -only-testing:Target/Class[/method] form, not a path
        seg = rel.split("/")
        if not exists and seg[0] == "OpenIntelligenceTests" and len(seg) in (2, 3) and "." not in seg[1] \
                and any(seg[1] in swift_info[q]["types"] for q in swift_info if q.startswith("OpenIntelligenceTests/")):
            exists = True
        why = "" if exists else ("removed or renamed" if rel in ever_paths else "never existed at this path")
        note("path", rel, exists, why)
        if exists and rel.endswith(".swift"):
            cited_swift.add(rel)
    for name in {m.group(1) for m in BARE_SWIFT.finditer(text) if not ignored(m.start())}:
        hits = resolve_swift(name)
        if hits:
            ok.append({"kind": "file", "ref": name, "why": ""})
            cited_swift.update(hits)
        else:
            note("file", name, False, "removed or renamed" if name in ever_bases else "no such file in history")
    for m in vdc.ANCHOR_CLAIM.finditer(text):
        if ignored(m.start()):
            continue
        fname, n = m.group(1), int(m.group(2))
        hits = resolve_swift(fname)
        if hits:
            total = swift_len.get(hits[0], 0)
            note("anchor", f"{fname}:{n}", n <= total, f"file has {total} lines")
    for m in vdc.SYMBOL_CLAIM.finditer(text):
        tname, member = m.group(1), m.group(2)
        if member in vdc.FILE_EXTENSIONS or member in SWIFTUI_MODIFIERS or ignored(m.start()):
            continue
        owners = vdc.declaring_files(tname)
        if member in ("allCases", "rawValue") and owners and any(
                re.search(r"\benum\s+" + tname + r"\s*:[^{]*\b(CaseIterable|String|Int)\b", vdc.swift_sources()[q]) for q in owners):
            ok.append({"kind": "symbol", "ref": f"{tname}.{member}", "why": ""})
            continue
        if not owners:
            if tname in REMOVED_TYPES:
                note("symbol", f"{tname}.{member}", False, f"type {tname} no longer exists")
            continue
        declared = re.compile(r"(?:\bfunc\s+|\bvar\s+|\blet\s+|\bcase\s+(?:[^\n]*[,\s])?\.?|\btypealias\s+"
                              r"|\b(?:class|struct|enum|protocol|actor)\s+)" + re.escape(member) + r"\b")
        good = any(declared.search(vdc.swift_sources()[q]) for q in owners)
        note("symbol", f"{tname}.{member}", good, "" if good else f"no member {member} on {tname}")
    for tname in {m.group(1) for m in BARE_TYPE.finditer(text) if not ignored(m.start())}:
        if tname in declared_now or tname in EXTERNAL:
            ok.append({"kind": "type", "ref": tname, "why": ""})
        elif tname in REMOVED_TYPES:
            note("type", tname, False, "type removed from the code")
    for name in set(BARE_DOC.findall(text)):
        if name in by_base or name.startswith(("Foo", "X.")):
            continue
        if name in ever_bases:
            note("doc", name, False, "document removed or renamed")

    # a reference named only in passages that say it is gone is recorded as history, not as dead
    historical = []
    for b in list(broken):
        token = b["ref"].split(":")[0] if b["kind"] == "anchor" else b["ref"]
        ps = passages(lines, token)
        if ps and all(HIST_CONTEXT.search(x) for x in ps):
            broken.remove(b)
            historical.append(b)

    # de-duplicate reference lists by (kind, ref)
    def dedupe(xs):
        seen, out = set(), []
        for x in xs:
            k = (x["kind"], x["ref"])
            if k not in seen:
                seen.add(k)
                out.append(x)
        return out
    ok, broken = dedupe(ok), dedupe(broken)

    h = hist.get(p, [])
    last = h[0] if h else ("", "", "")
    since = {}
    for s in cited_swift:
        c = commits_after(s, last[0]) if last[0] else []
        if c:
            since[s] = len(c)
    head_text = "\n".join(lines[:14])
    hv = [v for v in HEADER_VERSION.findall(head_text) if 2 <= int(v.split(".")[0]) <= 6]
    header_version = max(hv, key=vkey) if hv else ""
    docs.append({
        "path": p, "category": doc_category(p), "title": title[:160], "summary": summary,
        "lines": len(lines), "last": {"date": last[0], "sha": last[1], "subject": last[2][:140]},
        "edits": len(h), "refs_ok": len(ok), "refs_broken": broken[:60], "n_broken": len(broken),
        "refs_historical": dedupe(historical)[:30],
        "cited_swift": len(cited_swift), "code_changed_since": since,
        "code_commits_since": sum(since.values()), "header_version": header_version,
        "hist_marker": bool(HIST_MARK.search("\n".join(lines[:15]))),
        "gate_checked": p in vdc.DOCS, "inbound": inbound(p),
    })

# ---------------------------------------------------------------- statuses


def status(d: dict) -> tuple[str, list[str]]:
    why = []
    n_ok, n_bad = d["refs_ok"], d["n_broken"]
    total = n_ok + n_bad
    cat = d["category"]
    if n_bad:
        why.append(f"{n_bad} of {total} references no longer resolve")
    if d["code_changed_since"]:
        why.append(f"{len(d['code_changed_since'])} of the {d['cited_swift']} Swift files it cites changed "
                   f"after its last edit ({d['code_commits_since']} commits)")
    hv = d["header_version"]
    if hv and vkey(hv) < vkey(LIVE)[:2] and cat not in ("Archive", "Audits and snapshots"):
        why.append(f"its header names {hv}; the live version is {LIVE}")
    if cat == "Archive":
        return "history", ["In Docs/Archive: a record of the past, not current truth"] + why
    if cat == "Release logs":
        return "history", ["An append-only release log: each entry describes the code as it was then"] + why
    if cat == "Audits and snapshots" or d["hist_marker"] and cat != "Agent instructions":
        lead = "An audit or snapshot: accurate for its date, not maintained" if cat == "Audits and snapshots" \
            else "Marks itself as historical or superseded"
        return "history", [lead] + why
    if d["gate_checked"] and n_bad == 0:
        return "verified", ["Checked on every run of scripts/verify_doc_claims.py, and passing"] + why
    if total >= 3 and n_bad >= max(3, 0.1 * total):
        return "outdated", why
    if n_bad:
        return "dead-links", why
    if total < 3:
        return "unchecked", [f"Only {total} checkable reference{'s' if total != 1 else ''}; the rest is prose"] + why
    if (len(d["code_changed_since"]) >= max(3, 0.5 * max(1, d["cited_swift"]))) or \
            (hv and vkey(hv) < vkey(LIVE)[:2]):
        return "behind", why
    return "current", [f"All {total} references resolve"] + why


doc_names = collections.defaultdict(list)
for d in docs:
    doc_names[os.path.basename(d["path"]).lower()].append(d["path"])
for d in docs:
    d["status"], d["why"] = status(d)
    base = os.path.basename(d["path"]).lower()
    d["same_name"] = [q for q in doc_names[base] if q != d["path"]] if base not in ("readme.md", "skill.md") else []

# ---------------------------------------------------------------- all files, for the map
files = []
for p in tracked:
    full = ROOT / p
    try:
        size = full.stat().st_size
    except OSError:
        size = 0
    n = 0
    if p.endswith(TEXT_EXT + (".plist", ".xcscheme", ".pbxproj", ".storekit", ".entitlements", ".xcprivacy", ".patch", ".gitignore")):
        try:
            with full.open("rb") as fh:
                n = sum(1 for _ in fh)
        except OSError:
            pass
    h = hist.get(p, [])
    rec = {"p": p, "lines": n, "bytes": size, "last": h[0][0] if h else "", "sha": h[0][1] if h else "",
           "edits": len(h)}
    if p in swift_info:
        si = swift_info[p]
        rec.update({"k": si["kind"], "area": area_of(p), "blurb": si["blurb"], "types": si["types"][:8],
                    "use": si["use"], "used_by": si["used_by"][:12], "unused_types": si["unused_types"][:6], "n_used_by": len(si["used_by"]),
                    "tested_by": si["tested_by"][:6], "engine": in_engine(p)})
    files.append(rec)

# ---------------------------------------------------------------- loose files in the working folder, not in git
LOOSE_NOTES = {
    ".git.nosync": "Git's own data, kept out of iCloud on purpose. Leave it alone.",
    ".build": "SwiftPM build output; also holds the code index the LSP reads",
    "build": "Build output",
    ".device-smoke.nosync": "DerivedData from device smoke builds",
    ".attic.nosync": "Files moved aside earlier",
    ".swiftpm": "SwiftPM workspace state",
    ".env.appstore": "App Store credentials. Secret; must stay out of git.",
    "Package.resolved": "Package version pins (git ignores this file here)",
    "5.1 Screenshots": "Screenshots folder",
    "default.profraw": "Code-coverage profile left by a test run",
    ".gemini": "Gemini CLI state",
    ".claude": "",
}
loose = []
for entry in sorted(os.listdir(ROOT)):
    if entry in (".git", ".DS_Store") or git("ls-files", "--", entry).strip():
        continue
    full = ROOT / entry
    try:
        du = subprocess.run(["du", "-sk", str(full)], capture_output=True, text=True, timeout=120).stdout.split()[0]
        kb = int(du)
    except Exception:
        kb = 0
    mtime = dt.datetime.fromtimestamp(full.stat().st_mtime).date().isoformat()
    note = LOOSE_NOTES.get(entry, "")
    first = ""
    if full.is_file() and entry.endswith((".txt", ".md", ".log")):
        with full.open(errors="ignore") as fh:
            first = next((ln.strip() for ln in fh if ln.strip()), "")[:140]
        if not note and re.match(r"^(ℹ️|✅|⚠️|❌|🔍|Successfully |\[)", first):
            note = "Console output saved from a run of the app"
    loose.append({"name": entry, "kb": kb, "modified": mtime, "dir": full.is_dir(), "note": note, "first": first})

out = {
    "repo": REPO_SLUG, "head": HEAD, "link_sha": LINK_SHA, "generated": dt.datetime.now().isoformat(timespec="minutes"),
    "live_version": LIVE, "shipped": shipped, "areas": AREAS, "features": FEATURES,
    "docs": docs, "files": files, "loose": loose,
    "counts": {"tracked": len(tracked), "swift": len(SW), "docs": len(docs)},
}
OUT.write_text(json.dumps(out, indent=None, separators=(",", ":")))
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB): {len(tracked)} tracked files, {len(docs)} documents, {len(SW)} Swift files")
print("doc status:", collections.Counter(d["status"] for d in docs).most_common())
print("swift use:", collections.Counter(swift_info[p]["use"] for p in swift_info).most_common())
print("live version:", LIVE, "| ever-declared types:", len(ever_types), "| declared now:", len(declared_now))
