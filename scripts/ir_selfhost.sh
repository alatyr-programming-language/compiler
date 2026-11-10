#!/usr/bin/env bash
# scripts/ir_selfhost.sh — the shared-IR SELF-HOST probe (#980 step 0, #1108).
#
# ## Why
#
# `scripts/e2e.sh` builds its Stage1 with the committed SEED. When `src/` changes how x86_64 is emitted
# (the IR flip, #1072: `X86_IR_SELECT` on by default), the seed still compiles the compiler with the old
# emitter, so e2e exercises the new emission only on USER programs. The compiler compiled THROUGH the
# new emission is first run after a promotion — which is how #1108 (the self-built flipped compiler
# crashing with SIGILL on char/split iterators) was found only at the promote gate. This script runs
# that measurement without a promotion and without touching `seed/alatyr`:
#
#   Stage1 = the seed builds the tree   (legacy-compiled code, emits with the tree's emitter)
#   Stage2 = Stage1 builds the tree     (compiled BY the tree's emitter: the compiler under the flip)
#   Stage3 = Stage2 builds the tree     (the reproducibility check of Stage2)
#
# and then, optionally, the e2e suite with Stage2 (or Stage1) as e2e's Stage1, through
# `ALATYR_E2E_REBUILD=stale` — e2e keeps a fresh `target/debug/alatyr` instead of rebuilding it.
#
# ## Usage (native x86_64 Linux, inside `nix develop`; the seed is a static x86_64 binary)
#
#   scripts/ir_selfhost.sh [--e2e-stage 1|2|3|none] [--filter SUB]
#     --e2e-stage N  which stage runs the e2e table as its Stage1 (default 2: the self-compiled one);
#                    `none` stops after the stages
#     --filter SUB   passed to e2e as ALATYR_E2E_FILTER (iteration; a filtered run is not a gate)
#
# Stages are kept as target/ir_stage{1,2,3} (beside target/debug/: a compiler finds ../lib relative to
# itself), their GAS and build logs under target/ir_selfhost/. Exit 0 = every stage built, Stage1 ==
# Stage2 == Stage3 in normalized GAS, Stage2 == Stage3 in the binary, and the e2e run (if any) is green.
# Measurement only: it never writes seed/, package.al or an oracle, and a green run is not a gate.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
E2E_STAGE=2
FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --e2e-stage) E2E_STAGE="${2:-}"; shift 2 ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d'; exit 0 ;;
    *) echo "ir_selfhost: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$E2E_STAGE" in 1|2|3|none) ;; *) echo "ir_selfhost: --e2e-stage takes 1, 2, 3 or none" >&2; exit 2 ;; esac
[ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] || { echo "ir_selfhost: run on native x86_64 Linux (the seed is a static x86_64 binary)" >&2; exit 2; }
ulimit -c 0

M="$ROOT/package.al"   # absolute: the tree compiler's emit form refuses a relative manifest
O="$ROOT/target/ir_selfhost"
rm -rf "$O"; mkdir -p "$O"
## the same normalization as scripts/promote.sh (`.Lra` first: it is also a `.L`)
normalize_gas() { sed -E -e 's/\.Lra[0-9]+_[0-9]+/.LraN_K/g' -e 's/\.L[0-9]+/.LN/g'; }
same_gas() { cmp -s <(normalize_gas < "$1") <(normalize_gas < "$2"); }
verdict() { if "$@"; then echo SAME; else echo DIFFER; fi; }

"$ROOT/seed/alatyr" "$M" > "$O/gas_seed.s" 2> "$O/gas_seed.err"
echo "ir_selfhost: base $(git rev-parse --short HEAD) seed_gas=$(wc -l < "$O/gas_seed.s") lines"
cc="$ROOT/seed/alatyr"; built=0; bad=0
for n in 1 2 3; do
  rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"
  t0=$(date +%s)
  "$cc" build "$M" > "$O/build$n.log" 2>&1; rc=$?
  t1=$(date +%s)
  if [ "$rc" != 0 ] || [ ! -x "$ROOT/target/debug/alatyr" ]; then
    echo "ir_selfhost: Stage$n build FAILED rc=$rc (built by $(basename "$cc")) — see $O/build$n.log"
    tail -5 "$O/build$n.log" | sed 's/^/    /'
    bad=1; break
  fi
  cp "$ROOT/target/debug/alatyr" "$ROOT/target/ir_stage$n"
  "$ROOT/target/ir_stage$n" "$M" > "$O/gas$n.s" 2> "$O/gas$n.err"; grc=$?
  echo "ir_selfhost: Stage$n built in $((t1 - t0))s by $(basename "$cc"); gas rc=$grc lines=$(wc -l < "$O/gas$n.s") ir-selected=$(grep -c '^# ir: selected from the shared IR$' "$O/gas$n.s") sha256=$(sha256sum < "$ROOT/target/ir_stage$n" | cut -c1-16)"
  [ "$grc" = 0 ] && [ -s "$O/gas$n.s" ] || { echo "ir_selfhost: Stage$n did not emit the tree's GAS"; bad=1; break; }
  built=$n; cc="$ROOT/target/ir_stage$n"
done
[ "$built" -ge 1 ] && echo "ir_selfhost: seed vs Stage1 GAS (normalized): $(verdict same_gas "$O/gas_seed.s" "$O/gas1.s")"
[ "$built" -ge 2 ] && echo "ir_selfhost: Stage1 vs Stage2 GAS (normalized): $(verdict same_gas "$O/gas1.s" "$O/gas2.s")"
if [ "$built" -ge 3 ]; then
  echo "ir_selfhost: Stage2 vs Stage3 GAS (normalized): $(verdict same_gas "$O/gas2.s" "$O/gas3.s")"
  echo "ir_selfhost: Stage2 vs Stage3 binary: $(verdict cmp -s "$ROOT/target/ir_stage2" "$ROOT/target/ir_stage3")"
  same_gas "$O/gas1.s" "$O/gas2.s" && same_gas "$O/gas2.s" "$O/gas3.s" && cmp -s "$ROOT/target/ir_stage2" "$ROOT/target/ir_stage3" || bad=1
fi
if [ "$built" -ge 2 ]; then
  printf 'main := fn() -> u64 { return 7 + 35 }\n' > "$O/smoke.al"
  "$ROOT/target/ir_stage2" -o "$O/smoke" "$O/smoke.al" > /dev/null 2>&1; "$O/smoke"; sm=$?
  echo "ir_selfhost: Stage2 smoke = $sm (want 42)"; [ "$sm" = 42 ] || bad=1
fi
[ -s "$O/gas_seed.s" ] && [ -s "$O/gas1.s" ] && diff -U0 <(normalize_gas < "$O/gas_seed.s") <(normalize_gas < "$O/gas1.s") > "$O/delta_seed_stage1.diff"
[ -s "$O/gas2.s" ] && diff -U0 <(normalize_gas < "$O/gas1.s") <(normalize_gas < "$O/gas2.s") > "$O/delta_stage1_stage2.diff"
echo "ir_selfhost: stages built=$built/3 verdict=$([ "$bad" = 0 ] && echo CONVERGED || echo NOT-CONVERGED)"

if [ "$E2E_STAGE" != none ]; then
  if [ "$built" -lt "$E2E_STAGE" ]; then
    echo "ir_selfhost: e2e NOT RUN — Stage$E2E_STAGE was not built"; exit 1
  fi
  cp "$ROOT/target/ir_stage$E2E_STAGE" "$ROOT/target/debug/alatyr"
  echo "ir_selfhost: e2e with Stage$E2E_STAGE as Stage1 ($(sha256sum < "$ROOT/target/debug/alatyr" | cut -c1-16)) filter='$FILTER'"
  ALATYR_E2E_REBUILD=stale ALATYR_E2E_FILTER="$FILTER" bash scripts/e2e.sh > "$O/e2e_stage$E2E_STAGE.log" 2>&1; erc=$?
  cmp -s "$ROOT/target/debug/alatyr" "$ROOT/target/ir_stage$E2E_STAGE" \
    || { echo "ir_selfhost: e2e REBUILT its Stage1 (the stage was older than src/ or lib/); the run is not of Stage$E2E_STAGE"; bad=1; }
  grep -E '^FAIL ' "$O/e2e_stage$E2E_STAGE.log" | head -60
  grep -E '^\*\*\* e2e: (rows=|all green|FAILURES)' "$O/e2e_stage$E2E_STAGE.log"
  [ "$erc" = 0 ] || bad=1
fi
exit "$bad"
