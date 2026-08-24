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
## with stdin on /dev/null, and must print EXACTLY ONE line: `match`, `trap`, `reject`, or
## `WRONG <message>`. Absent fixtures are settled here, before the callback, so every backend agrees.
##
## Sets: SWEEP_SEEN SWEEP_MATCH SWEEP_TRAP SWEEP_REJECT SWEEP_MISSING SWEEP_WRONG SWEEP_LOST
## and prints the WRONG lines, in corpus order. Returns 1 if anything is unaccounted for.
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

  SWEEP_MATCH=0; SWEEP_TRAP=0; SWEEP_REJECT=0; SWEEP_MISSING=0; SWEEP_WRONG=0; SWEEP_LOST=0
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
      WRONG*)  SWEEP_WRONG=$((SWEEP_WRONG + 1)); echo "WRONG $_rc_name: ${_rc_v#WRONG }" ;;
      *)       SWEEP_LOST=$((SWEEP_LOST + 1))
               echo "FAIL: ${_rc_tag}: corpus row $_rc_i ($_rc_name) produced no verdict — the runner"
               echo "  lost it. That is a harness failure, NOT a finding about the backend." ;;
    esac
  done < "$SWEEP_DIR/corpus.txt"
  [ "$SWEEP_WRONG" = 0 ] && [ "$SWEEP_LOST" = 0 ]
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
