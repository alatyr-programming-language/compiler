# scripts/idiom/textual.awk — the three LEDGER rules. Line-level, because each of these is a
# property of a WRITTEN SITE, not of a function's vocabulary, and each earned its place by having
# already produced a defect in this repository. Output is TAB-separated:
#
#   STRIDE  <file> <count>            hand-rolled `<base> + <i> * <stride>` element addressing
#   DROPPED <file> <callee> <count>   a fallible write/flush whose result is discarded
#   CACHE   <file> <family> <cols>    a module-global memo cache's COLUMN SET
#   .       <detail line>             a located detail, printed in the report, never in the key
#
# Every row ends with a LOCATION field, `-` here because the key already names the file; the driver
# strips the last field of EVERY row before comparing, so the projection is uniform across rules.
#
# The KEY of every row is a file (plus a callee or a family) and a COUNT — never a line number.
# Counts are stable under unrelated edits; line numbers are not, and a baseline that goes red
# because something was inserted above is a baseline that gets deleted.
BEGIN { OFS = "\t"
  # The fallible surfaces: each returns the raw syscall result, so discarding it discards the
  # failure. `rt::write_file` loops to completion and reports its own status, and is listed for the
  # same reason — the STATUS is still droppable.
  FALLIBLE = "sb_flush|write_file|rt::write\\(|sys_write"
}

FNR == 1 {
  file = FILENAME
  nl = 0; delete L
  while ((getline ln < FILENAME) > 0) L[++nl] = ln
  close(FILENAME)
  NLINES[file] = nl
}

# ---- STRIDE ------------------------------------------------------------------------------------
# `deref(v).base + i * 16` and friends: an element address computed from a HAND-WRITTEN stride.
# names this as the danger for the layout switch — every such site hard-codes a byte layout
# the compiler is about to start choosing for itself, and the five it names ("five hand-rolled
# `size(T)`-strided arena containers") are only the ones somebody happened to list.
{
  s = decomment($0)
  if (s ~ /\.base[[:space:]]*\+[^)]*\*/) {
    STRIDE[file]++
    printf(".\tSTRIDE %s:%d  %s\n", file, FNR, trim(s))
  }
}

# ---- DROPPED -----------------------------------------------------------------------------------
# A fallible write/flush whose result nobody looks at. This is the `return 0`-after-flush shape,
# spelled as a property of the CALL rather than of the return: `rt::sb_flush` hands back the raw
# `write(2)` result, so binding it to a local that is never read again is precisely how a failed or
# short write became unreportable — twice, on five paths (the three cross emit surfaces, then the
# x86 GAS dump and `fmt`). "Never read again" is scoped to the enclosing TOP-LEVEL function: the
# scan runs forward to the next line that closes a top-level body (`^}`), not a fixed window.
{
  if (s ~ FALLIBLE && s !~ /fn[[:space:]]*\(/) {
    if (match(s, /^[[:space:]]*(mut[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:?=[^=]/, m)) {
      nm = m[2]
      used = 0
      for (i = FNR + 1; i <= nl; i++) {
        if (L[i] ~ /^\}/) break
        if (decomment(L[i]) ~ ("(^|[^A-Za-z0-9_])" nm "([^A-Za-z0-9_]|$)")) { used = 1; break }
      }
      if (!used) {
        callee = calleeof(s)
        DROPPED[file SUBSEP callee]++; DFILE[file SUBSEP callee] = file; DCALL[file SUBSEP callee] = callee
        printf(".\tDROPPED %s:%d  %s   (`%s` never read again in this function)\n", file, FNR, trim(s), nm)
      }
    }
  }
}

# ---- CACHE -------------------------------------------------------------------------------------
# A module-global memo cache is a family of parallel arrays, `mut _sdc_s`, `mut _sdc_n`, … — and
# what it is KEYED ON is exactly that column list. Getting the key wrong is not hypothetical here:
# `_sdc_*`/`_edc_*` were keyed on a `src` BASE and `LNI` on a decl COUNT, and 74 of 630 fixtures
# died rc 139 the first time a pass exercised them. No rule can tell a right key from a wrong one,
# so this one does the next best thing: it freezes the column set, so ADDING a column to one family
# and not to its twin becomes a line in a diff instead of a segfault six weeks later.
{
  if (match($0, /^[[:space:]]*mut[[:space:]]+(_[A-Za-z0-9]+)_([A-Za-z0-9]+)[[:space:]]*:[[:space:]]*\[/, m)) {
    fam = file SUBSEP m[1]
    CFILE[fam] = file; CFAM[fam] = m[1]
    CCOL[fam] = CCOL[fam] " " m[2]
  }
}

END {
  for (f in STRIDE)  print "STRIDE",  f, STRIDE[f], "-"
  for (k in DROPPED) print "DROPPED", DFILE[k], DCALL[k], DROPPED[k], "-"
  for (k in CCOL)    print "CACHE",   CFILE[k], CFAM[k], sortwords(CCOL[k]), "-"
  printf("files=%d lines=%d\n", length(NLINES), totlines()) > "/dev/stderr"
}

function totlines(   f, t) { for (f in NLINES) t += NLINES[f]; return t }
function decomment(x) { sub(/##.*/, "", x); return x }
function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
function calleeof(x,   mm) { return match(x, /([A-Za-z_][A-Za-z0-9_:]*)[[:space:]]*\(/, mm) ? mm[1] : "?" }
# The column ORDER in the source is an accident; the SET is the fact. Sort so a reordering of the
# declarations is not reported as a changed key.
function sortwords(x,   n, a, i, j, t, out) {
  n = split(x, a, " ")
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
  out = ""
  for (i = 1; i <= n; i++) out = (out == "") ? a[i] : out "," a[i]
  return out
}
