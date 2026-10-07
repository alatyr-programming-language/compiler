## selfhost::riscv64::isel — the RISC-V64 instruction selector over the shared IR (`docs/ir.md` §6,
## `docs/ir-slice-1.md` §4, slice 1c).
##
## A function the IR builder BUILT and the verifier accepted is emitted from its IR here instead of by
## `emit_rv_fn`; every other function keeps its legacy emission (owner decision D7). The selector is
## target text only: it never reads the AST. Every width and signedness decision it makes is read from
## the IR value's attributes (§3.8) — the instruction's `ty`/`sg` (a width op's `sg` is its source's) and the destination vreg's
## recorded type — never re-derived.
##
## Frame slots first (§6): vreg `k` lives in the 8-byte slot `16 + 8k(s0)`; a slot past the 12-bit
## displacement is addressed through t6. Operands load into t0/t1, the result is computed in t2 (t3,
## t4 temporaries) and stored whole: canonical form is the builder's job (V3). RISC-V has no flags,
## so a checked operation's overflow is a compare sequence (§6). A trap is `ebreak` with
## `# trap <kind> <file>:<line>:<col>`. A conditional transfer to a region label is a short branch
## over a `j`, so no function outgrows the ±4 KiB branch range.
##
## The convention is the target's existing one for the scalar class (`docs/ir-slice-1.md` §3):
## arguments in a0..a7, the result in a0, the legacy label (the bare name `emit_rv_fn` defines), so an
## IR-built and a legacy-emitted function call each other. A narrow parameter and a narrow call result
## are re-canonicalized from their IR type, because a legacy peer does not promise canonical form.
##
## Frame objects (slice 3a: struct locals and aggregate temporaries, `docs/ir.md` §3.3) follow the vreg
## slots, each at its alignment (`ir::frame_place`); an address operand `$k` is `s0 + <its offset>`.
## `load`/`store` take the width from the IR type, `copy`/`zero` move whole words when the size is a
## multiple of 8 and bytes otherwise.
##
## A selector may REFUSE a function (an op it does not select, more than 8 parameters); the caller then
## rewinds the output and emits the function the legacy way.
(Decl) := ast

## What one function is selected against (see `aarch64::isel`'s `SaX`).
SrX := struct { f : ptr(mut ir::IrFn), p : ir::IrProg, src : ptr(u8), decls : ptr(rt::Vec), fid : usize, fspan : usize, stk : ptr(mut ir::WBuf), fobj : ptr(mut ir::WBuf) }

## The number of the next function this selector emits, for its `.Lir<n>_<k>` labels.
mut SR_FN : usize = 0

sr_put := fn(in out sb : rt::StrBuf, s : str) { k := rt::push_str(sb, s) }
sr_int := fn(in out sb : rt::StrBuf, n : i64) { k := rt::push_int(sb, n) }
sr_u := fn(in out sb : rt::StrBuf, n : usize) { k := rt::push_int(sb, i64(n)) }

## The frame byte offset of vreg `v`'s slot.
sr_off := fn(v : usize) -> i64 { 16 + i64(v) * 8 }
## The largest 12-bit signed displacement a load or store encodes.
SR_DISP_MAX : i64 = 2040

## `  <op> <reg>, <slot of v>` — `ld`/`sd` of a slot, through t6 when the slot is out of reach.
sr_slot := fn(in out sb : rt::StrBuf, op : str, reg : str, v : usize) {
  off := sr_off(v)
  if off <= SR_DISP_MAX {
    sr_put(sb, "  "); sr_put(sb, op); sr_put(sb, " "); sr_put(sb, reg); sr_put(sb, ", "); sr_int(sb, off); sr_put(sb, "(s0)\n")
    return
  }
  sr_put(sb, "  li t6, "); sr_int(sb, off); sr_put(sb, "\n  add t6, s0, t6\n")
  sr_put(sb, "  "); sr_put(sb, op); sr_put(sb, " "); sr_put(sb, reg); sr_put(sb, ", 0(t6)\n")
}
sr_ldv := fn(in out sb : rt::StrBuf, reg : str, v : usize) { sr_slot(sb, "ld", reg, v) }
sr_stv := fn(in out sb : rt::StrBuf, reg : str, v : usize) { sr_slot(sb, "sd", reg, v) }
## Load an operand (a vreg or an immediate) into `reg`. Any other operand kind is not a value here.
sr_ld := fn(in out sb : rt::StrBuf, reg : str, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sr_ldv(sb, reg, usize(v)); true }
    OkImm => { sr_put(sb, "  li "); sr_put(sb, reg); sr_put(sb, ", "); sr_int(sb, v); sr_put(sb, "\n"); true }
    OkNone | OkFrame | OkSym | OkFn | OkLabel => { false }
  }
}
sr_lda := fn(in out sb : rt::StrBuf, reg : str, ip : ptr(mut ir::IrInst)) -> bool { sr_ld(sb, reg, ir::i_ak(ip), ir::i_av(ip)) }
sr_ldb := fn(in out sb : rt::StrBuf, reg : str, ip : ptr(mut ir::IrInst)) -> bool { sr_ld(sb, reg, ir::i_bk(ip), ir::i_bv(ip)) }
sr_dst := fn(ip : ptr(mut ir::IrInst)) -> Option(usize) {
  match ir::i_dk(ip) {
    OkVReg => { Option(usize).Some(usize(ir::i_dv(ip))) }
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { Option(usize).None }
  }
}
## Store t2 into `ip`'s destination.
sr_st2 := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sr_dst(ip)
  match dv { Some(d) => { sr_stv(sb, "t2", d); true }; None => { false } }
}

## `.Lir<fn>_<k>` — the one label family of a selected function (see `aarch64::isel`).
sr_lbl := fn(in out sb : rt::StrBuf, x : SrX, k : usize) { sr_put(sb, ".Lir"); sr_u(sb, x.fid); sr_put(sb, "_"); sr_u(sb, k) }
sr_def_lbl := fn(in out sb : rt::StrBuf, x : SrX, k : usize) { sr_lbl(sb, x, k); sr_put(sb, ":\n") }
sr_ret_lbl := fn(in out sb : rt::StrBuf, x : SrX) { sr_put(sb, ".Lir"); sr_u(sb, x.fid); sr_put(sb, "_ret") }

## `  ebreak  # trap <kind> <file>:<line>:<col>` (§3.6).
sr_trap := fn(in out sb : rt::StrBuf, x : SrX, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  tn := ir::trap_name(tk)
  sr_put(sb, "  ebreak  # trap ")
  sr_put(sb, tn)
  sr_put(sb, " ")
  ir::put_inst_loc(sb, x.src, ip, x.fspan)
  sr_put(sb, "\n")
}

## `rd ← canonical(rs)` at type `ty` with signedness `sg` (§3.2): a narrow integer is shifted to the
## top of the word and back, arithmetically for a signed type, logically for an unsigned one.
sr_canon := fn(in out sb : rt::StrBuf, rd : str, rs : str, ty : ir::Kty, sg : ir::Sgn) -> bool {
  match ty {
    KI8 => { sr_narrow(sb, rd, rs, 56, sg) }
    KI16 => { sr_narrow(sb, rd, rs, 48, sg) }
    KI32 => { sr_narrow(sb, rd, rs, 32, sg) }
    KI64 | KBool | KPtr => { sr_put(sb, "  mv "); sr_put(sb, rd); sr_put(sb, ", "); sr_put(sb, rs); sr_put(sb, "\n"); true }
    KF32 | KF64 | KNone => { false }
  }
}
sr_narrow := fn(in out sb : rt::StrBuf, rd : str, rs : str, sh : i64, sg : ir::Sgn) -> bool {
  mut back : str = ""
  match sg { SgS => { back = "  srai " }; SgU => { back = "  srli " }; SgNone => { return false } }
  sr_put(sb, "  slli "); sr_put(sb, rd); sr_put(sb, ", "); sr_put(sb, rs); sr_put(sb, ", "); sr_int(sb, sh); sr_put(sb, "\n")
  sr_put(sb, back); sr_put(sb, rd); sr_put(sb, ", "); sr_put(sb, rd); sr_put(sb, ", "); sr_int(sb, sh); sr_put(sb, "\n")
  true
}
## Canonicalize slot `v` in place, from its recorded type (a parameter at entry, a call's result).
sr_canon_slot := fn(in out sb : rt::StrBuf, x : SrX, v : usize) -> bool {
  ty : ir::Kty = ir::vreg_ty(x.f, v)
  sg : ir::Sgn = ir::vreg_sg(x.f, v)
  if not ir::kty_is_narrow(ty) { return true }
  sr_ldv(sb, "t0", v)
  if not sr_canon(sb, "t0", "t0", ty, sg) { return false }
  sr_stv(sb, "t0", v)
  true
}

## ── the operations ──

sr_const := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sr_lda(sb, "t2", ip) { return false }
  sr_st2(sb, ip)
}
## `+ - *` at 64 bits. `chk` traps `overflow` on the op's own signedness: a signed sum overflows when
## `(b < 0) != (r < a)`, a signed difference when `(b < 0) != (a < r)`, an unsigned sum when `r < a`,
## an unsigned difference when `a < b`; a product when its high word is not the sign (signed) or zero
## (unsigned) extension of its low word.
sr_arith := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  md : ir::Mode = ir::i_md(ip)
  mut mn : str = "  mul"
  match o {
    OpAdd => { mn = "  add" }
    OpSub => { mn = "  sub" }
    OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {}
  }
  sr_put(sb, mn)
  sr_put(sb, " t2, t0, t1\n")
  if not ir::mode_is_chk(md) { return sr_st2(sb, ip) }
  sg : ir::Sgn = ir::i_sg(ip)
  signed := ir::sgn_eq(sg, ir::Sgn.SgS)
  match o {
    OpAdd => {
      if signed { sr_put(sb, "  slt t3, t2, t0\n  slti t4, t1, 0\n  beq t3, t4, 1f\n") } else { sr_put(sb, "  bgeu t2, t0, 1f\n") }
    }
    OpSub => {
      if signed { sr_put(sb, "  slt t3, t0, t2\n  slti t4, t1, 0\n  beq t3, t4, 1f\n") } else { sr_put(sb, "  bgeu t0, t1, 1f\n") }
    }
    OpMul | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpDiv | OpRem | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      if signed { sr_put(sb, "  mulh t3, t0, t1\n  srai t4, t2, 63\n  beq t3, t4, 1f\n") } else { sr_put(sb, "  mulhu t3, t0, t1\n  beqz t3, 1f\n") }
    }
  }
  sr_trap(sb, x, ir::TrapKind.TkOverflow, ip)
  sr_put(sb, "1:\n")
  sr_st2(sb, ip)
}
## `/ %` at 64 bits. `chk` traps `div_zero` on a zero divisor and, signed, `div_overflow` on
## `MIN / -1` (§4). Any other mode is the hardware division (`hw`, owner decision D1: RISC-V answers
## all ones for a zero divisor, the dividend for its remainder, and `MIN` for `MIN / -1`).
sr_div := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  sg : ir::Sgn = ir::i_sg(ip)
  mut signed := false
  match sg { SgS => { signed = true }; SgU => {}; SgNone => { return false } }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sr_put(sb, "  bnez t1, 1f\n")
    sr_trap(sb, x, ir::TrapKind.TkDivZero, ip)
    sr_put(sb, "1:\n")
    if signed {
      sr_put(sb, "  li t3, -1\n  bne t1, t3, 1f\n  li t3, 1\n  slli t3, t3, 63\n  bne t0, t3, 1f\n")
      sr_trap(sb, x, ir::TrapKind.TkDivOverflow, ip)
      sr_put(sb, "1:\n")
    }
  }
  mut mn : str = "  div"
  match o {
    OpRem => { if signed { mn = "  rem" } else { mn = "  remu" } }
    OpDiv | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { if signed { mn = "  div" } else { mn = "  divu" } }
  }
  sr_put(sb, mn)
  sr_put(sb, " t2, t0, t1\n")
  sr_st2(sb, ip)
}
## `& | ^` on canonical operands (canonical-preserving at any width, V3).
sr_bits := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), mn : str) -> bool {
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  sr_put(sb, mn)
  sr_put(sb, " t2, t0, t1\n")
  sr_st2(sb, ip)
}
## `shl`/`shr` at 64 bits. `chk` traps `shift_range` on a count ≥ 64; otherwise the register shift
## (count mod 64). `shr` is arithmetic on a signed value, logical on an unsigned one.
sr_shift := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sr_put(sb, "  li t3, 64\n  bltu t1, t3, 1f\n")
    sr_trap(sb, x, ir::TrapKind.TkShiftRange, ip)
    sr_put(sb, "1:\n")
  }
  match o {
    OpShl => { sr_put(sb, "  sll t2, t0, t1\n") }
    OpShr | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => {
      sg : ir::Sgn = ir::i_sg(ip)
      match sg {
        SgS => { sr_put(sb, "  sra t2, t0, t1\n") }
        SgU => { sr_put(sb, "  srl t2, t0, t1\n") }
        SgNone => { return false }
      }
    }
  }
  sr_st2(sb, ip)
}
## `rotl`/`rotr` at 64 bits, from the base ISA's shifts: `rotl n = (v << n) | (v >> -n)` with both
## counts taken mod 64 by `sll`/`srl` (a zero count gives `v | v`), and its mirror.
sr_rot := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), o : ir::Op) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  sr_put(sb, "  neg t3, t1\n")
  match o {
    OpRotr => { sr_put(sb, "  srl t2, t0, t1\n  sll t3, t0, t3\n") }
    OpRotl | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub
      | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { sr_put(sb, "  sll t2, t0, t1\n  srl t3, t0, t3\n") }
  }
  sr_put(sb, "  or t2, t2, t3\n")
  sr_st2(sb, ip)
}
## `ext T <- F`: wrap or widen to the DESTINATION's type and signedness (§3.4).
sr_ext := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sr_dst(ip)
  match dv {
    Some(d) => {
      if not sr_lda(sb, "t0", ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      if not ir::kty_is_int(ty) { return false }
      if not sr_canon(sb, "t2", "t0", ty, sg) { return false }
      sr_stv(sb, "t2", d)
      true
    }
    None => { false }
  }
}
## `fit T <- F`: the checked narrow (see `aarch64::isel`'s `sa_fit`): the canonical form at the
## destination must be the same word, and bit 63 clear when the signednesses differ.
sr_fit := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(usize) = sr_dst(ip)
  match dv {
    Some(d) => {
      if not sr_lda(sb, "t0", ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, d)
      ## A width op spells its SOURCE's signedness (V4); the destination's is its vreg's.
      fsg : ir::Sgn = ir::i_sg(ip)
      if not ir::kty_is_int(ty) { return false }
      if not sr_canon(sb, "t2", "t0", ty, sg) { return false }
      sr_put(sb, "  bne t2, t0, 2f\n")
      if not ir::sgn_eq(sg, fsg) { sr_put(sb, "  bltz t0, 2f\n") }
      sr_put(sb, "  j 1f\n2:\n")
      sr_trap(sb, x, ir::i_tk(ip), ip)
      sr_put(sb, "1:\n")
      sr_stv(sb, "t2", d)
      true
    }
    None => { false }
  }
}
## `cmp` → `bool`: `slt`/`sltu` at the op's spelled signedness, equality by `xor` and a zero test.
sr_cmp := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  cc : ir::Cc = ir::i_cc(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  if not sr_lda(sb, "t0", ip) or not sr_ldb(sb, "t1", ip) { return false }
  mut slt : str = "  slt"
  match cc {
    CcEq => { sr_put(sb, "  xor t2, t0, t1\n  seqz t2, t2\n"); return sr_st2(sb, ip) }
    CcNe => { sr_put(sb, "  xor t2, t0, t1\n  snez t2, t2\n"); return sr_st2(sb, ip) }
    CcLt | CcLe | CcGt | CcGe => {
      match sg { SgS => {}; SgU => { slt = "  sltu" }; SgNone => { return false } }
    }
    CcNone => { return false }
  }
  match cc {
    CcLt => { sr_put(sb, slt); sr_put(sb, " t2, t0, t1\n") }
    CcGt => { sr_put(sb, slt); sr_put(sb, " t2, t1, t0\n") }
    CcLe => { sr_put(sb, slt); sr_put(sb, " t2, t1, t0\n  xori t2, t2, 1\n") }
    CcGe => { sr_put(sb, slt); sr_put(sb, " t2, t0, t1\n  xori t2, t2, 1\n") }
    CcEq | CcNe | CcNone => { return false }
  }
  sr_st2(sb, ip)
}
## The declaration a symbol operand names.
sr_sym_decl := fn(x : SrX, ip : ptr(mut ir::IrInst)) -> Option(Decl) {
  match ir::i_ak(ip) {
    OkSym => {
      di := ir::sym_decl(x.p, ir::SymId(usize(ir::i_av(ip))))
      d : Decl = deref(lower_ctx::decl_get(x.decls, di))
      Option(Decl).Some(d)
    }
    OkNone | OkVReg | OkImm | OkFrame | OkFn | OkLabel => { Option(Decl).None }
  }
}
## `addr @g` of a module scalar: `la` of the `.quad` cell `emit_rv_program` gives it (its bare name).
sr_addr := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  gdo : Option(Decl) = sr_sym_decl(x, ip)
  match gdo {
    Some(g) => {
      has_cell := lower_layout::global_has_scalar_cell(g)
      if not has_cell { return false }
      gname := str_at((x.src + g.name_start), g.name_len)
      sr_put(sb, "  la t2, ")
      sr_put(sb, gname)
      sr_put(sb, "\n")
      sr_st2(sb, ip)
    }
    None => { false }
  }
}
## `load T [a + off]`: the width from `T`, the extension from its spelled signedness.
## An ADDRESS operand into `reg`: a `ptr` vreg's value, or a frame object's address `s0 + off`.
sr_base := fn(in out sb : rt::StrBuf, x : SrX, reg : str, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sr_ldv(sb, reg, usize(v)); true }
    OkFrame => {
      sr_put(sb, "  li "); sr_put(sb, reg); sr_put(sb, ", "); sr_int(sb, i64(ir::wb_get(x.fobj, usize(v))))
      sr_put(sb, "\n  add "); sr_put(sb, reg); sr_put(sb, ", s0, "); sr_put(sb, reg); sr_put(sb, "\n")
      true
    }
    OkNone | OkImm | OkSym | OkFn | OkLabel => { false }
  }
}
## The displacement of an access whose base is in t0: the offset folded into t0 first when the 12-bit
## signed displacement cannot encode it.
sr_mem_off := fn(in out sb : rt::StrBuf, off : i64) -> i64 {
  if off >= 0 and off <= SR_DISP_MAX { return off }
  sr_put(sb, "  li t6, "); sr_int(sb, off); sr_put(sb, "\n  add t0, t0, t6\n")
  0
}
## `store T [a + off], v`: the value's low `T`-width bytes.
sr_store := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  if not sr_base(sb, x, "t0", ir::i_ak(ip), ir::i_av(ip)) { return false }
  if not sr_ldb(sb, "t1", ip) { return false }
  ty : ir::Kty = ir::i_ty(ip)
  mut mn : str = ""
  match ty {
    KI8 | KBool => { mn = "  sb" }
    KI16 => { mn = "  sh" }
    KI32 => { mn = "  sw" }
    KI64 | KPtr => { mn = "  sd" }
    KF32 | KF64 | KNone => { return false }
  }
  off := sr_mem_off(sb, ir::i_off(ip))
  sr_put(sb, mn)
  sr_put(sb, " t1, ")
  sr_int(sb, off)
  sr_put(sb, "(t0)\n")
  true
}
## `addr $k`: the frame object's address.
sr_addr_frame := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  if not sr_base(sb, x, "t2", ir::i_ak(ip), ir::i_av(ip)) { return false }
  sr_st2(sb, ip)
}
## `copy dst, src, n` (t0 ← dst, t1 ← src) and `zero dst, n` (t0 ← dst): a counted loop over 8-byte
## words when `n` is a multiple of 8, over bytes otherwise. Nothing for `n == 0`.
sr_mem := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst), copy : bool) -> bool {
  n := ir::i_n(ip)
  if not sr_base(sb, x, "t0", ir::i_ak(ip), ir::i_av(ip)) { return false }
  if copy { if not sr_base(sb, x, "t1", ir::i_bk(ip), ir::i_bv(ip)) { return false } }
  if n == 0 { return true }
  words := n % 8 == 0
  mut cnt : usize = n
  mut step : str = "1"
  if words { cnt = n / 8; step = "8" }
  sr_put(sb, "  li t3, "); sr_u(sb, cnt); sr_put(sb, "\n1:\n")
  if copy {
    if words { sr_put(sb, "  ld t2, 0(t1)\n  sd t2, 0(t0)\n") } else { sr_put(sb, "  lbu t2, 0(t1)\n  sb t2, 0(t0)\n") }
    sr_put(sb, "  addi t1, t1, "); sr_put(sb, step); sr_put(sb, "\n")
  } else {
    if words { sr_put(sb, "  sd zero, 0(t0)\n") } else { sr_put(sb, "  sb zero, 0(t0)\n") }
  }
  sr_put(sb, "  addi t0, t0, "); sr_put(sb, step); sr_put(sb, "\n  addi t3, t3, -1\n  bnez t3, 1b\n")
  true
}
sr_load := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  if not sr_base(sb, x, "t0", ir::i_ak(ip), ir::i_av(ip)) { return false }
  ty : ir::Kty = ir::i_ty(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  mut mn : str = ""
  match ty {
    KI8 => { match sg { SgS => { mn = "  lb" }; SgU => { mn = "  lbu" }; SgNone => { return false } } }
    KI16 => { match sg { SgS => { mn = "  lh" }; SgU => { mn = "  lhu" }; SgNone => { return false } } }
    KI32 => { match sg { SgS => { mn = "  lw" }; SgU => { mn = "  lwu" }; SgNone => { return false } } }
    KI64 | KPtr => { mn = "  ld" }
    KBool => { mn = "  lbu" }
    KF32 | KF64 | KNone => { return false }
  }
  off := sr_mem_off(sb, ir::i_off(ip))
  sr_put(sb, mn)
  sr_put(sb, " t2, ")
  sr_int(sb, off)
  sr_put(sb, "(t0)\n")
  sr_st2(sb, ip)
}
## The argument run of call or syscall `ip` into a0, a1, … (the one register mapping both share).
sr_args := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) {
  n := ir::i_n(ip)
  mut j : usize = 0
  while j < n {
    av := ir::pool_get(x.f, ir::i_pool(ip) + j)
    sr_ldv(sb, "t0", av)
    sr_put(sb, "  mv a")
    sr_u(sb, j)
    sr_put(sb, ", t0\n")
    j = j + 1
  }
}
## A direct call: the arguments in a0..a7, `call` the callee's legacy label, the result from a0,
## re-canonicalized from the destination's type.
sr_call := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  n := ir::i_n(ip)
  if n > 8 { return false }
  cdo : Option(Decl) = sr_sym_decl(x, ip)
  match cdo {
    Some(cd) => {
      if not cd.is_fn or cd.name_len == 0 { return false }
      sr_args(sb, x, ip)
      sr_put(sb, "  call ")
      sr_put_label(sb, x.src, cd)
      sr_put(sb, "\n")
      dv : Option(usize) = sr_dst(ip)
      mut ok := true
      match dv {
        Some(d) => {
          sr_stv(sb, "a0", d)
          ok = sr_canon_slot(sb, x, d)
        }
        None => {}
      }
      ok
    }
    None => { false }
  }
}
## `%r = syscall %nr(args…)` (ABI §5): the Linux RISC-V system-call convention — the number in a7, up to
## six arguments in a0..a5, `ecall`, the result in a0 (re-canonicalized from the destination's type).
sr_syscall := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst)) -> bool {
  n := ir::i_n(ip)
  if n > 6 { return false }
  if not sr_lda(sb, "a7", ip) { return false }
  sr_args(sb, x, ip)
  sr_put(sb, "  ecall\n")
  dv : Option(usize) = sr_dst(ip)
  match dv {
    Some(d) => {
      sr_stv(sb, "a0", d)
      sr_canon_slot(sb, x, d)
    }
    None => { true }
  }
}

## ── regions ──

sr_push := fn(x : SrX, in out a : rt::Arena, k : usize) { q := ir::wb_push(x.stk, a, k) }
sr_top := fn(x : SrX) -> Option(usize) {
  n := ir::wb_len(x.stk)
  if n == 0 { return Option(usize).None }
  Option(usize).Some(ir::wb_get(x.stk, n - 1))
}
## The open `block`/`loop` whose IR label is `l`, by its opener index.
sr_find := fn(x : SrX, l : usize) -> Option(usize) {
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
## `br L` / `br_if c L`, to the region label the opener names (a `block`'s end, a `loop`'s head).
sr_br := fn(in out sb : rt::StrBuf, x : SrX, ip : ptr(mut ir::IrInst), cond : bool) -> bool {
  to : Option(usize) = sr_find(x, ir::i_lbl(ip))
  match to {
    Some(k) => {
      if cond {
        if not sr_lda(sb, "t0", ip) { return false }
        sr_put(sb, "  beqz t0, 1f\n")
      }
      sr_put(sb, "  j ")
      sr_lbl(sb, x, k)
      sr_put(sb, "\n")
      if cond { sr_put(sb, "1:\n") }
      true
    }
    None => { false }
  }
}
## `end`: see `aarch64::isel`'s `sa_end`.
sr_end := fn(in out sb : rt::StrBuf, x : SrX) -> bool {
  to : Option(usize) = sr_top(x)
  match to {
    Some(k) => {
      kp := ir::fn_inst(x.f, k)
      o : ir::Op = ir::i_op(kp)
      match o {
        OpBlock | OpIf | OpElse => { sr_def_lbl(sb, x, k) }
        OpLoop | OpUnch | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
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

## One instruction. Answers false when the selector does not select it (the function then falls back).
sr_inst := fn(in out sb : rt::StrBuf, x : SrX, in out a : rt::Arena, i : usize) -> bool {
  ip := ir::fn_inst(x.f, i)
  o : ir::Op = ir::i_op(ip)
  match o {
    OpConst | OpMov => { sr_const(sb, ip) }
    OpAdd | OpSub | OpMul => { sr_arith(sb, x, ip, o) }
    OpDiv | OpRem => { sr_div(sb, x, ip, o) }
    OpAnd => { sr_bits(sb, ip, "  and") }
    OpOr => { sr_bits(sb, ip, "  or") }
    OpXor => { sr_bits(sb, ip, "  xor") }
    OpShl | OpShr => { sr_shift(sb, x, ip, o) }
    OpRotl | OpRotr => { sr_rot(sb, ip, o) }
    OpExt => { sr_ext(sb, x, ip) }
    OpFit => { sr_fit(sb, x, ip) }
    OpCmp => { sr_cmp(sb, ip) }
    OpAddrSym => { sr_addr(sb, x, ip) }
    OpLoad => { sr_load(sb, x, ip) }
    OpStore => { sr_store(sb, x, ip) }
    OpAddrFrame => { sr_addr_frame(sb, x, ip) }
    OpCopy => { sr_mem(sb, x, ip, true) }
    OpZero => { sr_mem(sb, x, ip, false) }
    OpCall => { sr_call(sb, x, ip) }
    OpSyscall => { sr_syscall(sb, x, ip) }
    OpBlock | OpUnch => { sr_push(x, a, i); true }
    OpLoop => { sr_push(x, a, i); sr_def_lbl(sb, x, i); true }
    OpIf => {
      if not sr_lda(sb, "t0", ip) { return false }
      sr_put(sb, "  bnez t0, 1f\n  j ")
      sr_lbl(sb, x, i)
      sr_put(sb, "\n1:\n")
      sr_push(x, a, i)
      true
    }
    OpElse => {
      to : Option(usize) = sr_top(x)
      match to {
        Some(k) => {
          sr_put(sb, "  j ")
          sr_lbl(sb, x, i)
          sr_put(sb, "\n")
          sr_def_lbl(sb, x, k)
          ir::wb_set_top(x.stk, i)
        }
        None => { false }
      }
    }
    OpEnd => { sr_end(sb, x) }
    OpBr => { sr_br(sb, x, ip, false) }
    OpBrIf => { sr_br(sb, x, ip, true) }
    OpRet => {
      match ir::i_ak(ip) {
        OkVReg => { sr_ldv(sb, "a0", usize(ir::i_av(ip))) }
        OkNone => {}
        OkImm | OkFrame | OkSym | OkFn | OkLabel => { return false }
      }
      sr_put(sb, "  j ")
      sr_ret_lbl(sb, x)
      sr_put(sb, "\n")
      true
    }
    OpTrap => { sr_trap(sb, x, ir::i_tk(ip), ip); true }
    OpTrapIf => {
      if not sr_lda(sb, "t0", ip) { return false }
      sr_put(sb, "  beqz t0, 1f\n")
      sr_trap(sb, x, ir::i_tk(ip), ip)
      sr_put(sb, "1:\n")
      true
    }
    OpFConst | OpFnAddr | OpNot | OpNeg | OpTrunc | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpBSwap | OpGep | OpBound | OpCallInd
      | OpCallC | OpSwitch => { false }
  }
}

## `sp ± frame`, by an immediate when it fits the 12-bit field, else through t6.
sr_sp_adjust := fn(in out sb : rt::StrBuf, frame : i64, down : bool) {
  if frame <= SR_DISP_MAX {
    sr_put(sb, "  addi sp, sp, ")
    if down { sr_put(sb, "-") }
    sr_int(sb, frame)
    sr_put(sb, "\n")
    return
  }
  sr_put(sb, "  li t6, ")
  sr_int(sb, frame)
  if down { sr_put(sb, "\n  sub sp, sp, t6\n") } else { sr_put(sb, "\n  add sp, sp, t6\n") }
}

## The label of function declaration `d`: the bare name the legacy `emit_rv_fn` defines, or for a
## bodyless `@abi(syscall)` trampoline its module-qualified symbol (`ir::put_fn_symbol`), because the
## same call is declared in more than one module (`docs/ir-slice-2.md`).
sr_put_label := fn(in out sb : rt::StrBuf, src : ptr(u8), d : Decl) {
  if d.kind == lower_layout::DECL_KIND_SYSCALL { ir::put_fn_symbol(sb, src, d); return }
  nm := str_at((src + d.name_start), d.name_len)
  sr_put(sb, nm)
}
## Select function `f` (declaration `d`) into `sb`. Answers false when the function is refused.
sr_fn := fn(in out sb : rt::StrBuf, x : SrX, d : Decl, in out a : rt::Arena) -> bool {
  nv := ir::fn_nvregs(x.f)
  np := ir::fn_nparams(x.f)
  if np > 8 { return false }
  ## The vreg slots, then the frame objects (`x.fobj`'s last word is their end), rounded to 16.
  mut frame : i64 = i64(ir::wb_get(x.fobj, ir::wb_len(x.fobj) - 1))
  if frame % 16 != 0 { frame = frame + (16 - frame % 16) }
  sr_put(sb, "# ir: selected from the shared IR\n")
  emit_rv_export(sb, x.src, d.name_start, d.name_len)
  sr_put_label(sb, x.src, d)
  sr_put(sb, ":\n")
  sr_sp_adjust(sb, frame, true)
  sr_put(sb, "  sd ra, 8(sp)\n  sd s0, 0(sp)\n  mv s0, sp\n")
  mut pi : usize = 0
  while pi < np {
    sr_put(sb, "  mv t0, a")
    sr_u(sb, pi)
    sr_put(sb, "\n")
    sr_stv(sb, "t0", pi)
    pi = pi + 1
  }
  pi = 0
  while pi < np {
    if not sr_canon_slot(sb, x, pi) { return false }
    pi = pi + 1
  }
  ni := ir::fn_ninst(x.f)
  mut i : usize = 0
  while i < ni {
    if not sr_inst(sb, x, a, i) { return false }
    i = i + 1
  }
  if ir::wb_len(x.stk) != 0 { return false }
  sr_ret_lbl(sb, x)
  sr_put(sb, ":\n  mv sp, s0\n  ld ra, 8(sp)\n  ld s0, 0(sp)\n")
  sr_sp_adjust(sb, frame, false)
  sr_put(sb, "  ret\n")
  true
}

## The hook in `emit_rv_program`'s declaration loop (see `aarch64::isel`'s `a64_isel_try`).
pub rv_isel_try := fn(decls : ptr(rt::Vec), di : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) -> bool {
  mut ia := a
  p := ir::prog_new(ia)
  si : ir::SelIn = ir::select_input(p, decls, src, di, ia)
  match si {
    SiBuilt(f) => {
      d : Decl = deref(lower_ctx::decl_get(decls, di))
      fo := ir::frame_place(f, ia, 16 + ir::fn_nvregs(f) * 8)
      x := SrX(f = f, p = p, src = src, decls = decls, fid = SR_FN, fspan = d.name_start, stk = ir::wb_new(ia, 16), fobj = fo)
      mark := sb.len
      if sr_fn(sb, x, d, ia) {
        SR_FN = SR_FN + 1
        return true
      }
      sb.len = mark
      false
    }
    SiLegacy => { false }
  }
}
