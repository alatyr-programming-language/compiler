# scripts/strict_forms_scan.awk — the LEXICAL scanner for scripts/strict_forms_check.sh (issue #691).
#
# A TOKENIZER, not a grep, for the reason `scripts/wildcard_arm_scan.awk` gives: a grep fires on a
# comment that quotes a form and misses a form split across lines, and a gate that does either earns
# a reputation for being wrong and gets routed around. The lexical rules are `src/lexrt.al`'s and the
# ones `wildcard_arm_scan.awk` already uses: `#` runs to end of line (`##` is the same token class),
# `"…"` and `'…'` take `\` as a two-byte escape, there are no block comments, and everything else is
# `[A-Za-z0-9_]` runs and punctuation. The multi-byte operators this file needs are added to that
# set (`==`, `!=`, `<=`, `>=`) — without them `a == 0` would be three tokens `=`, `=`, `0` and the
# comparison shapes below could not be told from an assignment.
#
# Output: one TAB-separated row per occurrence of a STRICT FORM —
#   <path> <line> <rule> <acknowledged> <form>
# where <rule> is one of (the catalogue, with the reasons, is
# `.agents/skills/alatyr-lane/strict_forms.md`):
#
#   unchecked      an `unchecked` escape (Memory §4.5 grant). The ONE `unchecked` that is not a row
#                  of its own is the one whose operand is a `null` form below: the language requires
#                  it to spell a null test explicitly, and that line is already a `null` row with its
#                  own marker, so marking it twice would add no information.
#   null           a pointer NULL SENTINEL spelled explicitly: a null FABRICATION
#                  `bitcast(ptr(T), 0)`, or a null TEST `bitcast(usize|u64, e) ==|!=|> 0` in either
#                  operand order. The IMPLICIT spelling (`p == 0` with `p : ptr(T)`) is invisible to a
#                  tokenizer — it needs the operand's type — and is counted by the compiler instead
#                  (`strict_forms_check.sh --typed`, over the #529 census channel).
#   kind-literal   a KIND compared with, or computed from, an integer literal: a name or field
#                  `kind`, `tag`, `prov`, `flags`, `*_kind`, `*_tag` (or a call `*_kind(…)`) as one
#                  operand of `==` `!=` `<` `>` `<=` `>=` `+` `-` `&` `|`, the other being an integer
#                  literal; and a `match` over such a name whose arm pattern is an integer literal.
#   try-inline     the VALUE of a `?` used inside a larger expression — `?` followed on its own line
#                  by anything but `}` or `;` (`f()?.x`, `g(f()?)`, `S(a = f()?)`, `f()? + 1`). The
#                  statement form `f()?` and the binding `x := f()?` are not rows.
#
# <acknowledged> is 1 when a `<rule>-ok:` comment with a non-empty reason sits on the row's own line
# or on the line immediately above it. The marker lives where the form lives, for #649's reason: a
# rule kept anywhere else is a rule people route around.
function isalnum_(c) { return c ~ /^[A-Za-z0-9_]$/ }
function isint_(t)   { return t ~ /^[0-9]/ }
function iskind_(t)  { return t ~ /^(kind|tag|prov|flags)$/ || t ~ /_(kind|tag)$/ }
function iscmp_(t)   { return t == "==" || t == "!=" || t == "<" || t == ">" || t == "<=" || t == ">=" }
function iskop_(t)   { return iscmp_(t) || t == "+" || t == "-" || t == "&" || t == "|" }

FNR == 1 { if (NR > 1) analyse(prevfile); reset() ; prevfile = FILENAME }
{
  line = $0; L = length(line); i = 1
  while (i <= L) {
    c = substr(line, i, 1)
    if (instr) { if (c == "\\") { i += 2; continue }; if (c == "\"") instr = 0; i++; continue }
    if (inchr) { if (c == "\\") { i += 2; continue }; if (c == "'")  inchr = 0; i++; continue }
    if (c == "#") {
      # A comment. The ONE thing read out of comment text is an acknowledgement marker, and it needs
      # a non-empty reason after the colon: `## unchecked-ok:` alone acknowledges nothing.
      rest = substr(line, i)
      if (rest ~ /unchecked-ok:[ \t]*[^ \t]/)    ack["unchecked", FNR] = 1
      if (rest ~ /null-ok:[ \t]*[^ \t]/)         ack["null", FNR] = 1
      if (rest ~ /kind-literal-ok:[ \t]*[^ \t]/) ack["kind-literal", FNR] = 1
      if (rest ~ /try-inline-ok:[ \t]*[^ \t]/)   ack["try-inline", FNR] = 1
      break
    }
    if (c == "\"") { instr = 1; i++; put("\"LIT\"", FNR); continue }
    if (c == "'")  { inchr = 1; i++; put("\"LIT\"", FNR); continue }
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (isalnum_(c)) { j = i; while (j <= L && isalnum_(substr(line, j, 1))) j++
                       put(substr(line, i, j - i), FNR); i = j; continue }
    two = substr(line, i, 2)
    if (two == "=>" || two == "::" || two == "->" || two == ":=" || two == ".." ||
        two == "==" || two == "!=" || two == "<=" || two == ">=") { put(two, FNR); i += 2; continue }
    put(c, FNR); i++
  }
}
END { if (NR > 0) analyse(prevfile) }

function reset(  k) { n = 0; instr = 0; inchr = 0; split("", T); split("", LN); split("", ack); split("", nullop) }
function put(t, ln) { n++; T[n] = t; LN[n] = ln }

## The index of the token closing the bracket opened at `k` (T[k] is `(` or `[`), or 0.
function close_(k,   d, m) {
  d = 0
  for (m = k; m <= n; m++) {
    if (T[m] == "(" || T[m] == "[") d++
    else if (T[m] == ")" || T[m] == "]") { d--; if (d == 0) return m }
  }
  return 0
}
## The index of the first depth-1 `,` inside the bracket opened at `k`, or 0.
function comma_(k, e,   d, m) {
  d = 0
  for (m = k; m <= e; m++) {
    if (T[m] == "(" || T[m] == "[") d++
    else if (T[m] == ")" || T[m] == "]") d--
    else if (T[m] == "," && d == 1) return m
  }
  return 0
}
## The index of the token that OPENS the bracket closed at `k` (T[k] is `)` or `]`), or 0.
function open_(k,   d, m) {
  d = 0
  for (m = k; m >= 1; m--) {
    if (T[m] == ")" || T[m] == "]") d++
    else if (T[m] == "(" || T[m] == "[") { d--; if (d == 0) return m }
  }
  return 0
}

function row(ln, rule, form,   a) {
  a = ((rule, ln) in ack || (rule, ln - 1) in ack) ? 1 : 0
  printf "%s\t%d\t%s\t%d\t%s\n", FNAME, ln, rule, a, form
}

function analyse(f,   k, e, cm, s, q, b, lhs, d, nl, t, pv, st) {
  FNAME = f
  ## Pass 1 — the explicit NULL forms, so pass 2 can tell which `unchecked` is spelling one.
  for (k = 1; k <= n; k++) {
    if (T[k] != "bitcast" || T[k + 1] != "(" || T[k - 1] == "." || T[k - 1] == "::") continue
    e = close_(k + 1); if (e == 0) continue
    cm = comma_(k + 1, e); if (cm == 0) continue
    s = k; if (T[k - 1] == "unchecked") s = k - 1
    if (T[k + 2] == "ptr" && cm == e - 2 && T[e - 1] == "0") {
      row(LN[k], "null", "bitcast(ptr(..), 0)"); nullop[k] = 1; continue
    }
    if ((T[k + 2] == "usize" || T[k + 2] == "u64") && cm == k + 3) {
      q = T[e + 1]
      if ((q == "==" || q == "!=" || q == ">") && T[e + 2] == "0" && T[e + 3] != "." && T[e + 3] != "(") {
        row(LN[k], "null", "bitcast(" T[k + 2] ", ..) " q " 0"); nullop[k] = 1; continue
      }
      b = s - 1
      if ((T[b] == "==" || T[b] == "!=" || T[b] == "<") && T[b - 1] == "0" && T[b - 2] != "." ) {
        row(LN[k], "null", "0 " T[b] " bitcast(" T[k + 2] ", ..)"); nullop[k] = 1; continue
      }
    }
  }
  for (k = 1; k <= n; k++) {
    ## unchecked — every escape, except one that spells a null form (already a `null` row).
    if (T[k] == "unchecked" && T[k - 1] != "." && T[k - 1] != "::") {
      if (!((k + 1) in nullop)) row(LN[k], "unchecked", "unchecked " T[k + 1])
      continue
    }
    ## kind-literal, the operand-on-the-left shape: `x.kind == 3`, `tag + 128`, `expr_kind(e) != 0`.
    if (iskind_(T[k]) && T[k - 1] != "::") {
      e = k
      if (T[k + 1] == "(") { e = close_(k + 1); if (e == 0) continue }
      if (T[e + 1] == ":" || T[e + 1] == ":=") continue          # a declaration, not a use
      if (iskop_(T[e + 1]) && isint_(T[e + 2])) { row(LN[k], "kind-literal", T[k] " " T[e + 1] " " T[e + 2]); continue }
      if (iskop_(T[e + 1]) && T[e + 2] == "-" && isint_(T[e + 3])) { row(LN[k], "kind-literal", T[k] " " T[e + 1] " -" T[e + 3]); continue }
    }
    ## kind-literal, the literal-on-the-left shape: `3 == t.kind`.
    if (isint_(T[k]) && iscmp_(T[k + 1])) {
      e = k + 2; while (e + 2 <= n && (T[e + 1] == "." ) && T[e + 2] ~ /^[A-Za-z_]/) e += 2
      if (iskind_(T[e]) && T[e + 1] != "(" && T[e + 1] != ".") { row(LN[k], "kind-literal", T[k] " " T[k + 1] " " T[e]); continue }
    }
    ## kind-literal, the `match` shape: `match t.kind { 3 => … }` — one row per literal arm.
    if (T[k] == "match" && T[k - 1] != "." && T[k - 1] != "::") {
      d = 0; lhs = ""
      for (e = k + 1; e <= n; e++) {
        if (T[e] == "(" || T[e] == "[") d++
        else if (T[e] == ")" || T[e] == "]") d--
        else if (T[e] == "{" && d == 0) break
        if (T[e] ~ /^[A-Za-z_]/) lhs = T[e]
        else if (T[e] == ")") { b = open_(e); if (b > 1 && T[b - 1] ~ /^[A-Za-z_]/) lhs = T[b - 1] }
      }
      if (e > n || !iskind_(lhs)) continue
      d = 0; pv = ""
      for (q = e; q <= n; q++) {
        t = T[q]
        if (t == "{" || t == "(" || t == "[") { d++; if (d == 1) { pv = "{"; continue } }
        else if (t == "}" || t == ")" || t == "]") { d--; if (d == 0) break; if (d == 1) { pv = "}"; continue } }
        if (d != 1) continue
        st = (pv == "{" || pv == ";" || pv == "," || pv == "}" || pv == "|" || LN[q] != LN[q - 1])
        if (st && (isint_(t) || (t == "-" && isint_(T[q + 1])))) row(LN[q], "kind-literal", "match " lhs " { " t " => }")
        pv = t
      }
      continue
    }
    ## try-inline — a `?` whose value is used: anything but `}`/`;` after it on its own line.
    if (T[k] == "?" && (T[k - 1] == ")" || T[k - 1] ~ /^[A-Za-z0-9_]/)) {
      nl = (k == n || LN[k + 1] != LN[k])
      if (!nl && T[k + 1] != "}" && T[k + 1] != ";") row(LN[k], "try-inline", "?" T[k + 1])
    }
  }
}
