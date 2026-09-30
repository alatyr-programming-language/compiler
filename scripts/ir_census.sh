#!/usr/bin/env bash
# scripts/ir_census.sh — how much of the tree goes through the shared IR, and why the rest does not
# (`docs/ir.md` §7.1 rule 6; #683). REPORTING ONLY: it writes nothing, reads no oracle, and its exit
# status says only whether it could take the census, never whether the numbers are good.
#
# ## What it counts
#
# Every function the IR builder is handed, in three sets:
#
#   corpus   the functions DEFINED by each tracked `test/*.al` program (the manifest's `source_glob`; git's `*` crosses `/`, so package fixtures count too), one `alatyr ir <file>` per
#            program — the twins' front half (ambient `lib/` closure, reachability prune), so exactly
#            the functions a twin emitter would see. A reject fixture that `check` refuses reaches no
#            builder and is counted as `refused-by-check`, not as a function.
#   lib/     every function of every `lib/**/*.al` module, one `alatyr ir --modules` over the whole
#            library (no prune: a library function counts whether or not a program reaches it).
#   src/     every function of the compiler's own modules (`src/**/*.al`), the same way.
#
# For each set it prints how many functions go through the IR per target — the "first column" of each
# slice's claim — and the builder's `NotYet` reasons, ranked. In slice 0a the builder is
# target-independent and accepts nothing, so every target's column is 0 and every function has a
# reason; the per-target columns exist so the census keeps its shape when a selector starts taking
# functions on one target before another.
#
# A corpus program's functions are the lines whose module is the program's own (its file stem); the
# library functions the program pulled in are attributed to `lib/` by the separate library walk, so no
# function is counted twice.
#
# ## Usage
#
#   scripts/ir_census.sh [--jobs N] [--reasons N] [--quiet]
#     --jobs N     parallel `alatyr ir` invocations over the corpus (default 8)
#     --reasons N  how many ranked reasons to print per set (default 12; 0 = all)
#     --quiet      print only the summary table
#
# The compiler is `$ALATYR` if set, else this checkout's `target/debug/alatyr`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AL="${ALATYR:-$ROOT/target/debug/alatyr}"
JOBS=8
NREASONS=12
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --reasons) NREASONS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "usage: $0 [--jobs N] [--reasons N] [--quiet]" >&2; exit 2 ;;
  esac
done
[ -x "$AL" ] || { echo "ir_census: no compiler at $AL (build it first)" >&2; exit 2; }
ulimit -c 0
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# The verb must exist and prove itself before its numbers mean anything: a compiler without the
# builder, or one whose verifier refuses nothing, would print a census of nothing.
"$AL" ir --self-test > "$W/selftest" 2>&1
st_rc=$?
if [ "$st_rc" != 0 ] || ! grep -q '^ir self-test: [0-9]* passed, 0 failed$' "$W/selftest"; then
  echo "ir_census: \`alatyr ir --self-test\` failed (rc=$st_rc) — no census taken" >&2
  cat "$W/selftest" >&2
  exit 1
fi

# ---- corpus: one `alatyr ir <file>` per tracked program ----
git ls-files 'test/*.al' | sort -u > "$W/corpus.list"
ncorpus=$(wc -l < "$W/corpus.list" | tr -d ' ')
[ "$ncorpus" -gt 0 ] || { echo "ir_census: no corpus sources" >&2; exit 2; }
export AL W
one() {
  f="$1"
  key=$(printf '%s' "$f" | tr '/' '_')
  timeout 60 "$AL" ir "$f" > "$W/c.$key.out" 2>/dev/null
  echo "$? $f" > "$W/c.$key.rc"
}
export -f one
xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} < "$W/corpus.list"
: > "$W/corpus.fns"
refused=0
failed=0
while read -r f; do
  key=$(printf '%s' "$f" | tr '/' '_')
  read -r rc _ < "$W/c.$key.rc"
  if [ "$rc" = 0 ]; then
    stem=$(basename "$f" .al)
    # The program's own functions: module == its file stem, or a root package module named by path.
    grep -E "^fn (${stem}|[^ ]*${stem}\\.al)::" "$W/c.$key.out" | sed "s|^|$f	|" >> "$W/corpus.fns" || true
    grep -q '^ir: functions=' "$W/c.$key.out" || failed=$((failed + 1))
  elif [ "$rc" = 1 ] || [ "$rc" = 9 ]; then
    refused=$((refused + 1))
  else
    failed=$((failed + 1))
    echo "$f rc=$rc" >> "$W/corpus.failed"
  fi
done < "$W/corpus.list"

# ---- lib/ and src/: one raw-module walk each ----
git ls-files 'lib/*.al' 'lib/**/*.al' | sort -u > "$W/lib.list"
git ls-files 'src/*.al' 'src/**/*.al' | sort -u > "$W/src.list"
xargs "$AL" ir --modules < "$W/lib.list" > "$W/lib.out" 2> "$W/lib.err"
lib_rc=$?
xargs "$AL" ir --modules < "$W/src.list" > "$W/src.out" 2> "$W/src.err"
src_rc=$?
grep '^fn ' "$W/lib.out" > "$W/lib.fns" || true
grep '^fn ' "$W/src.out" > "$W/src.fns" || true

# A report line is `fn <module>::<name> NotYet(<construct>, <file>:<line>:<col>)`; its reason is
# the construct. A line without `NotYet(` would be a function the builder BUILT.
reasons() { sed -nE 's/.* NotYet\(([^,]*), .*/\1/p' "$1" | sort | uniq -c | sort -k1,1nr -k2; }
built() { grep -vc ' NotYet(' "$1" || true; }
total() { wc -l < "$1" | tr -d ' '; }

nc=$(total "$W/corpus.fns"); bc=$(built "$W/corpus.fns")
nl=$(total "$W/lib.fns");    bl=$(built "$W/lib.fns")
ns=$(total "$W/src.fns");    bs=$(built "$W/src.fns")

echo "ir census: functions handed to the shared IR builder, and how many it built (per target)"
printf '  %-10s %9s   %8s %8s %8s %8s\n' set functions x86_64 aarch64 riscv64 wasm
printf '  %-10s %9s   %8s %8s %8s %8s\n' corpus "$nc" "$bc" "$bc" "$bc" "$bc"
printf '  %-10s %9s   %8s %8s %8s %8s\n' lib/ "$nl" "$bl" "$bl" "$bl" "$bl"
printf '  %-10s %9s   %8s %8s %8s %8s\n' src/ "$ns" "$bs" "$bs" "$bs" "$bs"
echo "  corpus programs: $ncorpus (refused-by-check $refused, failed $failed); lib rc=$lib_rc src rc=$src_rc"
echo "  (slice 0a: the builder is target-independent and accepts no construct, so every column is 0)"
if [ -s "$W/corpus.failed" ]; then
  echo "  failed corpus runs:"; sed 's/^/    /' "$W/corpus.failed"
fi
if [ "$QUIET" = 0 ]; then
  for set in corpus lib src; do
    echo "NotYet reasons, $set (ranked):"
    if [ "$NREASONS" = 0 ]; then reasons "$W/$set.fns"; else reasons "$W/$set.fns" | head -n "$NREASONS"; fi | sed 's/^/  /'
  done
fi
[ "$failed" = 0 ] && [ "$lib_rc" = 0 ] && [ "$src_rc" = 0 ] || exit 1
exit 0
