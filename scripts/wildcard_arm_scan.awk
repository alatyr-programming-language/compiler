# scripts/wildcard_arm_scan.awk — the `_ =>` arm SCANNER for scripts/wildcard_arm_check.sh (issue #658).
#
# It is a TOKENIZER, not a grep, and that distinction is the whole reason this file exists. The #544
# census measured 727 real arms where `grep -c '_ =>'` answered 497, and the error runs BOTH ways:
# `src/parser.al` has 27 grep hits of which 3 are band comments quoting the token in prose, while
# twenty of `src/lower_ctx.al`'s arms were invisible to `grep -cE '^\s+_ =>'` because they sit inline
# in one-line accessors. A gate built on either number fires on a comment and misses a real arm.
#
# The lexical rules are `src/lexrt.al`'s, and only those: `#` runs to end of line (`##` is the same
# token class — Grammar §2.5 makes the doc distinction cosmetic), `"…"` and `'…'` take `\` as a
# two-byte escape, and there are no block comments. Everything else is whitespace-separated
# punctuation and `[A-Za-z0-9_]` runs.
#
# Output: one TAB-separated row per `_ =>` arm —
#   <path> <arm-line> <match-line> <class> <acknowledged> <resolved-type>
# where <class> is one of:
#   enum        the scrutinee resolves to a project-declared `enum` (a sibling arm's pattern names
#               one of its variants, by `E::V`, `E.V`, or a bare `V` unique to one declared enum).
#   literal     every sibling pattern is an integer/char/string literal — an integer or byte
#               scrutinee, where `_` is legitimate (the census found 4 tree-wide).
#   comptime    a `comptime match typeinfo(T)` kind dispatch, or a generic `T.(v)` variant pattern:
#               a closed set, but not one this scanner can name, so it is exempt and REPORTED.
#   none        no sibling arm at all (`match x { _ => … }`) — nothing to resolve against, so it
#               counts, and the acknowledgement marker is the way out.
#
# `acknowledged` is 1 when a `wildcard-ok:` comment with a non-empty reason sits on the arm's own
# line or on the line immediately above it. The marker lives where the arm lives on purpose: the
# #649 lesson is that a rule kept anywhere else is a rule people route around.
function isalnum_(c) { return c ~ /^[A-Za-z0-9_]$/ }
function isnum_(t)   { return t ~ /^[0-9]/ }

FNR == 1 { instr = 0; inchr = 0; depth = 0; paren = 0; sp = 0; pend = 0; pendct = 0
           t1 = ""; t2 = ""; t3 = ""; esp = 0; armstart = 0; patn = 0 }
{
  line = $0; L = length(line); i = 1
  while (i <= L) {
    c = substr(line, i, 1)
    if (instr) { if (c == "\\") { i += 2; continue }; if (c == "\"") instr = 0; i++; continue }
    if (inchr) { if (c == "\\") { i += 2; continue }; if (c == "'")  inchr = 0; i++; continue }
    if (c == "#") {
      # A comment. The ONE thing read out of comment text is the acknowledgement marker, and it
      # needs a non-empty reason after the colon: `## wildcard-ok:` alone acknowledges nothing.
      if (substr(line, i) ~ /wildcard-ok:[ \t]*[^ \t]/) ack[FNR] = 1
      break
    }
    if (c == "\"") { instr = 1; i++; tok("\"LIT\"", FNR); continue }
    if (c == "'")  { inchr = 1; i++; tok("\"LIT\"", FNR); continue }
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (isalnum_(c)) { j = i; while (j <= L && isalnum_(substr(line, j, 1))) j++
                       tok(substr(line, i, j - i), FNR); i = j; continue }
    two = substr(line, i, 2)
    if (two == "=>" || two == "::" || two == "->" || two == ":=" || two == "..") {
      tok(two, FNR); i += 2; continue
    }
    tok(c, FNR); i++
  }
}

function tok(t, ln,   k, p1, p2, p3) {
  p1 = t1; p2 = t2; p3 = t3

  if (t == "(" || t == "[") paren++
  else if (t == ")" || t == "]") paren--

  if (t == "{") {
    depth++
    if (pend && paren == 0) {                       # the match's arm block opens here
      sp++; sdep[sp] = depth; sline[sp] = pline; sct[sp] = pendct
      nw[sp] = 0; nreal[sp] = 0; nlit[sp] = 0; cands[sp] = ""
      armstart = 1; patn = 0; pend = 0
    } else if (p1 == "enum" && p2 == ":=" && p3 != "") {
      enums[p3] = 1; esp = depth; ename = p3; vstart = 1   # an enum DECLARATION block
    }
    shift(t); return
  }
  if (t == "}") {
    if (sp > 0 && depth == sdep[sp]) {              # the match's arm block closes here
      emit(sp)
      sp--; depth--
      armstart = (sp > 0 && depth == sdep[sp]) ? 1 : 0
      patn = 0
      shift(t); return
    }
    if (esp > 0 && depth == esp) esp = 0
    depth--
    if (sp > 0 && depth == sdep[sp]) { armstart = 1; patn = 0 }   # an arm BODY closed
    shift(t); return
  }

  # --- enum variant names, collected from the declaration itself -----------------------------
  if (esp > 0 && depth == esp && paren == 0) {
    if (t == ",") vstart = 1
    else if (vstart && t ~ /^[A-Za-z_]/) { vowner[t] = (t in vowner && vowner[t] != ename) ? "?" : ename
                                           vstart = 0 }
    else vstart = 0
  }

  if (t == "match" && p1 != "." && p1 != "::") {
    pend = 1; pline = ln; pendct = (p1 == "comptime") ? 1 : 0
    shift(t); return
  }

  # --- inside a match's arm list -------------------------------------------------------------
  if (sp > 0 && depth == sdep[sp] && paren == 0) {
    if (t == ";" || t == ",") { armstart = 1; patn = 0; shift(t); return }
    if (t == "=>") {
      if (patn == 1 && pat[1] == "_") {
        nw[sp]++; wln[sp, nw[sp]] = patline; wack[sp, nw[sp]] = ((patline in ack) ? 1 : ((patline - 1) in ack) ? 1 : 0)
      } else if (patn > 0) {
        nreal[sp]++
        if (isnum_(pat[1]) || pat[1] == "\"LIT\"" || pat[1] == "-") nlit[sp]++
        for (k = 1; k <= patn; k++) {
          if (k < patn && (pat[k + 1] == "::" || pat[k + 1] == ".") && pat[k] ~ /^[A-Za-z_]/)
            cands[sp] = cands[sp] " " pat[k]
          if (pat[k] ~ /^[A-Za-z_]/ && (k == 1 || (pat[k - 1] != "::" && pat[k - 1] != ".")))
            heads[sp] = heads[sp] " " pat[k]
        }
      }
      armstart = 0; patn = 0; shift(t); return
    }
    if (armstart) { if (patn == 0) patline = ln; patn++; pat[patn] = t }
  }
  shift(t)
}

function shift(t) { t3 = t2; t2 = t1; t1 = t }

function emit(s,   k) {
  if (nw[s] == 0) { cands[s] = ""; heads[s] = ""; return }
  nrec++
  rf[nrec] = FILENAME; rml[nrec] = sline[s]; rct[nrec] = sct[s]
  rc_[nrec] = cands[s]; rh[nrec] = heads[s]; rn[nrec] = nreal[s]; rl[nrec] = nlit[s]
  rw[nrec] = nw[s]
  for (k = 1; k <= nw[s]; k++) { rwl[nrec, k] = wln[s, k]; rwa[nrec, k] = wack[s, k] }
  cands[s] = ""; heads[s] = ""
}

END {
  for (r = 1; r <= nrec; r++) {
    ty = ""
    n = split(rc_[r], cv, " ")
    for (k = 1; k <= n; k++) if (cv[k] in enums) { ty = cv[k]; break }
    if (ty == "") {
      n = split(rh[r], hv, " ")
      for (k = 1; k <= n; k++)
        if (hv[k] in vowner && vowner[hv[k]] != "?" && vowner[hv[k]] in enums) { ty = vowner[hv[k]]; break }
    }
    if (ty != "")            cls = "enum"
    else if (rn[r] == 0)     cls = "none"
    else if (rl[r] == rn[r]) cls = "literal"
    else                     cls = "comptime"
    for (k = 1; k <= rw[r]; k++)
      printf "%s\t%d\t%d\t%s\t%d\t%s\n", rf[r], rwl[r, k], rml[r], cls, rwa[r, k], (ty == "" ? "-" : ty)
  }
}
