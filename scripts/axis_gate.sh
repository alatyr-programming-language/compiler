#!/usr/bin/env bash
# scripts/axis_gate.sh — the AXIS gate: which axis of a covered class has never been varied.
# REPORTING ONLY. It never edits a fixture, and it needs no compiler.
#
# WHY THIS EXISTS, AND WHY IT IS NOT A COVERAGE PERCENTAGE
# -------------------------------------------------------
# Every defect probing found in the layout and place families sat in a class the corpus ALREADY
# covered, with one axis pinned at the value that hides the defect. The ledger, not a guess:
#
#   * `test/deref_field_write.al` owns the `deref(p).f = v` store path and declares
#     `Rec := struct { a : i64, b : i64 }` — all wide, so both layout models agree and #167's
#     word-wide store into a sub-word field could not show.
#   * `standard_byte_array_elem.al` states in its own header that its element size was chosen so the
#     byte stride EQUALS `struct_words * 8`, "to isolate the WRITE and the PLACE from the stride" —
#     which is exactly the disagreement #170 was.
#   * `agg_arr_elem_arg.al` enumerates eight spellings of an aggregate array element as a call
#     argument, all with `{i64,i64}` elements: #260 (read) and #263 (write) needed `{u8,u8}`.
#   * Twelve `reject_*` fixtures cover a write to an immutable binding, every one of them naming the
#     BINDING; #298 and #304 needed the target to be a field or an element.
#
# So the corpus is not thin, it is UNEVEN, and "add more fixtures" does not fix uneven: the next
# fixture is as likely as the last to hold the same axis constant. This tool prints the axes a class
# must vary and names the cells nothing mentions.
#
# WHERE THE CORPUS ACTUALLY LIVES
# -------------------------------
# Not only in test/*.al. Twenty-one functions in scripts/e2e.sh GENERATE their programs with `printf`
# into the gate's scratch directory and never commit a fixture — #303's immutable-place coverage is
# entirely of that shape. A detector that reads only test/ calls those cells empty, which is the one
# failure mode worse than missing a gap: it sends a worker to write a fixture that already exists. So
# this tool materialises a working corpus first — the tracked fixtures plus one virtual file per
# inline-generating e2e function — and measures that.
#
# WHAT A FILLED CELL MEANS, EXACTLY
# --------------------------------
# That some tracked fixture MENTIONS the signal for that value — not that it asserts the behaviour.
# The tool counts files, not assertions, and it cannot tell a real exercise from a passing mention.
# It is an indicator of where to look. An EMPTY cell is the useful output: nothing in the corpus even
# mentions that combination, so either a fixture is missing or the language has no such form. Which
# of the two is recorded in scripts/axis.baseline, reviewed the way scripts/idiom.baseline is.
#
# Usage (no compiler needed):
#   bash scripts/axis_gate.sh                 # report the matrix over test/
#   bash scripts/axis_gate.sh --corpus <dir>  # report over another fixture directory (used by --self-test)
#   bash scripts/axis_gate.sh --self-test     # prove the detector fires and can be silenced
#   bash scripts/axis_gate.sh --emit-baseline # print the empty cells as baseline lines, to be reviewed
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1

CORPUS="$ROOT/test"
SELF_TEST=0
EMIT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --corpus) CORPUS="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --emit-baseline) EMIT=1; shift ;;
    *) echo "axis gate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
BASELINE="$ROOT/scripts/axis.baseline"

# ── THE TABLE ────────────────────────────────────────────────────────────────────────────
# One `class` line per family, then one `axis` line per axis:
#   class~<id>~<scope signal>~<human name>
#   axis~<id>~<axis name>~<value>=<signal>;<value>=<signal>;…
#   cross~<id>~<axis A>~<axis B>
#
# The `cross` lines are the point of the tool. A single axis is almost always "covered": some fixture
# somewhere names u8, some fixture somewhere writes a field. Every defect this repository actually
# shipped needed a COMBINATION — #167 was two-narrow AND a write, #263 was narrow AND an array element
# AND a write. So the one-dimensional rows below are context, and the crossed matrices are the finding.
# Note the separators: `~` between the fields of a line, `;` between the value=signal pairs. A signal
# may therefore use alternation `(a|b)` and anything else except `~` and `;`.
#
# A signal is one of three kinds:
#   <regex>        the fixture's TEXT matches it
#   path:<regex>   the fixture's PATH matches it — for what a naming convention encodes
#   e2e:<regex>    the fixture is REGISTERED in scripts/e2e.sh by a line matching it — for what the
#                  harness decides rather than the source: which backends run it, whether it is a
#                  reject. That distinction is not visible inside the .al file at all, and it is
#                  exactly the axis that let non-x86 store defects sit behind a green gate.
#
# `scope` selects the fixtures that belong to the class at all; a cell counts a fixture only when it
# matches BOTH the scope and the value signal.
#
# Keep every regex NARROW. A loose one reports a class as covered on the strength of an unrelated
# mention, and a falsely filled cell is worse than no tool: it says "looked at" about the exact place
# nobody looked. When in doubt, prefer a regex that under-reports; an empty cell gets reviewed, a
# filled one does not.
#
# The axes are not arbitrary. Each is an axis some landed defect had pinned:
#   field-layout/eightbyte  — #167, #170: two narrow fields sharing one machine word
#   field-layout/path       — #263: the same write through a struct-field array rather than a local
#   place-check/target      — #298, #304: the check follows the name but not the field or element
#   aggregate-byval/width   — #260, #263: `{u8,u8}` where every fixture used `{i64,i64}`
#   */backend               — the sweeps are conditional, so a form can be x86-only for a long time
TABLE=$(cat <<'TBL'
class~field-layout~:= *(@packed *)?struct~struct field layout
axis~field-layout~width~u8=: *u8\b;u16=: *u16\b;u32=: *u32\b;u64=: *u64\b;bool=: *bool\b
axis~field-layout~eightbyte~two-narrow=struct \{[^}]*: *u(8|16|32)\b[^}]*, *[a-z_]+ *: *u(8|16|32)\b;narrow-then-wide=struct \{[^}]*: *u(8|16|32)\b[^}]*, *[a-z_]+ *: *(u64|i64|usize)\b;wide-then-narrow=struct \{[^}]*: *(u64|i64|usize)\b[^}]*, *[a-z_]+ *: *u(8|16|32)\b
axis~field-layout~layout~default=:= *struct;packed=:= *@packed *struct
axis~field-layout~path~local=mut [a-z_]+ *(:|:=);through-field=\.[a-z_]+\.[a-z_]+;array-element=\][a-z_. ]*\.[a-z_]+;pointer-deref=deref\([a-z_]+\)\.;slice-element=\[[0-9]+\.\.
axis~field-layout~operation~read=(if|return|:=) *[a-z_]+\.[a-z_]+;write=[a-z_]+\.[a-z_]+ *= [^=]
axis~field-layout~backend~x86=e2e:^ *run ;wasm=e2e:^ *run_wat;a64=e2e:^ *run_a64;rv64=e2e:^ *run_rv64
axis~field-layout~verdict~accepted=e2e:^ *run ;rejected=e2e:^ *build_reject
cross~field-layout~eightbyte~operation
cross~field-layout~eightbyte~path
cross~field-layout~eightbyte~backend
cross~field-layout~path~operation
class~place-check~.~place write checks
axis~place-check~target~binding-name=^ *[a-z_]+ *= [^=];field=\.[a-z_]+ *= [^=];array-element=\[[0-9a-z_+ ]+\] *= [^=];element-field=\[[0-9a-z_+ ]+\]\.[a-z_]+ *= [^=];pointer-deref=deref\([a-z_]+\)[a-z_.]* *= [^=]
axis~place-check~check~immutability=immutab;assignment-type=type mismatch;unbound-name=unbound;arity=(arg(ument)? count|arity)
axis~place-check~verdict~accepted=e2e:^ *run ;rejected=path:/reject_
cross~place-check~target~check
cross~place-check~check~verdict
class~aggregate-byval~(fn *\([a-z_]+ *: *[A-Z]|-> *[A-Z][A-Za-z_]*)~aggregate by value
axis~aggregate-byval~width~narrow=struct \{[^}]*: *u(8|16|32)\b;wide=struct \{[^}]*: *(u64|i64|usize)\b
axis~aggregate-byval~direction~argument=fn *\([a-z_]+ *: *[A-Z];return=-> *[A-Z][A-Za-z_]*(\b| *\{)
axis~aggregate-byval~backend~x86=e2e:^ *run ;wasm=e2e:^ *run_wat;a64=e2e:^ *run_a64;rv64=e2e:^ *run_rv64;ffi=@abi\( *c *\)
cross~aggregate-byval~width~direction
cross~aggregate-byval~width~backend
TBL
)

test -d "$CORPUS" || { echo "axis gate: no fixture directory at $CORPUS" >&2; exit 2; }
CORPUS_IN="$CORPUS"
tracked=$(find "$CORPUS" -name '*.al' 2>/dev/null | wc -l | tr -d ' ')
test "$tracked" -gt 0 || { echo "axis gate: no *.al under $CORPUS" >&2; exit 2; }

# ── the walk ──────────────────────────────────────────────────────────────────────────────
# One `grep -lE` per pattern over the whole corpus, never per file: the naive nesting is a grep per
# (cell x fixture) and takes minutes on a thousand fixtures, which is long enough that nobody runs it.
declare -A CLASS_NAME
declare -A AXIS_VALUES
SETS="$(mktemp -d)"
trap 'rm -rf "$SETS"' EXIT
# Private to this run, never a fixed shared path: --self-test invokes this script recursively, and a
# shared scratch file would have the inner run overwrite the outer one's findings.
EMPTY_LIST="$SETS/empty"
: > "$EMPTY_LIST"
SCOPE_LIST=""
empty_cells=0
report=""

E2E="$ROOT/scripts/e2e.sh"

# Materialise the working corpus: the tracked fixtures (directory structure preserved — 23 basenames
# collide across subdirectories) plus one virtual file per e2e function that generates its programs
# inline. A virtual file holds the function's text verbatim, so a textual signal finds the generated
# source the same way it finds a committed one.
CORPUS_WORK="$SETS/corpus"
mkdir -p "$CORPUS_WORK/e2e_inline"
cp -a "$CORPUS/." "$CORPUS_WORK/" 2>/dev/null \
  || { echo "axis gate: could not materialise $CORPUS" >&2; exit 2; }
# scripts/e2e.sh is REQUIRED, not optional. A third of the table's signals are `e2e:` — which backends
# run a fixture, whether it is a reject — and those live nowhere else. Without the file every one of
# those cells reads EMPTY, and the report then names 31 gaps that are pure absence of the source. That
# is a silently wrong answer wearing the shape of a finding, and it would send someone to write
# fixtures for coverage that already exists. Refuse instead: a missing input is not a finding.
test -f "$E2E" || {
  echo "axis gate: scripts/e2e.sh not found at $E2E" >&2
  echo "  A third of the declared signals are 'e2e:' — which backends run a fixture, and whether it is" >&2
  echo "  a reject. That information exists ONLY in scripts/e2e.sh; it appears nowhere inside a .al" >&2
  echo "  file. Reporting without it would call every such cell empty and name gaps that are only the" >&2
  echo "  missing input. Restore the file, or point --corpus at a tree whose repository has it." >&2
  exit 2
}

inline=0
if [ -f "$E2E" ]; then
  awk -v out="$CORPUS_WORK/e2e_inline" '
    # The `##` block immediately above a function states what the generated programs assert; it is part
    # of the fixture for measurement purposes, so carry it into the virtual file.
    fn == "" && /^## / { doc = doc $0 "\n"; next }
    fn == "" && !/^## / { doc = "" }
    /^[a-z0-9_]+_test\(\) \{/ { fn = $1; sub(/\(\).*/, "", fn); buf = doc; doc = ""; next }
    fn != "" { buf = buf $0 "\n" }
    fn != "" && /^\}/ {
      if (buf ~ /printf/ || buf ~ /cat >/) { printf "%s", buf > (out "/" fn ".al"); close(out "/" fn ".al") }
      fn = ""
    }' "$E2E"
  inline=$(find "$CORPUS_WORK/e2e_inline" -name '*.al' | wc -l | tr -d ' ')
fi
fixtures=$((tracked + inline))
# Everything below measures the materialised corpus, never the input directory.
CORPUS="$CORPUS_WORK"

matches() { # <signal> -> newline-separated matching fixture paths, sorted
  case "$1" in
    path:*) # the fixture's own path
      find "$CORPUS" -name '*.al' 2>/dev/null | grep -E -- "${1#path:}" | sort ;;
    e2e:*) # how the harness runs the fixture: a tracked one is named by a registration line in
           # scripts/e2e.sh (field 2 is its stem); a virtual one carries its own invocation in its text.
      # Unreachable: the run refuses at startup when $E2E is missing. Kept as an assertion so a
      # future edit that moves the startup check cannot silently reintroduce the false-empty report.
      test -f "$E2E" || { echo "axis gate: internal error — e2e: signal resolved with no $E2E" >&2; exit 2; }
      { grep -rlE -- "${1#e2e:}" --include='*.al' "$CORPUS/e2e_inline" 2>/dev/null
        grep -hE -- "${1#e2e:}" "$E2E" 2>/dev/null \
        | awk '{ print $2 }' \
        | sed 's/[^A-Za-z0-9_.\/-]//g' \
        | while IFS= read -r stem; do
            [ -n "$stem" ] || continue
            f="$CORPUS/${stem}.al"
            test -f "$f" && printf '%s\n' "$f"
          done
      } | sort -u ;;
    *) grep -rlE -- "$1" --include='*.al' "$CORPUS" 2>/dev/null | sort ;;
  esac
}

while IFS= read -r line; do
  case "$line" in
    class~*)
      IFS='~' read -r _ cid scope cname <<<"$line"
      CLASS_NAME[$cid]="$cname"
      SCOPE_LIST="$(matches "$scope")"
      in_scope=$(printf '%s\n' "$SCOPE_LIST" | grep -c . )
      report+="
class ${cid} — ${cname} (${in_scope} fixtures in scope)
"
      ;;
    axis~*)
      IFS='~' read -r _ cid aname _rest <<<"$line"
      row="  ${aname}:"
      vals=""
      pairs="${line#axis~$cid~$aname~}"
      old_ifs="$IFS"; IFS=';'
      for pair in $pairs; do
        IFS="$old_ifs"
        val="${pair%%=*}"; re="${pair#*=}"
        vals="$vals $val"
        # a cell counts a fixture only when it is in the class scope AND matches the value pattern
        cell="$SETS/${cid}.${aname}.${val}"
        comm -12 <(printf '%s\n' "$SCOPE_LIST") <(matches "$re") | grep . > "$cell"
        n=$(grep -c . "$cell")
        if [ "$n" = 0 ]; then
          row+=" ${val}=EMPTY"
          empty_cells=$((empty_cells + 1))
          echo "${cid} ${aname} ${val}" >> "$EMPTY_LIST"
        else
          row+=" ${val}=${n}"
        fi
        IFS=';'
      done
      IFS="$old_ifs"
      AXIS_VALUES["${cid}.${aname}"]="$vals"
      report+="${row}
"
      ;;
    cross~*)
      IFS='~' read -r _ cid axa axb <<<"$line"
      va="${AXIS_VALUES[${cid}.${axa}]:-}"; vb="${AXIS_VALUES[${cid}.${axb}]:-}"
      if [ -z "$va" ] || [ -z "$vb" ]; then
        echo "axis gate: cross ${cid} ${axa}x${axb} names an axis that was never declared" >&2
        exit 2
      fi
      report+="  cross ${axa} x ${axb}:
"
      for a in $va; do
        crow="    ${a}:"
        for b in $vb; do
          n=$(comm -12 "$SETS/${cid}.${axa}.${a}" "$SETS/${cid}.${axb}.${b}" | grep -c . )
          if [ "$n" = 0 ]; then
            crow+=" ${b}=EMPTY"
            empty_cells=$((empty_cells + 1))
            echo "${cid} ${axa}x${axb} ${a}x${b}" >> "$EMPTY_LIST"
          else
            crow+=" ${b}=${n}"
          fi
        done
        report+="${crow}
"
      done
      ;;
  esac
done <<<"$TABLE"

echo "axis gate: fixtures=$fixtures (tracked=$tracked under ${CORPUS_IN}, inline-in-e2e=$inline)"
printf '%s' "$report"
echo "axis gate: empty cells=$empty_cells"

# ── the gate of the gate ─────────────────────────────────────────────────────────────────
# A detector that reports nothing is indistinguishable from complete coverage, so the detector must be
# shown to move. Plant a fixture into a cell this corpus leaves empty, prove that exact cell reports
# filled, remove it, prove the cell reports empty again. Asserting the NAMED cell rather than a total
# count matters: a count can move because an unrelated cell shifted, which would let a broken signal
# pass this test.
if [ "$SELF_TEST" = 1 ]; then
  echo "axis gate: self-test"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$SETS" "$tmp"' EXIT
  cp -a "$CORPUS/." "$tmp/" || { echo "axis gate: self-test could not copy the corpus" >&2; exit 1; }

  # The probed cell: field-layout, cross eightbyte x operation, wide-then-narrow x write. Both signals
  # are textual, so the planted fixture needs no e2e.sh registration to fill it.
  cell_value() { # -> the cell's printed value, e.g. "EMPTY" or "3"
    bash "$0" --corpus "$1" 2>/dev/null | awk '
      /^  cross eightbyte x operation:/ { inblock = 1; next }
      /^  cross / { inblock = 0 }
      inblock && /^    wide-then-narrow:/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^write=/) { sub(/^write=/, "", $i); print $i; exit }
      }'
  }

  before="$(cell_value "$tmp")"
  cat > "$tmp/axis_selftest_planted.al" <<'PLANT'
## planted by scripts/axis_gate.sh --self-test; removed again before the script exits.
Probe := struct { wide : u64, narrow : u8 }
main := fn() -> u64 {
  mut p := Probe(wide = 1, narrow = 2)
  p.narrow = 7
  42
}
PLANT
  planted="$(cell_value "$tmp")"
  rm -f "$tmp/axis_selftest_planted.al"
  restored="$(cell_value "$tmp")"

  ok=1
  test "$before" = "EMPTY"   || { echo "axis gate: SELF-TEST SETUP STALE — the probed cell reads '$before', not EMPTY." >&2
                                  echo "  A fixture has since filled wide-then-narrow x write. That is good news for the" >&2
                                  echo "  corpus; move the self-test to another empty cell from the report above." >&2; ok=0; }
  test "$planted" != "EMPTY" && test -n "$planted" \
                             || { echo "axis gate: SELF-TEST FAILED — a planted fixture left the cell reading '$planted'." >&2
                                  echo "  The detector cannot see a form it is supposed to detect; the report is not evidence." >&2; ok=0; }
  test "$restored" = "EMPTY" || { echo "axis gate: SELF-TEST FAILED — after removal the cell reads '$restored', not EMPTY." >&2
                                  echo "  The detector is reporting state that outlives the corpus it claims to measure." >&2; ok=0; }
  test "$ok" = 1 || exit 1
  echo "axis gate: self-test ok (wide-then-narrow x write: $before -> $planted -> $restored)"
fi

if [ "$EMIT" = 1 ]; then
  echo "# --- empty cells, unreviewed; each needs a reason before it belongs in the baseline ---"
  sort "$EMPTY_LIST"
  exit 0
fi

# ── the baseline ─────────────────────────────────────────────────────────────────────────────────
# Reviewed empty cells live in scripts/axis.baseline, one `<class> <axis> <value>` per line. A cell
# not listed there is NEW and worth a look; the tool still exits 0 — it reports, it does not gate.
if [ -f "$BASELINE" ]; then
  new=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    grep -Fxq -- "$c" "$BASELINE" 2>/dev/null || { echo "  NEW empty cell: $c"; new=$((new + 1)); }
  done < "$EMPTY_LIST"
  # And the other direction. A baseline line whose cell has since been FILLED is stale: the reason
  # recorded beside it no longer describes anything, and a stale reason is how a review record quietly
  # turns into folklore. Reporting it is what lets the file shrink as the gaps close.
  stale=0
  reviewed=0
  while IFS= read -r c; do
    case "$c" in ''|'#'*) continue ;; esac
    reviewed=$((reviewed + 1))
    grep -Fxq -- "$c" "$EMPTY_LIST" 2>/dev/null || { echo "  STALE baseline line, the cell is filled now: $c"; stale=$((stale + 1)); }
  done < "$BASELINE"
  echo "axis gate: reviewed baseline=$reviewed new=$new stale=$stale"
else
  echo "axis gate: no scripts/axis.baseline yet — every empty cell above is unreviewed"
fi
exit 0
