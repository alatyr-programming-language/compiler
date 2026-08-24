# scripts/idiom/tokenize.awk — tokenize Alatyr source and segment TOP-LEVEL function bodies.
#
# Emits three record kinds, one per line, TAB-separated. Tabs, not spaces: the decision literals
# INCLUDE `" "` and `"\t"`, and awk's default field splitting eats a lone-space field outright —
# measured, `" "` silently vanished from every literal set until the separator changed, which is
# exactly the "verify that your measurement measures what you named it" trap in AGENTS.md.
#   F <fnid> <file> <line> <name> <ntok>    a top-level `[pub] NAME := fn(...) { ... }`
#   P <fnid> <normalized-parameter-type-list>
#   L <fnid> <decision-literal>             a string literal of 1..2 characters, inside that body
#
# WHY A TOKENIZER AND NOT grep. AGENTS.md records the exact trap: "a function-size scan whose
# pattern silently skipped every `pub` declaration (so a 2 971-line function read as 'already
# decomposed')". A line regex also cannot tell a `+` inside a string literal from an operator, nor
# a `##` comment from source. So this segments by BRACE DEPTH over a real token stream, and
# `idiom_gate.sh` cross-checks the function count it produces against an independent line-regex
# count — the tokenizer must find a strict SUPERSET (it also sees `@inline name := fn(`, which the
# regex cannot), and a function the regex finds and the tokenizer misses is a FAILURE. That check
# caught a real bug in this file: `assert` was in the keyword list, so `lib/base/assert.al`'s
# `assert := fn(...)` was invisible.
#
# A "decision literal" is a string literal of one or two characters after unescaping. That is the
# vocabulary of a hand-written TABLE — glyphs, whitespace, digits, punctuation. Longer literals are
# messages and mnemonics, which two unrelated functions share for unrelated reasons.
BEGIN { OFS = "\t"
  # Keywords stay verbatim so a body's shape survives normalization. Deliberately NOT here:
  # `panic`, `assert`, `embed`, `size`, `align` — those are PRELUDE IDENTIFIERS (D70/D79), and a
  # program may declare a function of that name (`lib/base/assert.al` does).
  split("if else while for loop match return break continue mut fn comptime unchecked checked \
         and or not true false pub type deref bitcast at when", a, " ")
  for (k in a) KW[a[k]] = 1
  split(":= == != <= >= -> => += -= *= /= %= &= |= ^= << >> ::", b, " ")
  for (k in b) OP2[b[k]] = 1
  infn = 0; depth = 0; paren = 0; pend = 0
}
FNR == 1 { file = FILENAME }
{ scan(strip($0)) }
END { if (infn) { printf("idiom: FATAL unterminated function body %s:%s %s\n", ffile, fline, fname) > "/dev/stderr"; exit 3 } }

# Drop a `##` comment, honouring string literals (a `##` inside a literal is not a comment).
function strip(line,    out, i, n, c, d) {
  out = ""; i = 1; n = length(line)
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\"") {
      out = out c; i++
      while (i <= n) {
        d = substr(line, i, 1)
        if (d == "\\") { out = out substr(line, i, 2); i += 2; continue }
        out = out d; i++
        if (d == "\"") break
      }
      continue
    }
    if (substr(line, i, 2) == "##") break
    out = out c; i++
  }
  return out
}

function scan(s,    i, n, c, d, two, t, lit) {
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (c == "\"") {
      lit = ""; i++
      while (i <= n) {
        d = substr(s, i, 1)
        if (d == "\\") { lit = lit substr(s, i, 2); i += 2; continue }
        if (d == "\"") { i++; break }
        lit = lit d; i++
      }
      push("S", lit); continue
    }
    if (c ~ /[0-9]/) {
      t = ""
      while (i <= n && substr(s, i, 1) ~ /[0-9A-Fa-fxXoObB_]/) { t = t substr(s, i, 1); i++ }
      push("N", t); continue
    }
    if (c ~ /[A-Za-z_]/) {
      t = ""
      while (i <= n && substr(s, i, 1) ~ /[A-Za-z0-9_]/) { t = t substr(s, i, 1); i++ }
      if (t in KW) push(t, t); else push("I", t)
      continue
    }
    two = substr(s, i, 2)
    if (two in OP2) { push(two, two); i += 2; continue }
    push(c, c); i++
  }
}

# Drop parameter NAMES and modes, keep the TYPE list: `(src : ptr(u8), ns : usize, nl : usize)`
# becomes `ptr(u8),usize,usize`. A signature is what a function TAKES, not what it calls its
# arguments — so two copies of one decision agree here even when their literal tables do not
# (`sema::assign_is_reassign` spelled its table `"+="`, `fmt::fmt_compound_op_str` spelled it `"+"`,
# and the signature is the only thing left that says they answer the same question).
function normsig(s,    i, c, cur, out, d, j, k, nseg, seg) {
  gsub(/[ \t]+/, "", s)
  d = 0; cur = ""; nseg = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(" || c == "[") d++
    else if (c == ")" || c == "]") d--
    if (c == "," && d == 0) { SEG[++nseg] = cur; cur = ""; continue }
    cur = cur c
  }
  if (cur != "") SEG[++nseg] = cur
  out = ""
  for (j = 1; j <= nseg; j++) {
    seg = SEG[j]
    k = index(seg, ":")
    if (k > 0) seg = substr(seg, k + 1)
    out = (out == "") ? seg : out "," seg
  }
  return (out == "") ? "-" : out
}

function shift(t, raw) {
  isid2 = isid1; isid1 = (raw ~ /^[A-Za-z_][A-Za-z0-9_]*$/)
  h2 = h1; h1 = t
  r2 = r1; r1 = raw
}

function push(t, raw) {
  if (infn) {
    if (t == "{") depth++
    else if (t == "}") {
      depth--
      if (depth == 0) { print "F", fnid, ffile, fline, fname, ntok; infn = 0; return }
    }
    ntok++
    if (t == "S") {
      ul = length(gensub(/\\./, "x", "g", raw))
      if (ul >= 1 && ul <= 2 && !((fnid SUBSEP raw) in LSEEN)) { LSEEN[fnid SUBSEP raw] = 1; print "L", fnid, raw }
    }
    return
  }
  if (t == "(") paren++
  else if (t == ")") paren--
  if (t == "fn" && h1 == ":=" && isid2) { pend = 1; pendname = r2; pendline = FNR; sigraw = ""; sigdepth = 0; insig = 0; sigdone = 0 }
  if (pend) {
    if (t == "(") {
      if (!insig) { if (sigdone) { shift(t, raw); return }   # the RETURN type's parens, not the signature's
                    insig = 1; sigdepth = 1; shift(t, raw); return }
      sigdepth++
    } else if (t == ")" && insig) { sigdepth--; if (sigdepth == 0) { insig = 0; sigdone = 1 } }
    if (insig) sigraw = sigraw " " raw
  }
  if (pend && t == "{" && paren == 0) {
    infn = 1; depth = 1; ntok = 0
    fname = pendname; ffile = file; fline = pendline
    fnid = file "#" pendline   # globally unique: `xargs` may split the file list across invocations,
                               # and a per-process counter would then collide two functions' ids
    print "P", fnid, normsig(sigraw)
    pend = 0
  } else if (pend && (t == ":=" || t == "}")) {
    pend = 0   # a `:= fn` with no body brace — a function TYPE, not a definition
  }
  shift(t, raw)
}
