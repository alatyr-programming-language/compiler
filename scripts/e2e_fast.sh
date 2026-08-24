#!/usr/bin/env bash
# scripts/e2e_fast.sh — the ITERATION front end for scripts/e2e.sh.
#
# There is now ONE runner. `scripts/e2e.sh` interprets the fixture table and executes it on `$(nproc)`
# workers; this wrapper only changes two POLICIES that make sense while iterating and never in the gate:
#
#   1. a name FILTER — `scripts/e2e_fast.sh uint` runs only the rows whose command contains `uint`;
#   2. Stage1 is rebuilt only when `target/debug/alatyr` is older than `src/`/`lib/`, instead of always.
#
# It used to be a SECOND runner, and that is the point of retiring it. It re-derived the table with its
# own `grep` for 7 of the ~56 assertion kinds, so it covered ~92% of the suite and quietly skipped
# `run_wat*`/`check_wat*`, `check_export`, `check_located`, `check_parse_expected` and every one-off
# helper — a coverage gap that existed only because the table had two interpreters. Anything this
# script reports is now, by construction, what the gate reports for the same rows.
#
# Usage (inside `nix develop`):  bash scripts/e2e_fast.sh [<substring filter>]
# Everything else is scripts/e2e.sh's: ALATYR_JOBS, ALATYR_E2E_TEST_DIR, and the counts it prints.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec env ALATYR_E2E_REBUILD=stale ALATYR_E2E_FILTER="${1:-}" bash "$ROOT/scripts/e2e.sh"
