#!/usr/bin/env bash
# scripts/pre_gate.sh — the lane's pre-gate: the part of the full gate a change can reach, in minutes (#1128).
#
# ## Why
#
# A lane had two choices: `scripts/dev.sh`, fast but blind to the corpus and the sweeps, or
# `scripts/full.sh`, ~50-60 min on omen and ~2 h on the GitHub runner. A red result was therefore
# usually found in the integrator's queue, not in the lane. This script runs, against one Stage1, the
# e2e rows and the backend sweeps the change can reach, and then NAMES every full-gate stage it did not
# run. It is never a verdict: a green pre-gate means "worth a full gate", and only `full.sh` lands.
#
# ## What it picks, from the files changed since <base> (committed, staged, unstaged and untracked)
#
# - every e2e row, when the compiler can change: any `src/` file, `package.al`, or `scripts/e2e.sh`
#   (the table itself). A compiler function is not named by any fixture, so no narrower choice is
#   sound;
# - otherwise the rows that mention a selected fixture: every changed `test/**.al`, and every fixture
#   that names a changed `lib/` module (`std::<module>`) or a function whose definition a hunk touches;
#   past ALATYR_PRE_GATE_MAX_FIXTURES (400) selected fixtures it runs every row instead;
# - the sweep of each backend whose emitter changed (`src/aarch64*` a64, `src/riscv64*` rv64,
#   `src/wat*` wasm); all three for any other compiler change except the x86-only emit files that
#   scripts/sweeps.sh also exempts; none for a `lib/`- or `test/`-only change (the full gate runs them).
#
# ## Usage (inside `nix develop`, on omen for the timing target of < 5 min)
#
#   bash scripts/pre_gate.sh [<base>]   base defaults to `git merge-base HEAD origin/main`
#   bash scripts/pre_gate.sh --plan [<base>]   print the plan and run nothing
#   bash scripts/pre_gate.sh --self-test       the planner, on planted change sets
#
# Output: the plan, each stage's own output, then `pre-gate: GREEN|RED ran=<stages> not-run=<stages>`.
# Exit 0 green, 1 red, 2 could not run. Logs go to target/pre_gate/, never a shared path.
set -u
ulimit -c 0 2>/dev/null || true
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PG_X86_ONLY="src/lower.al src/regalloc.al src/lower_asm.al"   # = scripts/sweeps.sh X86_ONLY
PG_MAX="${ALATYR_PRE_GATE_MAX_FIXTURES:-400}"

## The planner, pure: changed paths on stdin, one per line. Prints `e2e all|rows|none` and one
## `sweep <name>` line per sweep, in a64 rv64 wasm order.
pre_gate_plan() {
  local f e2e=none a64=0 rv64=0 wasm=0 x86only
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      src/aarch64.al|src/aarch64/*) e2e=all; a64=1 ;;
      src/riscv64.al|src/riscv64/*) e2e=all; rv64=1 ;;
      src/wat.al|src/wat/*) e2e=all; wasm=1 ;;
      src/*|package.al)
        e2e=all; x86only=0
        for w in $PG_X86_ONLY; do [ "$f" = "$w" ] && x86only=1; done
        [ "$x86only" = 1 ] || { a64=1; rv64=1; wasm=1; } ;;
      scripts/e2e.sh) e2e=all ;;
      test/*.al|lib/*.al) [ "$e2e" = all ] || e2e=rows ;;
    esac
  done
  echo "e2e $e2e"
  [ "$a64" = 0 ] || echo "sweep a64"
  [ "$rv64" = 0 ] || echo "sweep rv64"
  [ "$wasm" = 0 ] || echo "sweep wasm"
}

## The fixtures a `test/`/`lib/` change selects, as e2e row substrings (path under test/, no `.al`).
## $1 base; changed paths on stdin.
pre_gate_fixtures() {
  local base="$1" f names=() mods=() n
  while IFS= read -r f; do
    case "$f" in
      test/*.al) [ -f "$ROOT/$f" ] && { n="${f#test/}"; echo "${n%.al}"; } ;;
      lib/*.al)
        mods+=("$(basename "$f" .al)")
        # the function each hunk sits in (git's hunk header) and every definition a hunk adds or drops
        while IFS= read -r n; do names+=("$n"); done < <(
          { git -C "$ROOT" diff -U0 "$base" -- "$f" | sed -nE 's/^@@ [^@]* @@ (pub )?([A-Za-z_][A-Za-z0-9_]*) *:=.*/\2/p'
            git -C "$ROOT" diff -U0 "$base" -- "$f" | sed -nE 's/^[-+](pub )?([A-Za-z_][A-Za-z0-9_]*) *:= *(@[a-z(),]+ *)?fn.*/\2/p'
          } | sort -u) ;;
    esac
  done
  [ "${#mods[@]}" -gt 0 ] || return 0
  local pat="" m
  for m in "${mods[@]}"; do pat="$pat|std::$m\\b"; done
  for m in "${names[@]}"; do pat="$pat|\\b$m\\b"; done
  git -C "$ROOT" grep -lE "${pat#|}" -- 'test/*.al' 'test/**/*.al' 2>/dev/null |
    sed -e 's#^test/##' -e 's#\.al$##' | sort -u
}

## All changed paths since $1: committed, staged, unstaged, untracked.
pre_gate_changed() {
  { git -C "$ROOT" diff --name-only "$1"
    git -C "$ROOT" ls-files --others --exclude-standard; } | sort -u
}

pre_gate_self_test() {
  local bad=0 got want
  t() { got="$(printf '%s\n' $2 | pre_gate_plan | tr '\n' ' ')"; want="$3"
        if [ "$got" = "$want" ]; then echo "  ok   $1"; else echo "  FAIL $1: got '$got' want '$want'"; bad=1; fi; }
  t 'docs only: nothing to run' 'README.md docs/x.md' 'e2e none '
  t 'a fixture: its rows, no sweep' 'test/foo.al' 'e2e rows '
  t 'a lib module: rows, no sweep' 'lib/std/io.al' 'e2e rows '
  t 'the riscv64 emitter: all rows + its sweep' 'src/riscv64.al' 'e2e all sweep rv64 '
  t 'an aarch64 sub-file: all rows + its sweep' 'src/aarch64/emit.al' 'e2e all sweep a64 '
  t 'the wat emitter + a fixture' 'test/foo.al src/wat.al' 'e2e all sweep wasm '
  t 'x86-only emit file: all rows, no sweep' 'src/lower.al' 'e2e all '
  t 'front end: all rows + every sweep' 'src/sema.al' 'e2e all sweep a64 sweep rv64 sweep wasm '
  t 'the e2e table: all rows' 'scripts/e2e.sh' 'e2e all '
  t 'package.al: everything' 'package.al' 'e2e all sweep a64 sweep rv64 sweep wasm '
  t 'a rows-change after an all-change stays all' 'src/lower.al test/x.al' 'e2e all '
  echo "pre_gate self-test: $([ "$bad" = 0 ] && echo PASS || echo FAIL)"
  return "$bad"
}

mode=run
case "${1:-}" in
  --self-test) pre_gate_self_test; exit $? ;;
  --plan) mode=plan; shift ;;
esac
cd "$ROOT" || exit 2
base="${1:-}"
if [ -z "$base" ]; then
  base="$(git merge-base HEAD origin/main 2>/dev/null)" || { echo "pre-gate: no merge-base with origin/main; pass <base>"; exit 2; }
fi
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "pre-gate: base '$base' does not resolve"; exit 2; }

LOG="$ROOT/target/pre_gate"; rm -rf "$LOG"; mkdir -p "$LOG"
pre_gate_changed "$base" > "$LOG/changed"
plan="$(pre_gate_plan < "$LOG/changed")"
e2e="$(printf '%s\n' "$plan" | sed -n 's/^e2e //p')"
sweeps="$(printf '%s\n' "$plan" | sed -n 's/^sweep //p' | tr '\n' ' ')"
if [ "$e2e" = rows ]; then
  pre_gate_fixtures "$base" < "$LOG/changed" > "$LOG/fixtures"
  nf="$(grep -c '' "$LOG/fixtures")"
  if [ "$nf" -gt "$PG_MAX" ]; then e2e=all; echo "pre-gate: $nf fixtures selected (> $PG_MAX): every row"
  elif [ "$nf" = 0 ]; then e2e=none; fi
fi
echo "pre-gate: base $(git rev-parse --short "$base"), $(grep -c '' "$LOG/changed") changed path(s)"
echo "pre-gate: plan e2e=$e2e$([ "$e2e" = rows ] && echo " ($(grep -c '' "$LOG/fixtures") fixtures: $(head -8 "$LOG/fixtures" | tr '\n' ' ')…)") sweeps=${sweeps:-none}"
[ "$mode" = run ] || exit 0

ran=(); red=()
s0=$(date +%s)
echo "### STAGE1 ###"
# The seed build is single-threaded and dominates the pre-gate: measured 431 s on omen at load 4-7
# (2026-10-30). Stage1 is a function of src/, package.al and the seed alone (the stdlib is read from the
# tree at run time: e2e links lib/ beside its compiler snapshot), so a Stage1 built from the same bytes
# is reused. The cache is this worktree's own (target/pre_gate_cache/), keyed by the content of those
# inputs, uncommitted edits included.
key="$( { find src -type f | sort | xargs sha256sum; sha256sum package.al seed/alatyr; } | sha256sum | cut -c1-16)"
CACHE="$ROOT/target/pre_gate_cache/$key"
if [ -x "$CACHE/alatyr" ]; then
  mkdir -p target/debug && cp "$CACHE/alatyr" target/debug/alatyr
  echo "  Stage1 reused from target/pre_gate_cache/$key (same src/, package.al, seed)"
  ran+=(stage1:cached)
else
  rm -f target/debug/alatyr
  if ! ./seed/alatyr build package.al > "$LOG/stage1.log" 2>&1 || [ ! -x target/debug/alatyr ]; then
    tail -20 "$LOG/stage1.log"; echo "pre-gate: RED ran=stage1 (the seed could not build the tree)"; exit 1
  fi
  rm -rf "$ROOT/target/pre_gate_cache"; mkdir -p "$CACHE" && cp target/debug/alatyr "$CACHE/alatyr"
  ran+=(stage1)
fi
if [ "$e2e" != none ]; then
  echo "### E2E ($e2e) ###"
  if [ "$e2e" = rows ]; then
    ALATYR_E2E_REBUILD=stale ALATYR_E2E_FILTER_FILE="$LOG/fixtures" bash scripts/e2e.sh > "$LOG/e2e.log" 2>&1
  else
    ALATYR_E2E_REBUILD=stale bash scripts/e2e.sh > "$LOG/e2e.log" 2>&1
  fi
  rc=$?
  grep -E '^(FAIL|\*\*\* e2e)' "$LOG/e2e.log" | head -30
  ran+=("e2e:$e2e"); [ "$rc" = 0 ] || red+=(e2e)
fi
for s in $sweeps; do
  echo "### SWEEP $s ###"
  ALATYR_SWEEP_CC="$ROOT/target/debug/alatyr" bash "scripts/${s}_sweep.sh" > "$LOG/$s.log" 2>&1
  rc=$?
  grep -E '^(WRONG|FAIL|.*sweep.*(match|wrong|PASS|FAIL))' "$LOG/$s.log" | tail -8
  ran+=("sweep:$s"); [ "$rc" = 0 ] || red+=("sweep:$s")
done
# Every full-gate stage, by its own heading, less the two this script covers: the list cannot go stale.
not_run="$(sed -nE 's/^echo "### ([A-Z0-9 -]+[A-Z0-9]).*/\1/p' scripts/full.sh | grep -vxE 'E2E|SWEEPS' |
  sed 's/ /_/g' | tr '\n' ' ')"
[ "$e2e" = all ] || not_run="E2E(rest) $not_run"
for s in a64 rv64 wasm; do case " $sweeps " in *" $s "*) ;; *) not_run="sweep:$s $not_run" ;; esac; done
verdict=GREEN; [ "${#red[@]}" = 0 ] || verdict=RED
echo "pre-gate: $verdict in $(( $(date +%s) - s0 ))s ran=${ran[*]} red=${red[*]:-none}"
echo "pre-gate: NOT RUN (the full gate runs them): $not_run"
[ "$verdict" = GREEN ]
