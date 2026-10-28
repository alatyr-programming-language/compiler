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
# ## Per-backend coverage (`--targets`)
#
# The table above answers a TARGET-INDEPENDENT question — what the builder builds — and says so: "the
# per-target columns arrive with the selectors". The selectors arrived with slice 1c (`src/<be>/isel.al`,
# hooked into each emitter's decl loop), and the columns never did. Until they do, "all four backends
# lower from the shared IR" (`docs/ir.md` §6, criterion 2 of the strict-compiler goal) is a claim no
# number backs, and the twins' private copies of each decision (`docs/ir.md` §2.4) have no census that
# could ever ALLOW their deletion — §7.2 deletes them "when the census allows", and there was nothing to
# allow.
#
# So `--targets` emits every corpus program through each backend's own verb and counts the marker each
# selector writes when it takes a function from the IR — one per selected function, in that backend's
# comment syntax, and written by that backend's selector alone (`src/<be>/isel.al`, wasm's living at
# `src/wat/isel.al` because its verb is `wat`):
#
#   x86_64   `alatyr x86-ir <f>`    `# ir: selected from the shared IR`
#   aarch64  `alatyr aarch64 <f>`    `// ir: selected from the shared IR`
#   riscv64  `alatyr riscv64 <f>`    `# ir: selected from the shared IR`
#   wasm     `alatyr wat <f>`        `(; ir: selected from the shared IR ;)`
#
# The count is per BACKEND, not derived from the builder: a selector can refuse an op the builder built,
# and wasm's frame model differs from the twins' register model, so its coverage is its own number.
# Emitting only — no assemble, no run — so this costs seconds and needs no cross toolchain.
#
# The numbers are held by a ratchet (`scripts/ir_census.targets.baseline`): each backend's selected
# function count may not SHRINK. A slice that lowers coverage is a regression to explain, not a pass;
# and when a backend's count reaches the builder's `built`, that backend is fully on the IR and §7.2
# may delete its private copies. A backend at ZERO is printed as such and fails the gate: a selector
# that selects nothing is not "lowering from the shared IR", whatever its file weighs.
#
# ## Usage
#
#   scripts/ir_census.sh [--gate] [--targets] [--jobs N] [--reasons N] [--quiet]
#   scripts/ir_census.sh --self-test
#     --gate       fail on any verifier refusal or failed run (the full gate's IR stage); implies
#                  --targets, so the gate line carries the per-backend coverage it holds
#     --targets    measure per-BACKEND selection — how many functions each of the four emitters takes
#                  from the shared IR (see "Per-backend coverage" above)
#     --ratchet-write  write the per-backend baseline from this run (a deliberate, reviewable act)
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
TARGETS=0
RATCHET_WRITE=0
SELFTEST=0
BASELINE="$ROOT/scripts/ir_census.targets.baseline"
while [ $# -gt 0 ]; do
  case "$1" in
    --gate) GATE=1; TARGETS=1; shift ;;
    --targets) TARGETS=1; shift ;;
    --ratchet-write) RATCHET_WRITE=1; TARGETS=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --reasons) NREASONS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "usage: $0 [--gate] [--targets] [--jobs N] [--reasons N] [--quiet] | --self-test" >&2; exit 2 ;;
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

# ---- per-backend selection (`--targets`) -------------------------------------------------------------
# The verb each backend is emitted through, and the marker its selector writes once per function it
# takes from the shared IR. `src/<be>/isel.al` is the ONLY writer of its marker — `grep -n 'ir:
# selected' src/` shows exactly four lines, one per selector — so counting the marker counts selections
# and nothing else. Note `wasm` is emitted through the verb named `wat`.
sel_verb() { case "$1" in x86_64) printf 'x86-ir' ;; wasm) printf 'wat' ;; *) printf '%s' "$1" ;; esac; }
sel_marker() {
  case "$1" in
    aarch64) printf '// ir: selected from the shared IR' ;;
    wasm)    printf '(; ir: selected from the shared IR ;)' ;;
    *)       printf '# ir: selected from the shared IR' ;;
  esac
}

# count_selected <marker> <file> — how many times the marker appears (0 when the file is empty).
count_selected() { grep -cF -- "$1" "$2" 2>/dev/null || true; }

# targets <corpus-list> — emit every program through each backend's verb and count its selections.
# Writes `targets.txt`: `backend\tprograms\twith-IR\tfunctions\trefused`. Emitting only: no assemble,
# no run, so this needs no cross toolchain and costs seconds.
targets() {
  local CL="$1" be verb mk key
  : > "$W/targets.txt"
  for be in x86_64 aarch64 riscv64 wasm; do
    : > "$W/sel.$be.list"
    while read -r f; do printf '%s\t%s\n' "$be" "$f" >> "$W/sel.$be.list"; done < "$CL"
    export -f one_sel sel_marker sel_verb count_selected
    xargs -P "$JOBS" -I{} bash -c 'one_sel "$@"' _ {} < "$W/sel.$be.list"
    local nprogs=0 nwith=0 nfns=0 nref=0
    # One file per program (the `one()` pattern), never a shared append: 12 workers writing one file
    # would interleave.
    while read -r f; do
      key=$(printf '%s' "$f" | tr '/' '_')
      n=0; rc=missing
      if [ -f "$W/s.$be.$key.n" ]; then read -r n rc < "$W/s.$be.$key.n"; else rc=noout; fi
      nprogs=$((nprogs + 1))
      [ "$rc" = 0 ] || nref=$((nref + 1))
      if [ "${n:-0}" -gt 0 ]; then nwith=$((nwith + 1)); nfns=$((nfns + n)); fi
    done < "$CL"
    printf '%s\t%s\t%s\t%s\t%s\n' "$be" "$nprogs" "$nwith" "$nfns" "$nref" >> "$W/targets.txt"
  done
}

# one_sel <backend>TAB<file> — emit one program, record how many markers its text carries. xargs
# hands the whole line as ONE argument, so it is split here, not by the caller.
one_sel() {
  local line="$1" be f verb key out n rc
  be="${line%%	*}"; f="${line#*	}"
  verb=$(sel_verb "$be")
  key=$(printf '%s' "$f" | tr '/' '_')
  timeout 60 "$AL" "$verb" "$f" > "$W/s.$be.$key.out" 2>"$W/s.$be.$key.err" < /dev/null
  rc=$?
  n=$(count_selected "$(sel_marker "$be")" "$W/s.$be.$key.out")
  printf '%s %s\n' "${n:-0}" "$rc" > "$W/s.$be.$key.n"
}

# targets_report — print the per-backend table; 0 when every backend selects something.
targets_report() {
  echo "ir coverage per backend: functions each emitter takes from the shared IR (docs/ir.md §6)"
  printf '  %-9s %9s %8s %10s %9s\n' backend programs "with-IR" functions refused
  local be nprogs nwith nfns nref bad=0
  while IFS=$'\t' read -r be nprogs nwith nfns nref; do
    printf '  %-9s %9s %8s %10s %9s\n' "$be" "$nprogs" "$nwith" "$nfns" "$nref"
    [ "$nfns" -gt 0 ] || bad=$((bad + 1))
  done < "$W/targets.txt"
  echo "  (a selector refuses an op the builder built by returning false and rolling its StrBuf back, so"
  echo "   a backend count is its own; the refused column counts programs the verb would not emit at all.)"
  return $bad
}

# targets_ratchet <baseline> — each backend's function count may not SHRINK. 0 held, 1 GREW-DOWN,
# 2 the baseline is unusable. The baseline MUST name all four backends: one missing from it is a
# backend the ratchet does not hold, and it could fall to one selected function unseen — which is the
# hole this whole mode exists to close. Lines are validated, never filtered out: a line that does not
# parse is the baseline being broken, not a line to skip.
#
# ## An acknowledged decrease: `## <backend>-coverage-ok: #<issue> — <reason>`
# A count can fall for two opposite reasons, and the ratchet must tell them apart or it enforces the
# wrong one:
#   REGRESSION   a function the backend used to select from the IR now falls back to the private
#                emitter. Nothing excuses this; it fails, exactly as it always has.
#   CORRECTION   the baseline was inflated: what the selector emitted for those functions was not
#                right — either the spec forbids it, or the IR has no model for it and the count was
#                standing for output the IR does not actually model. The number was never honest, and
#                refusing to record the correction would keep the compiler wrong just to hold a figure
#                up (#1084 is the second kind: five x86_64 functions were counted while the selector
#                emitted a `call` for an `@inline` callee, and neither `docs/ir.md` nor the spec models
#                `@inline` substitution — a gap, so it is filed as #1084 rather than asserted here).
# The second is recorded, never hidden: the ack names the backend, cites the issue that establishes
# the correction, and says what restores the coverage. It prints on every run that uses it, so it
# cannot go quiet, and an ack with no citation is refused — a bare "trust me" is not a reason. Same
# discipline as the strict forms' `## <rule>-ok: <reason>` markers, moved from the source to the
# baseline.
targets_ratchet() {
  local f="$1"
  [ -s "$f" ] || { echo "ir targets ratchet: NO baseline at $f — write it with:" \
    ; echo "  scripts/ir_census.sh --targets --ratchet-write" >&2; return 2; }
  local be want have rc=0 seen="" ack="" short
  while read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      \#\#[[:space:]]*[a-z0-9_]*-coverage-ok:*)
        ## Validated here, printed where it is used (below): an ack that excuses nothing must not
        ## print as though it did, and a malformed one must fail at parse time, not silently pass.
        be="${line#\#\# }"; be="${be%%-coverage-ok:*}"
        case "$be" in x86_64|aarch64|riscv64|wasm) ;; *) echo "ir targets ratchet: ack names no known backend: '$line'" >&2; return 2 ;; esac
        ack="${line#*-coverage-ok:}"; ack="$(printf '%s' "$ack" | sed 's/^ *//')"
        case "$ack" in *'#'[0-9]*) ;; *) echo "ir targets ratchet: the $be ack cites no issue — a reason must name one (#1084)" >&2; return 2 ;; esac
        continue ;;
      *=*) ;; *) echo "ir targets ratchet: malformed baseline line '$line'" >&2; return 2 ;;
    esac
    be="${line%%=*}"; want="${line#*=}"
    case "$want" in ''|*[!0-9]*) echo "ir targets ratchet: malformed baseline line '$line'" >&2; return 2 ;; esac
    case "$be" in x86_64|aarch64|riscv64|wasm) ;; *) echo "ir targets ratchet: unknown backend '$be' in baseline" >&2; return 2 ;; esac
    seen="$seen $be"
    have=$(awk -F'\t' -v b="$be" '$1 == b {print $4}' "$W/targets.txt")
    [ -n "$have" ] || { echo "ir targets ratchet: no measurement for $be" >&2; return 2; }
    if [ "$have" -lt "$want" ]; then
      ack="$(awk -v b="$be" '$0 ~ "^## "b"-coverage-ok:" {sub("^## [^-]*-coverage-ok:[[:space:]]*",""); print; exit}' "$f")"
      if [ -n "$ack" ]; then
        short=$((want - have))
        echo "ir targets ratchet: $be is $short BELOW the baseline $want -> $have, ACKNOWLEDGED."
        echo "  ack: $ack"
        echo "  The ack is in the baseline and repeated here so it cannot go quiet. The shortfall is a"
        echo "  debt, not a new floor: docs/ir.md §7.2 closes when this returns to $want, or the"
        echo "  baseline is lowered by $short in its own reviewed commit."
        continue
      fi
      echo "ir targets ratchet: FAIL — $be selected FEWER functions from the IR than the baseline: $want -> $have"
      echo "  A backend losing IR coverage is a regression to explain, not a pass (docs/ir.md §7.2)."
      echo "  If the baseline was inflated — those functions were mis-lowered and the selector now refuses"
      echo "  them per the spec — RECORD that, do not hide it. Add to this baseline:"
      echo "    ## $be-coverage-ok: #<issue> — <what was wrong, and what restores the coverage>"
      rc=1
    elif [ "$have" -gt "$want" ]; then
      echo "ir targets ratchet: $be GREW its IR coverage $want -> $have; lower the baseline."
    fi
  done < "$f"
  for be in x86_64 aarch64 riscv64 wasm; do
    case " $seen " in *" $be "*) ;; *) echo "ir targets ratchet: baseline names no $be — that backend is unheld" >&2; return 2 ;; esac
    ## A stale ack is a lie by omission: it says this backend is below its baseline when it is not,
    ## which means the coverage came back and nobody removed the excuse. Warn, do not fail — the
    ## number is right, the comment is out of date, and a gate that fails on a stale comment teaches
    ## people to delete comments rather than check them.
    ack=no; grep -q "^## $be-coverage-ok:" "$f" && ack=yes
    [ "$ack" = yes ] || continue
    have=$(awk -F'\t' -v b="$be" '$1 == b {print $4}' "$W/targets.txt")
    want="$(awk -F= -v b="$be" '$1 == b {print $2; exit}' "$f")"
    [ -n "$have" ] && [ -n "$want" ] && [ "$have" -ge "$want" ] &&
      echo "  NOTE: $be carries a coverage ack but is AT or ABOVE the baseline ($want -> $have); remove the stale line."
  done
  return $rc
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
  echo "  (the builder is target-independent: \"built\" counts for every target. From slice 1c each twin"
  echo "   selects a built function from its IR unless its selector refuses an op; see docs/ir-slice-1.md §4)"
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
  st_n=0
  # chk <rc-0-is-pass> <name> — one check, counted.
  chk() { st_n=$((st_n + 1)); if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; st_fail=$((st_fail + 1)); fi; }
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
    st_n=$((st_n + 1))
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
    && printf '%s\n' "$cl" | grep -qE '^ +1 sema-gap absent: expr Var$'; then c=0; printf '%s\n' "$cl" >/dev/null
  else c=1; printf '%s\n' "$cl" | sed 's/^/     /'; fi
  chk "$c" "ir_census self-test counts: built, outside and sema-gap columns"
  # ---- per-backend coverage: the marker counting, with no compiler ----
  # Each backend's marker must be distinct where its comment syntax is distinct: riscv64 and x86_64
  # share `#` (different runs, so no collision), but wasm's `(; ;)` must not be counted by the twins'
  # prefix or vice versa, or one backend's coverage would silently read as another's.
  c=0
  [ "$(sel_marker aarch64)" = "// ir: selected from the shared IR" ] || c=1
  [ "$(sel_marker riscv64)" = "# ir: selected from the shared IR" ] || c=1
  [ "$(sel_marker wasm)" = "(; ir: selected from the shared IR ;)" ] || c=1
  [ "$(sel_marker wasm)" != "$(sel_marker riscv64)" ] || c=1
  [ "$(sel_verb wasm)" = "wat" ] || c=1
  [ "$(sel_verb x86_64)" = "x86-ir" ] || c=1
  chk "$c" "ir targets self-test markers: one prefix per comment syntax, wasm through the \`wat\` verb"
  # The counter counts selections, not prose that merely mentions them, and an empty file is zero.
  printf '# ir: selected from the shared IR\n  movq %%rax\n# ir: selected from the shared IR\n' > "$T/sel_a"
  printf ';; a comment that says ir: selected from the shared IR in prose\n' > "$T/sel_p"
  : > "$T/sel_e"
  c=0
  [ "$(count_selected '# ir: selected from the shared IR' "$T/sel_a")" = 2 ] || c=1
  [ "$(count_selected '# ir: selected from the shared IR' "$T/sel_p")" = 0 ] || c=1
  [ "$(count_selected '# ir: selected from the shared IR' "$T/sel_e")" = 0 ] || c=1
  [ "$(count_selected '(; ir: selected from the shared IR ;)' "$T/sel_a")" = 0 ] || c=1
  chk "$c" "ir targets self-test count: two markers counted, prose is not a selection, empty is zero"
  # A backend at ZERO fails the report: a selector that selects nothing is not lowering from the IR.
  W="$T"
  printf 'x86_64\t10\t5\t20\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t0\t0\t3\n' > "$T/targets.txt"
  out="$(targets_report 2>&1)"; rc=$?
  c=0; [ "$rc" != 0 ] || c=1
  printf '%s\n' "$out" | grep -q '^  wasm' || c=1
  chk "$c" "ir targets self-test zero: a backend selecting nothing is printed and fails (rc=$rc)"
  # The ratchet holds at the line, ignores growth, FAILS when a backend shrinks (naming it), and
  # refuses a baseline that is malformed, incomplete or absent.
  printf 'x86_64=20\naarch64=18\nriscv64=18\nwasm=0\n' > "$T/base_ok"
  printf 'x86_64=20\naarch64=18\nriscv64=18\n' > "$T/base_missing"
  printf 'x86_64=x\n' > "$T/base_bad"
  printf 'x86_64\t10\t5\t20\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t0\t0\t3\n' > "$T/targets.txt"
  targets_ratchet "$T/base_ok" >/dev/null 2>&1; chk $? "ir targets ratchet self-test: held at the line"
  printf 'x86_64\t10\t5\t21\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t1\t1\t3\n' > "$T/targets.txt"
  targets_ratchet "$T/base_ok" >/dev/null 2>&1; chk $? "ir targets ratchet self-test: coverage growing is not a failure"
  printf 'x86_64\t10\t5\t19\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t0\t0\t3\n' > "$T/targets.txt"
  out="$(targets_ratchet "$T/base_ok" 2>&1)"; rc=$?
  c=0; [ "$rc" = 1 ] || c=1
  printf '%s\n' "$out" | grep -q 'x86_64 selected FEWER' || c=1
  chk "$c" "ir targets ratchet self-test: FAIL when a backend loses coverage, and names it (rc=$rc)"
  printf '%s\n' "$out" | grep -q 'coverage-ok: #<issue>' || c=1
  chk "$c" "ir targets ratchet self-test: the refusal says HOW to record an honest correction (rc=$rc)"

  ## ── an acknowledged decrease: recorded, cited, and never silent. ──
  printf 'x86_64=20\n## x86_64-coverage-ok: #1084 — five functions were counted while the selector emitted a call for an @inline callee, which neither docs/ir.md nor the spec models; the IR gains the representation when #1084 is answered.\naarch64=18\nriscv64=18\nwasm=0\n' > "$T/base_ack"
  printf 'x86_64\t10\t5\t15\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t1\t1\t3\n' > "$T/targets.txt"
  out="$(targets_ratchet "$T/base_ack" 2>&1)"; rc=$?
  c=0; [ "$rc" = 0 ] || c=1
  printf '%s\n' "$out" | grep -q 'x86_64 is 5 BELOW the baseline 20 -> 15, ACKNOWLEDGED' || c=1
  printf '%s\n' "$out" | grep -q '#1084' || c=1
  chk "$c" "ir targets ratchet self-test: a cited ack holds the line and prints the reason (rc=$rc)"
  ## An ack with no citation is not a reason.
  printf 'x86_64=20\n## x86_64-coverage-ok: it is fine.\naarch64=18\nriscv64=18\nwasm=0\n' > "$T/base_ack_nocite"
  targets_ratchet "$T/base_ack_nocite" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: an ack citing no issue is refused (rc=$rc)"
  ## An ack naming a backend that does not exist is refused, not ignored.
  printf 'x86_64=20\n## mips64-coverage-ok: #1 — nope.\naarch64=18\nriscv64=18\nwasm=0\n' > "$T/base_ack_be"
  targets_ratchet "$T/base_ack_be" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: an ack naming an unknown backend is refused (rc=$rc)"
  ## Non-vacuity: the same file WITHOUT the ack must fail. If it did not, the ack test above proves
  ## nothing and the ack is decoration.
  printf 'x86_64=20\naarch64=18\nriscv64=18\nwasm=0\n' > "$T/base_noack"
  targets_ratchet "$T/base_noack" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 1 ] && echo 0 || echo 1)" "ir targets ratchet self-test: WITHOUT the ack the same shortfall FAILS (non-vacuity, rc=$rc)"
  ## A stale ack — coverage came back and nobody removed the excuse — is noticed.
  printf 'x86_64\t10\t5\t20\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\nwasm\t10\t1\t1\t3\n' > "$T/targets.txt"
  out="$(targets_ratchet "$T/base_ack" 2>&1)"; rc=$?
  c=0; [ "$rc" = 0 ] || c=1
  printf '%s\n' "$out" | grep -q 'stale line' || c=1
  chk "$c" "ir targets ratchet self-test: an ack no longer excusing anything is flagged stale (rc=$rc)"
  printf 'x86_64\t10\t5\t20\t0\naarch64\t10\t5\t18\t0\nriscv64\t10\t5\t18\t0\n' > "$T/targets.txt"
  targets_ratchet "$T/base_ok" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: a backend missing from the measurement is not a pass (rc=$rc)"
  targets_ratchet "$T/base_missing" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: a baseline naming no wasm is unusable (rc=$rc)"
  targets_ratchet "$T/base_bad" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: a malformed baseline is not a pass (rc=$rc)"
  targets_ratchet "$T/nope" >/dev/null 2>&1; rc=$?
  chk "$([ "$rc" = 2 ] && echo 0 || echo 1)" "ir targets ratchet self-test: no baseline is not a pass (rc=$rc)"
  # The four selectors must each write their marker exactly once in the tree as committed — the check
  # the gate runs before it believes any count. A renamed marker would read as "selects nothing".
  m_bad=0
  [ "$(grep -cF -- "$(sel_marker x86_64)" "$ROOT/src/lower/isel.al" 2>/dev/null || echo 0)" = 1 ] || m_bad=1
  [ "$(grep -cF -- "$(sel_marker aarch64)" "$ROOT/src/aarch64/isel.al" 2>/dev/null || echo 0)" = 1 ] || m_bad=1
  [ "$(grep -cF -- "$(sel_marker riscv64)" "$ROOT/src/riscv64/isel.al" 2>/dev/null || echo 0)" = 1 ] || m_bad=1
  [ "$(grep -cF -- "$(sel_marker wasm)" "$ROOT/src/wat/isel.al" 2>/dev/null || echo 0)" = 1 ] || m_bad=1
  chk "$m_bad" "ir targets self-test sources: all four selectors write their marker exactly once"
  echo "ir_census self-test: $st_n checks, $st_fail failed"
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

analyse_rc=0
analyse "$W" || analyse_rc=$?

# ---- per-backend coverage (`--targets`) ----
if [ "$TARGETS" = 1 ]; then
  # Before any count means anything: each selector must exist and write its marker, exactly once. A
  # renamed marker would silently read as "this backend selects nothing", and a marker written twice per
  # function would double the count. Both are checked here, in the source, not inferred from output.
  sel_ok=1
  for be in x86_64 aarch64 riscv64 wasm; do
    case "$be" in
      x86_64) sf="src/lower/isel.al" ;;
      wasm)   sf="src/wat/isel.al" ;;
      *)      sf="src/$be/isel.al" ;;
    esac
    [ -f "$sf" ] || { echo "ir targets: no selector at $sf" >&2; sel_ok=0; continue; }
    n=$(grep -cF -- "$(sel_marker "$be")" "$sf" || true)
    [ "$n" = 1 ] || { echo "ir targets: $sf writes its selection marker $n times, want exactly 1" >&2; sel_ok=0; }
  done
  if [ "$sel_ok" = 1 ]; then
    targets "$W/corpus.list"
    trc=0; targets_report || trc=$?
    if [ "$RATCHET_WRITE" = 1 ]; then
      awk -F'\t' '{print $1"="$4}' "$W/targets.txt" > "$BASELINE" || exit 2
      echo "ir targets ratchet: WROTE $BASELINE ($(tr '\n' ' ' < "$BASELINE"))"
      exit 0
    fi
    if [ "$GATE" = 1 ]; then
      if [ "$trc" != 0 ]; then
        echo "*** ir targets gate: FAIL — a backend takes NOTHING from the shared IR (docs/ir.md §6) ***"
        analyse_rc=1
      elif ! targets_ratchet "$BASELINE"; then
        echo "*** ir targets gate: FAIL — a backend lost IR coverage (above) ***"; analyse_rc=1
      else
        echo "ir targets gate: all four backends lower from the shared IR, at or above the baseline"
      fi
    fi
  else
    echo "*** ir targets: FAIL — a selector or its marker is missing, so no coverage number means anything ***"
    [ "$GATE" = 1 ] && analyse_rc=1
  fi
fi

exit $analyse_rc
