#!/usr/bin/env bash
# Shared helpers for the Context OS hooks. Sourced by session-start.sh, pre-compact.sh, and
# stop-handoff.sh; not run on its own.
#
# This file exists because the change-detection hash was originally written twice and the two
# copies diverged. One piped git straight into shasum, the other used a command substitution, which
# strips the trailing newline, so the hashes never matched and the Stop hook fired on every session
# including read-only ones. One definition, sourced by both.

# Read one top-level string field from the hook's stdin JSON, captured by the caller in HOOK_STDIN.
hook_field() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "${HOOK_STDIN:-}" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "${HOOK_STDIN:-}" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

# Count non-empty lines in $1, as a single integer.
#
# Not `grep -c . || echo 0`: on empty input grep prints 0 AND exits 1, so the fallback fires and
# appends a second 0. The result is the two-line string "0\n0", every integer comparison against it
# errors with "integer expression expected", and the clean-tree branch becomes unreachable. That is
# only visible on a clean working tree, which is why testing on a dirty one missed it.
count_lines() {
  printf '%s' "${1:-}" | grep -c . 2>/dev/null | head -1 | tr -dc '0-9' || true
}

# Modification time of $1 as an integer, or 0.
#
# `stat -f %m` is BSD. Under GNU coreutils `-f` means "filesystem status" and `%m` is the mount
# point, so GNU stat prints several lines of unrelated output and exits 1 — which means a bare
# `stat -f %m x || echo 0` APPENDS 0 to that garbage rather than replacing it, and the result then
# reaches an integer comparison. macOS ships BSD stat at /usr/bin/stat, but a machine with
# coreutils' gnubin ahead of it on PATH gets GNU stat. Try BSD, fall back to GNU, then validate.
mtime_of() {
  local m
  m="$(stat -f %m "$1" 2>/dev/null)" || m="$(stat -c %Y "$1" 2>/dev/null)" || m=""
  case "$m" in '' | *[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

# One hash covering everything a session could have changed. All four inputs are needed:
#
#   - HEAD, so committing counts as work.
#   - `git status --porcelain -uall`, so a new untracked file counts even when it lands inside an
#     already-untracked directory. The default listing collapses those to one line and hides it.
#   - `git diff HEAD`, so editing a file that was already dirty at session start counts. Status
#     alone is byte-identical before and after that edit.
#   - The CONTENT of untracked files. `git diff HEAD` covers tracked files only and a `?? path`
#     status line says nothing about content, so without this term, rewriting an untracked file
#     from end to end produces an identical fingerprint. That is not a hypothetical here: this
#     whole context system arrives untracked, so a session that only edits it would look idle.
#
# The `:(exclude)` pathspec keeps the hooks' own writes under .claude/.state/ out of the hash. That
# directory is gitignored, so this is belt and braces, but without it the system would depend on one
# .gitignore line: delete that line and every session would look like it changed the repo.
#
# Cost is ~80ms on this repository with ~24 untracked files, against a 20s hook timeout. The
# untracked list is capped at 1000 entries so a pathological working tree cannot stall a session;
# past that cap the hash stops discriminating and the Stop hook simply asks for a handoff more
# often than it needs to, which is the safe direction.
repo_fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null
    git status --porcelain -uall -- . ':(exclude).claude/.state' 2>/dev/null
    git diff HEAD -- . ':(exclude).claude/.state' 2>/dev/null
    git status --porcelain -z -uall -- . ':(exclude).claude/.state' 2>/dev/null |
      tr '\0' '\n' | sed -n 's/^?? //p' | head -1000 |
      tr '\n' '\0' | xargs -0 git hash-object -- 2>/dev/null
  } | shasum 2>/dev/null | cut -d' ' -f1
}
