#!/usr/bin/env python3
"""Copy the purpose block of Docs/ai/PURPOSE.md into every agent's always-loaded instruction file.

The block between `<!-- purpose:begin -->` and `<!-- purpose:end -->` in Docs/ai/PURPOSE.md is the only
place the app's purpose and the owner's rules are written. This script puts a byte-for-byte copy of it
between the same markers in:

  CLAUDE.md                      Claude Code (re-read from disk after every compaction)
  AGENTS.md                      Codex, Antigravity, Gemini CLI
  .agents/rules/02-purpose.md    Antigravity's always-on rules

Usage:
  python3 scripts/sync_purpose.py --write   rewrite the copies from Docs/ai/PURPOSE.md
  python3 scripts/sync_purpose.py --check   exit 1 if any copy differs
  python3 scripts/sync_purpose.py --check --staged   the same, on the git index (the pre-commit hook)

Added 2026-11-09, after the owner found the purpose living only in one agent's private memory.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Docs/ai/PURPOSE.md"
BEGIN, END = "<!-- purpose:begin -->", "<!-- purpose:end -->"
TARGETS = ["CLAUDE.md", "AGENTS.md", ".agents/rules/02-purpose.md"]
RULE_FILE_HEAD = (
    "# Rule: the app's purpose and the owner's rules (always on)\n\n"
    "Generated from `Docs/ai/PURPOSE.md` by `scripts/sync_purpose.py`. Edit that file, not this one.\n\n"
)
PATTERN = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.S)


def block(text: str, where: str) -> str:
    found = PATTERN.findall(text)
    if len(found) != 1:
        sys.exit(f"{where}: expected exactly one {BEGIN} ... {END} block, found {len(found)}. "
                 "Stage every copy with Docs/ai/PURPOSE.md, after: python3 scripts/sync_purpose.py --write")
    return found[0]


def read(rel: str, staged: bool) -> str:
    """The file as committed would see it: the index copy with --staged, else the working tree."""
    if staged:
        r = subprocess.run(["git", "show", f":{rel}"], cwd=ROOT, capture_output=True)
        if r.returncode == 0:
            return r.stdout.decode("utf-8")
    path = ROOT / rel
    return path.read_text(encoding="utf-8") if path.exists() else ""


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "--check"
    staged = "--staged" in sys.argv[2:]
    if mode not in ("--write", "--check") or (staged and mode == "--write"):
        sys.exit(__doc__)
    wanted = block(read("Docs/ai/PURPOSE.md", staged), "Docs/ai/PURPOSE.md")
    stale = []
    for rel in TARGETS:
        path = ROOT / rel
        old = read(rel, staged)
        if rel.startswith(".agents/rules/"):
            # The whole rule file is generated; compare its block, so a trailing edit outside it is not drift.
            new = RULE_FILE_HEAD + wanted + "\n"
            differs = PATTERN.findall(old) != [wanted]
        else:
            block(old, rel)
            new = PATTERN.sub(lambda _: wanted, old)
            differs = old != new
        if differs:
            stale.append(rel)
            if mode == "--write":
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(new, encoding="utf-8")
    if mode == "--check" and stale:
        print("The purpose block differs from Docs/ai/PURPOSE.md in: " + ", ".join(stale))
        print("Edit Docs/ai/PURPOSE.md only, then run: python3 scripts/sync_purpose.py --write")
        return 1
    print(("Rewrote: " + ", ".join(stale)) if (mode == "--write" and stale) else "Purpose block in sync: " + ", ".join(TARGETS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
