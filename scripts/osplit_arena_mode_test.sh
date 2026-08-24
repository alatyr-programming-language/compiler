#!/usr/bin/env bash
# scripts/osplit_arena_mode_test.sh — static/check regression for CT-12's osplit arena mode.
#
# The defect locked here is ownership propagation, not the ALATYR_OSPLIT split emitter. `osplit_on`
# allocates the environment scan on the caller's Arena and must therefore take `in out`; the split
# codegen remains behind its existing flag/fault boundary and this harness never enables it.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/src/cli.al"
CC="${ALATYR:-$ROOT/target/alatyr}"

if [ ! -f "$CLI" ]; then
  echo "FAIL osplit_arena_mode: compiler source not found at $CLI" >&2
  exit 1
fi

# grep, not rg: the gate's dev shell has no ripgrep, and a missing tool made this test fail as if the
# compiler were wrong. `grep -c` prints 0 and exits 1 on no match, so keep the `|| true`.
sig_count="$(grep -cE '^osplit_on := fn\(in out a : rt::Arena\) -> bool \{' "$CLI" || true)"
if [ "$sig_count" != 1 ]; then
  echo "FAIL osplit_arena_mode: expected exactly one in-out osplit_on signature (found $sig_count)" >&2
  exit 1
fi

if grep -nE '^osplit_on := fn\(a : rt::Arena\)' "$CLI" >/dev/null; then
  echo "FAIL osplit_arena_mode: legacy by-value Arena signature is still present" >&2
  exit 1
fi

call_count="$(grep -cE 'osplit_on\(a\)' "$CLI" || true)"
if [ "$call_count" != 1 ]; then
  echo "FAIL osplit_arena_mode: expected exactly one call with the caller Arena place (found $call_count)" >&2
  exit 1
fi

if [ ! -x "$CC" ]; then
  echo "FAIL osplit_arena_mode: compiler not found at $CC" >&2
  echo "build it first with: seed/alatyr build package.al" >&2
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! "$CC" check "$ROOT/package.al" >"$log" 2>&1; then
  echo "FAIL osplit_arena_mode: compiler package check rejected the mode change" >&2
  sed -n '1,12p' "$log" >&2
  exit 1
fi

echo "ok   osplit_arena_mode: in-out signature, caller-place call, and compiler package check"
