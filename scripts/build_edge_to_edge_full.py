#!/usr/bin/env python3
"""Rebuild Docs/EdgeToEdge/EDGE_TO_EDGE_FULL.md from its chapter files, or check that it matches them.

The full document is its own preamble (everything before "# Module 00.", written by hand in this file only)
followed by the 17 module chapters `00_...md` to `16_...md`, concatenated byte for byte with nothing between
them. On 2026-11-06 all 17 matched exactly; before that, edits made to one copy and not the other had made the
two disagree on 13 identifiers (reconciled 2026-11-05). Edit a chapter, then run this script; never edit a
module inside the full document.

    python3 scripts/build_edge_to_edge_full.py           # rewrite the full document
    python3 scripts/build_edge_to_edge_full.py --check   # exit 1 and name the chapters that differ
"""
import sys
from pathlib import Path

FOLDER = Path(__file__).resolve().parents[1] / "Docs" / "EdgeToEdge"
FULL = FOLDER / "EDGE_TO_EDGE_FULL.md"
MARKER = "# Module 00."


def chapters():
    return sorted(p for p in FOLDER.glob("[01][0-9]_*.md") if not p.name.startswith("00_START"))


def build():
    full = FULL.read_text()
    cut = full.index(MARKER)
    return full[:cut] + "".join(p.read_text() for p in chapters())


def main():
    current = FULL.read_text()
    wanted = build()
    if "--check" not in sys.argv:
        if current != wanted:
            FULL.write_text(wanted)
            print(f"rewrote {FULL.name} from {len(chapters())} chapters")
        else:
            print(f"{FULL.name} already matches its {len(chapters())} chapters")
        return 0
    if current == wanted:
        return 0
    # name the modules that differ, so the fix is obvious
    body = current[current.index(MARKER):]
    starts = [i for i in range(len(body)) if body.startswith("# Module ", i) and (i == 0 or body[i - 1] == "\n")]
    parts = [body[a:b] for a, b in zip(starts, starts[1:] + [len(body)])]
    names = [p.name for p in chapters()]
    bad = [n for n, part, p in zip(names, parts, chapters()) if part != p.read_text()]
    if len(parts) != len(names):
        bad.append(f"module count: full has {len(parts)}, chapters {len(names)}")
    print(f"{FULL.relative_to(FOLDER.parents[1])} does not match its chapters: {', '.join(bad) or 'order or spacing'}.")
    print("Edit the chapter, then run: python3 scripts/build_edge_to_edge_full.py")
    return 1


if __name__ == "__main__":
    sys.exit(main())
