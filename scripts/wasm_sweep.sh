#!/usr/bin/env bash
# scripts/wasm_sweep.sh — the WASM→WAT "never silently wrong" gate.
#
# For EVERY e2e `run <name> <want>` program, compile it to WAT (the `wat` backend), assemble with
# wat2wasm, and run under wasmtime. The WAT backend implements a SUBSET of the language, so a program
# is allowed to (a) MATCH the x86_64 exit code, (b) cleanly TRAP (exit 134 — an `(unreachable)` a
# fail-loud emit inserts for an unsupported construct), or (c) be REJECTED by wat2wasm (also
# acceptable — the module never runs). What is NOT allowed is a VALID module that runs to a wrong,
# non-trap exit code: that is a SILENT MISCOMPILE, the one failure mode the fail-loud design forbids.
#
# Requires wat2wasm + wasmtime (flake devShell); absent → SKIP (an env gap is not a failure). Builds
# Stage1 from the seed unless `ALATYR_SWEEP_CC` names one already built (scripts/sweeps.sh builds it
# once and shares it). Exit 0 = no silent miscompiles (or skipped); 1 = a WRONG was found.
#
# The corpus runs on `$(nproc)` workers (`ALATYR_JOBS=1` for strict corpus order); every artifact is
# keyed by the corpus ROW, not by the fixture name, because the corpus contains the same name twice.
# All artifacts go to a private, freshly wiped `target/sweep/wasm/`; every child is spawned with
# `< /dev/null`; and the loop must visit the whole corpus. See scripts/sweep_common.sh.
set -u
ulimit -c 0 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
. "$ROOT/scripts/sweep_common.sh"

command -v wat2wasm >/dev/null 2>&1 && command -v wasmtime >/dev/null 2>&1 || { echo "skip wasm_sweep: wat2wasm/wasmtime absent"; exit 0; }
sweep_compiler "$ROOT" wasm_sweep || exit 1
sweep_scratch "$ROOT" wasm
CC="$SWEEP_CC"
corpus="$(sweep_corpus_size "$ROOT")"
echo "wasm_sweep: compiler=$CC corpus=$corpus scratch=$SWEEP_DIR jobs=$(sweep_jobs)"

## One corpus program. `$1` is this ROW's scratch prefix, `$2` the fixture, `$3` its x86_64 exit code.
## The order of operations carries the meaning: a failure of the COMPILER's emit is a WRONG (the
## compiler must never fail to produce text for a program x86_64 accepted), while wat2wasm refusing
## the module is a `reject` — the assembler RAN and refused it, so nothing was ever executed.
wasm_verdict() { # scratch-prefix, name, want
  wat="$1.wat"; wasm="$1.wasm"
  "$CC" wat "$ROOT/test/$2.al" > "$wat" 2>"$wat.err" < /dev/null \
    || { echo "WRONG wat emit failed: $(head -3 "$wat.err" | tr '\n' ' ')"; return; }
  wat2wasm "$wat" -o "$wasm" 2>/dev/null < /dev/null || { echo reject; return; }
  timeout 10 wasmtime "$wasm" >/dev/null 2>&1 < /dev/null; got=$?
  if [ "$got" = "$3" ]; then echo match
  elif [ "$got" = 134 ]; then echo trap
  else echo "WRONG wasm=$got want=$3 (valid module, non-trap, wrong exit = SILENT MISCOMPILE)"; fi
}

sweep_selftest wasm_sweep || exit 1

fail=0
sweep_run_corpus "$ROOT" wasm_sweep wasm_verdict || fail=1
## `wrong` separates the ONE forbidden verdict (a valid binary with a wrong exit code) from a harness
## failure such as a truncated corpus, so the closing banner never claims a miscompile that nobody saw.
wrong=0; [ "$SWEEP_WRONG" = 0 ] || wrong=1
echo "wasm_sweep: match=$SWEEP_MATCH trap=$SWEEP_TRAP reject=$SWEEP_REJECT missing=$SWEEP_MISSING corpus=$corpus"
sweep_check_total wasm_sweep "$SWEEP_SEEN" "$corpus" || fail=1
if [ "$fail" = 0 ]; then echo "*** wasm_sweep: no silent miscompiles ***"
elif [ "$wrong" = 1 ]; then echo "*** wasm_sweep: SILENT MISCOMPILE(S) FOUND ***"
else echo "*** wasm_sweep: FAILED — the sweep could not reach a verdict (see the FAIL line above); this is NOT a miscompile finding ***"; fi
exit "$fail"
