## selfhost::lower::abi_c — the `@abi(c)` FOREIGN-CALL ABI (x86_64 System V AMD64, FN-9): eightbyte
## classification (INTEGER / SSE / MEMORY), the register and stack displacement of each argument, the
## variadic-C (`vac_*`) variant with its %al xmm count, the argument emitter, and aggregate RETURN
## reception. 30 functions, one type (`ACDisp`).
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Every UNQUALIFIED name it does not import — `streq`,
## `decl_at`, `decl_get`, `callee_decl_idx`, `emit_expr`, `emit_arg`, `slot_of` — binds `lower.al`'s OWN
## declaration through the ancestor chain (Modules §3), not an unrelated module's private duplicate.
##
## This band names NO module global; `ACDisp` is unique in the tree and used only here, so it travels
## with the band. Eleven entry points are re-imported into `lower.al` by BARE NAME, which leaves every
## call site unchanged and keeps the boundary `@inline`-transparent.
##
## It is the C-ABI HALF of the audit's 2 743-line `abi` band. The other half stays in `src/lower.al`:
## `emit_arg`, `emit_call_args`, `emit_call_dispatch` and the float classifiers are either `pub`, or
## called BY an already-moved child (`lower::fnval` names `emit_call_args`, `nstack_args`, `align_pad`,
## `param_is_float_sse`, `callee_param_is_float`, `callee_has_float_param`), and a child-to-child call
## is a SIBLING reach Modules §3 gives no legal spelling.
##
## NOTE the import ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a
## parse error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them.
strbuf := rt
fld_p := ast::fld_p
param_p := ast::param_p
(Arg, Decl, Expr) := ast
(push_str, push_int) := strbuf
(CSpan, LCtx, arg_expr_at) := lower_ctx
(decl_is_variadic, type_is_variadic_rest) := lower_attrs
(enum_decl_of, enum_inst_words, struct_decl_of, struct_words) := lower_layout

## ============================================================================================
## C-ABI FOREIGN CALLS (x86_64 System V AMD64 — spec 150 §FN-9). FIRST FFI increment: the
## ARGUMENT-PASSING ABI at an `@abi(c)` call site. Our INTERNAL ABI always passes an aggregate BY
## REFERENCE; the C ABI instead CLASSES each aggregate ≤ 16 bytes into eightbytes and passes an
## all-integer aggregate BY VALUE in the integer registers (%rdi %rsi %rdx %rcx %r8 %r9, shared
## with scalar args in source order). DEFERRED (fail loud in `abi_c_param_words`, not attempted
## here): a struct/scalar with a float/double field or type (SSE class → xmm regs); a struct > 16
## bytes (MEMORY class → by-reference to a caller copy); aggregate RETURN values (rax:rdx / sret);
## an enum/str/array aggregate arg; > 6 integer eightbytes total (stack args); the RECEIVING side
## (an `@abi(c)`-EXPORTED fn reading classed args); and the manifest `libs : [Lib]` parsing (MOD-9).
## Every path here is gated on `callee_is_abi_c`, and the self-host source declares NO `@abi(c)` fn,
## so none of this fires on the self-build → the TOOL-1 fixpoint stays byte-identical (NEUTRAL).
##
## True iff the fn declared at source name span `[ns, ns+nl)` carries the value-position effector
## `@abi(c)` — typically alongside `@extern` on an FFI import (`name := @extern @abi(c) fn(…) -> R`).
## Source-scan (the parser records no flag, mirroring `fn_is_naked` / `extern_symbol`): from just
## past the name skip whitespace + `:=` + whitespace, then an OPTIONAL leading `@extern` /
## `@extern("sym")`, then test for the compact `@abi(c)` effector. A spaced `@abi( c )` is not
## matched (acceptable — same restriction as `fn_is_naked`).
pub callee_is_abi_c := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p += 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  ## OPTIONAL leading `@extern` / `@extern("sym")` (the FFI import form) — the parser consumes
  ## `@extern` BEFORE `@abi`, so it precedes `@abi(c)` in source. Skip it (and any `(…)`).
  if str_at((src + p), 7) == "@extern" {
    p = p + 7
    while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
    if str_at((src + p), 1) == "(" {
      while str_at((src + p), 1) != ")" and str_at((src + p), 1) != "" { p = p + 1 }
      if str_at((src + p), 1) == ")" { p = p + 1 }
      while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
    }
  }
  str_at((src + p), 7) == "@abi(c)"
}

## Does the callee at decl index `cidx` carry `@abi(c)`? false for an unknown callee (`cidx < 0`).
pub callee_decl_is_abi_c := fn(decls : ptr(rt::Vec), src : ptr(u8), cidx : i64) -> bool {
  if cidx < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  callee_is_abi_c(src, d.name_start, d.name_len)
}

## Bounded caller-side packing seam: the standard byte tier stores two consecutive `u8` fields at byte
## offsets 0 and 1, while SysV C carries that two-byte image in one INTEGER eightbyte. This helper is
## deliberately exact; all other sub-word and multi-word field shapes remain behind the located reject.
abi_c_is_u8_pair := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut nf := 0
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    if str_at((src + fd.ts), fd.tl) != "u8" { ok = false }
    nf += 1
    f = fd.next
  }
  ok and nf == 2
}

## The TOTAL number of SysV register eightbytes (INTEGER + SSE) consumed by the `pidx`-th param (full
## param list, 0-based) of the `@abi(c)` callee at `cidx`: an integer/pointer/float scalar → 1; a
## small struct (≤ 16 bytes = ≤ 2 words) → its 1-2 words. The per-CLASS split (INTEGER vs SSE regs) is
## `abi_c_arg_int_words` / `abi_c_arg_sse_words`; this count drives the eightbyte iteration when a
## struct's word-0 address is expanded. FAILS LOUD on the deferred classes so nothing is silently
## miscompiled: a struct > 16 bytes (MEMORY, by-reference), an enum/str aggregate param. Mirrors the
## param walk in `callee_out_scalar`. 1 for an out-of-range index (defensive — never hit for a resolved call).
pub abi_c_param_words := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, pidx : usize) -> usize {
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  mut pp := d.params_head
  mut k := 0
  mut res := 1
  while pp != 0 {
    pm := deref(param_p(pp))
    if k == pidx {
      sdi := struct_decl_of(decls, src, pm.ts, pm.tl)
      if sdi >= 0 {
        ## ≤ 16 bytes (≤ 2 words) → register eightbytes; > 16 bytes (MEMORY class) → the word count is
        ## the number of stack words the struct occupies (passed BY VALUE on the stack, increment 3a).
        res = if abi_c_is_u8_pair(decls, src, pm.ts, pm.tl) { 1 } else { struct_words(decls, src, pm.ts, pm.tl, a) }
      } else if str_at((src + pm.ts), pm.tl) == "str" {
        ## a `str` is a 2-word {ptr, len} aggregate → two INTEGER eightbytes (increment 3c).
        res = 2
      } else if enum_decl_of(decls, src, pm.ts, pm.tl) >= 0 {
        ## an enum is a {disc, payload} aggregate → 1 + max-payload words, all INTEGER (increment 3c).
        res = 1 + enum_inst_words(decls, src, pm.ts, pm.tl, a)
      } else {
        res = 1
      }
    }
    k += 1
    pp = pm.next
  }
  res
}

## The struct TYPE span of the `pidx`-th param of the `@abi(c)` callee at `cidx` (0/0 if that param is
## not a struct) — used to per-eightbyte CLASS the argument aggregate on the emit side.
pub abi_c_param_tyspan := fn(decls : ptr(rt::Vec), src : ptr(u8), cidx : i64, pidx : usize) -> CSpan {
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  mut pp := d.params_head
  mut k := 0
  mut res := CSpan(s = 0, n = 0)
  while pp != 0 {
    pm := deref(param_p(pp))
    if k == pidx { res = CSpan(s = pm.ts, n = pm.tl) }
    k += 1
    pp = pm.next
  }
  res
}

## Per-eightbyte SysV class of an `@abi(c)` struct type [s, s+n): eightbyte `ei` is SSE iff its field
## is `f64`/`f32`, else INTEGER (spec 150 §FN-9 — an eightbyte is SSE only when every field in it is
## float). Scoped to structs whose fields are each ONE eightbyte (`struct_words` == field count); a
## sub-8-byte-packed or multi-word field fails loud (deferred), so eightbyte `ei` == field `ei`. Used
## both for a struct ARG (which register each eightbyte rides) and a struct RETURN (which result
## register each eightbyte arrives in).
pub abi_c_eightbyte_is_sse := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, s : usize, n : usize, ei : usize) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut nf := 0
  while f != 0 { fd := deref(fld_p(f)); nf = nf + 1; f = fd.next }
  if struct_words(decls, src, s, n, a) != nf { panic("selfhost: @abi(c) aggregate with a non-eightbyte-aligned field (sub-8-byte float packing / a multi-word field) not yet supported — each field must occupy one eightbyte") }
  mut g := d.fields_head
  mut k := 0
  mut res := false
  while g != 0 {
    fd := deref(fld_p(g))
    if k == ei {
      tn := str_at((src + fd.ts), fd.tl)
      if tn == "f64" or tn == "f32" { res = true }
    }
    k += 1
    g = fd.next
  }
  res
}

## The number of INTEGER-register eightbytes the `pidx`-th arg consumes: a float scalar → 0; an integer
## /pointer scalar → 1; a struct → its INTEGER (non-SSE) eightbytes. The int-register counter is
## INDEPENDENT of the SSE counter (SysV counts the two classes separately).
abi_c_arg_int_words := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, pidx : usize) -> usize {
  if callee_param_is_float(decls, src, a, cidx, pidx) { return 0 }
  ts := abi_c_param_tyspan(decls, src, cidx, pidx)
  if struct_decl_of(decls, src, ts.s, ts.n) >= 0 {
    if struct_words(decls, src, ts.s, ts.n, a) > 2 { return 0 }   ## MEMORY (> 16 bytes) → stack, no int regs
    if abi_c_is_u8_pair(decls, src, ts.s, ts.n) { return 1 }
    nw := abi_c_param_words(decls, src, a, cidx, pidx)
    mut c := 0
    mut ei := 0
    while ei < nw {
      if abi_c_eightbyte_is_sse(decls, src, a, ts.s, ts.n, ei) == false { c = c + 1 }
      ei += 1
    }
    return c
  }
  ## an enum / `str` aggregate — every eightbyte is INTEGER (no float fields); ≤ 16 bytes rides its
  ## word count in integer regs, > 16 bytes goes MEMORY (stack) → no int regs (increment 3c).
  if enum_decl_of(decls, src, ts.s, ts.n) >= 0 or str_at((src + ts.s), ts.n) == "str" {
    w := abi_c_param_words(decls, src, a, cidx, pidx)
    if w > 2 { return 0 }
    return w
  }
  1
}

## The number of SSE-register eightbytes the `pidx`-th arg consumes: a float scalar → 1; a struct → its
## SSE (all-float) eightbytes; an integer scalar → 0. The SSE dual of `abi_c_arg_int_words`.
abi_c_arg_sse_words := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, pidx : usize) -> usize {
  if callee_param_is_float(decls, src, a, cidx, pidx) { return 1 }
  ts := abi_c_param_tyspan(decls, src, cidx, pidx)
  if struct_decl_of(decls, src, ts.s, ts.n) >= 0 {
    if struct_words(decls, src, ts.s, ts.n, a) > 2 { return 0 }   ## MEMORY (> 16 bytes) → stack, no SSE regs
    if abi_c_is_u8_pair(decls, src, ts.s, ts.n) { return 0 }
    nw := abi_c_param_words(decls, src, a, cidx, pidx)
    mut c := 0
    mut ei := 0
    while ei < nw {
      if abi_c_eightbyte_is_sse(decls, src, a, ts.s, ts.n, ei) { c = c + 1 }
      ei += 1
    }
    return c
  }
  0
}

## Is the `pidx`-th param of the `@abi(c)` callee at `cidx` an AGGREGATE (a struct)? An aggregate arg
## is anchored on the value stack by its word-0 ADDRESS (`emit_arg` passes it by reference), so its
## eightbytes must be LOADED from `[address]` into the integer registers; a scalar arg is anchored by
## its VALUE and pops straight into its register. Distinguishing the two is why the pop can't key on
## the eightbyte COUNT alone (a 1-eightbyte struct and a scalar both consume one register).
pub abi_c_param_is_agg := fn(decls : ptr(rt::Vec), src : ptr(u8), cidx : i64, pidx : usize) -> bool {
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  mut pp := d.params_head
  mut k := 0
  mut res := false
  while pp != 0 {
    pm := deref(param_p(pp))
    ## a struct, an enum, OR a `str` is an AGGREGATE — anchored on the value stack by its word-0
    ## ADDRESS (see `emit_arg`), so its eightbytes are LOADED from `[address]` into registers, unlike
    ## a scalar which pops straight into its register (increment 3c adds enum/str to the struct case).
    if k == pidx and (struct_decl_of(decls, src, pm.ts, pm.tl) >= 0 or enum_decl_of(decls, src, pm.ts, pm.tl) >= 0 or str_at((src + pm.ts), pm.tl) == "str") { res = true }
    k += 1
    pp = pm.next
  }
  res
}

## Is the `pidx`-th param of the `@abi(c)` callee at `cidx` a SysV MEMORY-class struct (> 16 bytes = >
## 2 eightbytes)? Such an arg is passed BY VALUE ON THE STACK (increment 3a), not in registers and not
## by a hidden pointer — so it consumes NO argument register (`abi_c_arg_int_words`/`_sse_words` return
## 0) and is copied into the caller's stack argument area at the call. Non-struct / ≤16-byte → false.
abi_c_param_is_mem := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, pidx : usize) -> bool {
  ts := abi_c_param_tyspan(decls, src, cidx, pidx)
  if struct_decl_of(decls, src, ts.s, ts.n) >= 0 { return struct_words(decls, src, ts.s, ts.n, a) > 2 }
  ## an enum > 16 bytes is MEMORY too; a `str` is always 2 words (never MEMORY) (increment 3c).
  if enum_decl_of(decls, src, ts.s, ts.n) >= 0 { return (1 + enum_inst_words(decls, src, ts.s, ts.n, a)) > 2 }
  false
}

## Does the `@abi(c)` callee at `cidx` return a SysV MEMORY-class struct (> 16 bytes)? Such a return is
## delivered via SRET (a hidden result pointer): the caller passes the destination local's address in
## %rdi (shifting the real integer args to %rsi..), the callee writes the whole struct through it +
## returns the pointer in %rax. A ≤16-byte struct return (rax:rdx / xmm0:xmm1, increment 2) → false.
callee_abi_c_ret_mem := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64) -> bool {
  if cidx < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  if d.ret_tl == 0 { return false }
  if struct_decl_of(decls, src, d.ret_ts, d.ret_tl) < 0 { return false }
  struct_words(decls, src, d.ret_ts, d.ret_tl, a) > 2
}

## Is `e` a `Call` to an `@abi(c)` callee that returns a SysV MEMORY-class struct (SRET)? The binding
## `q := f(…)` routes to the sret path (publish `q`'s base on `cx.sret_call`; the C callee writes the
## struct straight into `q`'s slots). Gated on `@abi(c)` (src/ declares none) → fixpoint-neutral.
pub abi_c_ret_mem_call := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => {
      ci := ret_call_target(decls, src, cs, cl, nargs, args_head, a)
      if ci < 0 { return false }
      if callee_decl_is_abi_c(decls, src, ci) == false { return false }
      callee_abi_c_ret_mem(decls, src, a, ci)
    }
    _ => { false }
  }
}

## The starting INTEGER-register index of value arg `j` (source order) of an `@abi(c)` callee — the
## sum of the INTEGER eightbyte counts of args 0..j-1. So arg `j`'s integer eightbytes ride %rdi.. at
## `emit_argreg(abi_c_int_base(j))` onward. INDEPENDENT of the SSE counter.
abi_c_int_base := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, j : usize) -> usize {
  mut base := 0
  mut u := 0
  while u < j {
    base = base + abi_c_arg_int_words(decls, src, a, cidx, u)
    u += 1
  }
  base
}

## The starting SSE-register index of value arg `j` — the sum of the SSE eightbyte counts of args
## 0..j-1. So arg `j`'s float eightbytes ride %xmm.. at `emit_xmmreg(abi_c_sse_base(j))` onward.
## INDEPENDENT of the integer counter (SysV counts int and SSE arg registers separately).
abi_c_sse_base := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, j : usize) -> usize {
  mut base := 0
  mut u := 0
  while u < j {
    base = base + abi_c_arg_sse_words(decls, src, a, cidx, u)
    u += 1
  }
  base
}

## C-VARIADICS (spec 50 §7.3 — increment 3d). A §7.3 C-variadic `@abi(c)` callee has a bare `...` LAST
## param; a call passes its FIXED args (0..nfixed-1, declared params) followed by N trailing VARIADIC
## args that have NO declared param type and are classed by their OWN expression type. The `vac_*`
## wrappers below unify the two: for a fixed arg (`k < nfixed`) they defer to the declared-param `abi_c_*`
## classing; for a variadic arg (`k >= nfixed`) they class by the arg EXPRESSION — a scalar only (an
## f64/f32 expr → one SSE eightbyte, else one INTEGER eightbyte; never MEMORY / aggregate). A non-variadic
## `@abi(c)` call passes `nfixed == nvals`, so every wrapper defers to the original `abi_c_*` and the
## emitted GAS is unchanged (byte-identical). `src/`+`lib/` declare no `@abi(c)` fn → fixpoint-neutral.

## The number of FIXED (declared, non-`...`-rest) value params of the `@abi(c)` callee at `cidx` — the
## declared param count minus 1 when the last param is a bare `...` C-variadic rest.
abi_c_fixed_count := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64) -> usize {
  if cidx < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  mut pp := d.params_head
  mut k := 0
  mut last := 0
  while pp != 0 { last = pp; k = k + 1; pp = deref(param_p(pp)).next }
  if last != 0 {
    lp := deref(param_p(last))
    if type_is_variadic_rest(src, lp.ts, lp.tl) { return usize(k - 1) }
  }
  usize(k)
}

## Is the `@abi(c)` callee at `cidx` a §7.3 C-variadic (last param a bare `...` rest)? Gated on `@abi(c)`
## (the same `...` under NO `@abi(c)` is the §7.1 comptime tuple, handled by the call-site expander).
callee_is_c_variadic := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64) -> bool {
  if cidx < 0 { return false }
  if callee_decl_is_abi_c(decls, src, cidx) == false { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  decl_is_variadic(d, src, a)
}

## Is variadic arg `k`'s EXPRESSION a float (SSE) value? A C-variadic trailing arg has no declared param
## type, so it is classed by its own expression (`is_float_expr`): an f64/f32 value rides an XMM register,
## an integer/pointer value an integer register.
vac_arg_is_float := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, k : usize) -> bool {
  is_float_expr(arg_expr_at(args_head, k, a), cx)
}

## Variadic-aware INTEGER-register eightbyte count of arg `k`: a fixed arg defers to `abi_c_arg_int_words`;
## a variadic arg is a scalar (float → 0 int words, else → 1).
vac_int_words := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> usize {
  if k >= nfixed {
    if vac_arg_is_float(cx, args_head, a, k) { return 0 }
    return 1
  }
  abi_c_arg_int_words(cx.decls, cx.src, a, cidx, k)
}

## Variadic-aware SSE-register eightbyte count of arg `k` (the dual of `vac_int_words`): a variadic float
## arg → 1 SSE word, else 0.
vac_sse_words := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> usize {
  if k >= nfixed {
    if vac_arg_is_float(cx, args_head, a, k) { return 1 }
    return 0
  }
  abi_c_arg_sse_words(cx.decls, cx.src, a, cidx, k)
}

## Variadic-aware TOTAL word count of arg `k` (a variadic scalar arg → 1).
vac_param_words := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> usize {
  if k >= nfixed { return 1 }
  abi_c_param_words(cx.decls, cx.src, a, cidx, k)
}

## Variadic-aware MEMORY-class test (a variadic scalar arg is never MEMORY).
vac_is_mem := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> bool {
  if k >= nfixed { return false }
  abi_c_param_is_mem(cx.decls, cx.src, a, cidx, k)
}

## Variadic-aware AGGREGATE test (a variadic scalar arg is never an aggregate — anchored by VALUE).
vac_is_agg := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> bool {
  if k >= nfixed { return false }
  abi_c_param_is_agg(cx.decls, cx.src, cidx, k)
}

## Variadic-aware float-scalar test for the register pop-and-route loop: a variadic arg keys on its
## expression, a fixed arg on its declared param type.
vac_is_float := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), a : rt::Arena, cidx : i64, nfixed : usize, k : usize) -> bool {
  if k >= nfixed { return vac_arg_is_float(cx, args_head, a, k) }
  callee_param_is_float(cx.decls, cx.src, a, cidx, k)
}

## The SysV placement of one `@abi(c)` argument (increment 3c — register-overflow scalar stack spill):
## either in registers (`on_stack` false, its INTEGER base `ibase` = %rdi.. index, its SSE base `sbase`
## = %xmm.. index) or on the stack (`on_stack` true, at stack-argument-area word `swoff`). A MEMORY
## struct (> 16 bytes) is always on the stack; a register-class arg (scalar / ≤16B aggregate) goes to
## registers when ALL its eightbytes fit the remaining int/SSE registers, else the WHOLE arg spills.
ACDisp := struct { on_stack : bool, ibase : usize, sbase : usize, swoff : usize }

## Simulate the SysV register allocation of args 0..`j` (source order, INDEPENDENT int/SSE counters
## seeded past the hidden sret pointer via `sret_shift`) and RETURN arg `j`'s placement. A greedy
## per-arg allocation: an arg whose eightbytes don't all fit the remaining registers spills onto the
## stack at the running area cursor (in argument order — arg7 lowest); a MEMORY struct always spills.
## O(j) per call, only on the `@abi(c)` path (src/ declares none → fixpoint-neutral). This declared-param
## form is used by the RECEIVING side (`emit_fn` prologue, which has no `LCtx`); the CALLING side uses the
## variadic-aware `vac_arg_disp` below (a strict generalization that adds trailing-arg-by-expression classing).
pub abi_c_arg_disp := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, j : usize, sret_shift : usize) -> ACDisp {
  mut iu := sret_shift
  mut su := 0
  mut sc := 0
  mut k := 0
  mut res := ACDisp(on_stack = false, ibase = 0, sbase = 0, swoff = 0)
  while k <= j {
    if abi_c_param_is_mem(decls, src, a, cidx, k) {
      if k == j { res = ACDisp(on_stack = true, ibase = 0, sbase = 0, swoff = sc) }
      sc = sc + abi_c_param_words(decls, src, a, cidx, k)
    } else {
      iw := abi_c_arg_int_words(decls, src, a, cidx, k)
      sw := abi_c_arg_sse_words(decls, src, a, cidx, k)
      if iu + iw <= 6 and su + sw <= 8 {
        if k == j { res = ACDisp(on_stack = false, ibase = iu, sbase = su, swoff = 0) }
        iu = iu + iw
        su = su + sw
      } else {
        if k == j { res = ACDisp(on_stack = true, ibase = 0, sbase = 0, swoff = sc) }
        sc = sc + abi_c_param_words(decls, src, a, cidx, k)
      }
    }
    k += 1
  }
  res
}

## The TOTAL stack-argument-area word count for an `@abi(c)` call of `nvals` args (the sum of every
## MEMORY struct's and every register-overflow arg's word count). Declared-param form (receiving side).
abi_c_stack_words := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, nvals : usize, sret_shift : usize) -> usize {
  mut iu := sret_shift
  mut su := 0
  mut sc := 0
  mut k := 0
  while k < nvals {
    if abi_c_param_is_mem(decls, src, a, cidx, k) {
      sc = sc + abi_c_param_words(decls, src, a, cidx, k)
    } else {
      iw := abi_c_arg_int_words(decls, src, a, cidx, k)
      sw := abi_c_arg_sse_words(decls, src, a, cidx, k)
      if iu + iw <= 6 and su + sw <= 8 {
        iu = iu + iw
        su = su + sw
      } else {
        sc = sc + abi_c_param_words(decls, src, a, cidx, k)
      }
    }
    k += 1
  }
  sc
}

## VARIADIC-AWARE placement simulation for the CALLING side (spec 50 §7.3): the dual of `abi_c_arg_disp`
## that classes the trailing VARIADIC args (`k >= nfixed`) by their own EXPRESSION (`args_head`), via the
## `vac_*` wrappers. For a non-variadic call (`nfixed == nvals`) every wrapper defers to the declared-param
## classing → identical placement. Needs `cx` (for `is_float_expr` on a variadic arg).
vac_arg_disp := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), cidx : i64, j : usize, sret_shift : usize, nfixed : usize) -> ACDisp {
  a := arena_of(cx)
  mut iu := sret_shift
  mut su := 0
  mut sc := 0
  mut k := 0
  mut res := ACDisp(on_stack = false, ibase = 0, sbase = 0, swoff = 0)
  while k <= j {
    if vac_is_mem(cx, args_head, a, cidx, nfixed, k) {
      if k == j { res = ACDisp(on_stack = true, ibase = 0, sbase = 0, swoff = sc) }
      sc = sc + vac_param_words(cx, args_head, a, cidx, nfixed, k)
    } else {
      iw := vac_int_words(cx, args_head, a, cidx, nfixed, k)
      sw := vac_sse_words(cx, args_head, a, cidx, nfixed, k)
      if iu + iw <= 6 and su + sw <= 8 {
        if k == j { res = ACDisp(on_stack = false, ibase = iu, sbase = su, swoff = 0) }
        iu = iu + iw
        su = su + sw
      } else {
        if k == j { res = ACDisp(on_stack = true, ibase = 0, sbase = 0, swoff = sc) }
        sc = sc + vac_param_words(cx, args_head, a, cidx, nfixed, k)
      }
    }
    k += 1
  }
  res
}

## Variadic-aware TOTAL stack-argument-area word count (the calling-side dual of `abi_c_stack_words`).
vac_stack_words := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), cidx : i64, nvals : usize, sret_shift : usize, nfixed : usize) -> usize {
  a := arena_of(cx)
  mut iu := sret_shift
  mut su := 0
  mut sc := 0
  mut k := 0
  while k < nvals {
    if vac_is_mem(cx, args_head, a, cidx, nfixed, k) {
      sc = sc + vac_param_words(cx, args_head, a, cidx, nfixed, k)
    } else {
      iw := vac_int_words(cx, args_head, a, cidx, nfixed, k)
      sw := vac_sse_words(cx, args_head, a, cidx, nfixed, k)
      if iu + iw <= 6 and su + sw <= 8 {
        iu = iu + iw
        su = su + sw
      } else {
        sc = sc + vac_param_words(cx, args_head, a, cidx, nfixed, k)
      }
    }
    k += 1
  }
  sc
}

## The number of XMM (SSE) registers actually used to pass `nvals` args of the `@abi(c)` call — the SysV
## variadic requirement is that `%al` hold this count (0..8) before a `call` to a variadic function.
## Mirrors `vac_arg_disp`'s greedy register simulation, summing the SSE register words placed.
vac_xmm_count := fn(cx : ptr(LCtx), args_head : ptr(mut Arg), cidx : i64, nvals : usize, sret_shift : usize, nfixed : usize) -> usize {
  a := arena_of(cx)
  mut iu := sret_shift
  mut su := 0
  mut k := 0
  while k < nvals {
    if vac_is_mem(cx, args_head, a, cidx, nfixed, k) == false {
      iw := vac_int_words(cx, args_head, a, cidx, nfixed, k)
      sw := vac_sse_words(cx, args_head, a, cidx, nfixed, k)
      if iu + iw <= 6 and su + sw <= 8 {
        iu = iu + iw
        su = su + sw
      }
    }
    k += 1
  }
  su
}

## Lay an `@abi(c)` call's `nvals` value args into the SysV C ABI locations (spec 150 §FN-9) and RETURN
## the number of stack-argument-area words to reclaim after the `call` (0 for a register-only call).
## Register args reuse the two-phase `emit_arg` staging: (1) PUSH each register-class arg's single anchor
## word in source order (a scalar's VALUE / an f64's IEEE bits / a ≤16-byte aggregate's word-0 ADDRESS),
## (2) POP in REVERSE and route each by its SysV class with INDEPENDENT integer (%rdi..) and SSE (%xmm0..)
## counters. NEW in increment 3a:
##  • a MEMORY-class struct arg (> 16 bytes) is passed BY VALUE ON THE STACK — the caller reserves a
##    16-aligned stack argument area (`subq`), copies the struct's words into its slot (arg 0 at 0(%rsp)),
##    and the MEMORY arg consumes NO register (skipped in the two-phase register loop). The area is even
##    (padded up), so with a 16-aligned %rsp on entry and the register staging push/pop-balanced, %rsp is
##    16-aligned at the `call`; the caller reclaims the area (this fn's return value).
##  • a MEMORY-class struct RETURN (> 16 bytes) is delivered via SRET — the destination local's word-0
##    ADDRESS rides the hidden %rdi (real integer args shift to %rsi..), the C callee writes the struct
##    straight into the destination + returns the pointer in %rax. `cx.sret_call` carries the dest base.
## A 16-byte all-integer struct delivers p.x → %rdi, p.y → %rsi; an all-float `D{f64,f64}` → %xmm0,%xmm1;
## a mixed `M{i64,f64}` → i64/%rdi + f64/%xmm0. Fixpoint-neutral (gated on `callee_is_abi_c`; `src/`
## declares no `@abi(c)` fn). Still fails loud on register-overflow scalar spill (> 6 int / > 8 sse).
pub emit_abi_c_call_args := fn(args_head : ptr(mut Arg), nvals : usize, cidx : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), in out nl : usize) -> usize {
  a := arena_of(cx)
  aggsave := cx.agg_next
  ## SRET: an @abi(c) MEMORY-struct return rides a hidden %rdi result pointer (shift the real int args to
  ## %rsi..). `sc` = the destination slot base, published on `cx.sret_call` by the `q := f(…)` binding.
  sc := cx.sret_call
  cx.sret_call = -1
  retmem := callee_abi_c_ret_mem(cx.decls, cx.src, a, cidx)
  sret_shift := if retmem { 1 } else { 0 }
  if retmem and sc < 0 { panic("selfhost: @abi(c) MEMORY-struct return (sret) needs a destination local binding (q := f(…))") }
  ## C-VARIADIC (spec 50 §7.3): a callee whose LAST param is a bare `...` rest under `@abi(c)`. Its FIXED
  ## params are 0..nfixed-1; the trailing args (nfixed..nvals-1) have no declared param type and are classed
  ## by their own expression (`vac_*`). A non-variadic callee has `nfixed == nvals`, so every `vac_*` defers
  ## to the declared-param `abi_c_*` classing → the register/stack placement + emitted GAS is unchanged.
  cv := callee_is_c_variadic(cx.decls, cx.src, a, cidx)
  nfixed := if cv { abi_c_fixed_count(cx.decls, cx.src, a, cidx) } else { nvals }
  ## STACK ARGUMENT AREA — every MEMORY struct AND every register-overflow arg rides the stack (word
  ## count from `abi_c_stack_words`). Reserve `area` words (rounded UP to an EVEN count so %rsp stays
  ## 16-byte aligned at the `call`); the args sit at 0(%rsp).. and a pad word (if any) rides ABOVE them.
  sw_total := vac_stack_words(cx, args_head, cidx, nvals, sret_shift, nfixed)
  area := if sw_total % 2 != 0 { sw_total + 1 } else { sw_total }
  if area != 0 {
    push_str(sb, "  subq $")
    push_int(sb, i64(area * 8))
    push_str(sb, ", %rsp\n")
  }
  ## copy each STACK arg into its area slot (source order; SysV places arg7 at the lowest address, so
  ## slot `swoff`). `emit_arg` pushes the arg's anchor (transient, one word); pop it (restoring %rsp to
  ## the area top), then store. An AGGREGATE (MEMORY struct / overflow enum·str·struct) pushes its
  ## word-0 ADDRESS → copy word `ce` from `ce*8(%rax)` (up-growing) to `(swoff+ce)*8(%rsp)`; an
  ## overflow SCALAR (integer value / f64 bits) pushes the value itself → store the one word directly.
  mut mk := 0
  while mk < nvals {
    dm := vac_arg_disp(cx, args_head, cidx, mk, sret_shift, nfixed)
    if dm.on_stack {
      emit_arg(arg_expr_at(args_head, mk, a), sb, cx, a, nl, str_arg_tmp_off(args_head, 0 - 1, 0 - 1, 0 - 1, mk, cx, a))
      push_str(sb, "  popq %rax\n")
      if vac_is_agg(cx, args_head, a, cidx, nfixed, mk) {
        ts := abi_c_param_tyspan(cx.decls, cx.src, cidx, mk)
        if abi_c_is_u8_pair(cx.decls, cx.src, ts.s, ts.n) {
          push_str(sb, "  movzbq 0(%rax), %r10\n  movzbq 1(%rax), %r11\n  shlq $8, %r11\n  orq %r11, %r10\n  movq %r10, ")
          push_int(sb, i64(dm.swoff * 8))
          push_str(sb, "(%rsp)\n")
          mk += 1
          continue
        }
        w := vac_param_words(cx, args_head, a, cidx, nfixed, mk)
        mut ce := 0
        while ce < w {
          push_str(sb, "  movq ")
          push_int(sb, i64(ce * 8))
          push_str(sb, "(%rax), %r10\n  movq %r10, ")
          push_int(sb, i64((dm.swoff + ce) * 8))
          push_str(sb, "(%rsp)\n")
          ce += 1
        }
      } else {
        push_str(sb, "  movq %rax, ")
        push_int(sb, i64(dm.swoff * 8))
        push_str(sb, "(%rsp)\n")
      }
    }
    mk += 1
  }
  ## REGISTER ARGS — PHASE 1: push each register-placed arg's anchor in source order, SKIPPING the
  ## stack args (already copied above). `emit_arg` leaves a scalar's value / an f64's bits / a ≤16-byte
  ## aggregate's word-0 address on the stack (arg 0 deepest).
  mut k := 0
  while k < nvals {
    if vac_arg_disp(cx, args_head, cidx, k, sret_shift, nfixed).on_stack == false {
      emit_arg(arg_expr_at(args_head, k, a), sb, cx, a, nl, str_arg_tmp_off(args_head, 0 - 1, 0 - 1, 0 - 1, k, cx, a))
    }
    k += 1
  }
  ## PHASE 2 — pop the register args in REVERSE push order (top = highest-index register arg); route each
  ## by its SysV class into its integer register (`ibase` already shifted past the sret ptr) or %xmm.
  mut j := nvals
  while j != 0 {
    j = j - 1
    dj := vac_arg_disp(cx, args_head, cidx, j, sret_shift, nfixed)
    if dj.on_stack == false {
      ibase := dj.ibase
      sbase := dj.sbase
      if vac_is_agg(cx, args_head, a, cidx, nfixed, j) {
        ## a ≤16-byte aggregate: the anchor is the word-0 ADDRESS — pop it into %rax and LOAD each eightbyte
        ## (`ei*8(%rax)`) by value into the next integer OR %xmm register for its class (independent counters).
        ts := abi_c_param_tyspan(cx.decls, cx.src, cidx, j)
        w := abi_c_param_words(cx.decls, cx.src, a, cidx, j)
        push_str(sb, "  popq %rax\n")
        if abi_c_is_u8_pair(cx.decls, cx.src, ts.s, ts.n) {
          push_str(sb, "  movzbq 0(%rax), %r10\n  movzbq 1(%rax), %r11\n  shlq $8, %r11\n  orq %r11, %r10\n  movq %r10, ")
          emit_argreg(sb, ibase)
          push_str(sb, "\n")
          continue
        }
        mut ic := 0
        mut scnt := 0
        mut ei := 0
        while ei < w {
          push_str(sb, "  movq ")
          push_int(sb, i64(ei * 8))
          push_str(sb, "(%rax), ")
          if abi_c_eightbyte_is_sse(cx.decls, cx.src, a, ts.s, ts.n, ei) {
            emit_xmmreg(sb, sbase + scnt)
            scnt += 1
          } else {
            emit_argreg(sb, ibase + ic)
            ic += 1
          }
          push_str(sb, "\n")
          ei += 1
        }
      } else if vac_is_float(cx, args_head, a, cidx, nfixed, j) {
        ## float scalar: the anchor is the f64 bits — pop into %rax then move into its %xmm register.
        push_str(sb, "  popq %rax\n  movq %rax, ")
        emit_xmmreg(sb, sbase)
        push_str(sb, "\n")
      } else {
        ## integer scalar: the anchor IS the value — pop straight into its integer register.
        push_str(sb, "  popq ")
        emit_argreg(sb, ibase)
        push_str(sb, "\n")
      }
    }
  }
  ## SRET: load the destination local's word-0 ADDRESS into %rdi (the hidden result pointer). The C callee
  ## writes the whole struct through it (up-growing: field k at k*8(%rdi)) straight into the dest slots.
  if retmem {
    push_str(sb, "  leaq -")
    push_int(sb, i64((sc + 1) * 8))
    push_str(sb, "(%rbp), %rdi\n")
  }
  ## C-VARIADIC (spec 50 §7.3): SysV requires `%al` = the number of vector (XMM) registers used to pass
  ## arguments (0..8) before a `call` to a variadic function — a variadic prologue only spills its XMM
  ## registers when `%al` > 0. Emitted LAST (nothing below touches %rax before the caller's `call`); ONLY
  ## for a C-variadic callee (a fixed `@abi(c)` call omits it → byte-identical to increment 3c).
  if cv {
    push_str(sb, "  movb $")
    push_int(sb, i64(vac_xmm_count(cx, args_head, cidx, nvals, sret_shift, nfixed)))
    push_str(sb, ", %al\n")
  }
  cx.agg_next = aggsave
  area
}

## Normalize an `@abi(c)` STRUCT return (≤ 16 bytes) left in the SysV classed RESULT registers into the
## compiler's %rax:%rdx… retreg convention (word k → `emit_retreg(k)`), so the shared struct-return
## STORE loop (`struct_ret_call` in the `Stmt::Assign` emit) reads it. SysV delivers the INTEGER
## eightbytes in %rax/%rdx (class order) and the SSE eightbytes in %xmm0/%xmm1; eightbyte `ei` must land
## in `emit_retreg(ei)`. INTEGER moves are emitted FIRST (word order) then the SSE moves, so a
## leading-SSE struct's integer eightbyte (in %rax) is relocated to its target BEFORE %xmm0 overwrites
## %rax. An ALL-INTEGER struct (e.g. `Pt{i64,i64}`) emits only no-op self-moves (%rax→%rax, %rdx→%rdx) →
## byte-identical to reading the result directly. A scalar / void / non-struct return is a no-op; a
## struct > 16 bytes (sret / hidden pointer) fails loud (deferred). Gated (only an `@abi(c)` callee).
pub emit_abi_c_ret_agg := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, cidx : i64, in out sb : strbuf::StrBuf) {
  if cidx < 0 { return }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(cidx))))
  if d.ret_tl == 0 { return }
  di := struct_decl_of(decls, src, d.ret_ts, d.ret_tl)
  if di < 0 { return }
  nw := struct_words(decls, src, d.ret_ts, d.ret_tl, a)
  ## > 16 bytes (MEMORY): delivered via SRET — the C callee already wrote the whole struct into the
  ## destination local through the hidden %rdi pointer (see `emit_abi_c_call_args`), so there are NO
  ## result registers to normalize. No-op (the `q := f(…)` binding read-back reads the slots directly).
  if nw > 2 { return }
  ## INTEGER eightbytes: the k-th integer eightbyte arrives in result int reg k (retreg 0 = %rax,
  ## 1 = %rdx); relocate it to retreg(ei). A self-move (int reg already at its word slot) is skipped.
  mut ic := 0
  mut ei := 0
  while ei < nw {
    if abi_c_eightbyte_is_sse(decls, src, a, d.ret_ts, d.ret_tl, ei) == false {
      if ic != ei {
        push_str(sb, "  movq ")
        emit_retreg(sb, ic)
        push_str(sb, ", ")
        emit_retreg(sb, ei)
        push_str(sb, "\n")
      }
      ic += 1
    }
    ei += 1
  }
  ## SSE eightbytes: the k-th SSE eightbyte arrives in %xmm k; move it into retreg(ei).
  mut sc := 0
  mut ej := 0
  while ej < nw {
    if abi_c_eightbyte_is_sse(decls, src, a, d.ret_ts, d.ret_tl, ej) {
      push_str(sb, "  movq ")
      emit_xmmreg(sb, sc)
      push_str(sb, ", ")
      emit_retreg(sb, ej)
      push_str(sb, "\n")
      sc += 1
    }
    ej += 1
  }
}

## RECEIVING side (increment 3b): the INVERSE of `emit_abi_c_ret_agg`. An `@abi(c)` Alatyr fn
## DEFINITION returning a ≤16-byte struct has its trailing/early returns delivered by the shared
## struct-return path into the compiler's %rax:%rdx… retreg convention (word k → `emit_retreg(k)`).
## Before the `ret`, normalize those into the SysV classed RESULT registers so a C CALLER reads them:
## the INTEGER eightbytes ride %rax/%rdx (class order) and the SSE eightbytes ride %xmm0/%xmm1;
## eightbyte `ei` currently sits in `emit_retreg(ei)`. SSE moves are emitted FIRST (reading the raw
## retregs) so a leading-SSE struct's INTEGER eightbyte is relocated into %rax AFTER its SSE sibling
## has been read out of %rax (the dual of `emit_abi_c_ret_agg`'s int-first ordering). An ALL-INTEGER
## struct (`Pt{i64,i64}`) emits only no-op self-moves → byte-identical to the plain retreg delivery.
## `ret_ts`/`ret_tl` = the EFFECTIVE return type span. A >16-byte struct (sret) fails loud upstream in
## `emit_fn`, so this only sees ≤ 2 eightbytes. Gated on `fn_def_is_abi_c`; `src/`+`lib/` declare no
## `@abi(c)` fn → this never fires on the self-build → the TOOL-1 fixpoint stays byte-identical.
pub emit_abi_c_ret_agg_def := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena, ret_ts : usize, ret_tl : usize, in out sb : strbuf::StrBuf) {
  di := struct_decl_of(decls, src, ret_ts, ret_tl)
  if di < 0 { return }
  nw := struct_words(decls, src, ret_ts, ret_tl, a)
  if nw > 2 { return }
  ## SSE eightbytes FIRST: eightbyte `ei` sits in retreg(ei) → move it into %xmm(sc) (class order).
  mut sc := 0
  mut ei := 0
  while ei < nw {
    if abi_c_eightbyte_is_sse(decls, src, a, ret_ts, ret_tl, ei) {
      push_str(sb, "  movq ")
      emit_retreg(sb, ei)
      push_str(sb, ", ")
      emit_xmmreg(sb, sc)
      push_str(sb, "\n")
      sc += 1
    }
    ei += 1
  }
  ## INTEGER eightbytes: the ic-th integer eightbyte (in retreg(ej)) rides SysV int result reg ic
  ## (retreg 0 = %rax, 1 = %rdx). A self-move (already at its slot) is skipped.
  mut ic := 0
  mut ej := 0
  while ej < nw {
    if abi_c_eightbyte_is_sse(decls, src, a, ret_ts, ret_tl, ej) == false {
      if ic != ej {
        push_str(sb, "  movq ")
        emit_retreg(sb, ej)
        push_str(sb, ", ")
        emit_retreg(sb, ic)
        push_str(sb, "\n")
      }
      ic += 1
    }
    ej += 1
  }
}
