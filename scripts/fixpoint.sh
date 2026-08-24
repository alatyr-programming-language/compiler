#!/usr/bin/env bash
# scripts/fixpoint.sh — the TOOL-1 reproducible-build check for the self-hosted Alatyr compiler.
#
#   seed     = seed/alatyr  (a FROZEN, static self-host binary — the bootstrap)
#   Stage1   = target/debug/alatyr (the seed builds the tree under the debug profile)
#   Stage2   = Stage1 builds the tree again
#   FIXPOINT <=>  seed, Stage1, Stage2 all emit BYTE-IDENTICAL GAS for the tree
#
# It also asserts the committed seed is CURRENT (its emission == Stage1's — i.e. seed/ matches src/)
# and that a self-built compiler builds + links + runs an arbitrary program standalone (no seed at
# runtime). Run inside the dev shell (`nix develop`) so `as`/`ld` are on PATH.  Exit 0 = fixpoint.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
SEED="$ROOT/seed/alatyr"
M="$ROOT/package.al"
[ -x "$SEED" ] || { echo "FAIL: no seed at $SEED"; exit 1; }
mkdir -p target
## Do not let a compiler from a previous self-build satisfy the seed-stage assertion after the
## layout transition. The frozen seed must itself create the profile path; remove only that exact
## compiler-under-test artifact, never package fixture or gate scratch trees.
rm -f "$ROOT/target/alatyr" "$ROOT/target/alatyr.s" "$ROOT/target/alatyr.o"
rm -f "$ROOT/target/debug/alatyr" "$ROOT/target/debug/alatyr.s" "$ROOT/target/debug/alatyr.o"
step() { printf '=== %s ===\n' "$1"; }

step "Stage1 — the committed seed builds the tree (alatyr build) -> target/debug/alatyr or legacy target/alatyr"
SEED_LOG="$ROOT/target/fixpoint_seedbuild.log"
"$SEED" build "$M" >"$SEED_LOG" 2>&1
seed_rc=$?
tail -1 "$SEED_LOG"
[ "$seed_rc" = 0 ] || { echo "FAIL: seed build (rc=$seed_rc)"; exit 2; }
if [ -x "$ROOT/target/debug/alatyr" ]; then
  STAGE1="$ROOT/target/debug/alatyr"
else
  STAGE1="$ROOT/target/alatyr"
  [ -x "$STAGE1" ] || { echo "FAIL: seed did not create target/debug/alatyr or legacy target/alatyr"; exit 2; }
  echo "bootstrap transition: frozen seed used legacy target/alatyr; fixpoint comparison remains authoritative"
fi
cp "$STAGE1" "$ROOT/target/stage1"

step "gas — the seed and Stage1 emit the tree's GAS"
"$SEED" "$M" > target/gas_seed.s 2>/dev/null
"$ROOT/target/stage1" "$M" > target/gas1.s 2>/dev/null
echo "seed=$(wc -l < target/gas_seed.s) stage1=$(wc -l < target/gas1.s) lines"

step "Stage2 — Stage1 builds the tree -> target/debug/alatyr (then emits GAS)"
"$ROOT/target/stage1" build "$M" >/dev/null 2>&1
STAGE2="$ROOT/target/debug/alatyr"
[ -x "$STAGE2" ] || { echo "FAIL: Stage1 did not build target/debug/alatyr"; exit 3; }
cp "$STAGE2" "$ROOT/target/stage2"
"$ROOT/target/stage2" "$M" > target/gas2.s 2>/dev/null
echo "stage2=$(wc -l < target/gas2.s) lines"

step "self-sufficiency — Stage1 builds+links+runs an arbitrary program (no seed at runtime)"
printf 'main := fn() -> u64 { return 7 + 35 }\n' > target/smoke.al
"$ROOT/target/stage1" -o target/smoke.out "$ROOT/target/smoke.al" 2>/dev/null
"$ROOT/target/smoke.out" 2>/dev/null; sc=$?
[ "$sc" = 42 ] || { echo "FAIL: self-built compiler standalone (smoke exit=$sc, want 42)"; exit 5; }
echo "smoke = $sc (self-built compiler builds standalone)"

step "fixpoint"
if [ -s target/gas1.s ] && diff -q target/gas1.s target/gas2.s >/dev/null 2>&1 && diff -q target/gas_seed.s target/gas1.s >/dev/null 2>&1; then
  echo "*** TOOL-1 FIXPOINT: seed == Stage1 == Stage2 ($(wc -l < target/gas1.s) lines); self-built compiler builds standalone ***"
  exit 0
fi
echo "DIFFER: seed=$(wc -l<target/gas_seed.s) gas1=$(wc -l<target/gas1.s) gas2=$(wc -l<target/gas2.s)"
echo "  (seed != Stage1 means the committed seed/alatyr is STALE vs src/. The recovery is a SELF-PROMOTE,"
echo "   not a rebuild from the frozen Rust ancestor — that ancestor can no longer parse the current src/."
echo "   Build Stage1, let it build Stage2 and Stage3, require Stage1 == Stage2 == Stage3 in both the GAS"
echo "   and the binary, read the seed->Stage1 GAS delta line by line, then copy Stage1 over seed/alatyr and"
echo "   append the evidence to seed/VERSION. Normalize .L<N> and .Lra<N>_<k> before reading that delta.)"
exit 4
