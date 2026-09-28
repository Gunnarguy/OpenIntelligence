#!/usr/bin/env python3
"""Put a survey from build_map.py into the Repo Map page.

    python3 .claude/skills/repo-map/scripts/render.py <data.json> <out.html> [--preview <preview.html>]

The page is named "<app> Repo Map", taking the app from the survey (build_map.py --name, or the
repository folder name).

<out.html> is what the Artifact tool publishes: page content with no <html>/<head>/<body>, because
the publisher wraps it. --preview also writes a standalone copy with that wrapper, for a browser.
"""

import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser()
ap.add_argument("data")
ap.add_argument("out")
ap.add_argument("--preview")
args = ap.parse_args()

data = Path(args.data).read_text()
json.loads(data)  # fail here, not in the browser, on a truncated survey
template = (HERE / "page_template.html").read_text()
if "/*__DATA__*/" not in template:
    raise SystemExit("page_template.html has lost its /*__DATA__*/ placeholder")
# "</" inside the JSON would end the <script> element early; "\/" is the same JSON string.
# Name the page before the survey goes in, so no string inside the survey can be renamed by accident.
app = json.loads(data).get("app") or "OpenIntelligence"
template = template.replace("OpenIntelligence Repo Map", f"{app} Repo Map")
page = template.replace("/*__DATA__*/", data.replace("</", "<\\/"))
Path(args.out).write_text(page)
if args.preview:
    Path(args.preview).write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        "<style>body{margin:0}[hidden]{display:none!important}</style></head><body>"
        + page + "</body></html>")
print(f"wrote {args.out} ({len(page) // 1024} KB)")
