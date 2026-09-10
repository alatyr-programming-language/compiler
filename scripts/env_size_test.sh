#!/usr/bin/env bash
# scripts/env_size_test.sh — the environment-size regression for the process-spawn path (src/cli.al).
#
# THE DEFECT THIS LOCKS. `link_exe` read `/proc/self/environ` into a 65536-byte arena buffer and
# handed the bytes to `build_envp`, which sized its execve `envp` pointer array as
# `(NUL count + 1) * 8`. When the environment did not fit, the read stopped MID-ENTRY, so the
# buffer's last entry had no NUL: the fill loop then emitted one pointer MORE than the NUL count
# and wrote its terminating 0 word 8 bytes PAST the reserved block. The last in-bounds slot kept a
# pointer instead of the terminator, `execve` walked off the end of the array into whatever the
# arena handed out next (the `<dir>/as` PATH-probe strings `resolve_in_path` built right after),
# and failed EFAULT. The child exited 127, and the driver reported
#   alatyr: the assembler (`as`) rejected the emitted assembly
# — a codegen diagnosis for a driver defect, on assembly `as` never even read.
#
# Two independent things are asserted, because either alone can regress:
#   1. a LARGE BUT LEGAL environment builds successfully (no truncation at a 64 KiB cliff), and
#   2. no failure of the spawn path is ever reported as "the assembler rejected the assembly".
#
# Run standalone:  nix develop -c bash scripts/env_size_test.sh
# `ALATYR` overrides the compiler under test (default: `target/alatyr`, the just-built Stage1).
# The FROZEN SEED no longer carries the defect — the 2026-08-19/20 promote carried the envp fix into
# the bootstrap binary itself (see the 2026-08-19/20 entries in `seed/VERSION`; without the fix every
# gate failed at "seed builds Stage1" in a
# shell whose environment exceeded ~64 KiB). Measured 2026-08-21: `ALATYR=seed/alatyr` passes all 11
# assertions. The subject here is still the tree's own compiler, not the seed.
#
# ## PROOF OF WORK
#
# Every verdict goes through `pass`/`flunk`, which COUNT it, and the final line refuses to be green
# unless exactly `EXPECT_ASSERTIONS` verdicts were printed. A check that stops being reached — an
# early `return`, a `case` arm that swallows a branch, a loop whose bounds went empty — then turns
# the suite red instead of quietly shrinking it, which is the one failure mode a green-only script
# cannot report about itself. (`scripts/e2e.sh` replays these lines verbatim and counts them into
# its own `assertions=`, so the count is also visible from outside.)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${ALATYR:-$ROOT/target/alatyr}"
EXPECT_ASSERTIONS=11

if [ ! -x "$CC" ]; then
  echo "FAIL env_size: compiler not found at $CC" >&2
  echo "build it first with: seed/alatyr build package.al" >&2
  exit 1
fi

fail=0
checks=0
pass()  { checks=$((checks + 1)); echo "ok   $*"; }
flunk() { checks=$((checks + 1)); fail=1; echo "FAIL $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

## The final verdict, factored out under its own name so a self-test can drive the REAL decision.
## It is the SECOND decider in this file: `flunk` decides that one observation is a failure, and
## this decides that the run as a whole is one — including the coverage half, where a check that
## silently stopped being REACHED turns the suite red instead of quietly shrinking it.
env_size_verdict() { # checks-run failures-seen expected
  local _c="$1" _rc="$2" _e="$3"
  if [ "$_c" != "$_e" ]; then
    _rc=1
    echo "FAIL env_size: $_c assertions ran, expected $_e — a check was not reached"
  fi
  if [ "$_rc" = "0" ]; then
    echo "ok   env_size: all checks passed ($_c assertions)"
  else
    echo "FAIL env_size ($_c assertions ran)"
  fi
  return "$_rc"
}

# ==========================================================================================
# THE GATE OF THE GATE (issue #600) — this file's own verdict machinery, planted against.
#
# `flunk` is the ONLY function here that turns an observation into a failure, and `env_size_verdict`
# is the only one that turns the run into one. Neither had a self-test, which is the shape #584
# found in `_e2e_runtime_failure`, #585 in `sweep_check_total` and #599 in `allowed`/`mod_allowed`.
# Measured on the parent, with one assertion planted to fail: turning `flunk` into a note left the
# stage printing `ok   env_size: all checks passed (11 assertions)` and exiting 0 — every failure
# this suite can find routed into a footnote, and `ext_test env_size_test` green with it.
#
# Costs ~0: no compiler, no child, no build. It drives the real functions with synthetic verdicts,
# in a SUBSHELL, and records what it found in files — a bash arithmetic error or a `set -u` unbound
# variable inside a driven function unwinds to top level and ENDS THE SCRIPT, so a diagnostic
# written for that case can never print. The completion marker below is what notices instead.
ENV_SIZE_SELFTEST_EXPECTED=14
env_size_selftest() {
  local st="$WORK/selftest" bad="" k=0 out
  rm -rf "$st"; mkdir -p "$st"
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }

  # ---- 1 · `pass` and `flunk`: the per-observation decider, both directions. ----------------
  # Both must COUNT, only one may fail, and each must say so in the line the caller reads (this
  # script's lines are replayed verbatim by `ext_test env_size_test` and counted into e2e's
  # `assertions=`, so the wording is an interface, not decoration).
  fail=0; checks=0
  pass "selftest probe" > "$st/pass.out" 2>&1
  [ "$fail" = 0 ];   _ck $? pass-recorded-a-failure
  [ "$checks" = 1 ]; _ck $? "pass-did-not-count-its-verdict(checks=$checks)"
  grep -qx 'ok   selftest probe' "$st/pass.out"; _ck $? pass-did-not-print-its-ok-line

  fail=0; checks=0
  flunk "selftest probe" > "$st/flunk.out" 2>&1
  [ "$fail" = 1 ];   _ck $? flunk-did-not-record-the-failure
  [ "$checks" = 1 ]; _ck $? "flunk-did-not-count-its-verdict(checks=$checks)"
  grep -qx 'FAIL selftest probe' "$st/flunk.out"; _ck $? flunk-did-not-print-its-FAIL-line
  grep -q '^ok' "$st/flunk.out"; [ $? = 1 ]; _ck $? flunk-called-a-failure-ok

  # ---- 2 · `env_size_verdict`: the run-level decider, all four directions. ------------------
  # 2a a complete, clean run is green and says how much it covered.
  out="$(env_size_verdict 11 0 11 2>&1)"; _ck $? verdict-failed-a-clean-complete-run
  case "$out" in *'all checks passed (11 assertions)'*) _ck 0 x ;;
                 *) _ck 1 "verdict-did-not-report-its-coverage($out)" ;; esac
  # 2b a complete run holding a failure is red, and does NOT claim everything passed.
  out="$(env_size_verdict 11 1 11 2>&1)"; [ $? = 1 ]; _ck $? verdict-passed-a-run-with-a-failure
  case "$out" in *'all checks passed'*) _ck 1 verdict-claimed-a-failed-run-passed ;;
                 *) _ck 0 x ;; esac
  # 2c a run that lost a check is red even though nothing said FAIL — the coverage half, and the
  #    one failure mode a green-only script cannot report about itself.
  out="$(env_size_verdict 10 0 11 2>&1)"; [ $? = 1 ]; _ck $? verdict-passed-a-run-that-lost-a-check
  case "$out" in *'10 assertions ran, expected 11'*) _ck 0 x ;;
                 *) _ck 1 "verdict-did-not-name-the-missing-coverage($out)" ;; esac
  # 2d …and one that ran MORE than it owes is red too: the count is an identity, not a floor.
  out="$(env_size_verdict 12 0 11 2>&1)"; [ $? = 1 ]; _ck $? verdict-passed-a-run-with-an-unexpected-extra-check

  printf '%s' "$bad" > "$st/bad"
  printf '%s' "$k"   > "$st/checks"
  : > "$st/complete"
  if [ -n "$bad" ]; then
    echo "*** env_size selftest: FAILED —$bad ***"
    return 1
  fi
  if [ "$k" -lt "$ENV_SIZE_SELFTEST_EXPECTED" ]; then
    echo "*** env_size selftest: ran $k checks, expected at least $ENV_SIZE_SELFTEST_EXPECTED — a"
    echo "    self-test that reports fewer checks than it owes is a failure, not a shortcut ***"
    return 1
  fi
  echo "ok   env_size selftest: $k checks — pass/flunk in both directions, and the run-level"
  echo "     verdict on a clean run, a failed run, a run that lost a check and one that gained one"
  return 0
}
## In a SUBSHELL, and the verdict is read from what it RECORDED, so neither an unwind to top level
## nor a defect in its own reporting branch can turn a failed self-test into a green line.
( env_size_selftest ); ENV_SIZE_SELFTEST_RC=$?
if [ ! -f "$WORK/selftest/complete" ]; then
  echo "FAIL env_size selftest: did NOT run to completion (rc=$ENV_SIZE_SELFTEST_RC) — it recorded no"
  echo "     verdict, so this run proves nothing about pass/flunk or the run-level verdict"
  exit 1
fi
if [ -s "$WORK/selftest/bad" ]; then
  echo "FAIL env_size selftest: recorded failures — $(cat "$WORK/selftest/bad")"
  exit 1
fi
if [ "$(cat "$WORK/selftest/checks")" -lt "$ENV_SIZE_SELFTEST_EXPECTED" ]; then
  echo "FAIL env_size selftest: recorded $(cat "$WORK/selftest/checks") checks, expected at least"
  echo "     $ENV_SIZE_SELFTEST_EXPECTED"
  exit 1
fi
[ "$ENV_SIZE_SELFTEST_RC" = 0 ] || exit 1

# A tiny package, so each repetition costs a fraction of a second instead of a whole self-build.
mkdir -p "$WORK/pkg/src"
cat > "$WORK/pkg/src/main.al" <<'AL'
main := fn() -> u64 {
  return 7
}
AL
cat > "$WORK/pkg/package.al" <<'AL'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "env-probe",
    ),
  ],
)
AL

## Build `pkg` with an environment padded to roughly `$1` bytes; echo "<rc>|<first stderr line>".
## The padding is spread over many ~4 KiB variables: the kernel caps a SINGLE argument/environment
## string at MAX_ARG_STRLEN (128 KiB), so one huge variable would be rejected by execve itself and
## would test nothing.
build_with_env() {
  local pad="$1" out rc i n
  local chunk
  chunk="$(head -c 4000 /dev/zero | tr '\0' 'x')"
  n=$(( pad / 4008 + 1 ))
  local -a envargs=()
  for i in $(seq 1 "$n"); do envargs+=("PAD$i=$chunk"); done
  out=$(env "${envargs[@]}" "$CC" build "$WORK/pkg/package.al" 2>&1 </dev/null)
  rc=$?
  printf '%s|%s\n' "$rc" "$(printf '%s' "$out" | head -1)"
}

## 1. A large but entirely legal environment must BUILD. 64 KiB and 256 KiB both used to fail:
##    the environ read capped at 65536 (and the `-o`/`run` paths at 65536), so every environment
##    past that cliff produced a malformed envp.
check_large_env_builds() {
  local pad r rc msg
  for pad in 40000 80000 300000; do
    r="$(build_with_env "$pad")"
    rc="${r%%|*}"; msg="${r#*|}"
    if [ "$rc" = "0" ]; then
      pass "env_size(pad=$pad): a $((pad/1024)) KiB-padded environment builds"
    else
      flunk "env_size(pad=$pad): build exited $rc: $msg"
    fi
  done
}

## 2. Whatever happens on the spawn path, it must never be reported as an assembler REJECTION.
##    "`as` ran and rejected the input" and "the driver could not hand the input to `as`" are
##    different diagnoses (Tooling §6.1); collapsing them is what hid this defect for weeks.
check_no_false_codegen_diagnosis() {
  local pad r rc msg
  for pad in 40000 80000 300000 900000; do
    r="$(build_with_env "$pad")"
    rc="${r%%|*}"; msg="${r#*|}"
    case "$msg" in
      *"rejected the emitted assembly"*)
        flunk "env_size(pad=$pad): an environment-size fault was reported as an assembler rejection: $msg"
        ;;
      *)
        pass "env_size(pad=$pad): no false codegen diagnosis (rc=$rc)"
        ;;
    esac
  done
}

## 3. The compiler's OWN build, repeated, must be stable — the shape the sweeps run. The defect was
##    probabilistic, so a single green build proves nothing; `ALATYR_ENV_REPS` raises the count.
##    The repetitions run under the padded environment as well, which is the shape that made the
##    fault frequent (the environ read is per-link, so every build re-rolls the dice).
##
##    THE REPETITIONS ARE ONE ASSERTION REPEATED FOR CONFIDENCE, NOT A LADDER. `chunk`, `n` and
##    `envargs` are computed ONCE, above the loop, and every iteration then runs the identical
##    command with the identical environment: nothing varies with `i`, and no rep reads anything the
##    previous rep produced (a rep's inputs are `$CC`, `package.al` and `src/`, all read-only here).
##    The environment-SIZE ladder is checks 1 and 2 (40/80/300/900 KiB), not this loop. So the reps
##    were serial for one reason only: they all wrote the SHARED `$ROOT/target/`. That also meant
##    they rewrote `target/alatyr` — the compiler under test — mid-gate, with `scripts/e2e.sh`'s
##    workers executing it (which is why that gate hands us a SNAPSHOT), and in a standalone run
##    where `$CC` defaults to `$ROOT/target/alatyr` it silently replaced `$CC` itself between reps.
##    Each rep now builds through its OWN package tree: a copy of `src/` and the existing
##    source_dir="src" manifest live under its OWN directory, so both `source_dir` and `target_dir`
##    resolve inside that package. The reps are independent, run concurrently, and touch nothing
##    under `$ROOT/target`. Every rep's artifact remains byte-identical to an in-place self-build.
check_repeated_self_build() {
  local reps="${ALATYR_ENV_REPS:-8}" i rc chunk n j bad=0 lost=0
  local repdir reps_dir="$WORK/reps"
  chunk="$(head -c 4000 /dev/zero | tr '\0' 'x')"
  n=$(( ${ALATYR_ENV_PAD:-80000} / 4008 + 1 ))
  local -a envargs=()
  for j in $(seq 1 "$n"); do envargs+=("PAD$j=$chunk"); done
  for i in $(seq 1 "$reps"); do
    repdir="$reps_dir/$i"
    mkdir -p "$repdir"
    cp "$ROOT/package.al" "$repdir/package.al"
    cp -r "$ROOT/src" "$repdir/src"
    (
      env "${envargs[@]}" "$CC" build "$repdir/package.al" >"$repdir/self.log" 2>&1 </dev/null
      echo "$?" > "$repdir/rc"
    ) &
  done
  wait
  for i in $(seq 1 "$reps"); do
    repdir="$reps_dir/$i"
    ## a rep with no recorded status is a LOST rep, not a passing one: with the reps running
    ## concurrently, "nothing was reported" must never read as "nothing went wrong".
    if [ ! -f "$repdir/rc" ]; then
      lost=$((lost + 1))
      echo "     self-build $i reported no status at all"
      continue
    fi
    rc="$(cat "$repdir/rc")"
    if [ "$rc" != "0" ]; then
      bad=$((bad + 1))
      echo "     self-build $i exited $rc: $(head -1 "$repdir/self.log")"
    fi
  done
  if [ "$bad" = "0" ] && [ "$lost" = "0" ]; then
    pass "env_size(self): $reps concurrent self-builds, 0 failures"
  else
    flunk "env_size(self): $bad of $reps self-builds failed, $lost reported nothing"
  fi
}

## 4. "the tool could not be RUN" and "the tool RAN and rejected its input" must be different
##    diagnoses with different exit codes. Collapsing them into one message and one code is what
##    made a driver defect (a malformed envp -> execve EFAULT) read as a codegen regression.
check_spawn_vs_rejection() {
  local shim="$WORK/bin" out rc
  mkdir -p "$shim"

  ## (a) an `as` that RESOLVES on $PATH but cannot be exec'd (not executable) -> a SPAWN failure.
  printf '#!/bin/sh\nexit 0\n' > "$shim/as"; chmod 644 "$shim/as"
  out=$(PATH="$shim:$PATH" "$CC" build "$WORK/pkg/package.al" 2>&1 </dev/null); rc=$?
  case "$out" in
    *"could not run the assembler"*)
      case "$out" in
        *"rejected the emitted assembly"*)
          flunk "env_size(spawn): a spawn failure still claims the assembly was rejected" ;;
        *)
          if [ "$rc" = "19" ]; then
            pass "env_size(spawn): unspawnable \`as\` -> spawn diagnostic, exit 19"
          else
            flunk "env_size(spawn): spawn diagnostic but exit $rc (expected 19)"
          fi ;;
      esac ;;
    *) flunk "env_size(spawn): rc $rc, expected a spawn diagnostic, got: $(printf '%s' "$out" | head -1)" ;;
  esac

  ## (b) an `as` that RUNS and rejects its input -> the assembler-rejection diagnosis, exit 13.
  printf '#!/bin/sh\nexit 1\n' > "$shim/as"; chmod 755 "$shim/as"
  out=$(PATH="$shim:$PATH" "$CC" build "$WORK/pkg/package.al" 2>&1 </dev/null); rc=$?
  case "$out" in
    *"rejected the emitted assembly"*)
      if [ "$rc" = "13" ]; then
        pass "env_size(reject): failing \`as\` -> rejection diagnostic, exit 13"
      else
        flunk "env_size(reject): rejection diagnostic but exit $rc (expected 13)"
      fi ;;
    *) flunk "env_size(reject): rc $rc, expected a rejection diagnostic, got: $(printf '%s' "$out" | head -1)" ;;
  esac

  ## (c) a diagnostic is a LINE: it must end in a newline, or it runs into the next thing printed.
  rm -f "$shim/as"
  out=$(PATH="$shim" "$CC" build "$WORK/pkg/package.al" 2>&1 </dev/null; printf 'X')
  case "$out" in
    *"not found on PATH"*)
      case "$out" in
        *"
X") pass "env_size(newline): a toolchain diagnostic ends in a newline" ;;
        *)  flunk "env_size(newline): the diagnostic did not end in a newline" ;;
      esac ;;
    *) flunk "env_size(newline): expected a not-found diagnostic, got: $(printf '%s' "$out" | head -1)" ;;
  esac
  rm -rf "$shim"
}

check_large_env_builds
check_no_false_codegen_diagnosis
check_spawn_vs_rejection
check_repeated_self_build

## The count is the coverage claim: green means all $EXPECT_ASSERTIONS verdicts were REACHED, not
## merely that none of the ones that ran said FAIL. Both halves live in `env_size_verdict`, which
## the self-test above drives in all four directions.
env_size_verdict "$checks" "$fail" "$EXPECT_ASSERTIONS"
exit $?
