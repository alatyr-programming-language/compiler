## selfhost::lower::fnval — FN-6: calls through a function VALUE. The fn-type SOURCE re-scanner, the
## indirect-call return class (enum / struct / sret), the `fn`-typed struct field call, the expression-
## callee (`fs[i](x)`) resolver, and the float ARGUMENT masks all three of them need.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. That is what lets every UNQUALIFIED name it does not
## import — `streq`, `decl_get`, `decl_at`, `slot_of`, and the two emit-context globals `EMIT_BODY` /
## `EMIT_PARAMS` — bind `lower.al`'s OWN copy through the ancestor chain (Modules §3, privacy flows
## DOWN) rather than an unrelated module's same-named private duplicate.
##
## State: the seven `FNVR_*` memo globals move HERE with the band, because nothing outside it ever
## named them — that is the whole test for whether a global travels with its subsystem or stays in the
## parent. `EMIT_BODY`/`EMIT_PARAMS` stay in `src/lower.al`: `emit_fn` writes them and several of the
## parent's own scans read them, and §3 is one-way (a descendant may name an ancestor's private items,
## never the reverse).
##
## The seventeen externally-called entry points are re-imported into `lower.al` by BARE NAME
## (`(ind_call_ret_span, …) := fnval`), which leaves every call site unchanged and keeps the boundary
## `@inline`-transparent — a qualified `fnval::f(x)` site does NOT expand an `@inline` callee.
##
## NOTE the import ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a
## parse error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them — the
## same order `src/lower.al`'s own prologue uses. Keep it.
strbuf := rt
param_p := ast::param_p
stmt_p := ast::stmt_p
local_type_span := ast::local_type_span
(Arg, Expr, Stmt) := ast
(push_str, push_int) := strbuf
(CSpan, LCtx, arg_expr_at, var_name_span) := lower_ctx
(enum_decl_of, struct_decl_of, struct_words) := lower_layout

## ── FN-6 — the FLOAT RETURN CLASS of an INDIRECT call (through a function VALUE) ─────────────────
## The parser records only the bare `fn` TOKEN span for a fn-value type (`f : fn(f64) -> f64` → type
## text "fn"; the signature is deliberately discarded — see the fn-type parameter arm in `parser.al`),
## so every `call *%rax` site lowered its result with an UNCONDITIONAL `pushq %rax`, i.e. with NO
## return class at all. For an `f64`-returning fn value the SysV result lives in %xmm0, so the value
## stack captured whatever happened to sit in %rax — a SILENT 0 wherever the consumer was not itself a
## float op (`u64(h(10.5))` → 0, while `s + h(10.5)` was accidentally right because %xmm0 still held
## the result). The class is recovered here by SOURCE-SCANNING the fn type from the `fn` keyword the
## parser DID record (the established "re-read what the AST node dropped" idiom, as `local_type_span`
## does), or — when the value is bound straight to a named fn / a lifted lambda — from that callee's
## own `Decl`. Nothing in `src/` calls through a fn value, so every gate below is dormant for the
## self-host build and the emitted GAS is byte-identical (the TOOL-1 fixpoint holds).

## Skip spaces/newlines/tabs from `p0`, bounded by `lim`.
pub fnty_skip_ws := fn(src : ptr(u8), p0 : usize, lim : usize) -> usize {
  mut p := p0
  mut done := false
  while p < lim and done == false {
    c := str_at((src + p), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p + 1 } else { done = true }
  }
  p
}

## The offset just PAST the balanced parameter list `(…)` of the fn-value type whose `fn` keyword sits
## at `p0` — the anchor for the `-> R` tail. 0 when the text at `p0` is not a `fn (…)` type.
fnty_params_end := fn(src : ptr(u8), p0 : usize) -> usize {
  lim := p0 + 4096
  if str_at((src + p0), 2) != "fn" { return 0 }
  mut p := fnty_skip_ws(src, p0 + 2, lim)
  if str_at((src + p), 1) != "(" { return 0 }
  mut d := 0
  mut r := 0
  while p < lim {
    c := str_at((src + p), 1)
    if c == "(" { d = d + 1 }
    if c == ")" {
      if d > 0 { d = d - 1 }
      if d == 0 { r = p + 1; p = lim } else { p = p + 1 }
    } else { p = p + 1 }
  }
  r
}

## The end offset of a TYPE NAME starting at `p0` — the run of characters that is not whitespace or one
## of the type-text punctuators. A `mod::Type` tail stays whole (`:` is a name character here); a
## `ptr(u8)` / `Vec(T)` head stops at its `(`, which is all the float classification needs.
fnty_name_end := fn(src : ptr(u8), p0 : usize, lim : usize) -> usize {
  mut p := p0
  mut done := false
  while p < lim and done == false {
    c := str_at((src + p), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { done = true }
    if c == "(" or c == ")" or c == "," or c == "{" or c == "}" or c == "=" or c == ";" { done = true }
    if done == false { p = p + 1 }
  }
  p
}

## The RETURN-type name span of the fn-value type whose `fn` keyword sits at `p0` (`fn(…) -> R` → `R`).
## 0/0 when the text is not a fn type or declares no return.
pub fnty_ret_span := fn(src : ptr(u8), p0 : usize) -> CSpan {
  pe := fnty_params_end(src, p0)
  if pe == 0 { return CSpan(s = 0, n = 0) }
  lim := p0 + 4096
  mut p := fnty_skip_ws(src, pe, lim)
  if str_at((src + p), 2) != "->" { return CSpan(s = 0, n = 0) }
  p = fnty_skip_ws(src, p + 2, lim)
  e := fnty_name_end(src, p, lim)
  if e == p { return CSpan(s = 0, n = 0) }
  CSpan(s = p, n = e - p)
}

## A body binding's declaring NAME span + its right-hand side, for a name bound at the top level of the
## statement list `head`. Mirrors `block_decl_type`'s FLAT walk (`lower_stmt_nx` steps past every
## non-`Assign` statement). `nl == 0` when the name is not bound there.
BindInfo := struct { rhs : ptr(Expr), ns : usize, nl : usize }
body_binding := fn(head : ptr(mut Stmt), ns2 : usize, nl2 : usize, src : ptr(u8), a : rt::Arena) -> BindInfo {
  z := unchecked bitcast(ptr(Expr), 0)
  mut r := BindInfo(rhs = z, ns = 0, nl = 0)
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    mut isas := false
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        isas = true
        if streq(src, ans, anl, ns2, nl2) { r = BindInfo(rhs = v, ns = ans, nl = anl) }
        s = nx
      }
      _ => {}
    }
    if isas == false { s = lower_stmt_nx(s, a) }
  }
  r
}

## The index of the FUNCTION decl (kind 1) named `<ns,nl>`, or -1. (A fn VALUE binds to a plain named
## fn — `h := dblf` — so its return type is that decl's own.)
fn_decl_by_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> i64 {
  if nl == 0 { return 0 - 1 }
  cnt := rt::vec_len(deref(decls))
  mut res : i64 = 0 - 1
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, ns, nl) { res = i64(i) }
    i = i + 1
  }
  res
}

## The SOURCE offset of the `fn` keyword opening the DECLARED fn-value type of the name `<cs,cl>` — a
## parameter's `f : fn(…) -> R` (the parser kept the `fn` token span as the param type) or a local's
## `h : fn(…) -> R` annotation (a leading `dyn` is skipped: `d : dyn fn(…) -> R`). 0 = no annotation.
pub fnval_ty_pos := fn(cs : usize, cl : usize, src : ptr(u8), a : rt::Arena) -> usize {
  mut pc := EMIT_PARAMS
  mut pr := 0
  while pc != 0 {
    pm := deref(param_p(pc))
    if streq(src, pm.ns, pm.nl, cs, cl) and str_at((src + pm.ts), pm.tl) == "fn" { pr = pm.ts }
    pc = pm.next
  }
  if pr != 0 { return pr }
  if EMIT_BODY == 0 { return 0 }
  bi := body_binding(EMIT_BODY, cs, cl, src, a)
  if bi.nl == 0 { return 0 }
  lt := local_type_span(src, bi.ns, bi.nl)
  if lt.n < 2 { return 0 }
  mut p := lt.s
  if str_at((src + p), 3) == "dyn" { p = fnty_skip_ws(src, p + 3, p + 64) }
  if str_at((src + p), 2) != "fn" { return 0 }
  p
}

## The RETURN-type name span of the fn VALUE named `<cs,cl>` at an INDIRECT call site: from its declared
## fn type when it carries one, else from the `Decl` of the named fn (`h := dblf`) or the LIFTED LAMBDA
## (`f := fn(x : f64) -> f64 { … }`, an `Expr::FnRef`) the value is bound to. 0/0 = unresolvable.
## The decl index of the function a fn VALUE is BOUND to — `h := dblf` (a named fn) or `f := fn(x : f64)
## -> f64 { … }` (a lifted lambda, an `Expr::FnRef` RHS) — or -1 when there is no such direct binding
## (a parameter, a re-assigned value, a fn value read out of a container).
fnval_target_decl := fn(cs : usize, cl : usize, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  if EMIT_BODY == 0 { return 0 - 1 }
  bi := body_binding(EMIT_BODY, cs, cl, src, a)
  if bi.nl == 0 { return 0 - 1 }
  fr := fnref_info(bi.rhs)
  if fr.is_r { return lam_idx_by_fnpos(decls, fr.fnpos) }
  vn := var_name_span(bi.rhs)
  fn_decl_by_span(decls, src, vn.s, vn.n)
}

fnval_ret_ty := fn(cs : usize, cl : usize, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  tp := fnval_ty_pos(cs, cl, src, a)
  if tp != 0 { return fnty_ret_span(src, tp) }
  di := fnval_target_decl(cs, cl, decls, src, a)
  if di < 0 { return CSpan(s = 0, n = 0) }
  fd := deref(decl_get(decls, usize(di)))
  CSpan(s = fd.ret_ts, n = fd.ret_tl)
}

## The RETURN-type name span of an INDIRECT call — `f(args)` where `f` names a fn VALUE (a local/param
## holding a code pointer) rather than a declared fn. 0/0 for an ordinary named call (`ret_call_target`
## resolves that) and for an unresolvable fn value. This is what gives an indirect call a RETURN CLASS:
## the enum / struct / WIDE-struct(sret) classifiers below consult it after their direct decl lookup
## fails, so an aggregate-returning fn value is BOUND and RECEIVED exactly like the direct call it
## forwards to. Without a class the result rode the scalar `pushq %rax` convention: an enum result
## dispatched on a garbage word (a SILENT miscompile) and a wide-struct result never got its hidden
## result pointer (a SEGFAULT — the callee wrote through whatever %rdi held).
## NEUTRAL: gated on `ret_call_target < 0`, so every named call answers exactly as before; `src/`+`lib/`
## make no indirect call at all, so the self-host GAS is byte-identical (the TOOL-1 fixpoint holds).
## ONE-ENTRY MEMO for `ind_call_ret_span`. The classifiers below ask about the SAME call expression
## back to back (`struct_ret_call`, then `sret_ret_call`, then `call_ret_struct_span`, …), and each
## resolution walks the enclosing body's bindings (`body_binding`) twice. The call-site name span
## `<cs,cl>` is unique per source position, so it plus the enclosing fn (`EMIT_BODY`/`EMIT_PARAMS`,
## the only other inputs) is an EXACT key — the memo changes no answer, only the cost. Without it the
## self-build paid the walk ~6× per builtin/intrinsic call (`u64(x)`, `panic(m)`, `byte_at(…)` — the
## bulk of the calls whose name resolves to no fn decl).
mut FNVR_BODY : usize = 0
mut FNVR_PARAMS : usize = 0
mut FNVR_CS : usize = 0
mut FNVR_CL : usize = 0
mut FNVR_S : usize = 0
mut FNVR_N : usize = 0
mut FNVR_OK : bool = false

pub ind_call_ret_span := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  mut res := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => {
      if FNVR_OK and FNVR_BODY == EMIT_BODY and FNVR_PARAMS == EMIT_PARAMS and FNVR_CS == cs and FNVR_CL == cl {
        return CSpan(s = FNVR_S, n = FNVR_N)
      }
      if ret_call_target(decls, src, cs, cl, nargs, args_head, a) < 0 {
        res = fnval_ret_ty(cs, cl, decls, src, a)
      }
      FNVR_OK = true
      FNVR_BODY = EMIT_BODY
      FNVR_PARAMS = EMIT_PARAMS
      FNVR_CS = cs
      FNVR_CL = cl
      FNVR_S = res.s
      FNVR_N = res.n
    }
    _ => {}
  }
  res
}

## Does the INDIRECT call `e` return an ENUM? (the fn-value dual of `fn_returns_enum`.)
pub ind_call_ret_enum := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> bool {
  rs := ind_call_ret_span(e, decls, src, a)
  if rs.n == 0 { return false }
  enum_decl_of(decls, src, rs.s, rs.n) >= 0
}

## The WORD COUNT of the STRUCT an INDIRECT call returns, or 0 when it does not return a declared
## struct. 1..7 words ride the register-return convention (`emit_retreg`), >= 8 take SRET.
pub ind_call_ret_struct_words := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  rs := ind_call_ret_span(e, decls, src, a)
  if rs.n == 0 { return 0 }
  if struct_decl_of(decls, src, rs.s, rs.n) < 0 { return 0 }
  struct_words(decls, src, rs.s, rs.n, a)
}

## FN-10 dual of `ind_call_ret_span`: the RETURN-type span of a member call `o.g(args)` routed through
## a fn-VALUE STRUCT FIELD (the parser's UFCS desugar `Call(g, [o, args…])`). The field's DECLARED type
## text IS a real `fn(…) -> R` span (the parser keeps a field's type verbatim), so it reads straight
## off it — no source recovery needed. Needs `cx` for the receiver's slot, so it is consulted only by
## the `cx`-carrying enum classifiers (the emit-time `match o.g(x)` path); a fn-value field call BOUND
## to a local (`p := o.g(x)`) is resolved before slots exist and stays fail-loud in `check`.
## 0/0 for an ordinary named call / non-fn-typed field → `src/`+`lib/` (no fn-typed field) unchanged.
pub fnfield_call_ret_span := fn(e : ptr(Expr), cx : ptr(LCtx)) -> CSpan {
  a := arena_of(cx)
  mut res := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => {
      if nargs >= 1 and ret_call_target(cx.decls, cx.src, cs, cl, nargs, args_head, a) < 0 {
        a0 := arg_expr_at(args_head, 0, a)
        if fn_field_call_slot(a0, cs, cl, cx) >= 0 {
          fts := fn_field_ty_span(a0, cs, cl, cx)
          if fts.n >= 3 { res = fnty_ret_span(cx.src, fts.s) }
        }
      }
    }
    _ => {}
  }
  res
}

## Does the member call `o.g(args)` through a fn-VALUE STRUCT FIELD return an ENUM?
pub fnfield_call_ret_enum := fn(e : ptr(Expr), cx : ptr(LCtx)) -> bool {
  rs := fnfield_call_ret_span(e, cx)
  if rs.n == 0 { return false }
  enum_decl_of(cx.decls, cx.src, rs.s, rs.n) >= 0
}

## Is the type named `<ts,tl>` an `f64`/`f32` — after substituting the enclosing generic INSTANCE's type
## argument for its type-parameter name (`f : fn(T) -> T` inside `twice(f64, …)` returns `f64`)?
ty_is_float_sub := fn(ts : usize, tl : usize, cx : ptr(LCtx)) -> bool {
  if tl == 0 { return false }
  mut s := ts
  mut n := tl
  if cx.gp_l != 0 and cx.it_l != 0 and streq(cx.src, s, n, cx.gp_s, cx.gp_l) { s = cx.it_s; n = cx.it_l }
  if cx.gp2_l != 0 and cx.it2_l != 0 and streq(cx.src, s, n, cx.gp2_s, cx.gp2_l) { s = cx.it2_s; n = cx.it2_l }
  if cx.gp3_l != 0 and cx.it3_l != 0 and streq(cx.src, s, n, cx.gp3_s, cx.gp3_l) { s = cx.it3_s; n = cx.it3_l }
  tn := str_at((cx.src + s), n)
  tn == "f64" or tn == "f32"
}

## Does the INDIRECT call through the fn VALUE named `<cs,cl>` return an `f64`/`f32`? Drives BOTH the
## result capture at the three `call *%rax` sites (%xmm0 → the value stack) and `is_float_expr` (so a
## surrounding `u64(…)` truncates the float instead of reading its raw bits as an integer).
pub fnval_call_ret_float := fn(cs : usize, cl : usize, cx : ptr(LCtx)) -> bool {
  rts := fnval_ret_ty(cs, cl, cx.decls, cx.src, arena_of(cx))
  ty_is_float_sub(rts.s, rts.n, cx)
}

## The TYPE text span of the `idx`-th parameter of the fn-value type whose `fn` keyword sits at `p0`.
## The parameter list is split at its depth-1 commas; each slot reads `[name :] T` (a bare `fn(f64)`
## slot names no parameter). 0/0 when the slot does not exist.
fnty_param_span := fn(src : ptr(u8), p0 : usize, idx : usize) -> CSpan {
  lim := p0 + 4096
  if str_at((src + p0), 2) != "fn" { return CSpan(s = 0, n = 0) }
  mut p := fnty_skip_ws(src, p0 + 2, lim)
  if str_at((src + p), 1) != "(" { return CSpan(s = 0, n = 0) }
  p = p + 1
  mut d := 1
  mut k := 0
  mut ss := p
  mut rs := 0
  mut rn := 0
  mut fin := false
  while p < lim and fin == false {
    c := str_at((src + p), 1)
    if c == "(" { d = d + 1 }
    mut bnd := false
    if c == ")" {
      if d > 0 { d = d - 1 }
      if d == 0 { bnd = true; fin = true }
    }
    if c == "," and d == 1 { bnd = true }
    if bnd {
      if k == idx { rs = ss; rn = p - ss }
      k = k + 1
      ss = p + 1
    }
    p = p + 1
  }
  if rn == 0 { return CSpan(s = 0, n = 0) }
  fnty_slot_ty(src, rs, rn)
}

## The TYPE HEAD of one parameter slot `[name :] T` of a fn-value type: drop a leading `name :` binder
## (a `::` is a qualified-name separator, never a binder), trim the surrounding whitespace, and keep the
## head name (a `ptr(u8)` / `Vec(T)` argument list is cut — the float classification needs only the head).
fnty_slot_ty := fn(src : ptr(u8), s : usize, n : usize) -> CSpan {
  mut b := s
  mut e := s + n
  mut p := b
  mut d := 0
  mut cut := 0
  while p < e {
    c := str_at((src + p), 1)
    if c == "(" { d = d + 1 }
    if c == ")" {
      if d > 0 { d = d - 1 }
    }
    if c == ":" and d == 0 {
      if str_at((src + p + 1), 1) == ":" { p = p + 1 } else {
        if cut == 0 { cut = p + 1 }
      }
    }
    p = p + 1
  }
  if cut != 0 { b = cut }
  b = fnty_skip_ws(src, b, e)
  mut trimmed := false
  while e > b and trimmed == false {
    c2 := str_at((src + e - 1), 1)
    if c2 == " " or c2 == "\n" or c2 == "\t" or c2 == "\r" { e = e - 1 } else { trimmed = true }
  }
  if e <= b { return CSpan(s = 0, n = 0) }
  he := fnty_name_end(src, b, e)
  CSpan(s = b, n = he - b)
}

## The float-ARGUMENT mask of the fn VALUE named `<cs,cl>`: bit k set = its k-th parameter is an
## `f64`/`f32`, i.e. an SSE argument. Resolved from the value's declared fn type when it carries one
## (`fnty_param_span` re-reads the signature the parser dropped), else from the parameter list of the
## named fn / lifted lambda it is bound to. 0 = all-integer or unresolvable — which keeps the
## byte-identical all-GPR argument routing, exactly as before this classification existed.
pub fnval_param_fmask := fn(cs : usize, cl : usize, cx : ptr(LCtx)) -> usize {
  a := arena_of(cx)
  tp := fnval_ty_pos(cs, cl, cx.src, a)
  mut m := 0
  mut bit := 1
  if tp != 0 {
    mut i := 0
    while i < 6 {
      ps := fnty_param_span(cx.src, tp, i)
      if ps.n != 0 and ty_is_float_sub(ps.s, ps.n, cx) { m = m + bit }
      bit = bit * 2
      i = i + 1
    }
    return m
  }
  di := fnval_target_decl(cs, cl, cx.decls, cx.src, a)
  if di < 0 { return 0 }
  d := deref(decl_get(cx.decls, usize(di)))
  mut pp := d.params_head
  mut k := 0
  while pp != 0 {
    pm := deref(param_p(pp))
    if k < 6 and param_is_float_sse(pm, cx.src) { m = m + bit }
    bit = bit * 2
    pp = pm.next
    k = k + 1
  }
  m
}

## ── FN-6 CALL THROUGH AN EXPRESSION CALLEE (`fs[i](x)`, `t.fs[0](x)`) ─────────────────────────────
## The parser represents it as an ORDINARY `Expr::Call` whose ARGUMENT 0 IS THE CALLEE EXPRESSION, with
## the callee NAME SPAN borrowed from the chain's root variable, and records the site in the
## `ast::ecallee_*` set (see `ast.al` for why the node shape could not change). Everything below is the
## lower's half: recover the callee's fn TYPE by SOURCE SCAN (the parser keeps only the bare `fn` token,
## exactly as for a bound fn value), CHECK the arity + the return class against it, and emit through the
## SAME `call *%rax` convention the fn-value-local path uses. Anything unrecoverable is a `panic`, never
## a blind lowering — the shape used to leak the callee's CODE ADDRESS as the result.

## Is `c` an identifier byte (so a `fn` match inside a type text is a WHOLE word, not the head of `fnord`)?
ecallee_ident_char := fn(c : str) -> bool {
  if c >= "a" and c <= "z" { return true }
  if c >= "A" and c <= "Z" { return true }
  if c >= "0" and c <= "9" { return true }
  c == "_"
}

## The source offset of the `fn` keyword inside the TYPE TEXT `[s, s+n)` — the element type of an
## `[fn(u64) -> u64; 2]`, the field type of a struct's `fs : [fn(…) -> R; N]`. 0 = the text declares no
## fn type. The scan is over recovered SOURCE, so the offset it returns feeds `fnty_param_span` /
## `fnty_ret_span` directly (they read the real signature, which continues past `n`).
ecallee_fnty_in_text := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  if n < 2 { return 0 }
  e := s + n
  mut p := s
  mut r := 0
  while p + 2 <= e and r == 0 {
    if str_at((src + p), 2) == "fn" {
      mut ok := true
      if p > s {
        if ecallee_ident_char(str_at((src + p - 1), 1)) { ok = false }
      }
      if p + 2 < e {
        if ecallee_ident_char(str_at((src + p + 2), 1)) { ok = false }
      }
      if ok { r = p }
    }
    p = p + 1
  }
  r
}

## The declared TYPE TEXT of the local/param named `<ns,nl>` in the function being emitted. Recovered by
## SOURCE SCAN off the binding site (`ast::local_type_span`) — the same recovery `fnval_ty_pos` performs
## for a bare fn-value name, widened from "the type IS a fn type" to "the type CONTAINS one". 0/0 when
## the name is not bound here or carries no annotation (then the call is rejected, not guessed).
ecallee_localty := fn(ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> CSpan {
  mut pcur := EMIT_PARAMS
  mut ps := 0
  mut pn := 0
  while pcur != 0 {
    pm := deref(param_p(pcur))
    if streq(src, pm.ns, pm.nl, ns, nl) { ps = pm.ns ; pn = pm.nl }
    pcur = pm.next
  }
  if pn != 0 {
    lt := local_type_span(src, ps, pn)
    return CSpan(s = lt.s, n = lt.n)
  }
  if EMIT_BODY == 0 { return CSpan(s = 0, n = 0) }
  bi := body_binding(EMIT_BODY, ns, nl, src, a)
  if bi.nl == 0 { return CSpan(s = 0, n = 0) }
  lt2 := local_type_span(src, bi.ns, bi.nl)
  CSpan(s = lt2.s, n = lt2.n)
}

## The source offset of the `fn` keyword of the fn-VALUE TYPE the EXPRESSION callee `ce` produces
## (0 = not recoverable). Two shapes, each an element read off a place whose DECLARED type text names
## the element type:
##   `fs[i]`   — a LOCAL/PARAM array of fn values     `fs : [fn(u64) -> u64; 2] = [add1, dbl]`
##   `t.fs[i]` — a struct FIELD array of fn values    `fs : [fn(u64) -> u64; 2]`
ecallee_fnty_pos := fn(ce : ptr(Expr), cx : ptr(LCtx), a : rt::Arena) -> usize {
  ib := field_base_index(ce)
  if ib.is_ix == false { return 0 }
  bv := var_name_span(ib.arr)
  if bv.n != 0 {
    lt := ecallee_localty(bv.s, bv.n, cx.src, a)
    if lt.n == 0 { return 0 }
    return ecallee_fnty_in_text(cx.src, lt.s, lt.n)
  }
  fp := field_var_parts(ib.arr)
  if fp.ok == false { return 0 }
  ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fp.os, fp.on)))
  if ent.snl == 0 { return 0 }
  ft := field_type_span(cx.decls, cx.src, ent.sns, ent.snl, fp.fs, fp.fl, deref(cx.mar))
  if ft.n == 0 { return 0 }
  ecallee_fnty_in_text(cx.src, ft.s, ft.n)
}

## The PARAMETER COUNT of the fn-value type whose `fn` keyword sits at `p0` (-1 = the text is not a fn
## type / the parameter list never closes). Counts the depth-1 commas of the `(…)` group; an empty (or
## whitespace-only) group is 0 parameters. This is what makes an expression-callee call ARITY-CHECKED —
## the shape used to accept `(add1)(41, 99, 7)` without a word.
ecallee_param_count := fn(src : ptr(u8), p0 : usize) -> i64 {
  lim := p0 + 4096
  if str_at((src + p0), 2) != "fn" { return 0 - 1 }
  mut p := fnty_skip_ws(src, p0 + 2, lim)
  if str_at((src + p), 1) != "(" { return 0 - 1 }
  p = p + 1
  mut d := 1
  mut ncommas := 0
  mut seen := false
  mut fin := false
  while p < lim and fin == false {
    c := str_at((src + p), 1)
    if c == "(" or c == "[" { d = d + 1 }
    if c == ")" or c == "]" {
      if d > 0 { d = d - 1 }
      if d == 0 { fin = true }
    }
    if fin == false {
      if c == "," and d == 1 { ncommas = ncommas + 1 }
      if c != " " and c != "\t" and c != "\n" and c != "\r" { seen = true }
    }
    p = p + 1
  }
  if fin == false { return 0 - 1 }
  if seen == false { return 0 }
  i64(ncommas + 1)
}

## Is the RETURN type `<s,n>` of an expression callee one the `call *%rax` site below can DELIVER — a
## single-word scalar? An `f64`/`f32` return rides %xmm0 and, worse, is invisible to `is_float_expr` at
## this node (which resolves a fn value BY NAME, and this callee has none), so a consumer would read the
## raw bits; a `str` is a 2-word pair; a declared struct/enum has a whole return CLASS (register-return /
## sret / discriminant) keyed off the callee name. All of those are rejected rather than mis-delivered.
ecallee_ret_scalar := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  nm := str_at((src + s), n)
  if nm == "u8" or nm == "u16" or nm == "u32" or nm == "u64" or nm == "usize" { return true }
  if nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" or nm == "isize" { return true }
  if nm == "bool" or nm == "char" { return true }
  nm == "ptr"
}

## The float-ARGUMENT mask of the fn-value type at `p0` — the `fnval_param_fmask` twin for a callee with
## no name to resolve. Bit `k` set = parameter `k` is an `f64`/`f32` and so takes an SSE register.
ecallee_fmask := fn(p0 : usize, cx : ptr(LCtx)) -> usize {
  mut m := 0
  mut bit := 1
  mut i := 0
  while i < 6 {
    ps := fnty_param_span(cx.src, p0, i)
    if ps.n != 0 and ty_is_float_sub(ps.s, ps.n, cx) { m = m + bit }
    bit = bit * 2
    i = i + 1
  }
  m
}

## Lower a call through an EXPRESSION callee. `args_head` holds the CALLEE at source index 0 and the
## `nargs - 1` real value arguments after it.
##
## Sequence — the fn-value-local `call *%rax` path with the code pointer coming off the VALUE STACK
## instead of a frame slot, because the callee is an expression that must be evaluated BEFORE the
## argument registers are loaded (evaluating it after would clobber %rdi..%r9):
##   1. evaluate the callee expression (one word pushed) + one PAD word, so the two together keep %rsp's
##      16-byte residue INVARIANT across the call — the same discipline `align_pad` states for stack args;
##   2. lower the real arguments with `skip = 0` (source index 0, the callee, is ERASED — exactly how the
##      fn-value STRUCT FIELD path erases its receiver);
##   3. read the code pointer back from over the argument block into %rax and `call *%rax`;
##   4. reclaim the stack args, then the pad + callee word, and push the result.
pub emit_ecallee_call := fn(nargs : usize, args_head : ptr(mut Arg), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ce := arg_expr_at(args_head, 0, a)
  if unchecked bitcast(usize, ce) == 0 { panic("selfhost: FN-6 - expression-callee call has no callee") }
  tp := ecallee_fnty_pos(ce, cx, a)
  if tp == 0 { panic("selfhost: FN-6 - the callee expression's fn TYPE is not recoverable here, so the call cannot be arity-checked; annotate the place with its fn type (`fs : [fn(u64) -> u64; 2]`) or bind the callee to a name first") }
  nv := nargs - 1
  npc := ecallee_param_count(cx.src, tp)
  if npc < 0 { panic("selfhost: FN-6 - the callee's fn type has no readable parameter list") }
  if usize(npc) != nv { panic("selfhost: FN-6 - wrong ARITY in a call through an expression callee: the fn type declares a different number of parameters") }
  rs := fnty_ret_span(cx.src, tp)
  if ecallee_ret_scalar(cx.src, rs.s, rs.n) == false { panic("selfhost: FN-6 - a call through an expression callee supports only a single-word SCALAR return; bind the callee to a name first (`g := <callee>` then `g(args)`)") }
  if nv > 6 { panic("selfhost: FN-6 - a call through an expression callee takes at most 6 arguments") }
  cx.call_cidx = -1
  cx.sret_call = -1
  emit_gas(ce, sb, cx, a, nl)                              ## the code pointer, on the value stack
  push_str(sb, "  subq $8, %rsp\n")                        ## 16-byte alignment pad (see the note above)
  cx.ind_fn_fmask = ecallee_fmask(tp, cx)
  emit_call_args(args_head, 0, -1, -1, nv, sb, cx, nl)
  push_str(sb, "  movq ")
  push_int(sb, i64((nstack_args(nv) + align_pad(nv) + 1) * 8))
  push_str(sb, "(%rsp), %rax\n  call *%rax\n")
  emit_call_cleanup(sb, nv)
  push_str(sb, "  addq $16, %rsp\n  pushq %rax\n")
}

## Bit `k` of a float-argument mask (k ≤ 6 — the SysV register-argument budget).
fmask_bit := fn(m : usize, k : usize) -> bool {
  mut v := m
  mut i := 0
  while i < k {
    v = v / 2
    i = i + 1
  }
  v % 2 == 1
}

## Does the call being lowered take ANY float ARGUMENT? `cidx` is the callee decl (-1 for an indirect
## call), `ifm` the indirect call's float-argument mask. GATES the class-aware routing in
## `emit_call_args`: with `ifm == 0` this is exactly `callee_has_float_param`, so every named call keeps
## the byte-identical all-GPR pop loop (`src/` makes no indirect call → the self-host GAS is unchanged).
pub call_has_float_param := fn(cx : ptr(LCtx), cidx : i64, ifm : usize) -> bool {
  if cidx >= 0 { return callee_has_float_param(cx.decls, cx.src, arena_of(cx), cidx) }
  ifm != 0
}

## Is the argument at SOURCE index `sidx` (VALUE index `vidx`) of the call being lowered a float? A
## named callee classes by its own parameter list (the SOURCE index — an erased comptime type argument
## still occupies a position there); an INDIRECT call classes by the fn-value type, whose parameter
## list has no erased type arguments, so the VALUE index is the right key for its mask.
pub call_param_is_float := fn(cx : ptr(LCtx), cidx : i64, ifm : usize, sidx : usize, vidx : usize) -> bool {
  if cidx >= 0 { return callee_param_is_float(cx.decls, cx.src, arena_of(cx), cidx, sidx) }
  if ifm == 0 { return false }
  fmask_bit(ifm, vidx)
}

## FN-10 dual — does the fn-VALUE STRUCT FIELD `o.f` (the receiver `base`, field `<fs,fl>`) return a
## float? The field's DECLARED type text is a real `fn(…) -> R` span here, so it scans directly.
pub fn_field_call_ret_float := fn(base : ptr(Expr), fs : usize, fl : usize, cx : ptr(LCtx)) -> bool {
  fts := fn_field_ty_span(base, fs, fl, cx)
  if fts.n < 3 { return false }
  r := fnty_ret_span(cx.src, fts.s)
  ty_is_float_sub(r.s, r.n, cx)
}

## The DECLARED type-text span of the struct FIELD `<fs,fl>` of the inline-struct-local receiver `base`
## — the `fn(…) -> R` text FN-10 routes an `o.f(…)` member call through. 0/0 when `base` is not such a
## receiver (the shared resolution of `fn_field_call_slot`'s own gates).
fn_field_ty_span := fn(base : ptr(Expr), fs : usize, fl : usize, cx : ptr(LCtx)) -> CSpan {
  vn := var_name_span(base)
  if vn.n == 0 { return CSpan(s = 0, n = 0) }
  ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, vn.s, vn.n)))
  if ent.snl == 0 { return CSpan(s = 0, n = 0) }
  field_type_span(cx.decls, cx.src, ent.sns, ent.snl, fs, fl, deref(cx.mar))
}

## FN-11 — is the `i`-th USER argument of the `dyn fn(…)` type whose `fn` keyword sits at `ftpos` a
## float (an SSE register)? false for an unresolvable type (`ftpos == 0`), which keeps the all-integer
## adapter shape the `dyn` machinery had before the classes existed.
pub dyn_user_arg_is_float := fn(cx : ptr(LCtx), ftpos : usize, i : usize) -> bool {
  if ftpos == 0 { return false }
  ps := fnty_param_span(cx.src, ftpos, i)
  ty_is_float_sub(ps.s, ps.n, cx)
}

## FN-11 — is any of the lifted lambda's TRAILING capture parameters float-classed? The `dyn` adapter
## delivers every capture through an INTEGER register (it loads env words with `movq`), so a float-class
## capture parameter would be read from an %xmm the adapter never wrote — fail loud rather than miscompile.
pub lam_cap_is_float := fn(decls : ptr(rt::Vec), src : ptr(u8), lidx : usize, larity : usize, ncap : usize) -> bool {
  d := deref(decl_get(decls, lidx))
  mut pp := d.params_head
  mut k := 0
  mut r := false
  while pp != 0 {
    pm := deref(param_p(pp))
    if k + ncap >= larity and param_is_float_sse(pm, src) { r = true }
    pp = pm.next
    k = k + 1
  }
  r
}

## FN-10 dual of `fnval_param_fmask` — the float-ARGUMENT mask of a fn-VALUE STRUCT FIELD. The FN-10
## call erases the receiver (`skip = 0`), so VALUE argument k is the fn type's parameter k.
pub fn_field_param_fmask := fn(base : ptr(Expr), fs : usize, fl : usize, cx : ptr(LCtx)) -> usize {
  fts := fn_field_ty_span(base, fs, fl, cx)
  if fts.n < 3 { return 0 }
  mut m := 0
  mut bit := 1
  mut i := 0
  while i < 6 {
    ps := fnty_param_span(cx.src, fts.s, i)
    if ps.n != 0 and ty_is_float_sub(ps.s, ps.n, cx) { m = m + bit }
    bit = bit * 2
    i = i + 1
  }
  m
}

