## selfhost::wat::isel — the WebAssembly instruction selector over the shared IR (`docs/ir.md` §6,
## `docs/ir-slice-1.md` §4, slice 1c).
##
## A function the IR builder BUILT and the verifier accepted is emitted from its IR here instead of by
## `emit_wat_fn`; every other function keeps its legacy emission (owner decision D7). The selector is
## target text only: it never reads the AST. Every width and signedness decision it makes is read from
## the IR value's attributes (§3.8) — the instruction's `ty`/`sg` (a width op's `sg` is its source's) and the destination vreg's
## recorded type — never re-derived.
##
## Vregs are wasm locals (§6): vreg `k` is local `k` (the parameters first, as the IR numbers them),
## every one an `i64` (a `bool` is 0 or 1), plus two scratch locals after them. The IR's regions map
## one to one: `block`/`loop`/`if`/`else`/`end`, `br $L<n>` by the IR label. A trap is `unreachable`
## with `(; trap <kind> <file>:<line>:<col> ;)`; wasm has no flags, so a checked operation's overflow
## is computed (§6). A function with a result ends in `unreachable` after its last instruction, so a
## body whose every path returns inside a region still validates.
##
## The convention is the target's existing one for the scalar class (`docs/ir-slice-1.md` §3): i64
## params and an i64 result, the legacy `$<name>`, so an IR-built and a legacy-emitted function call each
## other. A narrow parameter and a narrow call result are re-canonicalized from their IR type. A module
## scalar is a wasm global (`emit_wat_program`'s `(global $<name> (mut i64))`), so `addr @g` followed
## by `load [%a + 0]` is selected as `global.get $g`; any other use of such an address is refused.
##
## A selector may REFUSE a function (an op it does not select, a member of a driver-disambiguated
## overload set, whose label carries a suffix); the caller then rewinds the output and emits the
## function the legacy way.
(Decl) := ast

## What one function is selected against (see `aarch64::isel`'s `SaX`), plus the scratch local base
## and the module-global addresses (`gv[i]` holds the address of symbol `gs[i]`).
SwX := struct { f : ptr(mut ir::IrFn), p : ir::IrProg, src : ptr(u8), decls : ptr(rt::Vec), fspan : usize, stk : ptr(mut ir::WBuf), s0 : usize, gv : ptr(mut ir::WBuf), gs : ptr(mut ir::WBuf) }

sw_put := fn(in out sb : rt::StrBuf, s : str) { k := rt::push_str(sb, s) }
sw_int := fn(in out sb : rt::StrBuf, n : i64) { k := rt::push_int(sb, n) }
sw_u := fn(in out sb : rt::StrBuf, n : usize) { k := rt::push_int(sb, i64(n)) }
## One instruction line.
sw_op := fn(in out sb : rt::StrBuf, s : str) { sw_put(sb, "    "); sw_put(sb, s); sw_put(sb, "\n") }
sw_get := fn(in out sb : rt::StrBuf, v : usize) { sw_put(sb, "    local.get "); sw_u(sb, v); sw_put(sb, "\n") }
sw_set := fn(in out sb : rt::StrBuf, v : usize) { sw_put(sb, "    local.set "); sw_u(sb, v); sw_put(sb, "\n") }
sw_const := fn(in out sb : rt::StrBuf, n : i64) { sw_put(sb, "    i64.const "); sw_int(sb, n); sw_put(sb, "\n") }
## Push an operand (a vreg or an immediate). Any other operand kind is not a value here.
sw_ld := fn(in out sb : rt::StrBuf, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sw_get(sb, usize(v)); true }
    OkImm => { sw_const(sb, v); true }
    OkNone | OkFrame | OkSym | OkFn | OkLabel => { false }
  }
}
sw_lda := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool { sw_ld(sb, ir::i_ak(ip), ir::i_av(ip)) }
sw_ldb := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool { sw_ld(sb, ir::i_bk(ip), ir::i_bv(ip)) }
sw_dst := fn(ip : ptr(mut ir::IrInst)) -> Option(usize) {
  match ir::i_dk(ip) {
    OkVReg => { Option(usize).Some(usize(ir::i_dv(ip))) }
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { Option(usize).None }
  }
}
## Pop the stack top into `ip`'s destination.
sw_setd := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sw_dst(ip)
  match dv { Some(d) => { sw_set(sb, d); true }; None => { false } }
}

## `unreachable (; trap <kind> <file>:<line>:<col> ;)` (§3.6).
sw_trap := fn(in out sb : rt::StrBuf, x : SwX, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  tn := ir::trap_name(tk)
  sw_put(sb, "    unreachable (; trap ")
  sw_put(sb, tn)
  sw_put(sb, " ")
  ir::put_inst_loc(sb, x.src, ip, x.fspan)
  sw_put(sb, " ;)\n")
}
## `if <trap> end` over the i32 condition on the stack.
sw_trap_on := fn(in out sb : rt::StrBuf, x : SwX, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  sw_op(sb, "if")
  sw_trap(sb, x, tk, ip)
  sw_op(sb, "end")
}

## The stack top ← canonical(stack top) at type `ty` with signedness `sg` (§3.2): a narrow signed
## integer by a shift pair, a narrow unsigned one by a mask; a 64-bit value, a `bool` and a pointer are
## already their word.
sw_canon := fn(in out sb : rt::StrBuf, ty : ir::Kty, sg : ir::Sgn) -> bool {
  match ty {
    KI8 => { sw_narrow(sb, 56, 255, sg) }
    KI16 => { sw_narrow(sb, 48, 65535, sg) }
    KI32 => { sw_narrow(sb, 32, 4294967295, sg) }
    KI64 | KBool | KPtr => { true }
    KF32 | KF64 | KNone => { false }
  }
}
sw_narrow := fn(in out sb : rt::StrBuf, sh : i64, mask : i64, sg : ir::Sgn) -> bool {
  match sg {
    SgS => { sw_const(sb, sh); sw_op(sb, "i64.shl"); sw_const(sb, sh); sw_op(sb, "i64.shr_s"); true }
    SgU => { sw_const(sb, mask); sw_op(sb, "i64.and"); true }
    SgNone => { false }
  }
}
## Canonicalize local `v` in place, from its recorded type (a parameter at entry).
sw_canon_local := fn(in out sb : rt::StrBuf, x : SwX, v : usize) -> bool {
  ty : ir::Kty = ir::vreg_ty(x.f, v)
  sg : ir::Sgn = ir::vreg_sg(x.f, v)
  if not ir::kty_is_narrow(ty) { return true }
  sw_get(sb, v)
  if not sw_canon(sb, ty, sg) { return false }
  sw_set(sb, v)
  true
}

## ── the operations ──

sw_mov := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sw_lda(sb, ip) { return false }
  sw_setd(sb, ip)
}
## `+ - *` at 64 bits; the result goes to the first scratch local before the checks read it. `chk`
## traps `overflow` on the op's own signedness: a signed sum when `(a ^ r) & (b ^ r)` is negative, a
## signed difference when `(a ^ b) & (a ^ r)` is; an unsigned sum when `r < a`, an unsigned difference
## when `a < b`; a product by division (`r / a != b` for `a ∉ {0, -1}`, and `-1 * MIN`).
sw_arith := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
  mut mn : str = "i64.mul"
  match o {
    OpAdd => { mn = "i64.add" }
    OpSub => { mn = "i64.sub" }
    OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
  }
  sw_op(sb, mn)
  if not ir::mode_is_chk(ir::i_md(ip)) { return sw_setd(sb, ip) }
  r := x.s0
  sw_set(sb, r)
  sg : ir::Sgn = ir::i_sg(ip)
  signed := ir::sgn_eq(sg, ir::Sgn.SgS)
  match o {
    OpAdd => {
      if signed {
        b1 := sw_lda(sb, ip); sw_get(sb, r); sw_op(sb, "i64.xor")
        b2 := sw_ldb(sb, ip); sw_get(sb, r); sw_op(sb, "i64.xor")
        sw_op(sb, "i64.and"); sw_const(sb, 0); sw_op(sb, "i64.lt_s")
      } else { sw_get(sb, r); b3 := sw_lda(sb, ip); sw_op(sb, "i64.lt_u") }
      sw_trap_on(sb, x, ir::TrapKind.TkOverflow, ip)
    }
    OpSub => {
      if signed {
        b4 := sw_lda(sb, ip); b5 := sw_ldb(sb, ip); sw_op(sb, "i64.xor")
        b6 := sw_lda(sb, ip); sw_get(sb, r); sw_op(sb, "i64.xor")
        sw_op(sb, "i64.and"); sw_const(sb, 0); sw_op(sb, "i64.lt_s")
      } else { b7 := sw_lda(sb, ip); b8 := sw_ldb(sb, ip); sw_op(sb, "i64.lt_u") }
      sw_trap_on(sb, x, ir::TrapKind.TkOverflow, ip)
    }
    OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      if signed {
        b9 := sw_lda(sb, ip); sw_const(sb, 0 - 1); sw_op(sb, "i64.eq")
        sw_op(sb, "if")
        c1 := sw_ldb(sb, ip); sw_const(sb, 0 - 9223372036854775807 - 1); sw_op(sb, "i64.eq")
        sw_trap_on(sb, x, ir::TrapKind.TkOverflow, ip)
        sw_op(sb, "else")
        c2 := sw_lda(sb, ip); sw_const(sb, 0); sw_op(sb, "i64.ne")
        sw_op(sb, "if")
        sw_get(sb, r); c3 := sw_lda(sb, ip); sw_op(sb, "i64.div_s"); c4 := sw_ldb(sb, ip); sw_op(sb, "i64.ne")
        sw_trap_on(sb, x, ir::TrapKind.TkOverflow, ip)
        sw_op(sb, "end")
        sw_op(sb, "end")
      } else {
        c5 := sw_lda(sb, ip); sw_const(sb, 0); sw_op(sb, "i64.ne")
        sw_op(sb, "if")
        sw_get(sb, r); c6 := sw_lda(sb, ip); sw_op(sb, "i64.div_u"); c7 := sw_ldb(sb, ip); sw_op(sb, "i64.ne")
        sw_trap_on(sb, x, ir::TrapKind.TkOverflow, ip)
        sw_op(sb, "end")
      }
    }
  }
  sw_get(sb, r)
  sw_setd(sb, ip)
}
## `/ %` at 64 bits. `chk` traps `div_zero` on a zero divisor and, signed, `div_overflow` on
## `MIN / -1` (§4). Any other mode is the hardware division (`hw`, owner decision D1: wasm's
## `div`/`rem` trap on a zero divisor and `div_s` on `MIN / -1`, as the legacy emitter's do).
sw_div := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  sg : ir::Sgn = ir::i_sg(ip)
  mut signed := false
  match sg { SgS => { signed = true }; SgU => {}; SgNone => { return false } }
  if ir::mode_is_chk(ir::i_md(ip)) {
    if not sw_ldb(sb, ip) { return false }
    sw_op(sb, "i64.eqz")
    sw_trap_on(sb, x, ir::TrapKind.TkDivZero, ip)
    if signed {
      d1 := sw_ldb(sb, ip); sw_const(sb, 0 - 1); sw_op(sb, "i64.eq")
      d2 := sw_lda(sb, ip); sw_const(sb, 0 - 9223372036854775807 - 1); sw_op(sb, "i64.eq")
      sw_op(sb, "i32.and")
      sw_trap_on(sb, x, ir::TrapKind.TkDivOverflow, ip)
    }
  }
  if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
  match o {
    OpRem => { if signed { sw_op(sb, "i64.rem_s") } else { sw_op(sb, "i64.rem_u") } }
    OpDiv | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { if signed { sw_op(sb, "i64.div_s") } else { sw_op(sb, "i64.div_u") } }
  }
  sw_setd(sb, ip)
}
## A two-operand op with no check: `& | ^`, a rotation, an unchecked shift.
sw_bin := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), mn : str) -> bool {
  if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
  sw_op(sb, mn)
  sw_setd(sb, ip)
}
## `shl`/`shr` at 64 bits. `chk` traps `shift_range` on a count ≥ 64; otherwise the wasm shift (count
## mod 64). `shr` is arithmetic on a signed value, logical on an unsigned one.
sw_shift := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if ir::mode_is_chk(ir::i_md(ip)) {
    if not sw_ldb(sb, ip) { return false }
    sw_const(sb, 64)
    sw_op(sb, "i64.ge_u")
    sw_trap_on(sb, x, ir::TrapKind.TkShiftRange, ip)
  }
  match o {
    OpShl => { sw_bin(sb, ip, "i64.shl") }
    OpShr | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      sg : ir::Sgn = ir::i_sg(ip)
      match sg {
        SgS => { sw_bin(sb, ip, "i64.shr_s") }
        SgU => { sw_bin(sb, ip, "i64.shr_u") }
        SgNone => { false }
      }
    }
  }
}
## `rotl`/`rotr` at 64 bits (the builder spells a narrow rotation with shifts).
sw_rot := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), mn : str) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  sw_bin(sb, ip, mn)
}
## `ext T <- F`: wrap or widen to the DESTINATION's type and signedness (§3.4).
sw_ext := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sw_dst(ip)
  match dv {
    Some(d) => {
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      if not ir::kty_is_int(ty) { return false }
      if not sw_lda(sb, ip) { return false }
      if not sw_canon(sb, ty, sg) { return false }
      sw_set(sb, d)
      true
    }
    None => { false }
  }
}
## `fit T <- F`: the checked narrow (see `aarch64::isel`'s `sa_fit`): the canonical form at the
## destination must be the same word, and the source non-negative when the signednesses differ.
sw_fit := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sw_dst(ip)
  match dv {
    Some(d) => {
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      ## A width op spells its SOURCE's signedness (V4); the destination's is its vreg's.
      fsg : ir::Sgn = ir::i_sg(ip)
      if not ir::kty_is_int(ty) { return false }
      if not sw_lda(sb, ip) { return false }
      if not sw_canon(sb, ty, sg) { return false }
      r := x.s0
      sw_set(sb, r)
      sw_get(sb, r)
      f1 := sw_lda(sb, ip)
      sw_op(sb, "i64.ne")
      if not ir::sgn_eq(sg, fsg) {
        f2 := sw_lda(sb, ip)
        sw_const(sb, 0)
        sw_op(sb, "i64.lt_s")
        sw_op(sb, "i32.or")
      }
      sw_trap_on(sb, x, ir::i_tk(ip), ip)
      sw_get(sb, r)
      sw_set(sb, d)
      true
    }
    None => { false }
  }
}
## The wasm comparison of a predicate at a signedness (an ordering needs one).
sw_cmp_op := fn(c : ir::Cc, sg : ir::Sgn) -> Option(str) {
  match c {
    CcEq => { Option(str).Some("i64.eq") }
    CcNe => { Option(str).Some("i64.ne") }
    CcLt => { sw_ord(sg, "i64.lt_s", "i64.lt_u") }
    CcLe => { sw_ord(sg, "i64.le_s", "i64.le_u") }
    CcGt => { sw_ord(sg, "i64.gt_s", "i64.gt_u") }
    CcGe => { sw_ord(sg, "i64.ge_s", "i64.ge_u") }
    CcNone => { Option(str).None }
  }
}
sw_ord := fn(sg : ir::Sgn, s : str, u : str) -> Option(str) {
  match sg { SgS => { Option(str).Some(s) }; SgU => { Option(str).Some(u) }; SgNone => { Option(str).None } }
}
## `cmp` → `bool` (an i64 0 or 1).
sw_cmp := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  cc : ir::Cc = ir::i_cc(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  co : Option(str) = sw_cmp_op(cc, sg)
  match co {
    Some(c) => {
      if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
      sw_op(sb, c)
      sw_op(sb, "i64.extend_i32_u")
      sw_setd(sb, ip)
    }
    None => { false }
  }
}
## The declaration a symbol operand names.
sw_sym_decl := fn(x : SwX, ip : ptr(mut ir::IrInst)) -> Option(Decl) {
  match ir::i_ak(ip) {
    OkSym => {
      di := ir::sym_decl(x.p, ir::SymId(usize(ir::i_av(ip))))
      d : Decl = deref(lower_ctx::decl_get(x.decls, di))
      Option(Decl).Some(d)
    }
    OkNone | OkVReg | OkImm | OkFrame | OkFn | OkLabel => { Option(Decl).None }
  }
}
## `addr @g` of a module scalar that has a wasm global: remembered, not emitted (see the header).
sw_addr := fn(x : SwX, in out a : rt::Arena, ip : ptr(mut ir::IrInst)) -> bool {
  gdo : Option(Decl) = sw_sym_decl(x, ip)
  dv : Option(usize) = sw_dst(ip)
  match gdo {
    Some(g) => {
      has_global := lower_layout::global_has_scalar_cell(g)
      if not has_global { return false }
      match dv {
        Some(d) => {
          q1 := ir::wb_push(x.gv, a, d)
          q2 := ir::wb_push(x.gs, a, usize(ir::i_av(ip)))
          true
        }
        None => { false }
      }
    }
    None => { false }
  }
}
## The symbol whose address vreg `v` holds, if `addr` gave it one.
sw_addr_of := fn(x : SwX, v : usize) -> Option(usize) {
  mut i : usize = 0
  while i < ir::wb_len(x.gv) {
    if ir::wb_get(x.gv, i) == v { return Option(usize).Some(ir::wb_get(x.gs, i)) }
    i = i + 1
  }
  Option(usize).None
}
## `load T [%a + 0]` of a module scalar's address: `global.get`, canonicalized at `T` by its spelled
## signedness. A load from any other address is outside what this selector models before slice 3.
sw_load := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  if ir::i_off(ip) != 0 { return false }
  match ir::i_ak(ip) {
    OkVReg => {}
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { return false }
  }
  so : Option(usize) = sw_addr_of(x, usize(ir::i_av(ip)))
  match so {
    Some(s) => {
      di := ir::sym_decl(x.p, ir::SymId(s))
      g : Decl = deref(lower_ctx::decl_get(x.decls, di))
      gname := str_at((x.src + g.name_start), g.name_len)
      sw_put(sb, "    global.get $")
      sw_put(sb, gname)
      sw_put(sb, "\n")
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::i_sg(ip)
      if not sw_canon(sb, ty, sg) { return false }
      sw_setd(sb, ip)
    }
    None => { false }
  }
}
## A direct call: the arguments pushed in order, `call $<name>`, the result canonicalized from the
## destination's type (or dropped when the callee answers one nobody reads).
sw_call := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  cdo : Option(Decl) = sw_sym_decl(x, ip)
  match cdo {
    Some(cd) => {
      if not cd.is_fn or cd.name_len == 0 or wat_ovl_is_marked(cd.name_start) { return false }
      n := ir::i_n(ip)
      mut j : usize = 0
      while j < n {
        sw_get(sb, ir::pool_get(x.f, ir::i_pool(ip) + j))
        j = j + 1
      }
      cname := str_at((x.src + cd.name_start), cd.name_len)
      sw_put(sb, "    call $")
      sw_put(sb, cname)
      sw_put(sb, "\n")
      dv : Option(usize) = sw_dst(ip)
      mut ok := true
      match dv {
        Some(d) => {
          ty : ir::Kty = ir::vreg_ty(x.f, d)
          sg : ir::Sgn = ir::vreg_sg(x.f, d)
          ok = sw_canon(sb, ty, sg)
          sw_set(sb, d)
        }
        None => { if cd.ret_tl != 0 { sw_op(sb, "drop") } }
      }
      ok
    }
    None => { false }
  }
}

## ── regions ──

sw_push := fn(x : SwX, in out a : rt::Arena, k : usize) { q := ir::wb_push(x.stk, a, k) }
sw_top := fn(x : SwX) -> Option(usize) {
  n := ir::wb_len(x.stk)
  if n == 0 { return Option(usize).None }
  Option(usize).Some(ir::wb_get(x.stk, n - 1))
}
## `block $L<n>` / `loop $L<n>`, named by the IR label.
sw_open := fn(in out sb : rt::StrBuf, mn : str, ip : ptr(mut ir::IrInst)) {
  sw_put(sb, "    ")
  sw_put(sb, mn)
  sw_put(sb, " $L")
  sw_u(sb, ir::i_lbl(ip))
  sw_put(sb, "\n")
}
## `end` closes a `block`, `loop`, `if` or `else`; `unchecked` has no wasm region.
sw_end := fn(in out sb : rt::StrBuf, x : SwX) -> bool {
  to : Option(usize) = sw_top(x)
  match to {
    Some(k) => {
      kp := ir::fn_inst(x.f, k)
      o : ir::Op = ir::i_op(kp)
      match o {
        OpBlock | OpLoop | OpIf | OpElse => { sw_op(sb, "end") }
        OpUnch | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
          | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp
          | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad
          | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpEnd | OpBr
          | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
      }
      ir::wb_pop(x.stk)
    }
    None => { false }
  }
}
## A `bool` vreg as wasm's i32 condition.
sw_cond := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sw_lda(sb, ip) { return false }
  sw_op(sb, "i32.wrap_i64")
  true
}

## One instruction. Answers false when the selector does not select it (the function then falls back).
sw_inst := fn(in out sb : rt::StrBuf, x : SwX, in out a : rt::Arena, i : usize) -> bool {
  ip := ir::fn_inst(x.f, i)
  o : ir::Op = ir::i_op(ip)
  match o {
    OpConst | OpMov => { sw_mov(sb, ip) }
    OpAdd | OpSub | OpMul => { sw_arith(sb, x, ip, o) }
    OpDiv | OpRem => { sw_div(sb, x, ip, o) }
    OpAnd => { sw_bin(sb, ip, "i64.and") }
    OpOr => { sw_bin(sb, ip, "i64.or") }
    OpXor => { sw_bin(sb, ip, "i64.xor") }
    OpShl | OpShr => { sw_shift(sb, x, ip, o) }
    OpRotl => { sw_rot(sb, ip, "i64.rotl") }
    OpRotr => { sw_rot(sb, ip, "i64.rotr") }
    OpExt => { sw_ext(sb, x, ip) }
    OpFit => { sw_fit(sb, x, ip) }
    OpCmp => { sw_cmp(sb, ip) }
    OpAddrSym => { sw_addr(x, a, ip) }
    OpLoad => { sw_load(sb, x, ip) }
    OpCall => { sw_call(sb, x, ip) }
    OpBlock => { sw_open(sb, "block", ip); sw_push(x, a, i); true }
    OpLoop => { sw_open(sb, "loop", ip); sw_push(x, a, i); true }
    OpUnch => { sw_push(x, a, i); true }
    OpIf => {
      if not sw_cond(sb, ip) { return false }
      sw_op(sb, "if")
      sw_push(x, a, i)
      true
    }
    OpElse => {
      sw_op(sb, "else")
      ir::wb_set_top(x.stk, i)
    }
    OpEnd => { sw_end(sb, x) }
    OpBr => { sw_put(sb, "    br $L"); sw_u(sb, ir::i_lbl(ip)); sw_put(sb, "\n"); true }
    OpBrIf => {
      if not sw_cond(sb, ip) { return false }
      sw_put(sb, "    br_if $L")
      sw_u(sb, ir::i_lbl(ip))
      sw_put(sb, "\n")
      true
    }
    OpRet => {
      match ir::i_ak(ip) {
        OkVReg => { sw_get(sb, usize(ir::i_av(ip))) }
        OkNone => {}
        OkImm | OkFrame | OkSym | OkFn | OkLabel => { return false }
      }
      sw_op(sb, "return")
      true
    }
    OpTrap => { sw_trap(sb, x, ir::i_tk(ip), ip); true }
    OpTrapIf => {
      if not sw_cond(sb, ip) { return false }
      sw_trap_on(sb, x, ir::i_tk(ip), ip)
      true
    }
    OpFConst | OpAddrFrame | OpFnAddr | OpNot | OpNeg | OpTrunc | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCallInd
      | OpCallC | OpSyscall | OpSwitch => { false }
  }
}

## Select function `f` (declaration `d`) into `sb`. Answers false when the function is refused.
sw_fn := fn(in out sb : rt::StrBuf, x : SwX, d : Decl, in out a : rt::Arena) -> bool {
  if wat_ovl_is_marked(d.name_start) { return false }
  nv := ir::fn_nvregs(x.f)
  np := ir::fn_nparams(x.f)
  fname := str_at((x.src + d.name_start), d.name_len)
  sw_put(sb, "  (; ir: selected from the shared IR ;)\n  (func $")
  sw_put(sb, fname)
  mut pi : usize = 0
  while pi < np { sw_put(sb, " (param i64)"); pi = pi + 1 }
  has_ret := ir::fn_has_ret(x.f)
  if has_ret { sw_put(sb, " (result i64)") }
  sw_put(sb, "\n    (local")
  mut li : usize = np
  while li < nv + 2 { sw_put(sb, " i64"); li = li + 1 }
  sw_put(sb, ")\n")
  pi = 0
  while pi < np {
    if not sw_canon_local(sb, x, pi) { return false }
    pi = pi + 1
  }
  ni := ir::fn_ninst(x.f)
  mut i : usize = 0
  while i < ni {
    if not sw_inst(sb, x, a, i) { return false }
    i = i + 1
  }
  if ir::wb_len(x.stk) != 0 { return false }
  if has_ret { sw_op(sb, "unreachable") }
  sw_put(sb, "  )\n")
  xn := wat_export_name(x.src, d.name_start, d.name_len)
  if xn.n != 0 {
    sw_put(sb, "  (export \"")
    sw_put(sb, str_at((x.src + xn.s), xn.n))
    sw_put(sb, "\" (func $")
    sw_put(sb, fname)
    sw_put(sb, "))\n")
  }
  true
}

## The hook in `emit_wat_program`'s declaration loop (see `aarch64::isel`'s `a64_isel_try`).
pub wat_isel_try := fn(decls : ptr(rt::Vec), di : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) -> bool {
  mut ia := a
  p := ir::prog_new(ia)
  si : ir::SelIn = ir::select_input(p, decls, src, di, ia)
  match si {
    SiBuilt(f) => {
      d : Decl = deref(lower_ctx::decl_get(decls, di))
      nv := ir::fn_nvregs(f)
      x := SwX(f = f, p = p, src = src, decls = decls, fspan = d.name_start, stk = ir::wb_new(ia, 16), s0 = nv, gv = ir::wb_new(ia, 8), gs = ir::wb_new(ia, 8))
      mark := sb.len
      if sw_fn(sb, x, d, ia) { return true }
      sb.len = mark
      false
    }
    SiLegacy => { false }
  }
}
