#!/usr/bin/env python3
"""Claims check: every figure in the App Store copy has a register entry, and every entry's evidence is still there.

Read-only. It reads the register (Docs/ai/CLAIMS.json), the five App Store copy files and the evidence files the
register names, and changes nothing. No network.
It exists because during 5.8 text shown to users described things the code did not do and gave figures nobody had
measured. The owner's rule: every claim is a claim about code or about a measurement. The register ties each figure
in the copy to the file that holds its evidence, and this script fails when a figure is in the copy with no entry,
or when an entry's evidence has gone.

Usage:
  python3 scripts/check_claims.py              check the real files, exit 1 on any FAIL
  python3 scripts/check_claims.py --strict     unverified entries and entries whose text left the copy fail too
  python3 scripts/check_claims.py --json       the same result as JSON
  python3 scripts/check_claims.py --root DIR   check another tree (the tests use this)

From another script: `import check_claims; result = check_claims.check(root)` returns a dict with the keys
`failures`, `warnings` and `counts`. Standard library only.

What it checks:
- Evidence. Each `evidence` item's `path` exists, and when `contains` is given the file holds that exact string.
  `BenchmarkRuns/*` is gitignored, so a run folder that is absent here is a WARN ("run folder not on this machine");
  `BenchmarkRuns/LEDGER.md` and `PROGRESSION.md` are tracked and are checked like any file. A path outside the
  repository fails: a memory note or a file in a home folder is not evidence.
- Arithmetic. A `derivation` written as "15/17 = 88.2%" is recomputed, and the whole percentage it gives (88%) must
  be in the entry's `claim`.
- Coverage. Every numeric token on every line of the copy (digits with an optional comma, decimal or %, and
  "N of M") must sit inside the `claim` text of an entry that lists that file, or inside a `not_claims` pattern.
  One that does neither is a FAIL with its file, line number and line. Digits joined to letters count (M1, 8K).
- Status. `verified` needs evidence. `unverified` needs a `note` saying where the evidence was looked for, and is a
  WARN. `mismatch` (the copy's figure disagrees with its evidence) is a FAIL until the copy or the entry changes.
- An entry whose `claim` text is no longer in a file it lists is a WARN (the copy changed, the register did not).

Levels: FAIL exits 1. WARN is printed and exits 0, except that `--strict` turns unverified entries and entries
whose text left the copy into FAILs. An absent run folder stays a WARN under `--strict`, because a fresh clone has
none of them.

What it does not cover:
- Any text outside the five files: Settings text and other strings in the app, the in-app guides and What's New,
  the three websites, the README, the user changelog itself.
- Claims with no digit in them ("works offline", "never sent to a third party") unless someone adds an entry, and
  numbers written as words ("eight test papers").
- Whether the evidence is right. It checks that the recorded string is still in the recorded file, not that the
  run was sound or that the sentence around the figure says what the run measured. That is a person's read.
- The text live in App Store Connect. It reads the files under fastlane/, not the store.
"""
import argparse, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTER = "Docs/ai/CLAIMS.json"
COPY_FILES = (
    "fastlane/metadata/en-US/description.txt",
    "fastlane/metadata/en-US/promotional_text.txt",
    "fastlane/metadata/en-US/release_notes.txt",
    "fastlane/metadata-ios/en-US/promotional_text.txt",
    "fastlane/metadata-ios/en-US/release_notes.txt",
)
KINDS = {"measured", "limit", "requirement", "count", "timing"}
STATUSES = {"verified", "unverified", "mismatch"}
RUNS_DIR = "BenchmarkRuns/"
TRACKED_IN_RUNS = {"BenchmarkRuns/LEDGER.md", "BenchmarkRuns/PROGRESSION.md"}
# 1,000  88%  27.0.1  8,192  "15 of 17"  "85% of 515". A comma counts only before a group of three digits.
NUMBER = r"\d+(?:,\d{3})*(?:\.\d+)*"
TOKEN = re.compile(NUMBER + r"%?(?:\s+of\s+" + NUMBER + r")?")
# "15/17 = 88.2%" or "8,920/10,029 = 88.9%" in a derivation.
FRACTION = re.compile(r"(\d[\d,]*)\s*/\s*(\d[\d,]*)\s*=\s*(\d+(?:\.\d+)?)\s*%")


def _read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
        return f.read()


def _inside_repo(rel):
    return bool(rel) and not os.path.isabs(rel) and ".." not in rel.replace("\\", "/").split("/") and not rel.startswith("~")


def _is_run_path(rel):
    return rel.startswith(RUNS_DIR) and rel.rstrip("/") not in TRACKED_IN_RUNS


def _spans(needle, line):
    """Every (start, end) where `needle` occurs in `line`."""
    out, at = [], line.find(needle)
    while at != -1:
        out.append((at, at + len(needle)))
        at = line.find(needle, at + 1)
    return out


def _covered(span, spans):
    return any(a <= span[0] and span[1] <= b for a, b in spans)


def check_derivation(entry):
    """Problems with an entry's "a/b = x%" arithmetic, as a list of sentences."""
    problems = []
    for a, b, stated in FRACTION.findall(entry.get("derivation") or ""):
        top, bottom, stated = int(a.replace(",", "")), int(b.replace(",", "")), float(stated)
        if bottom == 0:
            problems.append(f"{a}/{b} divides by zero")
            continue
        real = 100.0 * top / bottom
        if abs(real - stated) > 0.05 + 1e-9:
            problems.append(f"{a}/{b} is {real:.1f}%, the derivation says {stated:g}%")
            continue
        whole = int(real + 0.5)
        if not re.search(rf"(?<![\d.]){whole}%", entry.get("claim", "")):
            problems.append(f"{a}/{b} is {real:.1f}%, which rounds to {whole}%, and the claim does not say {whole}%")
    return problems


def check(root=ROOT, strict=False):
    """Check the register and the copy under `root`. Returns {"failures": [...], "warnings": [...], "counts": {...}}.

    Each failure and warning is a dict with `check` and `detail`, plus `id` for a register entry or `file`, `line`,
    `token` and `text` for a number in the copy. `strict` moves unverified and stale entries from warnings to
    failures.
    """
    failures, warnings = [], []
    counts = {"claims": 0, "verified": 0, "unverified": 0, "mismatch": 0, "not_claims": 0, "evidence_items": 0,
              "evidence_confirmed": 0, "run_folders_absent": 0, "copy_files": 0, "numbers": 0, "covered": 0,
              "exempted": 0, "uncovered": 0}
    result = {"failures": failures, "warnings": warnings, "counts": counts}

    def fail(check_name, detail, **more):
        failures.append({"check": check_name, "detail": detail, **more})

    def warn(check_name, detail, **more):
        (failures if strict and check_name in ("unverified", "claim not in copy") else warnings).append(
            {"check": check_name, "detail": detail, **more})

    try:
        register = json.loads(_read(root, REGISTER))
    except FileNotFoundError:
        fail("register", f"{REGISTER} is missing")
        return result
    except ValueError as error:
        fail("register", f"{REGISTER} is not valid JSON: {error}")
        return result
    claims = register.get("claims") if isinstance(register, dict) else None
    if not isinstance(claims, list):
        fail("register", f'{REGISTER} needs a top-level "claims" list')
        return result

    exemptions = []
    for item in register.get("not_claims") or []:
        pattern, reason = (item or {}).get("pattern"), (item or {}).get("reason")
        if not pattern or not reason:
            fail("not_claims", f"each not_claims item needs a pattern and a reason: {item!r}")
            continue
        try:
            exemptions.append(re.compile(pattern))
        except re.error as error:
            fail("not_claims", f"pattern {pattern!r} is not a valid regular expression: {error}")
    counts["not_claims"] = len(exemptions)

    copy = {}
    for rel in COPY_FILES:
        try:
            copy[rel] = _read(root, rel)
        except FileNotFoundError:
            fail("copy file", f"{rel} is missing", file=rel)
    counts["copy_files"] = len(copy)

    seen, by_file = set(), {rel: [] for rel in COPY_FILES}
    for position, entry in enumerate(claims):
        if not isinstance(entry, dict):
            fail("entry", f"claims[{position}] is not an object")
            continue
        ident = entry.get("id") or f"claims[{position}]"
        claim, files, status = entry.get("claim"), entry.get("files"), entry.get("status")
        evidence = entry.get("evidence")
        counts["claims"] += 1
        if not entry.get("id") or ident in seen:
            fail("entry", "an entry has no id" if not entry.get("id") else f"the id {ident} is used twice", id=ident)
        seen.add(ident)
        if not isinstance(claim, str) or not claim.strip():
            fail("entry", "no claim text", id=ident)
            claim = ""
        if entry.get("kind") not in KINDS:
            fail("entry", f"kind {entry.get('kind')!r} is not one of {', '.join(sorted(KINDS))}", id=ident)
        if not isinstance(files, list) or not files:
            fail("entry", "files must list at least one of the copy files", id=ident)
            files = []
        if not isinstance(evidence, list):
            fail("entry", "evidence must be a list (an empty one for an unverified entry)", id=ident)
            evidence = []
        if status not in STATUSES:
            fail("entry", f"status {status!r} is not one of {', '.join(sorted(STATUSES))}", id=ident)
        else:
            counts[status] += 1

        for rel in files:
            if rel not in COPY_FILES:
                fail("entry", f"{rel} is not one of the five copy files", id=ident)
            elif rel in copy:
                by_file[rel].append(claim)
                if claim and claim not in copy[rel]:
                    warn("claim not in copy", f'"{claim}" is not in {rel}: the copy changed and the register did not',
                         id=ident, file=rel)

        if status == "verified" and not evidence:
            fail("evidence", "a verified entry needs at least one evidence item", id=ident)
        if status == "unverified":
            if not entry.get("note"):
                fail("entry", "an unverified entry needs a note saying where the evidence was looked for", id=ident)
            warn("unverified", f'"{claim}": {entry.get("note") or "no note"}', id=ident)
        if status == "mismatch":
            fail("mismatch", f'"{claim}" disagrees with its evidence: {entry.get("note") or "no note"}', id=ident)

        for item in evidence:
            counts["evidence_items"] += 1
            rel = item.get("path") if isinstance(item, dict) else None
            contains = item.get("contains") if isinstance(item, dict) else None
            if not rel or not _inside_repo(rel):
                fail("evidence", f"{rel!r} is not a path inside the repository", id=ident)
                continue
            full = os.path.join(root, rel)
            if not os.path.exists(full):
                if _is_run_path(rel):
                    counts["run_folders_absent"] += 1
                    warnings.append({"check": "run folder not on this machine", "id": ident,
                                     "detail": f"{rel} (BenchmarkRuns/* is gitignored)"})
                else:
                    fail("evidence", f"{rel} does not exist", id=ident)
                continue
            if contains is None:
                counts["evidence_confirmed"] += 1
                continue
            if os.path.isdir(full):
                fail("evidence", f'{rel} is a folder, so "contains" cannot be checked: name a file in it', id=ident)
            elif contains in _read(root, rel):
                counts["evidence_confirmed"] += 1
            else:
                fail("evidence", f'{rel} no longer contains "{contains}"', id=ident)

        for problem in check_derivation(entry):
            fail("derivation", problem, id=ident)

    for rel, text in copy.items():
        for number, line in enumerate(text.splitlines(), 1):
            claimed = [span for claim in by_file[rel] if claim for span in _spans(claim, line)]
            exempt = [m.span() for pattern in exemptions for m in pattern.finditer(line)]
            for match in TOKEN.finditer(line):
                counts["numbers"] += 1
                if _covered(match.span(), claimed):
                    counts["covered"] += 1
                elif _covered(match.span(), exempt):
                    counts["exempted"] += 1
                else:
                    counts["uncovered"] += 1
                    fail("uncovered number", f'"{match.group(0)}" has no register entry and no not_claims pattern',
                         file=rel, line=number, token=match.group(0), text=line.strip())
    return result


def render(result):
    counts = result["counts"]
    lines = [f"{REGISTER}: {len(result['failures'])} FAIL, {len(result['warnings'])} WARN",
             f"claims {counts['claims']}: {counts['verified']} verified, {counts['unverified']} unverified, "
             f"{counts['mismatch']} mismatch; evidence {counts['evidence_confirmed']} of {counts['evidence_items']} "
             f"confirmed, {counts['run_folders_absent']} run folders not on this machine",
             f"copy {counts['copy_files']} of {len(COPY_FILES)} files, {counts['numbers']} numbers: "
             f"{counts['covered']} covered by an entry, {counts['exempted']} exempt, {counts['uncovered']} uncovered",
             "a figure in the copy has no evidence on record" if result["failures"]
             else "every figure in the copy has an entry, and every entry's evidence is in place", ""]
    for level, rows in (("FAIL", result["failures"]), ("WARN", result["warnings"])):
        for row in rows:
            where = f"{row['file']}:{row['line']}" if "line" in row else row.get("id", "")
            lines.append(f"{level:<5} {row['check']:<30} {where}  {row['detail']}")
            if "text" in row:
                lines.append(f"      {row['text']}")
    return "\n".join(lines).rstrip()


def main(argv=None):
    p = argparse.ArgumentParser(description="Read-only check of the App Store copy against the claims register.")
    p.add_argument("--root", default=ROOT, help="the repository to check (default: this one)")
    p.add_argument("--strict", action="store_true", help="unverified entries and entries whose text left the copy fail")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    result = check(a.root, strict=a.strict)
    print(json.dumps(result, indent=2, ensure_ascii=False) if a.json else render(result))
    return 1 if result["failures"] else 0


if __name__ == "__main__":
    sys.exit(main())
