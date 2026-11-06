#!/usr/bin/env python3
"""Where a line of a file split on 2026-11-05 went: RAGService.swift and AgenticOrchestrator.swift, and the files
split after them that night (ChatScreen.swift, DocumentProcessor.swift and the rest, listed under `_bases`).

    python3 scripts/split_linemap.py RAGService.swift:12019
    python3 scripts/split_linemap.py ChatScreen.swift:2066

The line numbers are those of the file at the commit before its split: e68facb2 for RAGService and
AgenticOrchestrator, and the commit `_bases` names for each later file (printed with the answer). A citation in an
older doc may name an earlier commit's line, which can differ; read the cited text in `git show <commit>:<path>`
when it matters.
"""
import json, sys
from pathlib import Path
m = json.loads((Path(__file__).resolve().parent.parent / "Docs/ai/split-2026-11-05-linemap.json").read_text())
for arg in sys.argv[1:] or [__doc__]:
    if ":" not in arg: print(__doc__); break
    name, line = arg.rsplit(":", 1)
    hit = m.get(Path(name).name, {}).get(line.split("-")[0])
    base = m.get("_bases", {}).get(Path(name).name, "e68facb2")
    print(f"{arg} (lines at {base}) -> " + (f"{hit[0]}:{hit[1]}" if hit else "removed or out of range"))
