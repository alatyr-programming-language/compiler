## selfhost::ir::build — the IR builder for slice 1's scalar subset (`docs/ir-slice-1.md` §2).
##
## The one place a function's scalar constructs become IR (`docs/ir.md` §3.1). Every value's kernel type
## and signedness come from sema's side table (`ir::sty_get`, owner decision D6): the builder never
## infers a type from an expression's shape. An expression sema left untyped is a `NotYet` that names
## sema's gap (`NyWhy`), never a default (§3.8.4), so the census counts each gap instead of hiding it.
## Anything outside the subset answers `NotYet(construct, span)` naming the first construct it could not
## build, and the function falls back to its target's legacy emitter (§7.1 rules 1–2). In slice 1b
## nothing consumes a built function except `alatyr ir`, which verifies and prints it; the selectors
## arrive in 1c.
##
## This is a child module of `ir` (Modules §3): it reaches `ir.al`'s private helpers — the instruction
## emitters `e_*`, the record readers, `put*` — by bare name through the ancestor chain.
##
## Absence is a variant here, never a reserved value: an expression builder answers `Option(VRegId)`
## (`None` once the function is refused), a call answers `CallOut`, and every handle is a brand
## (`VRegId`, `LabelId`, `SymId`, `FnId`).
(Arg, Decl, Expr, Param, Stmt) := ast
arg_p := ast::arg_p
arg_at := ast::arg_at
stmt_p := ast::stmt_p
stmt_any := ast::stmt_any
stmt_next := ast::stmt_next
param_p := ast::param_p
streq := lower_ctx::streq

## A kernel type with its signedness: what a value of the subset is.
IbKS := struct { ty : Kty, sg : Sgn }

## What `build_one` answered for one function: the built function's id in the program, or a refusal
## whose construct, class and span are in the caller's `BuildWhy`.
pub BuildOut := enum { Built(FnId), Refused }

## Why a function was refused. `NwOutside`: the construct is outside slice 1's subset (a later slice
## claims it). The other four are SEMA GAPS (D6): the builder needed a type sema did not record —
## `NwAbsent` sema never typed the node (a desugared node, a path sema does not visit), `NwUnknown` sema
## visited it and could not type it, `NwLit` a literal no context gave a type, `NwDisagree` sema typed
## two values that must agree (an operator's operands, a call's result and its callee) differently.
pub NyWhy := enum { NwOutside, NwAbsent, NwUnknown, NwLit, NwDisagree }
pub nywhy_is_gap := fn(w : NyWhy) -> bool {
  match w { NwOutside => { false }; NwAbsent | NwUnknown | NwLit | NwDisagree => { true } }
}
pub nywhy_name := fn(w : NyWhy) -> str {
  match w {
    NwOutside => { "outside the subset" }; NwAbsent => { "sema-gap absent" }; NwUnknown => { "sema-gap unknown" }
    NwLit => { "sema-gap literal" }; NwDisagree => { "sema-gap disagree" }
  }
}
## The refusal `build_one` reports: the construct, why it was refused, and where.
pub BuildWhy := struct { c : Construct, w : NyWhy, span : u64 }

## The binary operators of the AST, decoded ONCE from its operator byte (`ib_bin_of`) so every decision
## below is an exhaustive `match` on a named kind, never a literal comparison.
AstBin := enum { BAdd, BSub, BMul, BDiv, BRem, BBand, BBor, BBxor, BEq, BNe, BLt, BGt, BLe, BGe, BAnd, BOr, BNot }
## The AST's operator bytes are the lexer's token kinds (`src/lexrt.al` header, `src/parser.al`'s
## `and`/`or`/`not` at 40/41/42). This is the only place they are compared.
ib_bin_of := fn(op : u8) -> Option(AstBin) {
  if op == 16 { return Option(AstBin).Some(AstBin.BAdd) }
  if op == 17 { return Option(AstBin).Some(AstBin.BSub) }
  if op == 18 { return Option(AstBin).Some(AstBin.BMul) }
  if op == 19 { return Option(AstBin).Some(AstBin.BDiv) }
  if op == 29 { return Option(AstBin).Some(AstBin.BRem) }
  if op == 34 { return Option(AstBin).Some(AstBin.BBand) }
  if op == 35 { return Option(AstBin).Some(AstBin.BBor) }
  if op == 36 { return Option(AstBin).Some(AstBin.BBxor) }
  if op == 20 { return Option(AstBin).Some(AstBin.BEq) }
  if op == 28 { return Option(AstBin).Some(AstBin.BNe) }
  if op == 24 { return Option(AstBin).Some(AstBin.BLt) }
  if op == 25 { return Option(AstBin).Some(AstBin.BGt) }
  if op == 26 { return Option(AstBin).Some(AstBin.BLe) }
  if op == 27 { return Option(AstBin).Some(AstBin.BGe) }
  if op == 40 { return Option(AstBin).Some(AstBin.BAnd) }
  if op == 41 { return Option(AstBin).Some(AstBin.BOr) }
  if op == 42 { return Option(AstBin).Some(AstBin.BNot) }
  Option(AstBin).None
}
## The comparison predicate of an operator, if it is a comparison.
ib_bin_cc := fn(b : AstBin) -> Cc {
  match b {
    BEq => { Cc.CcEq }; BNe => { Cc.CcNe }; BLt => { Cc.CcLt }; BGt => { Cc.CcGt }; BLe => { Cc.CcLe }; BGe => { Cc.CcGe }
    BAdd | BSub | BMul | BDiv | BRem | BBand | BBor | BBxor | BAnd | BOr | BNot => { Cc.CcNone }
  }
}
## The predicate of the AST operator byte `op`, or `CcNone` when it is not a comparison: the one
## decoding of a comparison operator, for a legacy emitter that still holds the byte (the AArch64
## condition tables, `aarch64::isel`).
pub ast_op_cc := fn(op : u8) -> Cc {
  bo : Option(AstBin) = ib_bin_of(op)
  match bo { Some(b) => { ib_bin_cc(b) }; None => { Cc.CcNone } }
}
## The integer IR op of an arithmetic or bitwise operator (`OpMov` for the others, which never reach it).
ib_bin_op := fn(b : AstBin) -> Op {
  match b {
    BAdd => { Op.OpAdd }; BSub => { Op.OpSub }; BMul => { Op.OpMul }; BDiv => { Op.OpDiv }; BRem => { Op.OpRem }
    BBand => { Op.OpAnd }; BBor => { Op.OpOr }; BBxor => { Op.OpXor }
    BEq | BNe | BLt | BGt | BLe | BGe | BAnd | BOr | BNot => { Op.OpMov }
  }
}
## The shape of operator: short-circuit logic, comparison, arithmetic (with a mode), or bitwise.
AstBinK := enum { BkLogic, BkCmp, BkArith, BkBits }
ib_bin_kind := fn(b : AstBin) -> AstBinK {
  match b {
    BAnd | BOr | BNot => { AstBinK.BkLogic }
    BEq | BNe | BLt | BGt | BLe | BGe => { AstBinK.BkCmp }
    BAdd | BSub | BMul | BDiv | BRem => { AstBinK.BkArith }
    BBand | BBor | BBxor => { AstBinK.BkBits }
  }
}
## Does the operator divide (and so owe the zero and `MIN / -1` checks, §4)?
ib_bin_divides := fn(b : AstBin) -> bool {
  match b {
    BDiv | BRem => { true }
    BAdd | BSub | BMul | BBand | BBor | BBxor | BEq | BNe | BLt | BGt | BLe | BGe | BAnd | BOr | BNot => { false }
  }
}

## The shift and rotate operation-functions (Types §2.2, OP-6), by the callee's name.
ShiftK := enum { SkShl, SkShr, SkRotl, SkRotr }
ib_shift_of := fn(nm : str) -> Option(ShiftK) {
  if nm == "shl" { return Option(ShiftK).Some(ShiftK.SkShl) }
  if nm == "shr" { return Option(ShiftK).Some(ShiftK.SkShr) }
  if nm == "rotl" { return Option(ShiftK).Some(ShiftK.SkRotl) }
  if nm == "rotr" { return Option(ShiftK).Some(ShiftK.SkRotr) }
  Option(ShiftK).None
}
ib_shift_op := fn(s : ShiftK) -> Op {
  match s { SkShl => { Op.OpShl }; SkShr => { Op.OpShr }; SkRotl => { Op.OpRotl }; SkRotr => { Op.OpRotr } }
}
ib_shift_is_rot := fn(s : ShiftK) -> bool {
  match s { SkRotl | SkRotr => { true }; SkShl | SkShr => { false } }
}

## What a call answered: its result value, no value (a function with no result), or a refusal.
CallOut := enum { CoValue(VRegId), CoVoid, CoRefused }

## The builder's state for ONE function. Bindings and the loop stack are growing word buffers (no fixed
## capacity, docs/ir.md §7.2 slice 0a). `term` is whether the statement sequence being built has
## already transferred control (a `ret`/`br`/`trap`): a statement after one is unreachable and is
## dropped, because V7 refuses anything after a terminator. A refusal records the first construct that
## could not be built, why, and its span; every builder returns early once `failed` is set.
## The loop stack is four parallel buffers: each loop's exit label, its continue label, whether it
## carries a value (`lhasres`, 0/1) with that value's vreg (`lres`, read only when `lhasres` is 1), and
## whether a `break` reached it (`lbroken`, 0/1: a loop no `break` leaves never falls through).
## The binding table is parallel buffers too: each binding's name and what it is bound to, told apart
## by two 0/1 flags — a scalar in a vreg (`bvregs`, with the type span it was declared with in
## `bts`/`btn`, 0/0 when it has none), a struct local (`bagg` 1: its frame object in `bvregs`, its
## struct declaration in `bsd`, its type name span in `bts`/`btn`, slice 3a), or an address-taken
## scalar local (`bmem` 1: its frame object in `bvregs`, its declaration's name offset in `bsd`, the key
## of sema's binding record, slice 3b). `taken` holds the name spans `ptr(x)` takes in the function
## (`ib_scan_taken`), two words each.
IbB := struct {
  f : ptr(mut IrFn), p : IrProg,
  src : ptr(u8), decls : ptr(rt::Vec), mod_s : usize, mod_n : usize,
  bnames : ptr(mut WBuf), blens : ptr(mut WBuf), bvregs : ptr(mut WBuf),
  bagg : ptr(mut WBuf), bmem : ptr(mut WBuf), bsd : ptr(mut WBuf), bts : ptr(mut WBuf), btn : ptr(mut WBuf),
  taken : ptr(mut WBuf),
  lexit : ptr(mut WBuf), lcont : ptr(mut WBuf), lres : ptr(mut WBuf), lhasres : ptr(mut WBuf), lbroken : ptr(mut WBuf),
  unch : bool, term : bool,
  failed : bool, fail_c : Construct, fail_w : NyWhy, fail_s : u64,
  span0 : u64,
}

## Record reads, copy-then-read (#792: an enum or bool field read straight through `deref(p)` is wrong
## on x86_64 today). Writes copy the whole record back for the same reason.
ib_b_f := fn(bp : ptr(mut IbB)) -> ptr(mut IrFn) { bv : IbB = deref(bp); bv.f }
ib_b_p := fn(bp : ptr(mut IbB)) -> IrProg { bv : IbB = deref(bp); bv.p }
ib_b_src := fn(bp : ptr(mut IbB)) -> ptr(u8) { bv : IbB = deref(bp); bv.src }
ib_b_decls := fn(bp : ptr(mut IbB)) -> ptr(rt::Vec) { bv : IbB = deref(bp); bv.decls }
ib_b_failed := fn(bp : ptr(mut IbB)) -> bool { bv : IbB = deref(bp); bv.failed }
ib_b_unch := fn(bp : ptr(mut IbB)) -> bool { bv : IbB = deref(bp); bv.unch }
ib_b_term := fn(bp : ptr(mut IbB)) -> bool { bv : IbB = deref(bp); bv.term }
ib_b_set_unch := fn(bp : ptr(mut IbB), u : bool) { mut bv : IbB = deref(bp); bv.unch = u; deref(bp) = bv }
ib_b_set_term := fn(bp : ptr(mut IbB), t : bool) { mut bv : IbB = deref(bp); bv.term = t; deref(bp) = bv }

## Refuse the function at construct `c` for reason `w` (spanned `s`, else the function's name). The
## first refusal wins.
ib_refuse := fn(bp : ptr(mut IbB), c : Construct, w : NyWhy, s : Option(u64)) {
  mut bv : IbB = deref(bp)
  if bv.failed { return }
  bv.failed = true
  bv.fail_c = c
  bv.fail_w = w
  bv.fail_s = bv.span0
  match s { Some(x) => { bv.fail_s = x }; None => {} }
  deref(bp) = bv
}
ib_refuse_expr := fn(bp : ptr(mut IbB), e : ptr(Expr), w : NyWhy) {
  c : Construct = expr_construct(e)
  sp : Option(u64) = expr_span(e)
  ib_refuse(bp, c, w, sp)
}
ib_refuse_stmt := fn(bp : ptr(mut IbB), h : ptr(mut Stmt), w : NyWhy) {
  c : Construct = stmt_construct(h)
  sp : Option(u64) = stmt_span(h)
  ib_refuse(bp, c, w, sp)
}
## A refused expression, as an expression builder's answer.
ib_no := fn(bp : ptr(mut IbB), e : ptr(Expr), w : NyWhy) -> Option(VRegId) {
  ib_refuse_expr(bp, e, w)
  Option(VRegId).None
}
## The source offset a checked op carries (V9): its expression's, else the function's name.
ib_span_of := fn(bp : ptr(mut IbB), e : ptr(Expr)) -> usize {
  sp : Option(u64) = expr_span(e)
  bv : IbB = deref(bp)
  match sp { Some(x) => { return usize(x) }; None => {} }
  usize(bv.span0)
}

## ── kernel types (sema's record → IR type) ──

## The kernel type of an integer of `bytes` width and sign `s`, if it is one.
ib_int_ks := fn(bytes : u64, s : Sgn) -> Option(IbKS) {
  if bytes == 1 { return Option(IbKS).Some(IbKS(ty = Kty.KI8, sg = s)) }
  if bytes == 2 { return Option(IbKS).Some(IbKS(ty = Kty.KI16, sg = s)) }
  if bytes == 4 { return Option(IbKS).Some(IbKS(ty = Kty.KI32, sg = s)) }
  if bytes == 8 { return Option(IbKS).Some(IbKS(ty = Kty.KI64, sg = s)) }
  Option(IbKS).None
}
## The kernel type of a recorded value type, when the builder builds values of it: integers and `bool`
## (slice 1), and a pointer as the one-word address it is (slice 2: a pointer crosses a call, a return
## and a binding like any scalar; dereferencing one is a place, slice 3).
ib_vty_ks := fn(t : VTy) -> Option(IbKS) {
  c : VCls = t.cls
  match c {
    VcInt => { ib_int_ks(t.bytes, t.sg) }
    VcBool => { Option(IbKS).Some(IbKS(ty = Kty.KBool, sg = Sgn.SgNone)) }
    VcPtr => { Option(IbKS).Some(IbKS(ty = Kty.KPtr, sg = Sgn.SgNone)) }
    VcAbsent | VcUnknown | VcLit | VcFloat | VcAgg => { Option(IbKS).None }
  }
}
## Why a recorded value type gives no kernel type: a sema gap for the untyped classes, otherwise a type
## the builder does not build yet (a float, an aggregate, an integer wider than 64 bits).
ib_vty_why := fn(t : VTy) -> NyWhy {
  c : VCls = t.cls
  match c {
    VcAbsent => { NyWhy.NwAbsent }; VcUnknown => { NyWhy.NwUnknown }; VcLit => { NyWhy.NwLit }
    VcInt | VcBool | VcPtr | VcFloat | VcAgg => { NyWhy.NwOutside }
  }
}
## The kernel type sema recorded for `e`. Without one the function is refused at `e`, naming sema's gap
## (D6: never a default).
ib_ty := fn(bp : ptr(mut IbB), e : ptr(Expr)) -> Option(IbKS) {
  t : VTy = sty_get(e)
  ko : Option(IbKS) = ib_vty_ks(t)
  match ko { Some(k) => { return ko }; None => {} }
  w : NyWhy = ib_vty_why(t)
  ib_refuse_expr(bp, e, w)
  Option(IbKS).None
}
## The kernel type sema recorded for the binding declared at name offset `ns` (statement `h`).
ib_bind_ty := fn(bp : ptr(mut IbB), h : ptr(mut Stmt), ns : usize) -> Option(IbKS) {
  t : VTy = sty_bind_get(ns)
  ko : Option(IbKS) = ib_vty_ks(t)
  match ko { Some(k) => { return ko }; None => {} }
  w : NyWhy = ib_vty_why(t)
  ib_refuse_stmt(bp, h, w)
  Option(IbKS).None
}
## The kernel type a declared type NAME `[s, s+n)` denotes, by sema's one table of scalar names.
ib_name_ks := fn(src : ptr(u8), s : usize, n : usize) -> Option(IbKS) {
  t : VTy = sema::sema_vty_scalar(src, s, n)
  ib_vty_ks(t)
}
ib_vreg_ks := fn(f : ptr(mut IrFn), v : VRegId) -> IbKS {
  t : Kty = vreg_ty(f, usize(v))
  s : Sgn = vreg_sg(f, usize(v))
  IbKS(ty = t, sg = s)
}
ib_ks_eq := fn(x : IbKS, y : IbKS) -> bool { kty_eq(x.ty, y.ty) and sgn_eq(x.sg, y.sg) }
ib_ks_i64 := fn(s : Sgn) -> IbKS { IbKS(ty = Kty.KI64, sg = s) }
ib_bool_ks := fn() -> IbKS { IbKS(ty = Kty.KBool, sg = Sgn.SgNone) }
ib_ks_bits := fn(k : IbKS) -> u64 { kty_bytes(k.ty) * 8 }

## ── small emitters over the builder ──

ib_fresh := fn(bp : ptr(mut IbB), in out a : rt::Arena, k : IbKS) -> VRegId { new_vreg(ib_b_f(bp), a, k.ty, k.sg) }
ib_mov := fn(bp : ptr(mut IbB), in out a : rt::Arena, d : VRegId, x : VRegId) {
  k : IbKS = ib_vreg_ks(ib_b_f(bp), d)
  ox := o_vreg(x)
  on := o_none()
  i := e_bin(ib_b_f(bp), a, Op.OpMov, Mode.MdNone, Sgn.SgNone, k.ty, d, ox, on)
}
ib_konst := fn(bp : ptr(mut IbB), in out a : rt::Arena, k : IbKS, x : i64) -> VRegId {
  d := ib_fresh(bp, a, k)
  i := e_const(ib_b_f(bp), a, k.ty, k.sg, d, x)
  d
}
ib_open_if := fn(bp : ptr(mut IbB), in out a : rt::Arena, c : VRegId) { i := e_if(ib_b_f(bp), a, c) }
ib_plain := fn(bp : ptr(mut IbB), in out a : rt::Arena, o : Op) { i := e_plain(ib_b_f(bp), a, o) }
ib_br := fn(bp : ptr(mut IbB), in out a : rt::Arena, l : LabelId) { on := o_none(); i := e_br(ib_b_f(bp), a, Op.OpBr, on, l) }
## `%d = <o>.<md>.<sg> i64 x, y`, marked proven (V10: a `wrap` the builder proved cannot overflow).
ib_proven := fn(bp : ptr(mut IbB), in out a : rt::Arena, o : Op, k : IbKS, x : VRegId, y : Opnd) -> VRegId {
  d := ib_fresh(bp, a, k)
  mut it := st_mk(o, k.ty, k.sg, Mode.MdNone)
  if op_has_mode(o) { it.md = Mode.MdWrap; it.proven = true }
  set_dst(it, d)
  ox := o_vreg(x)
  set_a(it, ox)
  set_b(it, y)
  i := emit(ib_b_f(bp), a, it)
  d
}
## Widen (or re-sign) `x` to `to` with `ext` — the only way a value changes width or signedness (V4).
ib_ext_to := fn(bp : ptr(mut IbB), in out a : rt::Arena, x : VRegId, to : IbKS) -> VRegId {
  from : IbKS = ib_vreg_ks(ib_b_f(bp), x)
  if ib_ks_eq(from, to) { return x }
  d := ib_fresh(bp, a, to)
  i := e_width(ib_b_f(bp), a, Op.OpExt, from.sg, to.ty, from.ty, d, x)
  d
}
## The value `x` at the type `to` sema gave its position (a binding, an argument, a result, a `break`
## or an arm value). An integer narrower than `to` that sema accepted there loses no value: it is
## widened by `ext` (same signedness, or unsigned into signed). Any other mismatch is sema's two records
## disagreeing, and the function is refused at `at`.
ib_coerce := fn(bp : ptr(mut IbB), in out a : rt::Arena, x : VRegId, to : IbKS, at : ptr(Expr)) -> Option(VRegId) {
  from : IbKS = ib_vreg_ks(ib_b_f(bp), x)
  if ib_ks_eq(from, to) { return Option(VRegId).Some(x) }
  widens := kty_is_int(from.ty) and kty_is_int(to.ty) and kty_bytes(from.ty) < kty_bytes(to.ty)
    and (sgn_eq(from.sg, to.sg) or sgn_eq(from.sg, Sgn.SgU))
  if widens { w := ib_ext_to(bp, a, x, to); return Option(VRegId).Some(w) }
  ib_no(bp, at, NyWhy.NwDisagree)
}
## Narrow the 64-bit `x` to `to`: `fit` (traps `tk` when it does not fit) in a checked scope, `ext`
## (wraps) inside `unchecked` (§3.2 canonical form; V3).
ib_narrow_to := fn(bp : ptr(mut IbB), in out a : rt::Arena, x : VRegId, to : IbKS, tk : TrapKind, span : usize) -> VRegId {
  from : IbKS = ib_vreg_ks(ib_b_f(bp), x)
  if ib_ks_eq(from, to) { return x }
  if ib_b_unch(bp) { return ib_wrap_to(bp, a, x, to) }
  d := ib_fresh(bp, a, to)
  mut it := st_mk(Op.OpFit, to.ty, from.sg, Mode.MdNone)
  it.from = from.ty
  set_dst(it, d)
  ox := o_vreg(x)
  set_a(it, ox)
  it.tk = tk
  set_span(it, span)
  i2 := emit(ib_b_f(bp), a, it)
  d
}
## Wrap the 64-bit `x` to `to` with `ext`, in any scope: for an operation whose result keeps only the
## type's low bits by definition (a shift, a rotation, a bitwise op), never an overflow.
ib_wrap_to := fn(bp : ptr(mut IbB), in out a : rt::Arena, x : VRegId, to : IbKS) -> VRegId {
  from : IbKS = ib_vreg_ks(ib_b_f(bp), x)
  if ib_ks_eq(from, to) { return x }
  d := ib_fresh(bp, a, to)
  i := e_width(ib_b_f(bp), a, Op.OpExt, from.sg, to.ty, from.ty, d, x)
  d
}

## ── bindings (one vreg per binding; shadowing never shares one, §3.3) ──

## What a name is bound to: a scalar's vreg with the type span it was declared with (0/0 when none:
## a pointer's pointee is read from it, slice 3b); a struct local's frame object with its struct
## declaration and type name span (slice 3a); an address-taken scalar local's frame object with its
## declaration's name offset (sema's binding record, slice 3b); or nothing.
IbBind := enum { BdNone, BdVal(VRegId, usize, usize), BdAgg(FrameId, usize, usize, usize), BdMem(FrameId, usize) }

ib_bind_push := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, w : usize, agg : usize, mem : usize, sd : usize, ts : usize, tn : usize) {
  bv : IbB = deref(bp)
  k1 := wb_push(bv.bnames, a, s)
  k2 := wb_push(bv.blens, a, n)
  k3 := wb_push(bv.bvregs, a, w)
  k4 := wb_push(bv.bagg, a, agg)
  k8 := wb_push(bv.bmem, a, mem)
  k5 := wb_push(bv.bsd, a, sd)
  k6 := wb_push(bv.bts, a, ts)
  k7 := wb_push(bv.btn, a, tn)
}
ib_bind := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, v : VRegId) {
  ib_bind_push(bp, a, s, n, usize(v), 0, 0, 0, 0, 0)
}
## Bind `[s, s+n)` to the vreg `v` of a scalar declared with the type spelled `[ts, ts+tn)`.
ib_bind_typed := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, v : VRegId, ts : usize, tn : usize) {
  ib_bind_push(bp, a, s, n, usize(v), 0, 0, 0, ts, tn)
}
## Bind `[s, s+n)` to the struct local in frame object `fr`, of struct type `st`.
ib_bind_agg := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, fr : FrameId, st : IbSt) {
  ib_bind_push(bp, a, s, n, usize(fr), 1, 0, st.di, st.s, st.n)
}
## Bind `[s, s+n)` (declared at name offset `ns`) to the address-taken scalar in frame object `fr`.
ib_bind_mem := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, fr : FrameId, ns : usize) {
  ib_bind_push(bp, a, s, n, usize(fr), 0, 1, ns, 0, 0)
}
## The innermost binding of the name `[s, s+n)`.
ib_lookup := fn(bp : ptr(mut IbB), s : usize, n : usize) -> IbBind {
  bv : IbB = deref(bp)
  mut i := wb_len(bv.bnames)
  while i > 0 {
    i = i - 1
    if wb_get(bv.blens, i) == n and streq(bv.src, wb_get(bv.bnames, i), n, s, n) {
      w := wb_get(bv.bvregs, i)
      if wb_get(bv.bagg, i) == 1 { return IbBind.BdAgg(FrameId(w), wb_get(bv.bsd, i), wb_get(bv.bts, i), wb_get(bv.btn, i)) }
      if wb_get(bv.bmem, i) == 1 { return IbBind.BdMem(FrameId(w), wb_get(bv.bsd, i)) }
      return IbBind.BdVal(VRegId(w), wb_get(bv.bts, i), wb_get(bv.btn, i))
    }
  }
  IbBind.BdNone
}
## Drop the bindings made since the scope that recorded `mark` opened.
ib_wb_cut := fn(w : ptr(mut WBuf), n : usize) { if n < wb_len(w) { deref(w).len = n } }
ib_scope_mark := fn(bp : ptr(mut IbB)) -> usize { bv : IbB = deref(bp); wb_len(bv.bnames) }
ib_scope_drop := fn(bp : ptr(mut IbB), mark : usize) {
  bv : IbB = deref(bp)
  ib_wb_cut(bv.bnames, mark)
  ib_wb_cut(bv.blens, mark)
  ib_wb_cut(bv.bvregs, mark)
  ib_wb_cut(bv.bagg, mark)
  ib_wb_cut(bv.bmem, mark)
  ib_wb_cut(bv.bsd, mark)
  ib_wb_cut(bv.bts, mark)
  ib_wb_cut(bv.btn, mark)
}

## ── the loop stack ──

ib_loop_push := fn(bp : ptr(mut IbB), in out a : rt::Arena, exit : LabelId, cont : LabelId, res : Option(VRegId)) {
  bv : IbB = deref(bp)
  k1 := wb_push(bv.lexit, a, usize(exit))
  k2 := wb_push(bv.lcont, a, usize(cont))
  k3 := wb_push(bv.lbroken, a, 0)
  match res {
    Some(r) => { k4 := wb_push(bv.lres, a, usize(r)); k5 := wb_push(bv.lhasres, a, 1) }
    None => { k6 := wb_push(bv.lres, a, 0); k7 := wb_push(bv.lhasres, a, 0) }
  }
}
## Pop the innermost loop; answers whether a `break` left it.
ib_loop_pop := fn(bp : ptr(mut IbB)) -> bool {
  bv : IbB = deref(bp)
  n := wb_len(bv.lexit) - 1
  broken := wb_get(bv.lbroken, n) == 1
  ib_wb_cut(bv.lexit, n)
  ib_wb_cut(bv.lcont, n)
  ib_wb_cut(bv.lres, n)
  ib_wb_cut(bv.lhasres, n)
  ib_wb_cut(bv.lbroken, n)
  broken
}
## The loop `depth` levels out (0 = innermost) — its index in the stack, when it exists.
ib_loop_at := fn(bp : ptr(mut IbB), depth : usize) -> Option(u64) {
  bv : IbB = deref(bp)
  n := wb_len(bv.lexit)
  if depth >= n { return Option(u64).None }
  Option(u64).Some(u64(n - 1 - depth))
}
## The value vreg of loop `ix`, when it is a value loop.
ib_loop_res := fn(bp : ptr(mut IbB), ix : usize) -> Option(VRegId) {
  bv : IbB = deref(bp)
  if wb_get(bv.lhasres, ix) != 1 { return Option(VRegId).None }
  Option(VRegId).Some(VRegId(wb_get(bv.lres, ix)))
}
ib_loop_exit := fn(bp : ptr(mut IbB), ix : usize) -> LabelId { bv : IbB = deref(bp); LabelId(wb_get(bv.lexit, ix)) }
ib_loop_cont := fn(bp : ptr(mut IbB), ix : usize) -> LabelId { bv : IbB = deref(bp); LabelId(wb_get(bv.lcont, ix)) }
ib_loop_mark_broken := fn(bp : ptr(mut IbB), in out a : rt::Arena, ix : usize) {
  bv : IbB = deref(bp)
  w : WBuf = deref(bv.lbroken)
  deref(word_at(w.data, ix)) = 1
}

## ── expressions ──

## Build `e` and answer the vreg holding its value; `None` once the function is refused.
ib_bx := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) -> Option(VRegId) {
  if ib_b_failed(bp) { return Option(VRegId).None }
  match deref(e) {
    Expr::Num(v, s, n) => { return ib_bx_num(bp, a, e, v) }
    Expr::BoolLit(v) => { bk := ib_konst(bp, a, ib_bool_ks(), v); return Option(VRegId).Some(bk) }
    Expr::Var(s, n) => { return ib_bx_var(bp, a, e, s, n) }
    Expr::Bin(op, l, r) => { return ib_bx_bin(bp, a, e, op, l, r) }
    Expr::If(c, t, x) => { return ib_bx_if(bp, a, e, c, t, x) }
    Expr::Unchecked(inner) => {
      ou := ib_b_unch(bp)
      it := inst0(Op.OpUnch)
      k := emit(ib_b_f(bp), a, it)
      ib_b_set_unch(bp, true)
      v : Option(VRegId) = ib_bx(bp, a, inner)
      ib_b_set_unch(bp, ou)
      ib_plain(bp, a, Op.OpEnd)
      return v
    }
    Expr::Call(cs, cl, na, ah) => { return ib_bx_callv(bp, a, e, cs, cl, na, ah) }
    Expr::Loop(body) => { return ib_bx_value_loop(bp, a, e, body) }
    Expr::Bitcast(inner, ts, tl) => { return ib_bx_bitcast(bp, a, e, inner, ts, tl) }
    Expr::Field(b, fs, fl) => { return ib_bx_field(bp, a, e, b, fs, fl) }
    Expr::Deref(pe) => { return ib_bx_deref(bp, a, e, pe) }
    Expr::AddrOf(pl) => { return ib_bx_addr_of(bp, a, e, pl) }
    Expr::Match | Expr::StructLit | Expr::EnumLit | Expr::StrLit
      | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Lambda
      | Expr::FnRef => { ib_refuse_expr(bp, e, NyWhy.NwOutside) }
  }
  Option(VRegId).None
}

## A call in value position: it must have a result.
ib_bx_callv := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), cs : usize, cl : usize, na : usize, ah : Option(ptr(mut Arg))) -> Option(VRegId) {
  co : CallOut = ib_call(bp, a, e, cs, cl, na, ah)
  match co {
    CoValue(v) => { Option(VRegId).Some(v) }
    CoVoid => { ib_no(bp, e, NyWhy.NwDisagree) }
    CoRefused => { Option(VRegId).None }
  }
}

## A literal takes the type its context gave it (sema's record). One no context typed is refused
## (§3.8.4: never a default). A source literal is never negative; a negative one is a parser desugar
## (`~x` is `x ^ -1`) and takes its canonical form at the type. A source literal the type cannot hold
## is refused as a sema gap rather than wrapped (it can only arise inside a literal-only expression
## `ib_lit_fold` could not fold).
ib_bx_num := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), v : i64) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  cv := ib_canon(v, k)
  if v >= 0 and cv != v { return ib_no(bp, e, NyWhy.NwLit) }
  d := ib_konst(bp, a, k, cv)
  Option(VRegId).Some(d)
}

## The exact value of a literal-only `+ - *` expression, when it and every step of it fit `i64` (a
## comptime number is exact, Types §2.3; a value this cannot represent is not folded, and its literals
## are then built at their own types, where `ib_bx_num` refuses one that does not fit).
ib_lit_fold := fn(e : ptr(Expr)) -> Option(i64) {
  match deref(e) {
    Expr::Num(v, s, n) => {
      if v < 0 { return Option(i64).None }
      Option(i64).Some(v)
    }
    Expr::Bin(op, l, r) => {
      bo : Option(AstBin) = ib_bin_of(op)
      match bo {
        Some(b) => {
          lo : Option(i64) = ib_lit_fold(l)
          ro : Option(i64) = ib_lit_fold(r)
          match lo {
            Some(x) => { match ro { Some(y) => { ib_lit_step(b, x, y) }; None => { Option(i64).None } } }
            None => { Option(i64).None }
          }
        }
        None => { Option(i64).None }
      }
    }
    Expr::BoolLit | Expr::Var | Expr::If | Expr::Match | Expr::StructLit | Expr::Field | Expr::EnumLit | Expr::AddrOf
      | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit | Expr::Slice
      | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Call | Expr::Bitcast | Expr::Loop => { Option(i64).None }
  }
}
## One exact `+ - *` step over `i64`, when the result fits; any other operator is not folded.
IB_I64_MAX : i64 = 9223372036854775807
IB_I64_MIN : i64 = 0 - 9223372036854775807 - 1
IB_MUL_SAFE : i64 = 3037000499
ib_lit_step := fn(b : AstBin, x : i64, y : i64) -> Option(i64) {
  match b {
    BAdd => {
      if (y > 0 and x > IB_I64_MAX - y) or (y < 0 and x < IB_I64_MIN - y) { return Option(i64).None }
      Option(i64).Some(x + y)
    }
    BSub => {
      if (y < 0 and x > IB_I64_MAX + y) or (y > 0 and x < IB_I64_MIN + y) { return Option(i64).None }
      Option(i64).Some(x - y)
    }
    BMul => {
      ## Both factors within ±floor(sqrt(2^63 - 1)): the product cannot overflow. Larger ones are not folded.
      if x > IB_MUL_SAFE or x < 0 - IB_MUL_SAFE or y > IB_MUL_SAFE or y < 0 - IB_MUL_SAFE { return Option(i64).None }
      Option(i64).Some(x * y)
    }
    BDiv | BRem | BBand | BBor | BBxor | BEq | BNe | BLt | BGt | BLe | BGe | BAnd | BOr | BNot => { Option(i64).None }
  }
}
## The folded value `v` of the literal-only expression `e` as a constant of sema's type for `e`. In a
## checked scope a value the type cannot hold is refused (sema accepts only one that fits, so this is a
## gap); inside `unchecked` it wraps to the type's width (CG-7).
ib_lit_const := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), v : i64) -> Option(VRegId) {
  k := ib_int_ty(bp, e)?
  cv := ib_canon(v, k)
  fits := cv == v and (v >= 0 or sgn_eq(k.sg, Sgn.SgS))
  if not fits and not ib_b_unch(bp) { return ib_no(bp, e, NyWhy.NwLit) }
  d := ib_konst(bp, a, k, cv)
  Option(VRegId).Some(d)
}
## A literal's value in the canonical form of its type (§3.2): sign-extended from the width if signed,
## zero-extended if not. Sema refuses a source literal its type cannot hold, so this changes only the
## parser's own desugars — `~x` is `x ^ -1`, and at `u8` the `-1` is the all-ones byte 255.
ib_canon := fn(v : i64, k : IbKS) -> i64 {
  bytes : u64 = kty_bytes(k.ty)
  if bytes >= 8 or not kty_is_int(k.ty) { return v }
  bits : u64 = bytes * 8
  mask : u64 = shl(u64(1), bits) - 1
  ## unchecked-ok: the literal's 64 bits reinterpreted unsigned to mask them to the type's width.
  low : u64 = unchecked bitcast(u64, v) & mask
  if sgn_eq(k.sg, Sgn.SgS) {
    half : u64 = shl(u64(1), bits - 1)
    ## unchecked-ok: `low < 2^bits <= 2^32`, so the subtraction is exact; it sign-extends the narrow value.
    if low >= half { r : i64 = unchecked (i64(low) - i64(shl(u64(1), bits))); return r }
  }
  i64(low)
}

## A name: the innermost local binding, else a module constant or immutable global. Its type is sema's
## record of this use, and it must be the binding's own (both are sema's).
ib_bx_var := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), s : usize, n : usize) -> Option(VRegId) {
  ## A name whose span IS a module value's own name span was resolved by the front half (`m::NAME`,
  ## `driver::d_qual_var`): it is that value, never a local spelled the same.
  idv : Option(u64) = ib_decl_named_at(ib_b_decls(bp), s, n, false)
  match idv { Some(x) => { return ib_bx_global_at(bp, a, e, usize(x)) }; None => {} }
  found : IbBind = ib_lookup(bp, s, n)
  match found {
    BdVal(r, rts, rtn) => { return ib_bx_local(bp, e, r) }
    ## A struct local is memory, never an IR value (§3.2): only a field read, a copy or an aggregate
    ## position reads it.
    BdAgg(fr, sd, ts, tn) => { return ib_no(bp, e, NyWhy.NwOutside) }
    BdMem(mf, mns) => { return ib_bx_mem_read(bp, a, e, mf, mns) }
    BdNone => {}
  }
  ib_bx_global(bp, a, e, s, n)
}
ib_bx_local := fn(bp : ptr(mut IbB), e : ptr(Expr), r : VRegId) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  if not ib_ks_eq(ib_vreg_ks(ib_b_f(bp), r), k) { return ib_no(bp, e, NyWhy.NwDisagree) }
  Option(VRegId).Some(r)
}
## The one value declaration named `[s, s+n)`: the declaration whose own name span it IS (the twins'
## front half rewrites a resolved `m::NAME` to its target's name span, `driver::d_qual_expr`), else the
## one in the function's own module, else the only one in the program. None when there is none or the
## name is ambiguous.
ib_global_decl := fn(bp : ptr(mut IbB), s : usize, n : usize) -> Option(u64) {
  bv : IbB = deref(bp)
  idn : Option(u64) = ib_decl_named_at(bv.decls, s, n, false)
  match idn { Some(x) => { return idn }; None => {} }
  cnt := rt::vec_len(deref(bv.decls))
  mut own : Option(u64) = Option(u64).None
  mut any : Option(u64) = Option(u64).None
  mut nown : usize = 0
  mut nany : usize = 0
  mut i : usize = 0
  while i < cnt {
    d : Decl = deref(ib_decl_ptr(bv.decls, i))
    if not d.is_fn and d.name_len == n and streq(bv.src, d.name_start, d.name_len, s, n) {
      nany = nany + 1
      any = Option(u64).Some(u64(i))
      if d.mod_len == bv.mod_n and streq(bv.src, d.mod_start, d.mod_len, bv.mod_s, bv.mod_n) {
        nown = nown + 1
        own = Option(u64).Some(u64(i))
      }
    }
    i = i + 1
  }
  if nown == 1 { return own }
  if nown == 0 and nany == 1 { return any }
  Option(u64).None
}
## A module constant or immutable global read (§2): `const` when its initializer is a literal, else the
## address of its symbol and a `load` at sema's type (the selector names the symbol by its target's
## existing global naming). A mutable global is a place (slice 3).
ib_bx_global := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), s : usize, n : usize) -> Option(VRegId) {
  gd : Option(u64) = ib_global_decl(bp, s, n)
  match gd {
    Some(x) => { return ib_bx_global_at(bp, a, e, usize(x)) }
    None => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}
ib_bx_global_at := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), di : usize) -> Option(VRegId) {
  src := ib_b_src(bp)
  d : Decl = deref(ib_decl_ptr(ib_b_decls(bp), di))
  mutable := ast::local_is_mut(src, d.name_start)
  ## A mutable module scalar is a place (slice 3b): read from its one-word cell, never folded.
  if (mutable and not lower_layout::global_has_scalar_cell(d)) or ast::binding_is_comptime(src, d.name_start) or not expr_present(d.value) {
    return ib_no(bp, e, NyWhy.NwOutside)
  }
  k := ib_ty(bp, e)?
  lit : Option(i64) = ib_num_value(d.value)
  match lit {
    Some(v) => { if not mutable { d := ib_konst(bp, a, k, ib_canon(v, k)); return Option(VRegId).Some(d) } }
    None => {}
  }
  f := ib_b_f(bp)
  pa := ib_global_addr(bp, a, di, d)
  dv := ib_fresh(bp, a, k)
  od := o_vreg(dv)
  opa := o_vreg(pa)
  on := o_none()
  i2 := e_mem(f, a, Op.OpLoad, k.ty, k.sg, od, opa, 0, on)
  Option(VRegId).Some(dv)
}

ib_bx_bin := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), op : u8, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  bo : Option(AstBin) = ib_bin_of(op)
  match bo {
    Some(b) => { return ib_bx_binop(bp, a, e, b, l, r) }
    None => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}
ib_bx_binop := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), b : AstBin, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  bk : AstBinK = ib_bin_kind(b)
  match bk {
    BkLogic => { ib_bx_logic(bp, a, b, l, r) }
    BkCmp => { ib_bx_cmp(bp, a, e, b, l, r) }
    BkArith => { ib_bx_arith(bp, a, e, b, l, r) }
    BkBits => { ib_bx_bits(bp, a, e, b, l, r) }
  }
}

## `and`, `or`, `not`: regions over a `bool` vreg — short-circuit by construction (#777). `not x` is
## `Bin(not, x, _)`: the right operand is the parser's placeholder and is never built.
ib_bx_logic := fn(bp : ptr(mut IbB), in out a : rt::Arena, b : AstBin, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  res := ib_fresh(bp, a, ib_bool_ks())
  lv := ib_bool_operand(bp, a, l)?
  ib_open_if(bp, a, lv)
  lk : AstLogic = ib_logic_of(b)
  ## `a and b`: b when a, else false. `a or b`: true when a, else b. `not a`: false when a, else true.
  if ib_logic_is_and(lk) {
    rv := ib_bool_operand(bp, a, r)?
    ib_mov(bp, a, res, rv)
  } else {
    t1 := ib_konst(bp, a, ib_bool_ks(), ib_logic_then(lk))
    ib_mov(bp, a, res, t1)
  }
  ib_plain(bp, a, Op.OpElse)
  if ib_logic_is_or(lk) {
    rv2 := ib_bool_operand(bp, a, r)?
    ib_mov(bp, a, res, rv2)
  } else {
    f1 := ib_konst(bp, a, ib_bool_ks(), ib_logic_else(lk))
    ib_mov(bp, a, res, f1)
  }
  ib_plain(bp, a, Op.OpEnd)
  Option(VRegId).Some(res)
}
## The three short-circuit operators.
AstLogic := enum { LAnd, LOr, LNot }
ib_logic_of := fn(b : AstBin) -> AstLogic {
  match b {
    BAnd => { AstLogic.LAnd }; BOr => { AstLogic.LOr }
    BNot | BAdd | BSub | BMul | BDiv | BRem | BBand | BBor | BBxor | BEq | BNe | BLt | BGt | BLe | BGe => { AstLogic.LNot }
  }
}
ib_logic_is_and := fn(k : AstLogic) -> bool { match k { LAnd => { true }; LOr | LNot => { false } } }
ib_logic_is_or := fn(k : AstLogic) -> bool { match k { LOr => { true }; LAnd | LNot => { false } } }
## The constant an arm assigns when it does not evaluate the right operand.
ib_logic_then := fn(k : AstLogic) -> i64 { match k { LOr => { 1 }; LAnd | LNot => { 0 } } }
ib_logic_else := fn(k : AstLogic) -> i64 { match k { LNot => { 1 }; LAnd | LOr => { 0 } } }
## An operand that must be a `bool`.
ib_bool_operand := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) -> Option(VRegId) {
  v := ib_bx(bp, a, e)?
  if not kty_is_bool(vreg_ty(ib_b_f(bp), usize(v))) { return ib_no(bp, e, NyWhy.NwDisagree) }
  Option(VRegId).Some(v)
}

## A comparison. Both operands carry sema's types and must agree; the predicate's `s`/`u` is theirs.
ib_bx_cmp := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), b : AstBin, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  cc : Cc = ib_bin_cc(b)
  lv := ib_bx(bp, a, l)?
  rv := ib_bx(bp, a, r)?
  lk : IbKS = ib_vreg_ks(ib_b_f(bp), lv)
  rk : IbKS = ib_vreg_ks(ib_b_f(bp), rv)
  if not ib_ks_eq(lk, rk) { return ib_no(bp, e, NyWhy.NwDisagree) }
  if kty_is_bool(lk.ty) and cc_is_ordering(cc) { return ib_no(bp, e, NyWhy.NwOutside) }
  d := ib_fresh(bp, a, ib_bool_ks())
  ol := o_vreg(lv)
  orr := o_vreg(rv)
  mut csg : Sgn = lk.sg
  if not cc_is_ordering(cc) or kty_is_bool(lk.ty) { csg = Sgn.SgNone }
  i := e_cmp(ib_b_f(bp), a, cc, csg, lk.ty, d, ol, orr)
  Option(VRegId).Some(d)
}

## Two values, built in source order.
IbPair := struct { l : VRegId, r : VRegId }
## An integer operator `e`: its operands, built first (so a construct outside the subset is named before
## any type is asked for), and the integer result type sema recorded for `e`, which both must have.
## (Flat, not `k : IbKS`: an `Option` of a struct holding a struct crashes the GAS dump path, #NNN.)
IbIntOp := struct { ty : Kty, sg : Sgn, l : VRegId, r : VRegId }
ib_int_operands := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), l : ptr(Expr), r : ptr(Expr)) -> Option(IbIntOp) {
  lv := ib_bx(bp, a, l)?
  rv := ib_bx(bp, a, r)?
  k := ib_int_ty(bp, e)?
  f := ib_b_f(bp)
  if not ib_ks_eq(ib_vreg_ks(f, lv), k) or not ib_ks_eq(ib_vreg_ks(f, rv), k) {
    ib_refuse_expr(bp, e, NyWhy.NwDisagree)
    return Option(IbIntOp).None
  }
  Option(IbIntOp).Some(IbIntOp(ty = k.ty, sg = k.sg, l = lv, r = rv))
}
## The integer result type sema recorded for an operator expression `e`. Pointer arithmetic is a place
## computation (`gep`, slice 3), outside the subset; any other non-integer is sema's records disagreeing.
ib_int_ty := fn(bp : ptr(mut IbB), e : ptr(Expr)) -> Option(IbKS) {
  k := ib_ty(bp, e)?
  if kty_is_ptr(k.ty) {
    ib_refuse_expr(bp, e, NyWhy.NwOutside)
    return Option(IbKS).None
  }
  if not kty_is_int(k.ty) {
    ib_refuse_expr(bp, e, NyWhy.NwDisagree)
    return Option(IbKS).None
  }
  Option(IbKS).Some(k)
}

## Integer arithmetic. The result type is sema's record of `e`. A 64-bit op is emitted at its type; a
## narrow one widens its operands, operates at 64 bits, and narrows back (`fit` checked / `ext`
## wrapping, V3). Checked `+ - *` trap `overflow`; `/` and `%` trap `div_zero`, and `div_overflow` for a
## signed `MIN / -1` (§4). Inside `unchecked`, `+ - *` wrap and `/ %` are the hardware op (D1, CG-7).
ib_bx_arith := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), b : AstBin, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  ## A literal-only `+ - *` is a comptime number (Types §2.3): its exact value takes the type the
  ## context gave the expression, never each literal's. `a : i8 = 0 - 128` is -128, although sema types
  ## the literal `128` at `i8` too, where it does not fit.
  fo : Option(i64) = ib_lit_fold(e)
  match fo {
    Some(v) => { return ib_lit_const(bp, a, e, v) }
    None => {}
  }
  pr := ib_int_operands(bp, a, e, l, r)?
  k := IbKS(ty = pr.ty, sg = pr.sg)
  io : Op = ib_bin_op(b)
  divides := ib_bin_divides(b)
  wk := ib_ks_i64(k.sg)
  lv := ib_ext_to(bp, a, pr.l, wk)
  rv := ib_ext_to(bp, a, pr.r, wk)
  sp := ib_span_of(bp, e)
  f := ib_b_f(bp)
  unch := ib_b_unch(bp)
  if divides and not unch {
    z := ib_fresh(bp, a, ib_bool_ks())
    orv := o_vreg(rv)
    oz := o_imm(0)
    i1 := e_cmp(f, a, Cc.CcEq, Sgn.SgNone, Kty.KI64, z, orv, oz)
    i2 := e_trap_if(f, a, z, TrapKind.TkDivZero, sp, true)
    if sgn_eq(k.sg, Sgn.SgS) and kty_eq(k.ty, Kty.KI64) {
      ## `MIN / -1` overflows only at the full width: a narrow quotient is narrowed (and checked) below.
      m1 := ib_fresh(bp, a, ib_bool_ks())
      m2 := ib_fresh(bp, a, ib_bool_ks())
      olv := o_vreg(lv)
      omin := o_imm(0 - 9223372036854775807 - 1)
      i3 := e_cmp(f, a, Cc.CcEq, Sgn.SgNone, Kty.KI64, m1, olv, omin)
      orv2 := o_vreg(rv)
      oneg := o_imm(0 - 1)
      i4 := e_cmp(f, a, Cc.CcEq, Sgn.SgNone, Kty.KI64, m2, orv2, oneg)
      both := ib_fresh(bp, a, ib_bool_ks())
      ib_open_if(bp, a, m1)
      ib_mov(bp, a, both, m2)
      ib_plain(bp, a, Op.OpElse)
      fz := ib_konst(bp, a, ib_bool_ks(), 0)
      ib_mov(bp, a, both, fz)
      ib_plain(bp, a, Op.OpEnd)
      i5 := e_trap_if(f, a, both, TrapKind.TkDivOverflow, sp, true)
    }
  }
  d := ib_fresh(bp, a, wk)
  ol := o_vreg(lv)
  orr := o_vreg(rv)
  mut tk := TrapKind.TkOverflow
  if divides { tk = TrapKind.TkDivZero }
  if unch {
    mut md := Mode.MdWrap
    if divides { md = Mode.MdHw }
    i6 := e_bin(f, a, io, md, wk.sg, Kty.KI64, d, ol, orr)
  } else {
    i7 := e_binc(f, a, io, wk.sg, Kty.KI64, d, ol, orr, tk, sp)
  }
  ## A narrow quotient that does not fit is `MIN / -1` at the narrow width: a division overflow.
  mut ntk := TrapKind.TkOverflow
  if divides { ntk = TrapKind.TkDivOverflow }
  nd := ib_narrow_to(bp, a, d, k, ntk, sp)
  Option(VRegId).Some(nd)
}

## Bitwise `& | ^` on canonical operands is canonical at any width (V3), so it is emitted at its type.
ib_bx_bits := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), b : AstBin, l : ptr(Expr), r : ptr(Expr)) -> Option(VRegId) {
  pr := ib_int_operands(bp, a, e, l, r)?
  k := IbKS(ty = pr.ty, sg = pr.sg)
  d := ib_fresh(bp, a, k)
  ol := o_vreg(pr.l)
  orr := o_vreg(pr.r)
  io : Op = ib_bin_op(b)
  i := e_bin(ib_b_f(bp), a, io, Mode.MdNone, Sgn.SgNone, k.ty, d, ol, orr)
  Option(VRegId).Some(d)
}

## A value `if`: one result vreg, assigned in each arm.
ib_bx_if := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), c : ptr(Expr), t : ptr(Expr), x : ptr(Expr)) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  res := ib_fresh(bp, a, k)
  cv := ib_bool_operand(bp, a, c)?
  ib_open_if(bp, a, cv)
  tv0 := ib_bx(bp, a, t)?
  tv := ib_coerce(bp, a, tv0, k, t)?
  ib_mov(bp, a, res, tv)
  ib_plain(bp, a, Op.OpElse)
  xv0 := ib_bx(bp, a, x)?
  xv := ib_coerce(bp, a, xv0, k, x)?
  ib_mov(bp, a, res, xv)
  ib_plain(bp, a, Op.OpEnd)
  Option(VRegId).Some(res)
}

## A value `loop { … break v … }`: the result vreg is assigned at each `break v`.
ib_bx_value_loop := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), body : Option(ptr(mut Stmt))) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  res := ib_fresh(bp, a, k)
  ib_bs_loop(bp, a, body, Option(VRegId).Some(res))
  if ib_b_failed(bp) { return Option(VRegId).None }
  Option(VRegId).Some(res)
}

## `unchecked bitcast(T, x)` between integers of one width re-signs the value: `ext` at the same width
## (§4 `bitcast` scalar↔scalar). Every other bitcast is outside slice 1.
ib_bx_bitcast := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), inner : ptr(Expr), ts : usize, tl : usize) -> Option(VRegId) {
  to : Option(IbKS) = ib_name_ks(ib_b_src(bp), ts, tl)
  match to { Some(tk) => {}; None => { return ib_no(bp, e, NyWhy.NwOutside) } }
  xv := ib_bx(bp, a, inner)?
  k := ib_ty(bp, e)?
  match to { Some(tk2) => { if not ib_ks_eq(tk2, k) { return ib_no(bp, e, NyWhy.NwDisagree) } }; None => {} }
  from : IbKS = ib_vreg_ks(ib_b_f(bp), xv)
  if not kty_is_int(from.ty) or not kty_is_int(k.ty) or kty_bytes(from.ty) != kty_bytes(k.ty) { return ib_no(bp, e, NyWhy.NwOutside) }
  rs := ib_ext_to(bp, a, xv, k)
  Option(VRegId).Some(rs)
}

## ── calls ──

## A call: a width conversion when the callee names a scalar type (`u8(x)`, `i64(x)`), a shift or
## rotation operation-function, else a direct call to the one non-generic function of that name whose
## parameters and result are all kernel scalars.
ib_call := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), cs : usize, cl : usize, na : usize, ah : Option(ptr(mut Arg))) -> CallOut {
  src := ib_b_src(bp)
  tk : Option(IbKS) = ib_name_ks(src, cs, cl)
  match tk {
    Some(to) => { cv : Option(VRegId) = ib_bx_conv(bp, a, e, to, na, ah); return ib_call_out(cv) }
    None => {}
  }
  nm := str_at((src + cs), cl)
  so : Option(ShiftK) = ib_shift_of(nm)
  match so {
    Some(sk) => { if na == 2 { sv : Option(VRegId) = ib_bx_shift(bp, a, e, sk, ah); return ib_call_out(sv) } }
    None => {}
  }
  lo : Option(LayoutQ) = ib_layout_q_of(nm)
  match lo {
    Some(q) => {
      if na == 1 and not ib_fn_named(bp, cs, cl) { lv : Option(VRegId) = ib_bx_layout_q(bp, a, e, q, ah); return ib_call_out(lv) }
    }
    None => {}
  }
  ib_call_user(bp, a, e, cs, cl, na, ah)
}
ib_call_out := fn(v : Option(VRegId)) -> CallOut {
  match v { Some(x) => { CallOut.CoValue(x) }; None => { CallOut.CoRefused } }
}

## `T(x)` for a kernel integer or `bool` `T`. A literal argument is the constant at `T`, wrapped to its
## width inside `unchecked` (Types §9.2, CG-7; sema refuses one that does not fit in a checked scope).
## An integer is widened, or narrowed by `fit` (`narrow` trap) — `ext` inside `unchecked` (§4). A `bool`
## becomes 0 or 1.
ib_bx_conv := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), to : IbKS, na : usize, ah : Option(ptr(mut Arg))) -> Option(VRegId) {
  if na != 1 or not kty_is_int(to.ty) { return ib_no(bp, e, NyWhy.NwOutside) }
  a0 := deref(arg_at(ah, "argument list ended early"))
  lk : VTy = sty_get(a0.e)
  if vty_is_lit(lk) {
    nv : Option(i64) = ib_num_value(a0.e)
    match nv { Some(lv) => { c := ib_konst(bp, a, to, ib_canon(lv, to)); return Option(VRegId).Some(c) }; None => {} }
  }
  xv := ib_bx(bp, a, a0.e)?
  from : IbKS = ib_vreg_ks(ib_b_f(bp), xv)
  if kty_is_bool(from.ty) {
    res := ib_fresh(bp, a, to)
    ib_open_if(bp, a, xv)
    one := ib_konst(bp, a, to, 1)
    ib_mov(bp, a, res, one)
    ib_plain(bp, a, Op.OpElse)
    zero := ib_konst(bp, a, to, 0)
    ib_mov(bp, a, res, zero)
    ib_plain(bp, a, Op.OpEnd)
    return Option(VRegId).Some(res)
  }
  if not kty_is_int(from.ty) { return ib_no(bp, e, NyWhy.NwOutside) }
  w := ib_ext_to(bp, a, xv, ib_ks_i64(from.sg))
  sp := ib_span_of(bp, e)
  nw := ib_narrow_to(bp, a, w, to, TrapKind.TkNarrow, sp)
  Option(VRegId).Some(nw)
}

## `shl/shr/rotl/rotr(v, n)` (Types §2.2, §3.2; OP-6). The value's type is sema's record of the call
## (its first operand's); the count is an integer, taken at 64 bits. A shift traps `shift_range` when
## `n >= N`, N the TYPE's width (a checked guard, Concurrency §6.1); inside `unchecked` it is the
## hardware shift (§6.2). `shr` is arithmetic on a signed type, logical on an unsigned one. A rotation
## is total (count mod N). A narrow type shifts at 64 bits and wraps back to its width (V3).
ib_bx_shift := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), sk : ShiftK, ah : Option(ptr(mut Arg))) -> Option(VRegId) {
  a0 := deref(arg_at(ah, "argument list ended early"))
  a1 := deref(arg_at(a0.next, "argument list ended early"))
  xv0 := ib_bx(bp, a, a0.e)?
  nv0 := ib_bx(bp, a, a1.e)?
  k := ib_int_ty(bp, e)?
  xv := ib_coerce(bp, a, xv0, k, a0.e)?
  nk : IbKS = ib_vreg_ks(ib_b_f(bp), nv0)
  if not kty_is_int(nk.ty) { return ib_no(bp, a1.e, NyWhy.NwDisagree) }
  nv := ib_ext_to(bp, a, nv0, ib_ks_i64(nk.sg))
  sp := ib_span_of(bp, e)
  if ib_shift_is_rot(sk) { rr := ib_rotate(bp, a, sk, k, xv, nv); return Option(VRegId).Some(rr) }
  f := ib_b_f(bp)
  io : Op = ib_shift_op(sk)
  if kty_eq(k.ty, Kty.KI64) {
    d := ib_fresh(bp, a, k)
    ox := o_vreg(xv)
    on := o_vreg(nv)
    if ib_b_unch(bp) { i1 := e_bin(f, a, io, Mode.MdHw, k.sg, k.ty, d, ox, on) }
    else { i2 := e_binc(f, a, io, k.sg, k.ty, d, ox, on, TrapKind.TkShiftRange, sp) }
    return Option(VRegId).Some(d)
  }
  wx := ib_ext_to(bp, a, xv, ib_ks_i64(k.sg))
  r := ib_shift_wide(bp, a, io, k, wx, nv, sp)
  wr := ib_wrap_to(bp, a, r, k)
  Option(VRegId).Some(wr)
}
## The 64-bit shift of a narrow `k` value `wx` (already widened) by `n`. Inside `unchecked` it is the
## hardware shift. Otherwise the guard is the TYPE's width, so the 64-bit shift after it is proven in
## range.
ib_shift_wide := fn(bp : ptr(mut IbB), in out a : rt::Arena, io : Op, k : IbKS, wx : VRegId, n : VRegId, sp : usize) -> VRegId {
  f := ib_b_f(bp)
  wk := ib_ks_i64(k.sg)
  if ib_b_unch(bp) {
    r := ib_fresh(bp, a, wk)
    ox := o_vreg(wx)
    on := o_vreg(n)
    i1 := e_bin(f, a, io, Mode.MdHw, wk.sg, wk.ty, r, ox, on)
    return r
  }
  over := ib_fresh(bp, a, ib_bool_ks())
  onv := o_vreg(n)
  onw := o_imm(i64(ib_ks_bits(k)))
  i2 := e_cmp(f, a, Cc.CcGe, Sgn.SgU, Kty.KI64, over, onv, onw)
  i3 := e_trap_if(f, a, over, TrapKind.TkShiftRange, sp, true)
  on2 := o_vreg(n)
  ib_proven(bp, a, io, wk, wx, on2)
}
## A rotation of `x : k` by the 64-bit count `n`. At 64 bits it is the `rotl`/`rotr` op. A narrow type
## rotates its N low bits: with `z` the value's bits zero-extended and `c = n mod N`,
## `rotl = (z << c) | (z >> (N - c))` (and the mirror for `rotr`), every shift proven in range because
## `c < N <= 32`; the result wraps back to the type (V3).
ib_rotate := fn(bp : ptr(mut IbB), in out a : rt::Arena, sk : ShiftK, k : IbKS, x : VRegId, n : VRegId) -> VRegId {
  f := ib_b_f(bp)
  if kty_eq(k.ty, Kty.KI64) {
    d := ib_fresh(bp, a, k)
    ox := o_vreg(x)
    on := o_vreg(n)
    io : Op = ib_shift_op(sk)
    i0 := e_bin(f, a, io, Mode.MdNone, Sgn.SgNone, k.ty, d, ox, on)
    return d
  }
  uk := ib_ks_i64(Sgn.SgU)
  bits := ib_ks_bits(k)
  wx := ib_ext_to(bp, a, x, ib_ks_i64(k.sg))
  ux := ib_ext_to(bp, a, wx, uk)
  z := ib_fresh(bp, a, uk)
  oux := o_vreg(ux)
  omask := o_imm(i64(shl(u64(1), bits) - 1))
  i1 := e_bin(f, a, Op.OpAnd, Mode.MdNone, Sgn.SgNone, Kty.KI64, z, oux, omask)
  un := ib_ext_to(bp, a, n, uk)
  c := ib_fresh(bp, a, uk)
  oun := o_vreg(un)
  ocm := o_imm(i64(bits - 1))
  i2 := e_bin(f, a, Op.OpAnd, Mode.MdNone, Sgn.SgNone, Kty.KI64, c, oun, ocm)
  nn := ib_konst(bp, a, uk, i64(bits))
  oc := o_vreg(c)
  rest := ib_proven(bp, a, Op.OpSub, uk, nn, oc)
  mut first : Op = Op.OpShl
  mut second : Op = Op.OpShr
  match sk {
    SkRotr => { first = Op.OpShr; second = Op.OpShl }
    SkRotl | SkShl | SkShr => {}
  }
  oc2 := o_vreg(c)
  lo := ib_proven(bp, a, first, uk, z, oc2)
  orest := o_vreg(rest)
  hi := ib_proven(bp, a, second, uk, z, orest)
  both := ib_fresh(bp, a, uk)
  olo := o_vreg(lo)
  ohi := o_vreg(hi)
  i3 := e_bin(f, a, Op.OpOr, Mode.MdNone, Sgn.SgNone, Kty.KI64, both, olo, ohi)
  sx := ib_ext_to(bp, a, both, ib_ks_i64(k.sg))
  ib_wrap_to(bp, a, sx, k)
}

## A direct call to a user function. Each argument takes its parameter's declared type (widened by
## `ib_coerce` when sema accepted a narrower integer); the result is sema's record of the call, and it
## must be the callee's declared result.
ib_call_user := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), cs : usize, cl : usize, na : usize, ah : Option(ptr(mut Arg))) -> CallOut {
  ci : Option(u64) = ib_callee_decl(bp, cs, cl)
  match ci {
    Some(x) => { return ib_call_decl(bp, a, e, usize(x), na, ah) }
    None => {}
  }
  ib_refuse_expr(bp, e, NyWhy.NwOutside)
  CallOut.CoRefused
}
ib_call_decl := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), di : usize, na : usize, ah : Option(ptr(mut Arg))) -> CallOut {
  src := ib_b_src(bp)
  d : Decl = deref(ib_decl_ptr(ib_b_decls(bp), di))
  ## Only an Alatyr function with a body is called through the Alatyr convention; a syscall or an extern
  ## is slice 2's `syscall` / `call_c`, and more than 8 arguments are not modelled (docs/ir-slice-1.md §3).
  if d.arity != na or na > 8 or lower::extern_symbol(src, d.name_start, d.name_len).n != 0 {
    ib_refuse_expr(bp, e, NyWhy.NwOutside)
    return CallOut.CoRefused
  }
  ## The result first: a callee whose result is not a kernel scalar is outside the subset, and sema's
  ## record of the call must be that result.
  mut res : Option(IbKS) = Option(IbKS).None
  if d.ret_tl != 0 {
    res = ib_call_result(bp, e, d)
    if ib_b_failed(bp) { return CallOut.CoRefused }
  }
  ## The argument vregs are built first, then pushed onto the pool as one run.
  args := wb_new(a, 8)
  mut pp := d.params_head
  mut g : Option(ptr(mut Arg)) = ah
  loop {
    match g {
      Some(gq) => {
        ga := deref(arg_p(gq))
        ## An argument with no parameter left is a call sema would not accept; the builder refuses it
        ## rather than read past the list.
        match pp {
          Some(pq) => {
            pm := deref(param_p(pq))
            avo : Option(VRegId) = ib_arg(bp, a, e, pm, ga.e)
            match avo { Some(av) => { k1 := wb_push(args, a, usize(av)) }; None => { return CallOut.CoRefused } }
            pp = pm.next
          }
          None => { return CallOut.CoRefused }
        }
        g = ga.next
      }
      None => { break }
    }
  }
  f := ib_b_f(bp)
  mut it := inst0(Op.OpCall)
  dnm := str_at((src + d.name_start), d.name_len)
  sym := prog_sym(ib_b_p(bp), a, di, dnm.ptr, dnm.len)
  ocallee := o_sym(sym)
  set_a(it, ocallee)
  mut j : usize = 0
  while j < wb_len(args) {
    slot := pool_push(f, a, wb_get(args, j))
    if j == 0 { it.pool = slot }
    j = j + 1
  }
  it.n = na
  match res {
    Some(kr) => {
      rv := ib_fresh(bp, a, kr)
      set_dst(it, rv)
      i := emit(f, a, it)
      return CallOut.CoValue(rv)
    }
    None => {}
  }
  i0 := emit(f, a, it)
  CallOut.CoVoid
}
## The kernel result of callee `d`, which must be sema's record of the call `e`.
ib_call_result := fn(bp : ptr(mut IbB), e : ptr(Expr), d : Decl) -> Option(IbKS) {
  rk : Option(IbKS) = ib_name_ks(ib_b_src(bp), d.ret_ts, d.ret_tl)
  match rk {
    Some(kr) => { return ib_call_result_is(bp, e, kr) }
    None => {}
  }
  ib_refuse_expr(bp, e, NyWhy.NwOutside)
  Option(IbKS).None
}
ib_call_result_is := fn(bp : ptr(mut IbB), e : ptr(Expr), kr : IbKS) -> Option(IbKS) {
  ke := ib_ty(bp, e)?
  if ib_ks_eq(ke, kr) { return Option(IbKS).Some(kr) }
  ib_refuse_expr(bp, e, NyWhy.NwDisagree)
  Option(IbKS).None
}
## One argument `ae` of the call `e`, at its parameter `pm`'s declared kernel type.
ib_arg := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), pm : Param, ae : ptr(Expr)) -> Option(VRegId) {
  pk : Option(IbKS) = ib_name_ks(ib_b_src(bp), pm.ts, pm.tl)
  match pk {
    Some(want) => { if pm.pmode == 0 { return ib_value_at(bp, a, ae, want) } }
    None => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}
## The value of an integer literal node.
ib_num_value := fn(e : ptr(Expr)) -> Option(i64) {
  match deref(e) {
    Expr::Num(v, s, n) => { Option(i64).Some(v) }
    Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef
      | Expr::Bitcast | Expr::Loop => { Option(i64).None }
  }
}
## unchecked-ok: `decls` holds Decl record addresses (the parser's `rt::Vec` of handles).
ib_decl_ptr := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { unchecked bitcast(ptr(Decl), rt::vec_get(deref(decls), i)) }
## The declaration whose own name span is exactly `[s, s+n)` — a function when `want_fn`, else a value —
## the identity a call or a name carries once the front half resolved it (`driver::d_qual_expr`).
ib_decl_named_at := fn(decls : ptr(rt::Vec), s : usize, n : usize, want_fn : bool) -> Option(u64) {
  cnt := rt::vec_len(deref(decls))
  mut i : usize = 0
  while i < cnt {
    d : Decl = deref(ib_decl_ptr(decls, i))
    if d.name_start == s and d.name_len == n and n != 0 and d.is_fn == want_fn { return Option(u64).Some(u64(i)) }
    i = i + 1
  }
  Option(u64).None
}
## The function a call to `[cs, cs+cl)` names: the declaration the call's span IS (resolved by the front
## half), else the ONE non-generic function declaration of that name; none when there is no such function
## or several (an overload set is the mangling's, `docs/ir-slice-2.md`, so it is refused here).
ib_callee_decl := fn(bp : ptr(mut IbB), cs : usize, cl : usize) -> Option(u64) {
  decls := ib_b_decls(bp)
  src := ib_b_src(bp)
  idc : Option(u64) = ib_decl_named_at(decls, cs, cl, true)
  match idc {
    Some(x) => {
      dx : Decl = deref(ib_decl_ptr(decls, usize(x)))
      if dx.is_generic { return Option(u64).None }
      return idc
    }
    None => {}
  }
  cnt := rt::vec_len(deref(decls))
  mut found : Option(u64) = Option(u64).None
  mut hits : usize = 0
  mut i : usize = 0
  while i < cnt {
    d : Decl = deref(ib_decl_ptr(decls, i))
    if d.is_fn and d.name_len == cl and streq(src, d.name_start, d.name_len, cs, cl) {
      hits = hits + 1
      if not d.is_generic { found = Option(u64).Some(u64(i)) }
    }
    i = i + 1
  }
  if hits != 1 { return Option(u64).None }
  found
}

## ── aggregates (slice 3a, `docs/ir-slice-3.md` §1) ──
##
## A struct local is a FRAME OBJECT (`docs/ir.md` §3.3), never an IR value (§3.2): a struct literal is
## built field by field into a fresh object, a field read is a `load` and a field write a `store` at the
## field's byte offset, and a whole-struct assignment is a `copy`. The layout comes from `lower_layout`
## once, here (`field_byte_place`, `layout_type_size_bytes`); the IR carries only byte offsets and
## widths. In 3a an aggregate never crosses a call (a struct parameter or result is still
## `NotYet(signature)`), so the layout is internal to one function.
##
## Sema records an aggregate as `VcAgg` with no type name (`docs/ir-slice-3.md` §3.4), so the struct
## TYPE is taken from the declaration the expression names: a binding's annotation, a struct literal's
## name, the struct local a name is bound to. Every scalar the builder reads out of a struct is still
## sema's: a field read takes sema's record of it (a gap when sema left it untyped) and that record
## must be the field's declared type, else the function is refused (`NwDisagree`). That is what types
## a signed field's division signed (#765).
##
## 3a builds a WORD- or BYTE-tier struct (`lower_layout::layout_kind`) whose every field is a kernel
## scalar and that carries no layout attribute (`@packed`, `@align`, `@offset`, `@endian` are slice
## 3e); any other struct is `NotYet(outside)`.

## A struct type the builder lays out: its declaration's index, the name span it was named by (the
## span `lower_layout` resolves), its byte size and its alignment (the values `size(T)`/`align(T)`
## answer).
IbSt := struct { di : usize, s : usize, n : usize, size : usize, align : usize }
## A field of a struct: its byte offset in the object and its kernel type.
IbFld := struct { off : ByteOff, ty : Kty, sg : Sgn }
## An aggregate value in memory: its frame object, and whether the builder made that object for this
## value alone (a literal's fresh object may be bound directly; a local's must be copied).
IbObj := struct { fr : FrameId, fresh : bool }

## Is a recorded value type an aggregate?
ib_vty_is_agg := fn(t : VTy) -> bool {
  c : VCls = t.cls
  match c { VcAgg => { true }; VcAbsent | VcUnknown | VcLit | VcInt | VcBool | VcPtr | VcFloat => { false } }
}

## The struct type named `[s, s+n)`, when the builder lays it out (see the band comment).
ib_struct_named := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize) -> Option(IbSt) {
  bv : IbB = deref(bp)
  sdi := lower_layout::struct_decl_of(bv.decls, bv.src, s, n)
  if sdi < 0 { return Option(IbSt).None }
  d : Decl = deref(ib_decl_ptr(bv.decls, usize(sdi)))
  if d.is_generic { return Option(IbSt).None }
  lk := lower_layout::layout_kind(bv.decls, bv.src, s, n, a)
  if lower_layout::layout_kind_is_packed(lk) { return Option(IbSt).None }
  if lower_layout::struct_align_attr(bv.decls, bv.src, s, n) >= 1 { return Option(IbSt).None }
  mut f := d.fields_head
  mut nf : usize = 0
  loop {
    match f {
      Some(fq) => {
        fd := deref(ast::fld_p(fq))
        ko : Option(IbKS) = ib_name_ks(bv.src, fd.ts, fd.tl)
        match ko { Some(k) => {}; None => { return Option(IbSt).None } }
        if fd.wsize != 1 { return Option(IbSt).None }
        if lower_layout::field_offset_attr(bv.src, fd.ns) >= 0 or lower_layout::field_align_attr(bv.src, fd.ns) >= 0
          or lower_layout::field_endian_attr(bv.src, fd.ns) >= 0 { return Option(IbSt).None }
        nf = nf + 1
        f = fd.next
      }
      None => { break }
    }
  }
  if nf == 0 { return Option(IbSt).None }
  sz := lower_layout::layout_type_size_bytes(bv.decls, bv.src, s, n, a)
  if sz == 0 { return Option(IbSt).None }
  ## The struct's alignment as `align(T)` answers it: the §6.1 alignment in the BYTE tier, one machine
  ## word in the WORD tier.
  mut al : usize = 8
  if lower_layout::layout_kind_is_byte(lk) { al = lower_layout::standard_struct_align(bv.decls, bv.src, s, n, a) }
  Option(IbSt).Some(IbSt(di = usize(sdi), s = s, n = n, size = sz, align = al))
}
## The struct type of a struct local bound with declaration `sd` and type span `[ts, ts+tn)`.
ib_struct_bound := fn(bp : ptr(mut IbB), in out a : rt::Arena, sd : usize, ts : usize, tn : usize) -> Option(IbSt) {
  so : Option(IbSt) = ib_struct_named(bp, a, ts, tn)
  match so { Some(st) => { if st.di == sd { return so } }; None => {} }
  Option(IbSt).None
}
## Does struct `st` have a field narrower than its slot (padding the literal must not leave undefined)?
ib_struct_padded := fn(bp : ptr(mut IbB), st : IbSt) -> bool {
  bv : IbB = deref(bp)
  d : Decl = deref(ib_decl_ptr(bv.decls, st.di))
  mut f := d.fields_head
  mut w : usize = 0
  loop {
    match f {
      Some(fq) => {
        fd := deref(ast::fld_p(fq))
        ko : Option(IbKS) = ib_name_ks(bv.src, fd.ts, fd.tl)
        match ko { Some(k) => { w = w + usize(kty_bytes(k.ty)) }; None => { return true } }
        f = fd.next
      }
      None => { break }
    }
  }
  w != st.size
}
## Field `[fs, fs+fl)` of struct `st`: its declared kernel type and its byte place.
ib_field := fn(bp : ptr(mut IbB), in out a : rt::Arena, st : IbSt, fs : usize, fl : usize) -> Option(IbFld) {
  bv : IbB = deref(bp)
  d : Decl = deref(ib_decl_ptr(bv.decls, st.di))
  mut f := d.fields_head
  loop {
    match f {
      Some(fq) => {
        fd := deref(ast::fld_p(fq))
        if fd.nl == fl and streq(bv.src, fd.ns, fd.nl, fs, fl) {
          ko : Option(IbKS) = ib_name_ks(bv.src, fd.ts, fd.tl)
          match ko {
            Some(k) => {
              fp := lower_layout::field_byte_place(bv.decls, bv.src, st.s, st.n, fs, fl, a)
              if not fp.addressable or fp.off < 0 { return Option(IbFld).None }
              ## V6 holds the access inside the object; this keeps a place past it out of the IR.
              if usize(fp.off) + usize(kty_bytes(k.ty)) > st.size { return Option(IbFld).None }
              return Option(IbFld).Some(IbFld(off = ByteOff(usize(fp.off)), ty = k.ty, sg = k.sg))
            }
            None => { return Option(IbFld).None }
          }
        }
        f = fd.next
      }
      None => { break }
    }
  }
  Option(IbFld).None
}

## A fresh frame object for one value of struct `st` (§3.3: one object per value, never a pool).
ib_new_obj := fn(bp : ptr(mut IbB), in out a : rt::Arena, st : IbSt) -> FrameId { new_frame(ib_b_f(bp), a, st.size, st.align) }
ib_store_field := fn(bp : ptr(mut IbB), in out a : rt::Arena, fr : FrameId, fd : IbFld, v : VRegId) {
  ofr := o_frame(fr)
  ib_store_at(bp, a, ofr, fd, v)
}
ib_load_field := fn(bp : ptr(mut IbB), in out a : rt::Arena, fr : FrameId, fd : IbFld) -> VRegId {
  ofr := o_frame(fr)
  ib_load_at(bp, a, ofr, fd)
}
## `store T [base + off], v` / `%d = load T [base + off]` — `base` a frame object or a `ptr` vreg, the
## place's offset and kernel type in `fd`.
ib_store_at := fn(bp : ptr(mut IbB), in out a : rt::Arena, base : Opnd, fd : IbFld, v : VRegId) {
  on := o_none()
  ov := o_vreg(v)
  i := e_mem(ib_b_f(bp), a, Op.OpStore, fd.ty, Sgn.SgNone, on, base, byte_off_imm(fd.off), ov)
}
ib_load_at := fn(bp : ptr(mut IbB), in out a : rt::Arena, base : Opnd, fd : IbFld) -> VRegId {
  d := ib_fresh(bp, a, IbKS(ty = fd.ty, sg = fd.sg))
  od := o_vreg(d)
  on := o_none()
  i := e_mem(ib_b_f(bp), a, Op.OpLoad, fd.ty, fd.sg, od, base, byte_off_imm(fd.off), on)
  d
}
## `copy $dst, $src, n` — a whole struct value.
ib_copy_obj := fn(bp : ptr(mut IbB), in out a : rt::Arena, dst : FrameId, src : FrameId, n : usize) {
  mut it := inst0(Op.OpCopy)
  od := o_frame(dst)
  os := o_frame(src)
  set_a(it, od)
  set_b(it, os)
  it.n = n
  i := emit(ib_b_f(bp), a, it)
}
## `zero $k, n`.
ib_zero_obj := fn(bp : ptr(mut IbB), in out a : rt::Arena, fr : FrameId, n : usize) {
  mut it := inst0(Op.OpZero)
  ofr := o_frame(fr)
  set_a(it, ofr)
  it.n = n
  i := emit(ib_b_f(bp), a, it)
}

## The struct type an aggregate expression names by its own declaration: a struct literal's name, or
## the struct local a name is bound to. Anything else is `None` (sema does not record it, §3.4).
ib_agg_type_of := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) -> Option(IbSt) {
  match deref(e) {
    Expr::StructLit(ss, sl, nf, fh) => { return ib_struct_named(bp, a, ss, sl) }
    Expr::Var(s, n) => {
      if ib_names_global(bp, s, n) { return Option(IbSt).None }
      b : IbBind = ib_lookup(bp, s, n)
      match b {
        BdAgg(fr, sd, ts, tn) => { return ib_struct_bound(bp, a, sd, ts, tn) }
        BdVal(v, vts, vtn) => {}
        BdMem(mf, mns) => {}
        BdNone => {}
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::Field | Expr::EnumLit
      | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit
      | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => {}
  }
  Option(IbSt).None
}
## Does the name `[s, s+n)` resolve to a module value by span identity (`m::NAME` after the front half)?
ib_names_global := fn(bp : ptr(mut IbB), s : usize, n : usize) -> bool {
  g : Option(u64) = ib_decl_named_at(ib_b_decls(bp), s, n, false)
  match g { Some(x) => { true }; None => { false } }
}

## The aggregate value `e` of struct type `st`, in memory. Sema must have recorded `e` as an aggregate.
ib_agg := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), st : IbSt) -> Option(IbObj) {
  if ib_b_failed(bp) { return Option(IbObj).None }
  t : VTy = sty_get(e)
  if not ib_vty_is_agg(t) {
    mut w : NyWhy = ib_vty_why(t)
    if not nywhy_is_gap(w) { w = NyWhy.NwDisagree }
    ib_refuse_expr(bp, e, w)
    return Option(IbObj).None
  }
  et : Option(IbSt) = ib_agg_type_of(bp, a, e)
  match et {
    Some(x) => {
      if x.di != st.di {
        ib_refuse_expr(bp, e, NyWhy.NwDisagree)
        return Option(IbObj).None
      }
    }
    None => {
      ib_refuse_expr(bp, e, NyWhy.NwOutside)
      return Option(IbObj).None
    }
  }
  match deref(e) {
    Expr::StructLit(ss, sl, nf, fh) => { return ib_agg_lit(bp, a, e, st, nf, fh) }
    Expr::Var(s, n) => {
      b : IbBind = ib_lookup(bp, s, n)
      match b {
        BdAgg(fr, sd, ts, tn) => { return Option(IbObj).Some(IbObj(fr = fr, fresh = false)) }
        BdVal(v, vts, vtn) => {}
        BdMem(mf, mns) => {}
        BdNone => {}
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::Field | Expr::EnumLit
      | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit
      | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => {}
  }
  ib_refuse_expr(bp, e, NyWhy.NwOutside)
  Option(IbObj).None
}
## A struct literal `S(f0 = e0, …)` into a fresh object. The parser hands the initializers over in the
## struct's DECLARATION order (TYP-8), and they are evaluated and stored in that order; a literal that
## does not initialize every field is outside 3a. A struct with padding is zeroed first, so no byte of
## the object is undefined.
ib_agg_lit := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), st : IbSt, nf : usize, fh : Option(ptr(mut Arg))) -> Option(IbObj) {
  bv : IbB = deref(bp)
  d : Decl = deref(ib_decl_ptr(bv.decls, st.di))
  fr := ib_new_obj(bp, a, st)
  if ib_struct_padded(bp, st) { ib_zero_obj(bp, a, fr, st.size) }
  mut f := d.fields_head
  mut g : Option(ptr(mut Arg)) = fh
  loop {
    match f {
      Some(fq) => {
        fd := deref(ast::fld_p(fq))
        match g {
          Some(gq) => {
            ga := deref(arg_p(gq))
            flo : Option(IbFld) = ib_field(bp, a, st, fd.ns, fd.nl)
            match flo {
              Some(fld) => {
                vo : Option(VRegId) = ib_value_ctx(bp, a, ga.e, IbKS(ty = fld.ty, sg = fld.sg))
                match vo { Some(v) => { ib_store_field(bp, a, fr, fld, v) }; None => { return Option(IbObj).None } }
              }
              None => { ib_refuse_expr(bp, e, NyWhy.NwOutside); return Option(IbObj).None }
            }
            g = ga.next
          }
          None => { ib_refuse_expr(bp, e, NyWhy.NwOutside); return Option(IbObj).None }
        }
        f = fd.next
      }
      None => { break }
    }
  }
  match g { Some(gx) => { ib_refuse_expr(bp, e, NyWhy.NwOutside); return Option(IbObj).None }; None => {} }
  Option(IbObj).Some(IbObj(fr = fr, fresh = true))
}

## `s := e` / `s : S = e` for a struct local: the struct type is the annotation's, else the one the
## initializer names. A fresh literal's object becomes the local's; any other value is copied into a
## fresh object of its own (a local never shares another's memory).
ib_bs_agg_decl := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, nl : usize, v : ptr(Expr)) {
  src := ib_b_src(bp)
  lts := ast::local_type_span(src, ns, nl)
  mut sto : Option(IbSt) = Option(IbSt).None
  if lts.n != 0 { sto = ib_struct_named(bp, a, lts.s, lts.n) } else { sto = ib_agg_type_of(bp, a, v) }
  match sto {
    Some(st) => {
      oo : Option(IbObj) = ib_agg(bp, a, v, st)
      match oo {
        Some(o) => {
          if o.fresh { ib_bind_agg(bp, a, ns, nl, o.fr, st); return }
          fr := ib_new_obj(bp, a, st)
          ib_copy_obj(bp, a, fr, o.fr, st.size)
          ib_bind_agg(bp, a, ns, nl, fr, st)
        }
        None => {}
      }
    }
    None => { ib_refuse_stmt(bp, h, NyWhy.NwOutside) }
  }
}
## `s = e` into the struct local in object `fr`: the value is built in its own object first (a literal
## reading `s` itself sees the old value), then copied.
ib_bs_agg_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), fr : FrameId, sd : usize, ts : usize, tn : usize, v : ptr(Expr)) {
  sto : Option(IbSt) = ib_struct_bound(bp, a, sd, ts, tn)
  match sto {
    Some(st) => {
      oo : Option(IbObj) = ib_agg(bp, a, v, st)
      match oo { Some(o) => { ib_copy_obj(bp, a, fr, o.fr, st.size) }; None => {} }
    }
    None => { ib_refuse_stmt(bp, h, NyWhy.NwOutside) }
  }
}
## ── places (slice 3b, `docs/ir-slice-3.md` §6) ──
##
## A field is read or written at a PLACE: a base address — a struct local's frame object, or a `ptr`
## vreg whose declared type is `ptr(S)` / `ptr(mut S)` — and the struct type there. Through a pointer
## the memory may have been written, or may be read, by a legacy-emitted function, so the IR must use
## the layout the twin's legacy emitter uses for that type (`docs/ir.md` §3.7, rule 7.1.1). That
## agreement is PROVED only for the WORD tier with 8-byte scalar fields — every model places field `i`
## at byte `8 * i` and moves the whole word (`test/ir_ptr_agree.al` writes in each and reads in the
## other) — so a struct reached through a pointer must be WORD tier; a BYTE-tier struct is `NotYet`
## there. A struct local's own fields (slice 3a) never cross, so any tier 3a builds is fine there.
## Likewise a scalar read or written through `deref(p)`, or an address-taken scalar local, must be an
## 8-byte kernel type: a narrower store through a pointer would leave the upper bytes of a word a
## legacy reader loads whole.

## A place: its base operand's kind and payload, and the struct type there. Flat — the base is not an
## `Opnd` field — because an `Option` of a struct holding a struct crashes the frozen seed's build (the
## note at `IbIntOp`).
IbPlace := struct { bk : OpndK, bv : i64, di : usize, s : usize, n : usize }
ib_place_base := fn(pl : IbPlace) -> Opnd { Opnd(k = pl.bk, v = pl.bv) }
## The struct type `pl` names.
ib_place_st := fn(bp : ptr(mut IbB), in out a : rt::Arena, pl : IbPlace) -> Option(IbSt) { ib_struct_bound(bp, a, pl.di, pl.s, pl.n) }

## The type a binding of a pointer declared `[ts, ts+tn)` points at, when it spells one.
ib_pointee := fn(bp : ptr(mut IbB), ts : usize, tn : usize) -> Option(IbSpan) {
  if tn == 0 { return Option(IbSpan).None }
  src := ib_b_src(bp)
  full : IbSpan = ib_ptr_type_span(src, ts, tn)
  ps := lower_layout::ptr_target_pointee_s(src, full.s, full.n)
  pn := lower_layout::ptr_target_pointee_n(src, full.s, full.n)
  if pn == 0 { return Option(IbSpan).None }
  Option(IbSpan).Some(IbSpan(s = ps, n = pn))
}
## A source span `[s, s+n)`.
IbSpan := struct { s : usize, n : usize }
## The whole `ptr( … )` type a declared type span starts: a parameter's annotation span covers only
## the `ptr` head (the parser records the head), so the `( … )` group after it is found by bracket
## depth, within the published source extent. Any other span is answered unchanged.
ib_ptr_type_span := fn(src : ptr(u8), ts : usize, tn : usize) -> IbSpan {
  end := ast::src_extent()
  if tn < 3 or ts + 3 > end or str_at((src + ts), 3) != "ptr" { return IbSpan(s = ts, n = tn) }
  mut p := ts + 3
  while p < end and str_at((src + p), 1) == " " { p = p + 1 }
  if p >= end or str_at((src + p), 1) != "(" { return IbSpan(s = ts, n = tn) }
  mut depth : usize = 0
  while p < end {
    c := str_at((src + p), 1)
    if c == "(" { depth = depth + 1 }
    if c == ")" {
      depth = depth - 1
      if depth == 0 { return IbSpan(s = ts, n = p + 1 - ts) }
    }
    if c == "\n" or c == "=" or c == "{" { return IbSpan(s = ts, n = tn) }
    p = p + 1
  }
  IbSpan(s = ts, n = tn)
}

## The place a struct named `[s, s+n)` occupies: a struct local's object, or the struct a pointer
## local or parameter (declared `ptr(S)`) points at — WORD tier only through a pointer (see above).
ib_place_name := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize) -> Option(IbPlace) {
  if ib_names_global(bp, s, n) { return Option(IbPlace).None }
  bd : IbBind = ib_lookup(bp, s, n)
  match bd {
    BdAgg(fr, sd, ts, tn) => { return Option(IbPlace).Some(IbPlace(bk = OpndK.OkFrame, bv = i64(usize(fr)), di = sd, s = ts, n = tn)) }
    BdVal(v, vts, vtn) => {
      if not kty_is_ptr(vreg_ty(ib_b_f(bp), usize(v))) { return Option(IbPlace).None }
      po : Option(IbSpan) = ib_pointee(bp, vts, vtn)
      match po {
        Some(ps) => {
          sto : Option(IbSt) = ib_struct_named(bp, a, ps.s, ps.n)
          match sto {
            Some(st) => {
              if not ib_struct_word(bp, a, st) { return Option(IbPlace).None }
              return Option(IbPlace).Some(IbPlace(bk = OpndK.OkVReg, bv = i64(usize(v)), di = st.di, s = st.s, n = st.n))
            }
            None => {}
          }
        }
        None => {}
      }
    }
    BdMem(mf, mns) => {}
    BdNone => {}
  }
  Option(IbPlace).None
}
## The place a field base expression denotes: a name (`s.f`, `p.f` through a pointer) or `deref(p)` of
## a pointer name (`deref(p).f`).
ib_place_of := fn(bp : ptr(mut IbB), in out a : rt::Arena, b : ptr(Expr)) -> Option(IbPlace) {
  match deref(b) {
    Expr::Var(s, n) => { return ib_place_name(bp, a, s, n) }
    Expr::Deref(pe) => {
      match deref(pe) {
        Expr::Var(ps, pn) => {
          bd : IbBind = ib_lookup(bp, ps, pn)
          match bd {
            BdVal(v, vts, vtn) => { return ib_place_name(bp, a, ps, pn) }
            BdAgg(fr, sd, ts, tn) => {}
            BdMem(mf, mns) => {}
            BdNone => {}
          }
        }
        Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
          | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
          | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
          | Expr::Loop => {}
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit
      | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => {}
  }
  Option(IbPlace).None
}
## Is struct `st` in the WORD tier — every field one 8-byte word, the layout every emitter shares?
ib_struct_word := fn(bp : ptr(mut IbB), in out a : rt::Arena, st : IbSt) -> bool {
  bv : IbB = deref(bp)
  lk := lower_layout::layout_kind(bv.decls, bv.src, st.s, st.n, a)
  if lower_layout::layout_kind_is_packed(lk) or lower_layout::layout_kind_is_byte(lk) { return false }
  not ib_struct_padded(bp, st)
}

## `s.f = v` / `p.f = v` (FieldAssign): a `store` at the field's place, the value at its declared type.
ib_bs_field_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), bns : usize, bnl : usize, fns : usize, fnl : usize, fv : ptr(Expr)) {
  plo : Option(IbPlace) = ib_place_name(bp, a, bns, bnl)
  ib_bs_store_field(bp, a, h, plo, fns, fnl, fv)
}
## `<place>.f = v` (FieldPathAssign) where the place is `deref(p)` or a name; deeper paths are outside.
ib_bs_field_path_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), pl : ptr(Expr), pv : ptr(Expr)) {
  match deref(pl) {
    Expr::Field(b, fs, fl) => {
      plo : Option(IbPlace) = ib_place_of(bp, a, b)
      ib_bs_store_field(bp, a, h, plo, fs, fl, pv)
      return
    }
    Expr::Num | Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
      | Expr::Loop => {}
  }
  ib_refuse_stmt(bp, h, NyWhy.NwOutside)
}
ib_bs_store_field := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), plo : Option(IbPlace), fs : usize, fl : usize, fv : ptr(Expr)) {
  match plo {
    Some(pl) => {
      sto : Option(IbSt) = ib_place_st(bp, a, pl)
      match sto {
        Some(st) => {
          flo : Option(IbFld) = ib_field(bp, a, st, fs, fl)
          match flo {
            Some(fld) => {
              vo : Option(VRegId) = ib_value_ctx(bp, a, fv, IbKS(ty = fld.ty, sg = fld.sg))
              match vo { Some(v) => { pb := ib_place_base(pl); ib_store_at(bp, a, pb, fld, v) }; None => {} }
              return
            }
            None => {}
          }
        }
        None => {}
      }
    }
    None => {}
  }
  ib_refuse_stmt(bp, h, NyWhy.NwOutside)
}
## `s.f`, `p.f`, `deref(p).f`: a `load` at the field's place, at its declared type, which must be sema's
## record of the read (#765: the field's signedness is the value's from here on).
ib_bx_field := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), b : ptr(Expr), fs : usize, fl : usize) -> Option(VRegId) {
  plo : Option(IbPlace) = ib_place_of(bp, a, b)
  match plo {
    Some(pl) => {
      sto : Option(IbSt) = ib_place_st(bp, a, pl)
      match sto {
        Some(st) => {
          fo : Option(IbFld) = ib_field(bp, a, st, fs, fl)
          match fo {
            Some(fld) => {
              k := ib_ty(bp, e)?
              if not ib_ks_eq(k, IbKS(ty = fld.ty, sg = fld.sg)) { return ib_no(bp, e, NyWhy.NwDisagree) }
              pb := ib_place_base(pl)
              lv := ib_load_at(bp, a, pb, fld)
              return Option(VRegId).Some(lv)
            }
            None => {}
          }
        }
        None => {}
      }
    }
    None => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}

## A one-word kernel scalar (8 bytes): what a pointer or an address-taken local may move (see above).
ib_ks_word := fn(k : IbKS) -> bool { kty_bytes(k.ty) == 8 }
## The place-free field of a whole scalar at an address: offset 0, type `k`.
ib_word_fld := fn(k : IbKS) -> IbFld { IbFld(off = ByteOff(0), ty = k.ty, sg = k.sg) }

## `deref(p)` of a scalar: a `load` at sema's type of the read, which must be one word.
ib_bx_deref := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), pe : ptr(Expr)) -> Option(VRegId) {
  pv := ib_bx(bp, a, pe)?
  if not kty_is_ptr(vreg_ty(ib_b_f(bp), usize(pv))) { return ib_no(bp, e, NyWhy.NwDisagree) }
  k := ib_ty(bp, e)?
  if not ib_ks_word(k) { return ib_no(bp, e, NyWhy.NwOutside) }
  opv := o_vreg(pv)
  lv := ib_load_at(bp, a, opv, ib_word_fld(k))
  Option(VRegId).Some(lv)
}
## `deref(p) = v` of a scalar: `p` a pointer name declared `ptr(T)`, `T` a one-word kernel scalar; the
## value first, then the pointer (the legacy order), then the `store`.
ib_bs_deref_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), pe : ptr(Expr), dv : ptr(Expr)) {
  ko : Option(IbKS) = ib_ptr_pointee_ks(bp, pe)
  match ko {
    Some(k) => {
      if ib_ks_word(k) {
        vo : Option(VRegId) = ib_value_ctx(bp, a, dv, k)
        match vo {
          Some(v) => {
            po : Option(VRegId) = ib_bx(bp, a, pe)
            match po {
              Some(pv) => {
                if not kty_is_ptr(vreg_ty(ib_b_f(bp), usize(pv))) { ib_refuse_stmt(bp, h, NyWhy.NwDisagree); return }
                opv := o_vreg(pv)
                ib_store_at(bp, a, opv, ib_word_fld(k), v)
              }
              None => {}
            }
          }
          None => {}
        }
        return
      }
    }
    None => {}
  }
  ib_refuse_stmt(bp, h, NyWhy.NwOutside)
}
## The kernel scalar a pointer NAME's declared type `ptr(T)` points at.
ib_ptr_pointee_ks := fn(bp : ptr(mut IbB), pe : ptr(Expr)) -> Option(IbKS) {
  match deref(pe) {
    Expr::Var(s, n) => {
      if ib_names_global(bp, s, n) { return Option(IbKS).None }
      bd : IbBind = ib_lookup(bp, s, n)
      match bd {
        BdVal(v, vts, vtn) => {
          po : Option(IbSpan) = ib_pointee(bp, vts, vtn)
          match po { Some(ps) => { return ib_name_ks(ib_b_src(bp), ps.s, ps.n) }; None => {} }
        }
        BdAgg(fr, sd, ts, tn) => {}
        BdMem(mf, mns) => {}
        BdNone => {}
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
      | Expr::Loop => {}
  }
  Option(IbKS).None
}
## `ptr(x)`: the address of a local in memory — a WORD-tier struct local's object, or an address-taken
## scalar local's (`ib_scan_taken` made it one). Sema's record of the expression must be a pointer.
ib_bx_addr_of := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), pl : ptr(Expr)) -> Option(VRegId) {
  match deref(pl) {
    Expr::Var(s, n) => {
      if ib_names_global(bp, s, n) { return ib_no(bp, e, NyWhy.NwOutside) }
      bd : IbBind = ib_lookup(bp, s, n)
      match bd {
        BdAgg(fr, sd, ts, tn) => {
          sto : Option(IbSt) = ib_struct_bound(bp, a, sd, ts, tn)
          match sto {
            Some(st) => { if ib_struct_word(bp, a, st) { return ib_addr_frame(bp, a, e, fr) } }
            None => {}
          }
        }
        BdMem(mf, mns) => { return ib_addr_frame(bp, a, e, mf) }
        BdVal(v, vts, vtn) => {}
        BdNone => {}
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
      | Expr::Loop => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}
ib_addr_frame := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), fr : FrameId) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  if not kty_is_ptr(k.ty) { return ib_no(bp, e, NyWhy.NwDisagree) }
  d := ib_fresh(bp, a, k)
  mut it := inst0(Op.OpAddrFrame)
  it.ty = Kty.KPtr
  set_dst(it, d)
  ofr := o_frame(fr)
  set_a(it, ofr)
  i := emit(ib_b_f(bp), a, it)
  Option(VRegId).Some(d)
}

## ── address-taken scalar locals (slice 3b) ──
##
## A local whose address `ptr(x)` is taken anywhere in the function lives in a frame object (§3.3), so
## the pointer and the name see one memory. `ib_scan_taken` collects those names before the body is
## built — by NAME, so a shadowing local of the same name is put in memory too (correct, only slower).
## The scan walks the constructs the builder builds; a `ptr(x)` hidden in one it does not (a `match`
## arm) is never reached either, because the builder refuses that construct first, and `ptr(x)` of a
## local the scan missed is refused (`ib_bx_addr_of`), never a wrong address.

## Was `ptr([s, s+n))` seen by the scan?
ib_is_taken := fn(bp : ptr(mut IbB), s : usize, n : usize) -> bool {
  bv : IbB = deref(bp)
  mut i : usize = 0
  while i + 1 < wb_len(bv.taken) {
    if wb_get(bv.taken, i + 1) == n and streq(bv.src, wb_get(bv.taken, i), n, s, n) { return true }
    i = i + 2
  }
  false
}
ib_scan_stmts := fn(bp : ptr(mut IbB), in out a : rt::Arena, head : Option(ptr(mut Stmt))) {
  mut h : Option(ptr(mut Stmt)) = head
  loop {
    match h {
      Some(hq) => { ib_scan_stmt(bp, a, hq); h = stmt_next(hq) }
      None => { break }
    }
  }
}
ib_scan_opt := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) { if expr_present(e) { ib_scan_expr(bp, a, e) } }
ib_scan_stmt := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt)) {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { ib_scan_expr(bp, a, v) }
    Stmt::While(c, b, nx) => { ib_scan_expr(bp, a, c); ib_scan_stmts(bp, a, b) }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { ib_scan_expr(bp, a, fv) }
    Stmt::Return(rv, nx) => { ib_scan_opt(bp, a, rv) }
    Stmt::If(c, th, el, nx) => { ib_scan_expr(bp, a, c); ib_scan_stmts(bp, a, th); ib_scan_stmts(bp, a, el) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { ib_scan_expr(bp, a, lo); ib_scan_opt(bp, a, hi); ib_scan_stmts(bp, a, b) }
    Stmt::DerefAssign(p, v, nx) => { ib_scan_expr(bp, a, p); ib_scan_expr(bp, a, v) }
    Stmt::FieldPathAssign(pl, pv, nx) => { ib_scan_expr(bp, a, pl); ib_scan_expr(bp, a, pv) }
    Stmt::Loop(b, nx) => { ib_scan_stmts(bp, a, b) }
    Stmt::Break(bv, bd, nx) => { ib_scan_opt(bp, a, bv) }
    Stmt::ExprStmt(e, nx) => { ib_scan_expr(bp, a, e) }
    Stmt::Unchecked(b, nx) => { ib_scan_stmts(bp, a, b) }
    ## Constructs the builder refuses before it reaches anything inside them (see the band comment).
    Stmt::Match | Stmt::IndexAssign | Stmt::IndexFieldAssign | Stmt::Continue | Stmt::CompIf | Stmt::CompFor
      | Stmt::CompMatch | Stmt::CompForRange | Stmt::AllocWith => {}
  }
}
ib_scan_args := fn(bp : ptr(mut IbB), in out a : rt::Arena, ah : Option(ptr(mut Arg))) {
  mut g : Option(ptr(mut Arg)) = ah
  loop {
    match g {
      Some(gq) => { ga := deref(arg_p(gq)); ib_scan_expr(bp, a, ga.e); g = ga.next }
      None => { break }
    }
  }
}
ib_scan_expr := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) {
  match deref(e) {
    Expr::AddrOf(pl) => {
      match deref(pl) {
        Expr::Var(s, n) => {
          bv : IbB = deref(bp)
          k1 := wb_push(bv.taken, a, s)
          k2 := wb_push(bv.taken, a, n)
        }
        Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
          | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
          | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
          | Expr::Loop => { ib_scan_expr(bp, a, pl) }
      }
    }
    Expr::Bin(op, l, r) => { ib_scan_expr(bp, a, l); ib_scan_expr(bp, a, r) }
    Expr::If(c, t, x) => { ib_scan_expr(bp, a, c); ib_scan_expr(bp, a, t); ib_scan_expr(bp, a, x) }
    Expr::Call(cs, cl, na, ah) => { ib_scan_args(bp, a, ah) }
    Expr::StructLit(ss, sl, nf, fh) => { ib_scan_args(bp, a, fh) }
    Expr::Field(b, fs, fl) => { ib_scan_expr(bp, a, b) }
    Expr::Deref(p) => { ib_scan_expr(bp, a, p) }
    Expr::Unchecked(inner) => { ib_scan_expr(bp, a, inner) }
    Expr::Bitcast(inner, ts, tl) => { ib_scan_expr(bp, a, inner) }
    Expr::Loop(b) => { ib_scan_stmts(bp, a, b) }
    Expr::Num | Expr::BoolLit | Expr::Var | Expr::Match | Expr::EnumLit | Expr::StrLit | Expr::ArrayLit | Expr::Index
      | Expr::Try | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Lambda | Expr::FnRef => {}
  }
}

## A fresh one-word frame object holding `v`, for the address-taken local `[s, s+n)` declared at `ns`.
ib_mem_local := fn(bp : ptr(mut IbB), in out a : rt::Arena, s : usize, n : usize, ns : usize, v : VRegId) {
  fr := new_frame(ib_b_f(bp), a, 8, 8)
  k : IbKS = ib_vreg_ks(ib_b_f(bp), v)
  ofr := o_frame(fr)
  ib_store_at(bp, a, ofr, ib_word_fld(k), v)
  ib_bind_mem(bp, a, s, n, fr, ns)
}
## The kernel type of the address-taken local declared at `ns`: sema's record of the binding.
ib_mem_ks := fn(ns : usize) -> Option(IbKS) {
  t : VTy = sty_bind_get(ns)
  ib_vty_ks(t)
}
## A read of an address-taken local: a `load` at sema's type of the read, which must be the binding's.
ib_bx_mem_read := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), fr : FrameId, ns : usize) -> Option(VRegId) {
  k := ib_ty(bp, e)?
  bk : Option(IbKS) = ib_mem_ks(ns)
  match bk {
    Some(b) => {
      if not ib_ks_eq(k, b) { return ib_no(bp, e, NyWhy.NwDisagree) }
      ofr := o_frame(fr)
      lv := ib_load_at(bp, a, ofr, ib_word_fld(k))
      return Option(VRegId).Some(lv)
    }
    None => {}
  }
  ib_no(bp, e, NyWhy.NwDisagree)
}
## `x = v` into an address-taken local: a `store` at its type.
ib_bs_mem_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), fr : FrameId, ns : usize, v : ptr(Expr)) {
  bk : Option(IbKS) = ib_mem_ks(ns)
  match bk {
    Some(k) => {
      vo : Option(VRegId) = ib_value_at(bp, a, v, k)
      match vo { Some(x) => { ofr := o_frame(fr); ib_store_at(bp, a, ofr, ib_word_fld(k), x) }; None => {} }
    }
    None => { ib_refuse_stmt(bp, h, NyWhy.NwDisagree) }
  }
}

## ── mutable module scalars (slice 3b) ──
##
## A mutable module scalar is a place: `addr @G` and a `load` at sema's type of the read
## (`ib_bx_global_at`), or a `store` of the WHOLE one-word cell each target gives it
## (`global_has_scalar_cell`: `.quad` on aarch64/riscv64, an `i64` wasm global) — the value widened to
## 64 bits first, so a legacy reader of the word sees the canonical value whatever width it loads.
ib_bs_global_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, nl : usize, v : ptr(Expr)) {
  gd : Option(u64) = ib_global_decl(bp, ns, nl)
  match gd {
    Some(x) => {
      di := usize(x)
      src := ib_b_src(bp)
      d : Decl = deref(ib_decl_ptr(ib_b_decls(bp), di))
      if ast::local_is_mut(src, d.name_start) and lower_layout::global_has_scalar_cell(d) {
        lts := ast::local_type_span(src, d.name_start, d.name_len)
        ko : Option(IbKS) = ib_name_ks(src, lts.s, lts.n)
        match ko {
          Some(k) => { ib_store_global(bp, a, di, d, k, v); return }
          None => {}
        }
      }
    }
    None => {}
  }
  ib_refuse_stmt(bp, h, NyWhy.NwOutside)
}
ib_store_global := fn(bp : ptr(mut IbB), in out a : rt::Arena, di : usize, d : Decl, k : IbKS, v : ptr(Expr)) {
  vo : Option(VRegId) = ib_value_ctx(bp, a, v, k)
  match vo {
    Some(x) => {
      mut w : VRegId = x
      mut wk : IbKS = k
      if kty_is_int(k.ty) { wk = ib_ks_i64(k.sg); w = ib_ext_to(bp, a, x, wk) }
      pa := ib_global_addr(bp, a, di, d)
      opa := o_vreg(pa)
      ib_store_at(bp, a, opa, ib_word_fld(wk), w)
    }
    None => {}
  }
}
## `%p = addr @G` of module value declaration `di`.
ib_global_addr := fn(bp : ptr(mut IbB), in out a : rt::Arena, di : usize, d : Decl) -> VRegId {
  src := ib_b_src(bp)
  dnm := str_at((src + d.name_start), d.name_len)
  sym := prog_sym(ib_b_p(bp), a, di, dnm.ptr, dnm.len)
  pa := ib_fresh(bp, a, IbKS(ty = Kty.KPtr, sg = Sgn.SgNone))
  mut ai := inst0(Op.OpAddrSym)
  ai.ty = Kty.KPtr
  set_dst(ai, pa)
  osym := o_sym(sym)
  set_a(ai, osym)
  i1 := emit(ib_b_f(bp), a, ai)
  pa
}

## The value of `e` at the type `k` of the struct field it initializes. A literal-only expression no
## context typed (`VcLit`: sema gives a call argument its parameter's type, not yet a struct literal's
## initializer its field's) takes the field's DECLARED type, the context Types §2.3 names: its exact
## value as a constant at `k`, refused in a checked scope when `k` cannot hold it (sema accepts only
## one that fits) and wrapped inside `unchecked`. Anything else is `ib_value_at`.
ib_value_ctx := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), k : IbKS) -> Option(VRegId) {
  t : VTy = sty_get(e)
  if vty_is_lit(t) and kty_is_int(k.ty) {
    fo : Option(i64) = ib_lit_fold(e)
    match fo {
      Some(v) => {
        cv := ib_canon(v, k)
        fits := cv == v and (v >= 0 or sgn_eq(k.sg, Sgn.SgS))
        if not fits and not ib_b_unch(bp) { return ib_no(bp, e, NyWhy.NwLit) }
        d := ib_konst(bp, a, k, cv)
        return Option(VRegId).Some(d)
      }
      None => {}
    }
  }
  ib_value_at(bp, a, e, k)
}

## The layout queries `size(T)` and `align(T)` (Types §6), folded to a `const` (§4).
LayoutQ := enum { LqSize, LqAlign }
ib_layout_q_of := fn(nm : str) -> Option(LayoutQ) {
  if nm == "size" { return Option(LayoutQ).Some(LayoutQ.LqSize) }
  if nm == "align" { return Option(LayoutQ).Some(LayoutQ.LqAlign) }
  Option(LayoutQ).None
}
## Is there a function declaration named `[cs, cs+cl)` (a user `size`/`align` is not the builtin)?
ib_fn_named := fn(bp : ptr(mut IbB), cs : usize, cl : usize) -> bool {
  bv : IbB = deref(bp)
  cnt := rt::vec_len(deref(bv.decls))
  mut i : usize = 0
  while i < cnt {
    d : Decl = deref(ib_decl_ptr(bv.decls, i))
    if d.is_fn and d.name_len == cl and streq(bv.src, d.name_start, d.name_len, cs, cl) { return true }
    i = i + 1
  }
  false
}
## `size(T)` / `align(T)` of a type NAME: a kernel scalar by the target-independent scalar table
## (`lower_layout::type_byte_size` / `type_byte_align`, the answer x86_64's fold gives), or a struct
## 3a lays out (its layout's size; a WORD-tier struct is 8-aligned). Any other operand — a value, an
## enum, an array or view, a generic parameter — is outside 3a. The result is sema's record of the call.
ib_bx_layout_q := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), q : LayoutQ, ah : Option(ptr(mut Arg))) -> Option(VRegId) {
  a0 := deref(arg_at(ah, "argument list ended early"))
  ae : ptr(Expr) = a0.e
  match deref(ae) {
    Expr::Var(s, n) => {
      bd : IbBind = ib_lookup(bp, s, n)
      match bd { BdNone => {}; BdVal(v, vts, vtn) => { return ib_no(bp, e, NyWhy.NwOutside) }; BdAgg(fr, sd, ts, tn) => { return ib_no(bp, e, NyWhy.NwOutside) }; BdMem(mf, mns) => { return ib_no(bp, e, NyWhy.NwOutside) } }
      src := ib_b_src(bp)
      mut bytes : usize = 0
      ko : Option(IbKS) = ib_name_ks(src, s, n)
      match ko {
        Some(k) => {
          match q {
            LqSize => { bytes = lower_layout::type_byte_size(src, s, n) }
            LqAlign => { bytes = lower_layout::type_byte_align(src, s, n) }
          }
        }
        None => {
          sto : Option(IbSt) = ib_struct_named(bp, a, s, n)
          match sto {
            Some(st) => { match q { LqSize => { bytes = st.size }; LqAlign => { bytes = st.align } } }
            None => { return ib_no(bp, e, NyWhy.NwOutside) }
          }
        }
      }
      k := ib_int_ty(bp, e)?
      c := ib_konst(bp, a, k, i64(bytes))
      return Option(VRegId).Some(c)
    }
    Expr::Num | Expr::BoolLit | Expr::Bin | Expr::If | Expr::Match | Expr::Call | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
      | Expr::Loop => {}
  }
  ib_no(bp, e, NyWhy.NwOutside)
}

## ── statements ──

## Build the statement list at `h` in a scope of its own.
ib_bs_block := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : Option(ptr(mut Stmt))) {
  mark := ib_scope_mark(bp)
  ib_bs(bp, a, h)
  ib_scope_drop(bp, mark)
}

ib_bs := fn(bp : ptr(mut IbB), in out a : rt::Arena, head : Option(ptr(mut Stmt))) {
  mut h : Option(ptr(mut Stmt)) = head
  loop {
    match h {
      Some(hq) => {
        if ib_b_failed(bp) { break }
        ## A statement after a terminator is unreachable: dropped, never built (V7).
        if not ib_b_term(bp) { ib_bs_one(bp, a, hq) }
        h = stmt_next(hq)
      }
      None => { break }
    }
  }
}
## A function with a result whose body produces it as the value of its LAST statement (a trailing
## expression, or an `if`/`unchecked` block whose own last statement does): that statement is built in
## tail position, and each value it yields is returned.
ib_bs_tail := fn(bp : ptr(mut IbB), in out a : rt::Arena, head : Option(ptr(mut Stmt))) {
  mut h : Option(ptr(mut Stmt)) = head
  loop {
    match h {
      Some(hq) => {
        if ib_b_failed(bp) { break }
        nx := stmt_next(hq)
        if not ib_b_term(bp) {
          if stmt_any(nx) { ib_bs_one(bp, a, hq) } else { ib_bs_last(bp, a, hq) }
        }
        h = nx
      }
      None => { break }
    }
  }
}
ib_bs_tail_block := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : Option(ptr(mut Stmt))) {
  mark := ib_scope_mark(bp)
  ib_bs_tail(bp, a, h)
  ib_scope_drop(bp, mark)
}
## Return `v` as the function's result, at its declared type.
ib_ret_value := fn(bp : ptr(mut IbB), in out a : rt::Arena, v : VRegId, at : ptr(Expr)) {
  f := ib_b_f(bp)
  want := IbKS(ty = fn_ret_ty(f), sg = fn_ret_sg(f))
  wo : Option(VRegId) = ib_coerce(bp, a, v, want, at)
  match wo {
    Some(w) => { ow := o_vreg(w); i := e_ret(f, a, ow); ib_b_set_term(bp, true) }
    None => {}
  }
}
ib_bs_last := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt)) {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::ExprStmt(e, nx) => { ib_bs_tail_expr(bp, a, e) }
    Stmt::If(c, th, el, nx) => {
      if stmt_any(el) { ib_bs_tail_if(bp, a, c, th, el) } else { ib_bs_one(bp, a, h) }
    }
    Stmt::Unchecked(b, nx) => {
      ou := ib_b_unch(bp)
      it := inst0(Op.OpUnch)
      k := emit(ib_b_f(bp), a, it)
      ib_b_set_unch(bp, true)
      ib_bs_tail_block(bp, a, b)
      ib_b_set_unch(bp, ou)
      ib_plain(bp, a, Op.OpEnd)
    }
    Stmt::Assign | Stmt::While | Stmt::FieldAssign | Stmt::Return | Stmt::Match | Stmt::For | Stmt::DerefAssign
      | Stmt::IndexAssign | Stmt::IndexFieldAssign | Stmt::FieldPathAssign | Stmt::Loop | Stmt::Break | Stmt::Continue
      | Stmt::CompIf | Stmt::CompFor | Stmt::CompMatch | Stmt::CompForRange | Stmt::AllocWith => { ib_bs_one(bp, a, h) }
  }
}
## The tail expression's value is the result.
ib_bs_tail_expr := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) {
  vo : Option(VRegId) = ib_bx(bp, a, e)
  match vo { Some(v) => { ib_ret_value(bp, a, v, e) }; None => {} }
}
## A tail `if … else …`: each arm's own tail is returned.
ib_bs_tail_if := fn(bp : ptr(mut IbB), in out a : rt::Arena, c : ptr(Expr), th : Option(ptr(mut Stmt)), el : Option(ptr(mut Stmt))) {
  co : Option(VRegId) = ib_bool_operand(bp, a, c)
  match co {
    Some(cv) => {
      ib_open_if(bp, a, cv)
      ib_b_set_term(bp, false)
      ib_bs_tail_block(bp, a, th)
      tt := ib_b_term(bp)
      ib_plain(bp, a, Op.OpElse)
      ib_b_set_term(bp, false)
      ib_bs_tail_block(bp, a, el)
      et := ib_b_term(bp)
      ib_plain(bp, a, Op.OpEnd)
      ib_b_set_term(bp, tt and et)
    }
    None => {}
  }
}

ib_bs_one := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt)) {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { ib_bs_assign(bp, a, h, ns, nl, v) }
    Stmt::ExprStmt(e, nx) => { ib_bs_expr(bp, a, e) }
    Stmt::Return(rv, nx) => { ib_bs_return(bp, a, rv) }
    Stmt::If(c, th, el, nx) => { ib_bs_if(bp, a, c, th, el) }
    Stmt::While(c, b, nx) => { ib_bs_while(bp, a, c, b) }
    Stmt::Loop(b, nx) => { ib_bs_loop(bp, a, b, Option(VRegId).None) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { ib_bs_for(bp, a, h, fns, fnl, lo, hi, b) }
    Stmt::Break(bv, bd, nx) => { ib_bs_break(bp, a, h, bv, bd) }
    Stmt::Continue(cd, nx) => { ib_bs_continue(bp, a, h, cd) }
    Stmt::Unchecked(b, nx) => {
      ou := ib_b_unch(bp)
      it := inst0(Op.OpUnch)
      k := emit(ib_b_f(bp), a, it)
      ib_b_set_unch(bp, true)
      ib_bs_block(bp, a, b)
      ib_b_set_unch(bp, ou)
      ## A terminator inside the region ends it; nothing more is emitted before its `end`.
      ib_plain(bp, a, Op.OpEnd)
    }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { ib_bs_field_assign(bp, a, h, bns, bnl, fns, fnl, fv) }
    Stmt::DerefAssign(pe, dv, nx) => { ib_bs_deref_assign(bp, a, h, pe, dv) }
    Stmt::FieldPathAssign(pl, pv, nx) => { ib_bs_field_path_assign(bp, a, h, pl, pv) }
    Stmt::Match | Stmt::IndexAssign | Stmt::IndexFieldAssign
      | Stmt::CompIf | Stmt::CompFor | Stmt::CompMatch | Stmt::CompForRange
      | Stmt::AllocWith => { ib_refuse_stmt(bp, h, NyWhy.NwOutside) }
  }
}
## `continue [name]`: restart the target loop (a range `for` leaves its body block, so its step runs).
ib_bs_continue := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), depth : usize) {
  lo : Option(u64) = ib_loop_at(bp, depth)
  match lo {
    Some(ix) => { ib_br(bp, a, ib_loop_cont(bp, usize(ix))); ib_b_set_term(bp, true) }
    None => { ib_refuse_stmt(bp, h, NyWhy.NwOutside) }
  }
}
## An expression statement: its value, if any, is discarded; a call may have none.
ib_bs_expr := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr)) {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { co : CallOut = ib_call(bp, a, e, cs, cl, na, ah) }
    Expr::Num | Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::StructLit | Expr::Field
      | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try
      | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef
      | Expr::Bitcast | Expr::Loop => { v : Option(VRegId) = ib_bx(bp, a, e) }
  }
}

## `x := e` / `x : T = e` binds a new vreg at the binding's type (sema's record of the declaration);
## `x = e` assigns the innermost binding of `x`.
ib_bs_assign := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, nl : usize, v : ptr(Expr)) {
  src := ib_b_src(bp)
  if ast::local_is_uninit(src, ns, nl) { ib_refuse_stmt(bp, h, NyWhy.NwOutside); return }
  if ast::assign_is_decl(src, ns, nl) {
    if ib_vty_is_agg(sty_bind_get(ns)) { ib_bs_agg_decl(bp, a, h, ns, nl, v); return }
    nvo : Option(VRegId) = ib_decl_value(bp, a, h, ns, v)
    match nvo {
      Some(nv) => {
        if ib_is_taken(bp, ns, nl) {
          ## An address-taken local lives in memory; only a one-word scalar (see "places").
          if not ib_ks_word(ib_vreg_ks(ib_b_f(bp), nv)) { ib_refuse_stmt(bp, h, NyWhy.NwOutside); return }
          ib_mem_local(bp, a, ns, nl, ns, nv)
          return
        }
        lts := ast::local_type_span(src, ns, nl)
        ib_bind_typed(bp, a, ns, nl, nv, lts.s, lts.n)
      }
      None => {}
    }
    return
  }
  found : IbBind = ib_lookup(bp, ns, nl)
  match found {
    BdVal(dv, dts, dtn) => { ib_assign_to(bp, a, dv, v) }
    BdAgg(fr, sd, ts, tn) => { ib_bs_agg_assign(bp, a, h, fr, sd, ts, tn, v) }
    BdMem(mf, mns) => { ib_bs_mem_assign(bp, a, h, mf, mns, v) }
    BdNone => { ib_bs_global_assign(bp, a, h, ns, nl, v) }
  }
}
## A declaration's fresh vreg, holding its initializer at the binding's type.
ib_decl_value := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, v : ptr(Expr)) -> Option(VRegId) {
  vv := ib_bx(bp, a, v)?
  bk := ib_bind_ty(bp, h, ns)?
  cv := ib_coerce(bp, a, vv, bk, v)?
  nv := ib_fresh(bp, a, bk)
  ib_mov(bp, a, nv, cv)
  Option(VRegId).Some(nv)
}
## `x = e` into the binding `dv`, at its type.
ib_assign_to := fn(bp : ptr(mut IbB), in out a : rt::Arena, dv : VRegId, v : ptr(Expr)) {
  dk : IbKS = ib_vreg_ks(ib_b_f(bp), dv)
  co : Option(VRegId) = ib_value_at(bp, a, v, dk)
  match co { Some(cv) => { ib_mov(bp, a, dv, cv) }; None => {} }
}
## Build `e` and take it at the type `k` its position gives it (`ib_coerce`).
ib_value_at := fn(bp : ptr(mut IbB), in out a : rt::Arena, e : ptr(Expr), k : IbKS) -> Option(VRegId) {
  v := ib_bx(bp, a, e)?
  ib_coerce(bp, a, v, k, e)
}

ib_bs_return := fn(bp : ptr(mut IbB), in out a : rt::Arena, rv : ptr(Expr)) {
  f := ib_b_f(bp)
  if expr_present(rv) and not lower_layout::ex_is_no_tail(rv) {
    vo : Option(VRegId) = ib_bx(bp, a, rv)
    match vo { Some(v) => { ib_ret_value(bp, a, v, rv) }; None => {} }
    return
  }
  on := o_none()
  i2 := e_ret(f, a, on)
  ib_b_set_term(bp, true)
}

ib_bs_if := fn(bp : ptr(mut IbB), in out a : rt::Arena, c : ptr(Expr), th : Option(ptr(mut Stmt)), el : Option(ptr(mut Stmt))) {
  co : Option(VRegId) = ib_bool_operand(bp, a, c)
  match co { Some(cv) => { ib_bs_if_on(bp, a, cv, th, el) }; None => {} }
}
ib_bs_if_on := fn(bp : ptr(mut IbB), in out a : rt::Arena, cv : VRegId, th : Option(ptr(mut Stmt)), el : Option(ptr(mut Stmt))) {
  ib_open_if(bp, a, cv)
  ib_b_set_term(bp, false)
  ib_bs_block(bp, a, th)
  tt := ib_b_term(bp)
  ib_plain(bp, a, Op.OpElse)
  ib_b_set_term(bp, false)
  ib_bs_block(bp, a, el)
  et := ib_b_term(bp)
  ib_plain(bp, a, Op.OpEnd)
  ib_b_set_term(bp, tt and et and stmt_any(el))
}

## `while c { body }` = `block X { loop T { if c {} else { br X }; body; br T } }`. `continue` restarts T.
ib_bs_while := fn(bp : ptr(mut IbB), in out a : rt::Arena, c : ptr(Expr), body : Option(ptr(mut Stmt))) {
  f := ib_b_f(bp)
  lx := new_label(f)
  lt := new_label(f)
  i1 := e_open(f, a, Op.OpBlock, lx)
  i2 := e_open(f, a, Op.OpLoop, lt)
  co : Option(VRegId) = ib_bool_operand(bp, a, c)
  match co { Some(cv) => { ib_bs_while_on(bp, a, cv, lx, lt, body) }; None => {} }
}
ib_bs_while_on := fn(bp : ptr(mut IbB), in out a : rt::Arena, cv : VRegId, lx : LabelId, lt : LabelId, body : Option(ptr(mut Stmt))) {
  ib_open_if(bp, a, cv)
  ib_plain(bp, a, Op.OpElse)
  ib_br(bp, a, lx)
  ib_plain(bp, a, Op.OpEnd)
  ib_loop_push(bp, a, lx, lt, Option(VRegId).None)
  ib_b_set_term(bp, false)
  ib_bs_block(bp, a, body)
  broken := ib_loop_pop(bp)
  if not ib_b_term(bp) { ib_br(bp, a, lt) }
  ib_plain(bp, a, Op.OpEnd)
  ib_plain(bp, a, Op.OpEnd)
  ib_b_set_term(bp, false)
}

## `loop { body }` = `block X { loop T { body; br T } }`; a value loop carries its result vreg. A loop no
## `break` leaves never falls through, so what follows it is unreachable.
ib_bs_loop := fn(bp : ptr(mut IbB), in out a : rt::Arena, body : Option(ptr(mut Stmt)), res : Option(VRegId)) {
  f := ib_b_f(bp)
  lx := new_label(f)
  lt := new_label(f)
  i1 := e_open(f, a, Op.OpBlock, lx)
  i2 := e_open(f, a, Op.OpLoop, lt)
  ib_loop_push(bp, a, lx, lt, res)
  ib_b_set_term(bp, false)
  ib_bs_block(bp, a, body)
  broken := ib_loop_pop(bp)
  if not ib_b_term(bp) { ib_br(bp, a, lt) }
  ib_plain(bp, a, Op.OpEnd)
  ib_plain(bp, a, Op.OpEnd)
  ib_b_set_term(bp, not broken)
}

## A range `for i in lo..hi { body }`:
##   i = lo; end = hi; block X { loop T { if i >= end { br X }; block C { body }; i = add wrap proven 1; br T } }
## `continue` leaves C, so the step still runs. An iterable `for` (no `hi`) is not scalar, and a narrow
## induction variable is not built yet.
ib_bs_for := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, nl : usize, lo : ptr(Expr), hi : ptr(Expr), body : Option(ptr(mut Stmt))) {
  if not expr_present(hi) { ib_refuse_stmt(bp, h, NyWhy.NwOutside); return }
  bo : Option(IbPair) = ib_for_bounds(bp, a, h, ns, lo, hi)
  match bo { Some(pr) => { ib_bs_for_on(bp, a, ns, nl, pr, body) }; None => {} }
}
## The induction variable, holding `lo`, and the end, holding `hi`, both at the binding's type.
ib_for_bounds := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), ns : usize, lo : ptr(Expr), hi : ptr(Expr)) -> Option(IbPair) {
  k := ib_bind_ty(bp, h, ns)?
  if not kty_eq(k.ty, Kty.KI64) {
    ib_refuse_stmt(bp, h, NyWhy.NwOutside)
    return Option(IbPair).None
  }
  lv := ib_value_at(bp, a, lo, k)?
  ev := ib_value_at(bp, a, hi, k)?
  iv := ib_fresh(bp, a, k)
  ib_mov(bp, a, iv, lv)
  endv := ib_fresh(bp, a, k)
  ib_mov(bp, a, endv, ev)
  Option(IbPair).Some(IbPair(l = iv, r = endv))
}
ib_bs_for_on := fn(bp : ptr(mut IbB), in out a : rt::Arena, ns : usize, nl : usize, pr : IbPair, body : Option(ptr(mut Stmt))) {
  f := ib_b_f(bp)
  iv := pr.l
  endv := pr.r
  k : IbKS = ib_vreg_ks(f, iv)
  lx := new_label(f)
  lt := new_label(f)
  lc := new_label(f)
  i1 := e_open(f, a, Op.OpBlock, lx)
  i2 := e_open(f, a, Op.OpLoop, lt)
  ge := ib_fresh(bp, a, ib_bool_ks())
  oi := o_vreg(iv)
  oe := o_vreg(endv)
  i3 := e_cmp(f, a, Cc.CcGe, k.sg, k.ty, ge, oi, oe)
  oge := o_vreg(ge)
  i4 := e_br(f, a, Op.OpBrIf, oge, lx)
  i5 := e_open(f, a, Op.OpBlock, lc)
  mark := ib_scope_mark(bp)
  ib_bind(bp, a, ns, nl, iv)
  ib_loop_push(bp, a, lx, lc, Option(VRegId).None)
  ib_b_set_term(bp, false)
  ib_bs_block(bp, a, body)
  broken := ib_loop_pop(bp)
  ib_scope_drop(bp, mark)
  ib_plain(bp, a, Op.OpEnd)
  ## After the bound test `i < end`, so `i + 1` cannot overflow: a proven `wrap` (V10).
  one := o_imm(1)
  step := ib_proven(bp, a, Op.OpAdd, k, iv, one)
  ib_mov(bp, a, iv, step)
  ib_br(bp, a, lt)
  ib_plain(bp, a, Op.OpEnd)
  ib_plain(bp, a, Op.OpEnd)
  ib_b_set_term(bp, false)
}

## `break [name] [v]`: assign the target loop's result vreg (a value loop), then leave it.
ib_bs_break := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), bv : ptr(Expr), depth : usize) {
  lo : Option(u64) = ib_loop_at(bp, depth)
  match lo {
    Some(x) => { ib_bs_break_to(bp, a, h, bv, usize(x)) }
    None => { ib_refuse_stmt(bp, h, NyWhy.NwOutside) }
  }
}
## `break` to loop `ix`: a value loop owes a value, any other loop none.
ib_bs_break_to := fn(bp : ptr(mut IbB), in out a : rt::Arena, h : ptr(mut Stmt), bv : ptr(Expr), ix : usize) {
  res : Option(VRegId) = ib_loop_res(bp, ix)
  match res {
    Some(rd) => { if expr_present(bv) { ib_assign_to(bp, a, rd, bv) } else { ib_refuse_stmt(bp, h, NyWhy.NwOutside) } }
    None => { if expr_present(bv) { ib_refuse_stmt(bp, h, NyWhy.NwOutside) } }
  }
  if ib_b_failed(bp) { return }
  ib_loop_mark_broken(bp, a, ix)
  ib_br(bp, a, ib_loop_exit(bp, ix))
  ib_b_set_term(bp, true)
}

## ── functions ──

## Build the function declaration `di` of `decls` into `p`. `Built(id)` when every construct is in the
## subset; `Refused`, with the construct, the reason and the span in `why`, otherwise.
##
## A type name in the function resolves from the function's own module (Modules §3), as x86_64's emit
## loop publishes it (`lower_layout::set_type_ref_module`): published for the build and restored after,
## so a legacy emitter that runs next sees what it saw before.
pub build_one := fn(p : IrProg, decls : ptr(rt::Vec), src : ptr(u8), di : usize, in out a : rt::Arena, in out why : BuildWhy) -> BuildOut {
  d : Decl = deref(ib_decl_ptr(decls, di))
  was_on := lower_layout::type_ref_mod_on()
  was_s := lower_layout::type_ref_mod_s()
  was_l := lower_layout::type_ref_mod_l()
  lower_layout::set_type_ref_module(d.mod_start, d.mod_len, lower::root_mod_s(), lower::root_mod_l())
  out : BuildOut = ib_build_one(p, decls, src, di, a, why)
  if was_on { lower_layout::set_type_ref_module(was_s, was_l, lower::root_mod_s(), lower::root_mod_l()) } else { lower_layout::clear_type_ref_module() }
  out
}
ib_build_one := fn(p : IrProg, decls : ptr(rt::Vec), src : ptr(u8), di : usize, in out a : rt::Arena, in out why : BuildWhy) -> BuildOut {
  dp := ib_decl_ptr(decls, di)
  d : Decl = deref(dp)
  why.span = u64(d.name_start)
  why.w = NyWhy.NwOutside
  if d.is_generic { why.c = Construct.CGeneric; return BuildOut.Refused }
  if d.is_fn and d.kind == lower_layout::DECL_KIND_SYSCALL { return ib_build_syscall(p, src, d, a, why) }
  if not d.is_fn or lower::extern_symbol(src, d.name_start, d.name_len).n != 0 { why.c = Construct.CBodyless; return BuildOut.Refused }
  mut has_ret := false
  mut rk := IbKS(ty = Kty.KNone, sg = Sgn.SgNone)
  if d.ret_tl != 0 {
    rko : Option(IbKS) = ib_name_ks(src, d.ret_ts, d.ret_tl)
    match rko { Some(kk) => { rk = kk; has_ret = true }; None => { why.c = Construct.CSignature; return BuildOut.Refused } }
  }
  fnm := str_at((src + d.name_start), d.name_len)
  f := fn_new(a, fnm.ptr, fnm.len, has_ret, rk.ty, rk.sg)
  nb := IbB(f = f, p = p, src = src, decls = decls, mod_s = d.mod_start, mod_n = d.mod_len,
          bnames = wb_new(a, 16), blens = wb_new(a, 16), bvregs = wb_new(a, 16),
          bagg = wb_new(a, 16), bmem = wb_new(a, 16), bsd = wb_new(a, 16), bts = wb_new(a, 16), btn = wb_new(a, 16),
          taken = wb_new(a, 8),
          lexit = wb_new(a, 8), lcont = wb_new(a, 8), lres = wb_new(a, 8), lhasres = wb_new(a, 8), lbroken = wb_new(a, 8),
          unch = false, term = false, failed = false, fail_c = Construct.CEmpty, fail_w = NyWhy.NwOutside,
          fail_s = u64(d.name_start), span0 = u64(d.name_start))
  mut bb := nb
  bp := ptr(mut bb)
  ## The names `ptr(x)` takes, before any binding is made (an address-taken local lives in memory).
  ib_scan_stmts(bp, a, d.body_stmts)
  ib_scan_opt(bp, a, d.value)
  mut pp := d.params_head
  loop {
    match pp {
      Some(pq) => {
        pm := deref(param_p(pq))
        pk : Option(IbKS) = ib_name_ks(src, pm.ts, pm.tl)
        match pk {
          Some(kk) => {
            if pm.pmode != 0 { why.c = Construct.CSignature; return BuildOut.Refused }
            pv := new_param(f, a, kk.ty, kk.sg)
            if ib_is_taken(bp, pm.ns, pm.nl) {
              if not ib_ks_word(kk) { why.c = Construct.EAddrOf; return BuildOut.Refused }
              ib_mem_local(bp, a, pm.ns, pm.nl, pm.ns, pv)
            } else {
              ib_bind_typed(bp, a, pm.ns, pm.nl, pv, pm.ts, pm.tl)
            }
          }
          None => { why.c = Construct.CSignature; return BuildOut.Refused }
        }
        pp = pm.next
      }
      None => { break }
    }
  }
  has_tail := expr_present(d.value) and not lower_layout::ex_is_no_tail(d.value)
  if has_ret and not has_tail { ib_bs_tail(bp, a, d.body_stmts) } else { ib_bs(bp, a, d.body_stmts) }
  if not ib_b_failed(bp) and not ib_b_term(bp) {
    if has_tail {
      tvo : Option(VRegId) = ib_bx(bp, a, d.value)
      match tvo {
        Some(tv) => { if has_ret { ib_ret_value(bp, a, tv, d.value) } else { on := o_none(); i2 := e_ret(f, a, on) } }
        None => {}
      }
    } else {
      ## A body that neither returns nor yields its declared result on every path is not one the builder
      ## understands (sema accepted it, so a form is missing here): refused, never given a made-up exit.
      if has_ret { ib_refuse(bp, Construct.SReturn, NyWhy.NwOutside, Option(u64).None) } else { on2 := o_none(); i3 := e_ret(f, a, on2) }
    }
  }
  fb : IbB = deref(bp)
  if fb.failed { why.c = fb.fail_c; why.w = fb.fail_w; why.span = fb.fail_s; return BuildOut.Refused }
  fid := prog_add(p, a, f)
  BuildOut.Built(fid)
}

## A bodyless `@abi(syscall)` declaration `name := @abi(syscall) fn(num, a1, …) -> R` (ABI §5): the
## TRAMPOLINE from the Alatyr call convention to the system-call convention. Its first parameter is
## the call's number, which the library supplies per target (owner decision D3, `std::sysno`); the
## rest are the call's arguments. Built as one op:
##   fn name(%0 : num, %1 …) -> R { %r = syscall %0(%1, …); ret %r }
## so each selector spells the target's trap instruction and registers once (`docs/ir.md` §3.7), and
## a caller — IR-built or legacy — calls the trampoline's label like any function. Every parameter and
## the result must be a one-word kernel scalar; a result the builder cannot build (`Never`) refuses.
ib_build_syscall := fn(p : IrProg, src : ptr(u8), d : Decl, in out a : rt::Arena, in out why : BuildWhy) -> BuildOut {
  why.c = Construct.CSignature
  mut has_ret := false
  mut rk := IbKS(ty = Kty.KNone, sg = Sgn.SgNone)
  if d.ret_tl != 0 {
    rko : Option(IbKS) = ib_name_ks(src, d.ret_ts, d.ret_tl)
    match rko { Some(kk) => { rk = kk; has_ret = true }; None => { return BuildOut.Refused } }
  }
  if d.arity == 0 { return BuildOut.Refused }
  fnm := str_at((src + d.name_start), d.name_len)
  f := fn_new(a, fnm.ptr, fnm.len, has_ret, rk.ty, rk.sg)
  mut pp := d.params_head
  mut first := true
  loop {
    match pp {
      Some(pq) => {
        pm := deref(param_p(pq))
        pk : Option(IbKS) = ib_name_ks(src, pm.ts, pm.tl)
        match pk {
          Some(kk) => {
            if pm.pmode != 0 { return BuildOut.Refused }
            ## The number is an integer; an argument is any one-word scalar.
            if first and not kty_is_int(kk.ty) { return BuildOut.Refused }
            pv := new_param(f, a, kk.ty, kk.sg)
          }
          None => { return BuildOut.Refused }
        }
        first = false
        pp = pm.next
      }
      None => { break }
    }
  }
  np := fn_nparams(f)
  mut it := inst0(Op.OpSyscall)
  onr := o_vreg(VRegId(0))
  set_a(it, onr)
  mut j : usize = 1
  while j < np {
    slot := pool_push(f, a, j)
    if j == 1 { it.pool = slot }
    j = j + 1
  }
  it.n = np - 1
  if has_ret {
    rv := new_vreg(f, a, rk.ty, rk.sg)
    set_dst(it, rv)
    k1 := emit(f, a, it)
    orv := o_vreg(rv)
    k2 := e_ret(f, a, orv)
  } else {
    k3 := emit(f, a, it)
    on := o_none()
    k4 := e_ret(f, a, on)
  }
  fid := prog_add(p, a, f)
  BuildOut.Built(fid)
}
