#!/usr/bin/env bash
# scripts/ir_diff.sh — the x86 DIFFERENTIAL of the shared IR (`docs/ir.md` §7.1 rule 5,
# `docs/ir-slice-1.md` §5 item 4, slice 1d; #683).
#
# ## What it compares
#
# Every tracked corpus program (`git ls-files 'test/*.al'`, the manifest's `source_glob`) whose x86
# emission has at least one function selected from the shared IR is built and run twice on x86_64:
#
#   legacy    every function emitted by the legacy x86 emitter;
#   ir        the same invocation, front half, peephole and link, except that every function the IR
#             builder builds, the verifier accepts and `src/lower/isel.al` selects is emitted from the IR
#             instead (owner decision D7: every other function keeps its legacy emission).
#
# One of the two is the DEFAULT path, `alatyr -o <exe> <file>` — exactly the manifest's x86_64
# observation — and the other is a dev verb. Which is which moves at the x86 flip (`docs/ir.md` §7.4,
# #980), and this script asks the compiler rather than assuming (`decide_sides` below):
#
#   before the flip   default = legacy, other = `alatyr x86-ir -o <exe> <file>`;
#   after the flip    default = ir,     other = `alatyr x86-legacy -o <exe> <file>`.
#
# Two facts decide it, both read off the compiler under test: whether `alatyr --help` lists the
# `x86-legacy` verb, and whether the DEFAULT GAS dump of a probe program carries the selector's
# `# ir: selected` line. The pairs that agree name a side; the two that do not — a legacy verb beside a
# legacy default, or an IR default with no way back to legacy — are refused with exit 2, never guessed.
# Two more facts prove each side is what its name says, so the differential can never compare a side
# with itself: the `x86-ir` dump of the probe must select (on either side of the flip), and after the
# flip the `x86-legacy` dump of it must select nothing. The decision is printed as the `ir_diff: sides`
# line before the report.
#
# The two observations — the build's phase and exit, then the program's exit and stdout — must
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
# corpus, the `x86-ir` verb is missing, or the sides cannot be told apart or are not what they are named.
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
# `x86_*` columns are the LEGACY path's observation and the `ir_*` columns the IR path's, whichever of
# the two is the default; they are `-` when the program was not built twice.

# oracle <file> — what the program's OWN header declares as its expected outcome: `reject`, `exit:<N>`,
# or `none`. It lives in `scripts/fixture_oracle.sh`, shared with `xbackend_diff.sh`: two readers of the
# same declaration is the same defect class the IR removes from the emitters — one question, two places,
# free to drift. The regression tests in test/ state it in prose that is already machine-readable
# (`## build_reject`, `## Expected exit: 42`, `## Expected: TRAP (SIGILL, exit 132)`), and until this
# existed ir_diff never read it: every disagreement was "unexplained" even when the file named the culprit.
. "$(dirname "${BASH_SOURCE[0]}")/fixture_oracle.sh"

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

# decide_sides <legacy_verb> <default_selects> <legacy_selects> <ir_selects> — which path is the
# default, from four facts read off the compiler with one probe program:
#   legacy_verb      does `--help` list `x86-legacy` (1/0);
#   default_selects  does the DEFAULT dump of the probe carry `# ir: selected` (1/0);
#   legacy_selects   does the `x86-legacy` dump of the probe carry it (1/0; `-` when there is no verb);
#   ir_selects       does the `x86-ir` dump of the probe carry it (1/0).
# A probe dump that fails or prints nothing reads as `-`, never as "selects nothing".
# Prints `<side> <sentence>`, side `pre` or `post`, and answers 0; anything else prints
# `refuse <sentence>` and answers 2. The flip moves the first two facts in one commit (59e7be245 adds
# the verb and turns the default on together), so a split pair is a compiler this script does not
# understand, and it says so rather than picking a side. The last two prove each side is what its
# name says: a side that is only named, never observed, lets the differential compare IR with IR (or
# legacy with legacy) and report `disagree=0` on a self-comparison, which the ratchet in
# `scripts/full.sh` would then hold as green.
decide_sides() {
  case "$4" in
    1) ;;
    0) echo "refuse the x86-ir dump of the probe selects nothing from the IR, so there is no IR side to compare against"; return 2 ;;
    *) echo "refuse the side probe was unreadable (x86-ir selects '$4')"; return 2 ;;
  esac
  case "$1:$2:$3" in
    0:0:-) echo "pre default=legacy other=x86-ir (pre-flip: this compiler has no x86-legacy verb, its default dump selects nothing from the IR, and its x86-ir dump does)" ;;
    1:1:0) echo "post default=ir other=x86-legacy (post-flip: this compiler lists the x86-legacy verb, its default dump selects from the IR, and its x86-legacy dump selects nothing)" ;;
    1:1:1) echo "refuse this compiler's x86-legacy dump selects from the IR, so the legacy side is not legacy and the differential would compare the IR with itself"; return 2 ;;
    1:0:[01]) echo "refuse this compiler lists the x86-legacy verb but its default dump selects nothing from the IR; which side is the default cannot be told"; return 2 ;;
    0:1:-) echo "refuse this compiler's default dump selects from the IR but it has no x86-legacy verb, so there is no legacy side to compare against"; return 2 ;;
    *) echo "refuse the side probe was unreadable (legacy verb '$1', default selects '$2', x86-legacy selects '$3')"; return 2 ;;
  esac
}

# verbs_for <side> — the verb each observation is built through, `<legacy> <ir>`, `-` for the default
# path. The one place the side decision turns into commands; the self-test holds both rows.
verbs_for() {
  case "$1" in
    pre) echo "- x86-ir" ;;
    post) echo "x86-legacy -" ;;
    *) echo "verbs_for: unknown side '$1'" >&2; return 2 ;;
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
    printf '  DISAGREE %-6s %-18s %s  (ir fns %s)  legacy: %s %s %.12s  ir: %s %s %.12s\n' \
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
  # the side decision: both agreeing sets, both split pairs, a legacy verb that selects (post-flip, the
  # self-comparison), an x86-ir verb that does not (either side of the flip), and unreadable probes
  sides() { # name want-rc want-prefix legacy-verb default-selects legacy-selects ir-selects
    local got rc
    got="$(decide_sides "$4" "$5" "$6" "$7")"; rc=$?
    case "$rc:$got" in
      "$2:$3"*) echo "ok   ir_diff self-test sides $1" ;;
      *) echo "FAIL ir_diff self-test sides $1 (rc=$rc '$got')"; st_fail=$((st_fail + 1)) ;;
    esac
  }
  sides pre-flip 0 "pre default=legacy other=x86-ir" 0 0 - 1
  sides post-flip 0 "post default=ir other=x86-legacy" 1 1 0 1
  sides verb-without-ir-default 2 "refuse " 1 0 0 1
  sides ir-default-without-verb 2 "refuse " 0 1 - 1
  sides legacy-verb-selects-ir 2 "refuse this compiler's x86-legacy dump selects" 1 1 1 1
  sides pre-flip-x86-ir-selects-nothing 2 "refuse the x86-ir dump of the probe selects nothing" 0 0 - 0
  sides post-flip-x86-ir-selects-nothing 2 "refuse the x86-ir dump of the probe selects nothing" 1 1 0 0
  sides unreadable-default 2 "refuse the side probe was unreadable" 0 "" - 1
  sides unreadable-legacy-dump 2 "refuse the side probe was unreadable" 1 1 - 1
  sides unreadable-ir-dump 2 "refuse the side probe was unreadable" 0 0 - -
  # the decision turned into verbs, both ways round, and an unknown side refused
  verbs() { # name side want-rc want
    local got rc
    got="$(verbs_for "$2" 2>/dev/null)"; rc=$?
    if [ "$rc" = "$3" ] && [ "$got" = "$4" ]; then echo "ok   ir_diff self-test verbs $1"
    else echo "FAIL ir_diff self-test verbs $1 (rc=$rc '$got')"; st_fail=$((st_fail + 1)); fi
  }
  verbs pre pre 0 "- x86-ir"
  verbs post post 0 "x86-legacy -"
  verbs unknown refuse 2 ""
  [ "$st_fail" = 0 ] || printf '%s\n' "$out" | sed 's/^/     /'
  echo "ir_diff self-test: 25 checks, $st_fail failed"
  [ "$st_fail" = 0 ] || exit 1
  exit 0
fi

[ -x "$AL" ] || { echo "ir_diff: no compiler at $AL (build it first)" >&2; exit 2; }
"$AL" --help 2>/dev/null | grep -q '^  x86-ir ' || { echo "ir_diff: $AL has no x86-ir verb" >&2; exit 2; }
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/rows" "$W/work"

# Which side is the default, and whether each side is what its name says (`decide_sides`). The probe
# is one function the selector takes on every revision since slice 1d; each of its GAS dumps is read
# for the selector's marker. A dump that fails or prints nothing answers `-`, which refuses: "the dump
# broke" must never read as "selects nothing", or a broken legacy verb would pass as a legacy one.
legacy_verb=0
"$AL" --help 2>/dev/null | grep -q '^  x86-legacy ' && legacy_verb=1
printf 'main := fn() -> u64 {\n  x : u64 = 40\n  x + 2\n}\n' > "$W/probe.al"
probe_sel() { # [verb] — 1/0: does the probe's dump through the verb (none = default) carry the marker
  timeout "$TMO" "$AL" "$@" "$W/probe.al" > "$W/probe.s" 2> /dev/null < /dev/null || { echo -; return; }
  [ -s "$W/probe.s" ] || { echo -; return; }
  if grep -q '^# ir: selected from the shared IR$' "$W/probe.s"; then echo 1; else echo 0; fi
}
ir_sel="$(probe_sel x86-ir)"
default_sel="$(probe_sel)"
legacy_sel=-
[ "$legacy_verb" = 1 ] && legacy_sel="$(probe_sel x86-legacy)"
sides_line="$(decide_sides "$legacy_verb" "$default_sel" "$legacy_sel" "$ir_sel")" || { echo "ir_diff: ${sides_line#refuse } (on $AL)" >&2; exit 2; }
[ "$legacy_verb" = 1 ] || echo "ir_diff: $AL has no x86-legacy verb; taking the pre-flip path (default = legacy, other = x86-ir)"
echo "ir_diff: sides ${sides_line#* }"
# The verb each observation is built through; empty is the default path.
verbs="$(verbs_for "${sides_line%% *}")" || exit 2
LEGACY_VERB="${verbs%% *}"; IR_VERB="${verbs#* }"
[ "$LEGACY_VERB" = - ] && LEGACY_VERB=""
[ "$IR_VERB" = - ] && IR_VERB=""
git ls-files 'test/*.al' | sort -u > "$W/corpus.list"
[ -s "$W/corpus.list" ] || { echo "ir_diff: no corpus sources" >&2; exit 2; }

# One program: dump through the verb to count the selected functions; when there is one, build and run
# it through both paths. The run environment is the manifest's (scripts/corpus_manifest.sh `run_prog`).
export AL W TMO LEGACY_VERB IR_VERB
one() {
  local f="$1" key d drc nsel xp xe xs ip ie is
  key=$(printf '%s' "$f" | tr '/' '_')
  d="$W/work/$key"; mkdir -p "$d"
  timeout "$TMO" "$AL" x86-ir "$f" > "$d/ir.s" 2> "$d/ir.s.err" < /dev/null
  drc=$?
  nsel=$(grep -c '^# ir: selected from the shared IR$' "$d/ir.s" || true)
  xp=-; xe=-; xs=-; ip=-; ie=-; is=-
  if [ "$drc" = 0 ] && [ "$nsel" != 0 ]; then
    obs() { # <exe> [verb] — sets P E S; an empty verb is the default path
      local exe="$1" verb="${2:-}"
      timeout "$TMO" "$AL" ${verb:+"$verb"} -o "$exe" "$f" > "$exe.b.out" 2> "$exe.b.err" < /dev/null
      local brc=$?
      if [ "$brc" != 0 ]; then P=build; [ "$brc" = 124 ] && P=build_timeout; E=$brc; S=-; return; fi
      ( exec 2>/dev/null
        timeout "$TMO" env -i LC_ALL=C TZ=UTC HOME=/nonexistent PATH=/usr/bin:/bin "$exe" > "$exe.out" 2> "$exe.err" < /dev/null )
      E=$?; P=run; S=$(sha256sum < "$exe.out" | cut -d' ' -f1)
    }
    obs "$d/x86" "$LEGACY_VERB"; xp=$P; xe=$E; xs=$S
    obs "$d/ir" "$IR_VERB"; ip=$P; ie=$E; is=$S
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$drc" "$nsel" "$xp" "$xe" "$xs" "$ip" "$ie" "$is" > "$W/rows/$key"
  rm -rf "$d"
}
export -f one
xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} < "$W/corpus.list"
analyse "$W"
