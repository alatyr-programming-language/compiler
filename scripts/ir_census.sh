#!/usr/bin/env bash
# scripts/ir_census.sh — how much of the tree goes through the shared IR, why the rest does not, and
# whether the IR verifier accepts every function the builder builds (`docs/ir.md` §5, §7.1 rule 6;
# #683, `docs/ir-slice-1.md` §5.2).
#
# ## What it counts
#
# Every function the IR builder is handed, in three sets:
#
#   corpus   the functions DEFINED by each tracked `test/*.al` program (the manifest's `source_glob`; git's
#            `*` crosses `/`, so package fixtures count too), one `alatyr ir <file>` per program — the
#            twins' front half (ambient `lib/` closure, reachability prune), so exactly the functions a
#            twin emitter would see. A reject fixture that `check` refuses reaches no builder and is
#            counted as `refused-by-check`, not as a function.
#   lib/     every function of every `lib/**/*.al` module, one `alatyr ir --modules` over the whole
#            library (no prune: a library function counts whether or not a program reaches it).
#   src/     every function of the compiler's own modules (`src/**/*.al`), the same way.
#
# Each function's report line is one of
#   fn <module>::<name> Built                                    (then its verified IR, indented)
#   fn <module>::<name> NotYet(<construct>, <file>:<line>:<col>)  outside slice 1's subset
#   fn <module>::<name> NotYet(sema-gap <class>: <construct>, …)  sema left a value the builder needs
#                                                                 untyped (owner decision D6: counted,
#                                                                 never defaulted)
#   fn <module>::<name> VerifyFailed(<rule> at inst <n>)         the verifier refused a built function
# For each set the census prints the functions, how many were built, the NotYet split into "outside the
# subset" and "sema gaps", and the verifier refusals; then both kinds of reason, ranked. The builder is
# target-independent and no selector consumes a built function before slice 1c, so there is one "built"
# column; the per-target columns arrive with the selectors.
#
# A corpus program's functions are the lines whose module is the program's own (its file stem); the
# library functions the program pulled in are attributed to `lib/` by the separate library walk, so no
# function is counted twice.
#
# ## The verifier gate (`--gate`)
#
# Without `--gate` the census is REPORTING ONLY: its exit status says only whether it could take the
# census. With `--gate` it is the full gate's IR stage: it fails when the verifier refused ANY built
# function in any set (a `VerifyFailed` line, or the verb's internal-error exit 70), or when any
# `alatyr ir` run crashed, timed out or printed no summary. A verifier refusal is a located internal
# error (`docs/ir.md` §5), so it must stop the gate rather than become a census number.
#
# `--self-test` proves the decision is live without a compiler: it feeds the analysis planted report
# directories — a clean one that must pass, and one per failure class that must fail by name.
#
# ## Usage
#
#   scripts/ir_census.sh [--gate] [--jobs N] [--reasons N] [--quiet]
#   scripts/ir_census.sh --self-test
#     --gate       fail on any verifier refusal or failed run (the full gate's IR stage)
#     --jobs N     parallel `alatyr ir` invocations over the corpus (default 8)
#     --reasons N  how many ranked reasons to print per set and kind (default 12; 0 = all)
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
GATE=0
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --gate) GATE=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --reasons) NREASONS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "usage: $0 [--gate] [--jobs N] [--reasons N] [--quiet] | --self-test" >&2; exit 2 ;;
  esac
done
ulimit -c 0

# A report line's verdict, and its reason (the construct, after an optional `sema-gap <class>: `).
outside() { sed -nE 's/^[^ ]+	fn [^ ]+ NotYet\(([^,]*), .*/\1/p' "$1" | grep -v '^sema-gap ' || true; }
gaps() { sed -nE 's/^[^ ]+	fn [^ ]+ NotYet\((sema-gap [^,]*), .*/\1/p' "$1" || true; }
count_re() { grep -cE "$2" "$1" || true; }
ranked() {
  if [ "$NREASONS" = 0 ]; then sort | uniq -c | sort -k1,1nr -k2; else sort | uniq -c | sort -k1,1nr -k2 | head -n "$NREASONS"; fi
}

# analyse <dir> — read a collected census from <dir> (corpus.list, c.<key>.out/.rc, lib.out/.rc,
# src.out/.rc), print it, and answer 0 when the census was taken (and, under --gate, when nothing
# failed), 1 otherwise. Every `<set>.fns` line is `<source>\t<report line>`.
analyse() {
  local W="$1" f key rc stem refused=0 failed=0 vruns=0 ncorpus set nf nb nn ng nv bad=0
  : > "$W/corpus.fns"; : > "$W/corpus.failed"
  ncorpus=$(wc -l < "$W/corpus.list" | tr -d ' ')
  while read -r f; do
    key=$(printf '%s' "$f" | tr '/' '_')
    rc=missing
    [ -f "$W/c.$key.rc" ] && read -r rc _ < "$W/c.$key.rc"
    if [ "$rc" = 0 ] || [ "$rc" = 70 ]; then
      stem=$(basename "$f" .al)
      # The program's own functions: module == its file stem, or a root package module named by path.
      grep -E "^fn (${stem}|[^ ]*${stem}\\.al)::" "$W/c.$key.out" | sed "s|^|$f	|" >> "$W/corpus.fns" || true
      if ! grep -q '^ir: functions=' "$W/c.$key.out"; then
        failed=$((failed + 1)); echo "$f rc=$rc (no summary line)" >> "$W/corpus.failed"
      elif [ "$rc" = 70 ]; then
        # The verb's internal-error exit: a verifier refusal, in the program's own functions or in a
        # library function it pulled in (that line is not the program's, but the run still fails).
        vruns=$((vruns + 1)); echo "$f rc=70 (a verifier refusal)" >> "$W/corpus.failed"
      fi
    elif [ "$rc" = 1 ] || [ "$rc" = 9 ]; then
      refused=$((refused + 1))
    else
      failed=$((failed + 1)); echo "$f rc=$rc" >> "$W/corpus.failed"
    fi
  done < "$W/corpus.list"
  local lib_rc src_rc
  read -r lib_rc _ < "$W/lib.rc"; read -r src_rc _ < "$W/src.rc"
  for set in lib src; do
    grep '^fn ' "$W/$set.out" | sed "s|^|$set/	|" > "$W/$set.fns" || true
  done

  echo "ir census: functions handed to the shared IR builder; every built one is verified (docs/ir.md §5)"
  printf '  %-8s %9s %8s %8s %10s %10s %14s\n' set functions built notyet "(outside" "sema-gap)" verify-failed
  for set in corpus lib src; do
    nf=$(wc -l < "$W/$set.fns" | tr -d ' ')
    nb=$(count_re "$W/$set.fns" '	fn [^ ]+ Built$')
    nn=$(count_re "$W/$set.fns" '	fn [^ ]+ NotYet\(')
    ng=$(count_re "$W/$set.fns" '	fn [^ ]+ NotYet\(sema-gap ')
    nv=$(count_re "$W/$set.fns" '	fn [^ ]+ VerifyFailed\(')
    bad=$((bad + nv))
    local lbl="$set/"; [ "$set" = corpus ] && lbl=corpus
    printf '  %-8s %9s %8s %8s %10s %10s %14s\n' "$lbl" "$nf" "$nb" "$nn" "$((nn - ng))" "$ng" "$nv"
  done
  echo "  corpus programs: $ncorpus (refused-by-check $refused, failed $failed); lib rc=$lib_rc src rc=$src_rc"
  echo "  (slice 1b: the builder is target-independent and no selector consumes a built function yet,"
  echo "   so one \"built\" column stands for all four targets; the per-target columns arrive with 1c)"
  if [ -s "$W/corpus.failed" ]; then
    echo "  failed corpus runs:"; sed 's/^/    /' "$W/corpus.failed"
  fi
  if grep -qE '	fn [^ ]+ VerifyFailed\(' "$W/corpus.fns" "$W/lib.fns" "$W/src.fns"; then
    echo "  VERIFIER REFUSALS (located internal errors, docs/ir.md §5):"
    grep -hE '	fn [^ ]+ VerifyFailed\(' "$W/corpus.fns" "$W/lib.fns" "$W/src.fns" | sed 's/^/    /'
  fi
  if [ "$QUIET" = 0 ]; then
    for set in corpus lib src; do
      echo "NotYet outside the subset, $set (ranked):"
      outside "$W/$set.fns" | ranked | sed 's/^/  /'
      echo "NotYet sema gaps, $set (ranked):"
      gaps "$W/$set.fns" | ranked | sed 's/^/  /'
    done
  fi
  local lib_ok=1 src_ok=1
  { [ "$lib_rc" = 0 ] || { [ "$lib_rc" = 70 ] && [ "$GATE" = 0 ]; }; } || lib_ok=0
  { [ "$src_rc" = 0 ] || { [ "$src_rc" = 70 ] && [ "$GATE" = 0 ]; }; } || src_ok=0
  grep -q '^ir: functions=' "$W/lib.out" || lib_ok=0
  grep -q '^ir: functions=' "$W/src.out" || src_ok=0
  if [ "$GATE" = 1 ]; then
    local nb_all
    nb_all=$(cat "$W/corpus.fns" "$W/lib.fns" "$W/src.fns" | grep -cE '	fn [^ ]+ Built$' || true)
    echo "ir census gate: programs=$ncorpus refused-by-check=$refused failed=$failed verify_runs=$vruns lib_rc=$lib_rc src_rc=$src_rc built=$nb_all verify_failed=$bad"
    if [ "$failed" = 0 ] && [ "$vruns" = 0 ] && [ "$bad" = 0 ] && [ "$lib_ok" = 1 ] && [ "$src_ok" = 1 ]; then
      echo "*** ir census gate: the verifier accepted all $nb_all built functions, and every run reported ***"
      return 0
    fi
    echo "*** ir census gate: FAIL — a verifier refusal or a failed \`alatyr ir\` run (above) ***"
    return 1
  fi
  [ "$failed" = 0 ] && [ "$lib_ok" = 1 ] && [ "$src_ok" = 1 ] || return 1
  return 0
}

# ---- the self-test: planted report directories, no compiler ----
if [ "$SELFTEST" = 1 ]; then
  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT
  st_fail=0
  # plant <name> <corpus line> <corpus rc> <lib line> <lib rc>: a one-program, one-module census.
  plant() {
    local d="$T/$1"; mkdir -p "$d"
    echo "test/p.al" > "$d/corpus.list"
    { printf '%s\n' "$2"; echo "ir: functions=1 built=0 notyet=1 sema_gaps=0 verify_failed=0"; } > "$d/c.test_p.al.out"
    echo "$3 test/p.al" > "$d/c.test_p.al.rc"
    { printf '%s\n' "$4"; echo "ir: functions=1"; } > "$d/lib.out"; echo "$5" > "$d/lib.rc"
    { echo "fn src::s NotYet(expr Index, src/s.al:1:1)"; echo "ir: functions=1"; } > "$d/src.out"; echo 0 > "$d/src.rc"
  }
  # expect <name> <want rc> <needle the verdict must print>
  expect() {
    local out rc
    out="$(GATE=1 QUIET=0 analyse "$T/$1" 2>&1)"; rc=$?
    if [ "$rc" = "$2" ] && printf '%s\n' "$out" | grep -qF -- "$3"; then echo "ok   ir_census self-test $1: rc=$rc"
    else echo "FAIL ir_census self-test $1: rc=$rc (want $2, needle '$3')"; printf '%s\n' "$out" | sed 's/^/     /'; st_fail=$((st_fail + 1)); fi
  }
  plant clean "fn p::f Built" 0 "fn base::g NotYet(sema-gap absent: expr Var, lib/g.al:1:1)" 0
  expect clean 0 "accepted all 1 built functions"
  plant verify_corpus "fn p::f VerifyFailed(V4 at inst 3)" 70 "fn base::g Built" 0
  expect verify_corpus 1 "fn p::f VerifyFailed(V4 at inst 3)"
  plant verify_lib "fn p::f Built" 0 "fn base::g VerifyFailed(V7 at inst 9)" 70
  expect verify_lib 1 "fn base::g VerifyFailed(V7 at inst 9)"
  plant verify_pulled "fn base::h VerifyFailed(V3 at inst 2)" 70 "fn base::g Built" 0
  expect verify_pulled 1 "test/p.al rc=70 (a verifier refusal)"
  plant crash "fn p::f Built" 139 "fn base::g Built" 0
  expect crash 1 "test/p.al rc=139"
  plant timeout "fn p::f Built" 124 "fn base::g Built" 0
  expect timeout 1 "test/p.al rc=124"
  plant nosummary "fn p::f Built" 0 "fn base::g Built" 0
  : > "$T/nosummary/c.test_p.al.out"
  expect nosummary 1 "(no summary line)"
  plant librc "fn p::f Built" 0 "fn base::g Built" 139
  expect librc 1 "lib_rc=139"
  # The census counts what it reads: the clean plant's one Built line, its one sema gap.
  cl="$(GATE=0 QUIET=0 analyse "$T/clean" 2>&1)"
  if printf '%s\n' "$cl" | grep -qE '^  corpus +1 +1 +0 +0 +0 +0$' && printf '%s\n' "$cl" | grep -qE '^  lib/ +1 +0 +1 +0 +1 +0$' \
    && printf '%s\n' "$cl" | grep -qE '^ +1 sema-gap absent: expr Var$'; then echo "ok   ir_census self-test counts: built, outside and sema-gap columns"
  else echo "FAIL ir_census self-test counts"; printf '%s\n' "$cl" | sed 's/^/     /'; st_fail=$((st_fail + 1)); fi
  echo "ir_census self-test: 9 checks, $st_fail failed"
  [ "$st_fail" = 0 ] || exit 1
  exit 0
fi

[ -x "$AL" ] || { echo "ir_census: no compiler at $AL (build it first)" >&2; exit 2; }
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
grep '^ir self-test: ' "$W/selftest"

# ---- corpus: one `alatyr ir <file>` per tracked program ----
git ls-files 'test/*.al' | sort -u > "$W/corpus.list"
ncorpus=$(wc -l < "$W/corpus.list" | tr -d ' ')
[ "$ncorpus" -gt 0 ] || { echo "ir_census: no corpus sources" >&2; exit 2; }
export AL W
one() {
  f="$1"
  key=$(printf '%s' "$f" | tr '/' '_')
  timeout 60 "$AL" ir "$f" > "$W/c.$key.out" 2>"$W/c.$key.err"
  echo "$? $f" > "$W/c.$key.rc"
}
export -f one
xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} < "$W/corpus.list"

# ---- lib/ and src/: one raw-module walk each ----
git ls-files 'lib/*.al' 'lib/**/*.al' | sort -u > "$W/lib.list"
git ls-files 'src/*.al' 'src/**/*.al' | sort -u > "$W/src.list"
xargs "$AL" ir --modules < "$W/lib.list" > "$W/lib.out" 2> "$W/lib.err"
echo "$?" > "$W/lib.rc"
xargs "$AL" ir --modules < "$W/src.list" > "$W/src.out" 2> "$W/src.err"
echo "$?" > "$W/src.rc"

analyse "$W"
