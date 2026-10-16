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
## `fobj`: each frame object's byte offset from the frame base `fp` (a local, after the two scratch
## locals); slice 3w: frame objects live on the shadow stack in linear memory (docs/ir.md §6).
SwX := struct { f : ptr(mut ir::IrFn), p : ir::IrProg, src : ptr(u8), decls : ptr(rt::Vec), fspan : usize, stk : ptr(mut ir::WBuf), s0 : usize, gv : ptr(mut ir::WBuf), gs : ptr(mut ir::WBuf), fobj : ptr(mut ir::WBuf), fp : usize, gt : ptr(mut ir::WBuf) }

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
## `addr @G` of a module-global word array (the only aggregate global the builder addresses,
## `ib_bx_index_global`): its linear-memory address, which the legacy data emitter decides and
## `wat.al` hands over in `x.gt` (pairs of declaration index and base) — one layout, never a second
## copy of it here (Q4).
sw_addr := fn(in out sb : rt::StrBuf, x : SwX, in out a : rt::Arena, ip : ptr(mut ir::IrInst)) -> bool {
  gdo : Option(Decl) = sw_sym_decl(x, ip)
  dv : Option(usize) = sw_dst(ip)
  match gdo {
    Some(g) => {
      has_global := lower_layout::global_has_scalar_cell(g)
      if not has_global {
        gbo : Option(usize) = sw_word_array_base(x, ip)
        match gbo {
          Some(base) => {
            sw_const(sb, i64(base))
            return sw_setd(sb, ip)
          }
          None => { return false }
        }
      }
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
## The legacy linear-memory base of the word-array global `addr @G` names, from `x.gt`.
sw_word_array_base := fn(x : SwX, ip : ptr(mut ir::IrInst)) -> Option(usize) {
  match ir::i_ak(ip) {
    OkSym => {
      di := ir::sym_decl(x.p, ir::SymId(usize(ir::i_av(ip))))
      mut i : usize = 0
      while i + 1 < ir::wb_len(x.gt) {
        if ir::wb_get(x.gt, i) == di { return Option(usize).Some(ir::wb_get(x.gt, i + 1)) }
        i = i + 2
      }
    }
    OkNone | OkVReg | OkImm | OkFrame | OkFn | OkLabel => {}
  }
  Option(usize).None
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
## `load T [a + off]`. A module scalar is a wasm GLOBAL, not memory: `load [%g + 0]` of an address
## `addr @g` gave is a `global.get`, canonicalized at `T` by its spelled signedness (slice 3b). Any other
## address is linear memory (slice 3w): `i64.load*` of `T`'s width, sign- or zero-extended by `T`'s
## spelled signedness — the canonical i64 form every other value of `T` has here.
sw_load := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  ty : ir::Kty = ir::i_ty(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  gso : Option(usize) = sw_global_base(x, ir::i_ak(ip), ir::i_av(ip))
  match gso {
    Some(s) => {
      if ir::i_off(ip) != 0 { return false }
      di := ir::sym_decl(x.p, ir::SymId(s))
      g : Decl = deref(lower_ctx::decl_get(x.decls, di))
      gname := str_at((x.src + g.name_start), g.name_len)
      sw_put(sb, "    global.get $")
      sw_put(sb, gname)
      sw_put(sb, "\n")
      if not sw_canon(sb, ty, sg) { return false }
      return sw_setd(sb, ip)
    }
    None => {}
  }
  if not sw_addr32(sb, x, ir::i_ak(ip), ir::i_av(ip), ir::i_off(ip)) { return false }
  lio : Option(str) = sw_load_ins(ir::kty_bytes(ty), ir::sgn_eq(sg, ir::Sgn.SgS))
  match lio { Some(ins) => { sw_op(sb, ins) }; None => { return false } }
  sw_setd(sb, ip)
}
## `store T [a + off], v`. Into a module scalar (slice 3b): `global.set` of the whole `i64` cell (the
## builder stores a module scalar's whole word). Anywhere else, linear memory: `i64.store*` of `T`'s
## width (slice 3w).
sw_store := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  ty : ir::Kty = ir::i_ty(ip)
  gso : Option(usize) = sw_global_base(x, ir::i_ak(ip), ir::i_av(ip))
  match gso {
    Some(s) => {
      if ir::i_off(ip) != 0 { return false }
      match ty {
        KI64 | KBool => {}
        KI8 | KI16 | KI32 | KPtr | KF32 | KF64 | KNone => { return false }
      }
      if not sw_ld(sb, ir::i_bk(ip), ir::i_bv(ip)) { return false }
      di := ir::sym_decl(x.p, ir::SymId(s))
      g : Decl = deref(lower_ctx::decl_get(x.decls, di))
      gname := str_at((x.src + g.name_start), g.name_len)
      sw_put(sb, "    global.set $")
      sw_put(sb, gname)
      sw_put(sb, "\n")
      return true
    }
    None => {}
  }
  if not sw_addr32(sb, x, ir::i_ak(ip), ir::i_av(ip), ir::i_off(ip)) { return false }
  if not sw_ld(sb, ir::i_bk(ip), ir::i_bv(ip)) { return false }
  sio : Option(str) = sw_store_ins(ir::kty_bytes(ty))
  match sio { Some(ins) => { sw_op(sb, ins) }; None => { return false } }
  true
}
## The load of an `nb`-byte value into the canonical i64 (extended by the spelled signedness).
sw_load_ins := fn(nb : u64, signed : bool) -> Option(str) {
  if nb == 8 { return Option(str).Some("i64.load") }
  if nb == 4 and signed { return Option(str).Some("i64.load32_s") }
  if nb == 4 { return Option(str).Some("i64.load32_u") }
  if nb == 2 and signed { return Option(str).Some("i64.load16_s") }
  if nb == 2 { return Option(str).Some("i64.load16_u") }
  if nb == 1 and signed { return Option(str).Some("i64.load8_s") }
  if nb == 1 { return Option(str).Some("i64.load8_u") }
  Option(str).None
}
## The store of the low `nb` bytes of an i64.
sw_store_ins := fn(nb : u64) -> Option(str) {
  if nb == 8 { return Option(str).Some("i64.store") }
  if nb == 4 { return Option(str).Some("i64.store32") }
  if nb == 2 { return Option(str).Some("i64.store16") }
  if nb == 1 { return Option(str).Some("i64.store8") }
  Option(str).None
}
## The module scalar a base operand addresses, when it is a vreg `addr @g` gave (a wasm global, not
## memory); `None` for every other base.
sw_global_base := fn(x : SwX, k : ir::OpndK, v : i64) -> Option(usize) {
  match k {
    OkVReg => { return sw_addr_of(x, usize(v)) }
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => {}
  }
  Option(usize).None
}
## Push the i64 address `base + off`: a `ptr` vreg's value, or a frame object's place on the shadow
## stack (`fp` + its offset). A vreg holding a module scalar's address names a wasm global, which has no
## memory address, so it refuses.
sw_addr64 := fn(in out sb : rt::StrBuf, x : SwX, k : ir::OpndK, v : i64, off : i64) -> bool {
  match k {
    OkVReg => {
      gso : Option(usize) = sw_addr_of(x, usize(v))
      match gso { Some(s) => { return false }; None => {} }
      sw_get(sb, usize(v))
    }
    OkFrame => {
      if v < 0 or usize(v) >= ir::wb_len(x.fobj) { return false }
      sw_get(sb, x.fp)
      sw_const(sb, i64(ir::wb_get(x.fobj, usize(v))))
      sw_op(sb, "i64.add")
    }
    OkNone | OkImm | OkSym | OkFn | OkLabel => { return false }
  }
  if off != 0 {
    sw_const(sb, off)
    sw_op(sb, "i64.add")
  }
  true
}
## The same address as wasm's i32 memory index.
sw_addr32 := fn(in out sb : rt::StrBuf, x : SwX, k : ir::OpndK, v : i64, off : i64) -> bool {
  if not sw_addr64(sb, x, k, v, off) { return false }
  sw_op(sb, "i32.wrap_i64")
  true
}
## `%d = bswap T %a` (slice 3e, `@endian(big)`): wasm has no byte reverse, so the low `T`-width bytes
## are moved one by one through the two scratch locals (byte i to byte nb-1-i), then canonical at `T`.
sw_bswap := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  ty : ir::Kty = ir::i_ty(ip)
  nb := ir::kty_bytes(ty)
  if nb != 1 and nb != 2 and nb != 4 and nb != 8 { return false }
  if not sw_lda(sb, ip) { return false }
  sw_set(sb, x.s0)
  sw_const(sb, 0)
  sw_set(sb, x.s0 + 1)
  mut i : u64 = 0
  while i < nb {
    sw_get(sb, x.s0 + 1)
    sw_get(sb, x.s0)
    sw_const(sb, i64(i * 8))
    sw_op(sb, "i64.shr_u")
    sw_const(sb, 255)
    sw_op(sb, "i64.and")
    sw_const(sb, i64((nb - 1 - i) * 8))
    sw_op(sb, "i64.shl")
    sw_op(sb, "i64.or")
    sw_set(sb, x.s0 + 1)
    i = i + 1
  }
  sw_get(sb, x.s0 + 1)
  if not sw_canon(sb, ty, ir::i_sg(ip)) { return false }
  sw_setd(sb, ip)
}
## `copy dst, src, n` / `zero dst, n`: unrolled, 8-byte words when `n` is a multiple of 8, bytes
## otherwise (`n` is the object's size, known here). A very large object refuses rather than emit a
## page of code.
sw_mem := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst), copy : bool) -> bool {
  n := ir::i_n(ip)
  words := n % 8 == 0
  mut step : usize = 1
  if words { step = 8 }
  if n / step > 64 { return false }
  mut lins := "i64.load8_u"
  mut sins := "i64.store8"
  if words { lins = "i64.load"; sins = "i64.store" }
  mut o : usize = 0
  while o < n {
    if not sw_addr32(sb, x, ir::i_ak(ip), ir::i_av(ip), i64(o)) { return false }
    if copy {
      if not sw_addr32(sb, x, ir::i_bk(ip), ir::i_bv(ip), i64(o)) { return false }
      sw_op(sb, lins)
    }
    if not copy { sw_const(sb, 0) }
    sw_op(sb, sins)
    o = o + step
  }
  true
}
## Slice 4c: the words of a call's aggregate result — at the address the callee returned (on the stack)
## — copied into the frame object that receives it.
sw_agg_res := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  nb := ir::frame_bytes(x.f, usize(ir::i_dv(ip)))
  if nb == 0 or nb > 512 or nb % 8 != 0 { return false }
  sw_set(sb, x.s0)
  mut o : usize = 0
  while o < nb {
    if not sw_addr32(sb, x, ir::i_dk(ip), ir::i_dv(ip), i64(o)) { return false }
    sw_get(sb, x.s0)
    if o != 0 {
      sw_const(sb, i64(o))
      sw_op(sb, "i64.add")
    }
    sw_op(sb, "i32.wrap_i64")
    sw_op(sb, "i64.load")
    sw_op(sb, "i64.store")
    o = o + 8
  }
  true
}
## A direct call: the arguments pushed in order, `call $<name>`, the result canonicalized from the
## destination's type (or dropped when the callee answers one nobody reads).
sw_call := fn(in out sb : rt::StrBuf, x : SwX, ip : ptr(mut ir::IrInst)) -> bool {
  ## Slice 4c: a call whose aggregate result lands in a frame object. wasm's convention (its legacy
  ## emitter's, measured) returns the ADDRESS of a block in linear memory holding the words; the words
  ## are copied from there into the receiving object (`sw_agg_res`).
  fdst := ir::opndk_is_frame(ir::i_dk(ip))
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
      if fdst { return sw_agg_res(sb, x, ip) }
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
    OpAddrSym => { sw_addr(sb, x, a, ip) }
    OpLoad => { sw_load(sb, x, ip) }
    OpStore => { sw_store(sb, x, ip) }
    OpAddrFrame => {
      if not sw_addr64(sb, x, ir::i_ak(ip), ir::i_av(ip), 0) { return false }
      sw_setd(sb, ip)
    }
    OpGep => {
      ## `gep a, i, stride`: `a + i * stride` (the stride is the op's offset), no check (§3.4)
      if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
      sw_const(sb, ir::i_off(ip))
      sw_op(sb, "i64.mul")
      sw_op(sb, "i64.add")
      sw_setd(sb, ip)
    }
    OpBound => {
      ## `bound i, n`: trap with the op's kind unless `i < n`, read unsigned
      if not sw_lda(sb, ip) or not sw_ldb(sb, ip) { return false }
      sw_op(sb, "i64.ge_u")
      sw_trap_on(sb, x, ir::i_tk(ip), ip)
      true
    }
    OpBSwap => { sw_bswap(sb, x, ip) }
    OpCopy => { sw_mem(sb, x, ip, true) }
    OpZero => { sw_mem(sb, x, ip, false) }
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
    OpFConst | OpFnAddr | OpNot | OpNeg | OpTrunc | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpCallInd
      | OpCallC | OpSyscall | OpSwitch => { false }
  }
}

## Select function `f` (declaration `d`) into `sb`. Answers false when the function is refused.
sw_fn := fn(in out sb : rt::StrBuf, x : SwX, d : Decl, in out a : rt::Arena) -> bool {
  if wat_ovl_is_marked(d.name_start) { return false }
  ## Slice 3w: frame objects live on the shadow stack in linear memory (`docs/ir.md` §6), laid out from
  ## `fp`, the value of the module's `$__sp` at entry. This first step does not pop the frame on return:
  ## the legacy emitter bump-allocates the same way and never reclaims, and a legacy callee may hand back
  ## a pointer into memory it bumped above our frame, so reclaiming needs a rule of its own (step 2).
  nfr := ir::fn_nframes(x.f)
  mut ftot : usize = 0
  mut fk : usize = 0
  while fk < nfr {
    al := ir::frame_align_of(x.f, fk)
    if al == 0 or al > 8 { return false }
    ftot = (ftot + al - 1) / al * al
    k1 := ir::wb_push(x.fobj, a, ftot)
    ftot = ftot + ir::frame_bytes(x.f, fk)
    fk = fk + 1
  }
  ftot = (ftot + 7) / 8 * 8
  ## Slice 4c: an aggregate result is returned as the ADDRESS of its frame object — wasm's convention
  ## (its legacy emitter returns a bump-allocated block's address). The object stays valid after the
  ## return because the shadow stack is never reclaimed (3w step 1, as the legacy blocks are not); a
  ## step that reclaims frames must copy the result out first.
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
  while li < nv + 3 { sw_put(sb, " i64"); li = li + 1 }
  sw_put(sb, ")\n")
  pi = 0
  while pi < np {
    if not sw_canon_local(sb, x, pi) { return false }
    pi = pi + 1
  }
  if nfr > 0 {
    sw_op(sb, "global.get $__sp")
    sw_set(sb, x.fp)
    sw_get(sb, x.fp)
    sw_const(sb, i64(ftot))
    sw_op(sb, "i64.add")
    sw_op(sb, "global.set $__sp")
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
pub wat_isel_try := fn(decls : ptr(rt::Vec), di : usize, gt : ptr(mut ir::WBuf), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) -> bool {
  mut ia := a
  p := ir::prog_new(ia)
  si : ir::SelIn = ir::select_input(p, decls, src, di, ia)
  match si {
    SiBuilt(f) => {
      d : Decl = deref(lower_ctx::decl_get(decls, di))
      nv := ir::fn_nvregs(f)
      x := SwX(f = f, p = p, src = src, decls = decls, fspan = d.name_start, stk = ir::wb_new(ia, 16), s0 = nv, gv = ir::wb_new(ia, 8), gs = ir::wb_new(ia, 8), fobj = ir::wb_new(ia, 8), fp = nv + 2, gt = gt)
      mark := sb.len
      if sw_fn(sb, x, d, ia) { return true }
      sb.len = mark
      false
    }
    SiLegacy => { false }
  }
}
