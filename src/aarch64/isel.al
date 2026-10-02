## selfhost::aarch64::isel — the AArch64 instruction selector over the shared IR (`docs/ir.md` §6,
## `docs/ir-slice-1.md` §4, slice 1c).
##
## A function the IR builder BUILT and the verifier accepted is emitted from its IR here instead of by
## `emit_a64_fn`; every other function keeps its legacy emission (owner decision D7). The selector is
## target text only: it never reads the AST. Every width and signedness decision it makes is read from
## the IR value's attributes (§3.8) — the instruction's `ty`/`sg` (a width op's `sg` is its source's) and the destination
## vreg's recorded type — never re-derived.
##
## Frame slots first (§6): vreg `k` lives in the 8-byte slot `[x29, #16 + 8k]`. Each instruction
## loads its operands into scratch registers (x9, x10), computes into x11 (x12 a temporary) and stores
## the full 64-bit result: canonical form is the builder's job (V3), and `ext`/`fit` are the only width
## instructions this file emits for an operation. A trap is `brk #0` with `// trap <kind> <file>:<line>:<col>`.
##
## The convention is the target's existing one for the scalar class (`docs/ir-slice-1.md` §3):
## arguments in x0..x7, the result in x0, the legacy label (`a64_emit_fn_label`), so an IR-built and a
## legacy-emitted function call each other. Both ends of a call re-canonicalize a narrow value from its
## IR type (a parameter at entry, a result after the `bl`), because a legacy peer does not promise it.
##
## A selector may REFUSE a function (an op it does not select, more than 8 parameters, a frame past
## the addressing range); the caller then rewinds the output and emits the function the legacy way.
(Decl) := ast

## What one function is selected against: the IR, the program its symbols index, the source, the
## declaration list, a per-program function number for local labels, the function's own name span
## (the location of a trap that carries none), and the region stack (opener instruction indices).
SaX := struct { f : ptr(mut ir::IrFn), p : ir::IrProg, src : ptr(u8), decls : ptr(rt::Vec), fid : usize, fspan : usize, stk : ptr(mut ir::WBuf) }

## The number of the next function this selector emits, for its `.Lir<n>_<k>` labels.
mut SA_FN : usize = 0

sa_put := fn(in out sb : rt::StrBuf, s : str) { k := rt::push_str(sb, s) }
sa_int := fn(in out sb : rt::StrBuf, n : i64) { k := rt::push_int(sb, n) }
sa_u := fn(in out sb : rt::StrBuf, n : usize) { k := rt::push_int(sb, i64(n)) }

## The frame byte offset of vreg `v`'s slot.
sa_off := fn(v : usize) -> i64 { 16 + i64(v) * 8 }
## The most vregs a frame may hold: `ldr x, [x29, #imm]` addresses at most 32760 bytes.
SA_MAX_VREGS : usize = 4000

## `  ldr <reg>, [x29, #<slot of v>]` / `  str …`.
sa_ldv := fn(in out sb : rt::StrBuf, reg : str, v : usize) {
  sa_put(sb, "  ldr "); sa_put(sb, reg); sa_put(sb, ", [x29, #"); sa_int(sb, sa_off(v)); sa_put(sb, "]\n")
}
sa_stv := fn(in out sb : rt::StrBuf, reg : str, v : usize) {
  sa_put(sb, "  str "); sa_put(sb, reg); sa_put(sb, ", [x29, #"); sa_int(sb, sa_off(v)); sa_put(sb, "]\n")
}
## Load an operand (a vreg or an immediate) into `reg`. Any other operand kind is not a value here.
sa_ld := fn(in out sb : rt::StrBuf, reg : str, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sa_ldv(sb, reg, usize(v)); true }
    OkImm => { sa_put(sb, "  ldr "); sa_put(sb, reg); sa_put(sb, ", ="); sa_int(sb, v); sa_put(sb, "\n"); true }
    OkNone | OkFrame | OkSym | OkFn | OkLabel => { false }
  }
}
sa_lda := fn(in out sb : rt::StrBuf, reg : str, ip : ptr(mut ir::IrInst)) -> bool { sa_ld(sb, reg, ir::i_ak(ip), ir::i_av(ip)) }
sa_ldb := fn(in out sb : rt::StrBuf, reg : str, ip : ptr(mut ir::IrInst)) -> bool { sa_ld(sb, reg, ir::i_bk(ip), ir::i_bv(ip)) }
## The destination vreg of `ip`, if it defines one.
sa_dst := fn(ip : ptr(mut ir::IrInst)) -> Option(usize) {
  match ir::i_dk(ip) {
    OkVReg => { Option(usize).Some(usize(ir::i_dv(ip))) }
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { Option(usize).None }
  }
}
## Store x11 into `ip`'s destination.
sa_st11 := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sa_dst(ip)
  match dv { Some(d) => { sa_stv(sb, "x11", d); true }; None => { false } }
}

## `.Lir<fn>_<k>` — the one label family of a selected function. A region opener at instruction `k`
## names its label by `k`: a `block`'s end, a `loop`'s head, an `if`'s false arm, an `else`'s join.
sa_lbl := fn(in out sb : rt::StrBuf, x : SaX, k : usize) { sa_put(sb, ".Lir"); sa_u(sb, x.fid); sa_put(sb, "_"); sa_u(sb, k) }
sa_def_lbl := fn(in out sb : rt::StrBuf, x : SaX, k : usize) { sa_lbl(sb, x, k); sa_put(sb, ":\n") }
sa_ret_lbl := fn(in out sb : rt::StrBuf, x : SaX) { sa_put(sb, ".Lir"); sa_u(sb, x.fid); sa_put(sb, "_ret") }

## `  brk #0 // trap <kind> <file>:<line>:<col>` (§3.6).
sa_trap := fn(in out sb : rt::StrBuf, x : SaX, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  tn := ir::trap_name(tk)
  sa_put(sb, "  brk #0 // trap ")
  sa_put(sb, tn)
  sa_put(sb, " ")
  ir::put_inst_loc(sb, x.src, ip, x.fspan)
  sa_put(sb, "\n")
}

## `rd ← canonical(rs)` at type `ty` with signedness `sg` (§3.2): a narrow integer is sign- or
## zero-extended from its width, a 64-bit value, a `bool` and a pointer are already their word.
sa_canon := fn(in out sb : rt::StrBuf, xd : str, wd : str, xs : str, ws : str, ty : ir::Kty, sg : ir::Sgn) -> bool {
  match ty {
    KI8 => { sa_narrow(sb, xd, wd, ws, sg, "  sxtb ", "  uxtb ") }
    KI16 => { sa_narrow(sb, xd, wd, ws, sg, "  sxth ", "  uxth ") }
    KI32 => { sa_narrow(sb, xd, wd, ws, sg, "  sxtw ", "  mov ") }
    KI64 | KBool | KPtr => { sa_put(sb, "  mov "); sa_put(sb, xd); sa_put(sb, ", "); sa_put(sb, xs); sa_put(sb, "\n"); true }
    KF32 | KF64 | KNone => { false }
  }
}
## A narrow extension: `<sext> xd, ws` for a signed type, `<zext> wd, ws` (which clears the upper word)
## for an unsigned one. A narrow integer always carries a signedness.
sa_narrow := fn(in out sb : rt::StrBuf, xd : str, wd : str, ws : str, sg : ir::Sgn, sext : str, zext : str) -> bool {
  match sg {
    SgS => { sa_put(sb, sext); sa_put(sb, xd); sa_put(sb, ", "); sa_put(sb, ws); sa_put(sb, "\n"); true }
    SgU => { sa_put(sb, zext); sa_put(sb, wd); sa_put(sb, ", "); sa_put(sb, ws); sa_put(sb, "\n"); true }
    SgNone => { false }
  }
}
## Canonicalize slot `v` in place, from its recorded type (a parameter at entry, a call's result).
sa_canon_slot := fn(in out sb : rt::StrBuf, x : SaX, v : usize, reg_x : str, reg_w : str) -> bool {
  ty : ir::Kty = ir::vreg_ty(x.f, v)
  sg : ir::Sgn = ir::vreg_sg(x.f, v)
  if not ir::kty_is_narrow(ty) { return true }
  sa_ldv(sb, reg_x, v)
  if not sa_canon(sb, reg_x, reg_w, reg_x, reg_w, ty, sg) { return false }
  sa_stv(sb, reg_x, v)
  true
}

## How a comparison's operands are read: as signed or unsigned integers, or as floats after `fcmp`.
pub A64Cmp := enum { CkSigned, CkUnsigned, CkFloat }
## The AArch64 condition code of a comparison predicate — the one table, read by the selector and by
## the legacy `a64_cond`/`a64_ucond`/`a64_fcond`. An unsigned ordering uses the carry conditions, so
## `0 < u64::MAX` reads true. After `fcmp` the ordered predicates read false on an unordered result
## (C=1, V=1), `ne` true.
pub a64_cc_code := fn(c : ir::Cc, k : A64Cmp) -> Option(str) {
  match c {
    CcEq => { Option(str).Some("eq") }
    CcNe => { Option(str).Some("ne") }
    CcLt => { match k { CkSigned => { Option(str).Some("lt") }; CkUnsigned => { Option(str).Some("lo") }; CkFloat => { Option(str).Some("mi") } } }
    CcLe => { match k { CkSigned => { Option(str).Some("le") }; CkUnsigned => { Option(str).Some("ls") }; CkFloat => { Option(str).Some("ls") } } }
    CcGt => { match k { CkSigned => { Option(str).Some("gt") }; CkUnsigned => { Option(str).Some("hi") }; CkFloat => { Option(str).Some("gt") } } }
    CcGe => { match k { CkSigned => { Option(str).Some("ge") }; CkUnsigned => { Option(str).Some("hs") }; CkFloat => { Option(str).Some("ge") } } }
    CcNone => { Option(str).None }
  }
}
## How an integer `cmp` reads its operands: its spelled signedness. Equality spells none and reads
## the words either way; an ordering without one is not a comparison this selector selects.
sa_cmp_kind := fn(c : ir::Cc, sg : ir::Sgn) -> Option(A64Cmp) {
  match sg {
    SgS => { Option(A64Cmp).Some(A64Cmp.CkSigned) }
    SgU => { Option(A64Cmp).Some(A64Cmp.CkUnsigned) }
    SgNone => {
      match c {
        CcEq | CcNe => { Option(A64Cmp).Some(A64Cmp.CkSigned) }
        CcLt | CcLe | CcGt | CcGe | CcNone => { Option(A64Cmp).None }
      }
    }
  }
}

## ── the operations ──

sa_const := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sa_lda(sb, "x11", ip) { return false }
  sa_st11(sb, ip)
}
sa_mov := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sa_lda(sb, "x11", ip) { return false }
  sa_st11(sb, ip)
}
## `+ - *` at 64 bits. `chk` traps `overflow` on the operation's own signedness: `adds`/`subs` set V
## for a signed and C for an unsigned overflow; a product overflows when its high word is not the
## sign (signed) or zero (unsigned) extension of its low word.
sa_arith := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
  md : ir::Mode = ir::i_md(ip)
  if not ir::mode_is_chk(md) {
    match o {
      OpAdd => { sa_put(sb, "  add x11, x9, x10\n") }
      OpSub => { sa_put(sb, "  sub x11, x9, x10\n") }
      OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
        | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
        | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
        | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
        | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { sa_put(sb, "  mul x11, x9, x10\n") }
    }
    return sa_st11(sb, ip)
  }
  sg : ir::Sgn = ir::i_sg(ip)
  signed := ir::sgn_eq(sg, ir::Sgn.SgS)
  match o {
    OpAdd => { sa_put(sb, "  adds x11, x9, x10\n"); if signed { sa_put(sb, "  b.vc 1f\n") } else { sa_put(sb, "  b.cc 1f\n") } }
    OpSub => { sa_put(sb, "  subs x11, x9, x10\n"); if signed { sa_put(sb, "  b.vc 1f\n") } else { sa_put(sb, "  b.cs 1f\n") } }
    OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      sa_put(sb, "  mul x11, x9, x10\n")
      if signed { sa_put(sb, "  smulh x12, x9, x10\n  cmp x12, x11, asr #63\n  b.eq 1f\n") }
      else { sa_put(sb, "  umulh x12, x9, x10\n  cbz x12, 1f\n") }
    }
  }
  sa_trap(sb, x, ir::TrapKind.TkOverflow, ip)
  sa_put(sb, "1:\n")
  sa_st11(sb, ip)
}
## `/ %` at 64 bits. `chk` traps `div_zero` on a zero divisor and, signed, `div_overflow` on
## `MIN / -1` (§4); the builder states both checks before the op as well, and the op keeps its own
## meaning regardless. Any other mode is the hardware division (`hw`, owner decision D1: AArch64's
## `sdiv`/`udiv` answer 0 for a zero divisor and `MIN` for `MIN / -1`, as the legacy emitter does).
sa_div := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
  sg : ir::Sgn = ir::i_sg(ip)
  mut signed := false
  match sg { SgS => { signed = true }; SgU => {}; SgNone => { return false } }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sa_put(sb, "  cbnz x10, 1f\n")
    sa_trap(sb, x, ir::TrapKind.TkDivZero, ip)
    sa_put(sb, "1:\n")
    if signed {
      sa_put(sb, "  cmn x10, #1\n  b.ne 1f\n  mov x12, #1\n  lsl x12, x12, #63\n  cmp x9, x12\n  b.ne 1f\n")
      sa_trap(sb, x, ir::TrapKind.TkDivOverflow, ip)
      sa_put(sb, "1:\n")
    }
  }
  if signed { sa_put(sb, "  sdiv x11, x9, x10\n") } else { sa_put(sb, "  udiv x11, x9, x10\n") }
  match o {
    OpRem => { sa_put(sb, "  msub x11, x11, x10, x9\n") }
    OpDiv | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
  }
  sa_st11(sb, ip)
}
## `& | ^` on canonical operands, at any integer width or `bool` (canonical-preserving, V3).
sa_bits := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), mn : str) -> bool {
  if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
  sa_put(sb, mn)
  sa_put(sb, " x11, x9, x10\n")
  sa_st11(sb, ip)
}
## `shl`/`shr` at 64 bits. `chk` traps `shift_range` on a count ≥ 64; otherwise (`hw`, or a `wrap` the
## builder proved in range) the register shift. `shr` is arithmetic on a signed value, logical on an
## unsigned one — the op's spelled signedness.
sa_shift := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sa_put(sb, "  cmp x10, #64\n  b.lo 1f\n")
    sa_trap(sb, x, ir::TrapKind.TkShiftRange, ip)
    sa_put(sb, "1:\n")
  }
  match o {
    OpShl => { sa_put(sb, "  lsl x11, x9, x10\n") }
    OpShr | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      sg : ir::Sgn = ir::i_sg(ip)
      match sg {
        SgS => { sa_put(sb, "  asr x11, x9, x10\n") }
        SgU => { sa_put(sb, "  lsr x11, x9, x10\n") }
        SgNone => { return false }
      }
    }
  }
  sa_st11(sb, ip)
}
## `rotl`/`rotr` at 64 bits (the builder spells a narrow rotation with shifts): `ror`, and `rotl n` as
## `ror (-n)` (the count is taken mod 64).
sa_rot := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
  match o {
    OpRotr => { sa_put(sb, "  ror x11, x9, x10\n") }
    OpRotl | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { sa_put(sb, "  neg x12, x10\n  ror x11, x9, x12\n") }
  }
  sa_st11(sb, ip)
}
## `ext T <- F`: wrap or widen to the DESTINATION's type and signedness (§3.4). The source is
## canonical, so its word is its value; the destination's recorded type decides the extension.
sa_ext := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sa_dst(ip)
  match dv {
    Some(d) => {
      if not sa_lda(sb, "x9", ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      if not ir::kty_is_int(ty) { return false }
      if not sa_canon(sb, "x11", "w11", "x9", "w9", ty, sg) { return false }
      sa_stv(sb, "x11", d)
      true
    }
    None => { false }
  }
}
## `fit T <- F`: the checked narrow. The value fits when its canonical form at the destination type is
## the same word AND, when the two signednesses differ, the source is not negative as read by its own
## (signed source) or does not exceed the signed range (unsigned source) — both are "bit 63 clear".
## Otherwise it traps with the op's kind (`narrow`, or `div_overflow` for a narrowed quotient).
sa_fit := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sa_dst(ip)
  match dv {
    Some(d) => {
      if not sa_lda(sb, "x9", ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      ## A width op spells its SOURCE's signedness (V4); the destination's is its vreg's.
      fsg : ir::Sgn = ir::i_sg(ip)
      if not ir::kty_is_int(ty) { return false }
      if not sa_canon(sb, "x11", "w11", "x9", "w9", ty, sg) { return false }
      sa_put(sb, "  cmp x11, x9\n  b.ne 2f\n")
      if not ir::sgn_eq(sg, fsg) { sa_put(sb, "  tbnz x9, #63, 2f\n") }
      sa_put(sb, "  b 1f\n2:\n")
      sa_trap(sb, x, ir::i_tk(ip), ip)
      sa_put(sb, "1:\n")
      sa_stv(sb, "x11", d)
      true
    }
    None => { false }
  }
}
## `cmp` → `bool`: the predicate's condition at the op's spelled signedness.
sa_cmp := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  cc : ir::Cc = ir::i_cc(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  ko : Option(A64Cmp) = sa_cmp_kind(cc, sg)
  mut co : Option(str) = Option(str).None
  match ko { Some(k) => { co = a64_cc_code(cc, k) }; None => {} }
  match co {
    Some(c) => {
      if not sa_lda(sb, "x9", ip) or not sa_ldb(sb, "x10", ip) { return false }
      sa_put(sb, "  cmp x9, x10\n  cset x11, ")
      sa_put(sb, c)
      sa_put(sb, "\n")
      sa_st11(sb, ip)
    }
    None => { false }
  }
}
## The declaration a symbol operand names.
sa_sym_decl := fn(x : SaX, ip : ptr(mut ir::IrInst)) -> Option(Decl) {
  match ir::i_ak(ip) {
    OkSym => {
      di := ir::sym_decl(x.p, ir::SymId(usize(ir::i_av(ip))))
      d : Decl = deref(lower_ctx::decl_get(x.decls, di))
      Option(Decl).Some(d)
    }
    OkNone | OkVReg | OkImm | OkFrame | OkFn | OkLabel => { Option(Decl).None }
  }
}
## `addr @g` of a module scalar: the address of the `.quad` cell `emit_a64_program` gives it, under
## the target's existing global naming (its bare name). A symbol without such a cell is refused.
sa_addr := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst)) -> bool {
  gdo : Option(Decl) = sa_sym_decl(x, ip)
  match gdo {
    Some(g) => {
      has_cell := lower_layout::global_has_scalar_cell(g)
      if not has_cell { return false }
      gname := str_at((x.src + g.name_start), g.name_len)
      sa_put(sb, "  adrp x11, ")
      sa_put(sb, gname)
      sa_put(sb, "\n  add x11, x11, :lo12:")
      sa_put(sb, gname)
      sa_put(sb, "\n")
      sa_st11(sb, ip)
    }
    None => { false }
  }
}
## `load T [a + off]`: the width from `T`, the extension from its spelled signedness.
sa_load := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  off := ir::i_off(ip)
  if off < 0 or off > 4095 { return false }
  if not sa_lda(sb, "x9", ip) { return false }
  ty : ir::Kty = ir::i_ty(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  mut mn : str = ""
  match ty {
    KI8 => { match sg { SgS => { mn = "  ldrsb x11" }; SgU => { mn = "  ldrb w11" }; SgNone => { return false } } }
    KI16 => { match sg { SgS => { mn = "  ldrsh x11" }; SgU => { mn = "  ldrh w11" }; SgNone => { return false } } }
    KI32 => { match sg { SgS => { mn = "  ldrsw x11" }; SgU => { mn = "  ldr w11" }; SgNone => { return false } } }
    KI64 | KPtr => { mn = "  ldr x11" }
    KBool => { mn = "  ldrb w11" }
    KF32 | KF64 | KNone => { return false }
  }
  if off % i64(ir::kty_bytes(ty)) != 0 { return false }
  sa_put(sb, mn)
  sa_put(sb, ", [x9, #")
  sa_int(sb, off)
  sa_put(sb, "]\n")
  sa_st11(sb, ip)
}
## A direct call: the arguments in x0..x7, `bl` the callee's legacy label, the result from x0,
## re-canonicalized from the destination's type.
sa_call := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst)) -> bool {
  n := ir::i_n(ip)
  if n > 8 { return false }
  cdo : Option(Decl) = sa_sym_decl(x, ip)
  match cdo {
    Some(cd) => {
      if not cd.is_fn or cd.name_len == 0 { return false }
      mut j : usize = 0
      while j < n {
        av := ir::pool_get(x.f, ir::i_pool(ip) + j)
        sa_put(sb, "  ldr x")
        sa_u(sb, j)
        sa_put(sb, ", [x29, #")
        sa_int(sb, sa_off(av))
        sa_put(sb, "]\n")
        j = j + 1
      }
      sa_put(sb, "  bl ")
      a64_emit_fn_label(sb, x.src, cd)
      sa_put(sb, "\n")
      dv : Option(usize) = sa_dst(ip)
      mut ok := true
      match dv {
        Some(d) => {
          sa_stv(sb, "x0", d)
          ok = sa_canon_slot(sb, x, d, "x9", "w9")
        }
        None => {}
      }
      ok
    }
    None => { false }
  }
}

## ── regions ──

stk_push := fn(x : SaX, in out a : rt::Arena, k : usize) { q := ir::wb_push(x.stk, a, k) }
## The innermost open region's opener index.
stk_top := fn(x : SaX) -> Option(usize) {
  n := ir::wb_len(x.stk)
  if n == 0 { return Option(usize).None }
  Option(usize).Some(ir::wb_get(x.stk, n - 1))
}
stk_set_top := fn(x : SaX, k : usize) -> bool { ir::wb_set_top(x.stk, k) }
stk_pop := fn(x : SaX) -> bool { ir::wb_pop(x.stk) }
## The open `block`/`loop` whose IR label is `l`, by its opener index.
stk_find := fn(x : SaX, l : usize) -> Option(usize) {
  mut n := ir::wb_len(x.stk)
  while n > 0 {
    k := ir::wb_get(x.stk, n - 1)
    kp := ir::fn_inst(x.f, k)
    o : ir::Op = ir::i_op(kp)
    match o {
      OpBlock | OpLoop => { if ir::i_lbl(kp) == l { return Option(usize).Some(k) } }
      OpIf | OpElse | OpUnch | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul
        | OpDiv | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc
        | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits
        | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall
        | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
    }
    n = n - 1
  }
  Option(usize).None
}
## `br L` / `br_if c L`: a `block`'s label is its end, a `loop`'s its head — both named by the opener.
sa_br := fn(in out sb : rt::StrBuf, x : SaX, ip : ptr(mut ir::IrInst), cond : bool) -> bool {
  to : Option(usize) = stk_find(x, ir::i_lbl(ip))
  match to {
    Some(k) => {
      if cond {
        if not sa_lda(sb, "x9", ip) { return false }
        sa_put(sb, "  cbz x9, 1f\n  b ")
        sa_lbl(sb, x, k)
        sa_put(sb, "\n1:\n")
        return true
      }
      sa_put(sb, "  b ")
      sa_lbl(sb, x, k)
      sa_put(sb, "\n")
      true
    }
    None => { false }
  }
}
## `end`: a `block` defines its end label, an `if` with no `else` its false arm, an `else` its join; a
## `loop` falls out (its head was defined at the opener) and `unchecked` emits nothing.
sa_end := fn(in out sb : rt::StrBuf, x : SaX) -> bool {
  to : Option(usize) = stk_top(x)
  match to {
    Some(k) => {
      kp := ir::fn_inst(x.f, k)
      o : ir::Op = ir::i_op(kp)
      match o {
        OpBlock | OpIf | OpElse => { sa_def_lbl(sb, x, k) }
        OpLoop | OpUnch | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
          | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp
          | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad
          | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpEnd | OpBr
          | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
      }
      stk_pop(x)
    }
    None => { false }
  }
}

## One instruction. Answers false when the selector does not select it (the function then falls back).
sa_inst := fn(in out sb : rt::StrBuf, x : SaX, in out a : rt::Arena, i : usize) -> bool {
  ip := ir::fn_inst(x.f, i)
  o : ir::Op = ir::i_op(ip)
  match o {
    OpConst => { sa_const(sb, ip) }
    OpMov => { sa_mov(sb, ip) }
    OpAdd | OpSub | OpMul => { sa_arith(sb, x, ip, o) }
    OpDiv | OpRem => { sa_div(sb, x, ip, o) }
    OpAnd => { sa_bits(sb, ip, "  and") }
    OpOr => { sa_bits(sb, ip, "  orr") }
    OpXor => { sa_bits(sb, ip, "  eor") }
    OpShl | OpShr => { sa_shift(sb, x, ip, o) }
    OpRotl | OpRotr => { sa_rot(sb, ip, o) }
    OpExt => { sa_ext(sb, x, ip) }
    OpFit => { sa_fit(sb, x, ip) }
    OpCmp => { sa_cmp(sb, ip) }
    OpAddrSym => { sa_addr(sb, x, ip) }
    OpLoad => { sa_load(sb, ip) }
    OpCall => { sa_call(sb, x, ip) }
    OpBlock | OpUnch => { stk_push(x, a, i); true }
    OpLoop => { stk_push(x, a, i); sa_def_lbl(sb, x, i); true }
    OpIf => {
      if not sa_lda(sb, "x9", ip) { return false }
      sa_put(sb, "  cbnz x9, 1f\n  b ")
      sa_lbl(sb, x, i)
      sa_put(sb, "\n1:\n")
      stk_push(x, a, i)
      true
    }
    OpElse => {
      to : Option(usize) = stk_top(x)
      match to {
        Some(k) => {
          sa_put(sb, "  b ")
          sa_lbl(sb, x, i)
          sa_put(sb, "\n")
          sa_def_lbl(sb, x, k)
          stk_set_top(x, i)
        }
        None => { false }
      }
    }
    OpEnd => { sa_end(sb, x) }
    OpBr => { sa_br(sb, x, ip, false) }
    OpBrIf => { sa_br(sb, x, ip, true) }
    OpRet => {
      match ir::i_ak(ip) {
        OkVReg => { sa_ldv(sb, "x0", usize(ir::i_av(ip))) }
        OkNone => {}
        OkImm | OkFrame | OkSym | OkFn | OkLabel => { return false }
      }
      sa_put(sb, "  b ")
      sa_ret_lbl(sb, x)
      sa_put(sb, "\n")
      true
    }
    OpTrap => { sa_trap(sb, x, ir::i_tk(ip), ip); true }
    OpTrapIf => {
      if not sa_lda(sb, "x9", ip) { return false }
      sa_put(sb, "  cbz x9, 1f\n")
      sa_trap(sb, x, ir::i_tk(ip), ip)
      sa_put(sb, "1:\n")
      true
    }
    OpFConst | OpAddrFrame | OpFnAddr | OpNot | OpNeg | OpTrunc | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCallInd
      | OpCallC | OpSyscall | OpSwitch => { false }
  }
}

## Select function `f` (declaration `d`) into `sb`. Answers false — with `sb` possibly partly
## written; the caller rewinds it — when the function is refused.
sa_fn := fn(in out sb : rt::StrBuf, x : SaX, d : Decl, in out a : rt::Arena) -> bool {
  nv := ir::fn_nvregs(x.f)
  np := ir::fn_nparams(x.f)
  if np > 8 or nv > SA_MAX_VREGS { return false }
  mut frame : i64 = 16 + i64(nv) * 8
  if frame % 16 != 0 { frame = frame + 8 }
  sa_put(sb, "// ir: selected from the shared IR\n")
  emit_a64_export(sb, x.src, d.name_start, d.name_len)
  a64_emit_fn_label(sb, x.src, d)
  sa_put(sb, ":\n")
  if frame <= 504 { sa_put(sb, "  stp x29, x30, [sp, #-"); sa_int(sb, frame); sa_put(sb, "]!\n") }
  else { sa_put(sb, "  mov x9, #"); sa_int(sb, frame); sa_put(sb, "\n  sub sp, sp, x9\n  stp x29, x30, [sp]\n") }
  sa_put(sb, "  mov x29, sp\n")
  mut pi : usize = 0
  while pi < np {
    sa_put(sb, "  str x")
    sa_u(sb, pi)
    sa_put(sb, ", [x29, #")
    sa_int(sb, sa_off(pi))
    sa_put(sb, "]\n")
    pi = pi + 1
  }
  pi = 0
  while pi < np {
    if not sa_canon_slot(sb, x, pi, "x9", "w9") { return false }
    pi = pi + 1
  }
  ni := ir::fn_ninst(x.f)
  mut i : usize = 0
  while i < ni {
    if not sa_inst(sb, x, a, i) { return false }
    i = i + 1
  }
  if ir::wb_len(x.stk) != 0 { return false }
  sa_ret_lbl(sb, x)
  sa_put(sb, ":\n  mov sp, x29\n")
  if frame <= 504 { sa_put(sb, "  ldp x29, x30, [sp], #"); sa_int(sb, frame); sa_put(sb, "\n") }
  else { sa_put(sb, "  ldp x29, x30, [sp]\n  mov x9, #"); sa_int(sb, frame); sa_put(sb, "\n  add sp, sp, x9\n") }
  sa_put(sb, "  ret\n")
  true
}

## The hook in `emit_a64_program`'s declaration loop: emit declaration `di` from the shared IR when
## the builder builds it, the verifier accepts it and this selector selects every op. Answers whether
## it did; on false nothing was written and the caller emits the declaration the legacy way.
pub a64_isel_try := fn(decls : ptr(rt::Vec), di : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) -> bool {
  mut ia := a
  p := ir::prog_new(ia)
  si : ir::SelIn = ir::select_input(p, decls, src, di, ia)
  match si {
    SiBuilt(f) => {
      d : Decl = deref(lower_ctx::decl_get(decls, di))
      x := SaX(f = f, p = p, src = src, decls = decls, fid = SA_FN, fspan = d.name_start, stk = ir::wb_new(ia, 16))
      mark := sb.len
      if sa_fn(sb, x, d, ia) {
        SA_FN = SA_FN + 1
        return true
      }
      sb.len = mark
      false
    }
    SiLegacy => { false }
  }
}
