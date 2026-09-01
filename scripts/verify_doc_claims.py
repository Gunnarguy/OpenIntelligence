#!/usr/bin/env python3
"""Verify that documentation claims still match the source they describe.

Companion to `verify_capabilities.py`. That one checks the code behind a *public*
claim still exists. This one checks the claims documentation makes about the
*repository itself*: versions, enum cases, file paths, line anchors.

Why this exists. On 2026-09-01 a claim-by-claim re-read of two foundational
documents found four disagreements, every one of them mechanically checkable:

  - `Docs/RETRIEVAL_PIPELINE.md` asserted "iOS/macOS 4.9 is the shipped version"
    in its status block while its own title said v5.0. Both were wrong; iOS was
    5.0 and macOS 5.0.2.
  - `Docs/ai/ARCHITECTURE.md` listed six `RetrievalTraceCollector.Stage` cases.
    There are seven. `Docs/RETRIEVAL_PIPELINE.md` listed all seven, so the two
    documents disagreed with each other as well as with the code.
  - `BenchmarkRuns/LEDGER.md` and `Docs/RETRIEVAL_PIPELINE.md` cited benchmark
    directories that no longer existed on disk.
  - Stale `file.swift:NNN` anchors drift silently as code moves.

The enforcement layer already required that documentation be *touched* when
source changes. Nothing checked that it was *true*. Three weeks of drift is what
that gap costs, and it was only found because someone was asked to look.

**Doc-versus-doc agreement is a free consequence.** Two documents describing the
same enum are both checked against the same source, so they cannot disagree with
each other without at least one failing. There is deliberately no separate
cross-document comparison.

What this CANNOT do, stated plainly so nobody mistakes it for more:

  It cannot verify prose. "VNRecognizeTextRequest is the current OCR path" was
  false for a week and no parser will catch that. It needs a human reading the
  code, and pretending otherwise would be worse than not checking.

  It cannot verify that a symbol at a line number is the symbol claimed. It
  checks the file exists and is long enough, which catches deletion and heavy
  truncation but not a shifted anchor.

The one convention it asks of documents: **to have a list of enum cases checked,
name the enum in qualified form** -- `RetrievalTraceCollector.Stage`, not a bare
`RetrievalTraceCollector` -- somewhere in the paragraph before the list. Without
that anchor there is no way to know which of several same-named enums a list
refers to, and guessing produced a confident wrong failure the first time this
ran. An unqualified mention is simply not checked rather than checked badly.

Exit codes: 0 every checked claim holds, 1 at least one does not.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Documents whose claims are checked. Everything else is out of scope by design:
# a checker that scans every markdown file in a repository this size produces
# noise, and a noisy gate gets bypassed within a week.
DOCS = [
    "Docs/ai/ARCHITECTURE.md",
    "Docs/ai/PROJECT.md",
    "Docs/ai/RUNBOOK.md",
    "Docs/ai/STATE.md",
    "Docs/RETRIEVAL_PIPELINE.md",
    "Docs/INGESTION_PIPELINE.md",
    "Docs/PRIVACY_AND_ROUTING.md",
    "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md",
    "Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md",
    "HANDOFF.md",
    "README.md",
]

# Paths that are legitimately absent from a clean checkout. Benchmark runs are
# gitignored and were archived on 2026-09-01; citing one is correct, and
# `BenchmarkRuns/LEDGER.md` explains where to find it.
PATH_EXEMPT_PREFIXES = ("BenchmarkRuns/",)

# A line asserting a *current* shipped version. Deliberately narrow: historical
# statements ("v4.9 shipped on...") must not trip this, so the version and a
# present-tense shipped-state word have to appear together.
# Anchored on the phrase rather than on proximity. The first version was
# previously matched only if it sat within 60 characters of the phrase, so on a
# line reading "**iOS 5.0** ... and **macOS 5.0.2** ... are the shipped versions"
# only macOS was ever checked. Any line making a present-tense shipped claim now
# has *every* platform version on it verified.
SHIPPED_PHRASE = re.compile(
    r"\b(is the shipped version|are the shipped versions|is live|is currently live|is the current release)\b",
    re.IGNORECASE,
)
PLATFORM_VERSION = re.compile(r"\b(iOS|macOS)\b[^A-Za-z0-9]{0,12}v?(\d+\.\d+(?:\.\d+)?)\b", re.IGNORECASE)

# `Type.Enum` named in prose, followed by a run of backticked identifiers that
# claims to be its cases.
# The type may be named a sentence or two before the list it introduces, so the
# window spans a short paragraph and the colon is optional. Widened 2026-09-01
# after Docs/RETRIEVAL_PIPELINE.md's seven-stage list went unchecked because it
# names the type in the preceding sentence.
ENUM_CLAIM = re.compile(
    r"`(?P<type>[A-Z]\w+)\.(?P<enum>[A-Z]\w+)`.{0,400}?(?P<cases>(?:`\w+`(?:,| and |\s)+){3,}`\w+`)",
    re.DOTALL,
)
BACKTICKED = re.compile(r"`(\w+)`")

# Repository-relative paths mentioned in prose or links.
PATH_CLAIM = re.compile(
    r"[`(\[]((?:Docs|scripts|OpenIntelligence|OpenIntelligenceTests|Benchmarks|BenchmarkRuns|fastlane|ci_scripts|\.claude|\.codex|\.agents)/[A-Za-z0-9._/@+-]+)"
)

# `Something.swift:123`
ANCHOR_CLAIM = re.compile(r"`?([A-Za-z0-9_+]+\.swift):(\d+)`?")

failures: list[str] = []
checked = {"version": 0, "enum": 0, "path": 0, "anchor": 0}


def fail(doc: str, line_no: int, msg: str) -> None:
    failures.append(f"{doc}:{line_no}: {msg}")


def shipped_versions() -> dict[str, str]:
    p = ROOT / "Docs/SHIPPED_VERSION.json"
    if not p.exists():
        return {}
    data = json.loads(p.read_text())
    out: dict[str, str] = {}

    def walk(node, inherited=None):
        if isinstance(node, dict):
            for k, v in node.items():
                kl = k.lower()
                plat = "ios" if "ios" in kl else ("macos" if "mac" in kl else inherited)
                if isinstance(v, str) and re.fullmatch(r"\d+\.\d+(\.\d+)?", v) and plat:
                    out.setdefault(plat, v)
                else:
                    walk(v, plat)
        elif isinstance(node, list):
            for v in node:
                walk(v, inherited)

    walk(data)
    return out


def swift_enum_cases(enum_name: str, owner: str) -> set[str] | None:
    """Every `case` declared in `enum <name>` owned by `<owner>`, or None.

    The owner qualifier is load-bearing, not decoration. Two `enum Stage`
    declarations exist -- `IngestionStageLedger.Stage` and
    `RetrievalTraceCollector.Stage` -- and taking the first grep hit reported the
    ingestion cases as a contradiction of a retrieval document. When the owner
    cannot be resolved this returns None and the claim goes unchecked, because a
    confident wrong answer from a verifier is worse than no answer.
    """
    try:
        hits = subprocess.run(
            ["grep", "-rn", "--include=*.swift", f"enum {enum_name}", "OpenIntelligence"],
            cwd=ROOT, capture_output=True, text=True, timeout=60,
        ).stdout.strip().splitlines()
    except Exception:
        return None
    if not hits:
        return None
    if len(hits) > 1:
        owned = [h for h in hits if Path(h.split(":", 1)[0]).name == f"{owner}.swift"]
        if len(owned) != 1:
            return None
        hits = owned
    path, line_no = hits[0].split(":", 2)[0], int(hits[0].split(":", 2)[1])
    lines = (ROOT / path).read_text(errors="ignore").splitlines()
    cases: set[str] = set()
    depth = 0
    for raw in lines[line_no - 1:]:
        depth += raw.count("{") - raw.count("}")
        m = re.match(r"\s*case\s+([a-z]\w*)", raw)
        if m:
            cases.add(m.group(1))
        if depth <= 0 and cases:
            break
    return cases or None


def check(doc: str) -> None:
    p = ROOT / doc
    if not p.exists():
        failures.append(f"{doc}: listed for checking but does not exist")
        return
    text = p.read_text(errors="ignore")
    shipped = shipped_versions()

    for i, line in enumerate(text.splitlines(), 1):
        if "verify-doc-claims: ignore" in line:
            continue

        if not SHIPPED_PHRASE.search(line):
            continue
        for plat, ver in PLATFORM_VERSION.findall(line):
            checked["version"] += 1
            actual = shipped.get(plat.lower())
            if actual and ver != actual:
                fail(doc, i, f"claims {plat} {ver} is shipped; SHIPPED_VERSION.json says {actual}")

    for m in ENUM_CLAIM.finditer(text):
        enum, claimed = m.group("enum"), set(BACKTICKED.findall(m.group("cases")))
        actual = swift_enum_cases(enum, m.group("type"))
        if actual is None:
            continue
        checked["enum"] += 1
        line_no = text[: m.start()].count("\n") + 1
        missing, extra = actual - claimed, claimed - actual
        if missing:
            fail(doc, line_no, f"{enum}: doc omits case(s) {sorted(missing)} that exist in source")
        if extra:
            fail(doc, line_no, f"{enum}: doc lists case(s) {sorted(extra)} that do not exist in source")

    for m in PATH_CLAIM.finditer(text):
        rel = m.group(1).rstrip(".,;:")
        if rel.startswith(PATH_EXEMPT_PREFIXES):
            continue
        # A documented filename shape, not a file: the regex stops at the
        # placeholder, leaving a truncated stem that can never exist.
        tail = text[m.end(): m.end() + 1]
        if tail in "<{*" or rel.endswith("-") or "*" in rel:
            continue
        checked["path"] += 1
        if not (ROOT / rel).exists():
            fail(doc, text[: m.start()].count("\n") + 1, f"references missing path `{rel}`")

    for m in ANCHOR_CLAIM.finditer(text):
        fname, n = m.group(1), int(m.group(2))
        try:
            found = subprocess.run(
                ["find", "OpenIntelligence", "-name", fname], cwd=ROOT,
                capture_output=True, text=True, timeout=30,
            ).stdout.strip().splitlines()
        except Exception:
            continue
        if not found:
            continue
        checked["anchor"] += 1
        total = sum(1 for _ in (ROOT / found[0]).open(errors="ignore"))
        if n > total:
            fail(doc, text[: m.start()].count("\n") + 1,
                 f"anchor `{fname}:{n}` is past end of file ({total} lines)")


def main() -> int:
    for doc in DOCS:
        check(doc)

    total = sum(checked.values())
    print(f"verify_doc_claims: {total} claims checked "
          f"({checked['version']} version, {checked['enum']} enum, "
          f"{checked['path']} path, {checked['anchor']} anchor)")

    # Guard against the check silently ceasing to match. A rewording that stops
    # tripping the pattern reads as a pass, which is the failure mode this whole
    # script exists to prevent -- so each rule declares a floor it must clear.
    for rule, floor in (("version", 1), ("enum", 1), ("path", 20), ("anchor", 1)):
        if checked[rule] < floor:
            failures.append(
                f"verify_doc_claims: the '{rule}' rule matched {checked[rule]} claims, "
                f"below its floor of {floor}. Either the documents stopped making that "
                f"kind of claim, or the pattern stopped recognising it. Check the pattern "
                f"before lowering the floor."
            )

    if failures:
        print(f"\n❌ {len(failures)} documentation claim(s) no longer match source:\n")
        for f in failures:
            print(f"  {f}")
        print("\nFix the document, or the code, or append `verify-doc-claims: ignore` to the")
        print("line if the claim is deliberately historical.")
        return 1

    print("✅ every checked documentation claim matches source")
    return 0


if __name__ == "__main__":
    sys.exit(main())
