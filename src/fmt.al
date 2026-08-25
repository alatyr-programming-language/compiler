## selfhost::fmt (tooling parity): `alatyr fmt`, a canonical source pretty-printer.
##
## A THIRD consumer of the same parsed `Decl`/`Stmt`/`Expr` model (alongside lower + the backends):
## it walks the AST and re-emits CANONICAL Alatyr source. Scope (v1, the common language core): a
## value/const decl and a `fn` decl (params, `-> R`, statement body), the statement forms
## `name := / = e`, `return e`, `e` (expr-statement), `if`/`while`, `p.f = e`; and expressions over
## literals (`Num`/`BoolLit`/`StrLit`), names (`Var`), `Bin` (with `op_symbol`), calls, field/index
## access, `deref`/`ptr`, and a value-`if`. `:=` vs `=` is RECONSTRUCTED (the parser erases the token
## into a bare `Assign`) by a value-returning "seen a prior Assign of this name?" scan — the FIRST
## binding of a name in a fn body prints `:=`, a later one prints `=`; this canonical rule makes the
## output IDEMPOTENT (`fmt(fmt(x)) == fmt(x)`). Anything outside the core (struct/enum decls, `match`,
## aggregate literals, comptime forms) is FAIL-LOUD (`panic`) — never a silently-wrong reformat.
##
## ADDITIVE: nothing in the self-build invokes `emit_fmt_program` (the self-build uses `build`, not
## `fmt`), so the x86_64 GAS the tree emits for itself is byte-identical and the TOOL-1 fixpoint
## (seed==Stage1==Stage2) is unaffected — like `wat.al`/`aarch64.al`/`riscv64.al`.
(Arg, Arm, Bind, Decl, Expr, FieldDecl, LabelSpan, Param, Stmt, local_type_span) := ast
local_is_mut := ast::local_is_mut
## Grammar §130 line 287 / OP-2 — the compound-assignment glyph the source wrote after a place's name
## span, or "" (see `ast.al`). The ONE table of the eight operators, shared with `sema`; fmt used to
## carry two private copies of it, one listing five glyphs and one listing four.
compound_assign_op_at := ast::compound_assign_op_at
## The no-initializer local form `name : T` (source metadata — `Stmt.Assign` carries a placeholder
## value for it, so without this probe fmt re-emits `name : T = 0`, a different program).
local_is_uninit := ast::local_is_uninit
## FN-6 expression-callee site set (see `ast.al`): the only thing that tells a call through an
## EXPRESSION callee apart from a genuine call to the borrowed name.
ecallee_is := ast::ecallee_is
(bnd_ns, bnd_nl, bnd_next) := ast
fld_p := ast::fld_p
param_p := ast::param_p
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
stmt_label_span := ast::stmt_label_span
expr_label_span := ast::expr_label_span
(push_str, push_int) := rt

## A typed pointer to a Decl node at absolute handle `h` (per-module `decl_at`, as in the backends).
decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }

## A typed pointer to an AST node at arena OFFSET `h` (Stmt/Arg/Param handles are offsets; `Expr`
## children carried as `ptr(Expr)` are absolute and deref directly).
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## Is the source range `[from, to)` entirely whitespace (space / tab / newline / CR)? Used to decide
## whether a `##` comment sits DIRECTLY above a declaration (only blank space between).
gap_is_blank := fn(src : ptr(u8), from : usize, to : usize) -> bool {
  mut i := from
  while i < to {
    c := str_at((src + i), 1)
    if c != " " and c != "\t" and c != "\n" and c != "\r" { return false }
    i += 1
  }
  return true
}

## The RAW byte length of a string literal's inner content, scanning `src` from `inner_start` (the byte
## just after the opening `"`) up to the matching close `"`, honoring `\"` (a backslash escapes the next
## byte so an escaped quote does not close). Lets fmt render the VERBATIM source of a literal whose stored
## `StrLit` length is the DECODED count (`raw - escapes`) — otherwise an escaped literal loses bytes.
str_inner_raw_len := fn(src : ptr(u8), inner_start : usize) -> usize {
  mut i := inner_start
  mut scanning := true
  while scanning {
    b := bytes(str_at((src + i), 1))[0]
    if b == 34 or b == 0 { scanning = false }        ## closing '"' (34) or EOF backstop
    else if b == 92 { i += 2 }                       ## '\' escapes the next byte
    else { i += 1 }
  }
  i - inner_start
}

## Scan source `[0, len)` for `## …` LINE comments and push each as a (start, end) pair into `out`
## (end = the newline offset, so the text is `[start, end)`). String literals are skipped so a `##`
## inside `"…"` is not mistaken for a comment. Comments come out in source order.
pub scan_comments := fn(src : ptr(u8), len : usize, out : ptr(rt::Vec)) {
  mut i := 0
  while i < len {
    c := str_at((src + i), 1)
    if c == "\"" {
      i += 1
      mut instr := true
      while i < len and instr {
        d := str_at((src + i), 1)
        if d == "\\" { i = i + 2 } else if d == "\"" { instr = false ; i = i + 1 } else { i = i + 1 }
      }
    } else if c == "#" and str_at((src + i + 1), 1) == "#" {
      mut j := i
      while j < len and str_at((src + j), 1) != "\n" { j = j + 1 }
      rt::vec_push(deref(out), i)
      rt::vec_push(deref(out), j)
      i = j
    } else {
      i += 1
    }
  }
}

## Emit the contiguous block of `##` comments sitting DIRECTLY above `name_start` (only blank space
## between each comment and the next, and between the last comment and the decl). Preserves top-level
## doc comments; a comment inside a previous decl's body is separated from `name_start` by that body's
## `}` (non-blank), so it is NOT collected — never mis-placed. Idempotent: re-scanning the emitted
## `## …\n<decl>` re-attaches the same block.
emit_leading_comments := fn(src : ptr(u8), comments : ptr(rt::Vec), name_start : usize, in out sb : rt::StrBuf) {
  n := rt::vec_len(deref(comments)) / 2
  ## L = index of the comment directly above name_start (blank gap, nothing between), else none.
  mut lastc := 0
  mut have := false
  mut i := 0
  while i < n {
    ce := rt::vec_get(deref(comments), i * 2 + 1)
    if ce <= name_start and gap_is_blank(src, ce, name_start) { lastc = i ; have = true }
    i += 1
  }
  if have {
    ## walk UP while each preceding comment is blank-separated from the current one — a stacked block.
    mut startc := lastc
    mut climbing := true
    while startc > 0 and climbing {
      prev_end := rt::vec_get(deref(comments), (startc - 1) * 2 + 1)
      cur_start := rt::vec_get(deref(comments), startc * 2)
      if gap_is_blank(src, prev_end, cur_start) { startc = startc - 1 } else { climbing = false }
    }
    mut k := startc
    while k <= lastc {
      cs := rt::vec_get(deref(comments), k * 2)
      ce := rt::vec_get(deref(comments), k * 2 + 1)
      push_str(sb, str_at((src + cs), ce - cs))
      push_str(sb, "\n")
      k += 1
    }
  }
}

## Byte-span equality against `src` (per-module copy, as in the backends).
streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  if a_n != b_n { return false }
  mut i := 0
  while i < a_n {
    if str_at(((src + a_s) + i), 1) != str_at(((src + b_s) + i), 1) { return false }   ## pointer arith (I11/CG-8)
    i += 1
  }
  return true
}

## The binary-operator symbol for an op byte (mirrors lower::op_symbol; `""` for an unknown op).
fmt_op := fn(op : u8) -> str {
  o := i64(op)
  if o == 16 { return "+" }
  if o == 17 { return "-" }
  if o == 18 { return "*" }
  if o == 19 { return "/" }
  if o == 29 { return "%" }
  if o == 20 { return "==" }
  if o == 28 { return "!=" }
  if o == 24 { return "<" }
  if o == 25 { return ">" }
  if o == 26 { return "<=" }
  if o == 27 { return ">=" }
  if o == 34 { return "&" }
  if o == 35 { return "|" }
  if o == 36 { return "^" }
  ## Boolean short-circuit ops carry the PARSER's internal op bytes 40/41 (NOT the `and`/`or` token
  ## kinds) — `p_and`/`p_or` build `Bin(40,…)`/`Bin(41,…)`. (`not` is op 42, a unary prefix rendered
  ## specially in the `Bin` arm, not here.)
  if o == 40 { return "and" }
  if o == 41 { return "or" }
  return ""
}

## Binary-operator PRECEDENCE (higher binds TIGHTER), mirroring the parser's expression tiers
## (loosest→tightest: `or` < `and` < `not` < comparison < `|` < `^` < `&` < `+`/`-` < `*`/`/`/`%`).
## fmt uses it to decide when a `Bin` sub-expression needs parentheses so the RE-PARSED tree keeps
## the SAME grouping — the parser erases the surface parens (they leave no AST node), so a bare
## re-emit of `(a + b) * c` as `a + b * c` would silently RE-GROUP to `a + (b * c)` (a different
## program). NOT used during the self-build (fmt runs only under `alatyr fmt`), so fixpoint-neutral.
fmt_op_prec := fn(op : u8) -> i64 {
  k := i64(op)
  if k == 18 or k == 19 or k == 29 { return 9 }   ## * / %
  if k == 16 or k == 17 { return 8 }              ## + -
  if k == 34 { return 7 }                         ## &
  if k == 36 { return 6 }                         ## ^
  if k == 35 { return 5 }                         ## |
  if k == 20 or k == 24 or k == 25 or k == 26 or k == 27 or k == 28 { return 4 }  ## comparisons
  if k == 42 { return 3 }                         ## `not` (prefix unary)
  if k == 40 { return 2 }                         ## and
  if k == 41 { return 1 }                         ## or
  return 100
}

## Is `op` a (non-associative) comparison operator? A comparison PARENT must parenthesize a
## comparison child of EQUAL precedence (`(a < b) == c`) since `a < b == c` re-parses differently.
fmt_is_cmp_op := fn(op : u8) -> bool {
  k := i64(op)
  return k == 20 or k == 24 or k == 25 or k == 26 or k == 27 or k == 28
}

## The parenthesization precedence of an expression: a `Bin` node's operator precedence, or a HIGH
## sentinel (an atomic/postfix primary — a literal, var, call, field, index, … — never needs parens).
fmt_expr_prec := fn(e : ptr(Expr)) -> i64 {
  mut p : i64 = 100
  match deref(e) {
    Expr::Bin(op, l, r) => { p = fmt_op_prec(op) }
    _ => {}
  }
  p
}

## Is the fn's `value` slot the NO-TAIL sentinel (`Num(-1)`, per sema::expr_is_no_tail)? A fn whose
## body ends in statements (a `return`, a `while`, …) carries this; a fn ending in a bare TAIL
## EXPRESSION (`fn() { a + b }`) carries that expression here and it must be emitted as the last line.
fmt_is_no_tail := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(v, s, n) => { if v == 0 - 1 and n == 0 { r = true } }
    _ => {}
  }
  r
}

## `Bin` destructuring, one field per probe — a `match` nested directly inside another `match` arm
## mis-lowers under the seed (the landmine `fmt_var_span` / `fmt_index_base` document), so the chain
## renderer below cannot inline any of these.
fmt_is_bin := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bin(bop, bl, br) => { r = true }
    _ => {}
  }
  r
}
fmt_bin_op := fn(e : ptr(Expr)) -> u8 {
  mut r : u8 = 0
  match deref(e) {
    Expr::Bin(bop, bl, br) => { r = bop }
    _ => {}
  }
  r
}
fmt_bin_left := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Bin(bop, bl, br) => { r = bl }
    _ => {}
  }
  r
}
## Emit `n` two-space indents.
emit_indent := fn(in out sb : rt::StrBuf, n : usize) {
  mut i := 0
  while i < n {
    push_str(sb, "  ")
    i += 1
  }
}

## Emit a structured loop label or a named break/continue target.  The parser keeps the resolved
## depth in the ordinary AST for lowering and records this authored name span in ast's side table for
## the semantics-preserving fmt round trip.
emit_fmt_label := fn(label : LabelSpan, in out sb : rt::StrBuf, src : ptr(u8)) {
  if label.n != 0 {
    push_str(sb, "@label(")
    push_str(sb, str_at((src + label.s), label.n))
    push_str(sb, ") ")
  }
}

## ---- §4.2.3, the 100-column wrapping rule -------------------------------------------------------
##
## `fmt` renders a construct SINGLE-LINE first, then measures what it actually wrote and — if the
## OPENING LINE overflows the 100-column soft maximum — rolls the buffer back and re-renders the
## construct WRAPPED (one element per line, one level in, a trailing comma, the closing bracket at
## the opening line's indent). Measuring the emitted text instead of predicting its width keeps ONE
## renderer per construct, so the wrapped and single-line spellings cannot drift apart; and because
## the verdict is a pure function of the AST plus the construct's indent — never of the INPUT's line
## breaks — `fmt(fmt(x)) == fmt(x)` still holds with wrapping on: the second pass reparses to the same
## tree, renders the same trial, measures the same width and takes the same branch.
##
## The BUFFER is the state these helpers read: the current indent, the current column and the
## enclosing line all come out of `sb`. That is what keeps the change local to this file — no "may I
## wrap" parameter has to be threaded through the ~100 recursive `emit_fmt_expr` call sites, and the
## seed compiles the result unchanged.

## Emit `n` single spaces. `emit_indent` counts LEVELS (two spaces each); a continuation indent is
## derived in COLUMNS from the opening line, so it needs the column-counting spelling.
fmt_emit_spaces := fn(in out sb : rt::StrBuf, n : usize) {
  mut i : usize = 0
  while i < n {
    push_str(sb, " ")
    i += 1
  }
}

## Byte offset of the start of the buffer line containing `at` (just past the preceding `\n`, or 0).
fmt_sb_line_start := fn(in out sb : rt::StrBuf, at : usize) -> usize {
  mut i := at
  while i > 0 and bytes(str_at((sb.data + i - 1), 1))[0] != 10 { i -= 1 }
  i
}

## The width of the buffer range `[from, to)` in UNICODE SCALAR VALUES — the unit §4.2.3 names, NOT
## bytes. A byte in `0x80 .. 0xBF` (128..191) is a UTF-8 CONTINUATION byte and starts no scalar; every
## other byte starts exactly one. The corpus carries `—`, `§` and Cyrillic in comments and string
## literals, where a byte count runs 2-3x ahead of the column and would wrap lines well inside the
## margin (and, on the other side, report a wrapped line as still overflowing).
fmt_sb_scalars := fn(in out sb : rt::StrBuf, from : usize, to : usize) -> usize {
  mut i := from
  mut n : usize = 0
  while i < to {
    b := bytes(str_at((sb.data + i), 1))[0]
    if b < 128 or b > 191 { n += 1 }
    i += 1
  }
  n
}

## The leading-space count of the line the buffer currently ENDS on — the indent of the line the
## construct about to be emitted starts on, and so (§4.2.3) the indent its closing bracket returns to.
fmt_sb_indent := fn(in out sb : rt::StrBuf) -> usize {
  ls := fmt_sb_line_start(sb, sb.len)
  mut i := ls
  mut scanning := true
  while scanning {
    if i >= sb.len { scanning = false }
    else if bytes(str_at((sb.data + i), 1))[0] == 32 { i += 1 }
    else { scanning = false }
  }
  i - ls
}

## The width of the OPENING LINE of the render that starts at `mark`: from that line's start to the
## first `\n` at or after `mark`, or to the buffer end when there is none. Only the opening line is
## measured, deliberately — a list holding an inherently multi-line element (a `fn` VALUE's braced
## body) can never be "on one line" at all, and folding its inner lines into the measurement would
## wrap the OUTER list for an overflow that wrapping the outer list cannot fix.
fmt_open_line_cols := fn(in out sb : rt::StrBuf, mark : usize) -> usize {
  ls := fmt_sb_line_start(sb, mark)
  mut e := mark
  while e < sb.len and bytes(str_at((sb.data + e), 1))[0] != 10 { e += 1 }
  fmt_sb_scalars(sb, ls, e)
}

## Did the render from `mark` BREAK A LINE — i.e. did a DESCENDANT wrap inside this construct's own
## single-line trial? §4.2.3 puts the wrap at the OUTERMOST construct, so that descendant's decision
## has to be thrown away with the trial and retaken at the deeper indent; and the signal is not
## redundant with the width test, because a descendant that wraps SHORTENS the opening line (it now
## ends at the descendant's `(`), hiding the overflow from any measurement.
##
## Three signatures, read off the text, because fmt has exactly three ways to end a line inside an
## expression:
##   `(\n` / `[\n`  a WRAPPED LIST — nothing else fmt emits opens a bracket and immediately breaks.
##   `{\n`          a BRACED BODY: a `fn` VALUE (`Expr::Lambda`) or a `loop` expression, whose inner
##                  statements then break lines of their own. Such a construct is inherently
##                  multi-line, so its newlines are NOT a descendant's wrap and must not force one —
##                  a region holding a `{\n` falls back to the opening-line width test alone.
##   any other `\n` a broken BINARY-OPERATOR CHAIN (§4.2.3's second bullet). Its continuation begins
##                  with the OPERATOR, so the newline has no fixed neighbour to key on; what makes it
##                  identifiable is that, absent a braced body, no other construct puts one there.
fmt_region_has_wrap := fn(in out sb : rt::StrBuf, mark : usize) -> bool {
  mut i := mark
  mut listwrap := false
  mut blockopen := false
  mut anynl := false
  while i + 1 < sb.len {
    b := bytes(str_at((sb.data + i), 1))[0]
    if b == 10 { anynl = true }
    if b == 40 or b == 91 or b == 123 {
      if bytes(str_at((sb.data + i + 1), 1))[0] == 10 {
        if b == 123 { blockopen = true } else { listwrap = true }
      }
    }
    i += 1
  }
  if listwrap { return true }
  if blockopen { return false }
  anynl
}

## Does the buffer line containing `at` already carry a `##` COMMENT? §4.2.4: a trailing comment
## SUPPRESSES re-wrapping of the line it trails, so a deliberately laid-out, commented line is never
## reflowed. Two things this deliberately does not do. It does not consult the SOURCE line: comment
## retention is still imperfect, and a comment dropped on the way out would suppress pass 1 and not
## pass 2 — which is exactly a non-idempotent formatter — so the test is on the text fmt is WRITING.
## And it does not count a `##` inside a string literal: the line always starts outside a literal (fmt
## never emits one across a line break), so tracking the quote state makes the test exact rather than
## merely conservative, and a `"## …"` literal no longer freezes its line's layout.
fmt_line_has_comment := fn(in out sb : rt::StrBuf, at : usize) -> bool {
  mut i := fmt_sb_line_start(sb, at)
  mut instr := false
  mut r := false
  mut scanning := true
  while scanning {
    if i >= sb.len { scanning = false } else {
      b := bytes(str_at((sb.data + i), 1))[0]
      if b == 10 { scanning = false }
      else if instr {
        if b == 92 { i += 1 }
        if b == 34 { instr = false }
        i += 1
      } else {
        if b == 34 { instr = true }
        if b == 35 { if i + 1 < sb.len { if bytes(str_at((sb.data + i + 1), 1))[0] == 35 { r = true ; scanning = false } } }
        i += 1
      }
    }
  }
  r
}

## The width of a `str` in UNICODE SCALAR VALUES (§4.2.3's unit) — the `fmt_sb_scalars` rule applied
## to a source span rather than to the buffer, for a caller that must know how wide a tail will be
## BEFORE it writes it.
fmt_str_scalars := fn(s : str) -> usize {
  mut i : usize = 0
  mut n : usize = 0
  while i < s.len {
    b := bytes(s)[i]
    if b < 128 or b > 191 { n += 1 }
    i += 1
  }
  n
}

## The §4.2.3 verdict on the construct just rendered SINGLE-LINE into `[mark, sb.len)`: true — with the
## buffer already rolled back to `mark`, ready for the wrapped re-render — iff the opening line
## overflows the 100-column soft maximum, or a descendant wrapped inside the trial and the wrap
## therefore belongs out here. A `##` comment on that line suppresses it (§4.2.4).
##
## `reserve` is the width, in scalars, of text the CALLER knows will still land on this line after the
## construct — the `-> R` of a signature, a wrapped list's mandatory trailing `,`. §4.2.3 caps the
## LINE, not the construct, and the construct's own verdict cannot see its successor: `add8 := @extern
## @abi(c) fn(a : i64, … h : i64)` measures 98 and stays single-line, then ` -> i64` makes the line
## 105. A reserve of 0 is the plain "nothing follows" case.
fmt_wrap_needed_res := fn(in out sb : rt::StrBuf, mark : usize, reserve : usize) -> bool {
  if fmt_line_has_comment(sb, mark) { return false }
  mut need := fmt_region_has_wrap(sb, mark)
  if not need { if fmt_open_line_cols(sb, mark) + reserve > 100 { need = true } }
  if not need { return false }
  sb.len = mark
  true
}

fmt_wrap_needed := fn(in out sb : rt::StrBuf, mark : usize) -> bool {
  return fmt_wrap_needed_res(sb, mark, 0)
}

## §4.2.3 verdict for the ONE construct whose overflow is invisible to the sub-construct that caused
## it: an INLINE if-EXPRESSION. Its condition's own width verdict is taken before ` { … } else { … }`
## exists, so a condition that fits at 96 columns yields a 116-column LINE. Only the OPENING-LINE
## width counts here — deliberately NOT `fmt_region_has_wrap`: a descendant that broke a line inside
## a BRANCH already took the outermost wrap available to it, and re-taking that decision out here
## would wrap the CONDITION for an overflow it did not cause. A `##` comment suppresses it (§4.2.4).
## Rolls the buffer back to `mark` when it returns true, exactly like `fmt_wrap_needed`.
fmt_if_wrap_needed := fn(in out sb : rt::StrBuf, mark : usize) -> bool {
  if fmt_line_has_comment(sb, mark) { return false }
  if fmt_open_line_cols(sb, mark) <= 100 { return false }
  sb.len = mark
  true
}

## The WRAPPED spelling of a plain `Arg` list: one element per line at `ind + 2` columns, each with a
## trailing comma (canonical for a wrapped list, §4.2.3 — a single-line list has none), then `close`
## back at `ind`. A separate function on purpose: the self-host lower miscompiles an `Arg` read bound
## inside a nested `if` in a `match` arm whose expression is then handed to `emit_fmt_expr` (the
## landmine `fmt_emit_arraylit` documents), and the re-render is reached through exactly such an `if`.
fmt_emit_arg_list_multi := fn(head : ptr(mut Arg), close : str, ind : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  ## Every wrapped element is followed by its mandatory one-scalar trailing comma. Pass that tail
  ## through the expression boundary so a nested operator chain does not decide at column 100 and
  ## then become 101 when this renderer appends the comma.
  push_str(sb, "\n")
  mut g := head
  while g != 0 {
    ga := deref(arg_p(g))
    fmt_emit_spaces(sb, ind + 2)
    emit_fmt_expr_res(ga.e, sb, src, a, decls, 1)
    push_str(sb, ",\n")
    g = ga.next
  }
  fmt_emit_spaces(sb, ind)
  push_str(sb, close)
}

## Emit a plain `Arg` list as `open … close`, applying §4.2.3: single-line first, wrapped if that
## overflows. Shared by the three §4.2.3 forms whose elements are bare expressions — a CALL's argument
## list, an enum constructor's payload, and an array/list literal. An EMPTY list is never wrapped:
## `(\n)` is not a spelling of `()`, and a line that overflows around an argument-less call overflows
## for a reason no wrap of that call can fix.
fmt_emit_arg_list := fn(head : ptr(mut Arg), open : str, close : str, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec), reserve : usize) {
  mark := sb.len
  ind := fmt_sb_indent(sb)
  push_str(sb, open)
  mut g := head
  mut first := true
  while g != 0 {
    ga := deref(arg_p(g))
    if not first { push_str(sb, ", ") }
    emit_fmt_expr(ga.e, sb, src, a, decls)
    first = false
    g = ga.next
  }
  push_str(sb, close)
  if head != 0 {
    if fmt_wrap_needed_res(sb, mark, reserve) {
      push_str(sb, open)
      fmt_emit_arg_list_multi(head, close, ind, sb, src, a, decls)
    }
  }
}

## A struct literal's field list `(f = v, …)` rendered from the struct DECL's `FieldDecl` list, in
## either spelling: `multi` selects the §4.2.3 wrapped form (one `f = v` per line at `ind + 2`, each
## with a trailing comma, `)` back at `ind`), else the single-line form. ONE renderer with two
## spellings on purpose — a second copy of the field-name recovery could drift from this one, and the
## by-name pairing it performs is the part whose divergence is a SILENT relabelling of the fields.
fmt_emit_declfields := fn(head : ptr(mut Arg), fh : usize, ind : usize, multi : bool, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  push_str(sb, "(")
  if multi { push_str(sb, "\n") }
  mut g := head
  mut f := fh
  mut first := true
  while g != 0 {
    if f == 0 { panic("selfhost: fmt — struct literal has more args than fields") }
    ga := deref(arg_p(g))
    fd := deref(fld_p(f))
    if multi { fmt_emit_spaces(sb, ind + 2) }
    if not multi { if not first { push_str(sb, ", ") } }
    push_str(sb, str_at((src + fd.ns), fd.nl))
    push_str(sb, " = ")
    if multi { emit_fmt_expr_res(ga.e, sb, src, a, decls, 1) }
    if not multi { emit_fmt_expr(ga.e, sb, src, a, decls) }
    if multi { push_str(sb, ",\n") }
    first = false
    g = ga.next
    f = fd.next
  }
  if multi { fmt_emit_spaces(sb, ind) }
  push_str(sb, ")")
}

## The same, for the SOURCE-SCAN path (an imported / cross-module struct, whose decl is not in this
## file): each field name is read off the literal's own `( … )` in source. The scan cursor restarts
## from `fopen + 1` on every call, so the wrapped re-render recovers exactly the same names as the
## single-line trial it replaces.
fmt_emit_scanfields := fn(head : ptr(mut Arg), fopen : usize, ind : usize, multi : bool, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  push_str(sb, "(")
  if multi { push_str(sb, "\n") }
  mut scan := fopen + 1
  mut g := head
  mut first := true
  while g != 0 {
    ga := deref(arg_p(g))
    mut fns : usize = 0
    mut fnl : usize = 0
    ok := struct_field_scan(src, ptr(scan), ptr(fns), ptr(fnl))
    if ok == 0 { panic("selfhost: fmt — struct literal field name not found in source") }
    if multi { fmt_emit_spaces(sb, ind + 2) }
    if not multi { if not first { push_str(sb, ", ") } }
    push_str(sb, str_at((src + fns), fnl))
    push_str(sb, " = ")
    if multi { emit_fmt_expr_res(ga.e, sb, src, a, decls, 1) }
    if not multi { emit_fmt_expr(ga.e, sb, src, a, decls) }
    if multi { push_str(sb, ",\n") }
    first = false
    g = ga.next
  }
  if multi { fmt_emit_spaces(sb, ind) }
  push_str(sb, ")")
}

## The FieldDecl-list head of the STRUCT decl named `[ss, ss+sl)` (kind 2), else 0 — so a StructLit
## `S(v0, …)` can recover its FIELD NAMES positionally (the literal carries only the values, and
## Alatyr requires named construction `S(f = v)`, so fmt must re-attach the names).
## The length of the BASE name in `[ss, ss+sl)` — the prefix before a generic-argument `(` (`Slice(u64)`
## → `Slice`), else the whole span. A generic-instance struct literal (`Slice(u64)(ptr = …)`) carries the
## INSTANCE name as its head span, but the struct DECL is keyed by the base name, so field-name recovery
## must strip the `(…)` args first. Rendering still uses the full span (the instance name round-trips).
name_base_len := fn(src : ptr(u8), ss : usize, sl : usize) -> usize {
  mut i := 0
  while i < sl and bytes(str_at((src + ss + i), 1))[0] != 40 { i += 1 }   ## '(' = 40
  i
}

fmt_struct_fields := fn(decls : ptr(rt::Vec), src : ptr(u8), ss : usize, sl : usize) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.kind == 2 and streq(src, d.name_start, d.name_len, ss, sl) { r = d.fields_head }
    i += 1
  }
  r
}

## Is `b` an ASCII identifier byte (`0-9`, `A-Z`, `a-z`, `_`)?
fmt_is_ident_byte := fn(b : usize) -> bool {
  return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
}

## Is `b` a blank byte (space / tab / LF / CR)? The one-byte form of `gap_is_blank`, for the
## backward source scans that recover a marker sitting just before a known name span.
fmt_is_blank_byte := fn(b : usize) -> bool {
  return b == 32 or b == 9 or b == 10 or b == 13
}

## Blanks permitted inside a qualified value-path separator. LF/CR are lexer whitespace too. The
## backward recovery checks comment lines separately and refuses an ambiguous path rather than
## silently dropping its head.
fmt_is_path_blank_byte := fn(b : usize) -> bool {
  return b == 32 or b == 9 or b == 10 or b == 13
}

## A struct FIELD's `mut` marker (grammar §130: `field ::= { attribute } [ "mut" ] ident ":" type`).
## `FieldDecl` records only the name/type spans — CT-6's `Field.mutable` is re-derived FROM SOURCE at
## every use — so the reconstructed body dropped the marker and `comptime_typeinfo_field_mutable`
## reformatted from 42 to 41 (its `f.mutable` derive stopped counting the field). Recovered by a
## backward scan off the field's own name span, ANCHORED: the `mut` must be the member's FIRST token,
## i.e. the byte before it (modulo blanks) is the body's `{` or the previous member's `,`. Without
## that anchor a `## … mut` comment line above a field would read as a marker. An `@attr mut f : T`
## member never reaches here — a body holding `@` is copied verbatim (`fmt_agg_body_is_plain`).
fmt_field_is_mut := fn(src : ptr(u8), ns : usize) -> bool {
  if ns < 4 { return false }
  mut p := ns
  while p > 0 and fmt_is_blank_byte(bytes(str_at((src + p - 1), 1))[0]) { p -= 1 }
  if p < 4 { return false }
  if str_at((src + p - 3), 3) != "mut" { return false }
  mut q := p - 3
  while q > 0 and fmt_is_blank_byte(bytes(str_at((src + q - 1), 1))[0]) { q -= 1 }
  if q == 0 { return false }
  b := bytes(str_at((src + q - 1), 1))[0]
  return b == 123 or b == 44                                   ## '{' or ','
}

## Skip the balanced group that OPENS at `open` (a `(`/`[`/`{`) and return the offset just PAST its
## matching close — string- and char-literal aware (a bracket inside `"…"`/`'…'` can't unbalance it),
## honoring `\` escapes. Returns 0 if it runs off the end (malformed). Mirrors `enum_payload_len`.
skip_balanced_group := fn(src : ptr(u8), open : usize) -> usize {
  mut i := open
  mut depth := 0
  mut scanning := true
  mut r : usize = 0
  while scanning {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 { scanning = false }                                   ## EOF (malformed)
    else if b == 34 {                                                ## '"' — skip a string literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 34 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }           ## '\' escapes the next byte
        i += 1
      }
      i += 1
    } else if b == 39 {                                              ## '\'' — skip a char literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 39 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 40 or b == 91 or b == 123 { depth += 1 ; i += 1 } ## '(' '[' '{'
    else if b == 41 or b == 93 or b == 125 {                         ## ')' ']' '}'
      depth -= 1
      i += 1
      if depth == 0 { r = i ; scanning = false }
    } else { i += 1 }
  }
  return r
}

## Locate the field-list `(` of a struct literal whose head NAME ends at `from`. A generic instance
## `Slice(u8)(f = …)` interposes a TYPE-ARG group `(u8)` (a qualified `rt::Arena(f = …)` has none);
## the field group is the first `( … )` at/after `from` whose interior begins `ident =`. Any preceding
## type-arg group (no top-level `=`) is skipped as a balanced, string/char-aware unit. Returns the
## offset of the field `(`, or 0 if none is found (fail-loud upstream — never guess).
find_fields_open := fn(src : ptr(u8), from : usize) -> usize {
  mut i := from
  mut searching := true
  mut r : usize = 0
  while searching {
    mut b := bytes(str_at((src + i), 1))[0]
    while b == 32 or b == 9 or b == 10 or b == 13 { i += 1 ; b = bytes(str_at((src + i), 1))[0] }
    if b != 40 { searching = false }                                 ## no '(' → give up (r stays 0)
    else {
      ## peek the interior: `ident =` marks the field group.
      mut j := i + 1
      mut c := bytes(str_at((src + j), 1))[0]
      while c == 32 or c == 9 or c == 10 or c == 13 { j += 1 ; c = bytes(str_at((src + j), 1))[0] }
      mut idlen := 0
      while fmt_is_ident_byte(c) { j += 1 ; idlen += 1 ; c = bytes(str_at((src + j), 1))[0] }
      while c == 32 or c == 9 or c == 10 or c == 13 { j += 1 ; c = bytes(str_at((src + j), 1))[0] }
      if idlen > 0 and c == 61 { r = i ; searching = false }         ## '=' → field group
      else {
        i = skip_balanced_group(src, i)                              ## a type-arg group — skip it
        if i == 0 { searching = false }                              ## malformed
      }
    }
  }
  return r
}

## SOURCE-SCAN one `name = value` field of a struct literal. `pos` points at the start of a field
## (just past the field-list `(` or the previous depth-0 `,`). Writes the field NAME span to
## `out_ns`/`out_nl` and advances `pos` past this field's value — to just after its trailing depth-0
## `,`, or (last field) to the closing `)`. Tracks paren/bracket/brace depth and skips `"…"`/`'…'`
## literals so a `,`/`=` inside a nested call/struct/array/block/string can't fool the scan. Returns 1
## on success, 0 if no `ident =` is present at depth 0 (Alatyr struct literals are always named — a
## nameless value is FAIL-LOUD upstream, never guessed). Mirrors `enum_payload_len`'s balanced scan.
struct_field_scan := fn(src : ptr(u8), pos : ptr(mut usize), out_ns : ptr(mut usize), out_nl : ptr(mut usize)) -> usize {
  mut i := deref(pos)
  mut b := bytes(str_at((src + i), 1))[0]
  while b == 32 or b == 9 or b == 10 or b == 13 { i += 1 ; b = bytes(str_at((src + i), 1))[0] }   ## skip ws
  ns := i
  while fmt_is_ident_byte(b) { i += 1 ; b = bytes(str_at((src + i), 1))[0] }                       ## read field name
  nl := i - ns
  if nl == 0 { return 0 }
  deref(out_ns) = ns
  deref(out_nl) = nl
  while b == 32 or b == 9 or b == 10 or b == 13 { i += 1 ; b = bytes(str_at((src + i), 1))[0] }    ## skip ws to '='
  if b != 61 { return 0 }                                                                          ## '=' = 61
  i += 1
  ## scan the value to its terminating depth-0 ',' or ')'
  mut depth := 0
  mut scanning := true
  while scanning {
    b = bytes(str_at((src + i), 1))[0]
    if b == 0 { scanning = false }                                                                 ## EOF (malformed)
    else if b == 34 {                                                                              ## '"' — skip a string literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 34 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 39 {                                                                            ## '\'' — skip a char literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 39 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 40 or b == 91 or b == 123 { depth += 1 ; i += 1 }                               ## '(' '[' '{' open
    else if b == 41 or b == 93 or b == 125 {                                                       ## ')' ']' '}' close
      if depth == 0 { scanning = false }                                                           ## the struct-lit ')': last field
      else { depth -= 1 ; i += 1 }
    } else if b == 44 and depth == 0 { i += 1 ; scanning = false }                                 ## ',' field separator
    else { i += 1 }
  }
  deref(pos) = i
  return 1
}


## DRY-RUN the struct-literal field-name scan: does the source `( … )` opening at `fopen` spell a
## `name =` pair for EVERY argument in `ah`? The emitting loop pushes text as it goes and cannot back
## out, so the choice between the source-scan render and the decl-based fallback is made up front.
fmt_structlit_names_ok := fn(src : ptr(u8), fopen : usize, ah : ptr(mut Arg)) -> bool {
  mut scan := fopen + 1
  mut g := ah
  mut ok := true
  while g != 0 and ok {
    ga := deref(arg_p(g))
    mut fns : usize = 0
    mut fnl : usize = 0
    if struct_field_scan(src, ptr(scan), ptr(fns), ptr(fnl)) == 0 { ok = false }
    g = ga.next
  }
  ok
}

## Append `n` as an UNSIGNED decimal. `rt::push_int` formats a SIGNED `i64`, and a literal at or above
## 2^63 (`18446744073709551615`) is stored in the `Expr::Num` payload as its BIT PATTERN — so it came
## back out as `-1`. That is not the same program twice over: it is a different VALUE, and the parser
## desugars a written `-x` into `unchecked 0 - x`, so re-parsing the render put an overflowing
## SUBTRACTION on a `u64` where a literal had stood (`unchecked_add_ovf` ran 0 -> SIGILL 132, and the
## same trap took out `narrow_wrap_builtin` / `shift_intrinsics` / `operator_vec2` / `overload_mangle`
## / `arch_intrinsic`). ONLY called for `n >= 2^63` (the caller tests `v < 0`), so the value is split
## once: `n / 10` is at most (2^64-1)/10, comfortably below 2^63, and both halves then print correctly
## through the SIGNED `push_int`. Written without a loop on purpose — a `n >= 10` guard would not
## work here, because a `u64` holding a high-bit value compares SIGNED under the current lower (see
## `18446744073709551615 < 10` is true today), which is also what makes this whole path
## necessary. Unsigned `/` and `%` are correct, so the split is exact.
fmt_push_uint := fn(in out sb : rt::StrBuf, n : usize) {
  hi := n / 10
  lo := n % 10
  d1 := push_int(sb, i64(hi))
  d2 := push_int(sb, i64(lo))
}

## Locate the first occurrence of `w` (`wl` bytes) as a WHOLE identifier in `[0, len)` — neither
## neighbour may be an identifier byte, so `Resulting` does not match `Result`. Returns `wl` with the
## offset in `out_s`, else 0. Used by the fmt driver to seed its enum-name table with the PRELUDE
## tryable enums, which no source file declares (see `compile_file_fmt`).
pub fmt_find_ident := fn(src : ptr(u8), len : usize, w : str, wl : usize, out_s : ptr(mut usize)) -> usize {
  mut i : usize = 0
  mut r : usize = 0
  while i + wl <= len and r == 0 {
    if str_at((src + i), wl) == w {
      mut okb := true
      if i > 0 { if fmt_is_ident_byte(bytes(str_at((src + i - 1), 1))[0]) { okb = false } }
      if fmt_is_ident_byte(bytes(str_at((src + i + wl), 1))[0]) { okb = false }
      if okb { deref(out_s) = i ; r = wl }
    }
    i += 1
  }
  r
}

## Is this `ArrayLit` the `[e ; n]` FILL form rather than a written-out `[e0, e1, …]`? The parser
## desugars the fill by pushing `n` copies of the SINGLE element node (`p_primary`: "all copies share
## the single element node `ee`"), so every `Arg.e` is the very same pointer; a hand-written
## `[x, x, x]` allocates a fresh node per element, so the pointers differ and this never false-fires.
## Nothing else in the AST distinguishes the two, and the difference MATTERS: `[u64; 3]` in expression
## position is how an ARRAY TYPE is passed to a generic fn (`sum_gen([u64; 3], arr)`, Types §9.2), and
## expanding it to `[u64, u64, u64]` renamed the instantiation — the assembler then choked on a
## mangled symbol carrying a literal `, ` (`generic_array_param` / `display_array` /
## `display_array_struct` / `comptime_typeinfo_n` / `comptime_for_typeinfo_n` all died that way).
## `n < 2` has no signal at all (`[e; 1]` and `[e]` are the same node), so it is left expanded.
fmt_arraylit_is_fill := fn(n : usize, head : ptr(mut Arg)) -> bool {
  if n < 2 { return false }
  if unchecked bitcast(usize, head) == 0 { return false }
  h0 := deref(arg_p(head))
  p0 := unchecked bitcast(usize, h0.e)
  if p0 == 0 { return false }
  mut g := h0.next
  mut same := true
  while g != 0 {
    ga := deref(arg_p(g))
    ep := unchecked bitcast(usize, ga.e)
    if ep != p0 { same = false }
    g = ga.next
  }
  same
}

## The source offset of the expression's OWN FIRST byte, or 0 when it cannot be established. Only
## leaves that carry a span answer directly (a written literal, a name, a call/struct/enum head); a
## postfix or binary node answers for its leftmost child, and a nested aggregate literal answers with
## its own opening bracket (`fmt_arraylit_open`) so the enclosing literal sees the bracket and not the
## first scalar inside it. A PREFIX form (`not x`, `unchecked x`, `-x`, `deref(p)`) deliberately
## answers 0: its keyword sits to the LEFT of every child span, so a child's offset would mis-place it.
fmt_expr_left_off := fn(e : ptr(Expr), src : ptr(u8)) -> usize {
  mut r : usize = 0
  match deref(e) {
    Expr::Num(lnv, lns, lnn) => { if lnn != 0 { r = lns } }
    Expr::Var(lvs, lvn) => { if lvn != 0 { r = lvs } }
    Expr::FloatLit(lfs, lfn) => { if lfn != 0 { r = lfs } }
    Expr::Call(lcs, lcl, lcn, lcah) => { if lcl != 0 { r = lcs } }
    Expr::StructLit(lss, lsl, lsnf, lsah) => { if lsl != 0 { r = lss } }
    Expr::EnumLit(les, lel, levs, levl, lenp, leph) => { if lel != 0 { r = les } }
    Expr::Field(lfb, lffs, lffl) => { r = fmt_expr_left_off(lfb, src) }
    Expr::Index(lib, liix) => { r = fmt_expr_left_off(lib, src) }
    Expr::Slice(lslb, lslo, lshi) => { r = fmt_expr_left_off(lslb, src) }
    Expr::CompField(lcfb, lcfi) => { r = fmt_expr_left_off(lcfb, src) }
    Expr::Try(lti) => { r = fmt_expr_left_off(lti, src) }
    Expr::Bin(lbo, lbl, lbr) => { r = fmt_expr_left_off(lbl, src) }
    Expr::ArrayLit(lan, lah) => { r = fmt_arraylit_open(lan, lah, src) }
    _ => {}
  }
  r
}

## The offset of the bracket that OPENS this aggregate literal — a `(` for a TUPLE, a `[` for an
## array — found by walking left from the first element's own first byte over blanks. 0 when the
## element carries no usable offset, or when the byte found is neither bracket (never guess).
fmt_arraylit_open := fn(n : usize, head : ptr(mut Arg), src : ptr(u8)) -> usize {
  if unchecked bitcast(usize, head) == 0 { return 0 }
  h0 := deref(arg_p(head))
  off := fmt_expr_left_off(h0.e, src)
  if off == 0 { return 0 }
  mut p := off
  while p > 0 and fmt_is_blank_byte(bytes(str_at((src + p - 1), 1))[0]) { p -= 1 }
  if p == 0 { return 0 }
  b := bytes(str_at((src + p - 1), 1))[0]
  if b == 40 or b == 91 { return p - 1 }                                    ## '(' / '['
  0
}

## Was this literal written as a TUPLE `(a, b, …)` rather than an array `[a, b, …]`? The parser builds
## BOTH as `Expr::ArrayLit` ("a tuple is an N-word aggregate, so it is built as an `ArrayLit` … and
## reuses the array machinery"), and the node keeps no trace of the bracket — so fmt printed every
## tuple literal, and every tuple TYPE in expression position, with square brackets. That is a
## different program, not a different style: `t : (u64, u64) = [3, 4]` and `display([u64, u64], …)`
## stopped compiling (`display_tuple`, `display_tuple_agg`, `tuple_lit_arg`, `comptime_typeinfo_n`).
## Recovered from the source bracket itself (`fmt_arraylit_open`); an unprovable bracket keeps the
## historical `[` rather than inventing a tuple.
fmt_arraylit_is_tuple := fn(n : usize, head : ptr(mut Arg), src : ptr(u8)) -> bool {
  o := fmt_arraylit_open(n, head, src)
  if o == 0 { return false }
  return bytes(str_at((src + o), 1))[0] == 40                              ## '('
}

## Emit an array literal without putting an indirect by-value read in the `Expr::ArrayLit` match arm.
## The self-host lower miscompiles `fh := deref(arg_p(al_e))` when that binding sits inside a nested
## `if` there and its expression is passed recursively to `emit_fmt_expr` (the formatter then crashes).
## Keep the element read in the loop-local `ga` shape, which is seed-safe and also handles written-out
## literals; `fill` only cuts the shared-node walk short after the first element.
fmt_emit_arraylit := fn(n : usize, head : ptr(mut Arg), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec), reserve : usize) {
  tup := fmt_arraylit_is_tuple(n, head, src)
  ## the `[e; N]` fill form is an ARRAY spelling only — a tuple never shares one element node.
  mut fill := fmt_arraylit_is_fill(n, head)
  if tup { fill = false }
  ## §4.2.3 — the plain `[e0, e1, …]` LIST literal is one of the four wrapping forms. A TUPLE `(a, b)`
  ## is a tuple-ctor, which §4.2.3 does NOT list, and `[e; N]` is one element plus a repeat count, not
  ## a list of elements; both keep their single-line spelling however wide they are.
  if not tup {
    if not fill {
      fmt_emit_arg_list(head, "[", "]", sb, src, a, decls, reserve)
      return
    }
  }
  if tup { push_str(sb, "(") } else { push_str(sb, "[") }
  mut g := head
  mut first := true
  while g != 0 {
    ga := deref(arg_p(g))
    if not first { push_str(sb, ", ") }
    emit_fmt_expr(ga.e, sb, src, a, decls)
    first = false
    if fill { g = 0 } else { g = ga.next }
  }
  if fill { push_str(sb, "; ") ; dn := push_int(sb, i64(n)) }
  if tup { push_str(sb, ")") } else { push_str(sb, "]") }
}

## Is `e` an `Expr::Bitcast`? A SINGLE-match probe (the nested-match seed landmine, as `fmt_var_span`).
fmt_is_bitcast := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bitcast(bi, bs, bl) => { r = true }
    _ => {}
  }
  r
}

## Did the source write `unchecked` in front of the `bitcast` whose TARGET-TYPE span starts at `pts`?
## `Expr::Bitcast` records nothing about the verification-mode marker, so fmt emitted `unchecked
## bitcast(…)` unconditionally — which is NOT the same program: `unchecked bitcast(B, x)` over a
## 2-word aggregate returns 0 where the plain `bitcast(B, x)` returns 42 (a lower bug in its own
## right, reported separately), so a reformat of `bitcast_agg2word` silently changed the answer.
## Recovered by walking back from the type span to the enclosing `bitcast` keyword (it always sits
## immediately before, so the nearest one is the right one) and testing for the marker in front of it.
## A failed scan keeps the historical `unchecked` spelling rather than dropping a marker that was
## there — dropping one can put an overflowing operation back into checked mode.
fmt_bitcast_is_unchecked := fn(src : ptr(u8), pts : usize) -> bool {
  if pts < 8 { return true }
  mut lo : usize = 0
  if pts > 64 { lo = pts - 64 }
  mut k := pts - 7
  mut bpos : usize = 0
  mut hunting := true
  while hunting {
    if str_at((src + k), 7) == "bitcast" {
      mut okb := true
      if fmt_is_ident_byte(bytes(str_at((src + k + 7), 1))[0]) { okb = false }
      if k > 0 { if fmt_is_ident_byte(bytes(str_at((src + k - 1), 1))[0]) { okb = false } }
      if okb { bpos = k ; hunting = false }
    }
    if k <= lo { hunting = false } else { k -= 1 }
  }
  if bpos == 0 { return true }
  mut q := bpos
  while q > 0 and (bytes(str_at((src + q - 1), 1))[0] == 32 or bytes(str_at((src + q - 1), 1))[0] == 9 or bytes(str_at((src + q - 1), 1))[0] == 10 or bytes(str_at((src + q - 1), 1))[0] == 13) { q -= 1 }
  if q < 9 { return false }
  if str_at((src + q - 9), 9) != "unchecked" { return false }
  if q - 9 == 0 { return true }
  return fmt_is_ident_byte(bytes(str_at((src + q - 10), 1))[0]) == false
}

## Is the span a SUB-WORD SCALAR type name — the exact set `parser::subword_scalar_bytes` accepts?
## That predicate is what decides whether the parser preserved a bitcast's POINTEE (span `u8`, surface
## `ptr(u8)`) rather than its whole target type (span `B` / `ptr(mut Pt)`, surface as written), so it
## is also what decides whether fmt has to put the `ptr(…)` back. Kept as a mirror on purpose: a new
## sub-word width added there needs the same line here, or its render silently loses the pointer.
fmt_span_is_subword_scalar := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  t := str_at((src + s), n)
  return t == "u8" or t == "i8" or t == "bool" or t == "u16" or t == "i16" or t == "u32" or t == "i32" or t == "char" or t == "f32"
}

## Is `e` the literal `Num(0)`? (Single-level match — the self-host lower mis-compiles a `match` nested
## directly inside another `match` arm, so the unary-minus recognizer factors its two levels into two
## single-match helpers rather than one nested match.)
fmt_is_zero_num := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(v, s, n) => { if v == 0 and n == 0 { r = true } }
    _ => {}
  }
  r
}
## The unary-minus desugar is `Unchecked(Bin(17 /*-*/, Num(0), x))` (parser `p_factor`); return `x` (so
## fmt renders `-x`, not the literal `unchecked 0 - x` — semantically identical, and idempotent since a
## reparse of `-x` yields the same tree). 0 if `inner` is not that exact shape.
fmt_neg_rhs := fn(inner : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(inner) {
    Expr::Bin(bop, bl, br) => { if i64(bop) == 17 and fmt_is_zero_num(bl) { r = br } }
    _ => {}
  }
  r
}

## If `e` is a bare `Var`, write its name span to `out_s`/`out_n` and return true, else false. A
## SINGLE-match helper (a `match` nested directly inside another `match` arm mis-lowers under the
## seed — the documented landmine — so the caller can't inline this).
fmt_var_span := fn(e : ptr(Expr), out_s : ptr(mut usize), out_n : ptr(mut usize)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => { deref(out_s) = s ; deref(out_n) = n ; r = true }
    _ => {}
  }
  r
}

## Classify the source line immediately before `end`: 0 = ordinary, 1 = comment, 2 = line comment
## ending in `::`. A comment is whitespace to the lexer, but its words are not a path segment. Only
## a trailing separator can be mistaken for the head of the next Var; prose containing `::` is fine.
fmt_path_line_kind := fn(src : ptr(u8), end : usize) -> usize {
  mut ls := end
  while ls > 0 {
    b := bytes(str_at((src + ls - 1), 1))[0]
    if b == 10 or b == 13 { break }
    ls -= 1
  }
  mut p := ls
  mut comment_start := end
  mut quote := 0
  mut escaped := false
  while p + 1 < end and comment_start == end {
    b0 := bytes(str_at((src + p), 1))[0]
    b1 := bytes(str_at((src + p + 1), 1))[0]
    if quote != 0 {
      if escaped { escaped = false }
      else if b0 == 92 { escaped = true }
      else if (quote == 1 and b0 == 34) or (quote == 2 and b0 == 39) { quote = 0 }
      p += 1
    } else if b0 == 34 { quote = 1; p += 1 }
    else if b0 == 39 { quote = 2; p += 1 }
    else if b0 == 35 and b1 == 35 { comment_start = p }
    else { p += 1 }
  }
  if comment_start == end { return 0 }
  mut tail := end
  while tail > comment_start + 2 {
    b := bytes(str_at((src + tail - 1), 1))[0]
    if b == 32 or b == 9 { tail -= 1 } else { break }
  }
  if tail >= comment_start + 4 and str_at((src + tail - 2), 2) == "::" { return 2 }
  1
}

## Is the separator at `sep` outside a string/char literal and before any line comment? A raw
## backward scan can otherwise mistake the final `::` in `s := "text ::"` for a module separator
## before the next Var. Keep this lexical fence local to the source-recovery workaround.
fmt_path_sep_is_real := fn(src : ptr(u8), sep : usize) -> bool {
  mut ls := sep
  while ls > 0 {
    b := bytes(str_at((src + ls - 1), 1))[0]
    if b == 10 or b == 13 { break }
    ls -= 1
  }
  mut p := ls
  mut quote := 0
  mut escaped := false
  mut real := true
  while p < sep and real {
    b := bytes(str_at((src + p), 1))[0]
    if quote != 0 {
      if escaped { escaped = false }
      else if b == 92 { escaped = true }
      else if (quote == 1 and b == 34) or (quote == 2 and b == 39) { quote = 0 }
    } else if b == 34 { quote = 1 }
    else if b == 39 { quote = 2 }
    else if b == 35 { real = false }
    p += 1
  }
  real and quote == 0
}

## Recover the SOURCE start of a qualified value path whose AST `Var` span kept only its tail.
## `p_factor` stores `hex::encode` as `Var(encode)`, so the formatter must use the same narrow
## source-backed recovery as lower's `gref_split` until the AST grows a path field. Blanks, including
## line breaks, around `::` are part of the separator's accepted source spelling. If a comment or a
## non-identifier head makes the span ambiguous, fail loud: a formatter must never invent or drop
## source that changes the program.
fmt_var_path_start := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  if n == 0 { return s }
  mut cur_end := s
  mut path_start := s
  mut found := false
  mut scanning := true
  while scanning {
    mut sep_end := cur_end
    mut saw_comment := false
    mut gap_scanning := true
    while gap_scanning {
      while sep_end > 0 and fmt_is_path_blank_byte(bytes(str_at((src + sep_end - 1), 1))[0]) { sep_end -= 1 }
      line_kind := fmt_path_line_kind(src, sep_end)
      if line_kind == 2 { panic("selfhost: fmt — qualified value path crosses a comment containing ::") }
      if line_kind == 1 {
        saw_comment = true
        mut ls := sep_end
        while ls > 0 {
          b := bytes(str_at((src + ls - 1), 1))[0]
          if b == 10 or b == 13 { break }
          ls -= 1
        }
        sep_end = ls
      } else {
        gap_scanning = false
      }
    }
    if sep_end < 2 or str_at((src + sep_end - 2), 2) != "::" {
      scanning = false
    } else if not fmt_path_sep_is_real(src, sep_end - 2) {
      scanning = false
    } else {
      if saw_comment { panic("selfhost: fmt — qualified value path crosses a comment") }
      mut head_end := sep_end - 2
      while head_end > 0 and fmt_is_path_blank_byte(bytes(str_at((src + head_end - 1), 1))[0]) { head_end -= 1 }
      head_line_kind := fmt_path_line_kind(src, head_end)
      if head_line_kind != 0 { panic("selfhost: fmt — qualified value path head is in a comment") }
      mut head_start := head_end
      while head_start > 0 and fmt_is_ident_byte(bytes(str_at((src + head_start - 1), 1))[0]) { head_start -= 1 }
      if head_start == head_end { panic("selfhost: fmt — qualified value path head is not an identifier") }
      mut q := head_start
      while q < s {
        b := bytes(str_at((src + q), 1))[0]
        if b == 10 or b == 13 {
          panic("selfhost: fmt — multiline qualified value path is not safely renderable")
        }
        q += 1
      }
      path_start = head_start
      found = true
      cur_end = head_start
    }
  }
  if found { return path_start }
  s
}

## The BASE of an `Index` node (`fs` in `fs[0]`), 0 for anything else — a SINGLE-match probe (same
## seed landmine as `fmt_var_span`: a `match` nested directly inside another `match` arm mis-lowers).
fmt_index_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Index(b, ix) => { r = b }
    _ => {}
  }
  r
}

## The BASE of a `Field` node (`t` in `t.fs`), 0 for anything else — the sibling single-match probe.
fmt_field_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Field(b, fs, fl) => { r = b }
    _ => {}
  }
  r
}

## A `Num` node the parser SYNTHESIZED — its source span has length 0, so nothing was written for it.
## The tuple-component postfix `t.N` is parsed as `Index(t, Num(N, 0, 0))`, the very same node an
## array `t[N]` builds, except that a WRITTEN integer literal always carries its span (`p_primary`).
## So a spanless index is the only trace left that the source may have spelled `.N` and not `[N]`.
## (A CHAR-literal index `xs['a']` is spanless too — `fmt_sep_is_dot` reads the source to tell them
## apart, and renders the char case as the decimal `[97]` it already rendered: same value, same program.)
fmt_num_is_spanless := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(v, s, n) => { if n == 0 { r = true } }
    _ => {}
  }
  r
}

## The BASE of ANY postfix node (`[i]`, `.f`, `[lo..hi]`, `.(f)`, `?`), 0 for anything else — one
## match over the whole postfix family, so a chain walk descends exactly one step per call.
fmt_postfix_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Index(pib, piix) => { r = pib }
    Expr::Field(pfb, pffs, pffl) => { r = pfb }
    Expr::Slice(psb, pslo, pshi) => { r = psb }
    Expr::CompField(pcb, pci) => { r = pcb }
    Expr::Try(pti) => { r = pti }
    _ => {}
  }
  r
}

## Skip the ONE postfix step that starts at `p` (blanks may precede it) and return the offset just
## PAST it — `.<ident|digits>`, `.( … )`, `[ … ]`, `( … )`, `?`. 0 when `p` is not at a postfix step,
## which makes every caller fall back rather than mis-count a chain.
fmt_skip_postfix := fn(src : ptr(u8), p : usize) -> usize {
  mut i := p
  while fmt_is_blank_byte(bytes(str_at((src + i), 1))[0]) { i += 1 }
  c := bytes(str_at((src + i), 1))[0]
  if c == 91 or c == 40 { return skip_balanced_group(src, i) }                    ## '[' / '('
  if c == 63 { return i + 1 }                                                    ## '?'
  if c != 46 { return 0 }                                                        ## not a '.'
  mut j := i + 1
  while fmt_is_blank_byte(bytes(str_at((src + j), 1))[0]) { j += 1 }
  if bytes(str_at((src + j), 1))[0] == 40 { return skip_balanced_group(src, j) }  ## `.(f)`
  mut k := j
  while fmt_is_ident_byte(bytes(str_at((src + k), 1))[0]) { k += 1 }
  if k == j { return 0 }
  k
}

## Did the SOURCE write `.N` (a TUPLE-component projection) rather than `[N]` for the step
## `base <sep> idx`? Both parse to `Index(base, Num(N, …))` (parser: "a tuple is an N-word aggregate,
## so element N is read by the `t.N` postfix, lowered to `Index(t, Num(N))`"), so re-emitting a
## written `.N` as `[N]` is a silent REWRITE — and not an innocent one: `t.1.0 = 20` came back as
## `t[1][0] = 20`, which the parser does not accept as a nested element write, so the SECOND fmt pass
## read its own output as two bare statements (`t[1][0]` then `20`) and flattened the rest of the
## function — fmt destroying the program it had just written (`tuple_nested_write`,
## `standard_tuple_byte_component`), while `display_tuple`/`tuple_lit_arg` simply stopped compiling.
##
## Decided by READING the source, never by guessing. Two conditions must both hold: the index is a
## spanless `Num` (only `.N` and a char literal make one), and the chain below `base` bottoms out in a
## bare `Var` — then the var's name is followed in source by exactly `depth` postfix steps, and the
## step AFTER those is the one being rendered, so its first byte settles it. Anything not recognized
## (a call/deref root, a chain deeper than the walk, a malformed skip) answers false and the
## historical `[N]` stands — a miss, never a rewrite.
fmt_sep_is_dot := fn(base : ptr(Expr), idx : ptr(Expr), src : ptr(u8)) -> bool {
  if fmt_num_is_spanless(idx) == false { return false }
  mut node := unchecked bitcast(ptr(Expr), base)
  mut depth : usize = 0
  mut vs : usize = 0
  mut vn : usize = 0
  mut rooted := false
  mut going := true
  while going and depth < 16 {
    if fmt_var_span(node, ptr(vs), ptr(vn)) { rooted = true ; going = false }
    else {
      nx := fmt_postfix_base(node)
      if unchecked bitcast(usize, nx) == 0 { going = false }
      else { node = nx ; depth += 1 }
    }
  }
  if rooted == false { return false }
  if vn == 0 { return false }
  mut p := vs + vn
  mut k : usize = 0
  while k < depth {
    p = fmt_skip_postfix(src, p)
    if p == 0 { return false }
    k += 1
  }
  while fmt_is_blank_byte(bytes(str_at((src + p), 1))[0]) { p += 1 }
  if bytes(str_at((src + p), 1))[0] != 46 { return false }                        ## '.'
  d := bytes(str_at((src + p + 1), 1))[0]
  return d >= 48 and d <= 57
}

## FN-6 — is `e` a postfix chain (`[i]` / `.f` steps) bottoming out in the bare `Var` whose name span
## STARTS at `cs`? This is the STRUCTURAL half of the expression-callee test below: `ast::ecallee_is`
## is keyed on a source byte OFFSET, and a byte offset is only unique WITHIN one file — `alatyr fmt
## <package>` formats several files in one process off one global site set, so a mark left by file A
## could collide with an ordinary call's callee span at the same offset in file B. Requiring argument 0
## to actually BE a chain rooted at that very span (which the parser's `expr_root_name` guarantees for
## every real expression-callee site) makes such a collision inert: the ordinary call renders normally.
fmt_chain_rooted_at := fn(e : ptr(Expr), cs : usize) -> bool {
  mut node := unchecked bitcast(ptr(Expr), e)
  mut ok := false
  mut going := true
  mut steps := 0
  mut vs : usize = 0
  mut vn : usize = 0
  while going and steps < 16 {
    steps += 1
    if fmt_var_span(node, ptr(vs), ptr(vn)) {
      if vs == cs { ok = true }
      going = false
    }
    if going {
      mut nx := fmt_index_base(node)
      if unchecked bitcast(usize, nx) == 0 { nx = fmt_field_base(node) }
      if unchecked bitcast(usize, nx) == 0 {
        going = false
      } else {
        node = nx
      }
    }
  }
  ok
}

## FN-6 — is this `Expr::Call` a call through an EXPRESSION CALLEE (`fs[0](10)`, `t.fs[j](x)`,
## `(fs[0])(9)`) rather than a genuine call to the name at `cs`? `Expr::Call` carries its callee as a
## NAME SPAN, so such a call is represented as an ORDINARY call whose ARGUMENT 0 IS THE CALLEE
## EXPRESSION, with the name span BORROWED from the callee chain's root variable (`ast::ecallee_mark`
## records the site, keyed on that borrowed span's start). Without this test fmt renders the node
## LITERALLY — `fs[0](10)` comes back as `fs(fs[0], 10)`, a DIFFERENT program (a silent miscompile of
## the source itself). Both halves must hold: the parser marked this site AND argument 0 is a chain
## rooted at the borrowed name (see `fmt_chain_rooted_at` for why the second half is not redundant).
fmt_call_is_ecallee := fn(cs : usize, nn : usize, ah : ptr(mut Arg)) -> bool {
  if nn == 0 { return false }
  if unchecked bitcast(usize, ah) == 0 { return false }
  if ecallee_is(cs) == false { return false }
  a0 := deref(arg_p(ah))
  fmt_chain_rooted_at(a0.e, cs)
}

## When the fmt driver parses (`compile_file_fmt`), it passes NO enum-name table (`enums = NULL`), so
## `is_generic_enum_ctor` (parser) can't tell a real generic-enum construction `E(T).V` from a plain
## call-then-member `f(args).member` — it assumes the ctor shape and rewrites the head `f(args)` to a
## bare `Var("f")`, DROPPING the call arguments. fmt then sees `Field(Var("f"), member)` and would emit
## `f.member` — a SILENT MISCOMPILE (the args vanish). Detect it here: a `Field`/postfix base that is a
## bare `Var` whose source is immediately followed (past whitespace) by `(` was such a dropped call.
## Recover the WHOLE `f(args)` verbatim from source (name start through the balanced `(…)`), so the args
## survive and the reparse round-trips. Returns the byte length of the verbatim `f(args)` span from the
## Var start, or 0 when the base is a genuine `Var` member access (`x.v`, no `(` after the name) or a
## non-Var base. (A complete fix belongs in the driver — populate the enum table for the fmt parse, as
## `build` does — which also covers the `.method(…)`/`.V(…)` variants; this locks the common field case.)
fmt_dropped_call_len := fn(e : ptr(Expr), src : ptr(u8)) -> usize {
  mut vs : usize = 0
  mut vn : usize = 0
  if not fmt_var_span(e, ptr(vs), ptr(vn)) { return 0 }
  mut p := vs + vn
  mut c := str_at((src + p), 1)
  while c == " " or c == "\t" or c == "\n" or c == "\r" { p += 1 ; c = str_at((src + p), 1) }
  if c != "(" { return 0 }
  close := skip_balanced_group(src, p)
  if close == 0 { return 0 }
  close - vs
}

## A DOT call — `recv.method(args)` (UFCS, Functions §7.2) or an enum construction `E.V(args)` whose
## enum type is NOT declared in THIS file (`Option.Some(40)`, `Result.Ok(2)` — the stdlib sum types) —
## reaches fmt as an ORDINARY `Expr::Call`: parser.al desugars it to `Call(<method name span>,
## [receiver, args…])`, PREPENDING the receiver as argument 0 (the `is_ctor` decision at the `.name(`
## postfix keys on `is_enum_name`, and fmt's enum table holds only the FILE's own enum decls, so every
## stdlib-enum construction and every genuine method call lands in the `Call` branch).
## Rendered LITERALLY that is a DIFFERENT PROGRAM — a silent miscompile of the source itself:
##   `r.unwrap()`      came back as `unwrap(r)`        → `check: unbound name`
##   `Option.Some(40)` came back as `Some(Option, 40)` → the enum type passed as a VALUE argument
## The corpus check (`run(fmt(x))` vs `run(x)` over `test/*.al`) flagged ~35 files on this one shape.
## Detect it by SOURCE-SCAN (the same recovery idiom as `fmt_dropped_call_len` / `local_is_mut`): the
## callee name of a dot call is preceded, past whitespace, by a `.`. Two exclusions keep it exact:
##   • a `.` that is the second byte of a `..` RANGE (`xs[0..len(v)]` — `len` follows a dot) is not one;
##   • argument 0 must exist (`nn != 0`), since it is what the receiver is read back out of;
##   • the `.` must be on the SAME LINE as the method name — the backward scan skips blanks but NEVER
##     a newline. Without that guard a statement that merely FOLLOWS a `##` comment ending in a full
##     stop was read as a method call on the comment's last word: `u64(xs[0].z + …)` (the line after
##     `## … xs[1] stays untouched.`) came back as `(xs[0].z + …).u64()`. A written dot call always
##     has the dot and the name adjacent on one line, so the restriction costs no real form.
## A qualified call (`std::fmt::print(x)`) ends in `:`, a bare call in whitespace/`(`/`,` — neither
## matches — and the FN-6 expression-callee shape is decided BEFORE this test, so it is unaffected.
fmt_call_is_dot := fn(cs : usize, nn : usize, ah : ptr(mut Arg), src : ptr(u8)) -> bool {
  if nn == 0 { return false }
  if unchecked bitcast(usize, ah) == 0 { return false }
  if cs == 0 { return false }
  mut p := cs
  mut c := str_at((src + (p - 1)), 1)
  while p > 1 and (c == " " or c == "\t" or c == "\r") {
    p -= 1
    c = str_at((src + (p - 1)), 1)
  }
  if c != "." { return false }
  if p < 2 { return false }
  b := str_at((src + (p - 2)), 1)
  if b == "." { return false }
  true
}

## Emit a postfix BASE expression, recovering a fmt-mode dropped call `f(args)` verbatim if the parser
## erased its args (see `fmt_dropped_call_len`); otherwise the ordinary recursive render.
emit_fmt_base := fn(base : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  mut vs : usize = 0
  mut vn : usize = 0
  isv := fmt_var_span(base, ptr(vs), ptr(vn))
  clen := fmt_dropped_call_len(base, src)
  if isv and clen != 0 { push_str(sb, str_at((src + vs), clen)) } else { emit_fmt_expr(base, sb, src, a, decls) }
}

## Pretty-print an expression in canonical form. Fail-loud on a form outside the v1 core.
emit_fmt_expr_res := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec), reserve : usize) {
  match deref(e) {
    ## A NEGATIVE payload can only be a literal at or above 2^63 stored as its bit pattern (the parser
    ## desugars every written `-x` into `unchecked 0 - x`, so a source minus never reaches here) —
    ## render it UNSIGNED, the way it was written. See `fmt_push_uint`.
    Expr::Num(v, raw_s, raw_n) => {
      if raw_n != 0 {
        push_str(sb, str_at((src + raw_s), raw_n))
      } else {
        if v < 0 { fmt_push_uint(sb, unchecked bitcast(usize, v)) }
        else { push_int(sb, v) }
      }
    }
    Expr::BoolLit(v) => { if v == 0 { push_str(sb, "false") } else { push_str(sb, "true") } }
    Expr::Var(s, n) => {
      vstart := fmt_var_path_start(src, s, n)
      push_str(sb, str_at((src + vstart), s + n - vstart))
    }
    Expr::StrLit(s, n, lbl) => {
      ## `embed("path")` (Comptime §2.4) rides the `StrLit` node, but its payload is the FILE'S BYTES
      ## at an ABSOLUTE arena address — not an offset into `src` — and it carries the embed marker in
      ## its label's low residue (parser `embed_label_base`). Rendering it as an ordinary literal took
      ## `src + <absolute address>` and walked off the end of memory: `alatyr fmt` SEGFAULTED on any
      ## file containing an `embed`. The node keeps no path span, so the written form cannot be
      ## reconstructed — refuse, loudly. (Retaining the path span is a parser-side follow-up.)
      if lbl % 1000000 >= 500000 { panic("selfhost: fmt — embed(\"…\") is not modelled: the node keeps the file BYTES, not the path") }
      ## `n` is the DECODED byte length (the parser stores `raw_span - escape_count`, anticipating each
      ## `\x` folds to one byte — Types §3, "escapes deferred"), so it UNDERCOUNTS the source bytes for
      ## a literal with escapes (`"\n"` → n=1, pointing at just `\`). fmt must reproduce the source
      ## VERBATIM to round-trip, so it renders the RAW inner span (scanned from the open quote to the
      ## matching close, honoring `\"`), NOT the decoded `n`. Escape-free literals scan to the same span.
      push_str(sb, "\"")
      push_str(sb, str_at((src + s), str_inner_raw_len(src, s)))
      push_str(sb, "\"")
    }
    Expr::Bin(op, l, r) => {
      ## `not <operand>` is a UNARY prefix stored as `Bin(42, operand, dummy)` (the right child is a
      ## placeholder `Num(0)`) — render it prefix, not infix, so it round-trips.
      if i64(op) == 42 {
        push_str(sb, "not ")
        ## `not` binds looser than a comparison but tighter than `and`/`or`; a `not (a or b)` operand
        ## must keep its parens (a bare `not a or b` re-parses as `(not a) or b`).
        if fmt_expr_prec(l) < 3 {
          push_str(sb, "(")
          emit_fmt_expr(l, sb, src, a, decls)
          push_str(sb, ")")
        } else {
          emit_fmt_expr(l, sb, src, a, decls)
        }
      } else {
        ## Re-insert grouping parens the parser erased: a LEFT child of strictly-lower precedence (or
        ## equal precedence under a non-associative comparison parent) and a RIGHT child of lower-OR-
        ## EQUAL precedence must be wrapped, so the re-parse rebuilds the identical tree.
        ## §4.2.3, second bullet — a binary-operator CHAIN that overflows breaks BEFORE each of its
        ## operators. Rendered single-line first, then re-rendered broken when the opening line
        ## overflows (or when a descendant already broke a line, which puts the break out here).
        bmark := sb.len
        bind := fmt_sb_indent(sb)
        pp := fmt_op_prec(op)
        pcmp := fmt_is_cmp_op(op)
        lp := fmt_expr_prec(l)
        rp := fmt_expr_prec(r)
        wrap_l := lp < pp or (lp == pp and pcmp)
        wrap_r := rp <= pp
        if wrap_l { push_str(sb, "(") }
        emit_fmt_expr(l, sb, src, a, decls)
        if wrap_l { push_str(sb, ")") }
        ## bind the str-returning `fmt_op` to a LOCAL before forwarding it — an inline user str-returning
        ## call as a `str` argument mis-lowers under the seed (drops the length / faults).
        sym := fmt_op(op)
        push_str(sb, " ")
        push_str(sb, sym)
        push_str(sb, " ")
        if wrap_r { push_str(sb, "(") }
        emit_fmt_expr(r, sb, src, a, decls)
        if wrap_r { push_str(sb, ")") }
        ## The chain is the outermost wrappable construct in this expression. Its verdict must include
        ## the caller's still-pending suffix, not just the text that the chain itself emitted.
        if fmt_wrap_needed_res(sb, bmark, reserve) { fmt_emit_bin_chain(e, bind, sb, src, a, decls) }
      }
    }
    Expr::Call(cs, cl, nn, ah) => {
      ## FN-6: a call through an EXPRESSION CALLEE (`fs[0](10)`) is an ordinary `Call` node whose
      ## ARGUMENT 0 IS the callee and whose name span is BORROWED from the callee's root variable —
      ## render it back as `<arg0>(arg1, …)`, never as the literal `fs(fs[0], 10)` the fields spell.
      ec := fmt_call_is_ecallee(cs, nn, ah)
      ## UFCS / non-local-enum construction: `recv.method(args)` desugared to `method(recv, args)`.
      mut dc := false
      if ec == false { dc = fmt_call_is_dot(cs, nn, ah, src) }
      mut g := ah
      if ec {
        ga0 := deref(arg_p(ah))
        ## the callee chain is a postfix expression (highest precedence) — never needs grouping parens.
        emit_fmt_expr(ga0.e, sb, src, a, decls)
        g = ga0.next
      } else if dc {
        da0 := deref(arg_p(ah))
        ## a `Bin` receiver (`(a + b).m()`) must keep its grouping parens — `.` binds tighter than any
        ## operator, so an unparenthesized render would re-parse as `a + b.m()`.
        wrap := fmt_expr_prec(da0.e) < 100
        if wrap { push_str(sb, "(") }
        emit_fmt_base(da0.e, sb, src, a, decls)
        if wrap { push_str(sb, ")") }
        push_str(sb, ".")
        push_str(sb, str_at((src + cs), cl))
        g = da0.next
      } else {
        push_str(sb, str_at((src + cs), cl))
      }
      ## §4.2.3 — the argument list is one of the four wrapping forms; `fmt_emit_arg_list` renders it
      ## single-line and re-renders it one-argument-per-line when the opening line overflows 100 columns.
      fmt_emit_arg_list(g, "(", ")", sb, src, a, decls, reserve)
    }
    Expr::Field(base, fs, fl) => {
      emit_fmt_base(base, sb, src, a, decls)
      push_str(sb, ".")
      push_str(sb, str_at((src + fs), fl))
    }
    Expr::Index(base, idx) => {
      ## `t.N` (a tuple component) and `xs[N]` (an array element) are the SAME node — see
      ## `fmt_sep_is_dot` for how the written separator is recovered, and why guessing corrupts.
      emit_fmt_expr(base, sb, src, a, decls)
      if fmt_sep_is_dot(base, idx, src) {
        push_str(sb, ".")
        emit_fmt_expr(idx, sb, src, a, decls)
      } else {
        push_str(sb, "[")
        emit_fmt_expr(idx, sb, src, a, decls)
        push_str(sb, "]")
      }
    }
    Expr::Deref(p) => {
      push_str(sb, "deref(")
      emit_fmt_expr(p, sb, src, a, decls)
      push_str(sb, ")")
    }
    Expr::AddrOf(p) => {
      ## `ptr(mut x)` — the MUTABLE address-of spelling (`dyn_over(ptr(mut s1))`, a by-ref out-param).
      ## `Expr::AddrOf` records no mutability (the parser consumes the marker), so it was rendered back
      ## as `ptr(x)`: the same program TODAY (pointer mutability is not yet enforced) but a different
      ## SOURCE, and a build break the day it is. Recover the marker by source-scan off the operand's own
      ## name span (`local_is_mut`, as `emit_fmt_value`/`fmt_is_pub` recover `: T`/`pub`) — inside a
      ## `ptr(` the only token that can precede the operand is the `mut` marker itself, so no false match.
      mut ps : usize = 0
      mut pn : usize = 0
      mut ismut := false
      if fmt_var_span(p, ptr(ps), ptr(pn)) { if local_is_mut(src, ps) { ismut = true } }
      if ismut { push_str(sb, "ptr(mut ") }
      if not ismut { push_str(sb, "ptr(") }
      emit_fmt_expr(p, sb, src, a, decls)
      push_str(sb, ")")
    }
    Expr::If(c, t, f) => {
      ## Rendered inline first, then RE-rendered with the condition's operator chain broken when the
      ## whole line overflows (§4.2.3): the condition is the only construct on that line the spec
      ## names a wrapped spelling for, and its own verdict could not see the ` { … } else { … }` that
      ## follows it. `fmt_emit_if_expr` is the single renderer, parameterized by that one choice, so
      ## the two spellings cannot drift apart.
      imark := sb.len
      iind := fmt_sb_indent(sb)
      fmt_emit_if_expr(c, t, f, false, false, iind, sb, src, a, decls)
      if fmt_if_wrap_needed(sb, imark) {
        fmt_emit_if_expr(c, t, f, fmt_if_cond_chainable(c), true, iind, sb, src, a, decls)
      }
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      ## `E.V` construction (DOT — vs patterns' `::`); a payloaded variant appends `(p0, …)`.
      push_str(sb, str_at((src + es), el))
      ## A GENERIC INSTANCE head `Tri(A, B, C).First(a)` (Types §9.2) keeps only the BASE name span, so
      ## the type-argument group was dropped and `Tri.First(a)` no longer named a type. Recover it
      ## verbatim: the only thing that can directly follow an enum-name span here is that group — a
      ## payload `(…)` comes after the `.V`, never after `E`.
      if bytes(str_at((src + es + el), 1))[0] == 40 {                                  ## '('
        gl := skip_balanced_group(src, es + el)
        if gl != 0 { push_str(sb, str_at((src + es + el), gl - (es + el))) }
      }
      push_str(sb, ".")
      push_str(sb, str_at((src + vs), vl))
      ## §4.2.3 — an enum CONSTRUCTOR's payload wraps by the same rule as a call's argument list.
      if ph != 0 { fmt_emit_arg_list(ph, "(", ")", sb, src, a, decls, reserve) }
    }
    Expr::Match(scrut, arms_head) => {
      mm := sb.len
      mind := fmt_sb_indent(sb)
      push_str(sb, "match ")
      emit_fmt_expr(scrut, sb, src, a, decls)
      push_str(sb, " { ")
      emit_fmt_arms(arms_head, sb, src, a, decls)
      push_str(sb, " }")
      if fmt_wrap_needed(sb, mm) {
        push_str(sb, "match ")
        emit_fmt_expr(scrut, sb, src, a, decls)
        push_str(sb, " {\n")
        emit_fmt_arms_multi(arms_head, mind, sb, src, a, decls)
        fmt_emit_spaces(sb, mind)
        push_str(sb, "}")
      }
    }
    Expr::StructLit(ss, sl, nf, ah) => {
      ## `S(f0 = v0, …)` — the parser dropped the field NAMES (it keeps only the positional value
      ## args), so re-attach them. Two paths, both producing `name = value` in the parser's stored
      ## (= SOURCE) arg order:
      ##   • decl-based — when the struct DECL is in THIS file's `decls` (local): take the names from
      ##     its `FieldDecl` list, positionally. Unchanged legacy path.
      ##   • SOURCE-SCAN fallback — when the decl is NOT local (an IMPORTED / cross-module struct, so
      ##     `fmt_struct_fields` returns 0): recover each name by scanning the literal's `( … )` in
      ##     source (like `enum_payload_len`), keyed on nothing but the source text. This is what makes
      ##     fmt total across real MULTI-MODULE files (`rt::Arena(base = …)`, `Slice(u8)(ptr = …)`,
      ##     `StrBuf(idx = …)`) instead of fail-loud.
      ## The SOURCE-SCAN path is PREFERRED, and the decl-based one is now only the fallback for a
      ## literal whose field list cannot be located in source. The positional pairing the decl path
      ## does is only right when the literal names every field in DECLARATION ORDER — and the fmt
      ## parse deliberately runs with a NULL struct table (`compile_file_fmt`), so the by-name reorder
      ## is OFF and the stored args are in SOURCE order. Every other by-name literal was therefore
      ## RELABELLED, a silent miscompile of the worst kind (the values stay put, the names move):
      ##   P(y = 2, x = 40)  ->  P(x = 2, y = 40)     the two fields SWAP values
      ##   D(b = 3)          ->  D(a = 3)             an omitted defaulted field steals the value
      ##   D(c = 1, b = 2)   ->  D(a = 1, b = 2)
      ## Alatyr construction is by-name (Types §9.3), so the names are always THERE in the source.
      mut sfopen := find_fields_open(src, ss + sl)
      if sfopen != 0 { if fmt_structlit_names_ok(src, sfopen, ah) == false { sfopen = 0 } }
      mut fh : usize = 0
      if sfopen == 0 { fh = fmt_struct_fields(decls, src, ss, name_base_len(src, ss, sl)) }
      if fh != 0 {
        ## FIELD-NAME recovery keys on the BASE name (a generic instance `Slice(u64)` is declared as
        ## `Slice`); the full instance span is still what was rendered above, so the name round-trips.
        push_str(sb, str_at((src + ss), sl))
        ## §4.2.3 — a struct CONSTRUCTOR's fields are one of the four wrapping forms.
        dmark := sb.len
        dind := fmt_sb_indent(sb)
        fmt_emit_declfields(ah, fh, dind, false, sb, src, a, decls)
        if fmt_wrap_needed_res(sb, dmark, reserve) { fmt_emit_declfields(ah, fh, dind, true, sb, src, a, decls) }
      } else {
        ## SOURCE-SCAN: render the head VERBATIM from its (qualifier-widened) start up to the field
        ## `(`, so a qualifier (`rt::`) AND any generic type-arg group (`(u8)`) round-trip faithfully;
        ## then scan each `name =` before its value. The head span `[ss, ss+sl)` is the (tail) name;
        ## `find_fields_open` skips any interposed type-arg group to reach the real field list.
        mut hs := ss
        mut widen := true
        while widen {
          if hs == 0 { widen = false } else {
            k := hs - 1
            pb := bytes(str_at((src + k), 1))[0]
            if pb == 58 or fmt_is_ident_byte(pb) { hs = k } else { widen = false }   ## ':' (58) or ident byte
          }
        }
        fopen := sfopen
        if fopen == 0 { panic("selfhost: fmt — struct literal field-list not found in source") }
        push_str(sb, str_at((src + hs), fopen - hs))
        ## §4.2.3 — as the decl-based path above, on the source-scanned field names.
        smark := sb.len
        sind := fmt_sb_indent(sb)
        fmt_emit_scanfields(ah, fopen, sind, false, sb, src, a, decls)
        if fmt_wrap_needed_res(sb, smark, reserve) { fmt_emit_scanfields(ah, fopen, sind, true, sb, src, a, decls) }
      }
    }
    Expr::CompField(base, idx) => {
      ## comptime field/variant projection `v.(f)` — the member named by the comptime loop var `f`.
      emit_fmt_expr(base, sb, src, a, decls)
      push_str(sb, ".(")
      emit_fmt_expr(idx, sb, src, a, decls)
      push_str(sb, ")")
    }
    Expr::ArrayLit(al_n, al_e) => {
      fmt_emit_arraylit(al_n, al_e, sb, src, a, decls, reserve)
    }
    ## `unchecked <inner>` — the scoped verification mode marker (Types §4.2). Render the keyword
    ## then the inner expression.
    Expr::Unchecked(inner) => {
      rhs := fmt_neg_rhs(inner)
      if unchecked bitcast(usize, rhs) != 0 {
        ## Unary minus `-x` (desugared `unchecked 0 - x`) binds TIGHTER than EVERY binary operator
        ## (it is a `p_factor` prefix, below `*`/`/`). So a `Bin` operand must keep its parens: a bare
        ## `-(a + b)` re-emitted as `-a + b` RE-GROUPS to `(-a) + b` — a DIFFERENT program (the erased
        ## surface parens leave no AST node). An atomic operand (`fmt_expr_prec == 100`: a var / literal
        ## / call / field / index) never needs them. Idempotent: a re-parse of `-(a + b)` rebuilds the
        ## same tree, so re-fmt re-wraps identically.
        push_str(sb, "-")
        wrap_neg := fmt_expr_prec(rhs) < 100
        if wrap_neg { push_str(sb, "(") }
        if wrap_neg { emit_fmt_expr_res(rhs, sb, src, a, decls, reserve + 1) }
        if not wrap_neg { emit_fmt_expr(rhs, sb, src, a, decls) }
        if wrap_neg { push_str(sb, ")") }
      } else if fmt_is_bitcast(inner) {
        ## `unchecked bitcast(ptr(T), v)` parses as `Unchecked(Bitcast(…))`, and the `Bitcast` arm
        ## re-emits the WHOLE `unchecked bitcast(…)` surface itself — so emitting the keyword here too
        ## produced `unchecked unchecked bitcast(…)`, one more on every pass (fmt was NOT idempotent).
        emit_fmt_expr_res(inner, sb, src, a, decls, reserve)
      } else {
        ## `unchecked` is a `p_factor` PREFIX: it binds tighter than every binary operator, so a `Bin`
        ## operand must keep grouping parens. `unchecked { a + 1 }` re-emitted as `unchecked a + 1`
        ## re-parses as `(unchecked a) + 1` — the addition is back INSIDE the checked mode and
        ## `u64 MAX + 1` traps (`unchecked_add_ovf` ran 0 -> SIGILL 132). `unchecked (a + 1)` keeps the
        ## scope and re-parses to the same tree, so the render stays idempotent.
        ## ALWAYS parenthesized. `unchecked` is a `p_factor` PREFIX that takes a PRIMARY, so it does not
        ## reach past a binary operator OR a postfix step: `unchecked { lo - hi }` re-emitted bare
        ## became `(unchecked lo) - hi` (the subtraction back in CHECKED mode — SIGILL 132), and
        ## `unchecked (x.u)` became `(unchecked x).u` (the union member read out of its scope —
        ## `union_reinterpret` ran 42 -> 7). Parens round the whole operand cost nothing, are correct
        ## for every operand shape, and re-parse to the same tree, so the render stays idempotent.
        push_str(sb, "unchecked (")
        ## The inner expression is followed by this closing `)`, then by the caller's suffix. The old
        ## zero-reserve call therefore missed exactly the mandatory list comma in a wrapped field.
        emit_fmt_expr_res(inner, sb, src, a, decls, reserve + 1)
        push_str(sb, ")")
      }
    }
    ## `1.5` — a float literal, rendered from its verbatim source span (the lexer preserves the text).
    Expr::FloatLit(fs, fl) => {
      push_str(sb, str_at((src + fs), fl))
    }
    ## `<inner>?` — the tryable `?` operator (postfix).
    Expr::Try(inner) => {
      emit_fmt_expr(inner, sb, src, a, decls)
      push_str(sb, "?")
    }
    ## `base[lo..hi]` — a range-slice sub-view (str §3.5 / typed array-slice).
    Expr::Slice(base, lo, hi) => {
      emit_fmt_expr(base, sb, src, a, decls)
      push_str(sb, "[")
      emit_fmt_expr(lo, sb, src, a, decls)
      push_str(sb, "..")
      emit_fmt_expr(hi, sb, src, a, decls)
      push_str(sb, "]")
    }
    ## FN-6 — an inline function VALUE `fn(sig) { body }` (fmt does not lift, so it sees `Lambda`, not
    ## `FnRef`). Rendered like a fn definition's signature + braced body.
    Expr::Lambda(fnpos, ph, rts, rtl, bh, val) => {
      push_str(sb, "fn")
      ## The `-> R {` that follows the list is on the SAME line, so it belongs to the list's width
      ## verdict (§4.2.3 caps the line): 4 for `" -> "`, the return type's own scalars, 2 for `" {"`.
      mut lres : usize = 2
      if rtl != 0 { lres = 6 + fmt_str_scalars(str_at((src + rts), fmt_fnty_len(src, rts, rtl))) }
      emit_fmt_params(ph, lres, sb, src, a)
      if rtl != 0 {
        push_str(sb, " -> ")
        push_str(sb, str_at((src + rts), fmt_fnty_len(src, rts, rtl)))
      }
      push_str(sb, " {\n")
      tpl := fmt_type_param(ph, src, a)
      emit_fmt_stmts(bh, bh, sb, src, a, 1, decls, tpl)
      if not fmt_is_no_tail(val) {
        emit_indent(sb, 1)
        emit_fmt_expr(val, sb, src, a, decls)
        push_str(sb, "\n")
      }
      push_str(sb, "}")
    }
    Expr::Bitcast(inner, pts, ptl) => {
      ## A preserved sub-word pointer cast comes from `unchecked bitcast(ptr(<T>), v)`. The node stores
      ## the inner value plus the pointee type span; re-add the surrounding `unchecked bitcast(ptr(...), ...)`
      ## surface so a reparse keeps the same narrowing-aware AST node.
      ## The parser builds this node for THREE different surfaces and the span alone does not say
      ## which (`p_factor`'s bitcast branch): the POINTEE name for a sub-word `ptr(u8)` (span `u8`),
      ## the WHOLE pointer type for `ptr(mut Pt)` (span `ptr(mut Pt)`), and the bare TARGET TYPE of an
      ## aggregate→aggregate reinterpret `bitcast(B, x)` (span `B`). Wrapping the span in `ptr(…)`
      ## whenever it did not already start with `ptr(` conflated the last two: the aggregate cast
      ## `y := bitcast(B, x)` came back as `y := unchecked bitcast(ptr(B), x)` — a POINTER where a
      ## struct value stood, and `bitcast_agg2word` ran 42 before a reformat and SEGFAULTED after.
      ## The parser's own gate decides: it preserves a bare POINTEE only when that pointee is a
      ## SUB-WORD SCALAR, so those are exactly the spans that get the `ptr(…)` put back.
      ## The `mut` marker of a sub-word pointee (`ptr(mut u8)`) is NOT in the node either — the parser
      ## keeps the bare pointee span — so re-adding a flat `ptr(` dropped it and `bitcast(ptr(mut u8),
      ## a)` came back `bitcast(ptr(u8), a)`: the same program TODAY (pointer mutability is not yet
      ## enforced) but a different SOURCE, and a build break the day it is. Recovered by exactly the
      ## source-scan `Expr::AddrOf` uses for `ptr(mut x)` (`local_is_mut` off the span's own start) —
      ## and it is sound for the same reason: this branch runs only for a span the parser preserved
      ## from a `ptr( … )` target, and inside that `ptr(` the only token that can precede the pointee
      ## is the marker itself. `ptr(u8)` sees `tr(` before the span, so nothing is invented.
      if fmt_bitcast_is_unchecked(src, pts) { push_str(sb, "unchecked ") }
      push_str(sb, "bitcast(")
      if fmt_span_is_subword_scalar(src, pts, ptl) {
        push_str(sb, "ptr(")
        if local_is_mut(src, pts) { push_str(sb, "mut ") }
        push_str(sb, str_at((src + pts), ptl))
        push_str(sb, ")")
      } else {
        push_str(sb, str_at((src + pts), ptl))
      }
      push_str(sb, ", ")
      emit_fmt_expr(inner, sb, src, a, decls)
      push_str(sb, ")")
    }
    Expr::Loop(lb) => {
      ## VALUE-position loop expression: `loop { ... break v ... }`.
      emit_fmt_label(expr_label_span(e), sb, src)
      push_str(sb, "loop {\n")
      emit_fmt_stmts(lb, lb, sb, src, a, 2, decls, "")
      push_str(sb, "  }")
    }
    ## Defensive: `FnRef` is produced only by the driver's post-parse lift, which the fmt path never
    ## runs — so this is unreachable, but keeps the match total over the runtime `Expr` enum.
    Expr::FnRef(fnpos, fms, fml) => { push_str(sb, "fn() {}") }
    _ => { panic("selfhost: fmt — unsupported expression form") }
  }
}

## The ordinary expression entry point has no caller-supplied tail. Wrapping-aware callers use the
## reserve-carrying entry point above; keeping this wrapper preserves the intentionally flat call
## sites whose surrounding syntax is not a §4.2.3 list element.
emit_fmt_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  emit_fmt_expr_res(e, sb, src, a, decls, 0)
}

## The payload BINDING list of a match arm — `(pa, pb, …)`, or nothing when the arm has none.
emit_fmt_binds := fn(binds_head : ptr(mut Bind), in out sb : rt::StrBuf, src : ptr(u8)) {
  if unchecked bitcast(usize, binds_head) == 0 { return }
  push_str(sb, "(")
  mut b := binds_head
  mut bfirst := true
  while unchecked bitcast(usize, b) != 0 {
    if not bfirst { push_str(sb, ", ") }
    push_str(sb, str_at((src + bnd_ns(b)), bnd_nl(b)))
    bfirst = false
    b = bnd_next(b)
  }
  push_str(sb, ")")
}

## The ITERABLE text of a comptime variant-arm TEMPLATE — `comptime for <v> in typeinfo(T).variants {
## T.(v)(p…) => … }` (the shape `lib/base/derive.al`'s `eq`/`lt` are written in, parser `wild = 2`).
## The parser parses the iterable and THROWS IT AWAY (the `Arm` keeps only the loop-var span, the
## payload binds and the body), so fmt had nothing to render and refused the whole file. Recovered by
## scanning forward from the loop-var span to the `{` that opens the template body — the same
## discipline as `fmt_compfor_iter_arg`. Returns the iterable's length with `out_s` at its start and
## `out_open` at the `{`; 0 when the header does not spell `in <iterable> {`.
fmt_comptmpl_iter := fn(src : ptr(u8), vs : usize, vl : usize, out_s : ptr(mut usize), out_open : ptr(mut usize)) -> usize {
  lim := vs + vl + 512
  mut p := vs + vl
  mut c := bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if str_at((src + p), 2) != "in" { return 0 }
  p += 2
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  is := p
  mut depth : i64 = 0
  mut open : usize = 0
  mut scanning := true
  while scanning {
    b := bytes(str_at((src + p), 1))[0]
    if b == 0 or p >= lim { return 0 }
    else if b == 40 or b == 91 { depth += 1 ; p += 1 }
    else if b == 41 or b == 93 { depth -= 1 ; p += 1 }
    else if b == 123 and depth == 0 { open = p ; scanning = false }
    else { p += 1 }
  }
  mut e := open
  while e > is and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 10 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= is { return 0 }
  deref(out_s) = is
  deref(out_open) = open
  e - is
}

## The HEAD type name of the template's `T.(v)(p…)` pattern, read just past the template body's `{`.
## Returns its length with `out_s` at its start; 0 when the pattern is not the `<ident>.(` shape.
fmt_comptmpl_head := fn(src : ptr(u8), open : usize, out_s : ptr(mut usize)) -> usize {
  mut p := open + 1
  lim := open + 512
  mut c := bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  hs := p
  while p < lim and fmt_is_ident_byte(bytes(str_at((src + p), 1))[0]) { p += 1 }
  if p == hs { return 0 }
  he := p
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if bytes(str_at((src + p), 1))[0] != 46 { return 0 }                     ## '.'
  p += 1
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if bytes(str_at((src + p), 1))[0] != 40 { return 0 }                     ## '('
  deref(out_s) = hs
  he - hs
}

## The HEAD type name of a COMPTIME-VARIANT pattern `T.(v)` whose comptime VAR span starts at `vs`
## (parser `wild = 3`). The pattern parser overwrites the head span with the var's, so the head is
## recovered by walking BACK over `(` `.` to the identifier before them.
fmt_dotvar_head := fn(src : ptr(u8), vs : usize, out_s : ptr(mut usize)) -> usize {
  if vs < 3 { return 0 }
  mut p := vs
  while p > 0 and (bytes(str_at((src + p - 1), 1))[0] == 32 or bytes(str_at((src + p - 1), 1))[0] == 9) { p -= 1 }
  if p == 0 { return 0 }
  if bytes(str_at((src + p - 1), 1))[0] != 40 { return 0 }                 ## '('
  p -= 1
  while p > 0 and (bytes(str_at((src + p - 1), 1))[0] == 32 or bytes(str_at((src + p - 1), 1))[0] == 9) { p -= 1 }
  if p == 0 { return 0 }
  if bytes(str_at((src + p - 1), 1))[0] != 46 { return 0 }                 ## '.'
  p -= 1
  while p > 0 and (bytes(str_at((src + p - 1), 1))[0] == 32 or bytes(str_at((src + p - 1), 1))[0] == 9) { p -= 1 }
  he := p
  while p > 0 and fmt_is_ident_byte(bytes(str_at((src + p - 1), 1))[0]) { p -= 1 }
  if he <= p { return 0 }
  deref(out_s) = p
  he - p
}

## Emit the PATTERN portion of a value-match arm. Keeping this separate lets the wrapped renderer
## reuse exactly the same source-span recovery as the legacy single-line spelling.
fmt_emit_template_header := fn(am : Arm, in out sb : rt::StrBuf, src : ptr(u8), out_iopen : ptr(mut usize)) {
  mut its : usize = 0
  mut iopen : usize = 0
  itn := fmt_comptmpl_iter(src, am.vs, am.vl, ptr(its), ptr(iopen))
  if itn == 0 { panic("selfhost: fmt — comptime match-arm template header not found in source") }
  deref(out_iopen) = iopen
  push_str(sb, "comptime for ")
  push_str(sb, str_at((src + am.vs), am.vl))
  push_str(sb, " in ")
  push_str(sb, str_at((src + its), itn))
  push_str(sb, " {")
}

fmt_emit_template_pattern := fn(am : Arm, iopen : usize, in out sb : rt::StrBuf, src : ptr(u8)) {
  mut hds : usize = 0
  hdn := fmt_comptmpl_head(src, iopen, ptr(hds))
  if hdn == 0 { panic("selfhost: fmt — comptime match-arm template pattern head not found in source") }
  push_str(sb, str_at((src + hds), hdn))
  push_str(sb, ".(")
  push_str(sb, str_at((src + am.vs), am.vl))
  push_str(sb, ")")
  emit_fmt_binds(am.binds_head, sb, src)
}

fmt_emit_value_arm_pattern := fn(am : Arm, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  if am.wild == 2 {
    mut iopen : usize = 0
    fmt_emit_template_header(am, sb, src, ptr(iopen))
    push_str(sb, " ")
    fmt_emit_template_pattern(am, iopen, sb, src)
  }
  if am.wild == 3 {
    mut dhs : usize = 0
    dhn := fmt_dotvar_head(src, am.vs, ptr(dhs))
    if dhn == 0 { panic("selfhost: fmt — comptime-variant match pattern head not found in source") }
    push_str(sb, str_at((src + dhs), dhn))
    push_str(sb, ".(")
    push_str(sb, str_at((src + am.vs), am.vl))
    push_str(sb, ")")
    emit_fmt_binds(am.binds_head, sb, src)
  }
  if am.wild == 1 { push_str(sb, "_") }
  if am.wild == 4 {
    pat := unchecked bitcast(ptr(Expr), usize(am.lit))
    emit_fmt_expr(pat, sb, src, a, decls)
  }
  if am.wild == 5 { push_int(sb, am.lit); push_str(sb, ".."); push_int(sb, am.hi) }
  if am.wild == 6 { push_int(sb, am.lit); push_str(sb, "..="); push_int(sb, am.hi) }
  if am.wild == 0 {
    if am.vl != 0 {
      push_str(sb, str_at((src + am.vs), am.vl))
      emit_fmt_binds(am.binds_head, sb, src)
    } else {
      push_int(sb, am.lit)
    }
  }
}

## The parser expands `p | q` into adjacent arms sharing one body pointer. Re-group that representation
## while printing, so the canonical wrapped spelling can apply §4.3.3's break-before-`|` rule without
## changing the matched set or inventing a second AST representation.
fmt_same_value_arm_body := fn(a : Arm, b : Arm) -> bool {
  if a.wild == 2 or b.wild == 2 { return false }
  if a.body_stmts != 0 or b.body_stmts != 0 { return false }
  unchecked bitcast(usize, a.body) == unchecked bitcast(usize, b.body)
}

## Pretty-print a comma-separated value-match arm list in its compact form. Wrapping is decided by the
## caller after this trial; this function deliberately remains the one-line renderer used by the
## existing formatter for all constructs that fit.
emit_fmt_arms := fn(arms_head : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  mut arm := arms_head
  mut first := true
  while arm != 0 {
    am := deref(arm_p(arm))
    if not first { push_str(sb, ", ") }
    fmt_emit_value_arm_pattern(am, sb, src, a, decls)
    mut g := am.next
    while g != 0 {
      gm := deref(arm_p(g))
      if not fmt_same_value_arm_body(am, gm) { break }
      push_str(sb, " | ")
      fmt_emit_value_arm_pattern(gm, sb, src, a, decls)
      g = gm.next
    }
    push_str(sb, " => ")
    if am.body_stmts != 0 { panic("selfhost: fmt — braced match arm not modelled") }
    emit_fmt_expr(am.body, sb, src, a, decls)
    if am.wild == 2 { push_str(sb, " }") }
    first = false
    arm = g
  }
}

## Wrapped value-match arms: one arm per line, expression arms with a trailing comma, and a comptime
## template rendered as a real block even when its own header/body would fit on one line. OR-pattern
## continuations start one further level in, with `|` at the beginning of the continuation line.
emit_fmt_arms_multi := fn(arms_head : usize, indent : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  mut arm := arms_head
  while arm != 0 {
    am := deref(arm_p(arm))
    fmt_emit_spaces(sb, indent + 2)
    arm_mark := sb.len
    mut template_open : usize = 0
    if am.wild == 2 {
      fmt_emit_template_header(am, sb, src, ptr(template_open))
      push_str(sb, "\n")
      fmt_emit_spaces(sb, indent + 4)
      fmt_emit_template_pattern(am, template_open, sb, src)
    } else {
      fmt_emit_value_arm_pattern(am, sb, src, a, decls)
    }
    mut g := am.next
    if g != 0 {
      gm0 := deref(arm_p(g))
      if fmt_same_value_arm_body(am, gm0) {
        while g != 0 {
          gm := deref(arm_p(g))
          if not fmt_same_value_arm_body(am, gm) { break }
          push_str(sb, " | ")
          fmt_emit_value_arm_pattern(gm, sb, src, a, decls)
          g = gm.next
        }
        if fmt_open_line_cols(sb, arm_mark) > 100 {
          sb.len = arm_mark
          fmt_emit_value_arm_pattern(am, sb, src, a, decls)
          g = am.next
          while g != 0 {
            gm := deref(arm_p(g))
            if not fmt_same_value_arm_body(am, gm) { break }
            push_str(sb, "\n")
            fmt_emit_spaces(sb, indent + 4)
            push_str(sb, "| ")
            fmt_emit_value_arm_pattern(gm, sb, src, a, decls)
            g = gm.next
          }
        }
      }
    }
    if am.wild == 2 {
      push_str(sb, " => ")
      if am.body_stmts != 0 { panic("selfhost: fmt — braced comptime arm not modelled") }
      emit_fmt_expr_res(am.body, sb, src, a, decls, 1)
      push_str(sb, "\n")
      fmt_emit_spaces(sb, indent + 2)
      push_str(sb, "}\n")
    } else {
      push_str(sb, " => ")
      if am.body_stmts != 0 { panic("selfhost: fmt — braced match arm not modelled") }
      emit_fmt_expr_res(am.body, sb, src, a, decls, 1)
      push_str(sb, ",\n")
    }
    arm = g
  }
}

## Pretty-print `comptime match` arms — one per line, `<KindPattern> => {\n <stmts> \n}`. Kind patterns
## are `Struct(_)` / `Scalar(b, k)` / … (the kind name + binds) or `_`. Each arm's body is a BRACED
## statement block (unlike value-match's expr arms). Comptime template/var arms (wild 2/3) and a
## non-braced arm body (e.g. a nested `comptime match` directly as the arm value) are fail-loud —
## faithful formatting of those needs deeper comptime-shape handling.
## Verify the SOURCE shape of this one `comptime match`: the parser stores both `{ stmts }` and a
## bare one-statement arm body in `Arm.body_stmts`, so the nonzero pointer alone cannot distinguish
## them. Start at the AST scrutinee, find this match's opening brace, then inspect only `=>` tokens at
## the outer brace depth. A nested match is deeper and is ignored; braces in strings/chars/comments are
## skipped. Refuse if any arm is bare — emitting a brace around it would be a silent source rewrite.
fmt_comptime_match_arms_braced := fn(scrut : ptr(Expr), src : ptr(u8)) -> bool {
  start := fmt_expr_left_off(scrut, src)
  if start == 0 { return false }
  mut p := start
  mut paren : i64 = 0
  mut open : usize = 0
  mut looking := true
  while looking {
    b := bytes(str_at((src + p), 1))[0]
    if b == 0 { return false }
    if b == 34 or b == 39 {
      q := b
      p += 1
      mut quoted := true
      while quoted {
        c := bytes(str_at((src + p), 1))[0]
        if c == 0 { return false }
        if c == 92 { p += 2 }
        else if c == q { p += 1 ; quoted = false }
        else { p += 1 }
      }
    } else if b == 40 { paren += 1 ; p += 1 }
    else if b == 41 { if paren > 0 { paren -= 1 } ; p += 1 }
    else if b == 123 and paren == 0 { open = p ; looking = false }
    else { p += 1 }
  }
  mut depth : i64 = 1
  mut found := false
  p = open + 1
  while depth > 0 {
    b := bytes(str_at((src + p), 1))[0]
    if b == 0 { return false }
    if b == 34 or b == 39 {
      q := b
      p += 1
      mut quoted := true
      while quoted {
        c := bytes(str_at((src + p), 1))[0]
        if c == 0 { return false }
        if c == 92 { p += 2 }
        else if c == q { p += 1 ; quoted = false }
        else { p += 1 }
      }
    } else if b == 35 and bytes(str_at((src + p + 1), 1))[0] == 35 {
      while bytes(str_at((src + p), 1))[0] != 0 and bytes(str_at((src + p), 1))[0] != 10 { p += 1 }
    } else if b == 123 { depth += 1 ; p += 1 }
    else if b == 125 { depth -= 1 ; p += 1 }
    else if depth == 1 and b == 61 and bytes(str_at((src + p + 1), 1))[0] == 62 {
      found = true
      mut q := p + 2
      mut ws := true
      while ws {
        c := bytes(str_at((src + q), 1))[0]
        if c == 32 or c == 9 or c == 10 or c == 13 { q += 1 } else { ws = false }
      }
      if bytes(str_at((src + q), 1))[0] != 123 { return false }
      p += 2
    } else { p += 1 }
  }
  found
}

emit_fmt_comptime_arms := fn(arms_head : usize, scrut : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec), indent : usize, tparam : str) {
  if not fmt_comptime_match_arms_braced(scrut, src) { panic("selfhost: fmt — non-braced comptime match arm not modelled") }
  mut arm := arms_head
  while arm != 0 {
    am := deref(arm_p(arm))
    if am.wild >= 2 { panic("selfhost: fmt — comptime template/var match arm not modelled") }
    emit_indent(sb, indent)
    if am.wild == 1 { push_str(sb, "_") }
    if am.wild == 0 {
      push_str(sb, str_at((src + am.vs), am.vl))
      if unchecked bitcast(usize, am.binds_head) != 0 {
        push_str(sb, "(")
        mut b := am.binds_head
        mut bfirst := true
        while unchecked bitcast(usize, b) != 0 {
          if not bfirst { push_str(sb, ", ") }
          push_str(sb, str_at((src + bnd_ns(b)), bnd_nl(b)))
          bfirst = false
          b = bnd_next(b)
        }
        push_str(sb, ")")
      }
    }
    if am.body_stmts == 0 { panic("selfhost: fmt — non-braced comptime match arm not modelled") }
    push_str(sb, " => {\n")
    emit_fmt_stmts(am.body_stmts, am.body_stmts, sb, src, a, indent + 1, decls, tparam)
    emit_indent(sb, indent)
    push_str(sb, "}\n")
    arm = am.next
  }
}

## Pretty-print a STATEMENT-match's arm list (each body a braced statement block). The PATTERN follows
## the value-match form (variant `V(b0, …)` / integer literal / `_`); the body renders multi-line and
## indented (like `emit_fmt_comptime_arms`). A str-literal pattern (`wild == 4`) renders `"…"`; comptime
## template arms (`wild` 2) render the nested `comptime for`; var arms (`wild` 3) remain fail-loud.
emit_fmt_stmt_match_arms := fn(arms_head : usize, body_head : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec), indent : usize, tparam : str) {
  mut arm := arms_head
  while arm != 0 {
    am := deref(arm_p(arm))
    if am.wild == 3 { panic("selfhost: fmt — comptime statement-match var arm not modelled") }
    if am.wild == 2 {
      emit_indent(sb, indent + 1)
      push_str(sb, "comptime for ")
      push_str(sb, str_at((src + am.vs), am.vl))
      push_str(sb, " in typeinfo(")
      push_str(sb, tparam)
      push_str(sb, ").variants {\n")
      emit_indent(sb, indent + 2)
      push_str(sb, tparam)
      push_str(sb, ".(")
      push_str(sb, str_at((src + am.vs), am.vl))
      push_str(sb, ")")
      if unchecked bitcast(usize, am.binds_head) != 0 {
        push_str(sb, "(")
        mut cb := am.binds_head
        mut cbfirst := true
        while unchecked bitcast(usize, cb) != 0 {
          if not cbfirst { push_str(sb, ", ") }
          push_str(sb, str_at((src + bnd_ns(cb)), bnd_nl(cb)))
          cbfirst = false
          cb = bnd_next(cb)
        }
        push_str(sb, ")")
      }
      push_str(sb, " => {\n")
      emit_fmt_stmts(am.body_stmts, body_head, sb, src, a, indent + 3, decls, tparam)
      emit_indent(sb, indent + 2)
      push_str(sb, "}\n")
      emit_indent(sb, indent + 1)
      push_str(sb, "}\n")
    } else {
    emit_indent(sb, indent + 1)
    if am.wild == 1 { push_str(sb, "_") }
    if am.wild == 4 {
      ## STR-LITERAL pattern `"lit" => { … }` (§5.4): `am.lit` holds the `Expr::StrLit` node handle
      ## (recovered as a `ptr(Expr)`), rendered `"…"` by the StrLit arm — the statement-match twin of the
      ## value-match `emit_fmt_arms` str-pattern case.
      pat := unchecked bitcast(ptr(Expr), usize(am.lit))
      emit_fmt_expr(pat, sb, src, a, decls)
    }
    ## SCALAR RANGE patterns (§5.4): half-open `lo..hi` (wild 5) / inclusive `lo..=hi` (wild 6) — the
    ## statement-match twin of the value-match range case. Endpoints re-emit as decimal literals.
    if am.wild == 5 { push_int(sb, am.lit); push_str(sb, ".."); push_int(sb, am.hi) }
    if am.wild == 6 { push_int(sb, am.lit); push_str(sb, "..="); push_int(sb, am.hi) }
    if am.wild == 0 {
      if am.vl != 0 {
        push_str(sb, str_at((src + am.vs), am.vl))
        if unchecked bitcast(usize, am.binds_head) != 0 {
          push_str(sb, "(")
          mut b := am.binds_head
          mut bfirst := true
          while unchecked bitcast(usize, b) != 0 {
            if not bfirst { push_str(sb, ", ") }
            push_str(sb, str_at((src + bnd_ns(b)), bnd_nl(b)))
            bfirst = false
            b = bnd_next(b)
          }
          push_str(sb, ")")
        }
      } else {
        push_int(sb, am.lit)
      }
    }
    push_str(sb, " => {\n")
    emit_fmt_stmts(am.body_stmts, body_head, sb, src, a, indent + 2, decls, tparam)
    emit_indent(sb, indent + 1)
    push_str(sb, "}\n")
    }
    arm = am.next
  }
}

## Has the name `[ns, ns+nl)` been the target of an Assign STRICTLY BEFORE stmt handle `upto` in the
## list `head`? Drives the `:=` (first binding) vs `=` (reassignment) reconstruction — the parser
## erases the token, so fmt derives it canonically. Value-returning scan (no mutable set).
fmt_name_seen_before := fn(head : ptr(mut Stmt), upto : usize, ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> bool {
  mut s := head
  mut seen := false
  while s != 0 and s != upto {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => { if streq(src, ans, anl, ns, nl) { seen = true } ; s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(ex, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompIf(cc, cth, cel, nx) => { s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, iv, cb, nx) => { s = nx }
      ## control-flow / place-write statements bind no NEW top-level name — walk PAST them (follow `nx`)
      ## rather than halting the scan, so a binding AFTER one is still seen (correct `:=`/`=` choice).
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::DerefAssign(dp, dv, nx) => { s = nx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => { s = nx }
      Stmt::FieldPathAssign(pl, pv, nx) => { s = nx }
      Stmt::Loop(lb, nx) => { s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::Unchecked(ub, nx) => { s = nx }
      Stmt::AllocWith(ae, awb, nx) => { s = nx }
      _ => { s = 0 }
    }
  }
  seen
}

## Does the `@…` run starting at `p` belong to the local binding whose name starts at `name_s` — i.e.
## does it end exactly at the name, or at the `mut` marker immediately before it?
fmt_attr_run_reaches := fn(src : ptr(u8), p : usize, name_s : usize) -> bool {
  e := fmt_skip_attrs(src, p)
  if e == name_s { return true }
  if e + 3 > name_s { return false }
  if str_at((src + e), 3) != "mut" { return false }
  mut q := e + 3
  mut c := bytes(str_at((src + q), 1))[0]
  while q < name_s and (c == 32 or c == 9) { q += 1 ; c = bytes(str_at((src + q), 1))[0] }
  q == name_s
}

## A STATEMENT-level `@…` attribute run written before a LOCAL BINDING — today only the storage
## attribute `@alloc(a) x := init` (Memory §2.4). The parser DESUGARS it away into
## `x := alloc_into(a, init)` (or `alloc_into(isize, a, init)` for a bare literal) and records nothing,
## so fmt re-emitted the desugar: the `@alloc` marker vanished, and with it the base-allocator PRELUDE
## INJECTION it drives, so the reformatted file no longer resolved `alloc_into`/`get`/`arena_over` at
## all (`ambient_alloc_attr` / `ambient_alloc_scalar` / `ambient_alloc_deref_field` /
## `callfield_ptr_ret` / `serialize_roundtrip` each built before a reformat and failed after it).
## There is no faithful way to re-render the desugared call as the surface form, so the statement is
## copied VERBATIM from the `@` to the end of its own line (or to a top-level `;` / trailing `##`).
## When it does NOT end there — an unbalanced bracket at end of line — fmt REFUSES loudly rather than
## emit half a statement, because a wrong render here has no other way to announce itself.
## Returns the verbatim length with `out_s` at the `@`; 0 when the binding carries no attribute.
fmt_stmt_lead_attr := fn(src : ptr(u8), name_s : usize, out_s : ptr(mut usize)) -> usize {
  mut ls := name_s
  while ls > 0 and bytes(str_at((src + ls - 1), 1))[0] != 10 { ls -= 1 }
  ## The attribute must stand on this line AND its run must reach the name, so an `@` belonging to an
  ## earlier statement on the same line (`x := 1 ; @alloc(a) y := 2`) can never be picked up.
  mut s : usize = 0
  mut i := ls
  while i < name_s {
    if bytes(str_at((src + i), 1))[0] == 64 {
      if s == 0 { if fmt_attr_run_reaches(src, i, name_s) { s = i } }
    }
    i += 1
  }
  if s == 0 { return 0 }
  ## the statement text: from the `@` to end of line / top-level `;` / trailing `##`, brackets balanced
  mut j := s
  mut depth : i64 = 0
  mut stop : usize = 0
  while stop == 0 {
    b := bytes(str_at((src + j), 1))[0]
    if b == 0 or b == 10 { stop = j }
    else if b == 34 {                                                          ## '"' — skip a string
      j += 1
      while bytes(str_at((src + j), 1))[0] != 34 and bytes(str_at((src + j), 1))[0] != 0 {
        if bytes(str_at((src + j), 1))[0] == 92 { j += 1 }
        j += 1
      }
      j += 1
    }
    else if b == 40 or b == 91 or b == 123 { depth += 1 ; j += 1 }              ## '(' '[' '{'
    else if b == 41 or b == 93 or b == 125 { depth -= 1 ; j += 1 }              ## ')' ']' '}'
    else if b == 59 and depth == 0 { stop = j }                                 ## ';'
    else if b == 35 and depth == 0 { stop = j }                                 ## '#' — trailing comment
    else { j += 1 }
  }
  if depth != 0 { panic("selfhost: fmt — a `@…` statement attribute whose statement does not end on its own line (cannot be rendered faithfully)") }
  mut en := stop
  while en > s and (bytes(str_at((src + en - 1), 1))[0] == 32 or bytes(str_at((src + en - 1), 1))[0] == 9 or bytes(str_at((src + en - 1), 1))[0] == 13) { en -= 1 }
  if en <= s { return 0 }
  deref(out_s) = s
  en - s
}

## Did this Assign originate from the reassignment token `=` rather than a binding `:=` / `: T =`?
## Stmt.Assign erases that distinction, but the name's source span ends immediately before the token
## (modulo whitespace). Recovering it directly is scope-correct for nested blocks and match arms, where
## scanning only the enclosing fn body cannot distinguish an arm-local reassignment from a new binding.
fmt_local_is_reassign := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  end := p + 512
  mut c := str_at((src + p), 1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") {
    p += 1
    c = str_at((src + p), 1)
  }
  ## A COMPOUND assignment (`x -= 50`, `x *= 3`, spec §10) is DESUGARED by the parser into
  ## `Assign(x, Bin(-, x, 50))`, and the source at the name reads `-=`, not `=` — so the probe said
  ## "not seen before" and fmt re-emitted the statement as a fresh BINDING, `x := x - 50`, shadowing
  ## the mutable local instead of updating it (`compound_assign_ops` stopped compiling). ALL EIGHT
  ## compound spellings are reassignments too — and the set is `ast::compound_assign_op_at`'s, not a
  ## local list: this line used to name five of the eight, so `x &= 58` still rendered as the
  ## declaration `x := x & 58`. That predicate requires the second byte to be `=`, so a bare `x - 50`
  ## expression statement cannot match.
  if c == "=" { return true }
  return compound_assign_op_at(src, ns, nl).len != 0
}

## The RIGHT operand of a `Bin` value, or null for any other shape. Its own function because the
## `Stmt::Assign` arm must stay flat — a nested match/if-else there mis-lowers in a fn this big (the arm's
## own comment records it), so the destructuring lives out here. It is also the third of the `Bin`
## destructuring probes the §4.2.3 chain renderer needs (`fmt_is_bin` / `fmt_bin_op` / `fmt_bin_left`
## sit with the other single-match probes), for the same reason: a `match` nested inside a `match` arm.
## `if c { t } else { f }` as an EXPRESSION, in one of its two §4.2.3 spellings: `chain` false is the
## single-line form, `chain` true breaks the CONDITION before each of its operators at `ind + 2`
## columns (§4.2.3's operator-chain bullet) and leaves the braced arms on the last continuation line.
## An `else` whose whole content is another `if` is the `else if` CHAIN of Control Flow §4 and stays
## FLAT: re-braced as `} else { if … }` it becomes the LAST element of a block, which the parser
## classifies as an if-EXPRESSION, so pass 2 sees a different tree and renders it differently — that
## is what made fmt non-idempotent on six of the compiler's own modules. Worse, it is not even
## semantics-preserving: an arm that is a `deref(p) = v` store parses, in that position, as the bare
## place `deref(p)` and the store is silently LOST.
fmt_emit_if_expr := fn(c : ptr(Expr), t : ptr(Expr), f : ptr(Expr), chain : bool, multi : bool, ind : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  push_str(sb, "if ")
  if chain { fmt_emit_bin_chain(c, ind, sb, src, a, decls) }
  if not chain { emit_fmt_expr(c, sb, src, a, decls) }
  if multi {
    push_str(sb, " {\n")
    fmt_emit_spaces(sb, ind + 2)
    emit_fmt_expr(t, sb, src, a, decls)
    push_str(sb, "\n")
    fmt_emit_spaces(sb, ind)
    if fmt_expr_is_if(f) {
      push_str(sb, "} else ")
      match deref(f) {
        Expr::If(fc, ft, ff) => { fmt_emit_if_expr(fc, ft, ff, fmt_if_cond_chainable(fc), true, ind, sb, src, a, decls) }
        _ => { panic("selfhost: fmt — value-if chain shape disappeared during formatting") }
      }
    } else {
      push_str(sb, "} else {\n")
      fmt_emit_spaces(sb, ind + 2)
      emit_fmt_expr(f, sb, src, a, decls)
      push_str(sb, "\n")
      fmt_emit_spaces(sb, ind)
      push_str(sb, "}")
    }
  } else {
    push_str(sb, " { ")
    emit_fmt_expr(t, sb, src, a, decls)
    if fmt_expr_is_if(f) {
      push_str(sb, " } else ")
      emit_fmt_expr(f, sb, src, a, decls)
    } else {
      push_str(sb, " } else { ")
      emit_fmt_expr(f, sb, src, a, decls)
      push_str(sb, " }")
    }
  }
  return
}

## Can the CONDITION of an inline if-expression be re-rendered as a broken operator chain
## (§4.2.3, second bullet)? Only a `Bin` can, and not the unary `not` the parser stores as one
## (op 42). Everything else — a bare `Var`, a call, a comparison against a call — has no wrapped
## spelling the spec names, so the overflowing line is left as written rather than guessed at.
fmt_if_cond_chainable := fn(c : ptr(Expr)) -> bool {
  if not fmt_is_bin(c) { return false }
  i64(fmt_bin_op(c)) != 42
}

## True iff `e` is a value-`if` (`Expr::If`). Used to render an `else` whose whole content is
## another `if` as the FLAT `else if` chain (Control Flow §4) instead of a re-braced `else { if … }`.
fmt_expr_is_if := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::If(ic, it, ifa) => { r = true }
    _ => {}
  }
  r
}

## The `else` branch of a statement-`if`, when it is EXACTLY one `if` statement and nothing else —
## i.e. the `else if` the author wrote (Control Flow §4). Returns that `Stmt::If`, else 0.
## `Stmt::If`'s else field is a statement LIST, so "nothing else" is `nx == 0` on that one statement.
fmt_stmt_lone_if := fn(el : ptr(mut Stmt)) -> ptr(mut Stmt) {
  mut r := unchecked bitcast(ptr(mut Stmt), 0)
  if el == 0 { return r }
  ## Bind the `deref(<call>)` to a LOCAL before matching (the documented self-host lower limit — a
  ## `match deref(<call>)` scrutinee silently matches nothing, which is how this fix first no-oped).
  est := deref(stmt_p(Stmt, el))
  match est {
    Stmt::If(ic, ith, iel, inx) => { if inx == 0 { r = el } }
    _ => {}
  }
  r
}

## `if c { … } else if c2 { … } … else { … }` — one flat chain, written iteratively so the whole
## chain stays at ONE indent level. Rendering the chain as nested `else { if … }` blocks is what
## made fmt non-idempotent on six of the compiler's own modules (see `Expr::If` above): the nested
## `if` lands last in a block, re-parses as an if-EXPRESSION, and pass 2 renders it inline — and an
## arm that stores through a pointer silently loses the store on the way.
emit_fmt_if_chain := fn(c0 : ptr(Expr), th0 : ptr(mut Stmt), el0 : ptr(mut Stmt), body_head : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, indent : usize, decls : ptr(rt::Vec), tparam : str) {
  mut c := c0
  mut th := th0
  mut el := el0
  mut more := true
  emit_indent(sb, indent)
  push_str(sb, "if ")
  while more {
    more = false
    emit_fmt_expr(c, sb, src, a, decls)
    push_str(sb, " {\n")
    emit_fmt_stmts(th, body_head, sb, src, a, indent + 1, decls, tparam)
    emit_indent(sb, indent)
    if el == 0 { push_str(sb, "}\n") }
    if el != 0 {
      nested := fmt_stmt_lone_if(el)
      if nested != 0 {
        push_str(sb, "} else if ")
        more = true
        nst := deref(stmt_p(Stmt, nested))
        match nst {
          Stmt::If(nc, nth, nel, nnx) => {
            c = nc
            th = nth
            el = nel
          }
          _ => {}
        }
      }
      if nested == 0 {
        push_str(sb, "} else {\n")
        emit_fmt_stmts(el, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
      }
    }
  }
  return
}

fmt_bin_right := fn(v : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(v) {
    Expr::Bin(bop, bl, br) => { r = br }
    _ => {}
  }
  r
}

## The cleanup ACTION of a parser-synthesized `__defer(<expr>)` marker (the desugar of `defer <expr>`,
## Control Flow §9.3) — the inner expression, or 0 when `e` is any other expression. Rendering the
## marker literally would rewrite a user's `defer f()` into the compiler-internal `__defer(f())`.
fmt_defer_action := fn(e : ptr(Expr), src : ptr(u8)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      if cl == 7 and nn == 1 and str_at((src + cs), 7) == "__defer" { r = deref(arg_p(ah)).e }
    }
    _ => {}
  }
  r
}

## Is `e` the `__deferblk()` marker that OPENS the `defer { S1; S2 }` desugar chain (zero args)?
fmt_is_deferblk := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      if cl == 10 and nn == 0 and str_at((src + cs), 10) == "__deferblk" { r = true }
    }
    _ => {}
  }
  r
}

## Is `e` the `__deferblkend()` marker that CLOSES the `defer { … }` chain (zero args)?
fmt_is_deferblkend := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      if cl == 13 and nn == 0 and str_at((src + cs), 13) == "__deferblkend" { r = true }
    }
    _ => {}
  }
  r
}

## The `typeinfo(X)` ARGUMENT text of a `comptime for <v> in typeinfo(X).fields|.variants` header,
## recovered by a SOURCE-SCAN forward from the loop-var name span — the same recovery the LOWER does
## (`lower::compfor_iter_arg`) for the same reason: `Stmt::CompFor` keeps only the loop-var span, the
## fields/variants flag, the body and `next` (the seed's AST-node word budget), so the ITERATED TYPE
## is otherwise lost. fmt substituted the enclosing fn's TYPE-PARAMETER instead, which is wrong twice
## over: `comptime for f in typeinfo(B).fields` inside a `fn(T : type, …)` came back as
## `typeinfo(T).fields` (a SILENT rewrite to a different type), and at top level, where there is no
## type-param at all, fmt refused the whole file. Returns the argument length with `out_s` at its
## start; 0 when the header does not spell `in typeinfo(<type>)` (the caller then falls back).
fmt_compfor_iter_arg := fn(src : ptr(u8), vs : usize, vl : usize, out_s : ptr(mut usize)) -> usize {
  lim := vs + vl + 512
  mut p := vs + vl
  mut c := bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if str_at((src + p), 2) != "in" { return 0 }
  p += 2
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if str_at((src + p), 8) != "typeinfo" { return 0 }
  p += 8
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if bytes(str_at((src + p), 1))[0] != 40 { return 0 }                    ## '('
  p += 1
  c = bytes(str_at((src + p), 1))[0]
  while p < lim and (c == 32 or c == 9 or c == 10 or c == 13) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  ## the argument text runs to the `)` that closes the `typeinfo(` group — a type argument may itself
  ## carry parens (`typeinfo(Slice(u8))`), so the walk is depth-counted.
  mut e := p
  mut depth : i64 = 0
  mut scanning := true
  while scanning {
    b := bytes(str_at((src + e), 1))[0]
    if b == 0 or e >= lim { return 0 }
    else if b == 40 { depth += 1 ; e += 1 }
    else if b == 41 { if depth == 0 { scanning = false } else { depth -= 1 ; e += 1 } }
    else { e += 1 }
  }
  while e > p and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 10 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= p { return 0 }
  deref(out_s) = p
  e - p
}

## Pretty-print a statement list at `ind0`. `head` is the enclosing fn body (for `:=`/`=` scan).
##
## `extra` is the DEFER-BLOCK indent depth: `defer { S1; S2 }` desugars to a FLAT chain in THIS list
## (`__deferblk()` → S1 → S2 → `__deferblkend()`), so the block is rendered by shifting the statements
## between the two markers one level right — no sub-list, no recursion. Every arm below still reads
## `indent`, the per-iteration effective level.
emit_fmt_stmts := fn(list : ptr(mut Stmt), body_head : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, ind0 : usize, decls : ptr(rt::Vec), tparam : str) {
  mut s := list
  mut extra : usize = 0
  while s != 0 {
    indent := ind0 + extra
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        emit_indent(sb, indent)
        ## A RE-assignment (`name = v`) renders `=`; recover the erased token directly from source so
        ## nested block/arm locals remain scope-correct. A binding renders `:=`, UNLESS the source
        ## declares a type (`name : T = v`) — recover `T` from source
        ## (`local_type_span` returns 0/0 for both `:=` and `=`, so it fires only on a real `: T =`) and
        ## re-emit `name : T = v` so the annotation round-trips (was dropped → `name := v`). FLAT ifs
        ## (not nested if/else) — a big fn mis-lowers a nested if/else here (both branches fire).
        ## The `mut` binding qualifier is erased by the parser (front-end-only); recover it from source
        ## (`local_is_mut`) and re-emit it on the FIRST binding, else the reformatted local becomes
        ## IMMUTABLE and a later `name = …` reassignment is (correctly) rejected by sema-on-build.
        ## The NO-INITIALIZER form `mut xs : [A; 2]` (a reserved, uninitialized aggregate slot) is
        ## parsed as an ordinary Assign carrying a PLACEHOLDER value, so re-emitting `name : T = <value>`
        ## produced `mut xs : [A; 2] = 0` — a DIFFERENT program (the whole aggregate is initialized from
        ## a scalar 0, and the subsequent element writes land elsewhere: the deep-place fixture ran 65
        ## before and 1 after). `local_is_uninit` is the source metadata that recovers the distinction
        ## (the same probe lower/sema use); when it fires, emit the declaration WITHOUT an initializer.
        ## A STORAGE-ATTRIBUTE binding (`@alloc(ar) h := P(…)`) is DESUGARED by the parser into a
        ## plain `h := alloc_into(ar, P(…))` with the marker gone, so the AST cannot rebuild the surface
        ## form — copy the written statement VERBATIM (`fmt_stmt_lead_attr`) and skip the reconstruction
        ## below. Flat guards, not an if/else: a nested if/else in this arm mis-lowers (both branches
        ## fire) in a fn this big — the documented landmine the surrounding comment already warns about.
        mut sas : usize = 0
        sal := fmt_stmt_lead_attr(src, ans, ptr(sas))
        plain := sal == 0
        if sal != 0 { push_str(sb, str_at((src + sas), sal)) }
        seen := fmt_local_is_reassign(src, ans, anl)
        if plain and (not seen) and local_is_mut(src, ans) { push_str(sb, "mut ") }
        if plain { push_str(sb, str_at((src + ans), anl)) }
        lts := local_type_span(src, ans, anl)
        uninit := (not seen) and lts.n != 0 and local_is_uninit(src, ans, anl)
        ## Restore the written compound spelling (`x += 1`, `x &= 58`) instead of the desugared
        ## `x = x + 1`. Rendering the desugared shape is not a free choice of canonical form: Grammar §130
        ## line 287 defines the compound form as sugar with the place evaluated ONCE, so for a place with a
        ## side-effecting index (`a[f()] += 1`) the expanded spelling would evaluate it twice. All EIGHT
        ## glyphs come from `ast::compound_assign_op_at` — the private probe this replaced listed only
        ## four, so `x &= 58` lost its spelling AND (via `fmt_local_is_reassign`, which listed five)
        ## became the DECLARATION `x := x & 58`. BOTH conditions must hold: the source shows `op=` AND the
        ## value really is a `Bin`, so an unexpected shape falls back to the plain rendering.
        cop := compound_assign_op_at(src, ans, anl)
        mut crhs := unchecked bitcast(ptr(Expr), 0)
        if plain and seen and cop.len != 0 { crhs = fmt_bin_right(v) }
        compound := unchecked bitcast(usize, crhs) != 0
        if plain and seen and (not compound) { push_str(sb, " = ") }
        if plain and seen and compound { push_str(sb, " "); push_str(sb, cop); push_str(sb, "= ") }
        if plain and (not seen) and lts.n != 0 and (not uninit) { push_str(sb, " : "); push_str(sb, str_at((src + lts.s), lts.n)); push_str(sb, " = ") }
        if plain and uninit { push_str(sb, " : "); push_str(sb, str_at((src + lts.s), lts.n)) }
        if plain and (not seen) and lts.n == 0 { push_str(sb, " := ") }
        if plain and (not uninit) and (not compound) { emit_fmt_expr(v, sb, src, a, decls) }
        if plain and (not uninit) and compound { emit_fmt_expr(crhs, sb, src, a, decls) }
        push_str(sb, "\n")
        s = nx
      }
      Stmt::Return(rv, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "return ")
        emit_fmt_expr(rv, sb, src, a, decls)
        push_str(sb, "\n")
        s = nx
      }
      Stmt::ExprStmt(ex, nx) => {
        ## DEFER (§9.3): the parser desugars `defer <expr>` to the marker call `__defer(<expr>)` and
        ## `defer { S1; S2 }` to the flat chain `__deferblk()` → S1 → S2 → `__deferblkend()`, all of
        ## which STAY in this statement list. Re-emit the SURFACE form — rendering the markers literally
        ## rewrites the user's `defer` into compiler internals (round-trips only because the lower
        ## re-intercepts the marker names). FLAT ifs, not nested if/else (the documented big-fn landmine).
        dact := fmt_defer_action(ex, src)
        isblk := fmt_is_deferblk(ex, src)
        isend := fmt_is_deferblkend(ex, src)
        if unchecked bitcast(usize, dact) != 0 {
          emit_indent(sb, indent)
          push_str(sb, "defer ")
          emit_fmt_expr(dact, sb, src, a, decls)
          push_str(sb, "\n")
        }
        if isblk {
          emit_indent(sb, indent)
          push_str(sb, "defer {\n")
          extra = extra + 1
        }
        if isend {
          if extra == 0 { panic("selfhost: fmt — a `__deferblkend` marker with no open `defer {` (compiler invariant)") }
          extra = extra - 1
          emit_indent(sb, ind0 + extra)
          push_str(sb, "}\n")
        }
        if unchecked bitcast(usize, dact) == 0 and isblk == false and isend == false {
          emit_indent(sb, indent)
          emit_fmt_expr(ex, sb, src, a, decls)
          push_str(sb, "\n")
        }
        s = nx
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        emit_indent(sb, indent)
        push_str(sb, str_at((src + bns), bnl))
        push_str(sb, ".")
        push_str(sb, str_at((src + fns), fnl))
        ## FieldAssign carries the parser's desugared `Bin(field, rhs)` value, just like a local
        ## Assign. Recover the authored operator from the FIELD name span so `s.v op= e` stays a
        ## single-evaluation compound place rather than becoming `s.v = s.v op e`.
        cop := compound_assign_op_at(src, fns, fnl)
        mut crhs := unchecked bitcast(ptr(Expr), 0)
        if cop.len != 0 { crhs = fmt_bin_right(fv) }
        compound := unchecked bitcast(usize, crhs) != 0
        if compound {
          push_str(sb, " ")
          push_str(sb, cop)
          push_str(sb, "= ")
          emit_fmt_expr(crhs, sb, src, a, decls)
        } else {
          push_str(sb, " = ")
          emit_fmt_expr(fv, sb, src, a, decls)
        }
        push_str(sb, "\n")
        s = nx
      }
      Stmt::While(c, b, nx) => {
        emit_indent(sb, indent)
        emit_fmt_label(stmt_label_span(s), sb, src)
        push_str(sb, "while ")
        emit_fmt_expr(c, sb, src, a, decls)
        push_str(sb, " {\n")
        emit_fmt_stmts(b, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::If(c, th, el, nx) => {
        ## The whole `if / else if / … / else` CHAIN, flat at one indent (`emit_fmt_if_chain`).
        emit_fmt_if_chain(c, th, el, body_head, sb, src, a, indent, decls, tparam)
        s = nx
      }
      Stmt::Match(scrut, arms_head, nx) => {
        ## a STATEMENT-match: its arm bodies are BRACED statement blocks (that is what made the parser
        ## classify it a statement, not an expression), so it renders MULTI-LINE — the inline
        ## `emit_fmt_arms` (value-match, bare arms) would fail-loud on the braced bodies.
        emit_indent(sb, indent)
        push_str(sb, "match ")
        emit_fmt_expr(scrut, sb, src, a, decls)
        push_str(sb, " {\n")
        emit_fmt_stmt_match_arms(arms_head, body_head, sb, src, a, decls, indent, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "comptime match ")
        emit_fmt_expr(cmsc, sb, src, a, decls)
        push_str(sb, " {\n")
        emit_fmt_comptime_arms(cmah, cmsc, sb, src, a, decls, indent + 1, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::CompIf(cc, cthen, celse, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "comptime if ")
        emit_fmt_expr(cc, sb, src, a, decls)
        push_str(sb, " {\n")
        emit_fmt_stmts(cthen, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        if celse == 0 { push_str(sb, "}\n") } else {
          push_str(sb, "} else {\n")
          emit_fmt_stmts(celse, body_head, sb, src, a, indent + 1, decls, tparam)
          emit_indent(sb, indent)
          push_str(sb, "}\n")
        }
        s = nx
      }
      Stmt::CompFor(cvs, cvl, is_variants, cbody, nx) => {
        ## `comptime for <var> in typeinfo(<T>).fields|variants { body }` — the iterable is IMPLICIT in
        ## the node (only `is_variants` is stored); `T` is the enclosing fn's type-parameter, threaded
        ## in as `tparam`. Fail-loud if no type-param is in scope (can't reconstruct the iterable).
        ## The iterated type is recovered from the header text (`fmt_compfor_iter_arg`); the enclosing
        ## fn's type-param is only a FALLBACK, and when neither is available fmt refuses.
        mut cts : usize = 0
        ctl := fmt_compfor_iter_arg(src, cvs, cvl, ptr(cts))
        if ctl == 0 and tparam == "" { panic("selfhost: fmt — comptime for whose `typeinfo(...)` argument cannot be recovered and with no type-param in scope") }
        emit_indent(sb, indent)
        push_str(sb, "comptime for ")
        push_str(sb, str_at((src + cvs), cvl))
        push_str(sb, " in typeinfo(")
        if ctl != 0 { push_str(sb, str_at((src + cts), ctl)) }
        if ctl == 0 { push_str(sb, tparam) }
        push_str(sb, ")")
        if is_variants == 1 { push_str(sb, ".variants") } else { push_str(sb, ".fields") }
        push_str(sb, " {\n")
        emit_fmt_stmts(cbody, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rbody, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "comptime for ")
        push_str(sb, str_at((src + rvs), rvl))
        push_str(sb, " in ")
        emit_fmt_expr(rlo, sb, src, a, decls)
        ## a NULL hi is the pack-mode marker (`comptime for v in <pack>`, Functions §7.1) — no `.. hi`.
        if unchecked bitcast(usize, rhi) != 0 {
          push_str(sb, "..")
          emit_fmt_expr(rhi, sb, src, a, decls)
        }
        push_str(sb, " {\n")
        emit_fmt_stmts(rbody, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        emit_indent(sb, indent)
        emit_fmt_label(stmt_label_span(s), sb, src)
        push_str(sb, "for ")
        push_str(sb, str_at((src + fns), fnl))
        push_str(sb, " in ")
        emit_fmt_expr(flo, sb, src, a, decls)
        ## RANGE form `for i in lo .. hi` has a non-null `hi`; the ITERABLE form `for x in <slice>` has
        ## `hi == 0` (`lo` is the iterable) — mirrors the parser's two For shapes.
        if unchecked bitcast(usize, fhi) != 0 {
          push_str(sb, "..")
          emit_fmt_expr(fhi, sb, src, a, decls)
        }
        push_str(sb, " {\n")
        emit_fmt_stmts(fb, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::DerefAssign(dp, dv, nx) => {
        ## `deref(<ptr>) = <value>` — the store dual of the `Deref` read (the node carries the inner
        ## pointer expr, not the `deref(...)` wrapper, so re-add it).
        emit_indent(sb, indent)
        push_str(sb, "deref(")
        emit_fmt_expr(dp, sb, src, a, decls)
        push_str(sb, ") = ")
        emit_fmt_expr(dv, sb, src, a, decls)
        push_str(sb, "\n")
        s = nx
      }
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        ## `<base>[<index>] = <value>` — an array/nested-place element write; `base` is a `Var` or a
        ## `Field` place, both handled by `emit_fmt_expr`. A tuple-component write `t.N = v` /
        ## `t.N.M = v` lands here too, with the SAME node shape — `fmt_sep_is_dot` recovers which
        ## separator the source wrote (`t[1][0] = 20` is not a form the parser accepts back).
        emit_indent(sb, indent)
        emit_fmt_expr(ib, sb, src, a, decls)
        if fmt_sep_is_dot(ib, ii, src) {
          push_str(sb, ".")
          emit_fmt_expr(ii, sb, src, a, decls)
          push_str(sb, " = ")
        } else {
          push_str(sb, "[")
          emit_fmt_expr(ii, sb, src, a, decls)
          push_str(sb, "] = ")
        }
        emit_fmt_expr(iv, sb, src, a, decls)
        push_str(sb, "\n")
        s = nx
      }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => {
        ## `<base>[<index>].<field> = <value>` — an array-of-struct element-field write (or the tuple
        ## form `t.N.<field> = v`, hence the same separator recovery as `Stmt::IndexAssign`).
        emit_indent(sb, indent)
        emit_fmt_expr(fia, sb, src, a, decls)
        if fmt_sep_is_dot(fia, fii, src) {
          push_str(sb, ".")
          emit_fmt_expr(fii, sb, src, a, decls)
          push_str(sb, ".")
        } else {
          push_str(sb, "[")
          emit_fmt_expr(fii, sb, src, a, decls)
          push_str(sb, "].")
        }
        push_str(sb, str_at((src + ifs), ifl))
        push_str(sb, " = ")
        emit_fmt_expr(fiv, sb, src, a, decls)
        push_str(sb, "\n")
        s = nx
      }
      Stmt::FieldPathAssign(pl, pv, nx) => {
        ## `<place> = <value>` — a nested-field mutation `o.i.v = e`; the place is a nested `Field`
        ## expression that `emit_fmt_expr` renders in full.
        emit_indent(sb, indent)
        emit_fmt_expr(pl, sb, src, a, decls)
        push_str(sb, " = ")
        emit_fmt_expr(pv, sb, src, a, decls)
        push_str(sb, "\n")
        s = nx
      }
      Stmt::Loop(lb, nx) => {
        emit_indent(sb, indent)
        emit_fmt_label(stmt_label_span(s), sb, src)
        push_str(sb, "loop {\n")
        emit_fmt_stmts(lb, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::Break(bv, _bd, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "break")
        label := stmt_label_span(s)
        bvu := unchecked bitcast(usize, bv)
        if label.n != 0 {
          push_str(sb, " ")
          push_str(sb, str_at((src + label.s), label.n))
        }
        if bvu != 0 {
          push_str(sb, " ")
          emit_fmt_expr(bv, sb, src, a, decls)
        }
        push_str(sb, "\n")
        s = nx
      }
      Stmt::Continue(_cd, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "continue")
        label := stmt_label_span(s)
        if label.n != 0 {
          push_str(sb, " ")
          push_str(sb, str_at((src + label.s), label.n))
        }
        push_str(sb, "\n")
        s = nx
      }
      Stmt::Unchecked(ub, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "unchecked {\n")
        emit_fmt_stmts(ub, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      Stmt::AllocWith(ae, awb, nx) => {
        emit_indent(sb, indent)
        push_str(sb, "alloc::with(")
        emit_fmt_expr(ae, sb, src, a, decls)
        push_str(sb, ") {\n")
        emit_fmt_stmts(awb, body_head, sb, src, a, indent + 1, decls, tparam)
        emit_indent(sb, indent)
        push_str(sb, "}\n")
        s = nx
      }
      _ => { panic("selfhost: fmt — unsupported statement form") }
    }
  }
}

## FN-6 — the source length of a fn-VALUE type written at `[ts, ts+tl)`. The parser records such a type
## as the BARE HEAD TOKEN of an APPLIED type — `fn(u64) -> E` as `fn`, `ptr(mut R)` as `ptr`,
## `Slice(u64)` as `Slice` (the written type is re-read from source by every pass downstream, never
## stored) — so re-emitting the recorded span yields `f : fn` / `-> ptr`: a DIFFERENT program, silently
## (`test/fn_value_enum_ret` ran 42 before the reformat and 211 after). Widen the span over the balanced
## `( … )` group that IMMEDIATELY follows it, plus — for a fn TYPE only — a trailing `-> R`. Returns `tl`
## UNCHANGED whenever no group follows (a complete `u64` / a genuinely bare `fn`), so nothing else can be
## widened by accident. Used for the RETURN-type sites; a PARAMETER type is recovered from the parameter
## NAME instead (`fmt_param_type_span`), which also covers the head-less `[u64; 2]` / `dyn fn(…)` forms.
fmt_fnty_len := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if tl == 0 { return tl }
  ## A BRACKETED return type (`[u8]` slice sugar, `[u8; 4]`) is recorded as the bare `[` token, so
  ## re-emitting the recorded span printed `fn() -> [` — and then the body-vs-bodyless probe below
  ## looked for `{` right after it, found `u`, and declared the fn BODYLESS: fmt dropped the entire
  ## function body, and the second pass then re-read its own truncated output differently
  ## (`reject_codec_slice_sugar_return`). Widen to the balanced group, which is the written type.
  if str_at((src + ts), 1) == "[" {
    brk := skip_balanced_group(src, ts)
    if brk != 0 { return brk - ts }
  }
  mut p := ts + tl
  mut c := str_at((src + p), 1)
  while c == " " or c == "\t" { p += 1 ; c = str_at((src + p), 1) }
  if c != "(" { return tl }
  q := skip_balanced_group(src, p)
  if q == 0 { return tl }
  mut e := q
  mut r := q
  mut isfn := false
  if tl == 2 { if str_at((src + ts), 2) == "fn" { isfn = true } }
  c = str_at((src + r), 1)
  while c == " " or c == "\t" { r += 1 ; c = str_at((src + r), 1) }
  mut arrow := false
  if isfn { if str_at((src + r), 2) == "->" { arrow = true } }
  if arrow {
    r += 2
    mut depth := 0
    mut going := true
    while going {
      b := str_at((src + r), 1)
      if b == "" { going = false }
      if b == "(" or b == "[" { depth += 1 }
      if b == ")" or b == "]" {
        if depth == 0 { going = false } else { depth -= 1 }
      }
      if depth == 0 and (b == "," or b == "\n" or b == "{" or b == "#") { going = false }
      if going { r += 1 }
    }
    e = r
  }
  mut te := e
  mut trimming := true
  while trimming {
    if te > ts {
      lc := str_at((src + te - 1), 1)
      if lc == " " or lc == "\t" { te = te - 1 } else { trimming = false }
    } else { trimming = false }
  }
  te - ts
}

## The VERBATIM source text of a parameter's type annotation, recovered from the parameter's own NAME
## span (`name : <text>`), written to `out_s`/`out_n`; false when the parameter carries no `:` type.
##
## `Param.ts/tl` records only the type's HEAD TOKEN — `ptr(mut R)` is stored as `ptr`, `Slice(u64)` as
## `Slice`, `[u64; 2]` as `u64` (the ELEMENT), `dyn fn(u64) -> u64` as `dyn`, `fn(u64) -> E` as `fn` —
## because every pass downstream re-reads the written type from source. Re-emitting the recorded span
## therefore produced a DIFFERENT program, mostly SILENTLY: `p : ptr(mut Rec)` came back as `p : ptr`
## (test/deref_field_write ran 42 before the reformat and 0 after), `a : [u64; 2]` as a scalar `a : u64`,
## and `d : dyn fn(u64) -> u64` as the TWO parameters `d : dyn, fn : u64`. So scan the source instead —
## the same recovery `local_type_span` performs for a local binding: from the `:` to the depth-0 `,`/`)`
## that ends this parameter, which also carries a DEFAULT (`b : u64 = 3`) through verbatim.
fmt_param_type_span := fn(src : ptr(u8), ns : usize, nl : usize, out_s : ptr(mut usize), out_n : ptr(mut usize)) -> bool {
  mut p := ns + nl
  mut c := str_at((src + p), 1)
  while c == " " or c == "\t" or c == "\n" or c == "\r" { p += 1 ; c = str_at((src + p), 1) }
  if c != ":" { return false }
  p += 1
  c = str_at((src + p), 1)
  while c == " " or c == "\t" or c == "\n" or c == "\r" { p += 1 ; c = str_at((src + p), 1) }
  ts := p
  mut depth := 0
  mut going := true
  while going {
    b := str_at((src + p), 1)
    if b == "" { going = false }
    if b == "(" or b == "[" or b == "{" { depth += 1 }
    if b == ")" or b == "]" or b == "}" {
      if depth == 0 { going = false } else { depth -= 1 }
    }
    if depth == 0 and (b == "," or b == "\n" or b == "#") { going = false }
    if going { p += 1 }
  }
  mut te := p
  mut trimming := true
  while trimming {
    if te > ts {
      lc := str_at((src + te - 1), 1)
      if lc == " " or lc == "\t" or lc == "\r" { te = te - 1 } else { trimming = false }
    } else { trimming = false }
  }
  if te <= ts { return false }
  deref(out_s) = ts
  deref(out_n) = te - ts
  true
}

## The PASSING-MODE modifier written before a parameter name (`in out sb : …`, `out y : …`): 0 = none,
## 1 = `in`, 2 = `out`, 3 = `in out`. The parser erases it (it is front-end-only, like `mut` on a local),
## so fmt DROPPED it — turning an `out` parameter into a by-value one, a silent miscompile. Recovered by
## backward source-scan off the name, exactly like `local_is_mut`/`fmt_is_pub`; the token before a
## parameter name can only be `(`, `,`, or a modifier, so no false match is reachable.
## Is this parameter a COMPTIME VALUE parameter — `comptime N : u64` (Comptime §10 `comptime-param`)?
## The parser CONSUMES the keyword (`p_params`, `saw_ct`) and the `Param` node records only the name
## and type spans, so fmt dropped it and `@inline + := fn(comptime N : u64, a : uint(N), …)` came back
## with a RUNTIME `N`. That is a different declaration: the operator no longer routes by binding `N`
## from the operand, the `comptime for i in 0 .. N/64` ripple no longer folds, and `uint_generic_op`
## ran 42 before a reformat and SIGILL'd (132) after. Recovered from source the same way `in`/`out`
## are, with an identifier boundary so a name ending in "comptime" cannot false-match.
fmt_param_is_comptime := fn(src : ptr(u8), ns : usize) -> bool {
  mut p := ns
  while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
  if p < 8 { return false }
  if str_at((src + p - 8), 8) != "comptime" { return false }
  if p - 8 == 0 { return true }
  return fmt_is_ident_byte(bytes(str_at((src + p - 9), 1))[0]) == false
}

fmt_param_mode := fn(src : ptr(u8), ns : usize) -> usize {
  mut p := ns
  while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
  mut r : usize = 0
  if p >= 3 {
    if str_at((src + p - 3), 3) == "out" {
      r = 2
      p = p - 3
      while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
    }
  }
  if p >= 2 {
    if str_at((src + p - 2), 2) == "in" {
      if r == 2 { r = 3 }
      if r == 0 { r = 1 }
    }
  }
  r
}

## Emit a fn parameter list `(name : Type, …)` from `params_head`, applying §4.2.3: the single-line
## form first and — when its opening line overflows the 100-column soft maximum — the wrapped form,
## one parameter per line at one level in with a trailing comma and the `)` back at the opening line's
## indent. An EMPTY list is never wrapped (`()` has no elements to put on their own lines).
## `reserve` = the scalars the caller will still write on this line after the `)` — a signature's
## `-> R`. Without it the list's verdict is taken on a line that is not finished yet (see
## `fmt_wrap_needed_res`). It deliberately does NOT yet include the ` {` of a fn with a body, nor a
## `when` guard: both are recovered from source AFTER the return type, so counting them needs the
## guard scan hoisted above the parameter list. Under-counting only ever leaves a line long; it
## never wraps one that fits.
emit_fmt_params := fn(params_head : ptr(mut Param), reserve : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mark := sb.len
  ind := fmt_sb_indent(sb)
  fmt_emit_params_body(params_head, ind, false, sb, src, a)
  if params_head != 0 {
    if fmt_wrap_needed_res(sb, mark, reserve) { fmt_emit_params_body(params_head, ind, true, sb, src, a) }
  }
  return
}

## The parameter list itself, in either spelling (`multi` = the §4.2.3 wrapped form). ONE renderer with
## two spellings, so the `comptime` / `in` / `out` / `in out` markers and the type-span recovery below
## — every one of which a second copy could silently drop — are written exactly once.
fmt_emit_params_body := fn(params_head : ptr(mut Param), ind : usize, multi : bool, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  push_str(sb, "(")
  if multi { push_str(sb, "\n") }
  mut p := params_head
  mut first := true
  while p != 0 {
    pm := deref(param_p(p))
    if multi { fmt_emit_spaces(sb, ind + 2) }
    if not multi { if not first { push_str(sb, ", ") } }
    if fmt_param_is_comptime(src, pm.ns) { push_str(sb, "comptime ") }
    md := fmt_param_mode(src, pm.ns)
    if md == 1 { push_str(sb, "in ") }
    if md == 2 { push_str(sb, "out ") }
    if md == 3 { push_str(sb, "in out ") }
    push_str(sb, str_at((src + pm.ns), pm.nl))
    mut tys : usize = 0
    mut tyn : usize = 0
    scanned := fmt_param_type_span(src, pm.ns, pm.nl, ptr(tys), ptr(tyn))
    if scanned {
      push_str(sb, " : ")
      push_str(sb, str_at((src + tys), tyn))
    }
    if (not scanned) and pm.tl != 0 {
      push_str(sb, " : ")
      push_str(sb, str_at((src + pm.ts), fmt_fnty_len(src, pm.ts, pm.tl)))
    }
    ## FAIL-LOUD when the parsed list disagrees with the written one: this parameter's type text
    ## SWALLOWS the next parameter's name. That happens for a `dyn fn(u64) -> u64` parameter, which the
    ## front end splits into TWO parameters (`d : dyn` + `fn : u64`) — no rendering of that node list is
    ## the program the user wrote, so panic instead of emitting a guess (a wrong render is a silent
    ## miscompile of the source; a refused format is not). `dyn` in a LOCAL binding is unaffected.
    if scanned {
      if pm.next != 0 {
        nx := deref(param_p(pm.next))
        if nx.ns < tys + tyn { panic("selfhost: fmt — this parameter list does not round-trip: a parameter type overlaps the next parameter's name (a `dyn fn(…)` parameter is split in two by the front end)") }
      }
    }
    if multi { push_str(sb, ",\n") }
    first = false
    p = pm.next
  }
  if multi { fmt_emit_spaces(sb, ind) }
  push_str(sb, ")")
}

## Is `l` the next LINK of the binary-operator chain rooted at a `Bin` of precedence `pp`? A link is a
## `Bin` of the SAME precedence that needs no grouping parens — for equal precedence that means the
## parent is not a (non-associative) COMPARISON, since `(a < b) == c` has to keep its parens and is a
## grouped sub-expression, not a chain link. `not` (op 42, a unary prefix the parser stores as a `Bin`)
## is never a link. A DIFFERENT precedence ends the chain too: the `*` of `a * b + c` lives inside the
## `+` node's left operand, so it is a sub-expression that stays on its line and breaks only if that
## line still overflows — which is exactly §4.2.3's "an inner construct wraps only if it still
## overflows once the outer one has".
fmt_bin_chain_link := fn(l : ptr(Expr), pp : i64, pcmp : bool) -> bool {
  if pcmp { return false }
  if not fmt_is_bin(l) { return false }
  if i64(fmt_bin_op(l)) == 42 { return false }
  fmt_expr_prec(l) == pp
}

## The WRAPPED spelling of a binary-operator chain (§4.2.3, second bullet): the chain breaks BEFORE
## each of its operators, at the continuation indent (one level in), the operator BEGINNING the
## continuation line. The chain's first operand stays on the opening line; the left spine is walked by
## recursion, so `a + b + c` — which is `Bin(+, Bin(+, a, b), c)` — comes out with BOTH operators
## broken, not just the outer one.
##
## The parenthesization is the single-line arm's, character for character (`wrap_l` / `wrap_r` over
## `fmt_expr_prec`): the parser erases surface parens, so dropping one here would silently RE-GROUP the
## expression. A re-parse of the broken text rebuilds the identical left-leaning tree — grammar §2.6
## continues a line whose successor begins with a continuing token, verified for `+ - * == and` — which
## is what keeps the render idempotent.
fmt_emit_bin_chain := fn(e : ptr(Expr), ind : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  op := fmt_bin_op(e)
  l := fmt_bin_left(e)
  r := fmt_bin_right(e)
  pp := fmt_expr_prec(e)
  pcmp := fmt_is_cmp_op(op)
  if fmt_bin_chain_link(l, pp, pcmp) {
    fmt_emit_bin_chain(l, ind, sb, src, a, decls)
  } else {
    lp := fmt_expr_prec(l)
    wrap_l := lp < pp or (lp == pp and pcmp)
    if wrap_l { push_str(sb, "(") }
    emit_fmt_expr(l, sb, src, a, decls)
    if wrap_l { push_str(sb, ")") }
  }
  push_str(sb, "\n")
  fmt_emit_spaces(sb, ind + 2)
  ## bind the str-returning `fmt_op` to a LOCAL before forwarding it — an inline user str-returning
  ## call as a `str` argument mis-lowers under the seed (drops the length / faults).
  sym := fmt_op(op)
  push_str(sb, sym)
  push_str(sb, " ")
  rp := fmt_expr_prec(r)
  wrap_r := rp <= pp
  if wrap_r { push_str(sb, "(") }
  emit_fmt_expr(r, sb, src, a, decls)
  if wrap_r { push_str(sb, ")") }
}

## Emit the GENERIC type-parameter header `(T)` of a `Name(T) := struct/enum { … }` decl (the generic-
## struct/enum tier — ast::Decl `is_generic`, parsed+consumed by the parser's `skip_type_param`). The
## header sits between the decl NAME and the `:=`; the parser stores NO span for it (`params_head == 0`
## for a type decl), so — like `local_is_mut` / `fmt_is_pub` / the `: T` recovery in `emit_fmt_value` —
## fmt recovers it by SOURCE-SCAN. `enum_payload_len` already yields the balanced `( … )` span at/after
## an offset (its `out_open`/return pair), and for a generic decl the FIRST `(` past the name IS that
## header, so it is reused verbatim. Without this a generic type decl loses its `(T)` on format — fmt is
## NON-idempotent AND changes meaning (generic → non-generic). Emitted attached to the name (no gap).
emit_fmt_generic_header := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8)) {
  if d.is_generic {
    mut hopen : usize = 0
    hlen := enum_payload_len(src, d.name_start + d.name_len, ptr(hopen))
    if hlen != 0 { push_str(sb, str_at((src + hopen), hlen)) }
  }
}

## Consume the run of `@attr` / `@attr(args)` tokens starting at `p` (blanks and newlines between them
## are consumed too) and return the offset of the first byte that is NOT part of that run. `p` itself
## must already sit on the first non-blank byte. Shared by both attribute recoveries below.
fmt_skip_attrs := fn(src : ptr(u8), p : usize) -> usize {
  mut i := p
  mut scanning := true
  while scanning {
    if bytes(str_at((src + i), 1))[0] != 64 { scanning = false }                        ## '@'
    else {
      i += 1
      while fmt_is_ident_byte(bytes(str_at((src + i), 1))[0]) { i += 1 }
      if bytes(str_at((src + i), 1))[0] == 40 {                                         ## '(' — arg group
        past := skip_balanced_group(src, i)
        if past == 0 { scanning = false } else { i = past }
      }
      mut c := bytes(str_at((src + i), 1))[0]
      while c == 32 or c == 9 or c == 10 or c == 13 { i += 1 ; c = bytes(str_at((src + i), 1))[0] }
    }
  }
  i
}

## The `@…` ATTRIBUTE PREFIX a decl writes between its `:=` and the value that follows —
## `@abi(naked) fn(…)` (ABI §, `naked_add` / `raw_asm_*`), `@convert fn(…)` (Types §4.6, `convert_*`),
## `@require(pred) u32` (Types §8.1, `require_*`), `@inline fn(…)`. The parser consumes every one of
## them and leaves NOTHING on the `Decl`, so fmt dropped them all: a `@abi(naked)` fn came back as an
## ordinary fn (its hand-written prologue then ran with a compiler-generated one), a `@convert` fn
## stopped being the conversion `T(v)` resolves to, and `NonZero := @require(is_nonzero) u32` came back
## as a plain `u32` alias — each a link error or a different program. Recovered verbatim by source-scan.
## The `:=` search stops at a newline: a decl's `:=` always follows its name on the same line, and
## without the bound a decl that has NO `:=` (`x : T = v`) would run on into the NEXT decl's.
## Returns the prefix length with `out_s` set to its start; 0 when there is no attribute.
fmt_decl_attr_prefix := fn(src : ptr(u8), from : usize, out_s : ptr(mut usize)) -> usize {
  mut i := from
  mut found := false
  while found == false {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 or b == 10 { return 0 }
    if b == 58 and bytes(str_at((src + i + 1), 1))[0] == 61 { found = true } else { i += 1 }  ## ':' '='
  }
  mut p := i + 2
  mut c := bytes(str_at((src + p), 1))[0]
  while c == 32 or c == 9 or c == 10 or c == 13 { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if c != 64 { return 0 }                                                                     ## '@'
  s := p
  mut e := fmt_skip_attrs(src, p)
  while e > s and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 10 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= s { return 0 }
  deref(out_s) = s
  e - s
}

## The `when <predicate>` TAIL of a value binding — `bonus := 100 when target.arch == Arch.riscv64`
## (Comptime §7.1/§9, CT-5). Like the fn-decl guard it is consumed by the parser and recorded nowhere,
## so two arch-gated bindings of one name came back as an unguarded DUPLICATE (`check: duplicate
## name`). The tail runs to end of line; the scan starts past the binding `:=`/`=` and skips string
## literals, and the `when` must stand as its own token. Returns its length with `out_s` set to the
## `w`; 0 when the binding has no guard.
fmt_value_when_tail := fn(src : ptr(u8), from : usize, out_s : ptr(mut usize)) -> usize {
  mut i := from
  mut found := false
  while found == false {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 or b == 10 { return 0 }
    if b == 61 { found = true } else { i += 1 }                                       ## '='
  }
  mut p := i + 1
  mut ws : usize = 0
  mut hunting := true
  while hunting {
    b := bytes(str_at((src + p), 1))[0]
    if b == 0 or b == 10 { hunting = false }
    else if b == 34 {                                                                 ## '"' — skip a string
      p += 1
      while bytes(str_at((src + p), 1))[0] != 34 and bytes(str_at((src + p), 1))[0] != 0 {
        if bytes(str_at((src + p), 1))[0] == 92 { p += 1 }
        p += 1
      }
      p += 1
    } else if b == 35 { hunting = false }                                             ## '#' — a trailing comment
    else {
      if str_at((src + p), 4) == "when" {
        pb := bytes(str_at((src + p - 1), 1))[0]
        nb := bytes(str_at((src + p + 4), 1))[0]
        if (pb == 32 or pb == 9) and (nb == 32 or nb == 9) { ws = p ; hunting = false } else { p += 1 }
      } else { p += 1 }
    }
  }
  if ws == 0 { return 0 }
  mut e := ws
  while bytes(str_at((src + e), 1))[0] != 10 and bytes(str_at((src + e), 1))[0] != 0 and bytes(str_at((src + e), 1))[0] != 35 { e += 1 }
  while e > ws and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= ws { return 0 }
  deref(out_s) = ws
  e - ws
}

## A `when <predicate>` tail written AFTER a declaration's closing brace, on the same line —
## `Cfg := struct { a : u64 } when target.arch == Arch.x86_64` (Comptime §7.1/§9, CT-5). Dropped, two
## complementary arch-gated aggregates of one name came back as an unguarded DUPLICATE.
fmt_trailing_when := fn(src : ptr(u8), from : usize, out_s : ptr(mut usize)) -> usize {
  mut p := from
  mut c := bytes(str_at((src + p), 1))[0]
  while c == 32 or c == 9 { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if str_at((src + p), 4) != "when" { return 0 }
  nb := bytes(str_at((src + p + 4), 1))[0]
  if nb != 32 and nb != 9 { return 0 }
  mut e := p
  while bytes(str_at((src + e), 1))[0] != 10 and bytes(str_at((src + e), 1))[0] != 0 and bytes(str_at((src + e), 1))[0] != 35 { e += 1 }
  while e > p and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= p { return 0 }
  deref(out_s) = p
  e - p
}

## The VERBATIM right-hand side of a single-line declaration — from just past its `:=` to end of line
## (a trailing `##` comment and blanks trimmed). Used for the module/type ALIAS shape, where the AST
## keeps only a bare PATH span: `NonZero := u32.require(is_nonzero)` (the UFCS spelling of a validity
## contract, Types §8.1) came back as a plain `NonZero := u32` — the contract silently gone. Copying
## the written text is exact for every alias form and also carries a `when` guard tail along.
## Returns the length with `out_s` set to the RHS start; 0 when the `:=` is not on the name's line.
fmt_rhs_to_eol := fn(src : ptr(u8), from : usize, out_s : ptr(mut usize)) -> usize {
  mut i := from
  mut found := false
  while found == false {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 or b == 10 { return 0 }
    if b == 58 and bytes(str_at((src + i + 1), 1))[0] == 61 { found = true } else { i += 1 }  ## ':' '='
  }
  mut p := i + 2
  mut c := bytes(str_at((src + p), 1))[0]
  while c == 32 or c == 9 { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  mut e := p
  while bytes(str_at((src + e), 1))[0] != 10 and bytes(str_at((src + e), 1))[0] != 0 and bytes(str_at((src + e), 1))[0] != 35 { e += 1 }
  while e > p and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= p { return 0 }
  deref(out_s) = p
  e - p
}

## Is the source line `[ls, le)` (`le` just past its terminating newline) made up of NOTHING but a run
## of `@attr` / `@attr(args)` tokens? Used to decide whether an attribute line ABOVE a decl belongs to
## that decl. The check is deliberately strict — an argument group that runs past the line end, or any
## non-attribute byte, answers false and the attribute is left where it stands (fmt never guesses).
fmt_line_is_attrs_only := fn(src : ptr(u8), ls : usize, le : usize) -> bool {
  mut p := ls
  mut c := bytes(str_at((src + p), 1))[0]
  while p < le and (c == 32 or c == 9) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if p >= le { return false }
  if bytes(str_at((src + p), 1))[0] != 64 { return false }                                    ## '@'
  ## `@limits(…)` is NOT a declaration prefix — it is the translation unit's own limit-contract DECL
  ## (FND-10/11, parser `arity == 99`). Swallowing it as the next decl's prefix moved the directive
  ## onto that decl and left the marker decl to re-emit it, so the file grew a second `@limits` line
  ## every reformat. It is the one attribute that stands alone, so it is the one exclusion here.
  if str_at((src + p), 8) == "@limits(" { return false }
  mut ok := true
  mut scanning := true
  while scanning {
    if p >= le { scanning = false }
    else {
      b := bytes(str_at((src + p), 1))[0]
      if b == 64 {                                                                            ## '@'
        p += 1
        while p < le and fmt_is_ident_byte(bytes(str_at((src + p), 1))[0]) { p += 1 }
        if p < le and bytes(str_at((src + p), 1))[0] == 40 {                                  ## '(' — arg group
          past := skip_balanced_group(src, p)
          if past == 0 or past > le { ok = false ; scanning = false } else { p = past }
        }
      } else if b == 32 or b == 9 or b == 13 or b == 10 { p += 1 }
      else { ok = false ; scanning = false }
    }
  }
  ok
}

## The offset where a decl's LEADING attribute run may begin: the start of the decl's own line, walked
## back over any immediately preceding attribute-ONLY lines. Declarations §2.3 / Grammar §3.2 spell a
## declaration `{ modifier } binding` with `modifier ::= … | attribute` and put no newline restriction
## on it, so `@packed` on its own line above `Pfx := struct { … }` is the SAME declaration.
fmt_lead_attr_line_start := fn(src : ptr(u8), name_start : usize) -> usize {
  mut ls := name_start
  while ls > 0 and bytes(str_at((src + ls - 1), 1))[0] != 10 { ls -= 1 }
  mut scanning := true
  while scanning {
    if ls == 0 { scanning = false }
    else {
      mut ps := ls - 1                                                     ## the '\n' ending the line above
      while ps > 0 and bytes(str_at((src + ps - 1), 1))[0] != 10 { ps -= 1 }
      if fmt_line_is_attrs_only(src, ps, ls) { ls = ps } else { scanning = false }
    }
  }
  ls
}

## The `@…` attribute run written BEFORE a decl's name (`@export("shared_impl") producer := fn() …`,
## Modules §6.3). Same loss, different position: without it the symbol is never exported.
## The run may also stand on its OWN LINE(S) above the decl — `@packed` newline `Pk := struct { … }`
## (Declarations §2.3, Grammar §3.2). That spelling was ACCEPTED-and-IGNORED by the compiler until the
## layout lane started honouring it, at which point fmt began silently CORRUPTING it: `@packed` and
## `@align(16)` written this way were dropped and `attr_prefix_layout` ran 42 -> 2 after a reformat.
## Bounded by `fmt_lead_attr_line_start`, which only walks back over lines that are attributes and
## NOTHING else, so an attribute belonging to an earlier decl can never be picked up.
fmt_decl_lead_attr := fn(src : ptr(u8), name_start : usize, out_s : ptr(mut usize)) -> usize {
  ls := fmt_lead_attr_line_start(src, name_start)
  mut p := ls
  mut c := bytes(str_at((src + p), 1))[0]
  while p < name_start and (c == 32 or c == 9) { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  if p >= name_start { return 0 }
  if c != 64 { return 0 }                                                                     ## '@'
  s := p
  mut e := fmt_skip_attrs(src, p)
  if e > name_start { return 0 }
  while e > s and (bytes(str_at((src + e - 1), 1))[0] == 32 or bytes(str_at((src + e - 1), 1))[0] == 9 or bytes(str_at((src + e - 1), 1))[0] == 10 or bytes(str_at((src + e - 1), 1))[0] == 13) { e -= 1 }
  if e <= s { return 0 }
  deref(out_s) = s
  e - s
}

## The VERBATIM head of an aggregate decl — everything the source writes between the `:=` and the
## body's opening `{`. That is `struct` for a plain struct, but also `union` (Types §6.3 — an untagged
## overlap reuses the enum-shaped `Decl`, so nothing in the AST spells the keyword), `@packed struct`
## / `@align`-carrying / `@repr(i32) enum` (Types §8 — the layout attributes are consumed by the
## parser and left NOWHERE in the AST). Emitting the hard-coded keyword instead DROPPED all of them:
## `@packed struct { a : u8, b : u16, … }` came back as a naturally-aligned `struct` (a different
## LAYOUT — `packed_struct` ran 42 -> 1) and every `union { … }` came back as a tagged `struct`.
## Returns the head's byte length from `out_hs`, and the body `{`'s offset via `out_open`; 0 if the
## decl's `:=` or body brace cannot be located (caller keeps its previous hard-coded spelling).
fmt_agg_head := fn(src : ptr(u8), from : usize, out_hs : ptr(mut usize), out_open : ptr(mut usize)) -> usize {
  mut i := from
  mut found := false
  while found == false {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 { return 0 }
    if b == 58 and bytes(str_at((src + i + 1), 1))[0] == 61 { found = true } else { i += 1 }  ## ':' '='
  }
  mut p := i + 2
  mut c := bytes(str_at((src + p), 1))[0]
  while c == 32 or c == 9 or c == 10 or c == 13 { p += 1 ; c = bytes(str_at((src + p), 1))[0] }
  hs := p
  mut open := p
  mut looking := true
  while looking {
    b := bytes(str_at((src + open), 1))[0]
    if b == 0 { return 0 }
    if b == 123 { looking = false } else { open += 1 }                                        ## '{'
  }
  mut he := open
  while he > hs and (bytes(str_at((src + he - 1), 1))[0] == 32 or bytes(str_at((src + he - 1), 1))[0] == 9) { he -= 1 }
  if he <= hs { return 0 }
  deref(out_hs) = hs
  deref(out_open) = open
  he - hs
}

## The length of the balanced `{ … }` aggregate body opening at `open`, else 0. A dedicated scanner
## rather than `skip_balanced_group` because an aggregate body carries `##` COMMENTS, and the shared
## scanner treats `'` as a char-literal opener: an apostrophe in a comment (`## byte 8 (start of w) =
## w's MSB`) swallowed the rest of the body, the scan returned 0, and the caller fell back to the
## canonical rebuild — dropping the very `@offset`/`@endian` attributes it was there to preserve
## (`endian_offset_struct` ran 42 -> 2). Comments are skipped to end-of-line; strings are skipped
## honoring `\`; a member list holds no char literals, so `'` is an ordinary byte here.
fmt_agg_body_len := fn(src : ptr(u8), open : usize) -> usize {
  mut i := open
  mut depth := 0
  mut scanning := true
  mut r : usize = 0
  while scanning {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 { scanning = false }                                          ## EOF (malformed)
    else if b == 35 {                                                       ## '#' — comment to EOL
      while bytes(str_at((src + i), 1))[0] != 10 and bytes(str_at((src + i), 1))[0] != 0 { i += 1 }
    } else if b == 34 {                                                     ## '"' — string literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 34 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 40 or b == 91 or b == 123 { depth += 1 ; i += 1 }        ## '(' '[' '{'
    else if b == 41 or b == 93 or b == 125 {                                ## ')' ']' '}'
      depth -= 1
      i += 1
      if depth == 0 { r = i - open ; scanning = false }
    } else { i += 1 }
  }
  r
}

## Does the recovered head END in the aggregate keyword it is supposed to (`struct` / `enum` /
## `union`, possibly behind attributes)? When it does not, the decl is not the `Name := <kw> { … }`
## shape at all — a GENERIC TYPE FUNCTION `Tri := fn(A : type, B : type, C : type) -> type { return
## enum { First(A), … } }` is normalized by the parser into a generic ENUM decl whose fields are the
## variants, so rebuilding it canonically produced the nonsense `Tri(A : type, …) := fn(A : type, …)
## -> type { First(A), … }`, which no longer parsed at all. The caller emits such a decl VERBATIM.
fmt_head_is_agg := fn(src : ptr(u8), hs : usize, hlen : usize) -> bool {
  if hlen >= 6 { if str_at((src + hs + hlen - 6), 6) == "struct" { return true } }
  if hlen >= 4 { if str_at((src + hs + hlen - 4), 4) == "enum" { return true } }
  if hlen >= 5 { if str_at((src + hs + hlen - 5), 5) == "union" { return true } }
  false
}

## Can the aggregate BODY `{ … }` at `open` be reconstructed faithfully from the `FieldDecl` list?
## Only when it holds nothing but `name : Type` / `Variant(payload)` members: a `FieldDecl` records a
## name span, a type span and an arity, and NOTHING ELSE — so a member attribute (`@align(4) b : u32`),
## a field DEFAULT (`x : u64 = 40`, Types §9.4 — source-scanned at construction, never stored), an
## enum discriminant PIN (`A = 5`, Types §6.2 — the pin is re-scanned at `variant_index`) and an
## interleaved `##` comment all vanish on reconstruction. Rendering those back canonically is a SILENT
## MISCOMPILE (`enum_disc_pin` lost `B` entirely and ran 42 -> 0; `struct_field_default` 42 -> 1), so
## the caller copies such a body VERBATIM instead — not-formatting is always safe.
fmt_agg_body_is_plain := fn(src : ptr(u8), open : usize, blen : usize) -> bool {
  mut i := open
  mut r := true
  while i < open + blen {
    b := bytes(str_at((src + i), 1))[0]
    if b == 64 or b == 61 or b == 35 { r = false }                                  ## '@' '=' '#'
    i += 1
  }
  r
}

## `Name := struct { f0 : T0, f1 : T1 }` — one field per line, from the FieldDecl list. A GENERIC
## struct `Name(T) := struct { … }` keeps its `(T)` type-parameter header (recovered by source-scan).
## The `:=`-to-`{` head (`struct` / `@packed struct` / …) and any body the FieldDecl list cannot
## reproduce are copied VERBATIM from source — see `fmt_agg_head` / `fmt_agg_body_is_plain`.
emit_fmt_struct := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  mut hs : usize = 0
  mut open : usize = 0
  hlen := fmt_agg_head(src, d.name_start + d.name_len, ptr(hs), ptr(open))
  ## Not the `Name := <kw> { … }` shape at all — emit the whole decl verbatim (see `fmt_head_is_agg`).
  if hlen != 0 {
    if fmt_head_is_agg(src, hs, hlen) == false {
      vlen := fmt_agg_body_len(src, open)
      if vlen != 0 {
        push_str(sb, str_at((src + d.name_start), (open + vlen) - d.name_start))
        push_str(sb, "\n")
        return
      }
    }
  }
  push_str(sb, str_at((src + d.name_start), d.name_len))
  emit_fmt_generic_header(d, sb, src)
  push_str(sb, " := ")
  if hlen == 0 { push_str(sb, "struct") } else { push_str(sb, str_at((src + hs), hlen)) }
  mut blen : usize = 0
  if hlen != 0 { blen = fmt_agg_body_len(src, open) }
  ## a `when <predicate>` decl guard written after the closing brace (CT-5).
  mut wts : usize = 0
  mut wtl : usize = 0
  if blen != 0 { wtl = fmt_trailing_when(src, open + blen, ptr(wts)) }
  if blen != 0 and (fmt_agg_body_is_plain(src, open, blen) == false) {
    push_str(sb, " ")
    push_str(sb, str_at((src + open), blen))
    if wtl != 0 { push_str(sb, " ") ; push_str(sb, str_at((src + wts), wtl)) }
    push_str(sb, "\n")
    return
  }
  push_str(sb, " {\n")
  mut f := d.fields_head
  while f != 0 {
    fd := deref(fld_p(f))
    push_str(sb, "  ")
    ## the field's own `mut` marker — source-recovered, see `fmt_field_is_mut` (dropping it changes
    ## what a `typeinfo(T).fields` derive computes, i.e. what the program returns).
    if fmt_field_is_mut(src, fd.ns) { push_str(sb, "mut ") }
    push_str(sb, str_at((src + fd.ns), fd.nl))
    push_str(sb, " : ")
    push_str(sb, str_at((src + fd.ts), fd.tl))
    push_str(sb, ",\n")
    f = fd.next
  }
  push_str(sb, "}")
  if wtl != 0 { push_str(sb, " ") ; push_str(sb, str_at((src + wts), wtl)) }
  push_str(sb, "\n")
}

## `Name := enum { V0, V1(T) }` — one variant per line. A unit variant (arity 0) is a bare name; a
## single-payload variant (arity 1) prints `(T)`; a multi-payload variant is fail-loud (the FieldDecl
## records only one payload type span, so the others can't be faithfully reconstructed).
## The length of the balanced `( … )` payload group that starts at the FIRST `(` at/after `from` in
## `src` (including both parens), else 0. A multi-payload enum variant (`Bin(u8, ptr(Expr), ptr(Expr))`)
## stores only its arity + the FIRST payload type span in the FieldDecl, so fmt recovers the whole
## payload list VERBATIM from source (idempotent — re-fmt copies the same bytes). Skips a `"…"` literal
## defensively so a paren inside a string can't unbalance the scan (enum payloads are types, so a string
## is unusual, but the scanner stays honest). Returns the offset of the open paren via `out_open`.
enum_payload_len := fn(src : ptr(u8), from : usize, out_open : ptr(mut usize)) -> usize {
  mut i := from
  while bytes(str_at((src + i), 1))[0] != 40 and bytes(str_at((src + i), 1))[0] != 0 { i += 1 }  ## '(' = 40, 0 = EOF
  if bytes(str_at((src + i), 1))[0] != 40 { return 0 }
  open := i
  deref(out_open) = open
  mut depth := 0
  mut scanning := true
  mut result : usize = 0
  while scanning {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 { scanning = false }                                    ## ran off the end (malformed)
    else if b == 34 {                                                 ## '"' — skip a string literal
      i += 1
      while bytes(str_at((src + i), 1))[0] != 34 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }            ## '\' escapes the next byte
        i += 1
      }
      i += 1
    } else {
      if b == 40 { depth += 1 } else if b == 41 {                     ## ')' = 41
        depth -= 1
        if depth == 0 { result = i - open + 1 ; scanning = false }
      }
      i += 1
    }
  }
  return result
}

emit_fmt_enum := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  ## The `:=`-to-`{` head verbatim: an untagged `union` (Types §6.3) and a `@repr(i32) enum` (Types §8)
  ## ride this same enum-shaped `Decl`, and neither keyword/attribute survives into the AST.
  mut hs : usize = 0
  mut open : usize = 0
  hlen := fmt_agg_head(src, d.name_start + d.name_len, ptr(hs), ptr(open))
  ## A GENERIC TYPE FUNCTION (`Tri := fn(A : type, …) -> type { return enum { … } }`) is normalized
  ## into an enum-shaped decl and is NOT this shape — emit it verbatim (see `fmt_head_is_agg`).
  if hlen != 0 {
    if fmt_head_is_agg(src, hs, hlen) == false {
      vlen := fmt_agg_body_len(src, open)
      if vlen != 0 {
        push_str(sb, str_at((src + d.name_start), (open + vlen) - d.name_start))
        push_str(sb, "\n")
        return
      }
    }
  }
  push_str(sb, str_at((src + d.name_start), d.name_len))
  ## GENERIC enum `Name(T) := enum { … }` — keep its `(T)` type-parameter header (source-scan recovery).
  emit_fmt_generic_header(d, sb, src)
  push_str(sb, " := ")
  if hlen == 0 { push_str(sb, "enum") } else { push_str(sb, str_at((src + hs), hlen)) }
  mut blen : usize = 0
  if hlen != 0 { blen = fmt_agg_body_len(src, open) }
  ## a `when <predicate>` decl guard written after the closing brace (CT-5).
  mut wts : usize = 0
  mut wtl : usize = 0
  if blen != 0 { wtl = fmt_trailing_when(src, open + blen, ptr(wts)) }
  ## A discriminant PIN (`A = 5`) is re-scanned from source at emit and kept in no FieldDecl, so a
  ## canonical rebuild silently DROPS it (and, with it, every variant after the first pin) — copy
  ## such a body verbatim.
  if blen != 0 and (fmt_agg_body_is_plain(src, open, blen) == false) {
    push_str(sb, " ")
    push_str(sb, str_at((src + open), blen))
    if wtl != 0 { push_str(sb, " ") ; push_str(sb, str_at((src + wts), wtl)) }
    push_str(sb, "\n")
    return
  }
  push_str(sb, " {\n")
  mut f := d.fields_head
  while f != 0 {
    fd := deref(fld_p(f))
    push_str(sb, "  ")
    push_str(sb, str_at((src + fd.ns), fd.nl))
    if fd.arity == 1 {
      push_str(sb, "(")
      push_str(sb, str_at((src + fd.ts), fd.tl))
      push_str(sb, ")")
    } else if fd.arity > 1 {
      ## MULTI-payload variant — the FieldDecl kept only the arity + first type, so render the whole
      ## `( … )` payload group verbatim from source. Scan from the variant NAME start: the first `(`
      ## after it is the payload open (the name is an identifier, no parens), and the first payload
      ## type span `fd.ts` sits INSIDE those parens (so starting at `fd.ts` would miss the open).
      mut popen : usize = 0
      plen := enum_payload_len(src, fd.ns, ptr(popen))
      if plen == 0 { panic("selfhost: fmt — multi-payload enum variant payload not found in source") }
      push_str(sb, str_at((src + popen), plen))
    }
    push_str(sb, ",\n")
    f = fd.next
  }
  push_str(sb, "}")
  if wtl != 0 { push_str(sb, " ") ; push_str(sb, str_at((src + wts), wtl)) }
  push_str(sb, "\n")
}

## The NAME of the fn's first type-parameter (a param annotated `: type`), else "" — this is the `T`
## a `comptime for … in typeinfo(T).fields` / `comptime match typeinfo(T)` inside the body refers to
## (the node stores only the member kind, not `T`), so fmt threads it in to reconstruct the iterable.
fmt_type_param := fn(params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena) -> str {
  mut p := params_head
  mut r := ""
  mut found := false
  while p != 0 and (not found) {
    pm := deref(param_p(p))
    if pm.tl != 0 and str_at((src + pm.ts), pm.tl) == "type" { r = str_at((src + pm.ns), pm.nl) ; found = true }
    p = pm.next
  }
  r
}

## `Name := fn(params) -> R { body }`.
emit_fmt_fn := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  push_str(sb, str_at((src + d.name_start), d.name_len))
  push_str(sb, " := ")
  ## `@abi(naked)` / `@convert` / `@inline` — recovered verbatim (see `fmt_decl_attr_prefix`).
  mut aps : usize = 0
  apl := fmt_decl_attr_prefix(src, d.name_start + d.name_len, ptr(aps))
  if apl != 0 { push_str(sb, str_at((src + aps), apl)) ; push_str(sb, " ") }
  push_str(sb, "fn")
  ## `-> R` lands on this same line; count it into the list's verdict (§4.2.3 caps the LINE).
  mut fres : usize = 0
  if d.ret_tl != 0 { fres = 4 + fmt_str_scalars(str_at((src + d.ret_ts), fmt_fnty_len(src, d.ret_ts, d.ret_tl))) }
  emit_fmt_params(d.params_head, fres, sb, src, a)
  mut after_ret : usize = 0
  if d.ret_tl != 0 {
    push_str(sb, " -> ")
    ## `fmt_fnty_len`: a fn-VALUE return type is recorded as the bare `fn` token (FN-6); every other
    ## type comes back with its recorded length unchanged.
    rl := fmt_fnty_len(src, d.ret_ts, d.ret_tl)
    push_str(sb, str_at((src + d.ret_ts), rl))
    after_ret = d.ret_ts + rl
  }
  ## A BODYLESS declaration — `consumer := @extern("shared_impl") fn() -> u64` (Modules §6.3): the
  ## `Decl` looks like an ordinary fn with an empty body, so fmt gave it `{ 0 }`, DEFINING the symbol
  ## it was supposed to import (`extern_call` ran 42 -> 0). Decide from source: a real body opens with
  ## `{` after the return type. Only checked when a return type was written (otherwise the scan has no
  ## anchor and the previous always-a-body behaviour stands).
  if after_ret != 0 {
    mut k := after_ret
    mut c := bytes(str_at((src + k), 1))[0]
    while c == 32 or c == 9 or c == 10 or c == 13 { k += 1 ; c = bytes(str_at((src + k), 1))[0] }
    ## A `when <predicate>` GUARD (Comptime §7.1/§9, CT-4/CT-5) sits between the return type and the
    ## body and is recorded nowhere on the `Decl`. Dropping it made two guarded overloads of one name
    ## collapse into identical signatures — `check: duplicate name` on `when_predicate` / `when_guard`
    ## and friends. Copy it verbatim up to the body brace.
    if str_at((src + k), 4) == "when" {
      ## The BODY brace is the LAST `{…}` group of the decl: a predicate may itself hold one
      ## (`when match typeinfo(T) { Struct(_) => true; _ => false } { x }`), and stopping at the FIRST
      ## `{` truncated the guard mid-way — the render then no longer PARSED, and the second fmt pass
      ## segfaulted. Consume a balanced group whenever ANOTHER `{` follows it; the one that does not
      ## have a successor is the body.
      mut wend := 0
      mut i := k
      mut hunting := true
      while hunting {
        b := bytes(str_at((src + i), 1))[0]
        if b == 0 { hunting = false }
        else if b == 123 {                                                            ## '{'
          glen := fmt_agg_body_len(src, i)
          if glen == 0 { hunting = false } else {
            mut j := i + glen
            mut c2 := bytes(str_at((src + j), 1))[0]
            while c2 == 32 or c2 == 9 or c2 == 10 or c2 == 13 { j += 1 ; c2 = bytes(str_at((src + j), 1))[0] }
            if c2 == 123 { i = j } else { wend = i ; hunting = false }
          }
        } else { i += 1 }
      }
      if wend != 0 {
        mut we := wend
        while we > k and (bytes(str_at((src + we - 1), 1))[0] == 32 or bytes(str_at((src + we - 1), 1))[0] == 9 or bytes(str_at((src + we - 1), 1))[0] == 10 or bytes(str_at((src + we - 1), 1))[0] == 13) { we -= 1 }
        push_str(sb, " ")
        push_str(sb, str_at((src + k), we - k))
        c = 123
      }
    }
    if c != 123 { push_str(sb, "\n") ; return }                                       ## '{'
  }
  push_str(sb, " {\n")
  tp := fmt_type_param(d.params_head, src, a)
  emit_fmt_stmts(d.body_stmts, d.body_stmts, sb, src, a, 1, decls, tp)
  ## a bare trailing TAIL EXPRESSION (the fn's return value, no `return` keyword) lives in `value`,
  ## NOT in body_stmts — emit it as the last body line unless it is the no-tail sentinel.
  if not fmt_is_no_tail(d.value) {
    emit_indent(sb, 1)
    emit_fmt_expr(d.value, sb, src, a, decls)
    push_str(sb, "\n")
  }
  push_str(sb, "}\n")
}

## Pretty-print a top-level VALUE binding (kind 0): a constant `name := <value>` or a mutable global
## `mut name := <value>` (`ast::local_is_mut` recovers the `mut` the parser erased — the same source
## scan `is_module_mut_global` uses). The value is any surface expression (a literal, an enum/struct
## constructor, a `brand(…)`/path). `pub` is dropped (as `emit_fmt_fn` does — fmt is already lossy on
## `pub`). A TYPED top-level binding (`x : T = v`) reaches here too (the parser leaves `ret_tl == 0`
## for a kind-0 decl) and its `: T` annotation is recovered by source-scan; the `@limits` marker
## (`arity == 99`) is handled elsewhere / fail-loud.
emit_fmt_value := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  if ast::local_is_mut(src, d.name_start) { push_str(sb, "mut ") }
  push_str(sb, str_at((src + d.name_start), d.name_len))
  ## Recover a `: <type>` annotation the parser erased (a kind-0 decl keeps `ret_tl == 0` even when
  ## typed), by source-scanning after the name — so `X : u64 = 40` round-trips faithfully instead of
  ## being demoted to `X := 40` (which would also drop an `iN` signedness annotation). An inferred
  ## `:=` binding has no annotation. The type is read up to the binding `=` (so a multi-token type like
  ## `ptr(mut T)` is captured whole), then trailing whitespace trimmed. Same source-scan shape as
  ## `ast::local_is_mut` (the parser gives fmt no type span for kind-0 bindings).
  mut i := d.name_start + d.name_len
  mut go := true
  while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
  mut has_ty := false
  mut tstart := 0
  mut tend := 0
  if str_at((src + i), 1) == ":" {
    i = i + 1
    go = true
    while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
    if str_at((src + i), 1) != "=" {
      has_ty = true
      tstart = i
      go = true
      while go {
        c := str_at((src + i), 1)
        if c == "=" or c == "\n" or c == "" { go = false } else { i = i + 1 }
      }
      tend = i
      ## trim trailing whitespace before the `=` (nested ifs — a `while <cmp> and <fn-call>` mis-lowers)
      mut trimming := true
      while trimming {
        if tend > tstart {
          lc := str_at((src + tend - 1), 1)
          if lc == " " or lc == "\t" { tend = tend - 1 } else { trimming = false }
        } else { trimming = false }
      }
    }
  }
  if has_ty {
    push_str(sb, " : ")
    push_str(sb, str_at((src + tstart), tend - tstart))
    push_str(sb, " = ")
  } else {
    push_str(sb, " := ")
  }
  emit_fmt_expr(d.value, sb, src, a, decls)
  ## a `when <predicate>` binding guard (CT-5) — recovered verbatim, see `fmt_value_when_tail`.
  mut wts : usize = 0
  wtl := fmt_value_when_tail(src, d.name_start + d.name_len, ptr(wts))
  if wtl != 0 { push_str(sb, " ") ; push_str(sb, str_at((src + wts), wtl)) }
  push_str(sb, "\n")
}

## Pretty-print one top-level decl. Handles a `fn` (kind 1), `struct` (kind 2), `enum` (kind 3), and an
## value/const or mut-global binding (kind 0, typed or inferred — `emit_fmt_value` recovers a `: T`
## annotation by source-scan); the `@limits` marker, a type alias / import, and syscall/test decls are
## fail-loud. Sequential guarded dispatch (not an else-if chain — that mis-lowers as a fn body under the seed).
## `pub` VISIBILITY is not recorded on the `Decl` (the parser consumes the keyword), so recover it by
## SOURCE-SCAN: skip whitespace immediately before `name_start`; a `pub` token there (bounded by
## start-of-file or whitespace, so a name ending in "pub" does not false-match) means the decl is `pub`.
## Mirrors how emit_fmt_value recovers a `: T` annotation and `local_is_mut` recovers `mut`.
fmt_is_pub := fn(src : ptr(u8), name_start : usize) -> bool {
  if name_start < 4 { return false }
  mut p := name_start
  while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
  if p < 3 { return false }
  if str_at((src + p - 3), 3) != "pub" { return false }
  if p - 3 == 0 { return true }
  bc := str_at((src + p - 4), 1)
  return bc == " " or bc == "\n" or bc == "\t" or bc == "\r"
}
## The source offset where a decl's SYNTAX begins for comment-attachment purposes: the `pub` keyword
## position when the decl is `pub` (so a leading `## …` block above `pub name` still attaches — the
## comment→decl gap must be blank, and `pub` sits between name_start and the comment), else name_start.
fmt_decl_anchor := fn(src : ptr(u8), name_start : usize) -> usize {
  ## `@limits(...)` marker: name_start points at the first limit name INSIDE `@limits(` (8 chars), so a
  ## leading `## …` above `@limits(...)` sits before the `@` — anchor there so it attaches.
  if name_start >= 8 { if str_at((src + name_start - 8), 8) == "@limits(" { return name_start - 8 } }
  ## a `@test("…")` decl: `name_start` points INSIDE the description string, so a leading `## …` block
  ## above the `@test` sits before the `@` — anchor there so it attaches (same shape as `@limits`).
  mut tds : usize = 0
  if fmt_test_decl_start(src, name_start, ptr(tds)) { return tds }
  ## a MUTABLE global `mut G := …`: the `mut` marker sits between the comment block and `name_start`, so
  ## the gap was non-blank and a leading `## …` block above such a decl was DROPPED entirely (comment
  ## fidelity — the harness's comment-count check). Anchor at the `mut` token, exactly like `pub` below.
  mut anchor := name_start
  if local_is_mut(src, anchor) {
    mut q := anchor
    while q > 0 and (str_at((src + q - 1), 1) == " " or str_at((src + q - 1), 1) == "\n" or str_at((src + q - 1), 1) == "\t" or str_at((src + q - 1), 1) == "\r") { q = q - 1 }
    anchor = q - 3
  }
  if fmt_is_pub(src, anchor) {
    mut p := anchor
    while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
    anchor = p - 3   ## start of the `pub` token
  }
  ## a LEADING `@…` attribute run (possibly on its own line above the decl, Declarations §2.3) sits
  ## between the comment block and the name too — anchor at it so the block still attaches instead of
  ## being dropped for a non-blank gap.
  mut aps : usize = 0
  apl := fmt_decl_lead_attr(src, name_start, ptr(aps))
  if apl != 0 and aps < anchor { anchor = aps }
  anchor
}
## The `@test("…")` DECL start for a kind-5 test declaration whose description span starts at `ds`
## (TOOL-5). `@test("` is exactly 7 bytes, and the scan never enters the description itself, so a `@`
## inside the description text cannot be mistaken for the marker. Returns 0 when the shape is anything
## else (extra blanks around the `(`), and the caller then refuses rather than guess.
fmt_test_decl_start := fn(src : ptr(u8), ds : usize, out_s : ptr(mut usize)) -> bool {
  if ds < 7 { return false }
  if str_at((src + ds - 7), 6) != "@test(" { return false }
  if bytes(str_at((src + ds - 1), 1))[0] != 34 { return false }          ## the opening '"'
  deref(out_s) = ds - 7
  true
}

## The offset just PAST the body block of the declaration starting at `from`: the first `{` at or after
## `from` that is not inside a string or char literal, then its balanced close. 0 when there is none.
fmt_decl_body_end := fn(src : ptr(u8), from : usize) -> usize {
  mut i := from
  mut open : usize = 0
  mut hunting := true
  while hunting {
    b := bytes(str_at((src + i), 1))[0]
    if b == 0 { hunting = false }
    else if b == 34 {                                                    ## '"' — skip a string
      i += 1
      while bytes(str_at((src + i), 1))[0] != 34 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 39 {                                                  ## '\'' — skip a char
      i += 1
      while bytes(str_at((src + i), 1))[0] != 39 and bytes(str_at((src + i), 1))[0] != 0 {
        if bytes(str_at((src + i), 1))[0] == 92 { i += 1 }
        i += 1
      }
      i += 1
    } else if b == 123 { open = i ; hunting = false }                    ## '{'
    else { i += 1 }
  }
  if open == 0 { return 0 }
  skip_balanced_group(src, open)
}

emit_fmt_decl := fn(d : Decl, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) {
  ## `pub ` prefix for an exported decl (fn / struct / enum / value) — recovered by source-scan. The
  ## `@limits` marker (arity 99, below) is never `pub`, so it is excluded.
  isreal := (d.is_fn and d.kind == 1) or d.kind == 2 or d.kind == 3 or d.kind == 4 or (d.kind == 0 and d.arity != 99)
  ## An attribute written BEFORE the name (`@export("shared_impl") producer := fn() …`, Modules §6.3)
  ## is consumed by the parser and recorded nowhere — without it the symbol is never exported.
  if isreal {
    mut lps : usize = 0
    lpl := fmt_decl_lead_attr(src, d.name_start, ptr(lps))
    if lpl != 0 { push_str(sb, str_at((src + lps), lpl)) ; push_str(sb, " ") }
  }
  if isreal and fmt_is_pub(src, d.name_start) { push_str(sb, "pub ") }
  if d.is_fn and d.kind == 1 { emit_fmt_fn(d, sb, src, a, decls) ; return }
  if d.kind == 2 { emit_fmt_struct(d, sb, src, a, decls) ; return }
  if d.kind == 3 { emit_fmt_enum(d, sb, src, a, decls) ; return }
  if d.kind == 4 {
    ## `Name := @abi(syscall) fn(params) -> R` — a BODYLESS syscall-ABI trampoline decl (Stdlib §7 /
    ## ABI). Kind 4 is always the `syscall` selector (`@abi(naked)` parses as an ordinary kind-1 fn
    ## with a body). No body / no braces — just the signature. `emit_fmt_params` reconstructs the
    ## `(name : T, …)` list; the return type rides `ret_ts/ret_tl` like an ordinary fn.
    push_str(sb, str_at((src + d.name_start), d.name_len))
    push_str(sb, " := @abi(syscall) fn")
    mut sres : usize = 0
    if d.ret_tl != 0 { sres = 4 + fmt_str_scalars(str_at((src + d.ret_ts), fmt_fnty_len(src, d.ret_ts, d.ret_tl))) }
    emit_fmt_params(d.params_head, sres, sb, src, a)
    if d.ret_tl != 0 {
      push_str(sb, " -> ")
      push_str(sb, str_at((src + d.ret_ts), fmt_fnty_len(src, d.ret_ts, d.ret_tl)))
    }
    push_str(sb, "\n")
    return
  }
  if d.kind == 5 {
    ## `@test("desc") name := fn() -> R { … }` (TOOL-5) — a TEST declaration. The parser keeps the
    ## DESCRIPTION as the decl's "name", drops the binding name outright, and truncates the return
    ## type to its HEAD token (`Result` out of `Result(usize, str)`), so nothing in the AST can
    ## rebuild the declaration — fmt refused the whole FILE with "unsupported declaration kind", which
    ## is every file a user writes tests in. Copy it VERBATIM instead, from the `@` through the
    ## balanced end of the body: exact for every spelling, and it carries the body's `##` comments
    ## along. Still REFUSES (falls through to the loud panic) when either end cannot be located.
    mut ts : usize = 0
    if fmt_test_decl_start(src, d.name_start, ptr(ts)) {
      te := fmt_decl_body_end(src, ts)
      if te != 0 {
        push_str(sb, str_at((src + ts), te - ts))
        push_str(sb, "\n")
        return
      }
    }
  }
  if d.kind == 0 and d.arity == 99 {
    ## the `@limits(<list>)` marker decl (FND-10/11): its full limit list is retained in `ret_ts/ret_tl`
    ## (e.g. "no_alloc, no_comptime"), so it round-trips as `@limits(<list>)`. (A leading `##` comment does
    ## not yet attach to this decl: its `name_start` points at the first limit name INSIDE `@limits(`, so
    ## the comment→decl gap is non-blank — a follow-up; the directive text itself round-trips.)
    push_str(sb, "@limits(")
    push_str(sb, str_at((src + d.ret_ts), d.ret_tl))
    push_str(sb, ")\n")
    return
  }
  ## DESTRUCTURE import `(A, B, …) := mod` — a parse-only no-op decl whose names/path are dropped, but
  ## the parser retained the VERBATIM source span in `ret_ts/ret_tl` (name_len == 0 distinguishes it from
  ## a named module/type alias `name := path`, which the branch below renders). Emit it verbatim.
  if d.kind == 0 and d.arity != 99 and d.name_len == 0 and d.ret_tl != 0 {
    push_str(sb, str_at((src + d.ret_ts), d.ret_tl))
    push_str(sb, "\n")
    return
  }
  if d.kind == 0 and d.arity != 99 and d.ret_tl == 0 { emit_fmt_value(d, sb, src, a, decls) ; return }
  if d.kind == 0 and d.arity != 99 and d.ret_tl != 0 {
    ## MODULE / TYPE ALIAS import — `name := <path>` (`vec := alloc::vec`, `String := strbuf::StrBuf`;
    ## Modules § — no `use`). The parser records the RHS qualified path span in `ret_ts/ret_tl` and
    ## a `Num(0)` placeholder value; the path round-trips verbatim. Distinguished from a plain value
    ## binding (`ret_tl == 0`) and the `@limits` marker (`arity == 99`).
    push_str(sb, str_at((src + d.name_start), d.name_len))
    push_str(sb, " := ")
    ## The AST keeps only a bare PATH span, but the source line can hold more: a `@require(pred)`
    ## prefix or its UFCS spelling `u32.require(pred)` (Types §8.1 — dropped, the validity contract
    ## silently disappeared), or a `when` guard tail. Copy the written RHS verbatim; fall back to the
    ## recorded span only when the `:=` is not on the name's line.
    mut rhs : usize = 0
    rl := fmt_rhs_to_eol(src, d.name_start + d.name_len, ptr(rhs))
    if rl != 0 { push_str(sb, str_at((src + rhs), rl)) } else { push_str(sb, str_at((src + d.ret_ts), d.ret_tl)) }
    push_str(sb, "\n")
    return
  }
  panic("selfhost: fmt — unsupported declaration kind")
}

## Pretty-print a whole program: every top-level decl, blank line between.
## Pretty-print a whole program: each top-level decl preceded by its retained leading (`##`) comment
## block (from `comments`, a source-order (start,end) pair list — pass an empty Vec to drop comments),
## with a blank line between decls.
pub emit_fmt_program := fn(decls : ptr(rt::Vec), src : ptr(u8), in out sb : rt::StrBuf, a : rt::Arena, comments : ptr(rt::Vec)) {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    emit_leading_comments(src, comments, fmt_decl_anchor(src, d.name_start), sb)
    emit_fmt_decl(d, sb, src, a, decls)
    if i + 1 < cnt { push_str(sb, "\n") }
    i += 1
  }
}
