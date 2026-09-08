#!/usr/bin/env bash
# scripts/sweep_common.sh — shared plumbing for the a64/rv64/wasm "never silently wrong" sweeps.
#
# Sourced (never executed) by scripts/{a64,rv64,wasm}_sweep.sh. It owns the two things all three
# sweeps must do IDENTICALLY, and that they previously each got subtly wrong:
#
#   1. OBTAINING THE COMPILER UNDER TEST. Each sweep used to run `seed/alatyr build package.al`
#      with `>/dev/null 2>&1` and collapse any failure into the single word `FAIL: seed build`.
#      That discarded the one thing a reader needs — WHICH command failed and WHAT it said — and
#      it made the gate untrustworthy: a red sweep said nothing about whether the compiler was
#      broken, the assembler was broken, or the build never started. `sweep_compiler` now keeps the
#      build's own output, prints it verbatim on failure, and then INDEPENDENTLY re-assembles the
#      emitted `target/debug/alatyr.s` by hand so the report distinguishes the two very different
#      failures the driver's own diagnostic conflates (see `sweep_diagnose_build_failure`).
#
#   2. SCRATCH SPACE. All three sweeps used to write `target/sweep_<name>.{s,o,elf,wat,wasm}` — one
#      flat namespace SHARED by the aarch64 and riscv64 sweeps, so each run read back files the
#      other run had left there. `sweep_scratch` gives every sweep its own directory and wipes it
#      first, so no sweep can ever observe another sweep's artifact.
#
#   3. THE PER-PROGRAM WALL-CLOCK CEILING. All three sweeps used to run the guest as
#      `timeout 10 <emulator> "$elf"; got=$?` and then classify `got` directly. A ceiling breach makes
#      `got=124`, which is neither the wanted exit nor a trap, so the row printed
#      `WRONG …=124 want=<n> (valid binary, normal exit, wrong = SILENT MISCOMPILE)` — the one verdict
#      this project treats as unacceptable, for a binary that was never run to completion. Machine load
#      could therefore manufacture the accusation that the compiler silently miscompiles a program, and
#      a genuine infinite loop was misattributed the same way. A breach is now its OWN outcome
#      (`timeout`), it is RE-OBSERVED serially once the parallel walk is over, and only the second
#      observation is classified: `sweep_guest_run`, `sweep_reobserve` and the `TIMED-OUT` class below.
#
# Every sweep child process is spawned with `< /dev/null`. The sweeps drive their corpus with
# `while read … done < <(grep …)`; without that redirect a corpus program that reads stdin eats the
# loop's own input and the sweep silently stops early with a lower — but still "green" — count.

## Absolute path of the compiler under test.
##
## `ALATYR_SWEEP_CC` (an ABSOLUTE path to an already-built compiler) makes the state EXPLICIT: the
## sweep runner builds the compiler once, verifies it once, and hands the same binary to all three
## sweeps instead of each sweep silently rebuilding `target/debug/alatyr` on top of the previous one. When
## it is unset (a sweep run standalone) the sweep builds Stage1 from the frozen seed itself.
## `tag` is the caller's display label (e.g. `a64_sweep`), used verbatim in messages and as the
## seed-build log's basename. Sets `SWEEP_CC` to the compiler's absolute path; on failure prints a full diagnosis and returns 1
## (the diagnosis goes to stdout, so it must not be captured through a command substitution).
sweep_compiler() {
  _sc_root="$1"
  _sc_tag="$2"
  if [ -n "${ALATYR_SWEEP_CC:-}" ]; then
    if [ ! -x "$ALATYR_SWEEP_CC" ]; then
      echo "FAIL: ${_sc_tag}: ALATYR_SWEEP_CC is set but not an executable file"
      echo "  ALATYR_SWEEP_CC = $ALATYR_SWEEP_CC"
      return 1
    fi
    SWEEP_CC="$ALATYR_SWEEP_CC"
    return 0
  fi
  sweep_build_compiler "$_sc_root" "$_sc_tag" || return 1
  sweep_select_compiler "$_sc_root" || return 1
  return 0
}

sweep_select_compiler() {
  _sel_root="$1"
  if [ -x "$_sel_root/target/debug/alatyr" ]; then
    SWEEP_CC="$_sel_root/target/debug/alatyr"
  elif [ -x "$_sel_root/target/alatyr" ]; then
    SWEEP_CC="$_sel_root/target/alatyr"
    echo "bootstrap transition: sweep used legacy target/alatyr; fixpoint remains the reseed decision"
  else
    echo "FAIL: no compiler-under-test at target/debug/alatyr or legacy target/alatyr"
    return 1
  fi
}

## Build Stage1 from the frozen seed, keeping the build's own stdout+stderr. On failure print
## everything a reader needs to act, then hand off to the assembler cross-check.
sweep_build_compiler() {
  _bc_root="$1"
  _bc_tag="$2"
  mkdir -p "$_bc_root/target"
  _bc_log="$_bc_root/target/${_bc_tag}_seedbuild.log"
  rm -f "$_bc_root/target/alatyr" "$_bc_root/target/alatyr.s" "$_bc_root/target/alatyr.o"
  rm -f "$_bc_root/target/debug/alatyr" "$_bc_root/target/debug/alatyr.s" "$_bc_root/target/debug/alatyr.o"
  "$_bc_root/seed/alatyr" build "$_bc_root/package.al" > "$_bc_log" 2>&1 < /dev/null
  _bc_rc=$?
  [ "$_bc_rc" = 0 ] && return 0
  echo "FAIL: ${_bc_tag}: could not build the compiler under test"
  echo "  command : $_bc_root/seed/alatyr build $_bc_root/package.al"
  echo "  exit    : $_bc_rc"
  echo "  output  : (verbatim, $_bc_log)"
  if [ -s "$_bc_log" ]; then sed 's/^/    | /' "$_bc_log"; else echo "    | (the build printed nothing)"; fi
  sweep_diagnose_build_failure "$_bc_root" "$_bc_tag"
  return 1
}

## Tell apart the two failures the compiler driver reports with ONE message.
##
## `link_exe` (src/cli.al) prints "the assembler (`as`) rejected the emitted assembly" for BOTH
##   (a) `as` ran and rejected the input — a real codegen regression, and
##   (b) the driver could not spawn `as` at all (fork/execve failed) — a driver defect that has
##       nothing to do with the emitted assembly.
## Case (b) is what makes the sweeps look flaky. The harness cannot fix the driver, but it can and
## must stop reporting (b) as if it were (a): re-run the assembler on the very same `target/debug/alatyr.s`
## and say which of the two actually happened, quoting the assembler verbatim either way.
sweep_diagnose_build_failure() {
  _db_root="$1"
  _db_tag="$2"
  if [ -f "$_db_root/target/debug/alatyr.s" ]; then _db_s="$_db_root/target/debug/alatyr.s"; else _db_s="$_db_root/target/alatyr.s"; fi
  echo "  cross-check:"
  if [ ! -f "$_db_s" ]; then
    echo "    | $_db_s was never written — the build failed BEFORE code emission."
    return 0
  fi
  if ! command -v as > /dev/null 2>&1; then
    echo "    | \`as\` is not on PATH — cannot re-check the emitted assembly."
    return 0
  fi
  _db_probe="$_db_root/target/${_db_tag}_seedbuild_probe.o"
  _db_err="$_db_root/target/${_db_tag}_seedbuild_probe.log"
  if as "$_db_s" -o "$_db_probe" > "$_db_err" 2>&1 < /dev/null; then
    echo "    | \`as $_db_s -o $_db_probe\` SUCCEEDED (exit 0)."
    echo "    | The emitted assembly is VALID. The compiler did not fail to PRODUCE it, it failed"
    echo "    | to RUN the assembler: the driver's \"the assembler (\`as\`) rejected the emitted"
    echo "    | assembly\" also covers a failed fork/execve (src/cli.al link_exe -> rt::run), and"
    echo "    | that is what happened here. This is a compiler-driver defect, NOT a codegen"
    echo "    | regression and NOT a fault of this sweep."
  else
    echo "    | \`as $_db_s -o $_db_probe\` FAILED (exit $?). The assembler's own diagnostic:"
    sed 's/^/    | /' "$_db_err" | head -40
    echo "    | The emitted assembly really is bad — treat this as a codegen regression."
  fi
  return 0
}

## ---------------------------------------------------------------------------------------------
## THE PER-PROGRAM CEILING, AND TELLING A BREACH APART FROM THE GUEST'S OWN EXIT STATUS
##
## The ceiling exists to stop a program that does not TERMINATE; it does not measure the machine. It is
## deliberately NOT raised: a wall-clock threshold on a shared machine has no upper bound, so raising it
## only moves the load at which a false verdict returns (issue #537). What changes instead is what a
## breach MEANS — see `sweep_reobserve`.
##
## MEASURED, because nobody knew the margin and the consequence of breaching it was the worst in the
## gate (issue #585). EVERY guest of every sweep, timed one at a time (12 cores, load 2.6-5.0, so these
## are upper bounds for a quiet machine): one pass recording the whole distribution, plus three further
## passes recording each pass's slowest guest.
##
##   emulator       n     min    p50    p99    max     ceiling   margin at the max
##   qemu-aarch64   667   7ms    62ms   72ms   81ms    10s       123x
##   qemu-riscv64   667   7ms    64ms   78ms   84ms    10s       119x
##   wasmtime       764   7ms     8ms   10ms   12ms    10s       833x
##
## The shape of that distribution matters more than the margin. p50 and max are within a factor of 1.4,
## and the slowest guest was a DIFFERENT program on each of the three passes (a64: 311-arr_elem_enum,
## 720-slice_range_return, 288-str_array_elem_byte_index) — so ~60ms is qemu's fixed start-up cost, not
## a slow program, and this corpus has no hot spot at all. Contrast the corpus walk, where 2 pairs out
## of 8000 carried the whole exposure. A sweep row therefore cannot breach a 10s ceiling by being slow;
## it can only breach by being starved, or by not terminating. Keep these numbers honest: the one
## comment of this kind that already existed (the corpus walk's 30s justification) was off by 3x, and
## that stale figure is why the same file breached the ceiling twice before anyone re-measured it.

## Set the ceiling and the elapsed threshold that goes with it. `ALATYR_SWEEP_TIMEOUT` makes the
## ceiling reproducible from outside, as `ALATYR_CORPUS_TIMEOUT` already does for the corpus walk: with
## every guest of every sweep under 0.1 s, a SUB-SECOND ceiling is the only way to reproduce a breach on
## a quiet machine, so a decimal fraction is deliberately accepted. Whole seconds or a decimal only —
## `timeout`'s `s`/`m`/`h` suffixes are refused, because the breach test compares against elapsed WHOLE
## seconds and a suffix would silently read as its leading digits.
sweep_set_timeout() { # seconds
  case "$1" in
    ''|*[!0-9.]*|*.*.*|.|0|0.|0.0|0.00|0.000)
      echo "FAIL: the sweep ceiling must be a positive number of seconds without a unit suffix," >&2
      echo "  e.g. ALATYR_SWEEP_TIMEOUT=10 or =0.02; got '$1'" >&2
      return 1 ;;
  esac
  SWEEP_TIMEOUT="$1"
  ## Elapsed whole seconds at or after which a 124 may be read as a ceiling breach. `SECONDS` has
  ## whole-second resolution, so a child killed at an N-second ceiling can read N-1; erring this way
  ## costs a correctly-labelled WRONG only for a guest that exits 124 of its own accord within a second
  ## of the ceiling, while erring the other way loses a real breach. A sub-second ceiling floors to 0,
  ## which means every 124 under it is read as a breach — that ceiling is a reproduction aid, not a
  ## gate setting, and under it the exit-status ambiguity below is not resolvable at all.
  SWEEP_BREACH_AFTER="${SWEEP_TIMEOUT%%.*}"
  [ -n "$SWEEP_BREACH_AFTER" ] || SWEEP_BREACH_AFTER=0
  [ "$SWEEP_BREACH_AFTER" -gt 0 ] && SWEEP_BREACH_AFTER=$((SWEEP_BREACH_AFTER - 1))
  return 0
}
## `exit`, not `return`: this file is always SOURCED, and a sweep must not run its corpus against a
## ceiling nobody could parse. Exiting the sourcing shell is exactly the intended effect.
sweep_set_timeout "${ALATYR_SWEEP_TIMEOUT:-10}" || exit 1

## Run one guest under the ceiling, with the output discarded and stdin on /dev/null exactly as before.
## Prints nothing. Sets:
##   SWEEP_GOT      the child's exit status, verbatim
##   SWEEP_ELAPSED  whole seconds of wall clock the child was allowed
##   SWEEP_BREACH   1 when the CEILING ended the child, 0 when the child ended itself
##
## Why the elapsed time is consulted at all: `timeout` reports a ceiling breach as exit 124 and cannot
## distinguish that from a guest whose OWN exit status is 124, and a corpus program is allowed to exit
## 124 (AGENTS.md caps fixture exits below 126; no row wants 124 today, and a future one must not
## silently become unobservable). Reading every 124 as a breach would relabel a genuine wrong value as
## a machine-load artifact — the same class of mistake this file is fixing, pointed the other way. A
## breach cannot occur before the ceiling has elapsed, so the two are separable. `SECONDS` is used
## rather than `date` to keep two forks off every one of ~1900 guests; it counts in a subshell too.
## `sweep_set_timeout` owns the threshold and explains its off-by-one.
sweep_guest_run() { # cmd...
  _gr_t0=$SECONDS
  timeout "$SWEEP_TIMEOUT" "$@" >/dev/null 2>&1 < /dev/null
  SWEEP_GOT=$?
  SWEEP_ELAPSED=$((SECONDS - _gr_t0))
  SWEEP_BREACH=0
  [ "$SWEEP_GOT" = 124 ] && [ "$SWEEP_ELAPSED" -ge "$SWEEP_BREACH_AFTER" ] && SWEEP_BREACH=1
  return 0
}

## A private, empty scratch directory for one sweep; sets `SWEEP_DIR`.
sweep_scratch() {
  SWEEP_DIR="$1/target/sweep/$2"
  rm -rf "$SWEEP_DIR"
  mkdir -p "$SWEEP_DIR"
}

## The corpus is every `run <name> <want>` line of the e2e table. Reported so a truncated sweep
## (see the `< /dev/null` note above) is visible as a number that no longer adds up.
sweep_corpus_size() { grep -cE "^run [a-z]" "$1/scripts/e2e.sh"; }

## Final accounting: the loop must have VISITED every corpus program. A sweep that silently
## processed fewer programs than the corpus holds is a weaker gate that still looks green, so the
## mismatch is a hard failure rather than a footnote.
## Args: label seen corpus
sweep_check_total() {
  _ct_tag="$1"; _ct_seen="$2"; _ct_corpus="$3"
  [ "$_ct_seen" = "$_ct_corpus" ] && return 0
  echo "FAIL: ${_ct_tag}: visited $_ct_seen of $_ct_corpus corpus programs"
  echo "  The sweep loop ended early — a corpus program consuming the loop's own stdin is the"
  echo "  usual cause. The counts printed above are NOT a full sweep and must not be read as one."
  return 1
}

## ---------------------------------------------------------------------------------------------
## PARALLEL EXECUTION
##
## The corpus is ~640 programs and each sweep does an independent emit + assemble + link + emulate
## chain per program, so all three sweeps were pure serial latency: 4 m 10 s of the gate for ~1 900
## chains that never touch each other. `sweep_run_corpus` runs them on `$(nproc)` workers.
##
## What it deliberately does NOT change:
##   * the CORPUS DEFINITION — still `grep -E "^run [a-z]" scripts/e2e.sh`, so `corpus=` counts the
##     same rows, `missing=` counts the same absences, and `seen` is still checked against `corpus`;
##   * the VERDICT VOCABULARY — match / trap / reject / WRONG, decided by the backend's own callback;
##   * the DISTINCTION between "the assembler was not run" and "the assembler rejected the text":
##     a failure of the COMPILER's emit is a WRONG, a failure of `as`/`ld` is a `reject`. That
##     distinction is the whole point of these sweeps and a parallel rewrite is exactly where it gets
##     lost, so the callback still makes it, one row at a time, in the same order of operations;
##   * the ORDER OF THE OUTPUT — WRONG lines are printed in CORPUS order, not completion order, so
##     two runs over the same tree produce byte-identical output.
##
## What it adds: per-ROW scratch paths. They used to be keyed by fixture NAME, and the corpus
## contains the same name more than once (`run named_args 42` is registered twice), so two workers
## would have written one `.s`/`.o`/`.elf` between them.
## ---------------------------------------------------------------------------------------------

## Workers for the sweeps. Shares `ALATYR_JOBS` with scripts/e2e.sh; 1 = strict serial, in corpus order.
sweep_jobs() {
  _sj="${ALATYR_JOBS:-$(nproc 2>/dev/null || echo 4)}"
  case "$_sj" in ''|*[!0-9]*) _sj=1 ;; esac
  [ "$_sj" -ge 1 ] || _sj=1
  printf '%s' "$_sj"
}

## The corpus, one `run <name> <want>` row per line, in fixture-table order.
sweep_corpus_rows() { grep -E "^run [a-z]" "$1/scripts/e2e.sh"; }

## Drive the whole corpus through a per-row verdict function.
##
## Args: root, tag, verdict-fn.  The verdict function is called as `<fn> <scratch-prefix> <name> <want>`
## with stdin on /dev/null, and must print EXACTLY ONE line: `match`, `trap`, `reject`,
## `timeout <message>` (the per-program ceiling ended the guest — NOT a result), or `WRONG <message>`.
## Absent fixtures are settled here, before the callback, so every backend agrees.
##
## A `timeout` row is not classified from the parallel walk. Every one of them is re-observed serially
## once the walk is over (`sweep_reobserve`) and only the SECOND observation is classified, so a
## starved guest returns to its real verdict and a guest that breaches the ceiling twice is reported
## under its own `TIMED-OUT` class — never as a silent miscompile, and never as a pass either.
##
## Sets: SWEEP_SEEN SWEEP_MATCH SWEEP_TRAP SWEEP_REJECT SWEEP_MISSING SWEEP_WRONG SWEEP_LOST
## SWEEP_TIMEDOUT SWEEP_REOBS SWEEP_RECOVERED and prints the WRONG and TIMED-OUT lines, in corpus
## order. Returns 1 if anything is unaccounted for.
sweep_run_corpus() {
  _rc_root="$1"; _rc_tag="$2"; _rc_fn="$3"
  _rc_jobs="$(sweep_jobs)"
  mkdir -p "$SWEEP_DIR/v"
  sweep_corpus_rows "$_rc_root" > "$SWEEP_DIR/corpus.txt"
  SWEEP_SEEN=0
  _rc_running=0
  while read -r _ _rc_name _rc_want; do
    SWEEP_SEEN=$((SWEEP_SEEN + 1))
    while [ "$_rc_running" -ge "$_rc_jobs" ]; do wait -n 2>/dev/null; _rc_running=$((_rc_running - 1)); done
    (
      _w_idx="$SWEEP_SEEN"; _w_name="$_rc_name"; _w_want="$_rc_want"
      if [ ! -f "$_rc_root/test/$_w_name.al" ]; then
        echo missing > "$SWEEP_DIR/v/$_w_idx"
      else
        "$_rc_fn" "$SWEEP_DIR/$_w_idx-$_w_name" "$_w_name" "$_w_want" \
          > "$SWEEP_DIR/v/$_w_idx" 2> "$SWEEP_DIR/$_w_idx-$_w_name.stderr" < /dev/null
      fi
    ) < /dev/null &
    _rc_running=$((_rc_running + 1))
  done < "$SWEEP_DIR/corpus.txt"
  while [ "$_rc_running" -gt 0 ]; do wait -n 2>/dev/null; _rc_running=$((_rc_running - 1)); done

  ## Between the walk and the classification, and in that order: nothing of this sweep's is in flight
  ## any more, which is the whole point of the second observation.
  _rc_reobs_ok=1
  sweep_reobserve "$_rc_root" "$_rc_tag" "$_rc_fn" || _rc_reobs_ok=0

  SWEEP_MATCH=0; SWEEP_TRAP=0; SWEEP_REJECT=0; SWEEP_MISSING=0; SWEEP_WRONG=0; SWEEP_LOST=0
  SWEEP_TIMEDOUT=0
  _rc_i=0
  while read -r _ _rc_name _rc_want; do
    _rc_i=$((_rc_i + 1))
    _rc_v=""
    [ -f "$SWEEP_DIR/v/$_rc_i" ] && IFS= read -r _rc_v < "$SWEEP_DIR/v/$_rc_i"
    case "${_rc_v:-}" in
      match)   SWEEP_MATCH=$((SWEEP_MATCH + 1)) ;;
      trap)    SWEEP_TRAP=$((SWEEP_TRAP + 1)) ;;
      reject)  SWEEP_REJECT=$((SWEEP_REJECT + 1)) ;;
      missing) SWEEP_MISSING=$((SWEEP_MISSING + 1)) ;;
      ## A row that breached the ceiling in the parallel walk AND again on its own, with nothing else
      ## of this sweep's running. That is a program that does not terminate, or a machine that cannot
      ## finish it at all — a red gate under its own name, and deliberately not one of the classes
      ## above: `match`/`trap`/`reject` would hide it, and `WRONG` would claim an exit code nobody saw.
      timeout*) SWEEP_TIMEDOUT=$((SWEEP_TIMEDOUT + 1))
               echo "TIMED-OUT $_rc_name: ${_rc_v#timeout }"
               ## `$SWEEP_TIMEDOUT_WHY` is set by `sweep_reobserve` and says how many observations
               ## this verdict actually rests on. Hard-coding "and again when re-run alone" would be
               ## a claim about work that `ALATYR_SWEEP_REOBSERVE=0` skipped.
               echo "  $SWEEP_TIMEDOUT_WHY"
               echo "  The guest never produced an exit code, so this is NOT a wrong value and NOT a miscompile"
               echo "  finding: either the program does not terminate on this backend, or this machine could not"
               echo "  run it inside the ceiling. Reproduce with ALATYR_JOBS=1 and ALATYR_SWEEP_TIMEOUT=<n>." ;;
      WRONG*)  SWEEP_WRONG=$((SWEEP_WRONG + 1)); echo "WRONG $_rc_name: ${_rc_v#WRONG }" ;;
      *)       SWEEP_LOST=$((SWEEP_LOST + 1))
               echo "FAIL: ${_rc_tag}: corpus row $_rc_i ($_rc_name) produced no verdict — the runner"
               echo "  lost it. That is a harness failure, NOT a finding about the backend." ;;
    esac
  done < "$SWEEP_DIR/corpus.txt"
  [ "$SWEEP_WRONG" = 0 ] && [ "$SWEEP_LOST" = 0 ] && [ "$SWEEP_TIMEDOUT" = 0 ] && [ "$_rc_reobs_ok" = 1 ]
}

## ---------------------------------------------------------------------------------------------
## SERIAL RE-OBSERVATION OF A CEILING BREACH (issue #585, the sweeps' half of #537)
##
## `rc == 124 after N s` cannot tell a looping guest from a starved one, and no value of the ceiling
## can. The fine fact is cheap and was never asked for: run that one program again, alone, after the
## parallel walk has finished, and classify THAT observation. A guest that breaches the ceiling with
## nothing else of this gate's in flight has earned its own red class; one that finishes returns to
## whatever it actually is (`match`, `trap`, `reject` — or `WRONG`, which is still reported).
##
## Re-runs the whole verdict callback, not just the guest: the callback's unit of work is one corpus
## row's emit → assemble → link → run chain and it owns that row's scratch prefix, so the second
## observation is a complete, fresh observation of the same compiler. The exposure stays bounded to
## rows that breached at all — zero rows cost zero children.
##
## `ALATYR_SWEEP_REOBSERVE=0` keeps the old one-observation behaviour, so a run can be paired against
## its own control. It is not a gate verdict and says so.
##
## Sets: SWEEP_REOBS (rows re-observed) SWEEP_RECOVERED SWEEP_PERSISTED. Rewrites the verdict of every
## re-observed row with its second observation. Returns 1 only when the MECHANISM broke.
sweep_reobserve() { # root tag verdict-fn
  _ro_root="$1"; _ro_tag="$2"; _ro_fn="$3"
  SWEEP_REOBS=0; SWEEP_RECOVERED=0; SWEEP_PERSISTED=0
  SWEEP_TIMEDOUT_WHY="The ${SWEEP_TIMEOUT}s ceiling killed it in the parallel walk and again when it was re-run alone."
  : > "$SWEEP_DIR/timeouts.txt"
  _ro_i=0
  while read -r _ _ro_name _ro_want; do
    _ro_i=$((_ro_i + 1))
    _ro_v=""
    [ -f "$SWEEP_DIR/v/$_ro_i" ] && IFS= read -r _ro_v < "$SWEEP_DIR/v/$_ro_i"
    case "${_ro_v:-}" in
      timeout*) printf '%s\t%s\t%s\t%s\n' "$_ro_i" "$_ro_name" "$_ro_want" "$_ro_v" \
                  >> "$SWEEP_DIR/timeouts.txt" ;;
    esac
  done < "$SWEEP_DIR/corpus.txt"
  SWEEP_REOBS=$(grep -c '' < "$SWEEP_DIR/timeouts.txt")
  [ "$SWEEP_REOBS" = 0 ] && return 0

  if [ "${ALATYR_SWEEP_REOBSERVE:-1}" = 0 ]; then
    echo "${_ro_tag}: re-observation — ALATYR_SWEEP_REOBSERVE=0, so $SWEEP_REOBS ceiling breach(es) are being"
    echo "  classified from ONE observation taken while the whole corpus was in flight. That is the"
    echo "  mechanism issue #585 removed; this run is NOT a gate verdict."
    SWEEP_TIMEDOUT_WHY="The ${SWEEP_TIMEOUT}s ceiling killed it in the parallel walk. It was NOT re-observed (ALATYR_SWEEP_REOBSERVE=0), so this rests on ONE observation taken under load and is not a gate verdict."
    SWEEP_PERSISTED=$SWEEP_REOBS
    return 0
  fi

  echo "${_ro_tag}: re-observation — $SWEEP_REOBS corpus row(s) were killed by the ${SWEEP_TIMEOUT}s ceiling in the"
  echo "  parallel walk. The ceiling catches a guest that does not terminate; it does not measure the"
  echo "  machine. Each row is observed again ONE AT A TIME now that the walk is done, and the second"
  echo "  observation is the one that gets classified."
  echo "${_ro_tag}: re-observation   (load average now: $(sweep_loadavg), jobs were $(sweep_jobs))"
  _ro_t0=$SECONDS
  _ro_n=0
  while IFS="$(printf '\t')" read -r _ro_i _ro_name _ro_want _ro_first; do
    _ro_n=$((_ro_n + 1))
    echo "${_ro_tag}: re-observation   [$_ro_n/$SWEEP_REOBS] row $_ro_i ($_ro_name), serially…"
    echo "${_ro_tag}: re-observation       first observation: $_ro_first"
    "$_ro_fn" "$SWEEP_DIR/$_ro_i-$_ro_name" "$_ro_name" "$_ro_want" \
      > "$SWEEP_DIR/v/$_ro_i.second" 2> "$SWEEP_DIR/$_ro_i-$_ro_name.reobs.stderr" < /dev/null
    _ro_v2=""
    [ -f "$SWEEP_DIR/v/$_ro_i.second" ] && IFS= read -r _ro_v2 < "$SWEEP_DIR/v/$_ro_i.second"
    if [ -z "${_ro_v2:-}" ]; then
      echo "FAIL: ${_ro_tag}: the serial re-observation of row $_ro_i ($_ro_name) produced no verdict —"
      echo "  the re-observation mechanism is broken, so the first observation cannot be judged either."
      return 1
    fi
    ## The second observation REPLACES the first: that is the whole discipline. Nothing else writes
    ## this file after the walk, so the classification loop below reads exactly this line.
    printf '%s\n' "$_ro_v2" > "$SWEEP_DIR/v/$_ro_i"
    case "$_ro_v2" in
      timeout*) SWEEP_PERSISTED=$((SWEEP_PERSISTED + 1)); _ro_state=STILL-AT-THE-CEILING ;;
      *)        SWEEP_RECOVERED=$((SWEEP_RECOVERED + 1)); _ro_state=RECOVERED ;;
    esac
    printf '%s: re-observation   %-40s %s -> %s   %s\n' \
      "$_ro_tag" "$_ro_name" "timeout" "$_ro_v2" "$_ro_state"
  done < "$SWEEP_DIR/timeouts.txt"
  echo "${_ro_tag}: re-observation — $SWEEP_RECOVERED row(s) recovered, $SWEEP_PERSISTED still at the ceiling ($((SECONDS - _ro_t0))s)"
  return 0
}

sweep_loadavg() {
  if [ -r /proc/loadavg ]; then cut -d' ' -f1-3 /proc/loadavg; else printf 'unavailable'; fi
}

## THE GATE OF THE GATE for the parallel corpus driver (AGENTS.md: "an invariant nobody has seen fail
## is decoration"). A parallel rewrite of a sweep is exactly where a dropped row, a miscounted verdict
## or a lost WRONG line hides, and every one of those failures looks GREEN. So before touching the real
## corpus, each sweep drives `sweep_run_corpus` over a SYNTHETIC corpus whose every answer is known and
## checks the answer it gets back. Costs ~50 ms. Prints one line; returns 1 if the driver is broken.
sweep_selftest() { # tag
  _ss_tag="$1"
  _ss_keep_dir="$SWEEP_DIR"
  _ss_root="$SWEEP_DIR/selftest"
  rm -rf "$_ss_root"; mkdir -p "$_ss_root/scripts" "$_ss_root/test"
  # A synthetic fixture table. Note `run dup 4` TWICE: the real corpus does that too (`named_args`),
  # and name-keyed scratch paths are how two workers come to share one artifact.
  printf 'run m_match 42\nrun m_trap 42\nrun m_reject 42\nrun m_wrong1 42\nrun dup 4\nrun dup 4\nrun m_absent 42\nrun m_wrong2 42\nrun m_lost 42\n' \
    > "$_ss_root/scripts/e2e.sh"
  for _ss_f in m_match m_trap m_reject m_wrong1 dup m_wrong2 m_lost; do : > "$_ss_root/test/$_ss_f.al"; done
  ## Deliberately answers out of corpus order (a sleep on the first WRONG), so a driver that printed in
  ## COMPLETION order would be caught by the order assertion below.
  _ss_verdict() { # scratch-prefix, name, want
    case "$2" in
      m_match)  echo match ;;
      m_trap)   echo trap ;;
      m_reject) echo reject ;;
      dup)      printf 'match\n' > "$1.dup"; echo match ;;
      m_wrong1) sleep 0.4; echo "WRONG synthetic=1 want=42 (self-test)" ;;
      m_wrong2) echo "WRONG synthetic=2 want=42 (self-test)" ;;
      m_lost)   ;;                     # prints NOTHING: the runner must notice and say so
      *)        echo "WRONG unexpected fixture $2" ;;
    esac
  }
  SWEEP_DIR="$_ss_root/scratch"; rm -rf "$SWEEP_DIR"; mkdir -p "$SWEEP_DIR"
  # NOT a command substitution: `sweep_run_corpus` SETS the counters, and a `$( )` would set them in
  # a subshell and throw them away — which is how a self-test comes to assert nothing at all.
  sweep_run_corpus "$_ss_root" "${_ss_tag}_selftest" _ss_verdict > "$_ss_root/out.txt" 2>&1
  _ss_rc=$?
  _ss_out="$(cat "$_ss_root/out.txt")"
  SWEEP_DIR="$_ss_keep_dir"
  unset -f _ss_verdict
  _ss_bad=""
  [ "$_ss_rc" = 1 ]        || _ss_bad="$_ss_bad returned-0-despite-WRONGs"
  [ "$SWEEP_SEEN" = 9 ]    || _ss_bad="$_ss_bad seen=$SWEEP_SEEN(want 9)"
  [ "$SWEEP_MATCH" = 3 ]   || _ss_bad="$_ss_bad match=$SWEEP_MATCH(want 3)"
  [ "$SWEEP_TRAP" = 1 ]    || _ss_bad="$_ss_bad trap=$SWEEP_TRAP(want 1)"
  [ "$SWEEP_REJECT" = 1 ]  || _ss_bad="$_ss_bad reject=$SWEEP_REJECT(want 1)"
  [ "$SWEEP_MISSING" = 1 ] || _ss_bad="$_ss_bad missing=$SWEEP_MISSING(want 1)"
  [ "$SWEEP_WRONG" = 2 ]   || _ss_bad="$_ss_bad wrong=$SWEEP_WRONG(want 2)"
  [ "$SWEEP_LOST" = 1 ]    || _ss_bad="$_ss_bad lost=$SWEEP_LOST(want 1)"
  case "$_ss_out" in
    *"WRONG m_wrong1: synthetic=1"*) ;;
    *) _ss_bad="$_ss_bad first-WRONG-line-missing" ;;
  esac
  case "$_ss_out" in
    *"WRONG m_wrong1"*"WRONG m_wrong2"*) ;;
    *) _ss_bad="$_ss_bad WRONGs-not-in-corpus-order" ;;
  esac
  case "$_ss_out" in
    *"corpus row 9 (m_lost) produced no verdict"*) ;;
    *) _ss_bad="$_ss_bad lost-row-not-named" ;;
  esac
  if [ -z "$_ss_bad" ]; then
    echo "${_ss_tag}: selftest ok (9 synthetic rows: 3 match / 1 trap / 1 reject / 1 missing / 2 WRONG / 1 lost, WRONGs in corpus order)"
    return 0
  fi
  echo "FAIL: ${_ss_tag}: the parallel corpus driver is broken —$_ss_bad"
  echo "  The sweep was NOT run: this driver cannot be trusted to report a silent miscompile, and a"
  echo "  green sweep from a broken driver is worse than a red one. Its own output was:"
  printf '%s\n' "$_ss_out" | sed 's/^/    | /'
  return 1
}

## THE GATE OF THE GATE for the ceiling, in BOTH directions and in ONE run (issue #585).
##
## A mechanism that only ever un-fails a row is an eraser, not a measurement, so the genuine-hang
## direction is asserted first and the recovery second — over the same synthetic corpus, in the same
## `sweep_run_corpus` call, so neither can be green while the other is broken. It also covers the two
## functions that DECIDE an outcome and had no self-test of their own before this: `sweep_guest_run`,
## which alone separates a ceiling breach from the guest's own exit status, and `sweep_check_total`,
## which alone decides that a truncated corpus is a failure rather than a footnote. (The e2e half of
## #537 found exactly that shape of blind spot in `_e2e_runtime_failure`: the one function deciding
## whether a ceiling breach counts left the whole suite green when its timeout arm was neutered.)
##
## Costs ~1.2 s: three real children for `sweep_guest_run`, none for the corpus directions.
## Prints one line; returns 1 if the ceiling mechanism is broken.
sweep_reobserve_selftest() { # tag
  _rs_tag="$1"
  _rs_keep_dir="$SWEEP_DIR"
  _rs_keep_timeout="$SWEEP_TIMEOUT"
  _rs_root="$SWEEP_DIR/reobs-selftest"
  rm -rf "$_rs_root"; mkdir -p "$_rs_root/scripts" "$_rs_root/test"
  _rs_bad=""

  ## ---- `sweep_guest_run`: a real ceiling breach, and a real 124 that is NOT one. -----------------
  sweep_set_timeout 1 || _rs_bad="$_rs_bad set_timeout-refused-1"
  sweep_guest_run /bin/sh -c 'sleep 5'
  [ "$SWEEP_GOT" = 124 ] && [ "$SWEEP_BREACH" = 1 ] \
    || _rs_bad="$_rs_bad guest_run-missed-a-real-breach(got=$SWEEP_GOT breach=$SWEEP_BREACH)"
  ## 30 s, not 2: the threshold is then 29 elapsed seconds, so an instant child cannot read its way
  ## over it when a whole-second boundary happens to fall inside the fork. (Measured: at a 2 s ceiling
  ## this assertion flaked under load, reading elapsed=1 against a threshold of 1.)
  sweep_set_timeout 30 || _rs_bad="$_rs_bad set_timeout-refused-30"
  sweep_guest_run /bin/sh -c 'exit 124'
  [ "$SWEEP_GOT" = 124 ] && [ "$SWEEP_BREACH" = 0 ] \
    || _rs_bad="$_rs_bad guest_run-called-a-guest's-own-124-a-breach(elapsed=$SWEEP_ELAPSED)"
  sweep_guest_run /bin/sh -c 'exit 42'
  [ "$SWEEP_GOT" = 42 ] && [ "$SWEEP_BREACH" = 0 ] \
    || _rs_bad="$_rs_bad guest_run-mangled-an-ordinary-exit(got=$SWEEP_GOT breach=$SWEEP_BREACH)"
  ## The validator is a decider too: a malformed ceiling must be refused, not silently read as its
  ## leading digits, and a sub-second one must be accepted (it is the only reproducible breach).
  for _rs_t in 10s 1m '' abc 0 0.0 1.2.3 -5; do
    if sweep_set_timeout "$_rs_t" 2>/dev/null; then _rs_bad="$_rs_bad set_timeout-accepted('$_rs_t')"; fi
  done
  sweep_set_timeout 0.02 2>/dev/null || _rs_bad="$_rs_bad set_timeout-refused-a-sub-second-ceiling"
  [ "$SWEEP_BREACH_AFTER" = 0 ] || _rs_bad="$_rs_bad sub-second-ceiling-threshold=$SWEEP_BREACH_AFTER(want 0)"
  sweep_set_timeout 30 2>/dev/null || _rs_bad="$_rs_bad set_timeout-refused-30"
  [ "$SWEEP_BREACH_AFTER" = 29 ] || _rs_bad="$_rs_bad 30s-ceiling-threshold=$SWEEP_BREACH_AFTER(want 29)"
  sweep_set_timeout "$_rs_keep_timeout" || _rs_bad="$_rs_bad set_timeout-refused-the-real-ceiling"

  ## ---- `sweep_check_total`: the truncated-corpus decision. ---------------------------------------
  sweep_check_total probe 640 640 > "$_rs_root/total_ok.txt" 2>&1 \
    || _rs_bad="$_rs_bad check_total-failed-a-complete-corpus"
  [ -s "$_rs_root/total_ok.txt" ] && _rs_bad="$_rs_bad check_total-was-noisy-about-a-complete-corpus"
  if sweep_check_total probe 639 640 > "$_rs_root/total_bad.txt" 2>&1; then
    _rs_bad="$_rs_bad check_total-passed-a-TRUNCATED-corpus"
  fi
  grep -q "visited 639 of 640 corpus programs" "$_rs_root/total_bad.txt" \
    || _rs_bad="$_rs_bad check_total-did-not-name-the-counts"

  ## ---- the two ceiling directions, over one synthetic corpus. -------------------------------------
  ## `t_hang` breaches every time it is observed; `t_starved` breaches once and then finishes with the
  ## exit code it was always going to produce; `m_plain` never breaches and must be observed EXACTLY
  ## once, which is what proves the re-observation costs nothing when nothing timed out.
  printf 'run m_plain 42\nrun t_hang 42\nrun t_starved 42\n' > "$_rs_root/scripts/e2e.sh"
  for _rs_f in m_plain t_hang t_starved; do : > "$_rs_root/test/$_rs_f.al"; done
  _rs_verdict() { # scratch-prefix, name, want
    printf 'x\n' >> "$_rs_root/observed.$2"
    case "$2" in
      m_plain)   echo match ;;
      t_hang)    echo "timeout synthetic did not finish inside ${SWEEP_TIMEOUT}s (self-test)" ;;
      t_starved) if [ -f "$_rs_root/starved.seen" ]; then echo match
                 else : > "$_rs_root/starved.seen"
                      echo "timeout synthetic did not finish inside ${SWEEP_TIMEOUT}s (self-test)"; fi ;;
      *)         echo "WRONG unexpected fixture $2" ;;
    esac
  }
  ## One drive of the real `sweep_run_corpus` over that corpus. `$1` is the re-observation setting, so
  ## the escape hatch is exercised here and CANNOT switch the self-test off: a self-test that obeyed the
  ## operator's flag would stop testing the mechanism exactly when someone disabled it.
  _rs_drive() { # reobserve-setting out-file
    rm -f "$_rs_root/starved.seen" "$_rs_root"/observed.*
    SWEEP_DIR="$_rs_root/scratch"; rm -rf "$SWEEP_DIR"; mkdir -p "$SWEEP_DIR"
    # NOT a command substitution: `sweep_run_corpus` SETS the counters (see `sweep_selftest`).
    ALATYR_SWEEP_REOBSERVE="$1" \
      sweep_run_corpus "$_rs_root" "${_rs_tag}_reobs_selftest" _rs_verdict > "$2" 2>&1
    _rs_rc=$?
    _rs_out="$(cat "$2")"
    SWEEP_DIR="$_rs_keep_dir"
  }
  _rs_drive 1 "$_rs_root/out.txt"

  ## Direction 1 — the genuine hang must survive as a reported failure, under its OWN class.
  [ "$_rs_rc" = 1 ]         || _rs_bad="$_rs_bad returned-0-despite-a-persistent-breach"
  [ "$SWEEP_TIMEDOUT" = 1 ] || _rs_bad="$_rs_bad timedout=${SWEEP_TIMEDOUT:-unset}(want 1)"
  [ "$SWEEP_PERSISTED" = 1 ] || _rs_bad="$_rs_bad persisted=${SWEEP_PERSISTED:-unset}(want 1)"
  case "$_rs_out" in
    *"TIMED-OUT t_hang"*) ;;
    *) _rs_bad="$_rs_bad hang-not-reported-under-its-own-name" ;;
  esac
  case "$_rs_out" in
    *"STILL-AT-THE-CEILING"*) ;;
    *) _rs_bad="$_rs_bad hang-not-re-observed" ;;
  esac
  ## The point of the whole change: a ceiling breach must never be announced as the forbidden verdict.
  case "$_rs_out" in
    *"SILENT MISCOMPILE"*) _rs_bad="$_rs_bad ceiling-breach-called-a-SILENT-MISCOMPILE" ;;
    *"WRONG t_hang"*)      _rs_bad="$_rs_bad ceiling-breach-classified-WRONG" ;;
  esac
  [ "${SWEEP_WRONG:-x}" = 0 ] || _rs_bad="$_rs_bad wrong=${SWEEP_WRONG:-unset}(want 0)"

  ## Direction 2 — the starved row must come back as its SECOND observation, and not be reported.
  [ "$SWEEP_RECOVERED" = 1 ] || _rs_bad="$_rs_bad recovered=${SWEEP_RECOVERED:-unset}(want 1)"
  [ "$SWEEP_MATCH" = 2 ]     || _rs_bad="$_rs_bad match=${SWEEP_MATCH:-unset}(want 2: m_plain + the recovered t_starved)"
  case "$_rs_out" in
    *"RECOVERED"*) ;;
    *) _rs_bad="$_rs_bad recovery-not-reported" ;;
  esac
  case "$_rs_out" in
    *"TIMED-OUT t_starved"*) _rs_bad="$_rs_bad recovered-row-still-reported-as-TIMED-OUT" ;;
  esac

  ## Accounting: both breached rows were re-observed, and the row that did not breach was observed
  ## exactly once — a re-observation that re-ran the whole corpus would be a different mechanism.
  [ "$SWEEP_REOBS" = 2 ] || _rs_bad="$_rs_bad reobserved=${SWEEP_REOBS:-unset}(want 2)"
  _rs_n_plain=$(grep -c '' < "$_rs_root/observed.m_plain" 2>/dev/null || echo 0)
  _rs_n_hang=$(grep -c '' < "$_rs_root/observed.t_hang" 2>/dev/null || echo 0)
  _rs_n_starved=$(grep -c '' < "$_rs_root/observed.t_starved" 2>/dev/null || echo 0)
  [ "$_rs_n_plain" = 1 ]   || _rs_bad="$_rs_bad m_plain-observed-$_rs_n_plain-time(s)(want 1)"
  [ "$_rs_n_hang" = 2 ]    || _rs_bad="$_rs_bad t_hang-observed-$_rs_n_hang-time(s)(want 2)"
  [ "$_rs_n_starved" = 2 ] || _rs_bad="$_rs_bad t_starved-observed-$_rs_n_starved-time(s)(want 2)"

  ## Direction 3 — the escape hatch. `ALATYR_SWEEP_REOBSERVE=0` restores the one-observation mechanism
  ## this change removed, and it must say so and stay RED. It must never quietly drop a breach: a flag
  ## that erased breaches instead of leaving them unexplained would be the same eraser, wearing a
  ## switch. Note the *reported* class is still TIMED-OUT and never `WRONG` — the old behaviour being
  ## restored is the missing SECOND OBSERVATION, not the false miscompile verdict.
  _rs_drive 0 "$_rs_root/out0.txt"
  [ "$_rs_rc" = 1 ]         || _rs_bad="$_rs_bad reobserve=0-returned-0"
  [ "$SWEEP_TIMEDOUT" = 2 ] || _rs_bad="$_rs_bad reobserve=0-timedout=${SWEEP_TIMEDOUT:-unset}(want 2)"
  [ "$SWEEP_RECOVERED" = 0 ] || _rs_bad="$_rs_bad reobserve=0-recovered=$SWEEP_RECOVERED(want 0)"
  case "$_rs_out" in
    *"NOT a gate verdict"*) ;;
    *) _rs_bad="$_rs_bad reobserve=0-did-not-disclaim-itself" ;;
  esac
  case "$_rs_out" in
    *"SILENT MISCOMPILE"*) _rs_bad="$_rs_bad reobserve=0-called-a-breach-a-SILENT-MISCOMPILE" ;;
  esac
  [ "$(grep -c '' < "$_rs_root/observed.t_hang" 2>/dev/null || echo 0)" = 1 ] \
    || _rs_bad="$_rs_bad reobserve=0-still-re-observed"
  unset -f _rs_verdict _rs_drive

  if [ -z "$_rs_bad" ]; then
    echo "${_rs_tag}: selftest ok (re-observation: a guest that breaches the ceiling twice is reported as TIMED-OUT and never as a miscompile; one that breaches only under the parallel walk returns to its second observation; a ceiling breach and a guest's own exit 124 are told apart; a truncated corpus still fails)"
    return 0
  fi
  echo "FAIL: ${_rs_tag}: the ceiling mechanism is broken —$_rs_bad"
  echo "  The sweep was NOT run. This mechanism decides whether a wall-clock breach is reported as a"
  echo "  silent miscompile, so a broken one either invents the one forbidden verdict or erases it."
  printf '%s\n' "$_rs_out" | sed 's/^/    | /'
  return 1
}
