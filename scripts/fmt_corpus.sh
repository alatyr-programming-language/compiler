#!/usr/bin/env bash
# scripts/fmt_corpus.sh — the `alatyr fmt` ARBITER over the whole `test/` corpus.
#
# `alatyr fmt` has NO fail-loud channel for a wrong RENDERING: it exits 0 and writes source. So a
# mis-rendered form is a SILENT MISCOMPILE of the user's program. The only honest check is the
# spec's own norm (Tooling §4.3: semantics-preserving + idempotent), applied to every program the
# repo already owns:
#
#     run(fmt(x)) == run(x)        (same exit status AND same stdout)
#     fmt(fmt(x)) == fmt(x)        (idempotence, the acceptance property)
#
# One line per fixture, classified by DAMAGE (worst first — a BEHAVIOUR failure silently changes
# what the program does, a COMPILEFAIL is at least loud, a NONIDEMPOTENT is formatting churn):
#
#   BEHAVIOUR-EXIT  the formatted program runs to a different exit status or stdout
#   BEHAVIOUR-HANG  the formatted program does not terminate (a lost `break` target, …)
#   COMPILEFAIL     the formatted program no longer compiles (the source did)
#   RECOMPILE       the source was REJECTED but the formatted text compiles (a lost reject)
#   NONIDEMPOTENT   a second fmt pass changes the text again
#   FMT-REFUSE      fmt refused a program that COMPILES (fail-loud rather than guess — see below)
#   FMT-REJECT      fmt refused a program the compiler also rejects (the parse failed; benign)
#   NOCOMPILE-BASE  the source is a reject fixture; fmt is still checked for idempotence
#   OK              round-trips
#
# A `FMT-REFUSE` is DELIBERATE where the written form cannot be recovered from the AST at all
# refusing is the spec's posture, since a canonical form is normative and a guess would diverge
# between implementations. Those live in
# the ALLOW table below with a reason, so the gate stays green on them and turns RED on anything new.
#
# TWO WALKS, and they check different halves of the norm:
#
#   walk 1  `git ls-files 'test/*.al'`        — PROGRAMS: both halves (behaviour + idempotence)
#   walk 2  `git ls-files 'src/*.al' 'lib/*.al'` — the compiler's own MODULES: idempotence ONLY
#
# Walk 2 exists because walk 1 could not see it. `src/`/`lib/` files are modules, not programs:
# they have no `_start`, so `run(fmt(x)) == run(x)` has no meaning and idempotence is the only
# half of §4.3 that applies to them. That half was worth a gate on its own — `fmt` was
# non-idempotent on SIX of the compiler's own modules and nothing noticed until someone ran `fmt`
# by hand, and it was not cosmetic: on the `deref(p) = v` shape the reparse dropped the STORE, so
# `fmt` was silently rewriting the program. Walk 2 costs ~3 s serial (65 files, 128 `fmt`
# invocations) against walk 1's ~10 minutes, so it is unconditional.
#
# Usage:  nix develop -c bash scripts/fmt_corpus.sh [--jobs N] [--filter REGEX] [--all]
#                                                   [--only test|src]
#   --all         print the OK lines too (default: failures + the summary only)
#   --only test   run walk 1 only  ·  --only src   run walk 2 only (both walks by default)
# Exit 0 iff every failure in EVERY walk it ran is in that walk's ALLOW table.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${ALATYR:-}" ]; then
  AL="$ALATYR"
elif [ -x "$ROOT/target/debug/alatyr" ]; then
  AL="$ROOT/target/debug/alatyr"
else
  AL="$ROOT/target/alatyr"
fi
W="$ROOT/target/fmt_corpus"
JOBS=8
FILTER=""
SHOW_OK=0
ONLY=both
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --filter) FILTER="$2"; shift 2 ;;
    --all) SHOW_OK=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "usage: $0 [--jobs N] [--filter REGEX] [--all] [--only test|src]" >&2; exit 2 ;;
  esac
done
case "$ONLY" in both|test|src) ;; *) echo "usage: --only test|src" >&2; exit 2 ;; esac
ulimit -c 0

# Fixtures whose CURRENT classification is accepted, each with the reason it is not a fmt bug.
# Anything NOT listed here that fails is a regression. Keep this table shrinking, never growing
# without the reason being recorded in the entry's own comment here and in the issue that tracks
# `alatyr fmt` completeness.
# An ARRAY, not a `case`, so an entry that has STOPPED being needed can be NAMED: the report prints
# `allow-unused <entry>` for any line nothing matched, informationally — never as a failure, because
# a lane that FIXES a residual must not be punished with a red gate for it. (When this was first
# enumerable it immediately named three stale entries that the `case` had hidden: `FMT-REFUSE
# embed_missing` and both `while_labels` rows.)
ALLOW=(
)
allowed() { # class rel -> 0 if this exact (class, fixture) pair is a known, reasoned residual
  local k="$1 $2" e
  for e in "${ALLOW[@]}"; do [ "$e" = "$k" ] && return 0; done
  return 1
}

# WALK 2's table, the same shape, kept here beside walk 1's rather than inside walk 2's block: both
# predicates are driven by `fmt_corpus_selftest`, which runs before either walk. A table, not a
# predicate, so an entry that has STOPPED being needed can be named. Each line is `CLASS path` and
# carries a located reason above it. An entry that no longer matches anything is reported as
# `allow-unused` and does NOT fail: a live lane fixing one of these must not turn this gate red as
# its reward. Keep the list shrinking.
MOD_ALLOW=(
)
mod_allowed() { # class rel -> 0 if this exact (class, path) pair is a reasoned residual
  local k="$1 $2" e
  for e in "${MOD_ALLOW[@]}"; do [ "$e" = "$k" ] && return 0; done
  return 1
}

[ -x "$AL" ] || { echo "FAIL: no compiler at $AL (build it first: seed/alatyr build package.al)" >&2; exit 2; }
command -v timeout >/dev/null || { echo "FAIL: coreutils \`timeout\` is required" >&2; exit 2; }
rm -rf "$W"; mkdir -p "$W/o"
fail=0

# ==========================================================================================
# THE TWO WALL-CLOCK CEILINGS, AND WHAT A BREACH MEANS (issue #599, the last two of #470's five)
#
# A ceiling exists to stop a child that does not TERMINATE. It does not measure the machine, and it
# must never be read as a finding about the program. Before this, every breach in this file was
# reclassified as the specific defect the surrounding check exists to detect:
#
#   TCC  breach on the base compile    -> `NOCOMPILE-BASE` / `FMT-REJECT` ("this program does not compile")
#   TCC  breach on a `fmt` pass        -> `FMT-REFUSE` / `MOD-REFUSE`     ("fmt cannot format this")
#   TCC  breach on the formatted build -> `COMPILEFAIL`                   ("formatting broke the build")
#   TRUN breach on the formatted run   -> `BEHAVIOUR-HANG`                ("formatting changed termination")
#
# The last one is the worst: `BEHAVIOUR-HANG` is this stage's strongest verdict, and a starved child
# was enough to produce it. So machine load could manufacture the accusation that `alatyr fmt`
# silently changes what a program does.
#
# The ceilings are deliberately NOT raised. A wall-clock threshold on a shared machine has no upper
# bound, so raising it only moves the load at which the false verdict returns (issue #537: the corpus
# walk's ceiling was raised 10s -> 30s once and the same row came back at load 28, 33 and 42). What
# changes instead is what a breach MEANS: it becomes its own outcome (`TIMED-OUT`,
# `PACKAGE-TIMED-OUT`, `MOD-TIMED-OUT`) and it is RE-OBSERVED before it is classified — see
# `fmt_reobserve` for the parallel walk and `fmt_step` for the two serial ones.
#
# MEASURED, because nobody knew the margin and #537/#585 each found the prior claim stale or absent.
# Every child of every walk, timed ONE AT A TIME by a throwaway harness that replays the same child
# commands independently of this file — so a bug in the `FMT_TIMING` instrumentation below could not
# flatter the number. Re-measure from the shipped code path with
#
#     FMT_TIMING=/tmp/fmt.tsv nix develop -c bash scripts/fmt_corpus.sh --jobs 1
#
# which appends `kind<TAB>ms<TAB>rc<TAB>command` for every child. 12 cores, load average 2.47 rising
# to 4.89 over the pass (so these are upper bounds for an idle machine, and ~13% above the corpus
# walk's own idle figures for the same two programs):
#
#   ceiling  child                                 n     p50      p99     max      margin at the max
#   TCC=60   alatyr -o <bin> <src>      base     2020   47.8ms   126ms   7662ms       7.8x
#   TCC=60   alatyr -o <fbin> <fmt'd>            1959   47.6ms   127ms   7827ms       7.7x
#   TCC=60   alatyr fmt <src>           pass 1   2020    1.4ms     3ms      5ms   11196x
#   TCC=60   alatyr fmt <fmt'd>         pass 2   1959    1.5ms     3ms      4ms   14392x
#   TCC=60   alatyr fmt <module>        walk 2     69    4.4ms   539ms    539ms     111x
#   TRUN=10  <bin>                      base     1326    1.0ms    65ms    131ms      76x
#   TRUN=10  <fbin>                      fmt'd   1326    1.0ms    64ms    131ms      76x
#
# THE SHAPE MATTERS MORE THAN THE MARGIN, and it is the opposite of the sweeps'. #585 found no hot
# spot at all there — p50 and max within a factor of 1.4, a different slowest guest on every pass, so
# ~60ms was qemu start-up. Here TWO fixtures out of 2020 carry the ENTIRE compile-side exposure, and
# they are the SAME two the corpus walk found (#537). The third-slowest compile is
# `sort_conformance` at 300ms; drop those two files and the compile margin is 200x.
#
# So a compile here CAN breach by being slow, not only by being starved — and the margin is a
# function of load, which is the whole argument against raising the ceiling. Same tree, same two
# files, same one-at-a-time method, at three points on this machine's real load range:
#
#   load average     test/uint256.al      margin      test/u128_div.al
#   2.5 - 4.9         7.66s               7.8x         3.02s
#   14 - 16          11.3 / 13.0 / 13.3s  4.5 - 5.3x   5.0 / 5.0 / 5.9s
#   16 - 21          14.45s               4.2x         5.53s
#
# A ceiling raised to absorb that would have to be raised again: #537 records this project raising
# the corpus walk's ceiling 10s -> 30s and the same file breaching at load 28, 33 and 42. A
# wall-clock threshold on a shared machine has no upper bound. The second observation does have one.
#
# The run side is comfortable (76x, max 131ms on `issue348_env_lookup_matrix`) and the `fmt` passes
# are not close to anything (11196x). The exposure that matters is the compile ceiling on two files.
# ==========================================================================================

# `ALATYR_FMT_TCC` / `ALATYR_FMT_TRUN` make a breach reproducible from outside, the way
# `ALATYR_CORPUS_TIMEOUT` already does for the corpus walk and `ALATYR_SWEEP_TIMEOUT` for the sweeps.
# With every child of this stage far under a second, a SUB-SECOND ceiling is the only way to
# reproduce a breach on a quiet machine, so a decimal fraction is deliberately accepted. Whole
# seconds or a decimal ONLY: `timeout`'s `s`/`m`/`h` suffixes are refused, because a suffix would
# silently read as its leading digits in the breach threshold below.
FMT_CEIL_MS=0
fmt_parse_ceiling() { # seconds -> sets FMT_CEIL_MS (milliseconds), 1 on a malformed value
  case "$1" in
    ''|*[!0-9.]*|*.*.*|.|0|0.|0.0|0.00|0.000)
      echo "FAIL: a fmt_corpus ceiling must be a positive number of seconds with no unit suffix," >&2
      echo "  e.g. ALATYR_FMT_TCC=60 or ALATYR_FMT_TRUN=0.02; got '$1'" >&2
      return 1 ;;
  esac
  local _w="${1%%.*}" _f="${1#*.}"
  [ "$_f" = "$1" ] && _f=""
  _f="${_f}000"; _f="${_f:0:3}"
  # A SECOND, independent guard, and not belt-and-braces: a bash arithmetic expansion error does not
  # just fail its own command, it unwinds EVERY enclosing function straight to top level. A value
  # that reached `10#` malformed would therefore abort the caller — silently, with no line printed —
  # and the caller here is `fmt_corpus_selftest`. The `case` above is the authority on what a ceiling
  # is; this is the authority on what may reach the arithmetic.
  case "$_w$_f" in
    ''|*[!0-9]*)
      echo "FAIL: a fmt_corpus ceiling must be a positive number of seconds with no unit suffix," >&2
      echo "  e.g. ALATYR_FMT_TCC=60 or ALATYR_FMT_TRUN=0.02; got '$1'" >&2
      return 1 ;;
  esac
  FMT_CEIL_MS=$(( 10#0${_w} * 1000 + 10#0${_f} ))
  [ "$FMT_CEIL_MS" -gt 0 ] || { echo "FAIL: a fmt_corpus ceiling of '$1' rounds to 0 ms" >&2; return 1; }
  return 0
}

TCC="${ALATYR_FMT_TCC:-60}"    # seconds for one compile or one `fmt` pass
TRUN="${ALATYR_FMT_TRUN:-10}"  # seconds for one program run (a lost `break` target spins forever)
fmt_parse_ceiling "$TCC" || exit 2
TCC_MS=$FMT_CEIL_MS
fmt_parse_ceiling "$TRUN" || exit 2
TRUN_MS=$FMT_CEIL_MS

# Elapsed milliseconds at or after which a 124 may be read as a ceiling breach.
#
# Why elapsed time is consulted at all: `timeout` reports a breach as exit 124 and CANNOT distinguish
# that from a child whose own exit status is 124. A corpus fixture is allowed to exit 124 (AGENTS.md
# caps fixture exits below 126; no `run` row wants 124 today, and a future one must not silently
# become unobservable), and `alatyr` itself could grow a 124 exit. Reading every 124 as a breach would
# relabel a genuine wrong value as a load artifact — the same mistake as this fix, pointed the other
# way. A breach cannot happen before the ceiling has elapsed, so the two are separable.
#
# The 100 ms of slack absorbs the clock read that happens just before the fork. A sub-second
# reproduction ceiling floors to 0, which means every 124 under it is read as a breach: that ceiling
# is a reproduction aid, not a gate setting, and under it the ambiguity is not resolvable at all.
fmt_breach_after() { local a=$(( $1 - 100 )); [ "$a" -lt 0 ] && a=0; printf '%s' "$a"; }
TCC_AFTER_MS="$(fmt_breach_after "$TCC_MS")"
TRUN_AFTER_MS="$(fmt_breach_after "$TRUN_MS")"

# Microseconds, locale-proof: `EPOCHREALTIME` always carries six decimals and its separator is `.` or
# `,` depending on LC_NUMERIC, so dropping the separator yields microseconds directly. Pure bash, so
# this costs no fork on any of the ~14 000 children this stage spawns.
fmt_now_us() { local _t="$EPOCHREALTIME"; printf '%s' "${_t/[.,]/}"; }

# Run ONE child under a ceiling. Prints nothing. Sets:
#   FMT_RC        the child's exit status, verbatim
#   FMT_MS        milliseconds of wall clock the child was allowed
#   FMT_BREACH    1 when the CEILING ended the child, 0 when the child ended itself
# Appends `kind<TAB>ms<TAB>rc<TAB>label` to `$FMT_TIMING` when that variable is set, so the margin
# above can be re-measured from the shipped code path without editing this file (see the recipe there).
fmt_timed() { # kind ceiling-seconds after-ms dir stdout stderr cmd...
  local _kind="$1" _ceil="$2" _after="$3" _dir="$4" _out="$5" _err="$6"; shift 6
  local _t0 _t1
  _t0="$(fmt_now_us)"
  ( cd "$_dir" && exec timeout "$_ceil" "$@" ) >"$_out" 2>"$_err" </dev/null
  FMT_RC=$?
  _t1="$(fmt_now_us)"
  FMT_MS=$(( (_t1 - _t0) / 1000 ))
  FMT_BREACH=0
  if [ "$FMT_RC" = 124 ] && [ "$FMT_MS" -ge "$_after" ]; then FMT_BREACH=1; fi
  if [ -n "${FMT_TIMING:-}" ]; then
    printf '%s\t%s\t%s\t%s\n' "$_kind" "$FMT_MS" "$FMT_RC" "$*" >> "$FMT_TIMING"
  fi
  return 0
}

# The SERIAL walks' breach handling (walk 1b and walk 2). Both already run one child at a time, so
# the second observation is taken immediately rather than deferred: re-run the SAME child once, and
# classify THAT. Every child guarded here is a compile, a `fmt` of a fixed input, or a run of a fixed
# binary, so repeating it is safe and observes the same compiler.
#
# Returns the child's exit status, so an existing `if ! …` ladder keeps its shape. On a PERSISTENT
# breach it prints the timed-out line itself and sets `FMT_STEP_TIMEDOUT=1`, which is what
# `fmt_step_blame` reads to suppress the accusation the ladder would otherwise make.
FMT_STEP_TIMEDOUT=0
FMT_STEP_REOBS=0
FMT_STEP_RECOVERED=0
FMT_STEP_PERSISTED=0
FMT_TIMEDOUT_CLASS=TIMED-OUT
fmt_step() { # kind label dir stdout stderr cmd...
  local _kind="$1" _label="$2"; shift 2
  local _ceil _after
  case "$_kind" in
    run) _ceil="$TRUN"; _after="$TRUN_AFTER_MS" ;;
    *)   _ceil="$TCC";  _after="$TCC_AFTER_MS" ;;
  esac
  FMT_STEP_TIMEDOUT=0
  fmt_timed "$_kind" "$_ceil" "$_after" "$@"
  [ "$FMT_BREACH" = 1 ] || return "$FMT_RC"
  FMT_STEP_REOBS=$((FMT_STEP_REOBS + 1))
  if [ "${ALATYR_FMT_REOBSERVE:-1}" = 0 ]; then
    echo "re-observation: ALATYR_FMT_REOBSERVE=0, so the ${_ceil}s breach at $_label is classified from"
    echo "  ONE observation. That is the mechanism issue #599 removed; this run is NOT a gate verdict."
  else
    echo "re-observation: the ${_ceil}s ceiling killed $_label after ${FMT_MS}ms. The ceiling catches a"
    echo "  child that does not terminate; it does not measure the machine. Observing it again, alone."
    echo "re-observation:   (load average now: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?'))"
    fmt_timed "$_kind" "$_ceil" "$_after" "$@"
    if [ "$FMT_BREACH" = 0 ]; then
      FMT_STEP_RECOVERED=$((FMT_STEP_RECOVERED + 1))
      echo "re-observation:   $_label  timeout -> rc $FMT_RC after ${FMT_MS}ms   RECOVERED"
      return "$FMT_RC"
    fi
  fi
  FMT_STEP_PERSISTED=$((FMT_STEP_PERSISTED + 1))
  FMT_STEP_TIMEDOUT=1
  echo "$FMT_TIMEDOUT_CLASS $_label (the ${_ceil}s ceiling ended it, ${FMT_MS}ms)"
  echo "  The child never produced an exit status, so this is NOT a finding about the program and NOT"
  echo "  a fmt defect: either it does not terminate, or this machine could not finish it inside the"
  echo "  ceiling. Reproduce with --jobs 1 and ALATYR_FMT_TCC=<n> / ALATYR_FMT_TRUN=<n>."
  return "$FMT_RC"
}

# Print the accusation a ladder arm wants to make — UNLESS the step it is judging was never observed,
# in which case `fmt_step` has already reported the breach under its own name and blaming the program
# for it is precisely the defect this fix removes. Either way the caller's failure is recorded.
fmt_step_blame() { # accusation-line
  if [ "$FMT_STEP_TIMEDOUT" = 1 ]; then
    FMT_STEP_TIMEDOUT=0
  else
    echo "$1"
  fi
  fail=1
}

# ------------------------------------------------------------------------------------------
# SERIAL RE-OBSERVATION OF A CEILING BREACH IN THE PARALLEL WALK (issue #599)
#
# `rc == 124 after N s` cannot tell a child that loops from one that was starved, and no value of the
# ceiling can. The fine fact is cheap and was never asked for: run that one fixture again, ALONE,
# after the parallel walk has finished, and classify THAT observation. A row that breaches with
# nothing else of this walk's in flight has earned a red gate under its own name; one that finishes
# returns to whatever it actually is — `OK`, `NONIDEMPOTENT`, `BEHAVIOUR-EXIT`, anything, and a real
# failure among those is still reported.
#
# The whole row is re-observed, not just the child that breached: a row's unit of work is the
# compile → run → fmt → fmt → compile → run chain over one sandbox, and a partial retry would mix
# two observations into one verdict. The exposure stays bounded to rows that breached at all — zero
# rows cost one `grep` and no child.
#
# `ALATYR_FMT_REOBSERVE=0` keeps the old one-observation behaviour so a run can be paired against its
# own control. It is not a gate verdict and says so.
#
# Sets FMT_REOBS / FMT_RECOVERED / FMT_PERSISTED and rewrites each re-observed row's verdict in
# `<rawfile>`. Returns 1 only when the MECHANISM broke — a second observation that produced no
# verdict, or more than one, leaves the first one unjudgeable too and must not pass silently.
fmt_reobserve() { # rawfile worker-fn timed-out-class [sandbox-setup-fn]
  local _raw="$1" _fn="$2" _cls="$3" _setup="${4:-}"
  local _to="$_raw.timeouts" _second="$_raw.second" _line _rel _n=0 _lines _t0
  FMT_REOBS=0; FMT_RECOVERED=0; FMT_PERSISTED=0
  grep "^$_cls " "$_raw" > "$_to" 2>/dev/null || : > "$_to"
  FMT_REOBS="$(grep -c '' < "$_to")"
  [ "$FMT_REOBS" = 0 ] && return 0

  if [ "${ALATYR_FMT_REOBSERVE:-1}" = 0 ]; then
    echo "fmt corpus: re-observation — ALATYR_FMT_REOBSERVE=0, so $FMT_REOBS ceiling breach(es) are being"
    echo "  classified from ONE observation taken while the whole corpus was in flight. That is the"
    echo "  mechanism issue #599 removed; this run is NOT a gate verdict."
    FMT_PERSISTED=$FMT_REOBS
    return 0
  fi

  echo "fmt corpus: re-observation — $FMT_REOBS row(s) hit a wall-clock ceiling during the parallel walk."
  echo "  A ceiling catches a child that does not terminate; it does not measure the machine, and the"
  echo "  classes this walk prints are all findings about the PROGRAM. Each row is observed again ONE"
  echo "  AT A TIME now that the walk is done, and the second observation is the one that is classified."
  echo "fmt corpus: re-observation   (load average now: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?'), jobs were $JOBS)"
  [ -n "$_setup" ] && "$_setup"
  _t0="$(fmt_now_us)"
  : > "$_second"
  while IFS= read -r _line; do
    _n=$((_n + 1))
    _rel="$(printf '%s\n' "$_line" | awk '{print $2}')"
    echo "fmt corpus: re-observation   [$_n/$FMT_REOBS] $_rel, serially…"
    echo "fmt corpus: re-observation       first observation: $_line"
    "$_fn" R "$(printf '%s' "$_rel" | tr '/' '_')" "$_rel" > "$_raw.one" 2>/dev/null
    _lines="$(grep -c '' < "$_raw.one")"
    if [ "$_lines" != 1 ]; then
      echo "FAIL: fmt corpus: the serial re-observation of $_rel produced $_lines verdict line(s), want 1 —"
      echo "  the re-observation mechanism is broken, so the first observation cannot be judged either."
      return 1
    fi
    cat "$_raw.one" >> "$_second"
    case "$(cat "$_raw.one")" in
      "$_cls"*)   FMT_PERSISTED=$((FMT_PERSISTED + 1))
                  printf 'fmt corpus: re-observation   %-44s %s   %s\n' "$_rel" "still $_cls" "STILL-AT-THE-CEILING" ;;
      *)          FMT_RECOVERED=$((FMT_RECOVERED + 1))
                  printf 'fmt corpus: re-observation   %-44s %s   %s\n' \
                    "$_rel" "-> $(awk '{print $1}' "$_raw.one")" "RECOVERED" ;;
    esac
  done < "$_to"
  # The second observation REPLACES the first: that is the whole discipline. One line out for one
  # line in, so the walk's `checked == fixtures` proof of work is preserved by construction.
  grep -v "^$_cls " "$_raw" > "$_raw.kept" 2>/dev/null || : > "$_raw.kept"
  cat "$_raw.kept" "$_second" > "$_raw.new"
  sort -o "$_raw" "$_raw.new"
  echo "fmt corpus: re-observation — $FMT_RECOVERED row(s) recovered, $FMT_PERSISTED still at the ceiling ($(( ($(fmt_now_us) - _t0) / 1000000 ))s)"
  return 0
}

# ------------------------------------------------------------------------------------------
# THE CLASSIFIER — the only place that decides whether a verdict line is a failure or a footnote.
#
# Factored out of the two report loops it used to be written twice for, so a self-test can drive the
# REAL decision with planted rows. It was the uncovered decider of this stage: `allowed`/`mod_allowed`
# alone separate "a regression that reddens the gate" from "a reasoned residual", both ALLOW tables
# are empty, and nothing exercised either of them — the same blind spot #584 found in
# `_e2e_runtime_failure` and #585 found in `sweep_check_total`. See `fmt_corpus_selftest`.
#
# Sets FMT_TIMEDOUT and FMT_REGRESSIONS. Returns 1 if this walk found anything the gate must fail on.
fmt_classify() { # rawfile seenfile regressionsfile allow-fn benign-fn
  local _raw="$1" _seen="$2" _reg="$3" _allow="$4" _benign="$5"
  local _rc=0 _line _cls _rel
  : > "$_seen"; : > "$_reg"
  FMT_TIMEDOUT=0
  while IFS= read -r _line; do
    _cls=${_line%% *}
    _rel="$(printf '%s\n' "$_line" | awk '{print $2}')"
    case "$_cls" in
      TIMED-OUT|PACKAGE-TIMED-OUT|MOD-TIMED-OUT)
        # Deliberately NOT allow-able and deliberately NOT a `REGRESSION`: a ceiling breach is never
        # a reasoned residual about the formatter, and calling it a regression would still be a claim
        # about the program. It reddens the gate under its own name.
        FMT_TIMEDOUT=$((FMT_TIMEDOUT + 1))
        echo "$_line"
        echo "  Observed twice — in the walk and again alone — so it is reported, but the child never"
        echo "  produced an exit status: either it does not terminate, or this machine cannot finish it"
        echo "  inside the ceiling. NOT a fmt finding. Reproduce with --jobs 1 and --filter '$_rel'."
        _rc=1 ;;
      *)
        if "$_benign" "$_cls"; then
          [ "$SHOW_OK" = 1 ] && echo "$_line"
        else
          echo "$_cls $_rel" >> "$_seen"
          if "$_allow" "$_cls" "$_rel"; then echo "allow $_line"
          else echo "$_line" >> "$_reg"; echo "REGRESSION $_line"; _rc=1; fi
        fi ;;
    esac
  done < "$_raw"
  FMT_REGRESSIONS="$(grep -c '' < "$_reg")"
  return $_rc
}
# How many observations a reported breach actually rests on. Never hard-code "twice": with
# `ALATYR_FMT_REOBSERVE=0` the second observation was not taken, and saying it was would be the same
# kind of claim-about-unobserved-work this fix removes.
fmt_timedout_basis() {
  if [ "${ALATYR_FMT_REOBSERVE:-1}" = 0 ]; then
    printf 'ONCE, under the parallel walk and NOT re-observed (ALATYR_FMT_REOBSERVE=0, so this is not a gate verdict)'
  else
    printf 'TWICE, the second time alone'
  fi
}
fmt_benign_test() { case "$1" in OK|NOCOMPILE-BASE|FMT-REJECT) return 0 ;; esac; return 1; }
fmt_benign_src()  { case "$1" in MOD-IDEM) return 0 ;; esac; return 1; }

# ==========================================================================================
# THE GATE OF THE GATE — this stage's own non-vacuity check (issue #599, requirement 4 and 5).
#
# Two things need proving on every run, and NOT with a copy of the sweeps' self-test: this walk's
# outcomes, ALLOW tables and report shape are its own.
#
#   1. THE CEILING MECHANISM, IN BOTH DIRECTIONS. A mechanism that only ever un-fails a row is an
#      eraser, not a measurement. The genuine-hang direction is asserted first and the recovery
#      second, over the SAME synthetic corpus in the SAME `fmt_reobserve` call, so neither can be
#      green while the other is broken.
#
#   1b. THE FUNCTIONS THAT MAKE THE DECISION PER FIXTURE. `one` and `one_mod` are where a breached
#      child becomes `TIMED-OUT`/`MOD-TIMED-OUT` instead of the accusation below it, so a self-test
#      that only drives the helpers proves the mechanism and not the stage. Section 6 drives both
#      against a stub compiler.
#
#   2. THE DECIDERS THAT HAD NO SELF-TEST. #584 found `_e2e_runtime_failure` — the one function
#      deciding whether a runtime ceiling breach counts as a failure at all — uncovered, and turning
#      its timeout branch into a note left the whole e2e suite green. #585 found the same shape in
#      `sweep_check_total`. This file's equivalents are `allowed` and `mod_allowed`: they ALONE
#      separate "a REGRESSION that reddens the gate" from "a reasoned residual", both ALLOW tables
#      are EMPTY so neither predicate ever returned 0 in anger, and NOTHING exercised either of
#      them. Making `allowed` return 0 unconditionally turned every failure this stage can find into
#      an `allow` footnote and the whole stage green — measured, see the PR. It is covered here now,
#      in both directions and for exactness, together with `fmt_step_blame` (which decides whether an
#      accusation is printed at all) and `fmt_parse_ceiling` (which decides what the ceiling even is).
#
# Costs ~3 s: real children for the ceiling separation, for `fmt_step`'s two arms, and for the two
# walk workers driven against a stub compiler; none for the corpus directions. Prints one line with
# the number of checks actually made — a green line with no count cannot be told apart from a
# self-test that silently skipped everything.
# The re-observation of walk 1 gets its OWN sandbox (`w R`, the one job index `seq 1 $JOBS` cannot
# produce), so a row's second observation cannot inherit a formatted file that a first observation
# left behind. Built lazily by this hook, passed to `fmt_reobserve` as its fourth argument: a walk
# with no breach copies nothing. It lives up here with the workers so the self-test drives the real
# one — a hook that builds nothing is indistinguishable, from inside `fmt_reobserve`, from one that
# works.
fmt_reobs_sandbox() { rm -rf "$W/wR"; cp -r "$ROOT/test" "$W/wR"; ln -s . "$W/wR/test"; }

# The two WALK WORKERS live here, above the self-test, rather than inside the `if` block of the
# walk that uses them. They are the functions that actually short-circuit a breached child to a
# TIMED-OUT class instead of letting the ladder below it accuse the program — the whole subject of
# issue #599 — and a self-test that cannot reach them cannot prove that. Measured before they were
# hoisted: deleting `one`'s formatted-run breach arm (so a starved run falls through to
# `BEHAVIOUR-EXIT` again) and deleting `one_mod`'s pass-1 arm (so a starved module reads as
# `MOD-REFUSE`) each left the self-test green and the stage exit 0. Nothing else about them changed;
# both still read the same globals the walks set.

# `one` prints EXACTLY ONE verdict line for one fixture. A ceiling breach on ANY of its six children
# short-circuits the row to `TIMED-OUT <rel> (<which child>)`: the row was not observed, so none of
# the classes below can be asserted about it. That line is NOT the row's classification — it is
# re-observed serially by `fmt_reobserve` once the parallel walk is over, and the SECOND observation
# is what gets classified. `one` is therefore called twice for such a row and must leave the sandbox
# exactly as it found it, which is why every early return past the in-place `cp` restores `$dst`.
one() { # job-index flat-name relative-path
  local w="$W/w$1" nm="$2" rel="$3"
  local src="$ROOT/test/$rel.al" dst="$w/$rel.al"
  local o1="$W/o/$nm.f1.al" o2="$W/o/$nm.f2.al"
  local bout="$W/o/$nm.b.out" fout="$W/o/$nm.f.out" b2="$W/o/$nm.b2.out"
  local brc bexit frc fexit

  fmt_timed cc-base "$TCC" "$TCC_AFTER_MS" "$w" /dev/null /dev/null "$AL" -o "$w/$nm.bin" "$dst"
  brc=$FMT_RC
  if [ "$FMT_BREACH" = 1 ]; then
    echo "TIMED-OUT       $rel (base compile hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$brc" = 0 ]; then
    fmt_timed run-base "$TRUN" "$TRUN_AFTER_MS" "$w" "$bout" /dev/null "$w/$nm.bin"
    bexit=$FMT_RC
    if [ "$FMT_BREACH" = 1 ]; then
      echo "TIMED-OUT       $rel (base run hit the ${TRUN}s ceiling after ${FMT_MS}ms)"; return
    fi
  else
    bexit=""
  fi

  fmt_timed fmt1 "$TCC" "$TCC_AFTER_MS" "$w" "$o1" /dev/null "$AL" fmt "$dst"
  if [ "$FMT_BREACH" = 1 ]; then
    echo "TIMED-OUT       $rel (fmt pass 1 hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$FMT_RC" != 0 ]; then
    if [ "$brc" = 0 ]; then echo "FMT-REFUSE      $rel"; else echo "FMT-REJECT      $rel"; fi
    return
  fi
  if [ ! -s "$o1" ]; then echo "FMT-REFUSE      $rel (empty output)"; return; fi

  cp "$o1" "$dst"
  fmt_timed fmt2 "$TCC" "$TCC_AFTER_MS" "$w" "$o2" /dev/null "$AL" fmt "$dst"
  if [ "$FMT_BREACH" = 1 ]; then
    cp "$src" "$dst"
    echo "TIMED-OUT       $rel (fmt pass 2 hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$FMT_RC" != 0 ]; then
    cp "$src" "$dst"; echo "NONIDEMPOTENT   $rel (re-emit refused its own output)"; return
  fi
  if ! diff -q "$o1" "$o2" >/dev/null 2>&1; then
    cp "$src" "$dst"; echo "NONIDEMPOTENT   $rel"; return
  fi

  fmt_timed cc-fmt "$TCC" "$TCC_AFTER_MS" "$w" /dev/null /dev/null "$AL" -o "$w/$nm.fbin" "$dst"
  frc=$FMT_RC
  if [ "$FMT_BREACH" = 1 ]; then
    cp "$src" "$dst"
    echo "TIMED-OUT       $rel (formatted compile hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  cp "$src" "$dst"
  if [ "$brc" != 0 ]; then
    if [ "$frc" = 0 ]; then echo "RECOMPILE       $rel"; else echo "NOCOMPILE-BASE  $rel"; fi
    return
  fi
  if [ "$frc" != 0 ]; then echo "COMPILEFAIL     $rel"; return; fi
  fmt_timed run-fmt "$TRUN" "$TRUN_AFTER_MS" "$w" "$fout" /dev/null "$w/$nm.fbin"
  fexit=$FMT_RC
  # The one that mattered most: a starved formatted run used to print `BEHAVIOUR-HANG … (formatted
  # does not terminate)`, this stage's strongest verdict, on the strength of `rc == 124`. The elapsed
  # time separates "the ceiling ended it" from "the program exited 124 itself", and only the former
  # is a non-observation. A row that breaches here twice is still reported — under `TIMED-OUT`, which
  # says the child produced no exit status, rather than under a class that claims fmt changed the
  # program's termination.
  if [ "$FMT_BREACH" = 1 ]; then
    echo "TIMED-OUT       $rel (formatted run hit the ${TRUN}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$fexit" != "$bexit" ]; then echo "BEHAVIOUR-EXIT  $rel (exit $fexit want $bexit)"; return; fi
  if ! diff -q "$bout" "$fout" >/dev/null 2>&1; then
    # Confirm the SOURCE program's stdout is deterministic before blaming fmt (a fixture that
    # prints an mmap address differs run to run and is not a formatting failure).
    fmt_timed run-base2 "$TRUN" "$TRUN_AFTER_MS" "$w" "$b2" /dev/null "$w/$nm.bin"
    if [ "$FMT_BREACH" = 1 ]; then
      echo "TIMED-OUT       $rel (determinism re-run hit the ${TRUN}s ceiling after ${FMT_MS}ms)"; return
    fi
    if diff -q "$bout" "$b2" >/dev/null 2>&1; then echo "BEHAVIOUR-EXIT  $rel (stdout differs)"; return; fi
  fi
  echo "OK              $rel"
}

# One module, one verdict line — the same worker shape walk 1 uses, so the second observation of a
# ceiling breach can go through the SAME `fmt_reobserve`. A breach on either `fmt` pass short-circuits
# the module to `MOD-TIMED-OUT`: it must not be read as `MOD-REFUSE`, which asserts that `fmt` cannot
# format one of the compiler's own modules.
one_mod() { # unused-job-index flat-name relative-path
  local nm="$2" rel="$3"
  local o1="$MW/o/$nm.f1.al" o2="$MW/o/$nm.f2.al" er="$MW/o/$nm.err"
  local d="$MW/src/$(dirname "$rel")"
  mkdir -p "$d"
  cp "$ROOT/$rel" "$MW/src/$rel"
  INV=$((INV+1))
  fmt_timed mod-fmt1 "$TCC" "$TCC_AFTER_MS" "$MW/src" "$o1" "$er" "$AL" fmt "$rel"
  if [ "$FMT_BREACH" = 1 ]; then
    echo "MOD-TIMED-OUT   $rel (fmt pass 1 hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$FMT_RC" != 0 ]; then
    echo "MOD-REFUSE      $rel ($(tr -d '\r' < "$er" | grep -v '^$' | tail -1 | cut -c1-90))"; return
  fi
  if [ ! -s "$o1" ]; then echo "MOD-REFUSE      $rel (empty output)"; return; fi
  # Format the SANDBOX COPY IN PLACE: the module's name is its file stem and becomes a GAS
  # symbol, so the second pass has to read a file with the same basename, never a temp name.
  cp "$o1" "$MW/src/$rel"
  INV=$((INV+1))
  fmt_timed mod-fmt2 "$TCC" "$TCC_AFTER_MS" "$MW/src" "$o2" /dev/null "$AL" fmt "$rel"
  if [ "$FMT_BREACH" = 1 ]; then
    cp "$ROOT/$rel" "$MW/src/$rel"
    echo "MOD-TIMED-OUT   $rel (fmt pass 2 hit the ${TCC}s ceiling after ${FMT_MS}ms)"; return
  fi
  if [ "$FMT_RC" != 0 ]; then
    echo "MOD-NONIDEM     $rel (re-emit refused its own output)"; return
  fi
  if ! diff -q "$o1" "$o2" >/dev/null 2>&1; then
    echo "MOD-NONIDEM     $rel ($(diff "$o1" "$o2" | grep -c '^[<>]') differing line(s))"
    return
  fi
  echo "MOD-IDEM        $rel"
}

FMT_SELFTEST_EXPECTED=99
fmt_corpus_selftest() {
  local root="$W/selftest" bad="" k=0
  local keep_tcc="$TCC" keep_trun="$TRUN" keep_ta="$TCC_AFTER_MS" keep_ra="$TRUN_AFTER_MS"
  local keep_fail="$fail" keep_cls="$FMT_TIMEDOUT_CLASS" keep_show="$SHOW_OK"
  local keep_allow=("${ALLOW[@]+${ALLOW[@]}}")
  rm -rf "$root"; mkdir -p "$root"
  # `_ck <ok?> <name>` — one assertion, counted whether it passes or fails, so the printed count is
  # proof of work rather than proof of survival.
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }

  # ---- 1 · `fmt_parse_ceiling`: the validator is a decider. --------------------------------
  local t
  for t in 10s 1m 60s '' abc 1.2.3 -5 '1 2'; do
    if fmt_parse_ceiling "$t" 2>"$root/ceil.err"; then _ck 1 "parse_ceiling-accepted('$t')"; else _ck 0 x; fi
    # It must refuse ON PURPOSE. Without this the arithmetic below `case` refuses `10s` too, by
    # blowing up, and a hole in the pattern would be invisible.
    grep -q 'must be a positive number of seconds' "$root/ceil.err"
    _ck $? "parse_ceiling-refused('$t')-without-its-own-diagnostic"
  done
  for t in 0 0.0 0.000; do
    if fmt_parse_ceiling "$t" 2>"$root/ceil.err"; then _ck 1 "parse_ceiling-accepted('$t')"; else _ck 0 x; fi
    grep -q 'ceiling' "$root/ceil.err"; _ck $? "parse_ceiling-refused('$t')-silently"
  done
  fmt_parse_ceiling 60 2>/dev/null && [ "$FMT_CEIL_MS" = 60000 ]; _ck $? parse_ceiling-60
  fmt_parse_ceiling 0.02 2>/dev/null && [ "$FMT_CEIL_MS" = 20 ]; _ck $? parse_ceiling-0.02
  fmt_parse_ceiling 10 2>/dev/null && [ "$FMT_CEIL_MS" = 10000 ]; _ck $? parse_ceiling-10
  [ "$(fmt_breach_after 60000)" = 59900 ]; _ck $? breach_after-60s
  [ "$(fmt_breach_after 20)" = 0 ];        _ck $? breach_after-sub-second

  # ---- 2 · `fmt_timed`: a ceiling breach is not the same fact as the child's own 124. -------
  # THE assertion this whole fix rests on. Get it wrong the strict way and a starved child is
  # reported as a wrong value; wrong the loose way and a genuine 124 becomes a load artifact.
  fmt_timed probe 1 900 "$root" /dev/null /dev/null /bin/sh -c 'sleep 5'
  [ "$FMT_RC" = 124 ] && [ "$FMT_BREACH" = 1 ]
  _ck $? "timed-missed-a-real-breach(rc=$FMT_RC breach=$FMT_BREACH ms=$FMT_MS)"
  fmt_timed probe 30 29900 "$root" /dev/null /dev/null /bin/sh -c 'exit 124'
  [ "$FMT_RC" = 124 ] && [ "$FMT_BREACH" = 0 ]
  _ck $? "timed-called-a-child's-own-124-a-breach(ms=$FMT_MS)"
  fmt_timed probe 30 29900 "$root" /dev/null /dev/null /bin/sh -c 'exit 42'
  [ "$FMT_RC" = 42 ] && [ "$FMT_BREACH" = 0 ]
  _ck $? "timed-mangled-an-ordinary-exit(rc=$FMT_RC breach=$FMT_BREACH)"

  # ---- 3 · `fmt_step` + `fmt_step_blame`: the serial walks, both directions. ----------------
  TCC=1; TCC_AFTER_MS=900; FMT_TIMEDOUT_CLASS=SELFTEST-TIMED-OUT
  local r0=$FMT_STEP_REOBS c0=$FMT_STEP_RECOVERED p0=$FMT_STEP_PERSISTED
  # 3a a child that breaches EVERY observation stays a failure, under its own class, and the arm's
  #    accusation about the program is suppressed.
  fail=0
  fmt_step cc "selftest hang" "$root" "$root/hang.out" /dev/null \
    /bin/sh -c 'sleep 5' > "$root/step_hang.txt" 2>&1
  [ "$FMT_STEP_TIMEDOUT" = 1 ]; _ck $? step-did-not-flag-a-persistent-breach
  grep -q '^SELFTEST-TIMED-OUT selftest hang ' "$root/step_hang.txt"
  _ck $? step-did-not-report-the-breach-under-its-own-class
  fmt_step_blame "SELFTEST-ACCUSATION about the program" > "$root/blame_hang.txt" 2>&1
  [ ! -s "$root/blame_hang.txt" ]; _ck $? blame-still-accused-the-program-for-an-unobserved-child
  [ "$fail" = 1 ]; _ck $? blame-suppressed-the-accusation-AND-the-failure
  [ "$FMT_STEP_PERSISTED" = "$((p0+1))" ]; _ck $? step-persisted-counter
  # 3b a child that breaches ONCE and then finishes must recover to its real status, and the ladder
  #    must see that status rather than a timeout.
  fail=0
  rm -f "$root/starved.seen"
  fmt_step cc "selftest starved" "$root" "$root/starved.out" /dev/null \
    /bin/sh -c 'if [ -f '"$root"'/starved.seen ]; then exit 7; else : > '"$root"'/starved.seen; sleep 5; fi' \
    > "$root/step_starved.txt" 2>&1
  local starved_rc=$?
  [ "$starved_rc" = 7 ]; _ck $? "step-lost-the-second-observation's-status(rc=$starved_rc)"
  [ "$FMT_STEP_TIMEDOUT" = 0 ]; _ck $? step-kept-the-timeout-flag-after-a-recovery
  grep -q RECOVERED "$root/step_starved.txt"; _ck $? step-did-not-report-the-recovery
  [ "$FMT_STEP_RECOVERED" = "$((c0+1))" ]; _ck $? step-recovered-counter
  [ "$FMT_STEP_REOBS" = "$((r0+2))" ]; _ck $? step-reobs-counter
  # 3c the eraser check: after an ordinary failing child, `fmt_step_blame` MUST still print. A fix
  #    that silenced every accusation would pass 3a and be worthless. The flag is deliberately
  #    poisoned first: `FMT_STEP_TIMEDOUT` describes the step just taken, and two arms of walk 1b
  #    read it directly to decide whether an expected `fmt` REFUSAL was actually observed. A stale 1
  #    from an earlier step would silence a real accusation there, and deleting `fmt_step`'s own
  #    reset was measured to leave this self-test green before this line existed.
  fail=0
  FMT_STEP_TIMEDOUT=1
  fmt_step cc "selftest plain" "$root" /dev/null /dev/null /bin/sh -c 'exit 3' >/dev/null 2>&1
  [ "$FMT_STEP_TIMEDOUT" = 0 ]; _ck $? step-kept-a-stale-timeout-flag-from-an-earlier-step
  fmt_step_blame "SELFTEST-ACCUSATION about the program" > "$root/blame_plain.txt" 2>&1
  grep -q '^SELFTEST-ACCUSATION about the program$' "$root/blame_plain.txt"
  _ck $? blame-swallowed-a-legitimate-accusation
  [ "$fail" = 1 ]; _ck $? blame-did-not-record-a-legitimate-failure
  # 3d the `run` arm picks the RUN ceiling, the compile arms the COMPILE ceiling. `fmt_step` chooses
  #    between them on its `kind` argument alone, and every check above drives it as `cc`, so the
  #    arm that guards walk 1b's two program RUNS — the 10s ceiling, the one whose breach used to be
  #    reported as a behaviour finding — was never taken. Measured: swapping the `run` arm to `$TCC`
  #    left the whole self-test green. The two ceilings are set far apart here so the assertion is
  #    which one was consulted, not how long a child took.
  TCC=30; TCC_AFTER_MS=29900; TRUN=0.2; TRUN_AFTER_MS=0
  fail=0
  fmt_step run "selftest run-ceiling" "$root" /dev/null /dev/null \
    /bin/sh -c 'sleep 5' > "$root/step_run.txt" 2>&1
  [ "$FMT_STEP_TIMEDOUT" = 1 ]; _ck $? step-run-arm-did-not-use-the-run-ceiling
  grep -q 'the 0.2s ceiling ended it' "$root/step_run.txt"
  _ck $? step-run-arm-reported-a-ceiling-that-is-not-the-run-ceiling
  FMT_STEP_TIMEDOUT=0
  fmt_step cc "selftest cc-ceiling" "$root" /dev/null /dev/null \
    /bin/sh -c 'sleep 0.5' > "$root/step_cc.txt" 2>&1
  [ "$FMT_STEP_TIMEDOUT" = 0 ]; _ck $? step-compile-arm-used-the-run-ceiling
  fail=0
  TCC="$keep_tcc"; TRUN="$keep_trun"; TCC_AFTER_MS="$keep_ta"; TRUN_AFTER_MS="$keep_ra"
  FMT_TIMEDOUT_CLASS="$keep_cls"

  # ---- 4 · `fmt_reobserve`: both ceiling directions, one drive of the REAL function. --------
  # `m_plain` never breached and must be observed EXACTLY ZERO times here — that is what proves the
  # re-observation costs nothing when nothing timed out. `t_hang` breaches again; `t_starved` does not.
  local raw="$root/raw"
  printf '%s\n' \
    'BEHAVIOUR-EXIT  b_real (exit 1 want 42)' \
    'OK              m_plain' \
    'TIMED-OUT       t_hang (base run hit the 10s ceiling after 10001ms)' \
    'TIMED-OUT       t_starved (fmt pass 1 hit the 60s ceiling after 60002ms)' > "$raw"
  : > "$root/order"
  # Walk 1 passes a fourth argument: the hook that builds the re-observation's own sandbox. Nothing
  # drove it before, and a hook that is never called — or called after the first row — leaves every
  # re-observed row of walk 1 formatting into a directory that does not exist, which reports as a
  # recovery that never happened. Measured: both `fmt_reobserve` dropping the call and
  # `fmt_reobs_sandbox` building nothing left the self-test green.
  _st_setup() { printf 'setup\n' >> "$root/order"; }
  _st_worker() { # job flat-name rel
    printf 'work %s\n' "$3" >> "$root/order"
    printf 'x\n' >> "$root/observed.$3"
    case "$3" in
      t_hang)    echo "TIMED-OUT       t_hang (base run hit the 10s ceiling after 10003ms)" ;;
      t_starved) echo "OK              t_starved" ;;
      *)         echo "SELFTEST-LOST   $3" ;;
    esac
  }
  fmt_reobserve "$raw" _st_worker TIMED-OUT _st_setup > "$root/reobs.txt" 2>&1
  _ck $? reobserve-reported-a-broken-mechanism-when-it-was-not
  [ "$(head -1 "$root/order")" = setup ]
  _ck $? reobserve-re-observed-a-row-before-building-the-sandbox-the-hook-owns
  [ "$(grep -c '^setup$' "$root/order")" = 1 ]
  _ck $? "reobserve-called-the-sandbox-hook-$(grep -c '^setup$' "$root/order")-times(want 1)"
  [ "$FMT_REOBS" = 2 ];      _ck $? "reobs=$FMT_REOBS(want 2)"
  [ "$FMT_PERSISTED" = 1 ];  _ck $? "persisted=$FMT_PERSISTED(want 1)"
  [ "$FMT_RECOVERED" = 1 ];  _ck $? "recovered=$FMT_RECOVERED(want 1)"
  [ ! -f "$root/observed.m_plain" ]; _ck $? reobserve-re-ran-a-row-that-never-breached
  [ ! -f "$root/observed.b_real" ];  _ck $? reobserve-re-ran-a-genuine-failure
  [ "$(grep -c '' < "$raw")" = 4 ];  _ck $? "reobserve-changed-the-row-count(one-line-in-one-line-out)"
  grep -q '^TIMED-OUT       t_hang .*10003ms' "$raw"
  _ck $? reobserve-did-not-replace-the-hang-with-its-SECOND-observation
  grep -q '^OK              t_starved$' "$raw"; _ck $? reobserve-did-not-let-a-starved-row-recover
  grep -q STILL-AT-THE-CEILING "$root/reobs.txt"; _ck $? reobserve-did-not-name-the-persistent-row
  grep -q RECOVERED "$root/reobs.txt";            _ck $? reobserve-did-not-name-the-recovered-row
  # A second observation that produces NO verdict leaves the FIRST one unjudgeable too, so the
  # mechanism must fail loudly rather than quietly keep or drop the row.
  _st_silent() { : ; }
  printf '%s\n' 'TIMED-OUT       t_hang (x)' > "$root/raw_mute"
  fmt_reobserve "$root/raw_mute" _st_silent TIMED-OUT > "$root/reobs_mute.txt" 2>&1
  [ $? = 1 ]; _ck $? reobserve-accepted-a-second-observation-with-no-verdict
  grep -q 'mechanism is broken' "$root/reobs_mute.txt"; _ck $? reobserve-did-not-say-the-mechanism-broke
  unset -f _st_silent

  # The escape hatch must be exercised HERE and must not be able to switch the self-test off: a
  # self-test that obeyed the operator's flag would stop testing exactly when someone disabled it.
  printf '%s\n' 'TIMED-OUT       t_hang (x)' > "$root/raw0"
  ALATYR_FMT_REOBSERVE=0 fmt_reobserve "$root/raw0" _st_worker TIMED-OUT > "$root/reobs0.txt" 2>&1
  grep -q 'NOT a gate verdict' "$root/reobs0.txt"; _ck $? reobserve-0-did-not-disclaim-itself
  grep -q '^TIMED-OUT       t_hang (x)$' "$root/raw0"; _ck $? reobserve-0-rewrote-the-verdict-anyway

  # ---- 5 · `fmt_classify` + `allowed`: the decider that had no self-test. -------------------
  # Direction A: a failure nothing excuses is a REGRESSION and reddens the gate.
  SHOW_OK=0
  ALLOW=()
  fmt_classify "$raw" "$root/seen" "$root/reg" allowed fmt_benign_test > "$root/cls_a.txt" 2>&1
  [ $? = 1 ]; _ck $? classify-passed-a-walk-with-a-regression-and-a-timeout
  [ "$FMT_REGRESSIONS" = 1 ]; _ck $? "classify-regressions=$FMT_REGRESSIONS(want 1)"
  [ "$FMT_TIMEDOUT" = 1 ];    _ck $? "classify-timedout=$FMT_TIMEDOUT(want 1)"
  grep -q '^REGRESSION BEHAVIOUR-EXIT  b_real' "$root/cls_a.txt"; _ck $? classify-lost-the-regression
  grep -q '^TIMED-OUT       t_hang' "$root/cls_a.txt"; _ck $? classify-lost-the-timed-out-row
  grep -q 'NOT a fmt finding' "$root/cls_a.txt"; _ck $? classify-did-not-say-what-a-timeout-is-not
  # Direction B: the SAME row, excused by an exact ALLOW entry, is a footnote and the walk is green.
  ALLOW=("BEHAVIOUR-EXIT b_real")
  printf '%s\n' 'BEHAVIOUR-EXIT  b_real (exit 1 want 42)' 'OK              m_plain' > "$root/raw_b"
  fmt_classify "$root/raw_b" "$root/seen" "$root/reg" allowed fmt_benign_test > "$root/cls_b.txt" 2>&1
  [ $? = 0 ]; _ck $? classify-failed-a-walk-whose-only-failure-is-a-reasoned-residual
  grep -q '^allow BEHAVIOUR-EXIT  b_real' "$root/cls_b.txt"; _ck $? classify-did-not-print-the-allow
  [ "$FMT_REGRESSIONS" = 0 ]; _ck $? classify-counted-an-allowed-row-as-a-regression
  # Direction C: the predicate is EXACT on both fields. A near-miss must not excuse anything.
  ALLOW=("BEHAVIOUR-EXIT b_other" "NONIDEMPOTENT b_real")
  fmt_classify "$root/raw_b" "$root/seen" "$root/reg" allowed fmt_benign_test > "$root/cls_c.txt" 2>&1
  [ $? = 1 ]; _ck $? classify-let-a-near-miss-ALLOW-entry-excuse-a-failure
  # Direction D: a ceiling breach is NOT excusable. It is not a statement about the formatter, so an
  # ALLOW entry must not be able to bury it.
  ALLOW=("TIMED-OUT t_hang")
  printf '%s\n' 'TIMED-OUT       t_hang (x)' > "$root/raw_d"
  fmt_classify "$root/raw_d" "$root/seen" "$root/reg" allowed fmt_benign_test > "$root/cls_d.txt" 2>&1
  [ $? = 1 ]; _ck $? classify-let-an-ALLOW-entry-bury-a-ceiling-breach
  [ "$FMT_TIMEDOUT" = 1 ]; _ck $? classify-stopped-counting-an-allowed-timeout
  # Direction E: walk 2's own benign class and predicate, so `mod_allowed` is covered too.
  local MOD_ALLOW_KEEP=("${MOD_ALLOW[@]+${MOD_ALLOW[@]}}")
  MOD_ALLOW=("MOD-NONIDEM m_x")
  printf '%s\n' 'MOD-IDEM        m_ok' 'MOD-NONIDEM     m_x (1 differing line(s))' \
    'MOD-TIMED-OUT   m_slow (fmt pass 1 hit the 60s ceiling after 60001ms)' > "$root/raw_e"
  fmt_classify "$root/raw_e" "$root/seen" "$root/reg" mod_allowed fmt_benign_src > "$root/cls_e.txt" 2>&1
  [ $? = 1 ]; _ck $? classify-passed-walk2-despite-a-MOD-TIMED-OUT
  grep -q '^allow MOD-NONIDEM     m_x' "$root/cls_e.txt"; _ck $? mod_allowed-did-not-excuse-its-exact-entry
  [ "$FMT_TIMEDOUT" = 1 ]; _ck $? "walk2-timedout=$FMT_TIMEDOUT(want 1)"
  # …and a module failure nothing excuses must be a REGRESSION. Without this, `mod_allowed`
  # returning 0 unconditionally left the walk-2 direction green on the strength of the
  # MOD-TIMED-OUT row alone, which is not allow-able and so proves nothing about the predicate.
  printf '%s\n' 'MOD-IDEM        m_ok' 'MOD-NONIDEM     m_y (2 differing line(s))' > "$root/raw_f"
  fmt_classify "$root/raw_f" "$root/seen" "$root/reg" mod_allowed fmt_benign_src > "$root/cls_f.txt" 2>&1
  [ $? = 1 ]; _ck $? classify-passed-walk2-with-an-unexcused-MOD-NONIDEM
  grep -q '^REGRESSION MOD-NONIDEM     m_y' "$root/cls_f.txt"; _ck $? mod_allowed-excused-a-row-it-does-not-list
  [ "$FMT_REGRESSIONS" = 1 ]; _ck $? "walk2-regressions=$FMT_REGRESSIONS(want 1)"
  MOD_ALLOW=("${MOD_ALLOW_KEEP[@]+${MOD_ALLOW_KEEP[@]}}")

  # ---- 6 · `one` and `one_mod`: the two workers that actually short-circuit a breach. -------
  # Everything above drives the ceiling helpers and the classifier with synthetic rows. None of it
  # reaches the two functions that decide, per fixture, that a breached child means TIMED-OUT rather
  # than the accusation the ladder under it would otherwise make — and those decisions ARE issue
  # #599. Measured before this section existed: deleting `one`'s formatted-run breach arm and
  # deleting `one_mod`'s pass-1 arm each left the self-test green and the stage exit 0.
  #
  # Driven against a STUB compiler and a fake `$ROOT`, so the whole section costs well under a
  # second and depends on no real fixture's timing. The stub answers exactly two argv shapes, the
  # only two the workers use, and three environment switches choose which child hangs.
  local keep_al="$AL" keep_root="$ROOT" keep_mw="${MW:-}" keep_inv="${INV:-}"
  local stub="$root/stub-alatyr" fake="$root/fake"
  mkdir -p "$fake/test" "$W/wSELF"
  cat > "$stub" <<'STUB'
#!/bin/sh
case "$1" in
  fmt) [ -n "${STUB_FMT_HANG:-}" ] && sleep 5
       cat "$2"; exit 0 ;;
  -o)  [ -n "${STUB_CC_HANG:-}" ] && sleep 5
       case "$2" in
         *.fbin) if [ -n "${STUB_RUN_HANG:-}" ]
                 then printf '#!/bin/sh\nsleep 5\n' > "$2"
                 else printf '#!/bin/sh\nexit 0\n'  > "$2"; fi ;;
         *)      printf '#!/bin/sh\nexit 0\n' > "$2" ;;
       esac
       chmod +x "$2"; exit 0 ;;
esac
exit 2
STUB
  chmod +x "$stub"
  AL="$stub"; ROOT="$fake"
  printf 'main := fn() -> u64 { 0 }\n' > "$fake/test/selftest_row.al"
  cp "$fake/test/selftest_row.al" "$W/wSELF/selftest_row.al"
  # 6a a base-compile breach is `TIMED-OUT`, not `NOCOMPILE-BASE`/`FMT-REJECT`. This was the SILENT
  #    one: those two classes are benign, so the walk used to check nothing, say nothing and exit 0.
  TCC=0.2; TCC_AFTER_MS=0; TRUN=30; TRUN_AFTER_MS=29900
  STUB_CC_HANG=1 one SELF selftest_row selftest_row > "$root/one_cc.txt" 2>&1
  [ "$(grep -c '' < "$root/one_cc.txt")" = 1 ]; _ck $? one-did-not-print-exactly-one-line
  grep -q '^TIMED-OUT       selftest_row (base compile hit the 0.2s ceiling' "$root/one_cc.txt"
  _ck $? one-did-not-short-circuit-a-starved-base-compile
  grep -qE '^(NOCOMPILE-BASE|FMT-REJECT)' "$root/one_cc.txt"
  [ $? = 1 ]; _ck $? one-filed-a-starved-base-compile-as-a-finding-about-the-program
  # 6b a formatted-RUN breach is `TIMED-OUT`, not `BEHAVIOUR-*`. This is the accusation the issue is
  #    named for: this stage's strongest verdict, manufactured by machine load.
  TCC=30; TCC_AFTER_MS=29900; TRUN=0.2; TRUN_AFTER_MS=0
  cp "$fake/test/selftest_row.al" "$W/wSELF/selftest_row.al"
  STUB_RUN_HANG=1 one SELF selftest_row selftest_row > "$root/one_run.txt" 2>&1
  [ "$(grep -c '' < "$root/one_run.txt")" = 1 ]; _ck $? one-did-not-print-exactly-one-line-for-a-run-breach
  grep -q '^TIMED-OUT       selftest_row (formatted run hit the 0.2s ceiling' "$root/one_run.txt"
  _ck $? one-did-not-short-circuit-a-starved-formatted-run
  grep -q BEHAVIOUR "$root/one_run.txt"
  [ $? = 1 ]; _ck $? one-still-blamed-fmt-for-a-starved-formatted-run
  # 6c the eraser control: with nothing hanging, the SAME row must reach its real class. A `one`
  #    that answered TIMED-OUT for everything would pass 6a and 6b and be worthless.
  TCC=30; TCC_AFTER_MS=29900; TRUN=30; TRUN_AFTER_MS=29900
  cp "$fake/test/selftest_row.al" "$W/wSELF/selftest_row.al"
  one SELF selftest_row selftest_row > "$root/one_ok.txt" 2>&1
  grep -q '^OK              selftest_row$' "$root/one_ok.txt"
  _ck $? "one-lost-a-clean-row($(head -1 "$root/one_ok.txt"))"
  # 6d/6e the same pair for walk 2's worker: a starved `fmt` pass is `MOD-TIMED-OUT`, never
  #    `MOD-REFUSE`, which asserts that `fmt` cannot format one of the compiler's own modules.
  MW="$root/mw"; INV=0
  rm -rf "$MW"; mkdir -p "$MW/src" "$MW/o"
  printf 'main := fn() -> u64 { 0 }\n' > "$fake/selftest_mod.al"
  TCC=0.2; TCC_AFTER_MS=0
  STUB_FMT_HANG=1 one_mod - selftest_mod selftest_mod.al > "$root/mod_hang.txt" 2>&1
  grep -q '^MOD-TIMED-OUT   selftest_mod.al (fmt pass 1 hit the 0.2s ceiling' "$root/mod_hang.txt"
  _ck $? one_mod-did-not-short-circuit-a-starved-fmt-pass
  grep -q MOD-REFUSE "$root/mod_hang.txt"
  [ $? = 1 ]; _ck $? one_mod-said-fmt-cannot-format-a-module-it-never-observed
  TCC=30; TCC_AFTER_MS=29900
  one_mod - selftest_mod selftest_mod.al > "$root/mod_ok.txt" 2>&1
  grep -q '^MOD-IDEM        selftest_mod.al$' "$root/mod_ok.txt"
  _ck $? "one_mod-lost-a-clean-module($(head -1 "$root/mod_ok.txt"))"
  # 1 for the breached pass-1 (which returns before pass 2) plus 2 for the clean module.
  [ "$INV" = 3 ]; _ck $? "one_mod-fmt-invocation-count=$INV(want 3)"
  # 6f walk 1's own sandbox hook, driven against the fake `$ROOT` so the copy is one file. Passing
  #    it is section 4's subject; that it BUILDS something is this one's, and the two are separate
  #    defects — a hook that returns without copying left the self-test green until this check.
  rm -rf "$W/wR"
  fmt_reobs_sandbox
  [ -f "$W/wR/selftest_row.al" ]; _ck $? reobs_sandbox-did-not-copy-the-corpus-into-the-sandbox
  [ -L "$W/wR/test" ] && [ -f "$W/wR/test/selftest_row.al" ]
  _ck $? reobs_sandbox-did-not-make-the-test-self-symlink-resolve
  rm -rf "$W/wR"
  AL="$keep_al"; ROOT="$keep_root"; MW="$keep_mw"; INV="$keep_inv"
  rm -rf "$W/wSELF"

  # ---- 7 · `fmt_timedout_basis`: what the verdict line CLAIMS was observed. -----------------
  # Both walks put this function's answer inside their `*** … hit a wall-clock ceiling … ***` line.
  # It is the one place that states how many observations a reported breach rests on, and with
  # `ALATYR_FMT_REOBSERVE=0` the second one was never taken. Measured: hard-coding it to the
  # two-observation wording left the self-test green while every disabled-re-observation run
  # claimed a second observation it had not made.
  case "$(fmt_timedout_basis)" in
    TWICE*) _ck 0 x ;; *) _ck 1 "timedout_basis-does-not-say-TWICE-when-re-observation-is-on" ;;
  esac
  case "$(ALATYR_FMT_REOBSERVE=0 fmt_timedout_basis)" in
    ONCE*) _ck 0 x ;; *) _ck 1 "timedout_basis-claims-a-second-observation-it-did-not-take" ;;
  esac
  ALATYR_FMT_REOBSERVE=0 fmt_timedout_basis | grep -q 'not a gate verdict'
  _ck $? timedout_basis-did-not-disclaim-a-run-that-skipped-the-second-observation

  # ---- restore, then report ----------------------------------------------------------------
  # Reached only if nothing above unwound this function. `fmt_corpus_selftest` is called through a
  # marker check for exactly that reason: an arithmetic expansion error anywhere in a function it
  # drives returns straight to top level, printing nothing, and a self-test that can be silenced
  # rather than failed is not a self-test. Measured — the neutered-ceiling-validator plant did
  # exactly this and left no line at all.
  # The RESULT, in files, before any branch of this function decides what to say about it. The
  # caller reads these, so neutering the reporting branch below cannot turn a failed self-test into
  # a green line — that plant is in the non-vacuity set precisely because it used to work.
  # The self-test's own children breached a ceiling on purpose, and walk 1b's
  # `ceiling-breaches=`/`recovered=`/`timed-out=` line is a statement about the CORPUS. Asserted in
  # both directions rather than merely reset: non-zero first, because a self-test whose counters
  # never moved did not actually breach anything, and zero after, because the caller must not be
  # handed this function's own breaches as the corpus's. The subshell the caller runs this in makes
  # the leak impossible today; this is the check that notices if that ever stops being true.
  [ "$FMT_STEP_REOBS" -gt 0 ] && [ "$FMT_STEP_PERSISTED" -gt 0 ] && [ "$FMT_STEP_RECOVERED" -gt 0 ]
  _ck $? "selftest-took-no-ceiling-breach-of-its-own(reobs=$FMT_STEP_REOBS)"
  FMT_STEP_REOBS=0; FMT_STEP_RECOVERED=0; FMT_STEP_PERSISTED=0; FMT_STEP_TIMEDOUT=0
  [ "$FMT_STEP_REOBS$FMT_STEP_RECOVERED$FMT_STEP_PERSISTED$FMT_STEP_TIMEDOUT" = 0000 ]
  _ck $? selftest-left-its-own-ceiling-breaches-in-the-walk-1b-counters
  printf '%s' "$bad" > "$root/bad"
  printf '%s' "$k" > "$root/checks"
  : > "$root/complete"
  ALLOW=("${keep_allow[@]+${keep_allow[@]}}")
  TCC="$keep_tcc"; TRUN="$keep_trun"; TCC_AFTER_MS="$keep_ta"; TRUN_AFTER_MS="$keep_ra"
  fail="$keep_fail"; FMT_TIMEDOUT_CLASS="$keep_cls"; SHOW_OK="$keep_show"
  unset -f _ck _st_worker _st_setup
  if [ -n "$bad" ]; then
    echo "*** fmt corpus selftest: FAILED —$bad ***"
    return 1
  fi
  if [ "$k" -lt "$FMT_SELFTEST_EXPECTED" ]; then
    echo "*** fmt corpus selftest: ran $k checks, expected at least $FMT_SELFTEST_EXPECTED — a self-test"
    echo "    that reports fewer checks than it owes is a failure, not a shortcut to green ***"
    return 1
  fi
  echo "fmt corpus selftest: $k checks — ceiling breach vs a child's own 124, the ceiling validator,"
  echo "  fmt_step/fmt_step_blame in both directions and on both of its ceilings, serial"
  echo "  re-observation in both directions and its sandbox hook, one/one_mod short-circuiting a"
  echo "  starved child in both directions, what the verdict line claims was observed, and the"
  echo "  allowed/mod_allowed regression-vs-residual decision in five"
  return 0
}
# The self-test's verdict is read from what it RECORDED, not only from what it printed or returned.
# Two separate ways it could otherwise pass without proving anything, both measured while planting
# defects: a bash arithmetic expansion error anywhere in a function it drives unwinds every enclosing
# function to top level, printing nothing at all, and a defect in its own reporting branch turns a
# non-empty failure list into a green line.
rm -rf "$W/selftest"
# In a SUBSHELL, and that is the third defence rather than a style choice. A bash arithmetic
# expansion error — or an unbound variable under `set -u` — anywhere in a function this drives does
# not merely fail its own command: it unwinds to top level and, at top level, ENDS THE SCRIPT. The
# completion-marker check below was written for exactly that case and could never run, because the
# script was already gone: measured, two planted defects (`fmt_classify` losing its `FMT_TIMEDOUT`
# initialisation, and both of `fmt_parse_ceiling`'s guards removed at once) exited 1 having printed
# NOTHING AT ALL — no verdict, no diagnostic, no stage output. Inside a subshell the same unwind
# ends the subshell, `FMT_SELFTEST_RC` is assigned, and the marker check says what happened. Nothing
# the self-test sets needs to reach the walks; it records its verdict in files and restores the
# globals it borrows either way.
( fmt_corpus_selftest ); FMT_SELFTEST_RC=$?
if [ ! -f "$W/selftest/complete" ]; then
  echo "*** fmt corpus selftest: did NOT run to completion (rc=$FMT_SELFTEST_RC) — it recorded no"
  echo "    verdict, so this run proves nothing about the ceiling mechanism or the ALLOW deciders ***"
  fail=1
else
  if [ -s "$W/selftest/bad" ]; then
    echo "*** fmt corpus selftest: recorded failures — $(cat "$W/selftest/bad") ***"
    fail=1
  fi
  if [ "$(cat "$W/selftest/checks")" -lt "$FMT_SELFTEST_EXPECTED" ]; then
    echo "*** fmt corpus selftest: recorded $(cat "$W/selftest/checks") checks, expected at least"
    echo "    $FMT_SELFTEST_EXPECTED — a self-test that reports fewer checks than it owes is a"
    echo "    failure, not a shortcut to green ***"
    fail=1
  fi
  [ "$FMT_SELFTEST_RC" = 0 ] || fail=1
fi

# ==========================================================================================
# WALK 1 — the `test/` corpus: PROGRAMS, both halves of the norm.
# ==========================================================================================
if [ "$ONLY" != src ]; then

# One sandbox per job: a full copy of `test/` so a fixture's SIBLING imports still resolve, and so
# the file under test can be replaced by its formatted text IN PLACE (the module name is the file
# stem and becomes a GAS symbol, so the formatted text must keep the same basename). The `test ->
# .` self-symlink makes a path written the way e2e writes it (`embed("test/embed_fixture.bin")`,
# resolved against the compiler's CWD) resolve here too — without it the embed fixtures failed to
# COMPILE in the sandbox and were misfiled as FMT-REJECT instead of the deliberate FMT-REFUSE.
for j in $(seq 1 "$JOBS"); do cp -r "$ROOT/test" "$W/w$j"; ln -s . "$W/w$j/test"; done

export -f one fmt_timed fmt_now_us
export W AL TCC TRUN TCC_AFTER_MS TRUN_AFTER_MS FMT_TIMING

# The corpus is the TRACKED `.al` files under `test/`. Deliberately not `find`: an e2e run leaves
# generated, gitignored `.al` files there (`test/link/statstub/package.al`), which would make the
# corpus size — and so the gate — depend on what ran before it.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" ls-files 'test/*.al' | sed 's|^test/||; s|\.al$||' | sort > "$W/list"
else
  ( cd "$ROOT/test" && find . -name '*.al' -type f | sed 's|^\./||; s|\.al$||' | sort ) > "$W/list"
fi
if [ -n "$FILTER" ]; then grep -E "$FILTER" "$W/list" > "$W/list2" || true; mv "$W/list2" "$W/list"; fi

n=0
: > "$W/raw"
while read -r rel; do
  n=$((n+1))
  j=$(( (n % JOBS) + 1 ))
  ( one "$j" "$(echo "$rel" | tr '/' '_')" "$rel" ) >> "$W/raw" &
  if [ $((n % JOBS)) = 0 ]; then wait; fi
done < "$W/list"
wait
sort -o "$W/raw" "$W/raw"

# Between the walk and the classification, and in that order: nothing of this walk's is in flight
# any more, which is the whole point of the second observation.
#
fmt_reobserve "$W/raw" one TIMED-OUT fmt_reobs_sandbox || fail=1

# ---- report -------------------------------------------------------------------------------
fmt_classify "$W/raw" "$W/seen" "$W/regressions" allowed fmt_benign_test || fail=1

# Only meaningful over the WHOLE corpus: a `--filter`ed run legitimately touches a fraction of it.
if [ -z "$FILTER" ]; then
  for e in "${ALLOW[@]}"; do
    grep -qxF "$e" "$W/seen" || echo "allow-unused $e (no longer occurs — drop this entry)"
  done
fi

# Proof of work, not just a verdict: a green line with no counts cannot be told apart from a
# walk that silently found nothing to do. `checked=` must equal `fixtures=`, or the run covered
# less than the corpus and says so.
echo "fmt corpus walk=test fixtures=$(wc -l < "$W/list") checked=$(wc -l < "$W/raw") jobs=$JOBS reobserved=$FMT_REOBS recovered=$FMT_RECOVERED timed-out=$FMT_TIMEDOUT"
awk '{print $1}' "$W/raw" | sort | uniq -c | sort -rn
if [ "$(wc -l < "$W/list")" -lt 1 ]; then
  echo "*** fmt corpus walk=test: the corpus is EMPTY — the walk proved nothing ***"; fail=1
elif [ "$(wc -l < "$W/raw")" != "$(wc -l < "$W/list")" ]; then
  echo "*** fmt corpus walk=test: classified $(wc -l < "$W/raw") of $(wc -l < "$W/list") fixtures —"
  echo "    a fixture produced no line at all, so the walk covered LESS than the corpus ***"; fail=1
elif [ "$FMT_TIMEDOUT" != 0 ]; then
  # `fmt_timedout_basis` rather than a hard-coded "twice": with ALATYR_FMT_REOBSERVE=0 the second
  # observation was never taken, and claiming it was is the same kind of lie this fix removes.
  echo "*** fmt corpus walk=test: $FMT_TIMEDOUT row(s) hit a wall-clock ceiling $(fmt_timedout_basis) —"
  echo "    reported above under TIMED-OUT. That is not a finding about fmt, and not a pass either ***"
elif [ ! -s "$W/regressions" ]; then
  echo "*** fmt corpus walk=test: every failure is a reasoned residual (see the ALLOW table) ***"
else
  echo "*** fmt corpus walk=test: $(wc -l < "$W/regressions") NEW failure(s) — see REGRESSION above ***"
fi

fi  # end walk 1

# ==========================================================================================
# WALK 1b — the existing multi-file package fixture for qualified function values.
#
# The flat walk above deliberately covers only `test/*.al`; package modules live below
# `test/package/`. Keep this one focused package check beside the formatter arbiter so a source
# recovery in `Expr::Var` cannot silently turn `apply(hex::encode, …)` into `apply(encode, …)`.
# It checks the known-good package result, the formatted package result, and formatter idempotence.
# ==========================================================================================
if [ "$ONLY" != src ] && { [ -z "$FILTER" ] || printf '%s\n' 'test/package/fn_value_qualified' | grep -Eq "$FILTER"; }; then
  # Every guarded child below goes through `fmt_step`, which takes a SECOND observation of a ceiling
  # breach on the spot (this walk is already serial, so there is nothing to wait for) and reports a
  # persistent one under this class instead of letting the surrounding arm blame the program.
  FMT_TIMEDOUT_CLASS=PACKAGE-TIMED-OUT
  PW="$W/package/fn_value_qualified"
  rm -rf "$PW"
  mkdir -p "$W/package"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PW"
  PO1="$W/o/fn_value_qualified.package.f1.al"
  PO2="$W/o/fn_value_qualified.package.f2.al"
  PE="$W/o/fn_value_qualified.package.err"
  PB="$W/o/fn_value_qualified.package.base.out"
  PF="$W/o/fn_value_qualified.package.formatted.out"

  pbase_build=0
  if ! fmt_step cc "package build (baseline)" "$PW" "$PB" "$PE" "$AL" build package.al; then
    fmt_step_blame "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (baseline)"
  else
    pbin="$PW/target/debug/fn-value-qualified"
    if [ ! -x "$pbin" ]; then
      fmt_step_blame "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (missing executable)"
    else
      fmt_step run "package run (baseline)" "$PW" "$PB" /dev/null "$pbin"; pbase_rc=$FMT_RC
      if [ "$pbase_rc" != 42 ]; then
        fmt_step_blame "PACKAGE-BASE-BEHAVIOUR test/package/fn_value_qualified (exit $pbase_rc want 42)"
      else
        pbase_build=1
      fi
    fi
  fi

  if ! fmt_step cc "package fmt src/main.al (pass 1)" "$PW" "$PO1" "$PE" "$AL" fmt src/main.al; then
    fmt_step_blame "PACKAGE-FMT-REFUSE test/package/fn_value_qualified"
  elif [ ! -s "$PO1" ]; then
    fmt_step_blame "PACKAGE-FMT-REFUSE test/package/fn_value_qualified (empty output)"
  else
    if ! grep -qF 'apply(hex::encode, 40)' "$PO1"; then
      fmt_step_blame "PACKAGE-QUALIFIED-PATH test/package/fn_value_qualified (qualified value path lost)"
    fi
    cp "$PO1" "$PW/src/main.al"
    if ! fmt_step cc "package fmt src/main.al (pass 2)" "$PW" "$PO2" "$PE" "$AL" fmt src/main.al; then
      fmt_step_blame "PACKAGE-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
    elif ! diff -q "$PO1" "$PO2" >/dev/null 2>&1; then
      fmt_step_blame "PACKAGE-NONIDEMPOTENT test/package/fn_value_qualified"
    elif ! fmt_step cc "package build (formatted)" "$PW" "$PF" "$PE" "$AL" build package.al; then
      fmt_step_blame "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (formatted)"
    elif [ "$pbase_build" = 1 ]; then
      pbin="$PW/target/debug/fn-value-qualified"
      if [ ! -x "$pbin" ]; then
        fmt_step_blame "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
      else
        fmt_step run "package run (formatted)" "$PW" "$PF" /dev/null "$pbin"; pformatted_rc=$FMT_RC
        if [ "$pformatted_rc" != 42 ]; then
          fmt_step_blame "PACKAGE-BEHAVIOUR-EXIT test/package/fn_value_qualified (exit $pformatted_rc want 42)"
        else
          echo "PACKAGE-OK        test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  echo "fmt package fixture=test/package/fn_value_qualified checked=1"

  # The lexer/parser also accept blanks around `::`. Exercise and EXECUTE that spelling in a COPY of
  # the existing fixture so this formatter-only regression needs no new corpus row or oracle update.
  PS="$W/package/fn_value_qualified_spaced"
  rm -rf "$PS"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PS"
  sed -i \
    -e '/^main := fn() -> u64 {/i\
spaced_value := fn() -> u64 {\
  apply(hex :: encode, 40)\
}' \
  -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  spaced := spaced_value()\
  if direct == 41 and indirect == 41 and spaced == 41 { 42 } else { 0 }' \
  "$PS/src/main.al"
  PSO1="$W/o/fn_value_qualified.package.spaced.f1.al"
  PSO2="$W/o/fn_value_qualified.package.spaced.f2.al"
  PSE="$W/o/fn_value_qualified.package.spaced.err"
  PSB="$W/o/fn_value_qualified.package.spaced.build.out"
  if ! fmt_step cc "package/spaced build (baseline)" "$PS" "$PSB" "$PSE" "$AL" build package.al; then
    fmt_step_blame "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified"
  elif ! fmt_step cc "package/spaced fmt (pass 1)" "$PS" "$PSO1" "$PSE" "$AL" fmt src/main.al; then
    fmt_step_blame "PACKAGE-SPACED-FMT-REFUSE test/package/fn_value_qualified"
  elif [ ! -s "$PSO1" ]; then
    fmt_step_blame "PACKAGE-SPACED-FMT-REFUSE test/package/fn_value_qualified (empty output)"
  else
    if ! grep -qF 'apply(hex :: encode, 40)' "$PSO1"; then
      fmt_step_blame "PACKAGE-SPACED-QUALIFIED-PATH test/package/fn_value_qualified (qualified value path lost)"
    fi
    cp "$PSO1" "$PS/src/main.al"
    if ! fmt_step cc "package/spaced fmt (pass 2)" "$PS" "$PSO2" "$PSE" "$AL" fmt src/main.al; then
      fmt_step_blame "PACKAGE-SPACED-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
    elif ! diff -q "$PSO1" "$PSO2" >/dev/null 2>&1; then
      fmt_step_blame "PACKAGE-SPACED-NONIDEMPOTENT test/package/fn_value_qualified"
    elif ! fmt_step cc "package/spaced build (formatted)" "$PS" "$PSB" "$PSE" "$AL" build package.al; then
      fmt_step_blame "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified (formatted)"
    else
      psbin="$PS/target/debug/fn-value-qualified"
      if [ ! -x "$psbin" ]; then
        fmt_step_blame "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
      else
        fmt_step run "package/spaced run" "$PS" "$PSB" /dev/null "$psbin"; pspaced_rc=$FMT_RC
        if [ "$pspaced_rc" != 42 ]; then
          fmt_step_blame "PACKAGE-SPACED-BEHAVIOUR test/package/fn_value_qualified (exit $pspaced_rc want 42)"
        else
          echo "PACKAGE-SPACED-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  echo "fmt package fixture=test/package/fn_value_qualified checked=2"

  # A line comment ending in `::` must not become the head of the next Var. This variant is
  # sandbox-only: it keeps the corpus and all three oracles unchanged and accepts a deliberate
  # fail-loud refusal for the ambiguous source.
  PC="$W/package/fn_value_qualified_comment"
  rm -rf "$PC"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PC"
  sed -i \
    -e 's/^  direct := hex::encode(40)$/  x := 41/' \
    -e '/^  indirect := apply(hex::encode, 40)$/d' \
    -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  ## a comment ending in a path-looking separator ::\
  x' "$PC/src/main.al"
  PCO1="$W/o/fn_value_qualified.package.comment.f1.al"
  PCO2="$W/o/fn_value_qualified.package.comment.f2.al"
  PCE="$W/o/fn_value_qualified.package.comment.err"
  PCB="$W/o/fn_value_qualified.package.comment.build.out"
  if ! fmt_step cc "package/comment build (baseline)" "$PC" "$PCB" "$PCE" "$AL" build package.al; then
    fmt_step_blame "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified"
  elif ! fmt_step cc "package/comment fmt (pass 1)" "$PC" "$PCO1" "$PCE" "$AL" fmt src/main.al; then
    # A deliberate fail-loud refusal is this variant's accepted outcome — so a ceiling breach here is
    # the FALSE GREEN, not a false red: nothing was observed and the arm would call it the expected
    # refusal. `fmt_step` has already reported the breach; make it fail rather than pass.
    if [ "$FMT_STEP_TIMEDOUT" = 1 ]; then fmt_step_blame ""
    else echo "PACKAGE-COMMENT-REFUSED test/package/fn_value_qualified"; fi
  elif ! grep -qE '^  x$' "$PCO1" || grep -qF 'separator ::' "$PCO1"; then
    fmt_step_blame "PACKAGE-COMMENT-PATH test/package/fn_value_qualified (comment altered next Var)"
  else
    cp "$PCO1" "$PC/src/main.al"
    if ! fmt_step cc "package/comment fmt (pass 2)" "$PC" "$PCO2" "$PCE" "$AL" fmt src/main.al; then
      fmt_step_blame "PACKAGE-COMMENT-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
    elif ! diff -q "$PCO1" "$PCO2" >/dev/null 2>&1; then
      fmt_step_blame "PACKAGE-COMMENT-NONIDEMPOTENT test/package/fn_value_qualified"
    elif ! fmt_step cc "package/comment build (formatted)" "$PC" "$PCB" "$PCE" "$AL" build package.al; then
      fmt_step_blame "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified (formatted)"
    else
      pcbin="$PC/target/debug/fn-value-qualified"
      if [ ! -x "$pcbin" ]; then
        fmt_step_blame "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
      else
        fmt_step run "package/comment run" "$PC" "$PCB" /dev/null "$pcbin"; pcomment_rc=$FMT_RC
        if [ "$pcomment_rc" != 41 ]; then
          fmt_step_blame "PACKAGE-COMMENT-BEHAVIOUR test/package/fn_value_qualified (exit $pcomment_rc want 41)"
        else
          echo "PACKAGE-COMMENT-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi

  # A string literal containing the comment marker must not be classified as a comment while the
  # formatter looks backward from the following value. This is the exact raw-byte false positive
  # caught by independent review; it is a valid program and must format, build, and run.
  PL="$W/package/fn_value_qualified_literal"
  rm -rf "$PL"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PL"
  sed -i \
    -e 's/^  direct := hex::encode(40)$/  x := 41/' \
    -e '/^  indirect := apply(hex::encode, 40)$/d' \
    -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  s := "## ::"\
  x' "$PL/src/main.al"
  PLO1="$W/o/fn_value_qualified.package.literal.f1.al"
  PLO2="$W/o/fn_value_qualified.package.literal.f2.al"
  PLE="$W/o/fn_value_qualified.package.literal.err"
  PLB="$W/o/fn_value_qualified.package.literal.build.out"
  if ! fmt_step cc "package/literal build (baseline)" "$PL" "$PLB" "$PLE" "$AL" build package.al; then
    fmt_step_blame "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified"
  elif ! fmt_step cc "package/literal fmt (pass 1)" "$PL" "$PLO1" "$PLE" "$AL" fmt src/main.al; then
    fmt_step_blame "PACKAGE-LITERAL-FMT-REFUSE test/package/fn_value_qualified"
  elif ! grep -qF 's := "## ::"' "$PLO1" || ! grep -qE '^  x$' "$PLO1"; then
    fmt_step_blame "PACKAGE-LITERAL-PATH test/package/fn_value_qualified (literal altered or next Var lost)"
  else
    cp "$PLO1" "$PL/src/main.al"
    if ! fmt_step cc "package/literal fmt (pass 2)" "$PL" "$PLO2" "$PLE" "$AL" fmt src/main.al; then
      fmt_step_blame "PACKAGE-LITERAL-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
    elif ! diff -q "$PLO1" "$PLO2" >/dev/null 2>&1; then
      fmt_step_blame "PACKAGE-LITERAL-NONIDEMPOTENT test/package/fn_value_qualified"
    elif ! fmt_step cc "package/literal build (formatted)" "$PL" "$PLB" "$PLE" "$AL" build package.al; then
      fmt_step_blame "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified (formatted)"
    else
      plbin="$PL/target/debug/fn-value-qualified"
      if [ ! -x "$plbin" ]; then
        fmt_step_blame "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
      else
        fmt_step run "package/literal run" "$PL" "$PLB" /dev/null "$plbin"; pliteral_rc=$FMT_RC
        if [ "$pliteral_rc" != 41 ]; then
          fmt_step_blame "PACKAGE-LITERAL-BEHAVIOUR test/package/fn_value_qualified (exit $pliteral_rc want 41)"
        else
          echo "PACKAGE-LITERAL-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  # The lexer accepts multiline separators, but the current formatter/lowering boundary cannot
  # safely render their reflowed form. It must refuse rather than silently change runtime behavior.
  PML="$W/package/fn_value_qualified_multiline"
  rm -rf "$PML"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PML"
  sed -i '/^  indirect := apply(hex::encode, 40)$/c\
  indirect := apply(hex\
  ::\
  encode, 40)' "$PML/src/main.al"
  PMLO="$W/o/fn_value_qualified.package.multiline.out"
  PMLE="$W/o/fn_value_qualified.package.multiline.err"
  if ! fmt_step cc "package/multiline fmt" "$PML" "$PMLO" "$PMLE" "$AL" fmt src/main.al; then
    # As above: a refusal is the accepted outcome here, so an unobserved child would pass. It must not.
    if [ "$FMT_STEP_TIMEDOUT" = 1 ]; then fmt_step_blame ""
    else echo "PACKAGE-MULTILINE-REFUSED test/package/fn_value_qualified"; fi
  else
    fmt_step_blame "PACKAGE-MULTILINE-SILENT test/package/fn_value_qualified (multiline path was rewritten)"
  fi

  echo "fmt package fixture=test/package/fn_value_qualified checked=5 ceiling-breaches=$FMT_STEP_REOBS recovered=$FMT_STEP_RECOVERED timed-out=$FMT_STEP_PERSISTED"
  FMT_TIMEDOUT_CLASS=TIMED-OUT
fi

# ==========================================================================================
# WALK 2 — `src/` + `lib/`: the compiler's own MODULES, IDEMPOTENCE ONLY.
#
# A module has no `_start`, so there is no program to run and `run(fmt(x)) == run(x)` is not a
# statement about it. What remains is §4.3's acceptance property, `fmt(fmt(x)) == fmt(x)`, and
# it is the half that was unwatched: `fmt` was non-idempotent on six of these files while walk 1
# stayed green, and one of those non-idempotences DROPPED A STORE on reparse.
#
# Serial on purpose. The whole walk is ~3 s (measured: 3.1 s, 65 files, 128 `fmt` invocations)
# against walk 1's ~10 minutes, so a job pool would buy nothing and cost determinism in the
# order of the output.
#
# Classes (walk 2 only):
#   MOD-IDEM        `fmt(fmt(x)) == fmt(x)`  — the module round-trips
#   MOD-NONIDEM     a second pass changed the text again (or refused its own output)
#   MOD-REFUSE      `fmt` refused the module outright (fail-loud, but it cannot format it)
# ==========================================================================================
if [ "$ONLY" != test ]; then

MW="$W/mod"
rm -rf "$MW"; mkdir -p "$MW/src" "$MW/o"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" ls-files 'src/*.al' 'lib/*.al' | sort > "$MW/list"
else
  ( cd "$ROOT" && find src lib -name '*.al' -type f | sort ) > "$MW/list"
fi
if [ -n "$FILTER" ]; then grep -E "$FILTER" "$MW/list" > "$MW/list2" || true; mv "$MW/list2" "$MW/list"; fi

# `INV` counts `fmt` invocations, so the proof-of-work line reports work actually done rather
# than files merely listed — a `fmt` that refused everything instantly would otherwise print the
# same green summary as a walk that did 128 real renders.
INV=0
: > "$MW/raw"

while read -r rel; do
  [ -n "$rel" ] || continue
  one_mod - "$(echo "$rel" | tr '/' '_')" "$rel" >> "$MW/raw"
done < "$MW/list"
sort -o "$MW/raw" "$MW/raw"

# This walk is serial, but a breach still rests on ONE observation taken while the rest of the gate
# (and every other lane on the machine) was in flight. Take the second one now, the same way walk 1
# does. `one_mod` re-copies the pristine module into the sandbox itself, so no setup hook is needed.
fmt_reobserve "$MW/raw" one_mod MOD-TIMED-OUT || fail=1

fmt_classify "$MW/raw" "$MW/seen" "$MW/regressions" mod_allowed fmt_benign_src || fail=1

# An ALLOW entry nobody hit is either a fixed defect or a forgotten one. Say which entries they
# are — informational, never fatal, so a lane that FIXES one is not punished for it.
for e in "${MOD_ALLOW[@]}"; do
  grep -qxF "$e" "$MW/seen" || echo "allow-unused $e (no longer occurs — drop this entry)"
done

echo "fmt corpus walk=src modules=$(wc -l < "$MW/list") checked=$(wc -l < "$MW/raw") fmt_invocations=$INV allow=${#MOD_ALLOW[@]} reobserved=$FMT_REOBS recovered=$FMT_RECOVERED timed-out=$FMT_TIMEDOUT"
awk '{print $1}' "$MW/raw" | sort | uniq -c | sort -rn
if [ "$(wc -l < "$MW/list")" -lt 1 ]; then
  echo "*** fmt corpus walk=src: no modules found — the walk proved nothing ***"; fail=1
elif [ "$(wc -l < "$MW/raw")" != "$(wc -l < "$MW/list")" ]; then
  echo "*** fmt corpus walk=src: classified $(wc -l < "$MW/raw") of $(wc -l < "$MW/list") modules —"
  echo "    a module produced no line at all, so the walk covered LESS than src/+lib/ ***"; fail=1
elif [ "$INV" -lt "$(wc -l < "$MW/list")" ]; then
  echo "*** fmt corpus walk=src: $INV fmt invocations for $(wc -l < "$MW/list") modules — fewer than"
  echo "    one per module, so the walk did not actually format everything it listed ***"; fail=1
elif [ "$FMT_TIMEDOUT" != 0 ]; then
  echo "*** fmt corpus walk=src: $FMT_TIMEDOUT module(s) hit the ${TCC}s ceiling $(fmt_timedout_basis) —"
  echo "    reported above under MOD-TIMED-OUT. Not a fmt finding, and not a pass either ***"
elif [ ! -s "$MW/regressions" ]; then
  echo "*** fmt corpus walk=src: idempotent on every module bar the reasoned residuals ***"
else
  echo "*** fmt corpus walk=src: $(wc -l < "$MW/regressions") NEW failure(s) — see REGRESSION above ***"
fi

fi  # end walk 2

exit $fail
