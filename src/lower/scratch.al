## selfhost::lower::scratch — scratch-pool sizing scanners.
##
## MOD-12: this child owns the bounded walks that size the string and aggregate temporary pools.
## The scanner bodies below are preserved from `lower.al`; only the module/import plumbing moves.
## The child reaches lower.al's private helpers through the ancestor chain (Modules §3).
## The six public entry points are re-imported by bare name in lower.al so their call sites and
## @inline behavior remain unchanged. No visitor abstraction or semantic cleanup belongs here.
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
(Expr, Stmt) := ast

## STRING tier — str-temp-pool SIZING. A str LITERAL passed as a call argument is materialized
## into a reserved 2-word frame block (`emit_arg` / `str_arg_tmp_off`); every str-literal arg of a
## SINGLE call needs its own block (their addresses are live on the stack simultaneously at the
## `call`). So `emit_fn` reserves `scan_str_arg_temps(body)` blocks = the MAX number of str-literal
## arguments over any single call reachable in the function body (statements + the trailing return
## expr). The walk is a structural max over the AST (every call's str-literal-arg count, AND the
## max from each argument's own sub-expression, since an arg may itself be a call). Over-counting is
## harmless frame padding — builtins (`str_eq`/`len`/`byte_at`) read their str operands directly via
## `emit_str_pair`, not the pool, but counting their args too just reserves a couple of unused words.
##
## Count the str-LITERAL arguments of ONE call's arena-linked `Arg` list head `head`.
scan_call_str_args := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt), a : rt::Arena) -> usize {
  mut g := head
  mut cnt := 0
  while g != 0 {
    ga := deref(arg_p(g))
    ## a str LITERAL / `str_at(base, len)` view / `bytes(<literal|str_at>)` argument needs a 2-word
    ## temp block (no frame home → materialized + passed by reference, see `emit_arg`).
    if arg_str_temp(ga.e, src, decls, a) { cnt = cnt + 1 }
    g = ga.next
  }
  cnt
}
## The max str-literal-argument count of any single call within expression `e` (including `e`
## itself if it is a `Call`, and recursing into every sub-expression / argument).
pub scan_str_arg_expr := fn(src : ptr(u8), decls : ptr(rt::Vec), e : ptr(Expr), a : rt::Arena) -> usize {
  mut m := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { m = imax(scan_str_arg_expr(src, decls, l, a), scan_str_arg_expr(src, decls, r, a)) }
    Expr::If(c, t, f) => { m = imax(scan_str_arg_expr(src, decls, c, a), imax(scan_str_arg_expr(src, decls, t, a), scan_str_arg_expr(src, decls, f, a))) }
    Expr::Match(scrut, head) => {
      m = scan_str_arg_expr(src, decls, scrut, a)
      mut arm := head
      while arm != 0 {
        am := deref(arm_p(arm))
        m = imax(m, scan_str_arg_expr(src, decls, am.body, a))
        m = imax(m, scan_str_arg_stmts(src, decls, am.body_stmts, a))
        arm = am.next
      }
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      m = scan_call_str_args(src, decls, args_head, a)
      mut g := args_head
      while g != 0 {
        ga := deref(arg_p(g))
        m = imax(m, scan_str_arg_expr(src, decls, ga.e, a))
        g = ga.next
      }
    }
    Expr::StructLit(cs, cl, nf, fhead) => {
      mut g := fhead
      while g != 0 {
        ga := deref(arg_p(g))
        m = imax(m, scan_str_arg_expr(src, decls, ga.e, a))
        g = ga.next
      }
    }
    Expr::Field(base, fs, fl) => { m = scan_str_arg_expr(src, decls, base, a) }
    Expr::EnumLit(es, el, vs, vl, np, phead) => {
      mut g := phead
      while g != 0 {
        ga := deref(arg_p(g))
        m = imax(m, scan_str_arg_expr(src, decls, ga.e, a))
        g = ga.next
      }
    }
    Expr::AddrOf(p) => { m = scan_str_arg_expr(src, decls, p, a) }
    Expr::Deref(p) => { m = scan_str_arg_expr(src, decls, p, a) }
    Expr::ArrayLit(nel, ehead) => {
      mut g := ehead
      while g != 0 {
        ga := deref(arg_p(g))
        m = imax(m, scan_str_arg_expr(src, decls, ga.e, a))
        g = ga.next
      }
    }
    Expr::Index(base, idx) => { m = imax(scan_str_arg_expr(src, decls, base, a), scan_str_arg_expr(src, decls, idx, a)) }
    Expr::Try(inner) => { m = scan_str_arg_expr(src, decls, inner, a) }
    Expr::Unchecked(inner) => { m = scan_str_arg_expr(src, decls, inner, a) }
    Expr::Bitcast(inner, _bcs, _bcl) => { m = scan_str_arg_expr(src, decls, inner, a) }
    _ => {}
  }
  m
}

## The max str-literal-argument count of any single call within a statement list `head`.
pub scan_str_arg_stmts := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt), a : rt::Arena) -> usize {
  mut s := head
  mut m := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { m = imax(m, scan_str_arg_expr(src, decls, v, a)); s = nx }
      Stmt::While(c, b, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, c, a), scan_str_arg_stmts(src, decls, b, a))); s = nx }
      Stmt::Loop(b, nx) => { m = imax(m, scan_str_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::Unchecked(b, nx) => { m = imax(m, scan_str_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::AllocWith(ae, b, nx) => { m = imax(m, scan_str_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { m = imax(m, scan_str_arg_expr(src, decls, e, a)); s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { m = imax(m, scan_str_arg_expr(src, decls, fv, a)); s = nx }
      Stmt::FieldPathAssign(pl, fpv, nx) => { m = imax(m, scan_str_arg_expr(src, decls, fpv, a)); s = nx }
      Stmt::Return(rv, nx) => { m = imax(m, scan_str_arg_expr(src, decls, rv, a)); s = nx }
      Stmt::DerefAssign(ptr, val, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, ptr, a), scan_str_arg_expr(src, decls, val, a))); s = nx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, ib, a), imax(scan_str_arg_expr(src, decls, ii, a), scan_str_arg_expr(src, decls, iv, a)))); s = nx }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, fia, a), imax(scan_str_arg_expr(src, decls, fii, a), scan_str_arg_expr(src, decls, fiv, a)))); s = nx }
      Stmt::If(c, th, el, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, c, a), imax(scan_str_arg_stmts(src, decls, th, a), scan_str_arg_stmts(src, decls, el, a)))); s = nx }
      Stmt::Match(sc, ah, nx) => {
        m = imax(m, scan_str_arg_expr(src, decls, sc, a))
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          m = imax(m, scan_str_arg_stmts(src, decls, am.body_stmts, a))
          arm = am.next
        }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { m = imax(m, imax(scan_str_arg_expr(src, decls, flo, a), scan_str_arg_stmts(src, decls, fb, a))); if unchecked bitcast(usize, fhi) != 0 { m = imax(m, scan_str_arg_expr(src, decls, fhi, a)) } ; s = nx }
      Stmt::CompIf(ccond, cthen, celse, nx) => { m = imax(m, imax(scan_str_arg_stmts(src, decls, cthen, a), scan_str_arg_stmts(src, decls, celse, a))); s = nx }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => { m = imax(m, scan_str_arg_stmts(src, decls, cb, a)); s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { m = imax(m, scan_str_arg_stmts(src, decls, rb, a)); s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { mut car : usize = cmah; while car != 0 { cam := deref(arm_p(car)); m = imax(m, scan_str_arg_stmts(src, decls, cam.body_stmts, a)); car = cam.next } ; s = nx }
    }
  }
  m
}

## Is `e` a Var naming a MUTABLE-GLOBAL aggregate (struct/array)? `emit_arg` copies such a global into the
## agg-temp pool before passing it by-ref (a global has no frame home), so it also consumes a pool slice.
is_global_agg_arg := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> bool {
  vn := var_name_span(e)
  if vn.n == 0 { return false }
  gv := mut_global_value(decls, src, vn.s, vn.n)
  if unchecked bitcast(usize, gv) == 0 { return false }
  struct_lit_info(gv).is_s or array_lit_info(gv).is_a
}
## Is `e` an aggregate-VALUE call argument — a struct/enum/tuple LITERAL, a struct-RETURNING call, or a
## mutable-global aggregate Var — that `emit_arg` materializes into the agg-temp pool and passes by
## reference (Functions §4 ABI)? Each such arg consumes one distinct pool slice.
## `sret_ret_call` is counted alongside `struct_ret_call`: a WIDE (> 7-word) struct-returning call arg
## also materializes into a pool slice (it is the callee's hidden-result-pointer destination), so two of
## them in one call (`two(mk(), mk())`) need two DISTINCT blocks. Without it `aggpeak` stayed 0 and the
## single reserved block overflowed (a loud abort). `src/`+`lib/` pass no such arg → fixpoint-neutral.
## `enum_sret_ret_call` is counted for the SAME reason as `sret_ret_call`: a WIDE (disc + payload >
## 7-word) enum-returning call arg also materializes into a pool slice (it is the callee's hidden-result-
## pointer destination), so two of them in one call need two DISTINCT blocks. `src/`+`lib/` declare no
## wide-enum-returning fn → `aggpeak` is unchanged there → fixpoint-neutral.
arg_is_agg_value := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> bool {
  require_agg_blocks(e, decls, src, a) != 0 or struct_lit_info(e).is_s or enum_lit_info(e).is_e or array_lit_info(e).is_a or struct_ret_call(e, decls, src, a) or sret_ret_call(e, decls, src, a) or enum_sret_ret_call(e, decls, src, a) or fixed_array_byte_return_len(e, decls, src, a) >= 1 or is_global_agg_arg(e, decls, src, a)
}

## WIDTH of one expression that can be MATERIALIZED into the aggregate-value pool. This is deliberately
## separate from `scan_agg_arg_*`: the latter answers HOW MANY blocks must be live (including nested-call
## depth), while this answers the width of EACH block. Keeping the two measurements separate avoids the
## old program-global upper bound and preserves the existing fail-loud block-count fence.
agg_value_words := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  ra := require_agg_parts(e, decls, src, a)
  if ra.ok {
    w := require_agg_words(ra.under, decls, src, a)
    if w == 0 { panic("selfhost: aggregate-value scratch width could not resolve checked aggregate type") }
    return w
  }
  sli := struct_lit_info(e)
  if sli.is_s {
    mut w := struct_words(decls, src, sli.ss, sli.sl, a)
    if w == 0 { w = 1 }
    return w
  }
  eli := enum_lit_info(e)
  if eli.is_e { return 1 + enum_inst_words(decls, src, eli.es, eli.el, a) }
  ali := array_lit_info(e)
  if ali.is_a {
    mut w := 0
    mut g := ali.ehead
    while g != 0 {
      ga := deref(arg_p(g))
      mut ew := agg_value_words(ga.e, decls, src, a)
      if ew == 0 { ew = 1 }
      w += ew
      g = ga.next
    }
    if w == 0 { w = 1 }
    return w
  }
  if fixed_array_byte_return_len(e, decls, src, a) >= 1 { return 1 }
  if struct_ret_call(e, decls, src, a) or sret_ret_call(e, decls, src, a) {
    cs := call_ret_struct_span(e, decls, src, a)
    w := struct_words(decls, src, cs.s, cs.n, a)
    if w == 0 { panic("selfhost: aggregate-value scratch width could not resolve struct-return call") }
    return w
  }
  if enum_sret_ret_call(e, decls, src, a) or enum_ret_call_d(e, decls, src, a) {
    es := call_ret_enum_span_d(e, decls, src, a)
    if es.n == 0 { panic("selfhost: aggregate-value scratch width could not resolve enum-return call") }
    return 1 + enum_inst_words(decls, src, es.s, es.n, a)
  }
  if str_ret_call(e, decls, src, a) { return 2 }
  if is_global_agg_arg(e, decls, src, a) {
    vn := var_name_span(e)
    gv := mut_global_value(decls, src, vn.s, vn.n)
    gs := struct_lit_info(gv)
    if gs.is_s { return struct_words(decls, src, gs.ss, gs.sl, a) }
    gai := array_lit_info(gv)
    if gai.is_a {
      mut w := 0
      mut gg := gai.ehead
      while gg != 0 { ge := deref(arg_p(gg)); mut ew := agg_value_words(ge.e, decls, src, a); if ew == 0 { ew = 1 }; w += ew; gg = ge.next }
      if w != 0 { return w }
    }
    panic("selfhost: mutable-global aggregate scratch width could not be resolved")
  }
  0
}

## Maximum aggregate-temp BLOCK WIDTH in one function's own body/value tree. A direct struct/enum/array
## literal is included because the same expression may be a call argument, a branch value, or a whole-value
## mutable-global store; over-reserving that local width is safe, but a declaration elsewhere in the program
## is intentionally invisible here. Mutable-global Vars are counted only at argument sites through
## `agg_value_words`, so merely reading a global does not tax the frame.
pub scan_agg_width_expr := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  mut m := 0
  if arg_is_agg_value(e, decls, src, a) or str_ret_call(e, decls, src, a) { m = agg_value_words(e, decls, src, a) }
  match deref(e) {
    Expr::Bin(op, l, r) => { m = imax(m, imax(scan_agg_width_expr(l, decls, src, a), scan_agg_width_expr(r, decls, src, a))) }
    Expr::If(c, t, f) => { m = imax(m, imax(scan_agg_width_expr(c, decls, src, a), imax(scan_agg_width_expr(t, decls, src, a), scan_agg_width_expr(f, decls, src, a)))) }
    Expr::Match(scrut, head) => {
      m = imax(m, scan_agg_width_expr(scrut, decls, src, a))
      mut arm := head
      while arm != 0 { am := deref(arm_p(arm)); m = imax(m, scan_agg_width_expr(am.body, decls, src, a)); m = imax(m, scan_agg_width_stmts(am.body_stmts, decls, src, a)); arm = am.next }
    }
    Expr::Call(cs, cl, nargs, args_head) => { mut g := args_head; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_width_expr(ga.e, decls, src, a)); g = ga.next } }
    Expr::StructLit(cs, cl, nf, fhead) => { mut g := fhead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_width_expr(ga.e, decls, src, a)); g = ga.next } }
    Expr::Field(base, fs, fl) => { m = imax(m, scan_agg_width_expr(base, decls, src, a)) }
    Expr::EnumLit(es, el, vs, vl, np, phead) => { mut g := phead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_width_expr(ga.e, decls, src, a)); g = ga.next } }
    Expr::AddrOf(p) => { m = imax(m, scan_agg_width_expr(p, decls, src, a)) }
    Expr::Deref(p) => { m = imax(m, scan_agg_width_expr(p, decls, src, a)) }
    Expr::ArrayLit(nel, ehead) => { mut g := ehead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_width_expr(ga.e, decls, src, a)); g = ga.next } }
    Expr::Index(base, idx) => { m = imax(m, imax(scan_agg_width_expr(base, decls, src, a), scan_agg_width_expr(idx, decls, src, a))) }
    Expr::Try(inner) => { m = imax(m, scan_agg_width_expr(inner, decls, src, a)) }
    Expr::Unchecked(inner) => { m = imax(m, scan_agg_width_expr(inner, decls, src, a)) }
    Expr::Bitcast(inner, _bcs, _bcl) => { m = imax(m, scan_agg_width_expr(inner, decls, src, a)) }
    _ => {}
  }
  m
}

pub scan_agg_width_stmts := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  mut s := head
  mut m := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { m = imax(m, scan_agg_width_expr(v, decls, src, a)); s = nx }
      Stmt::While(c, b, nx) => { m = imax(m, imax(scan_agg_width_expr(c, decls, src, a), scan_agg_width_stmts(b, decls, src, a))); s = nx }
      Stmt::Loop(b, nx) => { m = imax(m, scan_agg_width_stmts(b, decls, src, a)); s = nx }
      Stmt::Unchecked(b, nx) => { m = imax(m, scan_agg_width_stmts(b, decls, src, a)); s = nx }
      Stmt::AllocWith(ae, b, nx) => { m = imax(m, imax(scan_agg_width_expr(ae, decls, src, a), scan_agg_width_stmts(b, decls, src, a))); s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { m = imax(m, scan_agg_width_expr(e, decls, src, a)); s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { m = imax(m, scan_agg_width_expr(fv, decls, src, a)); s = nx }
      Stmt::FieldPathAssign(pl, fpv, nx) => { m = imax(m, scan_agg_width_expr(fpv, decls, src, a)); s = nx }
      Stmt::Return(rv, nx) => { m = imax(m, scan_agg_width_expr(rv, decls, src, a)); s = nx }
      Stmt::DerefAssign(ptr, val, nx) => { m = imax(m, imax(scan_agg_width_expr(ptr, decls, src, a), scan_agg_width_expr(val, decls, src, a))); s = nx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { m = imax(m, imax(scan_agg_width_expr(ib, decls, src, a), imax(scan_agg_width_expr(ii, decls, src, a), scan_agg_width_expr(iv, decls, src, a)))); s = nx }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => { m = imax(m, imax(scan_agg_width_expr(fia, decls, src, a), imax(scan_agg_width_expr(fii, decls, src, a), scan_agg_width_expr(fiv, decls, src, a)))); s = nx }
      Stmt::If(c, th, el, nx) => { m = imax(m, imax(scan_agg_width_expr(c, decls, src, a), imax(scan_agg_width_stmts(th, decls, src, a), scan_agg_width_stmts(el, decls, src, a)))); s = nx }
      Stmt::Match(sc, ah, nx) => { m = imax(m, scan_agg_width_expr(sc, decls, src, a)); mut arm := ah; while arm != 0 { am := deref(arm_p(arm)); m = imax(m, scan_agg_width_stmts(am.body_stmts, decls, src, a)); arm = am.next }; s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { m = imax(m, imax(scan_agg_width_expr(flo, decls, src, a), scan_agg_width_stmts(fb, decls, src, a))); if unchecked bitcast(usize, fhi) != 0 { m = imax(m, scan_agg_width_expr(fhi, decls, src, a)) }; s = nx }
      Stmt::CompIf(ccond, cthen, celse, nx) => { m = imax(m, imax(scan_agg_width_stmts(cthen, decls, src, a), scan_agg_width_stmts(celse, decls, src, a))); s = nx }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => { m = imax(m, scan_agg_width_stmts(cb, decls, src, a)); s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { m = imax(m, scan_agg_width_stmts(rb, decls, src, a)); s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { mut car : usize = cmah; while car != 0 { cam := deref(arm_p(car)); m = imax(m, scan_agg_width_stmts(cam.body_stmts, decls, src, a)); car = cam.next }; s = nx }
    }
  }
  m
}
## Count the aggregate-VALUE arguments of ONE call's arg list — each needs a distinct agg-temp slice
## (N in one call → N slices; sharing one slot aliases them, a §8 miscompile — see `emit_call_args`).
scan_call_agg_args := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt), a : rt::Arena) -> usize {
  mut g := head
  mut cnt := 0
  while g != 0 {
    ga := deref(arg_p(g))
    rb := require_agg_blocks(ga.e, decls, src, a)
    if rb != 0 { cnt = cnt + rb }
    else if arg_is_agg_value(ga.e, decls, src, a) { cnt = cnt + 1 }
    g = ga.next
  }
  cnt
}
## The max aggregate-VALUE-argument count of any single call within expr `e` — the structural twin of
## `scan_str_arg_expr`. Drives the agg-temp POOL reservation (`aggpeak` blocks). A flat max (not a
## nesting sum): deep agg-nesting that would exceed the reservation is caught by `emit_arg`'s defensive
## overflow panic (sound — a loud abort, never a silent miscompile), not by over-reserving here.
pub scan_agg_arg_expr := fn(src : ptr(u8), decls : ptr(rt::Vec), e : ptr(Expr), a : rt::Arena) -> usize {
  mut m := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { m = imax(scan_agg_arg_expr(src, decls, l, a), scan_agg_arg_expr(src, decls, r, a)) }
    Expr::If(c, t, f) => { m = imax(scan_agg_arg_expr(src, decls, c, a), imax(scan_agg_arg_expr(src, decls, t, a), scan_agg_arg_expr(src, decls, f, a))) }
    Expr::Match(scrut, head) => {
      m = scan_agg_arg_expr(src, decls, scrut, a)
      mut arm := head
      while arm != 0 {
        am := deref(arm_p(arm))
        m = imax(m, scan_agg_arg_expr(src, decls, am.body, a))
        m = imax(m, scan_agg_arg_stmts(src, decls, am.body_stmts, a))
        arm = am.next
      }
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      ## Types §9.4 — NESTING SUMS, it does not max. `emit_call_args` saves the bump pointer and a
      ## NESTED call's args "stack ABOVE this call's still-live slices", so `sumf(bump(mk(1)))` needs
      ## `own (1, for bump's result) + the deepest arg subtree (1, for mk's result)` = 2 blocks. The old
      ## flat `imax` reserved 1 and `agg_alloc` aborted loudly ("call-arg temp pool overflow") on a
      ## perfectly ordinary nested wide-SRET call — aarch64 already compiles+runs the same program
      ## because `a64_aggval_words_e` counts TREE-WIDE. Identical whenever either term is 0 (a call with
      ## no aggregate-value arg, or one whose args hold no further aggregate-value call).
      mut own := scan_call_agg_args(src, decls, args_head, a)
      mut deepest := 0
      mut g := args_head
      while g != 0 { ga := deref(arg_p(g)); deepest = imax(deepest, scan_agg_arg_expr(src, decls, ga.e, a)); g = ga.next }
      ## A require call itself consumes its preserved-result block plus its predicate-copy block. The
      ## ordinary recursive walk still sees the source constructor as a nested aggregate expression and
      ## may over-reserve one block; over-reservation is harmless, under-reservation would alias the
      ## value with the predicate and violate §8.1.
      reqb := require_agg_blocks(e, decls, src, a)
      if reqb > own { own = reqb }
      m = own + deepest
    }
    Expr::StructLit(cs, cl, nf, fhead) => { mut g := fhead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_arg_expr(src, decls, ga.e, a)); g = ga.next } }
    Expr::Field(base, fs, fl) => { m = scan_agg_arg_expr(src, decls, base, a) }
    Expr::EnumLit(es, el, vs, vl, np, phead) => { mut g := phead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_arg_expr(src, decls, ga.e, a)); g = ga.next } }
    Expr::AddrOf(p) => { m = scan_agg_arg_expr(src, decls, p, a) }
    Expr::Deref(p) => { m = scan_agg_arg_expr(src, decls, p, a) }
    Expr::ArrayLit(nel, ehead) => { mut g := ehead; while g != 0 { ga := deref(arg_p(g)); m = imax(m, scan_agg_arg_expr(src, decls, ga.e, a)); g = ga.next } }
    Expr::Index(base, idx) => { m = imax(scan_agg_arg_expr(src, decls, base, a), scan_agg_arg_expr(src, decls, idx, a)) }
    Expr::Try(inner) => { m = scan_agg_arg_expr(src, decls, inner, a) }
    Expr::Unchecked(inner) => { m = scan_agg_arg_expr(src, decls, inner, a) }
    Expr::Bitcast(inner, _bcs, _bcl) => { m = scan_agg_arg_expr(src, decls, inner, a) }
    _ => {}
  }
  m
}
## The max aggregate-value-argument count of any single call within a statement list `head`.
pub scan_agg_arg_stmts := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt), a : rt::Arena) -> usize {
  mut s := head
  mut m := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { m = imax(m, scan_agg_arg_expr(src, decls, v, a)); s = nx }
      Stmt::While(c, b, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, c, a), scan_agg_arg_stmts(src, decls, b, a))); s = nx }
      Stmt::Loop(b, nx) => { m = imax(m, scan_agg_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::Unchecked(b, nx) => { m = imax(m, scan_agg_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::AllocWith(ae, b, nx) => { m = imax(m, scan_agg_arg_stmts(src, decls, b, a)); s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { m = imax(m, scan_agg_arg_expr(src, decls, e, a)); s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { m = imax(m, scan_agg_arg_expr(src, decls, fv, a)); s = nx }
      Stmt::FieldPathAssign(pl, fpv, nx) => { m = imax(m, scan_agg_arg_expr(src, decls, fpv, a)); s = nx }
      Stmt::Return(rv, nx) => { m = imax(m, scan_agg_arg_expr(src, decls, rv, a)); s = nx }
      Stmt::DerefAssign(ptr, val, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, ptr, a), scan_agg_arg_expr(src, decls, val, a))); s = nx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, ib, a), imax(scan_agg_arg_expr(src, decls, ii, a), scan_agg_arg_expr(src, decls, iv, a)))); s = nx }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, fia, a), imax(scan_agg_arg_expr(src, decls, fii, a), scan_agg_arg_expr(src, decls, fiv, a)))); s = nx }
      Stmt::If(c, th, el, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, c, a), imax(scan_agg_arg_stmts(src, decls, th, a), scan_agg_arg_stmts(src, decls, el, a)))); s = nx }
      Stmt::Match(sc, ah, nx) => {
        m = imax(m, scan_agg_arg_expr(src, decls, sc, a))
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          m = imax(m, scan_agg_arg_stmts(src, decls, am.body_stmts, a))
          arm = am.next
        }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { m = imax(m, imax(scan_agg_arg_expr(src, decls, flo, a), scan_agg_arg_stmts(src, decls, fb, a))); if unchecked bitcast(usize, fhi) != 0 { m = imax(m, scan_agg_arg_expr(src, decls, fhi, a)) } ; s = nx }
      Stmt::CompIf(ccond, cthen, celse, nx) => { m = imax(m, imax(scan_agg_arg_stmts(src, decls, cthen, a), scan_agg_arg_stmts(src, decls, celse, a))); s = nx }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => { m = imax(m, scan_agg_arg_stmts(src, decls, cb, a)); s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { m = imax(m, scan_agg_arg_stmts(src, decls, rb, a)); s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { mut car : usize = cmah; while car != 0 { cam := deref(arm_p(car)); m = imax(m, scan_agg_arg_stmts(src, decls, cam.body_stmts, a)); car = cam.next } ; s = nx }
    }
  }
  m
}
