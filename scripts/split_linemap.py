#!/usr/bin/env python3
"""Where a line of RAGService.swift or AgenticOrchestrator.swift went in the 2026-11-05 split.

    python3 scripts/split_linemap.py RAGService.swift:12019
    python3 scripts/split_linemap.py AgenticOrchestrator.swift:2209

The line numbers are those of the files at commit e68facb2, the last before the split. A citation in an older doc may
name an earlier commit's line, which can differ; read the cited text in `git show <commit>:<path>` when it matters.
"""
import json, sys
from pathlib import Path
m = json.loads((Path(__file__).resolve().parent.parent / "Docs/ai/split-2026-11-05-linemap.json").read_text())
for arg in sys.argv[1:] or [__doc__]:
    if ":" not in arg: print(__doc__); break
    name, line = arg.rsplit(":", 1)
    hit = m.get(Path(name).name, {}).get(line.split("-")[0])
    print(f"{arg} -> " + (f"{hit[0]}:{hit[1]}" if hit else "removed or out of range"))
