#!/usr/bin/env bash
# Measure one AST-list migration step (docs/ast-option-migration.md). Run inside `nix develop`, from the
# root of the worktree that holds the migrated tree, on a native x86_64 machine.
#
#   bash scripts/ast_option_measure.sh <tree-compiler> <base-ref> [--e2e]
#
# <tree-compiler>  an alatyr binary built from the BASE tree (or any tree that has every compiler fix the
#                  migrated source needs) — used instead of seed/alatyr when the frozen seed cannot build
#                  the migrated source yet. It must sit in a repository layout (its `lib/` next to it).
# <base-ref>       the commit the step is measured against (the parent PR's head).
#
# Prints: the self-build fixpoint on the migrated tree (Stage1' GAS == Stage2' GAS, Stage2 == Stage3
# binaries), whether codegen is unchanged (the base compiler emits the same GAS for this tree as the
# tree's own compiler), the strict-forms census delta (lexical + typed: null-explicit, typed null,
# implicit OP-CMP, unchecked), the GAS delta of the compiler's own source against the base tree
# (hunks, functions touched, per module), whether the frozen seed accepts the tree, and optionally e2e.
set -u
CC0="$1"; BASE="$2"; E2E="${3:-}"
# absolute: the base-tree GAS below is emitted from a temporary directory
case "$CC0" in /*) ;; *) CC0="$PWD/$CC0" ;; esac
ulimit -c 0
mkdir -p target
"$CC0" build package.al >/dev/null 2>target/am_build0.err || { echo "FAIL: the tree compiler cannot build this tree:"; head -c 600 target/am_build0.err; exit 1; }
cp target/debug/alatyr target/am_s1
./target/am_s1 package.al > target/am_gas1.s 2>/dev/null
./target/am_s1 build package.al >/dev/null 2>&1 || { echo "FAIL: Stage1' cannot rebuild the tree"; exit 1; }
cp target/debug/alatyr target/am_s2
./target/am_s2 package.al > target/am_gas2.s 2>/dev/null
if cmp -s target/am_gas1.s target/am_gas2.s; then echo "fixpoint: Stage1' GAS == Stage2' GAS ($(wc -l < target/am_gas1.s) lines)"; else echo "FIXPOINT MISMATCH"; fi
./target/am_s2 build package.al >/dev/null 2>&1
if cmp -s target/debug/alatyr target/am_s2; then echo "fixpoint: Stage2 == Stage3 binaries"; else echo "BINARY MISMATCH Stage2 != Stage3"; fi
"$CC0" package.al > target/am_gas_cc0.s 2>/dev/null
if cmp -s target/am_gas_cc0.s target/am_gas1.s; then echo "codegen unchanged: the base compiler emits the same GAS for this tree"; else echo "CODEGEN CHANGED: the base compiler and this tree's compiler disagree on this tree"; fi
ALATYR_STRICT_BASE="$BASE" bash scripts/strict_forms_check.sh 2>&1 | grep "^strict forms: base="
ALATYR_STRICT_BASE="$BASE" bash scripts/strict_forms_check.sh --typed 2>&1 | grep "^strict forms typed: base="
# GAS delta of the compiler's own source (same compiler, base tree vs this tree; local labels normalized)
W="$(mktemp -d)"
git archive "$BASE" | tar -x -C "$W"
( cd "$W" && "$CC0" package.al > "$W/base.s" 2>/dev/null )
norm() { sed -E 's/\.L[a-z]*[0-9]+(_[0-9]+)?/.LN/g' "$1"; }
norm "$W/base.s" > "$W/b.n"; norm target/am_gas1.s > "$W/p.n"
diff "$W/b.n" "$W/p.n" > "$W/d.diff"
echo "own-GAS delta: hunks $(grep -c '^[0-9]' "$W/d.diff") removed $(grep -c '^<' "$W/d.diff") added $(grep -c '^>' "$W/d.diff")"
awk '/^[a-zA-Z_][a-zA-Z0-9_]*:$/ {f=$0} {print f}' "$W/p.n" > "$W/p.fn"
grep '^[0-9]' "$W/d.diff" | sed -E 's/^[0-9,]+[acd]([0-9]+).*/\1/' > "$W/hl"
awk 'NR==FNR{want[$1]=1;next} (FNR in want){print}' "$W/hl" "$W/p.fn" | sort -u > "$W/fn"
echo "functions touched: $(wc -l < "$W/fn") (labels base=$(grep -c '^[a-zA-Z_][a-zA-Z0-9_]*:$' "$W/b.n") tree=$(grep -c '^[a-zA-Z_][a-zA-Z0-9_]*:$' "$W/p.n"))"
echo "per module: $(sed 's/:$//' "$W/fn" | awk -F__ '{print $1}' | sort | uniq -c | sort -rn | tr -s ' ' | tr '\n' ' ')"
rm -rf "$W"
if ./seed/alatyr package.al > /dev/null 2>target/am_seed.err; then echo "seed: the frozen seed accepts this tree"; else echo "seed: the frozen seed REFUSES this tree: $(tail -c 240 target/am_seed.err)"; fi
if [ "$E2E" = --e2e ]; then
  touch target/debug/alatyr
  ALATYR_E2E_REBUILD=stale bash scripts/e2e.sh > target/am_e2e.log 2>&1
  grep -E '^\*\*\* e2e|^FAIL' target/am_e2e.log | head -20
fi
