## selfhost::lower::isel — the x86_64 instruction selector over the shared IR (`docs/ir.md` §6,
## `docs/ir-slice-1.md` §4, slice 1d). DEV ONLY: it is reached through the `alatyr x86-ir` verb alone
## (owner decision D5, Codegen §3.1), never by the default x86 emission, which is unchanged until the
## flip (`docs/ir.md` §7.4, slice 9).
##
## A function the IR builder BUILT and the verifier accepted is emitted from its IR here instead of by
## `emit_fn`; every other function keeps its legacy emission (owner decision D7). The selector is
## target text only: it never reads the AST. Every width and signedness decision it makes is read from
## the IR value's attributes (§3.8) — the instruction's `ty`/`sg` (a width op's `sg` is its source's)
## and the destination vreg's recorded type — never re-derived.
##
## Frame slots first (§6): vreg `k` lives in the 8-byte slot `-8(k+1)(%rbp)`. Each instruction loads
## its operands into %rax and %rcx, computes into %rax (%rdx a temporary) and stores the full
## 64-bit result: canonical form is the builder's job (V3), and `ext`/`fit` are the only width
## instructions this file emits for an operation. Only caller-saved registers are touched, so a legacy
## caller's %rbx/%r12..%r15 survive. A trap is `ud2` — the legacy emitter's trap, so the exit status
## agrees — with `# trap <kind> <file>:<line>:<col>`.
##
## The convention is the legacy x86 one for the scalar class (`docs/ir-slice-1.md` §3): arguments in
## %rdi, %rsi, %rdx, %rcx, %r8, %r9, the result in %rax, the legacy mangled label (`emit_mangled_def`),
## so an IR-built and a legacy-emitted function call each other. Both ends of a call re-canonicalize a
## narrow value from its IR type (a parameter at entry, a result after the `call`), because a legacy
## peer does not promise it.
##
## Frame objects (slice 3a, `docs/ir.md` §3.3) sit below the vreg slots, each at its alignment; an
## address operand `$k` is `leaq <its offset>(%rbp)`. `load`/`store` take the width from the IR type,
## `copy`/`zero` are `rep movsb`/`rep stosb` (%rdi, %rsi, %rcx are caller-saved).
##
## A selector may REFUSE a function (an op it does not select, more than 6 parameters or arguments —
## the legacy stack-argument layout is not modelled —, a declaration whose label the legacy emitter
## spells specially); the caller then rewinds the output and emits the function the legacy way.
##
## The file shares its stem with the three twins' selectors (#871: same-stem child modules share one
## namespace), so every name here carries the `sx_`/`Sx`/`x86_` prefix, as theirs carry their own.
(Decl) := ast

## What one function is selected against: the IR, the program its symbols index, the source, the
## declaration list, a per-program function number for local labels, the function's own name span
## (the location of a trap that carries none), the region stack (opener instruction indices), and the
## frame objects: their placement (`ir::frame_place` from 0: one offset per object, then the end) and
## `ftop`, the bytes the frame reserves below %rbp (the vreg slots and then the objects, each rounded
## to 16) — object `k` lives at `-ftop + off_k(%rbp)`.
SxX := struct { f : ptr(mut ir::IrFn), p : ir::IrProg, src : ptr(u8), decls : ptr(rt::Vec), fid : usize, fspan : usize, stk : ptr(mut ir::WBuf), fobj : ptr(mut ir::WBuf), ftop : i64 }

## The number of the next function this selector emits, for its `.Lxir<n>_<k>` labels.
mut SX_FN : usize = 0

sx_put := fn(in out sb : rt::StrBuf, s : str) { k := rt::push_str(sb, s) }
sx_int := fn(in out sb : rt::StrBuf, n : i64) { k := rt::push_int(sb, n) }
sx_u := fn(in out sb : rt::StrBuf, n : usize) { k := rt::push_int(sb, i64(n)) }

## The registers this selector names, and their spellings at each width it reads or writes. Only
## caller-saved registers: the scratch pair, %rdx (`idivq`/`mulq`), and the argument registers.
SxR := enum { XrAx, XrCx, XrDx, XrDi, XrSi, XrR8, XrR9 }
sx_rq := fn(r : SxR) -> str {
  match r { XrAx => { "%rax" }; XrCx => { "%rcx" }; XrDx => { "%rdx" }; XrDi => { "%rdi" }; XrSi => { "%rsi" }; XrR8 => { "%r8" }; XrR9 => { "%r9" } }
}
sx_rd := fn(r : SxR) -> str {
  match r { XrAx => { "%eax" }; XrCx => { "%ecx" }; XrDx => { "%edx" }; XrDi => { "%edi" }; XrSi => { "%esi" }; XrR8 => { "%r8d" }; XrR9 => { "%r9d" } }
}
sx_rw := fn(r : SxR) -> str {
  match r { XrAx => { "%ax" }; XrCx => { "%cx" }; XrDx => { "%dx" }; XrDi => { "%di" }; XrSi => { "%si" }; XrR8 => { "%r8w" }; XrR9 => { "%r9w" } }
}
sx_rb := fn(r : SxR) -> str {
  match r { XrAx => { "%al" }; XrCx => { "%cl" }; XrDx => { "%dl" }; XrDi => { "%dil" }; XrSi => { "%sil" }; XrR8 => { "%r8b" }; XrR9 => { "%r9b" } }
}
## The integer argument registers of the legacy convention, by position (six; a seventh argument
## travels on the stack, which this selector does not model).
sx_argreg := fn(i : usize) -> Option(SxR) {
  if i == 0 { return Option(SxR).Some(SxR.XrDi) }
  if i == 1 { return Option(SxR).Some(SxR.XrSi) }
  if i == 2 { return Option(SxR).Some(SxR.XrDx) }
  if i == 3 { return Option(SxR).Some(SxR.XrCx) }
  if i == 4 { return Option(SxR).Some(SxR.XrR8) }
  if i == 5 { return Option(SxR).Some(SxR.XrR9) }
  Option(SxR).None
}
SX_MAX_ARGS : usize = 6

## A frame slot of the selected function: slot `k` holds IR vreg `k` (frame slots first, §6).
SxSlot := brand(usize)
## The slot of the vreg an operand or a pool entry names.
sx_slot := fn(v : usize) -> SxSlot { SxSlot(v) }
## The frame byte offset of slot `v` (negative, below %rbp).
sx_off := fn(v : SxSlot) -> i64 { 0 - (i64(usize(v)) + 1) * 8 }
## `  movq -off(%rbp), <reg>` / `  movq <reg>, -off(%rbp)`.
sx_ldv := fn(in out sb : rt::StrBuf, r : SxR, v : SxSlot) {
  sx_put(sb, "  movq "); sx_int(sb, sx_off(v)); sx_put(sb, "(%rbp), "); sx_put(sb, sx_rq(r)); sx_put(sb, "\n")
}
sx_stv := fn(in out sb : rt::StrBuf, r : SxR, v : SxSlot) {
  sx_put(sb, "  movq "); sx_put(sb, sx_rq(r)); sx_put(sb, ", "); sx_int(sb, sx_off(v)); sx_put(sb, "(%rbp)\n")
}
## Whether `v` is encodable as a sign-extended 32-bit immediate.
sx_imm32 := fn(v : i64) -> bool { v >= 0 - 2147483648 and v <= 2147483647 }
## Load an operand (a vreg or an immediate) into `reg`. Any other operand kind is not a value here.
sx_ld := fn(in out sb : rt::StrBuf, r : SxR, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sx_ldv(sb, r, sx_slot(usize(v))); true }
    OkImm => {
      if sx_imm32(v) { sx_put(sb, "  movq $") } else { sx_put(sb, "  movabsq $") }
      sx_int(sb, v); sx_put(sb, ", "); sx_put(sb, sx_rq(r)); sx_put(sb, "\n")
      true
    }
    OkNone | OkFrame | OkSym | OkFn | OkLabel => { false }
  }
}
sx_lda := fn(in out sb : rt::StrBuf, r : SxR, ip : ptr(mut ir::IrInst)) -> bool { sx_ld(sb, r, ir::i_ak(ip), ir::i_av(ip)) }
sx_ldb := fn(in out sb : rt::StrBuf, r : SxR, ip : ptr(mut ir::IrInst)) -> bool { sx_ld(sb, r, ir::i_bk(ip), ir::i_bv(ip)) }
## Both operands: `a` into %rax, `b` into %rcx.
sx_ld2 := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool { sx_lda(sb, SxR.XrAx, ip) and sx_ldb(sb, SxR.XrCx, ip) }
## The destination vreg of `ip`, if it defines one.
sx_dst := fn(ip : ptr(mut ir::IrInst)) -> Option(SxSlot) {
  match ir::i_dk(ip) {
    OkVReg => { Option(SxSlot).Some(sx_slot(usize(ir::i_dv(ip)))) }
    OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { Option(SxSlot).None }
  }
}
## Store %rax into `ip`'s destination.
sx_strax := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(SxSlot) = sx_dst(ip)
  match dv { Some(d) => { sx_stv(sb, SxR.XrAx, d); true }; None => { false } }
}

## The index of a region-opening instruction (`block`, `loop`, `if`, `else`, `unchecked`) within its
## function: the identity of the region, and of the one label it owns.
SxAt := brand(usize)
## `.Lxir<fn>_<k>` — the one label family of a selected function. A region opener at instruction `k`
## names its label by `k`: a `block`'s end, a `loop`'s head, an `if`'s false arm, an `else`'s join.
sx_lbl := fn(in out sb : rt::StrBuf, x : SxX, k : SxAt) { sx_put(sb, ".Lxir"); sx_u(sb, x.fid); sx_put(sb, "_"); sx_u(sb, usize(k)) }
sx_def_lbl := fn(in out sb : rt::StrBuf, x : SxX, k : SxAt) { sx_lbl(sb, x, k); sx_put(sb, ":\n") }
sx_ret_lbl := fn(in out sb : rt::StrBuf, x : SxX) { sx_put(sb, ".Lxir"); sx_u(sb, x.fid); sx_put(sb, "_ret") }

## `  ud2 # trap <kind> <file>:<line>:<col>` (§3.6).
sx_trap := fn(in out sb : rt::StrBuf, x : SxX, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  tn := ir::trap_name(tk)
  sx_put(sb, "  ud2 # trap ")
  sx_put(sb, tn)
  sx_put(sb, " ")
  ir::put_inst_loc(sb, x.src, ip, x.fspan)
  sx_put(sb, "\n")
}
## `  <jcc> 1f`, the trap, `1:` — a trap taken when the condition `jcc` names is FALSE.
sx_trap_unless := fn(in out sb : rt::StrBuf, x : SxX, jcc : str, tk : ir::TrapKind, ip : ptr(mut ir::IrInst)) {
  sx_put(sb, "  "); sx_put(sb, jcc); sx_put(sb, " 1f\n")
  sx_trap(sb, x, tk, ip)
  sx_put(sb, "1:\n")
}

## `r ← canonical(r)` at type `ty` with signedness `sg` (§3.2): a narrow integer is sign- or
## zero-extended from its width; a 64-bit value, a `bool` and a pointer are already their word.
sx_canon := fn(in out sb : rt::StrBuf, r : SxR, ty : ir::Kty, sg : ir::Sgn) -> bool {
  q := sx_rq(r)
  dw := sx_rd(r)
  w := sx_rw(r)
  b := sx_rb(r)
  match ty {
    KI8 => { sx_narrow(sb, sg, "  movsbq ", b, q, "  movzbl ", b, dw) }
    KI16 => { sx_narrow(sb, sg, "  movswq ", w, q, "  movzwl ", w, dw) }
    KI32 => { sx_narrow(sb, sg, "  movslq ", dw, q, "  movl ", dw, dw) }
    KI64 | KBool | KPtr => { true }
    KF32 | KF64 | KNone => { false }
  }
}
## A narrow extension: `<sext> src, dst` for a signed type, `<zext> src, dst` (a 32-bit write clears
## the upper word) for an unsigned one. A narrow integer always carries a signedness.
sx_narrow := fn(in out sb : rt::StrBuf, sg : ir::Sgn, sext : str, ss : str, sd : str, zext : str, zs : str, zd : str) -> bool {
  match sg {
    SgS => { sx_put(sb, sext); sx_put(sb, ss); sx_put(sb, ", "); sx_put(sb, sd); sx_put(sb, "\n"); true }
    SgU => { sx_put(sb, zext); sx_put(sb, zs); sx_put(sb, ", "); sx_put(sb, zd); sx_put(sb, "\n"); true }
    SgNone => { false }
  }
}
## Canonicalize slot `v` in place, from its recorded type (a parameter at entry, a call's result).
sx_canon_slot := fn(in out sb : rt::StrBuf, x : SxX, v : SxSlot) -> bool {
  ty : ir::Kty = ir::vreg_ty(x.f, usize(v))
  sg : ir::Sgn = ir::vreg_sg(x.f, usize(v))
  if not ir::kty_is_narrow(ty) { return true }
  sx_ldv(sb, SxR.XrAx, v)
  if not sx_canon(sb, SxR.XrAx, ty, sg) { return false }
  sx_stv(sb, SxR.XrAx, v)
  true
}

## The `setcc` suffix of an integer comparison predicate, read at the op's spelled signedness. An
## unsigned ordering uses the carry conditions, so `0 < u64::MAX` reads true. Equality spells no
## signedness and reads the words either way; an ordering without one is not selected here.
sx_cc_code := fn(c : ir::Cc, sg : ir::Sgn) -> Option(str) {
  match c {
    CcEq => { Option(str).Some("e") }
    CcNe => { Option(str).Some("ne") }
    CcLt => { match sg { SgS => { Option(str).Some("l") }; SgU => { Option(str).Some("b") }; SgNone => { Option(str).None } } }
    CcLe => { match sg { SgS => { Option(str).Some("le") }; SgU => { Option(str).Some("be") }; SgNone => { Option(str).None } } }
    CcGt => { match sg { SgS => { Option(str).Some("g") }; SgU => { Option(str).Some("a") }; SgNone => { Option(str).None } } }
    CcGe => { match sg { SgS => { Option(str).Some("ge") }; SgU => { Option(str).Some("ae") }; SgNone => { Option(str).None } } }
    CcNone => { Option(str).None }
  }
}

## ── the operations ──

## The three ring operations, the two division results, the two shifts, the two rotations.
SxArith := enum { XaAdd, XaSub, XaMul }
SxDivK := enum { XdQuot, XdRem }
SxShift := enum { XsShl, XsShr }
SxRot := enum { XrRotl, XrRotr }

## `const` / `mov`: the operand's word into the destination.
sx_move := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  if not sx_lda(sb, SxR.XrAx, ip) { return false }
  sx_strax(sb, ip)
}
## `+ - *` at 64 bits. `chk` traps `overflow` on the operation's own signedness: a signed overflow sets
## OF, an unsigned `add`/`sub` sets CF; an unsigned product overflows when its high word (`mulq`'s
## %rdx, which sets CF and OF) is not zero.
sx_arith := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst), o : SxArith) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sx_ld2(sb, ip) { return false }
  if not ir::mode_is_chk(ir::i_md(ip)) {
    match o {
      XaAdd => { sx_put(sb, "  addq %rcx, %rax\n") }
      XaSub => { sx_put(sb, "  subq %rcx, %rax\n") }
      XaMul => { sx_put(sb, "  imulq %rcx, %rax\n") }
    }
    return sx_strax(sb, ip)
  }
  sg : ir::Sgn = ir::i_sg(ip)
  match sg {
    SgS => {
      match o {
        XaAdd => { sx_put(sb, "  addq %rcx, %rax\n") }
        XaSub => { sx_put(sb, "  subq %rcx, %rax\n") }
        XaMul => { sx_put(sb, "  imulq %rcx, %rax\n") }
      }
      sx_trap_unless(sb, x, "jno", ir::TrapKind.TkOverflow, ip)
    }
    SgU => {
      match o {
        XaAdd => { sx_put(sb, "  addq %rcx, %rax\n") }
        XaSub => { sx_put(sb, "  subq %rcx, %rax\n") }
        XaMul => { sx_put(sb, "  mulq %rcx\n") }
      }
      sx_trap_unless(sb, x, "jnc", ir::TrapKind.TkOverflow, ip)
    }
    SgNone => { return false }
  }
  sx_strax(sb, ip)
}
## `/ %` at 64 bits. `chk` traps `div_zero` on a zero divisor and, signed, `div_overflow` on
## `MIN / -1` (§4); the builder states both checks before the op as well, and the op keeps its own
## meaning regardless. Any other mode is the hardware division (`hw`, owner decision D1: x86's
## `idivq`/`divq` fault — SIGFPE — on a zero divisor and on `MIN / -1`, as the legacy emitter's do).
sx_div := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst), o : SxDivK) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sx_ld2(sb, ip) { return false }
  sg : ir::Sgn = ir::i_sg(ip)
  mut signed := false
  match sg { SgS => { signed = true }; SgU => {}; SgNone => { return false } }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sx_put(sb, "  testq %rcx, %rcx\n")
    sx_trap_unless(sb, x, "jnz", ir::TrapKind.TkDivZero, ip)
    if signed {
      sx_put(sb, "  cmpq $-1, %rcx\n  jne 1f\n  movabsq $-9223372036854775808, %rdx\n  cmpq %rdx, %rax\n")
      sx_trap_unless(sb, x, "jne", ir::TrapKind.TkDivOverflow, ip)
    }
  }
  if signed { sx_put(sb, "  cqto\n  idivq %rcx\n") } else { sx_put(sb, "  xorl %edx, %edx\n  divq %rcx\n") }
  match o {
    XdQuot => {}
    XdRem => { sx_put(sb, "  movq %rdx, %rax\n") }
  }
  sx_strax(sb, ip)
}
## `& | ^` on canonical operands, at any integer width or `bool` (canonical-preserving, V3).
sx_bits := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), mn : str) -> bool {
  if not sx_ld2(sb, ip) { return false }
  sx_put(sb, mn)
  sx_put(sb, " %rcx, %rax\n")
  sx_strax(sb, ip)
}
## `shl`/`shr` at 64 bits. `chk` traps `shift_range` on a count ≥ 64; otherwise (`hw`, or a `wrap` the
## builder proved in range) the register shift. `shr` is arithmetic on a signed value, logical on an
## unsigned one — the op's spelled signedness.
sx_shift := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst), o : SxShift) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sx_ld2(sb, ip) { return false }
  if ir::mode_is_chk(ir::i_md(ip)) {
    sx_put(sb, "  cmpq $64, %rcx\n")
    sx_trap_unless(sb, x, "jb", ir::TrapKind.TkShiftRange, ip)
  }
  match o {
    XsShl => { sx_put(sb, "  shlq %cl, %rax\n") }
    XsShr => {
      sg : ir::Sgn = ir::i_sg(ip)
      match sg {
        SgS => { sx_put(sb, "  sarq %cl, %rax\n") }
        SgU => { sx_put(sb, "  shrq %cl, %rax\n") }
        SgNone => { return false }
      }
    }
  }
  sx_strax(sb, ip)
}
## `rotl`/`rotr` at 64 bits (the builder spells a narrow rotation with shifts); the count is taken
## mod 64 by the instruction.
sx_rot := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst), o : SxRot) -> bool {
  if not ir::kty_eq(ir::i_ty(ip), ir::Kty.KI64) { return false }
  if not sx_ld2(sb, ip) { return false }
  match o {
    XrRotl => { sx_put(sb, "  rolq %cl, %rax\n") }
    XrRotr => { sx_put(sb, "  rorq %cl, %rax\n") }
  }
  sx_strax(sb, ip)
}
## `ext T <- F`: wrap or widen to the DESTINATION's type and signedness (§3.4). The source is
## canonical, so its word is its value; the destination's recorded type decides the extension.
sx_ext := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(SxSlot) = sx_dst(ip)
  match dv {
    Some(d) => {
      if not sx_lda(sb, SxR.XrAx, ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, usize(d))
      if not ir::kty_is_int(ty) { return false }
      if not sx_canon(sb, SxR.XrAx, ty, sg) { return false }
      sx_stv(sb, SxR.XrAx, d)
      true
    }
    None => { false }
  }
}
## `fit T <- F`: the checked narrow. The value fits when its canonical form at the destination type is
## the same word AND, when the two signednesses differ, the source is not negative as read by its own
## (signed source) or does not exceed the signed range (unsigned source) — both are "bit 63 clear".
## Otherwise it traps with the op's kind (`narrow`, or `div_overflow` for a narrowed quotient).
sx_fit := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  dv : Option(SxSlot) = sx_dst(ip)
  match dv {
    Some(d) => {
      if not sx_lda(sb, SxR.XrAx, ip) { return false }
      ty : ir::Kty = ir::i_ty(ip)
      sg : ir::Sgn = ir::vreg_sg(x.f, usize(d))
      ## A width op spells its SOURCE's signedness (V4); the destination's is its vreg's.
      fsg : ir::Sgn = ir::i_sg(ip)
      if not ir::kty_is_int(ty) { return false }
      sx_put(sb, "  movq %rax, %rcx\n")
      if not sx_canon(sb, SxR.XrCx, ty, sg) { return false }
      sx_put(sb, "  cmpq %rax, %rcx\n  jne 2f\n")
      if not ir::sgn_eq(sg, fsg) { sx_put(sb, "  testq %rax, %rax\n  js 2f\n") }
      sx_put(sb, "  jmp 1f\n2:\n")
      sx_trap(sb, x, ir::i_tk(ip), ip)
      sx_put(sb, "1:\n")
      sx_stv(sb, SxR.XrCx, d)
      true
    }
    None => { false }
  }
}
## `cmp` → `bool`: the predicate's condition at the op's spelled signedness.
sx_cmp := fn(in out sb : rt::StrBuf, ip : ptr(mut ir::IrInst)) -> bool {
  co : Option(str) = sx_cc_code(ir::i_cc(ip), ir::i_sg(ip))
  match co {
    Some(c) => {
      if not sx_ld2(sb, ip) { return false }
      sx_put(sb, "  cmpq %rcx, %rax\n  set")
      sx_put(sb, c)
      sx_put(sb, " %al\n  movzbl %al, %eax\n")
      sx_strax(sb, ip)
    }
    None => { false }
  }
}
## The declaration a symbol operand names.
sx_sym_decl := fn(x : SxX, ip : ptr(mut ir::IrInst)) -> Option(Decl) {
  match ir::i_ak(ip) {
    OkSym => {
      di := ir::sym_decl(x.p, ir::SymId(usize(ir::i_av(ip))))
      d : Decl = deref(lower_ctx::decl_get(x.decls, di))
      Option(Decl).Some(d)
    }
    OkNone | OkVReg | OkImm | OkFrame | OkFn | OkLabel => { Option(Decl).None }
  }
}
## `addr @g` of a module scalar: the address of the `.data` cell `emit_program` gives it, under the
## legacy global naming (`emit_mangled_def`, as `emit_global_label` spells it). A symbol without such a
## cell — an immutable scalar the legacy emitter inlines — is refused.
sx_addr := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  gdo : Option(Decl) = sx_sym_decl(x, ip)
  match gdo {
    Some(g) => {
      if not lower_layout::global_has_scalar_cell(g) or not global_needs_storage(x.src, g) { return false }
      sx_put(sb, "  leaq ")
      emit_mangled_def(sb, x.src, g.mod_start, g.mod_len, g.name_start, g.name_len)
      sx_put(sb, "(%rip), %rax\n")
      sx_strax(sb, ip)
    }
    None => { false }
  }
}
## `load T [a + off]`: the width from `T`, the extension from its spelled signedness.
## An ADDRESS operand into `r`: a `ptr` vreg's value, or a frame object's address.
sx_base := fn(in out sb : rt::StrBuf, x : SxX, r : SxR, k : ir::OpndK, v : i64) -> bool {
  match k {
    OkVReg => { sx_ldv(sb, r, sx_slot(usize(v))); true }
    OkFrame => {
      sx_put(sb, "  leaq "); sx_int(sb, i64(ir::wb_get(x.fobj, usize(v))) - x.ftop); sx_put(sb, "(%rbp), "); sx_put(sb, sx_rq(r)); sx_put(sb, "\n")
      true
    }
    OkNone | OkImm | OkSym | OkFn | OkLabel => { false }
  }
}
## `store T [a + off], v`: the value's low `T`-width bytes (base in %rax, value in %rcx).
sx_store := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  off := ir::i_off(ip)
  if not sx_imm32(off) { return false }
  if not sx_base(sb, x, SxR.XrAx, ir::i_ak(ip), ir::i_av(ip)) { return false }
  if not sx_ldb(sb, SxR.XrCx, ip) { return false }
  ty : ir::Kty = ir::i_ty(ip)
  mut mn : str = ""
  match ty {
    KI8 | KBool => { mn = "  movb %cl, " }
    KI16 => { mn = "  movw %cx, " }
    KI32 => { mn = "  movl %ecx, " }
    KI64 | KPtr => { mn = "  movq %rcx, " }
    KF32 | KF64 | KNone => { return false }
  }
  sx_put(sb, mn)
  sx_int(sb, off)
  sx_put(sb, "(%rax)\n")
  true
}
## `addr $k`.
sx_addr_frame := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  if not sx_base(sb, x, SxR.XrAx, ir::i_ak(ip), ir::i_av(ip)) { return false }
  sx_strax(sb, ip)
}
## `copy dst, src, n` = `rep movsb`; `zero dst, n` = `rep stosb` of %al = 0.
sx_mem := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst), copy : bool) -> bool {
  if not sx_base(sb, x, SxR.XrDi, ir::i_ak(ip), ir::i_av(ip)) { return false }
  if copy { if not sx_base(sb, x, SxR.XrSi, ir::i_bk(ip), ir::i_bv(ip)) { return false } }
  sx_put(sb, "  movq $"); sx_u(sb, ir::i_n(ip)); sx_put(sb, ", %rcx\n")
  if copy { sx_put(sb, "  rep movsb\n") } else { sx_put(sb, "  xorl %eax, %eax\n  rep stosb\n") }
  true
}
sx_load := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  off := ir::i_off(ip)
  if not sx_imm32(off) { return false }
  if not sx_base(sb, x, SxR.XrAx, ir::i_ak(ip), ir::i_av(ip)) { return false }
  ty : ir::Kty = ir::i_ty(ip)
  sg : ir::Sgn = ir::i_sg(ip)
  mut mn : str = ""
  mut dst : str = "%rax"
  match ty {
    KI8 => { match sg { SgS => { mn = "  movsbq " }; SgU => { mn = "  movzbq " }; SgNone => { return false } } }
    KI16 => { match sg { SgS => { mn = "  movswq " }; SgU => { mn = "  movzwq " }; SgNone => { return false } } }
    KI32 => { match sg { SgS => { mn = "  movslq " }; SgU => { mn = "  movl "; dst = "%eax" }; SgNone => { return false } } }
    KI64 | KPtr => { mn = "  movq " }
    KBool => { mn = "  movzbq " }
    KF32 | KF64 | KNone => { return false }
  }
  sx_put(sb, mn)
  sx_int(sb, off)
  sx_put(sb, "(%rax), ")
  sx_put(sb, dst)
  sx_put(sb, "\n")
  sx_strax(sb, ip)
}
## A direct call: the arguments in the six argument registers, `call` the callee's legacy label, the
## result from %rax, re-canonicalized from the destination's type. A callee whose label the legacy
## emitter spells with a suffix or an alias is refused (`sx_plain_label`).
sx_call := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst)) -> bool {
  n := ir::i_n(ip)
  if n > SX_MAX_ARGS { return false }
  cdo : Option(Decl) = sx_sym_decl(x, ip)
  match cdo {
    Some(cd) => {
      if not sx_plain_label(x, cd) { return false }
      mut j : usize = 0
      while j < n {
        av := sx_slot(ir::pool_get(x.f, ir::i_pool(ip) + j))
        ro : Option(SxR) = sx_argreg(j)
        match ro { Some(r) => { sx_ldv(sb, r, av) }; None => { return false } }
        j = j + 1
      }
      sx_put(sb, "  call ")
      emit_mangled_def(sb, x.src, cd.mod_start, cd.mod_len, cd.name_start, cd.name_len)
      sx_put(sb, "\n")
      dv : Option(SxSlot) = sx_dst(ip)
      match dv {
        Some(d) => {
          sx_stv(sb, SxR.XrAx, d)
          return sx_canon_slot(sb, x, d)
        }
        None => {}
      }
      true
    }
    None => { false }
  }
}
## Whether `d`'s code is reached through its bare mangled label under the legacy internal convention
## (`x86_plain_label`, in the parent: its parts live in sibling modules this file cannot name).
sx_plain_label := fn(x : SxX, d : Decl) -> bool { x86_plain_label(x.decls, x.src, d) }

## ── regions ──

## The region an opener instruction opens, and what an `end` does for it.
SxRegion := enum { XgBlock, XgLoop, XgIf, XgElse, XgUnch }
## The region instruction `k` opens, if it opens one.
sx_region := fn(x : SxX, k : SxAt) -> Option(SxRegion) {
  o : ir::Op = ir::i_op(ir::fn_inst(x.f, usize(k)))
  match o {
    OpBlock => { Option(SxRegion).Some(SxRegion.XgBlock) }
    OpLoop => { Option(SxRegion).Some(SxRegion.XgLoop) }
    OpIf => { Option(SxRegion).Some(SxRegion.XgIf) }
    OpElse => { Option(SxRegion).Some(SxRegion.XgElse) }
    OpUnch => { Option(SxRegion).Some(SxRegion.XgUnch) }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem
      | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp
      | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits
      | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { Option(SxRegion).None }
  }
}
sx_stk_push := fn(x : SxX, in out a : rt::Arena, k : SxAt) { q := ir::wb_push(x.stk, a, usize(k)) }
## The innermost open region's opener.
sx_stk_top := fn(x : SxX) -> Option(SxAt) {
  n := ir::wb_len(x.stk)
  if n == 0 { return Option(SxAt).None }
  Option(SxAt).Some(SxAt(ir::wb_get(x.stk, n - 1)))
}
## The open `block`/`loop` whose IR label is `l`, by its opener index.
sx_stk_find := fn(x : SxX, l : usize) -> Option(SxAt) {
  mut n := ir::wb_len(x.stk)
  while n > 0 {
    k := SxAt(ir::wb_get(x.stk, n - 1))
    ro : Option(SxRegion) = sx_region(x, k)
    match ro {
      Some(r) => {
        match r {
          XgBlock | XgLoop => { if ir::i_lbl(ir::fn_inst(x.f, usize(k))) == l { return Option(SxAt).Some(k) } }
          XgIf | XgElse | XgUnch => {}
        }
      }
      None => {}
    }
    n = n - 1
  }
  Option(SxAt).None
}
## `br L` / `br_if c L`: a `block`'s label is its end, a `loop`'s its head — both named by the opener.
sx_br := fn(in out sb : rt::StrBuf, x : SxX, ip : ptr(mut ir::IrInst), cond : bool) -> bool {
  to : Option(SxAt) = sx_stk_find(x, ir::i_lbl(ip))
  match to {
    Some(k) => {
      if cond {
        if not sx_lda(sb, SxR.XrAx, ip) { return false }
        sx_put(sb, "  testq %rax, %rax\n  jnz ")
      } else {
        sx_put(sb, "  jmp ")
      }
      sx_lbl(sb, x, k)
      sx_put(sb, "\n")
      true
    }
    None => { false }
  }
}
## `end`: a `block` defines its end label, an `if` with no `else` its false arm, an `else` its join; a
## `loop` falls out (its head was defined at the opener) and `unchecked` emits nothing.
sx_end := fn(in out sb : rt::StrBuf, x : SxX) -> bool {
  to : Option(SxAt) = sx_stk_top(x)
  match to {
    Some(k) => {
      ro : Option(SxRegion) = sx_region(x, k)
      match ro {
        Some(r) => {
          match r {
            XgBlock | XgIf | XgElse => { sx_def_lbl(sb, x, k) }
            XgLoop | XgUnch => {}
          }
        }
        None => { return false }
      }
      ir::wb_pop(x.stk)
    }
    None => { false }
  }
}

## One instruction. Answers false when the selector does not select it (the function then falls back).
sx_inst := fn(in out sb : rt::StrBuf, x : SxX, in out a : rt::Arena, i : usize) -> bool {
  ip := ir::fn_inst(x.f, i)
  o : ir::Op = ir::i_op(ip)
  match o {
    OpConst | OpMov => { sx_move(sb, ip) }
    OpAdd => { sx_arith(sb, x, ip, SxArith.XaAdd) }
    OpSub => { sx_arith(sb, x, ip, SxArith.XaSub) }
    OpMul => { sx_arith(sb, x, ip, SxArith.XaMul) }
    OpDiv => { sx_div(sb, x, ip, SxDivK.XdQuot) }
    OpRem => { sx_div(sb, x, ip, SxDivK.XdRem) }
    OpAnd => { sx_bits(sb, ip, "  andq") }
    OpOr => { sx_bits(sb, ip, "  orq") }
    OpXor => { sx_bits(sb, ip, "  xorq") }
    OpShl => { sx_shift(sb, x, ip, SxShift.XsShl) }
    OpShr => { sx_shift(sb, x, ip, SxShift.XsShr) }
    OpRotl => { sx_rot(sb, ip, SxRot.XrRotl) }
    OpRotr => { sx_rot(sb, ip, SxRot.XrRotr) }
    OpExt => { sx_ext(sb, x, ip) }
    OpFit => { sx_fit(sb, x, ip) }
    OpCmp => { sx_cmp(sb, ip) }
    OpAddrSym => { sx_addr(sb, x, ip) }
    OpLoad => { sx_load(sb, x, ip) }
    OpStore => { sx_store(sb, x, ip) }
    OpAddrFrame => { sx_addr_frame(sb, x, ip) }
    OpCopy => { sx_mem(sb, x, ip, true) }
    OpZero => { sx_mem(sb, x, ip, false) }
    OpCall => { sx_call(sb, x, ip) }
    OpBlock | OpUnch => { sx_stk_push(x, a, SxAt(i)); true }
    OpLoop => { sx_stk_push(x, a, SxAt(i)); sx_def_lbl(sb, x, SxAt(i)); true }
    OpIf => {
      if not sx_lda(sb, SxR.XrAx, ip) { return false }
      sx_put(sb, "  testq %rax, %rax\n  jz ")
      sx_lbl(sb, x, SxAt(i))
      sx_put(sb, "\n")
      sx_stk_push(x, a, SxAt(i))
      true
    }
    OpElse => {
      to : Option(SxAt) = sx_stk_top(x)
      match to {
        Some(k) => {
          sx_put(sb, "  jmp ")
          sx_lbl(sb, x, SxAt(i))
          sx_put(sb, "\n")
          sx_def_lbl(sb, x, k)
          ir::wb_set_top(x.stk, i)
        }
        None => { false }
      }
    }
    OpEnd => { sx_end(sb, x) }
    OpBr => { sx_br(sb, x, ip, false) }
    OpBrIf => { sx_br(sb, x, ip, true) }
    OpRet => {
      match ir::i_ak(ip) {
        OkVReg => { sx_ldv(sb, SxR.XrAx, sx_slot(usize(ir::i_av(ip)))) }
        OkNone => {}
        OkImm | OkFrame | OkSym | OkFn | OkLabel => { return false }
      }
      sx_put(sb, "  jmp ")
      sx_ret_lbl(sb, x)
      sx_put(sb, "\n")
      true
    }
    OpTrap => { sx_trap(sb, x, ir::i_tk(ip), ip); true }
    OpTrapIf => {
      if not sx_lda(sb, SxR.XrAx, ip) { return false }
      sx_put(sb, "  testq %rax, %rax\n")
      sx_trap_unless(sb, x, "jz", ir::i_tk(ip), ip)
      true
    }
    OpFConst | OpFnAddr | OpNot | OpNeg | OpTrunc | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpBSwap | OpGep | OpBound | OpCallInd
      | OpCallC | OpSyscall | OpSwitch => { false }
  }
}

## Select function `f` (declaration `d`) into `sb`. Answers false — with `sb` possibly partly
## written; the caller rewinds it — when the function is refused. The labels are the ones `emit_fn`
## writes for a plain function: an `@export` alias, the mangled label, `.globl` where the legacy
## emitter makes it global. A `_start` (the process entry, not a function) is left to `emit_fn`.
sx_fn := fn(in out sb : rt::StrBuf, x : SxX, d : Decl, in out a : rt::Arena) -> bool {
  nv := ir::fn_nvregs(x.f)
  np := ir::fn_nparams(x.f)
  if np > SX_MAX_ARGS or not sx_plain_label(x, d) { return false }
  if str_at((x.src + d.name_start), d.name_len) == "_start" { return false }
  frame := x.ftop
  sx_put(sb, "# ir: selected from the shared IR\n")
  exn := export_name(x.src, d.name_start, d.name_len)
  if exn.n != 0 and entry_export_moved(d.mod_start, d.mod_len, d.name_start, d.name_len) == false {
    sx_put(sb, ".global ")
    sx_put(sb, str_at(x.src + exn.s, exn.n))
    sx_put(sb, "\n")
    sx_put(sb, str_at(x.src + exn.s, exn.n))
    sx_put(sb, ":\n")
  }
  if mangled_symbol_is_global(x.src, d) {
    sx_put(sb, ".globl ")
    emit_mangled_def(sb, x.src, d.mod_start, d.mod_len, d.name_start, d.name_len)
    sx_put(sb, "\n")
  }
  emit_mangled_def(sb, x.src, d.mod_start, d.mod_len, d.name_start, d.name_len)
  sx_put(sb, ":\n  pushq %rbp\n  movq %rsp, %rbp\n")
  if frame != 0 { sx_put(sb, "  subq $"); sx_int(sb, frame); sx_put(sb, ", %rsp\n") }
  mut pi : usize = 0
  while pi < np {
    ro : Option(SxR) = sx_argreg(pi)
    match ro { Some(r) => { sx_stv(sb, r, sx_slot(pi)) }; None => { return false } }
    pi = pi + 1
  }
  pi = 0
  while pi < np {
    if not sx_canon_slot(sb, x, sx_slot(pi)) { return false }
    pi = pi + 1
  }
  ni := ir::fn_ninst(x.f)
  mut i : usize = 0
  while i < ni {
    if not sx_inst(sb, x, a, i) { return false }
    i = i + 1
  }
  if ir::wb_len(x.stk) != 0 { return false }
  sx_ret_lbl(sb, x)
  sx_put(sb, ":\n  movq %rbp, %rsp\n  popq %rbp\n  ret\n")
  true
}

## The hook in `emit_program`'s declaration loop, reached only when the `x86-ir` verb asked for IR
## selection (`lower::set_x86_ir_select`): emit declaration `di` from the shared IR when the builder builds it, the verifier accepts it and this selector selects
## every op. Answers whether it did; on false nothing was written and the caller emits the declaration
## the legacy way.
pub x86_isel_try := fn(decls : ptr(rt::Vec), di : usize, in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) -> bool {
  mut ia := a
  p := ir::prog_new(ia)
  si : ir::SelIn = ir::select_input(p, decls, src, di, ia)
  match si {
    SiBuilt(f) => {
      d : Decl = deref(lower_ctx::decl_get(decls, di))
      fo := ir::frame_place(f, ia, 0)
      mut vb : i64 = i64(ir::fn_nvregs(f)) * 8
      if vb % 16 != 0 { vb = vb + 8 }
      mut ob : i64 = i64(ir::wb_get(fo, ir::wb_len(fo) - 1))
      if ob % 16 != 0 { ob = ob + (16 - ob % 16) }
      x := SxX(f = f, p = p, src = src, decls = decls, fid = SX_FN, fspan = d.name_start, stk = ir::wb_new(ia, 16), fobj = fo, ftop = vb + ob)
      mark := sb.len
      if sx_fn(sb, x, d, ia) {
        SX_FN = SX_FN + 1
        return true
      }
      sb.len = mark
      false
    }
    SiLegacy => { false }
  }
}
