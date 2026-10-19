#!/bin/sh
set -eu
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
CURRENT="$(git config --local --get core.hooksPath || true)"
if [ -n "$CURRENT" ] && [ "$CURRENT" != ".githooks" ]; then
  echo "BLOCKED: existing core.hooksPath=$CURRENT; not replacing custom hooks" >&2
  exit 1
fi
if [ -z "$CURRENT" ]; then
  HOOKS="$(git rev-parse --git-path hooks)"
  if [ -f "$HOOKS/pre-commit" ] && ! grep -Fq 'Vibe Handoff' "$HOOKS/pre-commit"; then
    echo "BLOCKED: existing pre-commit hook at $HOOKS/pre-commit; preserve it" >&2
    exit 1
  fi
fi
test -f .githooks/pre-commit
test -f Tools/vibe_handoff.py
git config --local core.hooksPath .githooks
printf 'Installed Vibe Handoff hook in %s\n' "$ROOT"
