# scripts/idiom/pairs.awk — the two GENERAL rules, over tokenize.awk's records.
#
# RULE `TABLE` — N functions that compare against the SAME short-literal table.
#   Two functions sharing at least LK decision literals, counting only literals that occur in at
#   most LMAXF functions repo-wide. The cutoff is the whole trick: `" "` and `"\n"` appear in
#   hundreds of functions and mean nothing, while `"%"` next to `"^"` next to `":="` is a table.
#
# RULE `SCAN` — N functions that take the SAME INPUT and disagree about it.
#   An IDENTICAL normalized parameter signature plus at least SK shared decision literals. What two
#   copies of one decision share when they share nothing else is the QUESTION they answer, and the
#   signature is where that survives: `(ptr(u8), usize, usize)` is "look at the source text at a
#   name span". Measured (see the END block for the postings): before the `=`-fold below,
#   `sema::assign_is_reassign` scored ZERO against both `fmt` copies under TABLE's cutoff, and 3
#   under SCAN's looser one — enough to matter, not enough at SK=4, which is why the fold and not
#   this rule is what finally reaches it. SCAN earns its keep on the annotation-span and
#   range-bound triples instead.
#
# Output, one line per FUNCTION PAIR (the pair, not the cluster, is the unit: adding a copy adds
# pairs and must FAIL, removing a copy only makes baseline pairs stale):
#   <RULE> <fileA> <nameA> <fileB> <nameB> <nshared> <signature> <lineA:lineB>
# The LAST field is the location, and the driver strips it before comparing against the baseline —
# a line number churns on every edit above it, and a baseline that goes red for an unrelated
# insertion is a baseline that gets deleted. Everything before it IS the key, the shared-literal
# count included: if a duplicated table gains a glyph in one copy and not the other, that is the
# ledger's exact bug and the gate should say so.
BEGIN {
  if (LK == "")    LK = 4
  if (LMAXF == "") LMAXF = 20
  if (SK == "")    SK = 4
  if (SMAXF == "") SMAXF = 40
  FS = "\t"; OFS = "\t"
}
$1 == "F" { FILE[$2] = $3; LINE[$2] = $4; NAME[$2] = $5; nfn++; next }
$1 == "P" { SIG[$2] = $3; next }
$1 == "L" {
  lit = fold($3)
  nlit++
  if (($2 SUBSEP lit) in SEEN) next          # folding can collapse two of a function's literals
  SEEN[$2 SUBSEP lit] = 1
  POST[lit] = POST[lit] " " $2; NP[lit]++
  next
}
# FOLD a trailing `=` off an operator glyph. `"+="` and `"+"` are two SPELLINGS OF ONE TABLE ENTRY:
# in this language `x += e` desugars to `Assign(x, Bin(+, x, e))`, so a function listing `"+="` and
# a function listing `"+"` are listing the same operator. Without this fold the detector misses the
# single most expensive duplicate in the project's ledger — `sema::assign_is_reassign` spelled its
# table `"+=" "-=" "*=" "/="`, giving those four literals a repo-wide posting of ONE each, so they
# contributed nothing to any pair and the copy that REJECTED A VALID PROGRAM was invisible.
function fold(l) { return (l ~ /^[-+*\/%&|^<>!:=]=$/) ? substr(l, 1, 1) : l }
END {
  # TWO cutoffs, because the two rules carry different amounts of other evidence. TABLE has
  # nothing but the literals, so it may only use RARE ones (<= LMAXF functions). SCAN additionally
  # demands an identical parameter signature, so it can afford a looser literal cutoff
  # (<= SMAXF) — and it has to: measured on the pre-fix tree, EVERY literal
  # `sema::assign_is_reassign` shares with `fmt::fmt_local_is_reassign` is either unique to it
  # (`"+="` `"-="` `"*="` `"/="`, posting 1) or common (`"\n"` 185, `"\t"` 91, `"\r"` 70, `"="` 38),
  # so at LMAXF=20 the pair scores ZERO and the copy that caused a real reject is invisible.
  for (lit in POST) {
    if (NP[lit] < 2) continue
    n = split(POST[lit], g, " ")
    if (NP[lit] <= LMAXF) { keptT++; ncmp += n * (n - 1) / 2
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) C[pk(g[i], g[j])]++ }
    if (NP[lit] <= SMAXF) { keptS++; ncmp += n * (n - 1) / 2
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (SIG[g[i]] == SIG[g[j]]) S[pk(g[i], g[j])]++ }
  }
  for (key in C) if (C[key] >= LK) { split(key, ab, SUBSEP); emit("TABLE", ab[1], ab[2], C[key], "") }
  for (key in S) {
    split(key, ab, SUBSEP)
    x = ab[1]; y = ab[2]
    if (C[key] >= LK) continue                      # already reported, more strongly, as TABLE
    if (S[key] >= SK && SIG[x] != "-") emit("SCAN", x, y, S[key], SIG[x])
  }
  printf("functions=%d literal-records=%d distinct-literals=%d table-literals=%d scan-literals=%d pair-comparisons=%d\n",
         nfn, nlit, length(NP), keptT, keptS, ncmp) > "/dev/stderr"
}
# The fnid is `file#line`, a STRING — compare as one (a numeric compare would make every id 0).
function pk(a, b) { return (a < b) ? a SUBSEP b : b SUBSEP a }
function emit(rule, x, y, n, sig,   ax, ay) {
  if (FILE[x] " " NAME[x] < FILE[y] " " NAME[y]) { ax = x; ay = y } else { ax = y; ay = x }
  print rule, FILE[ax], NAME[ax], FILE[ay], NAME[ay], n, (sig == "" ? "-" : sig), LINE[ax] ":" LINE[ay]
}
