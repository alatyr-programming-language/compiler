#!/usr/bin/env bash
# scripts/agents_size_check.sh — AGENTS.md stays at most 150 lines (#1130).
#
# AGENTS.md holds the rules, one line each; the reasons, measurements and history go to docs/rationale/.
# The file grew from 403 to 486 lines in a week before this check existed, because every rule picked up
# its own history. A count is the one thing a reviewer cannot argue past, so the gate holds it.
#
# Usage:  bash scripts/agents_size_check.sh [file]     # default: AGENTS.md at the repository root
#         bash scripts/agents_size_check.sh --self-test
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_MAX_LINES=150

## Prints the verdict for a file; 0 within the limit, 1 over it, 2 missing.
agents_size_verdict() { # file
  [ -f "$1" ] || { echo "agents size: FAIL — $1 does not exist"; return 2; }
  local n; n="$(wc -l < "$1" | tr -d ' ')"
  if [ "$n" -gt "$AGENTS_MAX_LINES" ]; then
    echo "agents size: FAIL — $1 has $n lines, over the limit of $AGENTS_MAX_LINES."
    echo "  Keep the rule here in one line and move its reasons to docs/rationale/ (#1130)."
    return 1
  fi
  echo "agents size: lines=$n limit=$AGENTS_MAX_LINES ok"
}

if [ "${1:-}" = "--self-test" ]; then
  d="$ROOT/target/agents-size-selftest-$$"; mkdir -p "$d"; trap 'rm -rf "$d"' EXIT
  bad=0
  seq 1 150 > "$d/at"; agents_size_verdict "$d/at" >/dev/null || { echo "self-test: 150 lines refused"; bad=1; }
  seq 1 151 > "$d/over"; out="$(agents_size_verdict "$d/over")"; rc=$?
  [ "$rc" = 1 ] || { echo "self-test: 151 lines not refused (rc $rc)"; bad=1; }
  case "$out" in *'has 151 lines'*) ;; *) echo "self-test: refusal does not name the count"; bad=1 ;; esac
  agents_size_verdict "$d/absent" >/dev/null; [ $? = 2 ] || { echo "self-test: a missing file passed"; bad=1; }
  [ "$bad" = 0 ] && echo "agents size self-test: 4 checks ok"
  exit "$bad"
fi

agents_size_verdict "${1:-$ROOT/AGENTS.md}"
