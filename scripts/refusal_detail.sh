#!/usr/bin/env bash
# refusal_detail.sh — name what the builder actually refused, by reading its own span.
#
# WHY. `alatyr ir` reports a refusal as `NotYet(<construct>, <file>:<line>:<col>)`. The construct is the
# NODE KIND — `expr Call`, `stmt Assign` — and the kind alone cannot drive a slice: 623 corpus rows refuse
# as "undefined/builtin callee" and dozens more as `expr Call`, and none of them says WHICH callee or WHICH
# assignment. Every slice choice this project has made from that table has been a guess, and §14, §15, §17
# and §18 of docs/ir-slice-3.md are four corrections that each began as one of those guesses.
#
# The refusal already carries the SPAN. The source text at that span names the callee, the field, the
# statement — everything the kind leaves out. This script reads it. It changes nothing: no compiler code, no
# emitted byte, no golden, no oracle. It reads `alatyr ir`'s committed output format and the source files.
#
#   scripts/refusal_detail.sh <ABSOLUTE compiler path> <path...>            # ranked table
#   scripts/refusal_detail.sh <ABSOLUTE compiler path> --list <needle> <path...>
#   scripts/refusal_detail.sh --from-file <ir-output> <srcroot>             # annotate existing output
#
# Output: one line per distinct refusal, most frequent first —
#   count  <construct>  <- `<source text at the span>`
# so the next slice is chosen by what blocks most, named.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

LIST=""
FROM=""
SRCROOT="."
CC=""
PATHS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list)     [ "$#" -ge 2 ] || { echo "refusal_detail: --list needs a substring" >&2; exit 2; }
                LIST="$2"; shift 2 ;;
    --from-file)[ "$#" -ge 2 ] || { echo "refusal_detail: --from-file needs a file" >&2; exit 2; }
                FROM="$2"; shift 2 ;;
    -*)         echo "refusal_detail: unknown flag $1" >&2; exit 2 ;;
    *)        if [ -z "$CC" ] && [ -z "$FROM" ]; then CC="$1"; else PATHS+=("$1"); fi; shift ;;
  esac
done

## ── the annotator: for each NotYet line, pull the source text at its span ─────────────────────
## A span is <file>:<line>:<col>. The text taken runs from the column to the end of the line, then is
## trimmed to the balanced head: enough to name `Al.align()` or `arena_over(bp, 65536)` without dragging
## the whole statement along. Balanced-by-count, not by parse — this is a report, and a wrong count here
## shows up as an over-long quote rather than a wrong verdict.
if [ -n "$FROM" ]; then
  IRIN="$FROM"; SRCROOT="${PATHS[0]:-.}"
else
  [ -n "$CC" ] || { echo "refusal_detail: needs an ABSOLUTE compiler path (or --from-file)" >&2; exit 2; }
  case "$CC" in /*) ;; *) echo "refusal_detail: compiler path must be ABSOLUTE" >&2; exit 2 ;; esac
  [ "${#PATHS[@]}" -gt 0 ] || { echo "refusal_detail: needs at least one source path" >&2; exit 2; }
  IRIN="$(mktemp)"; trap 'rm -f "$IRIN"' EXIT
  for p in "${PATHS[@]}"; do
    [ -f "$p" ] || continue
    ulimit -c 0 2>/dev/null || true
    "$CC" ir "$p" 2>/dev/null | grep '^fn .* NotYet(' >> "$IRIN" || true
  done
fi

grep -o 'NotYet([^)]*)' "$IRIN" \
| sed 's/^NotYet(//; s/)$//' \
| awk -F', ' -v root="$SRCROOT" -v list="$LIST" '
{
  kind = $1; sp = $2
  if (list != "" && index(tolower($0), tolower(list)) == 0) next
  ## file:line:col
  n = split(sp, a, ":")
  f = a[1]; ln = a[2] + 0; col = a[3] + 0
  path = (f ~ /^\//) ? f : (root "/" f)
  txt = ""
  if (ln > 0 && (getline line < path) > 0) {
    ## the file may hold several refusals: re-open each time rather than carry a cursor
    close(path)
    i = 0
    while ((getline line < path) > 0) { i++; if (i == ln) break }
    close(path)
    ## The span points at the CALLEE NAME, so `Al.align()` starts at `align()`: walk left over
    ## identifier-and-dot to recover the receiver, or a qualified callee reads as a bare name and the
    ## ranked table loses exactly the information that distinguishes `Al.align()` from `Pk.size()`.
    start = col
    while (start > 1) {
      pc = substr(line, start - 1, 1)
      if (pc ~ /[A-Za-z0-9_.]/) start--
      else break
    }
    txt = substr(line, start)
    ## trim to the balanced head: stop after the closing paren of the first call-shaped text; with no
    ## paren, keep a readable head of the statement rather than the single token the span names
    depth = 0; out = ""; seen_open = 0
    for (j = 1; j <= length(txt); j++) {
      ch = substr(txt, j, 1)
      if (ch == "(") { depth++; seen_open = 1 }
      if (ch == ")") depth--
      if (!seen_open && ch == " ") break
      out = out ch
      if (seen_open && depth == 0) break
    }
    if (!seen_open) txt = substr(txt, 1, 40)
    else txt = out
  }
  if (txt == "") txt = "(span unreadable)"
  key = kind "\t" txt
  cnt[key]++
}
END { for (k in cnt) printf "%6d  %s\n", cnt[k], k }
' | sort -rn | head -40
