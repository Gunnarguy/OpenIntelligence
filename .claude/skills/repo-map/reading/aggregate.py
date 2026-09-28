#!/usr/bin/env python3
"""Collect the readers' results, check every cited line exists, and write review files.

    python3 aggregate.py collect      # results -> per-app merged verdicts + wrong-claims review files
    python3 aggregate.py apply        # verifier outcomes -> final verdicts in ~/.claude/repo-map-verdicts/
"""

import json
import os
import re
import sys
from pathlib import Path

# Work files (batches, results, reviews) live in a scratch folder, never in a repository.
HERE = Path(os.environ.get("REPO_MAP_WORK", os.path.join(os.environ.get("TMPDIR", "/tmp"), "repo-map-reading")))
REPOS = {"OpenIntelligence": "~/Documents/GitHub/OpenIntelligence", "OpenResponses": "~/Documents/GitHub/OpenResponses",
         "OpenCone": "~/Documents/GitHub/OpenCone", "OpenManual": "~/Documents/GitHub/OpenManual"}
BATCH_APP = {"OI": "OpenIntelligence", "OR": "OpenResponses", "OC": "OpenCone", "OM": "OpenManual"}
KEYS = {"path", "blob", "kind", "verdict", "claims_estimate", "claims_checked", "wrong", "holds", "unverifiable",
        "used_by_app", "summary"}
VERDICTS = {"holds", "some-wrong", "mostly-wrong", "not-claims", "plan-done", "plan-partial", "plan-open",
            "record", "external", "template"}
CITE = re.compile(r"([A-Za-z0-9_./+-]+\.[A-Za-z0-9]+):(\d+)")  # no spaces: prose around a citation is not its path


def repo(app):
    return Path(os.path.expanduser(REPOS[app]))


SHA = re.compile(r"\b[0-9a-f]{7,40}\b")


def lines_at_commit(root, sha, path):
    import subprocess
    if "/" not in path:  # a bare file name: find it in that commit's tree
        names = subprocess.run(["git", "-C", str(root), "ls-tree", "-r", "--name-only", sha],
                               capture_output=True, text=True).stdout.splitlines()
        path = next((n for n in names if n.endswith("/" + path) or n == path), path)
    r = subprocess.run(["git", "-C", str(root), "show", f"{sha}:{path}"], capture_output=True, text=True)
    return r.stdout.count("\n") + 1 if r.returncode == 0 else 0


def cited_lines_exist(app, evidence):
    """Every path:line in the evidence names a real file with at least that many lines, in the
    working tree or at a commit the evidence names ("at bb16871", "34fde4f:path:line"): what shipped
    in an earlier version can be evidence even after HEAD removed it."""
    root = repo(app)
    cites = CITE.findall(evidence or "")
    shas = SHA.findall(evidence or "")
    if not cites:
        return False
    for path, line in cites:
        path = path.strip().lstrip("./")
        if any(lines_at_commit(root, sha, path) >= int(line) for sha in shas):
            continue
        f = root / path
        if not f.is_file():
            hits = list(root.rglob(os.path.basename(path)))
            hits = [h for h in hits if "/.build/" not in str(h) and "/DerivedData/" not in str(h)]
            if not hits:
                return False
            f = hits[0]
        try:
            n = sum(1 for _ in f.open(errors="ignore"))
        except OSError:
            return False
        if int(line) > n:
            return False
    return True


def collect():
    merged = {a: {} for a in REPOS}
    problems = []
    for rf in sorted(HERE.glob("result-*.json")):
        batch = rf.stem.split("-", 1)[1]
        app = BATCH_APP[batch.split("-")[0]]
        try:
            rows = json.loads(rf.read_text())
        except ValueError as e:
            problems.append(f"{rf.name}: not JSON ({e})")
            continue
        expected = {d["path"] for d in json.loads((HERE / f"batch-{batch}.json").read_text())["docs"]}
        seen = set()
        for r in rows:
            missing = KEYS - set(r)
            if missing or r.get("verdict") not in VERDICTS or r.get("path") not in expected:
                problems.append(f"{rf.name}: {r.get('path')} malformed ({sorted(missing)} {r.get('verdict')})")
                continue
            seen.add(r["path"])
            for w in r["wrong"]:
                w["evidence_lines_exist"] = cited_lines_exist(app, w.get("evidence", ""))
            r["checked_on"] = os.environ.get("REPO_MAP_READ_ON") or __import__("datetime").date.today().isoformat()
            merged[app][r["path"]] = r
        for p in sorted(expected - seen):
            problems.append(f"{rf.name}: no result for {p}")
    for app, rows in merged.items():
        if not rows:
            continue
        (HERE / f"merged-{app}.json").write_text(json.dumps(rows, indent=1))
        review = [{"id": f"{app}:{p}:{i}", "path": p, "claim": w["claim"], "evidence": w["evidence"],
                   "evidence_lines_exist": w["evidence_lines_exist"]}
                  for p, r in rows.items() for i, w in enumerate(r["wrong"])]
        (HERE / f"review-{app}.json").write_text(json.dumps(review, indent=1))
        n_wrong = len(review)
        n_bad = sum(1 for x in review if not x["evidence_lines_exist"])
        verdicts = {}
        for r in rows.values():
            verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
        print(f"{app}: {len(rows)} docs read; verdicts {verdicts}; wrong claims {n_wrong}, of which cite a line that does not exist: {n_bad}")
    for p in problems:
        print("PROBLEM:", p)


def apply():
    """Keep only wrong claims the verifier confirmed; recompute each document's verdict."""
    out_dir = Path(os.path.expanduser("~/.claude/repo-map-verdicts"))
    out_dir.mkdir(parents=True, exist_ok=True)
    for app in REPOS:
        mf = HERE / f"merged-{app}.json"
        if not mf.exists():
            continue
        rows = json.loads(mf.read_text())
        if not list(HERE.glob(f"verified-{app}*.json")):
            print(f"{app}: second check not run yet; skipped (its findings are kept for when it runs)")
            continue
        outcomes = {}
        for vf in HERE.glob(f"verified-{app}*.json"):
            for o in json.loads(vf.read_text()):
                outcomes[o["id"]] = o
        dropped = 0
        for p, r in rows.items():
            kept = []
            for i, w in enumerate(r["wrong"]):
                o = outcomes.get(f"{app}:{p}:{i}")
                evidence = (o or {}).get("corrected_evidence") or w.get("evidence", "")
                if o and o.get("outcome") == "confirmed" and cited_lines_exist(app, evidence):
                    w["evidence"] = evidence
                    kept.append(w)
                else:
                    dropped += 1
                    r.setdefault("unverifiable", []).append(
                        f"{w['claim']} (a first reading called this wrong; the second check "
                        f"{'refuted it' if o and o.get('outcome') == 'refuted' else 'could not confirm it'})")
            r["wrong"] = kept
            # an outside reference that also carries notes about the app, and gets them wrong, is flagged
            if r["verdict"] == "external" and kept:
                r["verdict"] = "some-wrong"
            if r["verdict"] in ("holds", "some-wrong", "mostly-wrong"):
                checked = max(1, r.get("claims_checked") or 1)
                r["verdict"] = "holds" if not kept else ("mostly-wrong" if len(kept) / checked > 1 / 3 else "some-wrong")
            r["unverifiable"] = r["unverifiable"][:6]
        (out_dir / f"{app}.json").write_text(json.dumps(rows, indent=1))
        print(f"{app}: wrote {len(rows)} verdicts; {dropped} first-reading 'wrong' claims not confirmed and moved to unverifiable")


if __name__ == "__main__":
    {"collect": collect, "apply": apply}[sys.argv[1]]()
