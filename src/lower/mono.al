## selfhost::lower::mono — the MONOMORPHIZATION PRE-PASS: the walk that collects, ahead of emit, every
## generic instance a program actually needs (`collect_insts_expr`/`collect_insts_stmts`), plus the
## local-type recovery the walk needs to name an implicit-UFCS receiver's instance (`block_decl_type`,
## `recv_full_pre`/`recv_full_emit`, the `{}`-template `print` hole types, the aggregate operand type).
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Everything it does not import — `streq`, `decl_at`,
## `decl_get`, `ret_call_target`, `generic_decl_of`, the `LocalTypeSpan` TYPE — binds `lower.al`'s OWN
## declaration through the ancestor chain (Modules §3 for values, TYPE-ANCESTOR for types).
##
## State, and this is the band that makes the rule concrete. `_bdt_active` (the `block_decl_type`
## re-entrancy guard) travels HERE: nothing outside the band ever named it. The FIVE pre-pass context
## globals stay declared in `src/lower.al` and are read AND WRITTEN from here through the ancestor
## chain (`09242cc`, twelve committed fixtures): `COLLECT_BODY` (12 further sites in the parent),
## `COLLECT_MOD_S`/`COLLECT_MOD_L` (5 each), `EMIT_BODY` (2 in the parent, 11 in `lower::fnval`) and
## `EMIT_PARAMS` (6 / 7). No accessor pair, no `LCtx` field: a descendant writing an ancestor's
## non-`pub` global emits `lower__COLLECT_BODY(%rip)`, which is exactly what is wanted in a pre-pass
## that runs once per top-level fn.
##
## The five externally-called entry points are re-imported into `lower.al` by BARE NAME.
arg_p := ast::arg_p
arm_p := ast::arm_p
stmt_p := ast::stmt_p
local_type_span := ast::local_type_span
(Arg, Decl, Expr, Stmt) := ast
(CSpan, arg_expr_at, var_name_span) := lower_ctx
(base_type_name, enum_decl_of, enum_inst_words, struct_decl_of, struct_words, typearg_at) := lower_layout


## The declared TYPE span of a local named `[ns2, nl2)` — scan the block `head` for its `name : T = …`
## `Assign` (the DECLARATION occurrence) and read the annotation via `local_type_span`. Used by the
## pre-pass to type a `{}`-template `print` hole argument (a slot read isn't available there). v1:
## same-block, annotated locals; last declaration wins.
## The return-ENUM type span of a `m := f(…)` binding whose callee `f` returns a CONCRETE generic-enum
## instance (`Result(u64, u64)` — NO callee type-PARAMETER in the return). Lets `block_decl_type` type
## the bound local `m` so a later `m.unwrap()` / `m.expect(msg)` / `m.ok()` (implicit-UFCS, receiver-keyed)
## recovers its type-args from `m`'s declared return — the call-site-local recovery, one level deep.
## Returns 0/0 for a non-call RHS, a non-enum return, or a return that NAMES a callee type-parameter
## (e.g. a generic `map`/`ok` return `Result(U, E)`/`Option(T)`): resolving those needs substitution the
## SLOT path performs but this source-scan resolver cannot, so they stay on the fail-loud path (bounded).
call_rhs_concrete_enum_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  mut res := CSpan(s = 0, n = 0)
  match deref(v) {
    Expr::Call(cs, cl, nargs, ah) => {
      if enum_ret_call_d(v, decls, src, a) {
        esp := call_ret_enum_span_d(v, decls, src, a)
        ci := ret_call_target(decls, src, cs, cl, nargs, ah, a)
        if esp.n != 0 and ci >= 0 {
          ## CONCRETE only: reject if any top-level return type-arg names a callee type-parameter.
          mut k := 0
          mut go := true
          mut anyp := false
          while go {
            ta := typearg_at(src, esp.s, esp.n, k)
            if ta.n == 0 { go = false }
            else { if callee_param_pos(decls, usize(ci), src, ta.s, ta.n, a) >= 0 { anyp = true } ; k += 1 }
          }
          if anyp == false { res = CSpan(s = esp.s, n = esp.n) }
        }
      }
    }
    _ => {}
  }
  res
}
## RE-ENTRANCY GUARD: `block_decl_type` now types a call-RHS local via `call_rhs_concrete_enum_span` →
## `ret_call_target` → `recv_full_emit` → `block_decl_type` (the receiver-keyed redirect added in
## 168297b), so a binding whose RHS call takes the SAME local as its arg 0 (`a = f(a, …)`) would recurse
## forever → stack overflow. One level only: a re-entrant call returns empty (the nested redirect just
## doesn't fire — a concrete-return callee still resolves by arity), breaking the cycle. Neutral: at HEAD
## `block_decl_type` never reached `ret_call_target`, so this path is entirely new.
mut _bdt_active : bool = false
pub block_decl_type := fn(head : ptr(mut Stmt), ns2 : usize, nl2 : usize, src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> LocalTypeSpan {
  if _bdt_active { return LocalTypeSpan(s = 0, n = 0) }
  _bdt_active = true
  mut s := head
  mut rs := 0
  mut rn := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    mut isas := false
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        isas = true
        if streq(src, ans, anl, ns2, nl2) {
          lt := local_type_span(src, ans, anl)
          if lt.n != 0 { rs = lt.s; rn = lt.n }
          else {
            ## an INFERRED struct local (`p := Pt(…)`, no `: T`) — resolve its type from the RHS
            ## `StructLit`'s name span, the SAME span `expr_type_span` (the emit side) reads, so the
            ## collected `print_one__Pt` instance and the call site agree. Enables `print("{}", p)` on
            ## an inferred struct var (else the call referenced an uncollected `print_one__Pt`).
            sli := struct_lit_info(v)
            eli := enum_lit_info(v)
            crc := call_rhs_concrete_enum_span(v, decls, src, a)
            if sli.is_s { rs = sli.ss; rn = sli.sl }
            else if crc.n != 0 {
              ## an INFERRED enum local bound from a CONCRETE-return CALL (`m := parse(s)`, `parse ->
              ## Result(Config, Err)`): type `m` as the callee's return enum, so `m.unwrap()` / `m.ok()`
              ## (implicit-UFCS receiver-keyed) recover their type-args from `m`. NEUTRAL for src/: at HEAD
              ## a call-RHS receiver was untracked, so a `m := call(); m.<multi-tparam-method>()` shape
              ## fail-loud'd (never built) — enabling it is purely additive.
              rs = crc.s; rn = crc.n
            }
            else if eli.is_e and enum_decl_of(decls, src, eli.es, eli.el) >= 0 {
              ## an INFERRED enum local (`a := E.A(5)`, no `: T`) — resolve its type from the RHS
              ## `EnumLit`'s type-name span (`enum_decl_of >= 0` confirms a genuine enum ctor, not a
              ## UFCS `recv.method(…)` which also parses as `EnumLit`). Without this a bare comparison
              ## `a == b` over payload-carrying enum LOCALS registered NO `base::derive::eq__<E>` instance
              ## in the mono pre-pass (the struct-literal branch alone matched), so the emit side's
              ## synthesized `eq` call linked to an UNDEFINED `base__derive__eq__<E>`. The enum dual of the
              ## struct-literal inference above.
              rs = eli.es; rn = eli.el
            }
            else {
              ## a SNAPSHOT copy `p := S` of a struct GLOBAL — `p` is a proper down-growing local, so
              ## resolve its type from the global's struct name (no layout issue, unlike passing the
              ## global itself by-ref). The supported way to `print` a global struct: copy it first.
              rvn := var_name_span(v)
              if rvn.n != 0 {
                gmv := mut_global_value(decls, src, rvn.s, rvn.n)
                if unchecked bitcast(usize, gmv) != 0 {
                  gsli := struct_lit_info(gmv)
                  if gsli.is_s { rs = gsli.ss; rn = gsli.sl }
                }
              }
            }
          }
        }
        s = nx
      }
      _ => {}
    }
    if isas == false { s = lower_stmt_nx(s, a) }
  }
  ## not a block-local — a module GLOBAL `{}`-hole (`print("{}", S)`, S a mut STRUCT global): resolve
  ## its type from the global's `StructLit` name. Safe now that `emit_arg` MATERIALIZES a global struct
  ## into a down-growing temp before passing it by-ref (so `print_one__Pt` reads its fields correctly);
  ## the collected instance + the call site agree via this same span. (An array global has no type name.)
  if rn == 0 {
    gmv := mut_global_value(decls, src, ns2, nl2)
    if unchecked bitcast(usize, gmv) != 0 {
      gsli := struct_lit_info(gmv)
      if gsli.is_s { rs = gsli.ss; rn = gsli.sl }
    }
  }
  _bdt_active = false
  LocalTypeSpan(s = rs, n = rn)
}
## Collect the `print_one(<argtype>)` instances a `{}`-template variadic `print` call expands to.
## Resolve the same hole shapes as `emit_variadic_print`: plain Vars use their declaring Assign,
## indexed fixed-array reads use the declared element type, and calls use their declared return type.
## Keeping this and the emit-side fallback on one helper prevents an emitted `print_one__T` label from
## outrunning the mono pre-pass (the original failure for `xs[i]` and `f(xs[i])`).
collect_variadic_print := fn(args_head : ptr(mut Arg), block_head : ptr(mut Stmt), in out insts : IVec, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  poi := decl_by_lit_name(decls, src, "print_one")
  if poi < 0 { return }
  fmt := arg_expr_at(args_head, 0, a)
  fi := str_lit_info(fmt)
  if fi.is_s == false { return }
  mut ai := 1
  mut i := 0
  while i < fi.sl {
    mut step := false
    if i + 1 < fi.sl {
      c := str_at((src + fi.ss + i), 1)
      c2 := str_at((src + fi.ss + i + 1), 1)
      if (c == "{" and c2 == "{") or (c == "}" and c2 == "}") {
        ## `{{` / `}}` escape — not a hole, consumes no argument.
        i += 2
        step = true
      } else if c == "{" and c2 == "}" {
        argx := arg_expr_at(args_head, ai, a)
        mut ty := variadic_hole_type_span(argx, block_head, decls, src, a)
        if ty.n == 0 {
          vn := var_name_span(argx)
          if vn.n != 0 {
            lt := block_decl_type(block_head, vn.s, vn.n, src, decls, a)
            if lt.n != 0 { ty = CSpan(s = lt.s, n = lt.n) }
          }
        }
        if ty.n != 0 { add_inst(insts, src, usize(poi), ty.s, ty.n, 0, 0, 0, 0) }
        ai += 1
        i += 2
        step = true
      }
    }
    if step == false { i = i + 1 }
  }
}
## The struct/enum TYPE span of a comparison operand VAR in the mono PRE-PASS (no frame slots): the
## var's declared type resolved from the enclosing fn body (`COLLECT_BODY`/`block_decl_type`) or its
## params (`penv`), restricted to a MULTI-WORD aggregate (>1 word). 0/0 for a scalar / pointer /
## single-word / unresolvable operand — so the bare-aggregate comparison routing registers a derive
## instance ONLY where the emit site (`agg_value_var_words > 1`) also routes, and `src/`'s pointer
## null-checks + 1-word enum compares register nothing → fixpoint-neutral. Returns the FULL type span
## (not the base name) so a generic instance `Pair(u64,u64)` tags identically to the emit side.
collect_agg_operand_type := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, penv : usize) -> CSpan {
  vn := var_name_span(e)
  if vn.n == 0 { return CSpan(s = 0, n = 0) }
  mut ts := 0
  mut tl := 0
  if COLLECT_BODY != 0 {
    ltp := block_decl_type(COLLECT_BODY, vn.s, vn.n, src, decls, a)
    if ltp.n != 0 { ts = ltp.s; tl = ltp.n }
  }
  if tl == 0 {
    pt := param_type_of(vn.s, vn.n, penv, src, a)
    if pt.n != 0 { ts = pt.s; tl = pt.n }
  }
  if tl == 0 { return CSpan(s = 0, n = 0) }
  bn := base_type_name(src, ts, tl)
  ## CANONICALIZE a NON-generic aggregate to its DECL name span (paren-free). A `p := P(x = 5, …)`
  ## inferred local resolves to the struct-LITERAL name span, whose trailing `(x = 5, …)` `typearg_at`
  ## misreads as type-arguments — so two registrations of the same `P` (from different literals, or
  ## against the transitive nested-field `P`) would NOT dedup and would emit a DUPLICATE `…__eq__P`
  ## label. The decl name span (followed by ` := struct`, no paren) tags identically (`P`) and dedups
  ## cleanly. A GENERIC instance (`Pair(u64, u64)`) keeps its full span so the type-args survive.
  sdi := struct_decl_of(decls, src, bn.s, bn.n)
  if sdi >= 0 {
    if struct_words(decls, src, bn.s, bn.n, a) > 1 {
      sd := deref(decl_get(decls, usize(sdi)))
      if sd.is_generic { return CSpan(s = ts, n = tl) }
      return CSpan(s = sd.name_start, n = sd.name_len)
    }
    return CSpan(s = 0, n = 0)
  }
  edi := enum_decl_of(decls, src, bn.s, bn.n)
  if edi >= 0 {
    if 1 + enum_inst_words(decls, src, bn.s, bn.n, a) > 1 {
      ed := deref(decl_get(decls, usize(edi)))
      if ed.is_generic { return CSpan(s = ts, n = tl) }
      return CSpan(s = ed.name_start, n = ed.name_len)
    }
    return CSpan(s = 0, n = 0)
  }
  CSpan(s = 0, n = 0)
}
## The BASE type name of a call's receiver (arg 0) in the mono PRE-PASS — a Var resolved against the
## enclosing fn body (`COLLECT_BODY`/`block_decl_type`) or its params (`penv`). Mirrors the emit
## side's `base_type_name(expr_type_span(arg0))` so receiver-keyed generic selection picks the SAME
## decl in both passes (else the collected instance and the emitted call disagree on the label). 0/0
## when the receiver isn't a resolvable Var (a type-name arg / literal → no receiver redirection).
## Returns the FULL type span (`Result(u64, u64)`) so both the base name (redirect) and the type-args
## (implicit-tag inference) are recoverable.
pub recv_full_pre := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), penv : usize, a : rt::Arena) -> CSpan {
  vn := var_name_span(e)
  if vn.n == 0 { return CSpan(s = 0, n = 0) }
  mut ts := 0
  mut tl := 0
  if COLLECT_BODY != 0 {
    ltp := block_decl_type(COLLECT_BODY, vn.s, vn.n, src, decls, a)
    if ltp.n != 0 { ts = ltp.s; tl = ltp.n }
  }
  if tl == 0 {
    pt := param_type_of(vn.s, vn.n, penv, src, a)
    if pt.n != 0 { ts = pt.s; tl = pt.n }
  }
  if tl == 0 { return CSpan(s = 0, n = 0) }
  CSpan(s = ts, n = tl)
}
## The EMIT-side counterpart of `recv_full_pre`: a receiver Var's FULL declared type span, resolved
## from the enclosing fn's body (`EMIT_BODY`/`block_decl_type`) or its params (`EMIT_PARAMS`), so the
## emit side recovers the type-args (`Result(u64, u64)`) the slot dropped. 0/0 when unresolvable.
pub recv_full_emit := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  vn := var_name_span(e)
  if vn.n == 0 { return CSpan(s = 0, n = 0) }
  mut ts := 0
  mut tl := 0
  if EMIT_BODY != 0 {
    ltp := block_decl_type(EMIT_BODY, vn.s, vn.n, src, decls, a)
    if ltp.n != 0 { ts = ltp.s; tl = ltp.n }
  }
  if tl == 0 and EMIT_PARAMS != 0 {
    pt := param_type_of(vn.s, vn.n, EMIT_PARAMS, src, a)
    if pt.n != 0 { ts = pt.s; tl = pt.n }
  }
  if tl == 0 { return CSpan(s = 0, n = 0) }
  CSpan(s = ts, n = tl)
}
pub collect_insts_expr := fn(e : ptr(Expr), in out insts : IVec, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, penv : usize) {
  match deref(e) {
    Expr::Num(v, s, n) => {}
    Expr::Var(s, n) => {}
    Expr::Bin(op, l, r) => {
      collect_insts_expr(l, insts, decls, src, a, penv)
      collect_insts_expr(r, insts, decls, src, a, penv)
      ## A bare aggregate comparison (`==`/`!=`/`<`/`>`/`<=`/`>=`) lowers to a `base::derive::eq`/`lt`
      ## CALL (see the emit-site routing in `emit_gas`'s Bin case) — register the SAME monomorphized
      ## instance here so the mono pass emits it (and, via the transitive worklist, its nested field
      ## derives). `==`/`!=` → `eq`; the four ordering ops → `lt`. Both operands must resolve to the
      ## SAME multi-word aggregate type (mirrors the emit gate); `src/` has none → registers nothing.
      if op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 {
        lty := collect_agg_operand_type(l, decls, src, a, penv)
        rty := collect_agg_operand_type(r, decls, src, a, penv)
        ## Skip a type that has a user / `@inline` / GENERIC comparison OPERATOR for this glyph
        ## (`operator_decl_idx >= 0` — e.g. the prelude `u128 ≡ uint(128)` OP-1 operators; it
        ## alias-resolves `u128`→`uint(128)`): the EMIT site routes such a compare through that operator
        ## and never reaches the derive fallthrough, so registering a derive instance here would emit a
        ## DEAD (and duplicate-label) `…__lt__<T>`. Mirrors the emit-side operator-routing precedence.
        ## Skip a `Slice(T)` operand: the EMIT site compares a slice view by CONTENT
        ## (`emit_slice_word_eq_core`) and never reaches the derive fallthrough, so a derive instance
        ## registered here is DEAD — and one that does not even ASSEMBLE, because derive's struct arm
        ## recurses on `Slice(T)`'s field type `ptr(T)` with `T` unsubstituted and emits the label
        ## `base__derive__eq__ptr(T)` (`as`: `junk (T) after expression`). That dead instance is why a
        ## program merely comparing two `Slice(T)` PARAMS failed to BUILD. Mirrors the operator-routing
        ## precedence skip on the same line.
        if lty.n != 0 and rty.n != 0 and collect_ty_is_slice(src, lty.s, lty.n) == false and operator_decl_idx(decls, src, i64(op), lty.s, lty.n, a) < 0 {
          if op == 20 or op == 28 {
            gie := derive_cmp_decl(decls, src, false)
            if gie >= 0 { add_inst(insts, src, usize(gie), lty.s, lty.n, 0, 0, 0, 0) }
          } else {
            gil := derive_cmp_decl(decls, src, true)
            if gil >= 0 { add_inst(insts, src, usize(gil), lty.s, lty.n, 0, 0, 0, 0) }
          }
        }
      }
    }
    Expr::If(c, t, f) => {
      collect_insts_expr(c, insts, decls, src, a, penv)
      collect_insts_expr(t, insts, decls, src, a, penv)
      collect_insts_expr(f, insts, decls, src, a, penv)
    }
    Expr::Match(scrut, head) => {
      collect_insts_expr(scrut, insts, decls, src, a, penv)
      mut arm := head
      while arm != 0 {
        am := deref(arm_p(arm))
        collect_insts_expr(am.body, insts, decls, src, a, penv)
        collect_insts_stmts(am.body_stmts, insts, decls, src, a, penv)
        arm = am.next
      }
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      ## a generic call → record (generic-fn, type-arg) before recursing into its value args.
      ## The module pair is the COLLECTING declaration's own module, so a BARE call ranks by the §3
      ## ancestor chain here exactly as it does at emit (see `COLLECT_MOD_S`).
      mut gi := generic_decl_of(decls, src, cs, cl, COLLECT_MOD_S, COLLECT_MOD_L, nargs, args_head, a)
      ## RECEIVER-KEYED SELECTION (mirror the emit side): pick the same-name generic whose `self`
      ## matches arg 0's type, so the collected instance matches the emitted call's label.
      mut rcv_full_pp := CSpan(s = 0, n = 0)
      if gi >= 0 and nargs >= 1 {
        rcv_full_pp = recv_full_pre(arg_expr_at(args_head, 0, a), decls, src, penv, a)
        if rcv_full_pp.n != 0 {
          rcb := base_type_name(src, rcv_full_pp.s, rcv_full_pp.n)
          gi = recv_redirect_generic(decls, src, gi, nargs, rcb.s, rcb.n, a)
        }
      }
      ## a CONCRETE overload matching by arity+first-arg type is NOT a generic instantiation.
      if gi >= 0 {
        gat := arg_type_name_pre(args_head, penv, src, a)
        if nongen_type_match(decls, src, cs, cl, nargs, gat.s, gat.n, a) { gi = 0 - 1 }
      }
      if gi >= 0 {
        ntpc := tparam_count(decls, gi, src, a)
        mut ta := type_arg_full_at(args_head, tparam_idx(decls, gi, src, a), decls, src, a)
        if is_fn_name(decls, src, ta.s, ta.n) { ta = CSpan(s = 0, n = 0) }
        ## a TUPLE type-arg `(T0, T1, …)` — recover its `(…)` source span (mono keys on it).
        if ta.n == 0 {
          tt := tuple_typearg_span(arg_expr_at(args_head, tparam_idx(decls, gi, src, a), a), src, a)
          if tt.n != 0 { ta = tt }
        }
        mut ta2 := CSpan(s = 0, n = 0)
        if ntpc >= 2 { ta2 = type_arg_full_at(args_head, tparam_idx2(decls, gi, src, a), decls, src, a) ; if is_fn_name(decls, src, ta2.s, ta2.n) { ta2 = CSpan(s = 0, n = 0) } }
        mut ta3 := CSpan(s = 0, n = 0)
        if ntpc >= 3 { ta3 = type_arg_full_at(args_head, tparam_idx3(decls, gi, src, a), decls, src, a) ; if is_fn_name(decls, src, ta3.s, ta3.n) { ta3 = CSpan(s = 0, n = 0) } }
        ## IMPLICIT type-arg (`hash(key)` — T omitted): the call passes only value args. Infer T from
        ## the value arg's declared type in the enclosing params; the worklist substitutes K→concrete.
        gdc := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(gi))))
        if ntpc == 1 and gdc.arity != 0 and nargs == gdc.arity - ntpc {
          it := infer_implicit_pre(gi, args_head, penv, decls, src, a)
          if it.n != 0 { ta = it }
        }
        ## IMPLICIT UFCS on a 2-or-3-type-param method — MIRROR the emit side exactly so the collected
        ## instance's label matches the emitted call. `r.unwrap()`/`r.ok()`/`r.unwrap_or(d)` take BOTH
        ## type-args from the receiver's concrete type; `o.map(f)`/`r.map(f)`/`r.and_then(f)`/`r.map_err(g)`
        ## take all-but-one from the receiver and the LAST (the mapper's return type-param `U`/`F`) from
        ## the fn ARGUMENT's declared return (`infer_map_targ3`). Gated to the implicit shape.
        if (ntpc == 2 or ntpc == 3) and gdc.arity != 0 and nargs == gdc.arity - ntpc and rcv_full_pp.n != 0 {
          rbp := base_type_name(src, rcv_full_pp.s, rcv_full_pp.n)
          d0 := implicit_targ_from_recv(decls, src, gi, rcv_full_pp.s, rcv_full_pp.n, 0, a)
          d1 := implicit_targ_from_recv(decls, src, gi, rcv_full_pp.s, rcv_full_pp.n, 1, a)
          d2 := implicit_targ_from_recv(decls, src, gi, rcv_full_pp.s, rcv_full_pp.n, 2, a)
          fu := infer_map_targ3(decls, src, args_head, nargs, rbp.s, rbp.n, a)
          mut e0 := d0
          mut e1 := d1
          mut e2 := d2
          if e0.n == 0 { e0 = fu }
          if e1.n == 0 { e1 = fu }
          if e2.n == 0 { e2 = fu }
          if ntpc == 2 and e0.n != 0 and e1.n != 0 {
            ta = e0
            ta2 = e1
          }
          if ntpc == 3 and e0.n != 0 and e1.n != 0 and e2.n != 0 {
            ta = e0
            ta2 = e1
            ta3 = e2
          }
        }
        add_inst(insts, src, usize(gi), ta.s, ta.n, ta2.s, ta2.n, ta3.s, ta3.n)
      }
      mut g := args_head
      while g != 0 {
        ga := deref(arg_p(g))
        collect_insts_expr(ga.e, insts, decls, src, a, penv)
        g = ga.next
      }
    }
    Expr::StructLit(cs, cl, nf, fhead) => {
      mut g := fhead
      while g != 0 {
        ga := deref(arg_p(g))
        collect_insts_expr(ga.e, insts, decls, src, a, penv)
        g = ga.next
      }
    }
    Expr::Field(base, fs, fl) => { collect_insts_expr(base, insts, decls, src, a, penv) }
    Expr::EnumLit(es, el, vs, vl, np, phead) => {
      mut g := phead
      while g != 0 {
        ga := deref(arg_p(g))
        collect_insts_expr(ga.e, insts, decls, src, a, penv)
        g = ga.next
      }
    }
    Expr::AddrOf(p) => { collect_insts_expr(p, insts, decls, src, a, penv) }
    Expr::Deref(p) => { collect_insts_expr(p, insts, decls, src, a, penv) }
    Expr::ArrayLit(nel, ehead) => {
      mut g := ehead
      while g != 0 {
        ga := deref(arg_p(g))
        collect_insts_expr(ga.e, insts, decls, src, a, penv)
        g = ga.next
      }
    }
    Expr::Index(base, idx) => {
      collect_insts_expr(base, insts, decls, src, a, penv)
      collect_insts_expr(idx, insts, decls, src, a, penv)
    }
    Expr::Try(inner) => { collect_insts_expr(inner, insts, decls, src, a, penv) }
    Expr::Unchecked(inner) => { collect_insts_expr(inner, insts, decls, src, a, penv) }
    Expr::Bitcast(inner, _bcs, _bcl) => { collect_insts_expr(inner, insts, decls, src, a, penv) }
    Expr::Slice(base, lo, hi) => {
      collect_insts_expr(base, insts, decls, src, a, penv)
      collect_insts_expr(lo, insts, decls, src, a, penv)
      collect_insts_expr(hi, insts, decls, src, a, penv)
    }
    Expr::StrLit(ss, sl, lbl, _ps, _pn) => {}
  }
}

## Walk a body statement list, recording every generic-fn call's instantiation (recursing
## into nested branch/arm/loop statement lists). Mirrors `emit_rodata_stmts`.
pub collect_insts_stmts := fn(head : ptr(mut Stmt), in out insts : IVec, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, penv : usize) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { collect_insts_expr(v, insts, decls, src, a, penv); s = nx }
      Stmt::While(c, b, nx) => {
        collect_insts_expr(c, insts, decls, src, a, penv)
        collect_insts_stmts(b, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::Loop(b, nx) => {
        collect_insts_stmts(b, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::Unchecked(b, nx) => {
        collect_insts_stmts(b, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        ## Descend into the `alloc::with(A) { … }` body with COLLECT_BODY pointing at THAT body, so an
        ## implicit generic call inside it (`v.push(i)`, `v`/`i` declared as flat siblings of the enclosing
        ## unchecked/while) can resolve its type argument from those locals via `block_decl_type` (which is a
        ## FLAT scan of COLLECT_BODY). The fn-level COLLECT_BODY doesn't see them (they're nested). Restore
        ## after so siblings of the AllocWith keep the fn scope. src has no `alloc::with` → dormant → neutral.
        saved_cb := COLLECT_BODY
        COLLECT_BODY = unchecked bitcast(usize, b)
        collect_insts_stmts(b, insts, decls, src, a, penv)
        COLLECT_BODY = saved_cb
        s = nx
      }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => {
        ## a `{}`-template variadic `print` → collect a `print_one(<argtype>)` per hole (the arg's
        ## type resolved from its declaration in THIS block `head`).
        ecp := call_parts(e)
        if ecp.is_call and variadic_print_target(decls, src, ecp.cs, ecp.cl, ecp.na, 0, 0, a) >= 0 {
          collect_variadic_print(ecp.ah, head, insts, decls, src, a)
        }
        collect_insts_expr(e, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { collect_insts_expr(fv, insts, decls, src, a, penv); s = nx }
      Stmt::FieldPathAssign(pl, fpv, nx) => { collect_insts_expr(fpv, insts, decls, src, a, penv); s = nx }
      Stmt::Return(rv, nx) => { collect_insts_expr(rv, insts, decls, src, a, penv); s = nx }
      Stmt::If(c, th, el, nx) => {
        collect_insts_expr(c, insts, decls, src, a, penv)
        collect_insts_stmts(th, insts, decls, src, a, penv)
        collect_insts_stmts(el, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::Match(sc, ah, nx) => {
        collect_insts_expr(sc, insts, decls, src, a, penv)
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          collect_insts_stmts(am.body_stmts, insts, decls, src, a, penv)
          arm = am.next
        }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        collect_insts_expr(flo, insts, decls, src, a, penv)
        if unchecked bitcast(usize, fhi) != 0 { collect_insts_expr(fhi, insts, decls, src, a, penv) }   ## fhi==0 = for-over-iterable
        collect_insts_stmts(fb, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::CompIf(ccond, cthen, celse, nx) => {
        collect_insts_stmts(cthen, insts, decls, src, a, penv)
        collect_insts_stmts(celse, insts, decls, src, a, penv)
        s = nx
      }
      ## SKIP the comptime-for body here — collecting it with `f.type` UNRESOLVED would seed a bogus
      ## tagless `<gi>__` instance. The mono worklist instantiates the per-field-type instances instead
      ## (with the concrete field type), so the emit-side unroll finds them defined.
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => { s = nx }
      ## SKIP the range body here too (like CompFor): a `comptime for i in 0 .. typeinfo(T).n` body
      ## (derive's tuple/array fold) references the loop var + `v.(i)` with `i` UNRESOLVED, so collecting
      ## it would seed bogus tagless instances → a mono-worklist explosion. The emit-side unroll (with
      ## `i` a concrete constant) collects the real per-iteration instances; a range body with literal
      ## bounds + generic calls is rare and its instances are reached transitively.
      Stmt::CompForRange(crvs, crvl, crlo, crhi, crb, nx) => { s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        mut car := cmah
        while car != 0 { cam := deref(arm_p(car)); collect_insts_stmts(cam.body_stmts, insts, decls, src, a, penv); car = cam.next }
        s = nx
      }
      Stmt::DerefAssign(ptr, val, nx) => {
        collect_insts_expr(ptr, insts, decls, src, a, penv)
        collect_insts_expr(val, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        collect_insts_expr(ib, insts, decls, src, a, penv)
        collect_insts_expr(ii, insts, decls, src, a, penv)
        collect_insts_expr(iv, insts, decls, src, a, penv)
        s = nx
      }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => {
        collect_insts_expr(fia, insts, decls, src, a, penv)
        collect_insts_expr(fii, insts, decls, src, a, penv)
        collect_insts_expr(fiv, insts, decls, src, a, penv)
        s = nx
      }
    }
  }
}
