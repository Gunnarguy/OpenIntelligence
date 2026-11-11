#!/usr/bin/env python3
"""Run the unit suite on Xcode Cloud and read the result, with nothing running on this Mac.

The `Tests (manual)` workflow runs the whole suite on three iOS 27 simulators (about 1,706 tests each, 26 to 30
minutes, roughly 1.5 of the owner's 100 monthly compute hours). It never starts on a push; this script starts it on
`main` as pushed. Apple's language model does not answer on these runners (run 496, 2026-11-11), so a test that
needs it skips or fails there; the `testing-routes` skill says where those run instead.

Needs the App Store Connect key that `~/.zshrc` exports, so run it through `zsh -ic` (the Bash tool and launchd do
not read `~/.zshrc`). It never prints the key's id, issuer or contents.

    zsh -ic 'python3 scripts/xcloud.py start'            # start a run on main; prints its number
    zsh -ic 'python3 scripts/xcloud.py watch'            # wait for the last run, then print its result
    zsh -ic 'python3 scripts/xcloud.py watch 497 --against 496'   # also: newly failing, fixed, still failing
    zsh -ic 'python3 scripts/xcloud.py logs 497 SOURCE-MISS'      # lines the tests printed, from the log bundle
    zsh -ic 'python3 scripts/xcloud.py list'             # recent runs: number, commit, result, failures

State (the last run started) is kept in BenchmarkRuns/xcloud/, which git ignores. Log bundles go to
/private/tmp/oi-xcloud/<run number>/.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

try:
    import jwt  # PyJWT
except ImportError:  # pragma: no cover
    sys.exit("PyJWT is missing: python3 -m pip install --user pyjwt cryptography")

API = "https://api.appstoreconnect.apple.com"
WORKFLOW_NAME = "Tests (manual)"
PRODUCT_ID = "c6efe188-583b-47d8-9db8-dc8e17ecc7c5"  # OpenIntelligence's Xcode Cloud product
REPOSITORY_ID = "bec570a6-ac71-4f19-a898-060f290b33bb"
TEST_ACTION = "Test - iOS"
ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "BenchmarkRuns" / "xcloud"
LOGS = Path("/private/tmp/oi-xcloud")


def token() -> str:
    try:
        key_id = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
        issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
        path = os.path.expanduser(os.environ["APP_STORE_CONNECT_API_KEY_PATH"])
    except KeyError:
        sys.exit("The App Store Connect key's variables are not set. Run this through zsh -ic '...'.")
    now = int(time.time())
    claims = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(claims, Path(path).read_text(), algorithm="ES256", headers={"kid": key_id})


def call(method: str, path: str, body: dict | None = None) -> dict:
    headers = {"Authorization": "Bearer " + token()}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    url = path if path.startswith("http") else API + path
    request = urllib.request.Request(url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        sys.exit(f"HTTP {error.code} {method} {path[:80]}: {error.read().decode()[:800]}")


def pages(path: str):
    while path:
        page = call("GET", path)
        yield from page.get("data", [])
        path = page.get("links", {}).get("next")


def workflow_id() -> str:
    for workflow in pages(f"/v1/ciProducts/{PRODUCT_ID}/workflows?limit=50"):
        if workflow["attributes"]["name"] == WORKFLOW_NAME:
            return workflow["id"]
    sys.exit(f"No workflow named {WORKFLOW_NAME!r} on the product.")


def runs(limit: int = 10) -> list[dict]:
    return call("GET", f"/v1/ciWorkflows/{workflow_id()}/buildRuns?limit={limit}&sort=-number")["data"]


def run_by_number(number: str | None) -> dict:
    if number is None:
        saved = STATE / "last_run.json"
        if not saved.exists():
            sys.exit("No run started from this checkout yet; pass a run number.")
        return call("GET", f"/v1/ciBuildRuns/{json.loads(saved.read_text())['id']}")["data"]
    for run in runs(50):
        if str(run["attributes"]["number"]) == str(number):
            return run
    sys.exit(f"Run {number} is not among the workflow's last 50.")


def test_action(run: dict) -> dict | None:
    for action in call("GET", f"/v1/ciBuildRuns/{run['id']}/actions")["data"]:
        if action["attributes"]["name"] == TEST_ACTION:
            return action
    return None


def results(action: dict) -> dict[str, dict]:
    """Per test, `Class.name`: its message and status on each device."""
    out: dict[str, dict] = {}
    for test in pages(f"/v1/ciBuildActions/{action['id']}/testResults?limit=200"):
        attributes = test["attributes"]
        name = f"{attributes.get('className')}.{attributes.get('name')}"
        devices = {d.get("deviceName"): d.get("status") for d in attributes.get("destinationTestResults", [])}
        out[name] = {"message": attributes.get("message") or "", "devices": devices,
                     "file": (attributes.get("fileSource") or {})}
    return out


def failing(table: dict[str, dict]) -> dict[str, dict]:
    return {name: test for name, test in table.items() if "FAILURE" in test["devices"].values()}


def describe(run: dict) -> str:
    a = run["attributes"]
    sha = (a.get("sourceCommit") or {}).get("commitSha", "")[:8]
    return f"run {a['number']} commit {sha} {a.get('executionProgress')} {a.get('completionStatus') or ''}".strip()


def command_start(_: argparse.Namespace) -> None:
    references = pages(f"/v1/scmRepositories/{REPOSITORY_ID}/gitReferences?limit=200")
    main = next(r for r in references if r["attributes"].get("name") == "main" and r["attributes"].get("kind") == "BRANCH")
    body = {"data": {"type": "ciBuildRuns", "relationships": {
        "workflow": {"data": {"type": "ciWorkflows", "id": workflow_id()}},
        "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": main["id"]}}}}}
    run = call("POST", "/v1/ciBuildRuns", body)["data"]
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "last_run.json").write_text(json.dumps({"id": run["id"], "number": run["attributes"]["number"]}))
    print(describe(run))
    print("It runs what origin/main holds: push first. Then: zsh -ic 'python3 scripts/xcloud.py watch'")


def command_watch(options: argparse.Namespace) -> None:
    run = run_by_number(options.run)
    started = time.time()
    while not run["attributes"].get("completionStatus"):
        if time.time() - started > 4 * 3600:
            sys.exit(describe(run) + ": still running after 4 hours")
        time.sleep(120)
        run = call("GET", f"/v1/ciBuildRuns/{run['id']}")["data"]
    print(describe(run))
    action = test_action(run)
    if action is None:
        sys.exit("The run has no test action.")
    a = action["attributes"]
    print(f"{TEST_ACTION}: {a.get('completionStatus')} {a.get('startedDate')} to {a.get('finishedDate')}")
    table = results(action)
    if not table:
        print("No test results: it failed before the tests ran. Read its issues in App Store Connect, or:")
        for issue in pages(f"/v1/ciBuildActions/{action['id']}/issues?limit=50"):
            i = issue["attributes"]
            print("  ISSUE", i.get("issueType"), (i.get("fileSource") or {}).get("path"), (i.get("message") or "")[:300])
        return
    counts = collections.Counter((device, status) for t in table.values() for device, status in t["devices"].items())
    for (device, status), n in sorted(counts.items(), key=str):
        print(f"  {device}: {status} {n}")
    failed = failing(table)
    for name, test in sorted(failed.items()):
        where = [d for d, s in test["devices"].items() if s == "FAILURE"]
        print(f"FAIL {name} on {len(where)} of {len(test['devices'])}: {test['message'][:300]}")
    if options.against:
        earlier = test_action(run_by_number(options.against))
        before = failing(results(earlier)) if earlier else {}
        print(f"\nAgainst run {options.against}:")
        for label, names in (("newly failing", failed.keys() - before.keys()),
                             ("fixed", before.keys() - failed.keys()),
                             ("still failing", failed.keys() & before.keys())):
            print(f"  {label}: {len(names)}")
            for name in sorted(names):
                print(f"    {name}")


def command_logs(options: argparse.Namespace) -> None:
    run = run_by_number(options.run)
    action = test_action(run)
    if action is None:
        sys.exit("The run has no test action.")
    folder = LOGS / str(run["attributes"]["number"])
    folder.mkdir(parents=True, exist_ok=True)
    bundle = folder / "logs.zip"
    if not bundle.exists():
        for artifact in call("GET", f"/v1/ciBuildActions/{action['id']}/artifacts")["data"]:
            if artifact["attributes"]["fileType"] == "LOG_BUNDLE":
                urllib.request.urlretrieve(artifact["attributes"]["downloadUrl"], bundle)
                break
        else:
            sys.exit("The run has no log bundle.")
    with zipfile.ZipFile(bundle) as archive:
        archive.extractall(folder / "logs")
    pattern = re.compile(options.pattern) if options.pattern else None
    for path in sorted((folder / "logs").rglob("*")):
        if not path.is_file():
            continue
        with path.open(errors="replace") as handle:
            lines = handle.read().splitlines()
        hits = [n for n, line in enumerate(lines) if pattern is None or pattern.search(line)]
        for n in hits[: options.max]:
            for line in lines[n: n + 1 + options.after]:
                print(re.sub(r"^\S+Z\t", "", line))
    print(f"(log bundle: {folder / 'logs'})", file=sys.stderr)


def command_list(_: argparse.Namespace) -> None:
    for run in runs(10):
        action = test_action(run)
        failures: object = "-"
        if action and run["attributes"].get("completionStatus"):
            table = results(action)
            failures = len(failing(table)) if table else "none ran"
        print(describe(run), "failing tests:", failures, run["attributes"].get("createdDate", "")[:16])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("start", help="start a run on main").set_defaults(func=command_start)
    watch = sub.add_parser("watch", help="wait for a run and print its result")
    watch.add_argument("run", nargs="?", help="run number (default: the last one started here)")
    watch.add_argument("--against", help="a run number to compare failures with")
    watch.set_defaults(func=command_watch)
    logs = sub.add_parser("logs", help="print lines the tests printed")
    logs.add_argument("run", nargs="?")
    logs.add_argument("pattern", nargs="?", help="a regular expression; every line when left out")
    logs.add_argument("--after", type=int, default=0, help="lines to print after each match")
    logs.add_argument("--max", type=int, default=200, help="matches to print per file")
    logs.set_defaults(func=command_logs)
    sub.add_parser("list", help="recent runs").set_defaults(func=command_list)
    options = parser.parse_args()
    options.func(options)


if __name__ == "__main__":
    main()
