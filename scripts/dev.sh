#!/usr/bin/env bash
# scripts/dev.sh — the FAST dev-loop check (NOT the authoritative gate; see scripts/full.sh).
#
# One self-build + optional focused tests + a guard for the Priority-0 arena-overflow corruption class.
# Use this while iterating; run scripts/full.sh (fixpoint + full e2e + conditional sweeps) before a commit.
#
# Usage (inside `nix develop`):  bash scripts/dev.sh [test_name ...]
#   test_name    a `test/<name>.al` to compile + run (repeatable); its exit code is printed.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1
ulimit -c 0

# Logs and per-test binaries live in this checkout's own target/, never a fixed path under the shared
# temp directory — the same rule scripts/full.sh follows and states. A fixed shared path is used by
# every worktree on the machine: two lanes running this script overwrite each other's evidence, and
# the per-test artifact was worse than that — it is EXECUTED, so one tree would silently run the
# other's binary and report its exit code as its own.
LOGDIR="$ROOT/target"; mkdir -p "$LOGDIR"
BUILD_LOG="$LOGDIR/dev_build.log"

echo "=== build (committed seed builds the compiler → target/debug/alatyr) ==="
rm -f "$ROOT/target/alatyr" "$ROOT/target/alatyr.s" "$ROOT/target/alatyr.o"
rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"
"$ROOT/seed/alatyr" build package.al > "$BUILD_LOG" 2>&1
rc=$?
# corruption guard: manifest/source text fused into an instruction (the arena-overflow signature)
if grep -qiE "no such instruction|junk at end of line|bad register|,package\.al|%package\.al" "$BUILD_LOG"; then
  echo "FAIL: malformed GAS (arena-overflow class?) — first errors:"; grep -iE "error|junk|package\.al" "$BUILD_LOG" | head -3
  exit 1
fi
[ "$rc" = 0 ] || { echo "FAIL: build (rc=$rc)"; grep -iE "error|selfhost|panic" "$BUILD_LOG" | head -3; exit 1; }
if [ -x "$ROOT/target/debug/alatyr" ]; then
  CC="$ROOT/target/debug/alatyr"
else
  CC="$ROOT/target/alatyr"
  [ -x "$CC" ] || { echo "FAIL: seed created neither target/debug/alatyr nor legacy target/alatyr"; exit 1; }
  echo "bootstrap transition: dev used legacy target/alatyr; fixpoint remains the reseed decision"
fi
echo "build OK — $("$CC" package.al 2>/dev/null | wc -l) GAS lines"

fail=0
for t in "$@"; do
  src="$ROOT/test/$t.al"
  [ -f "$src" ] || { echo "  MISS test/$t.al"; fail=1; continue; }
  if "$CC" -o "$LOGDIR/dev_$t.out" "$src" >/dev/null 2>&1; then
    "$LOGDIR/dev_$t.out" >/dev/null 2>&1; ec=$?
    echo "  test $t → exit $ec"
  else
    echo "  test $t → COMPILE FAIL"; fail=1
  fi
done

echo "=== dev check done — run scripts/full.sh before committing ==="
exit "$fail"
