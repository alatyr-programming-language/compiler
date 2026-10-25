#!/usr/bin/env bash
# scripts/ir_diff.sh — the x86 DIFFERENTIAL of the shared IR (`docs/ir.md` §7.1 rule 5,
# `docs/ir-slice-1.md` §5 item 4, slice 1d; #683).
#
# ## What it compares
#
# Every tracked corpus program (`git ls-files 'test/*.al'`, the manifest's `source_glob`) whose x86
# emission has at least one function selected from the shared IR is built and run twice on x86_64:
#
#   x86       the default path, `alatyr -o <exe> <file>` — exactly the manifest's x86_64 observation;
#   x86-ir    the dev verb, `alatyr x86-ir -o <exe> <file>` — the same invocation, front half,
#             peephole and link, except that every function the IR builder builds, the verifier
#             accepts and `src/lower/isel.al` selects is emitted from the IR instead of by the legacy
#             emitter (owner decision D7: every other function keeps its legacy emission).
#
# and the two observations — the build's phase and exit, then the program's exit and stdout — must
# agree. A program with no selected function (`alatyr x86-ir <file>` prints no `# ir: selected` line)
# is not built twice: both paths would emit the same GAS. It is the proof that the builder means what
# the reference lowering means, function by function, before any twin relies on it — and the count of
# programs with a selected function is x86's IR coverage long before the flip (`docs/ir.md` §7.4).
#
# Each disagreement is classified by its first differing observation: `build` (one path failed to
# build or the build phases differ), `exit` (both ran, the exits differ), `stdout` (same exit, the
# output differs). A run of the dump verb that exits 70 is a verifier refusal over the x86 tree — a
# located internal error (`docs/ir.md` §5) — and is listed by name.
#
# ## Reporting only
#
# This script never gates on a FINDING: it exits 0 whenever it could take the differential, whatever
# it found. Each disagreement is a triage item — an IR or selector bug, a legacy x86 bug the IR
# answers per the specification, or a spec-silent question — and the triage's conclusions are not
# this script's to hold. What it must do is prove it can see one: `--self-test` feeds the analysis
# planted collections (no compiler), and a planted disagreement of each class must be reported with
# its path, a planted agreement must not be.
#
# ## Usage
#
#   scripts/ir_diff.sh [--jobs N] [--timeout S] [--quiet]
#   scripts/ir_diff.sh --self-test
#     --jobs N     parallel programs (default 4)
#     --timeout S  bound on each build step and each program run, seconds (default 30)
#     --quiet      print only the summary line and the disagreeing paths
#
# The compiler is `$ALATYR` if set, else this checkout's `target/debug/alatyr`.
# Exit 0 = the differential was taken (findings or not). 1 = --self-test failed. 2 = no compiler or no
# corpus, or the verb is missing.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AL="${ALATYR:-$ROOT/target/debug/alatyr}"
JOBS=4
TMO=30
QUIET=0
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELFTEST=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --timeout) TMO="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "usage: $0 [--jobs N] [--timeout S] [--quiet] | --self-test" >&2; exit 2 ;;
  esac
done
ulimit -c 0

# A collected row, one per program (`$W/rows/<key>`), tab-separated:
#   path  dump_rc  nsel  x86_phase  x86_exit  x86_stdout_sha  ir_phase  ir_exit  ir_stdout_sha
# `dump_rc`/`nsel` are the `alatyr x86-ir <file>` dump's exit and its selected-function count; the
# observation columns are `-` when the program was not built twice.

# oracle <file> — what the program's OWN header declares as its expected outcome. The regression tests
# in test/ state it in prose that is already machine-readable (`## build_reject`, `## Expected exit: 42`,
# `## Expected: TRAP (SIGILL, exit 132)`), and until now ir_diff never read it: it classified a row as
# build/exit/stdout and stopped, so every disagreement was "unexplained" even when the file named the
# culprit itself. Prints `reject`, `exit:<N>`, or `none`.
oracle() {
  local f="$1" hdr
  [ -f "$f" ] || { echo none; return; }
  hdr=$(head -n 30 "$f")
  if printf '%s\n' "$hdr" | grep -qiE '^##[[:space:]]*build_reject'; then echo reject; return; fi
  local n
  n=$(printf '%s\n' "$hdr" | grep -iE '^##[[:space:]]*expected' \
        | grep -oiE '(exit|status)[[:space:]]*[:=]?[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ -n "$n" ]; then echo "exit:$n"; else echo none; fi
}

# verdict <oracle> <x86_phase> <x86_exit> <ir_phase> <ir_exit> — who is wrong, given what the program
# declares. A refusal the emitter documents and the IR path does not need is a STOPGAP, not a defect;
# an exit that contradicts the declared one IS the defect, and it is named after the path that has it.
verdict() {
  local o="$1" xp="$2" xe="$3" ip="$4" ie="$5"
  case "$o" in
    reject)
      if [ "$xp" = build ] && [ "$ip" = run ]; then echo STOPGAP-IR-RUNS
      elif [ "$xp" = build ] && [ "$ip" = build ]; then echo BOTH-REFUSE
      elif [ "$ip" = build ] && [ "$xp" = run ]; then echo IR-REFUSES
      else echo UNEXPLAINED; fi ;;
    exit:*)
      local want=${o#exit:}
      # the path whose exit CONTRADICTS the declared one is the wrong one — read it that way round, as
      # the first draft of this did not: xe matching the declaration says nothing is wrong with x86.
      if [ "$xe" != "$want" ] && [ "$ie" = "$want" ]; then echo LEGACY-WRONG
      elif [ "$ie" != "$want" ] && [ "$xe" = "$want" ]; then echo IR-WRONG
      elif [ "$xe" != "$want" ] && [ "$ie" != "$want" ]; then echo BOTH-WRONG
      else echo STDOUT-ONLY; fi ;;
    *) echo UNEXPLAINED ;;
  esac
}

# analyse <dir> — read a collection and print the differential. Answers 0 (reporting only).
analyse() {
  local W="$1" path drc nsel xp xe xs ip ie is
  local n=0 withir=0 agree=0 dis=0 dbuild=0 dexit=0 dstdout=0 noir=0 refused=0 vfail=0 dfail=0 nfn=0
  local unexp=0 attrib=0
  : > "$W/disagree"; : > "$W/vfail"; : > "$W/dfail"; : > "$W/unexplained"
  for r in "$W"/rows/*; do
    [ -f "$r" ] || continue
    IFS=$'\t' read -r path drc nsel xp xe xs ip ie is < "$r"
    n=$((n + 1))
    if [ "$drc" = 70 ]; then vfail=$((vfail + 1)); echo "$path" >> "$W/vfail"; continue; fi
    if [ "$drc" = 1 ] || [ "$drc" = 9 ]; then refused=$((refused + 1)); continue; fi
    if [ "$drc" != 0 ]; then dfail=$((dfail + 1)); echo "$path dump rc=$drc" >> "$W/dfail"; continue; fi
    if [ "$nsel" = 0 ]; then noir=$((noir + 1)); continue; fi
    withir=$((withir + 1)); nfn=$((nfn + nsel))
    local cls=""
    if [ "$xp" != "$ip" ] || { [ "$xp" != run ] && [ "$xe" != "$ie" ]; }; then cls=build
    elif [ "$xe" != "$ie" ]; then cls=exit
    elif [ "$xs" != "$is" ]; then cls=stdout
    fi
    if [ -z "$cls" ]; then agree=$((agree + 1)); continue; fi
    dis=$((dis + 1))
    case "$cls" in build) dbuild=$((dbuild + 1)) ;; exit) dexit=$((dexit + 1)) ;; stdout) dstdout=$((dstdout + 1)) ;; esac
    local o v
    o=$(oracle "$path"); v=$(verdict "$o" "$xp" "$xe" "$ip" "$ie")
    if [ "$v" = UNEXPLAINED ]; then unexp=$((unexp + 1)); echo "$path" >> "$W/unexplained"; else attrib=$((attrib + 1)); fi
    printf '  DISAGREE %-6s %-18s %s  (ir fns %s)  x86: %s %s %.12s  x86-ir: %s %s %.12s\n' \
      "$cls" "$v" "$path" "$nsel" "$xp" "$xe" "$xs" "$ip" "$ie" "$is" >> "$W/disagree"
  done
  echo "ir diff: programs=$n with-ir=$withir ir-fns=$nfn agree=$agree disagree=$dis (build=$dbuild exit=$dexit stdout=$dstdout) attributed=$attrib unexplained=$unexp no-ir=$noir refused-by-check=$refused verify-failed=$vfail dump-failed=$dfail"
  if [ -s "$W/disagree" ]; then sort -k3 "$W/disagree"; fi
  if [ -s "$W/unexplained" ]; then
    echo "  UNEXPLAINED: these disagree and their own header declares no expected outcome, so nothing in"
    echo "  the repository says which path is wrong. Declare it in the file's header (## build_reject or"
    echo "  ## Expected exit: N), or fix the path that is wrong — scripts/corroboration.sh <file> asks"
    echo "  the other three backends, whose agreement is the oracle:"
    sed 's/^/    /' "$W/unexplained"
  fi
  if [ -s "$W/vfail" ]; then echo "  VERIFIER REFUSALS over the x86 tree (located internal errors, docs/ir.md §5):"; sed 's/^/    /' "$W/vfail"; fi
  if [ -s "$W/dfail" ] && [ "$QUIET" = 0 ]; then echo "  dump failures (x86-ir <file> exited neither 0 nor a check refusal):"; sed 's/^/    /' "$W/dfail"; fi
  return 0
}

# ---- the self-test: planted collections, no compiler ----
if [ "$SELFTEST" = 1 ]; then
  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT
  st_fail=0
  mkdir -p "$T/rows"
  row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" > "$T/rows/$(printf '%s' "$1" | tr '/' '_')"; }
  A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  # Planted SOURCES, not just rows: the verdict comes from what the program's own header declares, so
  # the self-test has to plant headers too. `oracle/` holds them; the row paths point into it.
  mkdir -p "$T/oracle"
  printf '## Expected: TRAP (SIGILL, exit 132) on x86_64\nmain := fn() -> u64 { exit(1) }\n' > "$T/oracle/trapdecl.al"
  printf '## build_reject — must FAIL LOUD.\nmain := fn() -> u64 { exit(2) }\n' > "$T/oracle/rejectdecl.al"
  printf '## Expected exit: 42\nmain := fn() -> u64 { exit(42) }\n' > "$T/oracle/irwrong.al"
  printf '## a regression with no declared outcome\nmain := fn() -> u64 { exit(3) }\n' > "$T/oracle/silent.al"
  row test/agree.al 0 2 run 42 "$A" run 42 "$A"
  row test/p_exit.al 0 1 run 42 "$A" run 132 "$A"
  row test/p_stdout.al 0 1 run 42 "$A" run 42 "$B"
  row test/p_build.al 0 3 run 42 "$A" build 1 -
  row test/noir.al 0 0 - - - - - -
  row test/reject.al 1 0 - - - - - -
  row test/vfail.al 70 0 - - - - - -
  # the declared oracle decides who is wrong, in both directions, and a refusal-vs-run pair where the
  # file documents its own refusal is a stopgap rather than a defect
  row "$T/oracle/trapdecl.al" 0 1 run 25 "$A" run 132 "$A"
  row "$T/oracle/rejectdecl.al" 0 1 build 1 "-" run 42 "$A"
  row "$T/oracle/irwrong.al" 0 1 run 42 "$A" run 7 "$A"
  row "$T/oracle/silent.al" 0 1 run 42 "$A" run 7 "$A"
  out="$(QUIET=0 analyse "$T" 2>&1)"
  chk() { # name needle
    if printf '%s\n' "$out" | grep -qF -- "$2"; then echo "ok   ir_diff self-test $1"
    else echo "FAIL ir_diff self-test $1 (needle '$2')"; st_fail=$((st_fail + 1)); fi
  }
  chk summary "ir diff: programs=11 with-ir=8 ir-fns=11 agree=1 disagree=7 (build=2 exit=4 stdout=1) attributed=3 unexplained=4 no-ir=1 refused-by-check=1 verify-failed=1 dump-failed=0"
  chk exit "DISAGREE exit   UNEXPLAINED"
  chk stdout "DISAGREE stdout UNEXPLAINED"
  chk build "DISAGREE build  UNEXPLAINED"
  chk legacy-wrong "DISAGREE exit   LEGACY-WRONG"
  chk stopgap "DISAGREE build  STOPGAP-IR-RUNS"
  chk ir-wrong "DISAGREE exit   IR-WRONG"
  chk unexplained-lists-only-silent "    $T/oracle/silent.al"
  chk unexplained-count "unexplained=4"
  chk vfail "    test/vfail.al"
  if printf '%s\n' "$out" | grep -qE 'DISAGREE .*test/(agree|noir|reject)\.al'; then
    echo "FAIL ir_diff self-test agreement reported as a disagreement"; st_fail=$((st_fail + 1))
  else echo "ok   ir_diff self-test agreement not reported"; fi
  # a declared trap must never read as the IR being wrong, and vice versa: the two directions are the
  # whole point of the attribution, so each is asserted against its ABSENCE too
  if printf '%s\n' "$out" | grep -qE 'DISAGREE .* IR-WRONG  *[[:space:]]*'"$T"'/oracle/trapdecl'; then
    echo "FAIL ir_diff self-test attributed a declared trap to the IR path"; st_fail=$((st_fail + 1))
  else echo "ok   ir_diff self-test declared trap not blamed on the IR"; fi
  [ "$st_fail" = 0 ] || printf '%s\n' "$out" | sed 's/^/     /'
  echo "ir_diff self-test: 12 checks, $st_fail failed"
  [ "$st_fail" = 0 ] || exit 1
  exit 0
fi

[ -x "$AL" ] || { echo "ir_diff: no compiler at $AL (build it first)" >&2; exit 2; }
"$AL" --help 2>/dev/null | grep -q '^  x86-ir ' || { echo "ir_diff: $AL has no x86-ir verb" >&2; exit 2; }
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/rows" "$W/work"
git ls-files 'test/*.al' | sort -u > "$W/corpus.list"
[ -s "$W/corpus.list" ] || { echo "ir_diff: no corpus sources" >&2; exit 2; }

# One program: dump through the verb to count the selected functions; when there is one, build and run
# it through both paths. The run environment is the manifest's (scripts/corpus_manifest.sh `run_prog`).
export AL W TMO
one() {
  local f="$1" key d drc nsel xp xe xs ip ie is
  key=$(printf '%s' "$f" | tr '/' '_')
  d="$W/work/$key"; mkdir -p "$d"
  timeout "$TMO" "$AL" x86-ir "$f" > "$d/ir.s" 2> "$d/ir.s.err" < /dev/null
  drc=$?
  nsel=$(grep -c '^# ir: selected from the shared IR$' "$d/ir.s" || true)
  xp=-; xe=-; xs=-; ip=-; ie=-; is=-
  if [ "$drc" = 0 ] && [ "$nsel" != 0 ]; then
    obs() { # <exe> <verb...> — sets P E S
      local exe="$1"; shift
      timeout "$TMO" "$AL" "$@" -o "$exe" "$f" > "$exe.b.out" 2> "$exe.b.err" < /dev/null
      local brc=$?
      if [ "$brc" != 0 ]; then P=build; [ "$brc" = 124 ] && P=build_timeout; E=$brc; S=-; return; fi
      ( exec 2>/dev/null
        timeout "$TMO" env -i LC_ALL=C TZ=UTC HOME=/nonexistent PATH=/usr/bin:/bin "$exe" > "$exe.out" 2> "$exe.err" < /dev/null )
      E=$?; P=run; S=$(sha256sum < "$exe.out" | cut -d' ' -f1)
    }
    obs "$d/x86"; xp=$P; xe=$E; xs=$S
    obs "$d/ir" x86-ir; ip=$P; ie=$E; is=$S
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$drc" "$nsel" "$xp" "$xe" "$xs" "$ip" "$ie" "$is" > "$W/rows/$key"
  rm -rf "$d"
}
export -f one
xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} < "$W/corpus.list"
analyse "$W"
