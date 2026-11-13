#!/usr/bin/env bash
# scripts/full_parts.sh — the ONE verdict of a full gate run as parallel parts (#1568).
#
# ## Why
#
# One `scripts/full.sh --force-sweeps` on a 4-core GitHub runner took 82 minutes (run 42653954256): 18 of
# them FIXPOINT, then 64 of stages run one after another although they share nothing but the compiler
# the fixpoint built. `.github/workflows/gate.yml` therefore runs `full.sh` once per part
# (ALATYR_FULL_PART, the table in scripts/full.sh, `full.sh --parts`), each on its own runner, and this
# script turns the part logs into the gate's verdict. Every reader (the lanes, the reviewers, the
# integrator) greps a run for one `*** FULL GATE` line and one `xbackend diff:` line, so the aggregate
# has to keep that contract exactly. A part that is missing, cancelled, red, or that ran other stages
# than its own must read as red, never as green.
#
# ## What GREEN means here
#
#   - every part of the table left a log, and each log names this gate object;
#   - each log carries exactly one `--- full part <part>: GREEN ---` and no line containing
#     `*** FULL GATE` (only this script prints one, so a run and its gate.log hold exactly one);
#   - each log's `full part: <part> ran=` list is exactly the table's stages for that part, so every
#     stage ran exactly once over the whole run;
#   - exactly one `xbackend diff: paths=` line across all the logs;
#   - the sweeps part reports `sweeps STATUS=RAN`. Any other status prints the same "SWEEPS DID NOT RUN"
#     verdict full.sh prints.
#
# Usage:  bash scripts/full_parts.sh --collect <download-dir> <gate-object-sha> <parts-dir> <gate.log>
#         bash scripts/full_parts.sh --aggregate <dir-of-<part>.log> <gate-object-sha>
#         bash scripts/full_parts.sh --self-test
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## The coverage names full.sh's serial verdict defaults to `NO COVERAGE LINE` (#1598)
FULL_PARTS_COVER_REQUIRED="ird fc ig"

## aggregate TABLE DIR OBJECT -> stdout: the verdict; 0 GREEN, 1 anything else
aggregate() {
  local table="$1" dir="$2" obj="$3" bad=0 p want got log n red sw="" xb=0 reasons=""
  why() { reasons="${reasons}    $*"$'\n'; bad=1; }
  [ -n "$obj" ] || why "no gate object was named"
  for p in $(printf '%s\n' "$table" | awk '{ print $1 }' | uniq); do
    log="$dir/$p.log"
    if [ ! -s "$log" ]; then why "part $p: no log (the job did not run, was cancelled, or uploaded nothing)"; continue; fi
    n="$(grep -c "^gate object: $obj " "$log")"
    [ "$n" = 1 ] || why "part $p: its log names gate object $obj $n time(s), want 1"
    [ "$(grep -c '\*\*\* FULL GATE' "$log")" = 0 ] || why "part $p: carries a whole-gate verdict line, which only the aggregate prints"
    n="$(grep -cE '^--- full part [a-z0-9-]+: (GREEN|FAILURES|REFUSED)' "$log")"
    if [ "$n" != 1 ]; then why "part $p: $n part verdict lines, want 1 (the job stopped before its verdict?)"
    elif ! grep -qx -- "--- full part $p: GREEN ---" "$log"; then
      why "part $p: $(grep -E '^--- full part ' "$log")"
      red="$(grep -E "^full part: $p red=" "$log" | tail -1 | sed "s/^full part: $p red=//")"
      [ -z "$red" ] || why "  red stages: $red"
      grep -A12 -E '^--- full part ' "$log" | grep -E '^    full_[a-z_0-9-]+ ' | head -8 | sed 's/^/  /' > "$dir/.why"
      while IFS= read -r n; do reasons="${reasons}    $n"$'\n'; done < "$dir/.why"; rm -f "$dir/.why"
    fi
    want="$(printf '%s\n' "$table" | awk -v p="$p" '$1 == p { print $2 }' | sort | tr '\n' ',')"
    n="$(grep -c "^full part: $p ran=" "$log")"
    got="$(grep "^full part: $p ran=" "$log" | tail -1 | sed "s/^full part: $p ran=//" | tr ',' '\n' | grep -v '^$' | sort | tr '\n' ',')"
    if [ "$n" != 1 ]; then why "part $p: $n 'ran=' lines, want 1"
    elif [ "$want" != "$got" ]; then why "part $p: ran {${got%,}}, its stages are {${want%,}}"; fi
    xb=$((xb + $(grep -c '^xbackend diff: paths=' "$log")))
    [ "$p" = sweeps ] && sw="$(grep -E '^full part: sweeps STATUS=' "$log" | tail -1 | sed 's/^full part: sweeps STATUS=//')"
  done
  for log in "$dir"/*.log; do
    [ -e "$log" ] || continue
    p="$(basename "$log" .log)"
    printf '%s\n' "$table" | awk -v p="$p" '$1 == p { f = 1 } END { exit !f }' || why "part $p: a log for a part the table does not name (gate.yml's matrix and the table differ)"
  done
  [ "$xb" = 1 ] || why "$xb 'xbackend diff: paths=' lines across the parts, want exactly 1"
  if printf '%s\n' "$table" | awk '$1 == "sweeps"' | grep -q . && [ -z "$sw" ]; then why "the sweeps part reported no STATUS"; fi
  if [ "$bad" != 0 ]; then
    echo "*** FULL GATE: FAILURES ***"
    echo "  the parts of gate object ${obj:-?} (scripts/full_parts.sh, #1568):"
    printf '%s' "$reasons"
    return 1
  fi
  if [ "$sw" = RAN ]; then echo "*** FULL GATE: GREEN (sweeps RAN) ***"
  else
    echo "*** FULL GATE: GREEN — but the SWEEPS DID NOT RUN (sweeps STATUS=$sw): the aarch64/"
    echo "    riscv64/wasm backends were NOT exercised by the sweeps. Re-run with --force-sweeps before"
    echo "    landing any change that can reach a backend. ***"
  fi
  echo "    gate object:     $obj, $(printf '%s\n' "$table" | awk '{ print $1 }' | uniq | wc -l | tr -d ' ') parts in parallel"
  ## Each coverage value once over the run, under the first part (table order) that reports it: the
  ## pre-build stages run in every part, so their lines would otherwise print once per part (#1598).
  for p in $(printf '%s\n' "$table" | awk '{ print $1 }' | uniq); do
    grep -E '^full part cover: [a-z]+ ' "$dir/$p.log" | sed "s/^full part cover: /$p /"
  done | awk '!seen[$2]++ { p = $1; sub(/^[^ ]+ /, ""); print "    [" p "] " $0 }'
  ## The values the serial verdict prints as `NO COVERAGE LINE` when empty (full.sh: ird_cover, fc_line,
  ## ig_line) say so here too, rather than dropping out of the verdict unseen.
  for n in $FULL_PARTS_COVER_REQUIRED; do
    grep -qE "^full part cover: $n " "$dir"/*.log 2>/dev/null || echo "    [?] $n NO COVERAGE LINE"
  done
  return 0
}

## collect TABLE DOWNLOADED SHA PARTSDIR GATELOG -> copies every part log the matrix uploaded
## (DOWNLOADED/gate-SHA-<anything>/parts/*.log) into PARTSDIR, not only the table's, so a matrix part
## the table does not name reaches the aggregate, which refuses it (#1598); appends them to GATELOG in
## table order, then any extra part. gate.yml's verdict job runs it, so the self-test can plant the
## artifacts it reads.
collect() {
  local table="$1" dl="$2" sha="$3" pd="$4" gl="$5" f p parts
  mkdir -p "$pd"
  for f in "$dl"/gate-"$sha"-*/parts/*.log; do
    [ -f "$f" ] && cp "$f" "$pd/$(basename "$f")"
  done
  parts="$(printf '%s\n' "$table" | awk '{ print $1 }' | uniq)"
  for p in $parts; do [ -f "$pd/$p.log" ] && cat "$pd/$p.log" >> "$gl"; done
  for f in "$pd"/*.log; do
    [ -f "$f" ] || continue
    printf '%s\n' "$parts" | grep -qx "$(basename "$f" .log)" || cat "$f" >> "$gl"
  done
  return 0
}

## workflow_parts_ok GATEYML -> 0 when every `run: |` block that writes `parts/` (a `tee` or a `>` into
## it) runs `mkdir -p parts` before that line, or hands parts/ to --collect, which creates it
workflow_parts_ok() {
  awk '
    /^ *(- name:|- uses:)/ || /^ *run: \|/ { made = 0 }
    /mkdir -p parts/ || /--collect / { made = 1 }
    /(tee|>>?) *"?parts\// && !made { print "  gate.yml:" NR ": writes parts/ before creating it" > "/dev/stderr"; bad = 1 }
    END { exit bad }' "$1"
}

## guards_match_table FULLSH TABLE -> 0 when every `if full_part_runs X; then` of FULLSH names a stage of
## TABLE once, and every TABLE stage has exactly one guard; prints each mismatch
guards_match_table() {
  local g t rc=0
  g="$(sed -nE 's/^if full_part_runs ([a-z0-9-]+); then$/\1/p' "$1" | sort)"
  t="$(printf '%s\n' "$2" | awk '{ print $2 }' | sort)"
  [ -z "$(printf '%s\n' "$g" | uniq -d)" ] || { echo "  guarded twice: $(printf '%s\n' "$g" | uniq -d | tr '\n' ' ')"; rc=1; }
  [ -z "$(printf '%s\n' "$t" | uniq -d)" ] || { echo "  in the table twice: $(printf '%s\n' "$t" | uniq -d | tr '\n' ' ')"; rc=1; }
  [ -z "$(comm -23 <(printf '%s\n' "$g" | uniq) <(printf '%s\n' "$t" | uniq))" ] || { echo "  guarded, not in the table: $(comm -23 <(printf '%s\n' "$g" | uniq) <(printf '%s\n' "$t" | uniq) | tr '\n' ' ')"; rc=1; }
  [ -z "$(comm -13 <(printf '%s\n' "$g" | uniq) <(printf '%s\n' "$t" | uniq))" ] || { echo "  in the table, never guarded: $(comm -13 <(printf '%s\n' "$g" | uniq) <(printf '%s\n' "$t" | uniq) | tr '\n' ' ')"; rc=1; }
  return "$rc"
}

self_test() {
  local d rc=0 n=0 T O=0123abcd FULL_PARTS_COVER_REQUIRED=ird
  d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  chk() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; rc=1; fi; }
  T='a s1
a s2
corpus xb
sweeps sweeps'
  part() { # part ran-list [extra-line...]
    local p="$1" r="$2"; shift 2
    { echo "gate object: $O  base: b  runner: 4 cpu"; echo "*** TOOL-1 FIXPOINT: seed == Stage1 == Stage2 (9 lines) ***"
      echo "full part: $p ran=$r"; [ "$p" = sweeps ] && echo "full part: sweeps STATUS=RAN"
      [ "$p" = corpus ] && echo "xbackend diff: paths=9 rows=9"
      echo "full part cover: ce shared by every part"; echo "full part cover: $p covered"
      [ "$p" = corpus ] && echo "full part cover: ird 4 disagree"
      for x in "$@"; do echo "$x"; done
      echo "--- full part $p: GREEN ---"; } > "$d/r/$p.log"
  }
  green() { rm -rf "$d/r"; mkdir -p "$d/r"; part a s1,s2; part corpus xb; part sweeps sweeps; }
  run() { aggregate "$T" "$d/r" "${1-$O}" > "$d/out" 2>&1; echo "$?:$(grep -c '\*\*\* FULL GATE' "$d/out")"; }

  green; chk "control: every part green and complete is GREEN, with exactly one verdict line" "$(run)" "0:1"
  chk "control: the green verdict says the sweeps ran" "$(grep -c '^\*\*\* FULL GATE: GREEN (sweeps RAN) \*\*\*$' "$d/out")" "1"
  chk "control: the green verdict carries each part's coverage" "$(grep -c '^    \[[a-z]*\] ' "$d/out")" "5"
  chk "control: a coverage line every part reports prints once, under the first part" "$(grep -c '^    \[a\] ce shared by every part$' "$d/out")" "1"
  chk "control: no required coverage value is missing" "$(grep -c 'NO COVERAGE LINE' "$d/out")" "0"
  green; sed -i.b '/^full part cover: ird /d' "$d/r/corpus.log"; run > /dev/null
  chk "plant: a required coverage value no part reports says NO COVERAGE LINE" "$(grep -c '^    \[?\] ird NO COVERAGE LINE$' "$d/out")" "1"
  green; rm "$d/r/corpus.log"; chk "plant: a missing part (cancelled, skipped) is red" "$(run)" "1:1"
  green; : > "$d/r/a.log"; chk "plant: an empty part log is red" "$(run)" "1:1"
  green; sed -i.b 's/: GREEN ---$/: FAILURES ---/' "$d/r/a.log"; echo "full part: a red=s2" >> "$d/r/a.log"; chk "plant: a red part is red" "$(run)" "1:1"
  chk "control: a red part's verdict names its red stage" "$(grep -c 'red stages: s2' "$d/out")" "1"
  green; sed -i.b 's/^--- full part a: GREEN ---$/--- full part a: REFUSED before any stage ran ---/' "$d/r/a.log"; chk "plant: a refused part is red" "$(run)" "1:1"
  green; sed -i.b '/^--- full part/d' "$d/r/a.log"; chk "plant: a part that stopped before its verdict is red" "$(run)" "1:1"
  green; sed -i.b 's/^--- full part a: GREEN/--- full part corpus: GREEN/' "$d/r/a.log"
  chk "plant: a part log carrying ANOTHER part's green is red" "$(run)" "1:1"
  green; part a s1; chk "plant: a part that skipped one of its stages is red" "$(run)" "1:1"
  green; part a s1,s2,xb; chk "plant: a part that ran another part's stage is red" "$(run)" "1:1"
  green; part a s1,s1,s2; chk "plant: a stage that ran twice in its part is red" "$(run)" "1:1"
  green; echo "full part: a ran=s1" >> "$d/r/a.log"; chk "plant: two ran lines in one part are red" "$(run)" "1:1"
  green; echo "*** FULL GATE: GREEN (sweeps RAN) ***" >> "$d/r/a.log"; chk "plant: a part carrying a whole-gate verdict is red" "$(run)" "1:1"
  green; echo "x *** FULL GATE PART a: GREEN ***" >> "$d/r/a.log"; chk "plant: a part carrying any '*** FULL GATE' text is red" "$(run)" "1:1"
  green; part a s1,s2 "xbackend diff: paths=9 rows=9"; chk "plant: two xbackend diff lines are red" "$(run)" "1:1"
  green; sed -i.b '/^xbackend diff/d' "$d/r/corpus.log"; chk "plant: no xbackend diff line is red" "$(run)" "1:1"
  green; part extra s9; chk "plant: a part the table does not name is red" "$(run)" "1:1"
  green; chk "plant: a log naming another gate object is red" "$(run fedcba98)" "1:1"
  green; chk "plant: no gate object named is red" "$(run '')" "1:1"
  green; sed -i.b 's/STATUS=RAN/STATUS=SKIPPED/' "$d/r/sweeps.log"; run > /dev/null
  chk "control: sweeps that did not run are green but say so" "$(grep -c 'SWEEPS DID NOT RUN' "$d/out")" "1"
  green; sed -i.b '/STATUS=/d' "$d/r/sweeps.log"; chk "plant: a sweeps part with no STATUS is red" "$(run)" "1:1"

  green; echo "full part cover: zz a  b|c — d	e" >> "$d/r/a.log"; run > /dev/null
  chk "control: a coverage value keeps its spaces, tabs and punctuation" "$(grep -cF "    [a] zz a  b|c — d	e" "$d/out")" "1"

  ## collect: the artifacts as download-artifact@v4 lays them out (one directory per artifact)
  coll() { rm -rf "$d/dl" "$d/p" "$d/g.log"; green
    for p in a corpus sweeps; do mkdir -p "$d/dl/gate-$O-$p/parts"; cp "$d/r/$p.log" "$d/dl/gate-$O-$p/parts/"; done; }
  coll; collect "$T" "$d/dl" "$O" "$d/p" "$d/g.log"
  chk "control: collect copies the table's parts" "$(ls "$d/p" | tr '\n' ' ')" "a.log corpus.log sweeps.log "
  chk "control: collect writes gate.log in table order" "$(grep -o '^--- full part [a-z]*' "$d/g.log" | tr '\n' '|')" "--- full part a|--- full part corpus|--- full part sweeps|"
  coll; mkdir -p "$d/dl/gate-$O-extra/parts"; part extra s9; cp "$d/r/extra.log" "$d/dl/gate-$O-extra/parts/"
  collect "$T" "$d/dl" "$O" "$d/p" "$d/g.log"; aggregate "$T" "$d/p" "$O" > "$d/out" 2>&1
  chk "plant: an uploaded part the table does not name reaches the aggregate and is red" "$?:$(grep -c 'part extra: a log for a part the table does not name' "$d/out")" "1:1"
  chk "control: an extra part's log follows the table's in gate.log" "$(grep -o '^--- full part [a-z]*' "$d/g.log" | tail -1)" "--- full part extra"
  coll; mkdir -p "$d/dl/gate-$O/parts" "$d/dl/gate-fedcba98-x/parts"; echo decoy > "$d/dl/gate-$O/parts/zz.log"; echo decoy > "$d/dl/gate-fedcba98-x/parts/yy.log"
  collect "$T" "$d/dl" "$O" "$d/p" "$d/g.log"
  chk "control: collect ignores the aggregate's artifact and another object's" "$(ls "$d/p" | tr '\n' ' ')" "a.log corpus.log sweeps.log "

  ## The workflow's own shell (#1646 review N4): each step that tees into parts/ makes it first, since
  ## tee opens its file before full.sh runs, and a missing directory turns every part red.
  chk "the real gate.yml: every step that writes parts/ creates it first" "$(workflow_parts_ok "$ROOT/.github/workflows/gate.yml"; echo $?)" "0"
  sed '/^          mkdir -p parts$/d' "$ROOT/.github/workflows/gate.yml" > "$d/g.yml"
  chk "plant: a gate.yml whose part step tees into parts/ without creating it is refused" "$(workflow_parts_ok "$d/g.yml" 2>/dev/null; echo $?)" "1"

  printf 'if full_part_runs s1; then\nfi\nif full_part_runs s2; then\nfi\nif full_part_runs xb; then\nfi\nif full_part_runs sweeps; then\nfi\n' > "$d/f.sh"
  guards_match_table "$d/f.sh" "$T" > /dev/null; chk "control: one guard per table stage matches" "$?" "0"
  printf 'if full_part_runs s9; then\n' >> "$d/f.sh"; guards_match_table "$d/f.sh" "$T" > /dev/null
  chk "plant: a guard whose stage is in no part is refused" "$?" "1"
  printf 'if full_part_runs s1; then\nif full_part_runs xb; then\nif full_part_runs sweeps; then\n' > "$d/f.sh"
  guards_match_table "$d/f.sh" "$T" > /dev/null; chk "plant: a table stage with no guard is refused" "$?" "1"
  printf 'if full_part_runs s1; then\nif full_part_runs s1; then\nif full_part_runs s2; then\nif full_part_runs xb; then\nif full_part_runs sweeps; then\n' > "$d/f.sh"
  guards_match_table "$d/f.sh" "$T" > /dev/null; chk "plant: a stage guarded twice is refused" "$?" "1"
  guards_match_table "$ROOT/scripts/full.sh" "$(bash "$ROOT/scripts/full.sh" --parts)"
  chk "the real scripts/full.sh: every guard is a table stage and every table stage is guarded once" "$?" "0"
  [ "$rc" = 0 ] && echo "full parts self-test: $n checks, 0 failed" || echo "full parts self-test: FAILED"
  return "$rc"
}

case "${1:-}" in
  --aggregate) aggregate "$(bash "$ROOT/scripts/full.sh" --parts)" "${2:?the directory of part logs}" "${3:-}" ;;
  --collect) collect "$(bash "$ROOT/scripts/full.sh" --parts)" "${2:?the download directory}" "${3:?the gate object}" "${4:?the parts directory}" "${5:?the gate log}" ;;
  --self-test) self_test ;;
  -h|--help|'') sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d'; [ -n "${1:-}" ] ;;
  *) echo "full parts: unknown argument '$1' (try --help)" >&2; exit 2 ;;
esac
