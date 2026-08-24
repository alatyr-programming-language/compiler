#!/usr/bin/env bash
# scripts/rv64_sweep.sh — the riscv64 "never silently wrong" gate.
#
# For EVERY e2e `run <name> <want>` program, emit RISC-V GAS (the `riscv64` backend), assemble+link
# with the cross binutils, and run under qemu-riscv64. The backend implements a SUBSET (the scalar
# kernel + scalar globals), so a program is allowed to (a) MATCH the x86_64 exit code, (b) cleanly
# TRAP/crash (exit >= 128 — an `ebreak` fail-loud emit for an unsupported construct raises SIGTRAP →
# 133), or (c) be REJECTED by as/ld (the ELF never runs). What is NOT allowed is a VALID binary that
# runs to a normal (< 128) wrong exit code: that is a SILENT MISCOMPILE, the one forbidden failure.
#
# Requires riscv64-unknown-linux-gnu-{as,ld} + qemu-riscv64 (flake devShell); absent → SKIP (an env
# gap is not a failure). Builds Stage1 from the seed unless `ALATYR_SWEEP_CC` names one already built
# (scripts/sweeps.sh builds it once and shares it). Exit 0 = no silent miscompiles.
#
# The corpus runs on `$(nproc)` workers (`ALATYR_JOBS=1` for strict corpus order); every artifact is
# keyed by the corpus ROW, not by the fixture name, because the corpus contains the same name twice.
# All artifacts go to a private, freshly wiped `target/sweep/rv64/`; every child is spawned with
# `< /dev/null`; and the loop must visit the whole corpus. See scripts/sweep_common.sh.
set -u
# The fail-loud `ebreak` raises SIGTRAP; under qemu-riscv64 that would dump a core file into the cwd
# for every trapping program. Disable core dumps so the sweep leaves no litter in the repo root.
ulimit -c 0 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
. "$ROOT/scripts/sweep_common.sh"

command -v riscv64-unknown-linux-gnu-as >/dev/null 2>&1 && command -v qemu-riscv64 >/dev/null 2>&1 || { echo "skip rv64_sweep: riscv64 toolchain absent"; exit 0; }
sweep_compiler "$ROOT" rv64_sweep || exit 1
sweep_scratch "$ROOT" rv64
CC="$SWEEP_CC"
corpus="$(sweep_corpus_size "$ROOT")"
echo "rv64_sweep: compiler=$CC corpus=$corpus scratch=$SWEEP_DIR jobs=$(sweep_jobs)"

## One corpus program. `$1` is this ROW's scratch prefix, `$2` the fixture, `$3` its x86_64 exit code.
## The order of operations carries the meaning: a failure of the COMPILER's emit is a WRONG (the
## compiler must never fail to produce text for a program x86_64 accepted), while a failure of `as` or
## `ld` is a `reject` — the assembler RAN and refused the text, the ELF never existed, nothing ran.
## Collapsing those two would turn every "could not run the assembler" into a miscompile finding.
rv64_verdict() { # scratch-prefix, name, want
  s="$1.s"; o="$1.o"; elf="$1.elf"
  "$CC" riscv64 "$ROOT/test/$2.al" > "$s" 2>"$s.err" < /dev/null \
    || { echo "WRONG riscv64 emit failed: $(head -3 "$s.err" | tr '\n' ' ')"; return; }
  riscv64-unknown-linux-gnu-as "$s" -o "$o" 2>/dev/null < /dev/null || { echo reject; return; }
  riscv64-unknown-linux-gnu-ld "$o" -o "$elf" 2>/dev/null < /dev/null || { echo reject; return; }
  timeout 10 qemu-riscv64 "$elf" >/dev/null 2>&1 < /dev/null; got=$?
  if [ "$got" = "$3" ]; then echo match
  elif [ "$got" -ge 128 ]; then echo trap
  else echo "WRONG riscv64=$got want=$3 (valid binary, normal exit, wrong = SILENT MISCOMPILE)"; fi
}

sweep_selftest rv64_sweep || exit 1

fail=0
sweep_run_corpus "$ROOT" rv64_sweep rv64_verdict || fail=1
## `wrong` separates the ONE forbidden verdict (a valid binary with a wrong exit code) from a harness
## failure such as a truncated corpus, so the closing banner never claims a miscompile that nobody saw.
wrong=0; [ "$SWEEP_WRONG" = 0 ] || wrong=1
echo "rv64_sweep: match=$SWEEP_MATCH trap=$SWEEP_TRAP reject=$SWEEP_REJECT missing=$SWEEP_MISSING corpus=$corpus"
sweep_check_total rv64_sweep "$SWEEP_SEEN" "$corpus" || fail=1
if [ "$fail" = 0 ]; then echo "*** rv64_sweep: no silent miscompiles ***"
elif [ "$wrong" = 1 ]; then echo "*** rv64_sweep: SILENT MISCOMPILE(S) FOUND ***"
else echo "*** rv64_sweep: FAILED — the sweep could not reach a verdict (see the FAIL line above); this is NOT a miscompile finding ***"; fi
exit "$fail"
