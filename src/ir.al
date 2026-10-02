## selfhost::ir — the shared intermediate representation (`docs/ir.md` §3), slice 0a: INERT.
##
## One semantic lowering for four backends. This module holds the IR's data model, its printer, its
## verifier (`docs/ir.md` §5, rules V1–V10) and the builder's entry point. In slice 0a nothing is
## lowered through it: the builder answers `NotYet(construct, span)` for every function, every target
## keeps its legacy emitter, and no byte of any emitted program depends on this file. The only surfaces
## are the dev verb `alatyr ir` (D5: a CLI verb listed in `alatyr help`, never an environment switch)
## and its `--self-test`, which builds IR functions by hand, prints them, and plants one violation per
## verifier rule to prove each rule refuses what it names.
##
## Design rules this file keeps (and each later slice must keep):
##   * IR types are KERNEL types only (§3.2): `i8 i16 i32 i64 bool ptr f32 f64`. Brands, aliases,
##     generic parameters and aggregates never become an IR value; the enum `Kty` has no variant for
##     them, so V2 holds by construction and the verifier only refuses the "no type" marker.
##   * Signedness is an attribute of the VALUE (§3.8): every vreg records `s`/`u`, and every
##     signedness-dependent op spells it; V4 checks the two agree. There is no "unknown" default.
##   * Control flow is STRUCTURED (§3.5): `block`/`loop`/`if`/`unchecked` regions are opened by an op
##     and closed by `end`; `br L` leaves `block L` or restarts `loop L`.
##   * Storage is ARENA-BACKED and GROWS (no fixed capacities, unlike `src/lower/ir.al`'s 64/32/16):
##     every list is a `WBuf` that doubles into a fresh block of the arena it is handed.
##
## Strict forms (`.agents/skills/alatyr-lane/strict_forms.md`): kinds are enums decided by exhaustive
## `match`; absence is a variant (`OkNone`, `KNone`, `SgNone`, …), never a reserved number; the
## `usize` <-> pointer crossings are confined to the four accessors of the storage band, each with its
## reason.
(Arg, Arm, Decl, Expr, Param, Stmt) := ast
## The slice-1 builder, a child module (`src/ir/build.al`), imported by bare name.
(build_one, BuildOut, BuildWhy, NyWhy, nywhy_is_gap, nywhy_name, ast_op_cc) := build
## The golden builds `ir --self-test` runs (`src/ir/golden.al`).
(golden_run) := golden
arg_p := ast::arg_p
arg_at := ast::arg_at
stmt_p := ast::stmt_p

## ───────────────────────────── kinds ─────────────────────────────

## The kernel type of an IR value. `KNone` is "no value" (a `store`, a `br`, a void call): it is a
## variant so that absence is explicit, and the verifier refuses it as a vreg's type (V2).
pub Kty := enum { KI8, KI16, KI32, KI64, KBool, KPtr, KF32, KF64, KNone }

## Signedness, on a value and on every op whose meaning depends on it (§3.2, §3.8).
pub Sgn := enum { SgS, SgU, SgNone }

## The arithmetic MODE (§3.4): where the checked/unchecked decision lives.
pub Mode := enum { MdWrap, MdChk, MdHw, MdNone }

## A comparison predicate.
pub Cc := enum { CcEq, CcNe, CcLt, CcLe, CcGt, CcGe, CcNone }

## The kind a trap names (§3.6). `TkNone` is "this op does not trap".
pub TrapKind := enum { TkOverflow, TkDivZero, TkDivOverflow, TkShiftRange, TkNarrow, TkBounds, TkMatchNoArm, TkUnwrap, TkRequire, TkPanic, TkNone }

## An operand's kind. `OkFn` names a function of the same IR program by its index (a call V8 can
## check); `OkSym` names a symbol outside the program (a legacy-emitted function, a global).
pub OpndK := enum { OkNone, OkVReg, OkImm, OkFrame, OkSym, OkFn, OkLabel }

## The operations (§3.4). Regions: `block`, `loop`, `if`, `unchecked` open one, `else` separates an
## `if`'s arms, `end` closes the innermost. `mov` assigns a vreg from another (vregs are variables,
## not SSA: §3.3).
pub Op := enum {
  OpConst, OpFConst, OpAddrSym, OpAddrFrame, OpFnAddr, OpMov,
  OpAdd, OpSub, OpMul, OpDiv, OpRem, OpAnd, OpOr, OpXor, OpNot, OpNeg, OpShl, OpShr, OpRotl, OpRotr,
  OpExt, OpFit, OpTrunc,
  OpCmp, OpFCmp,
  OpFAdd, OpFSub, OpFMul, OpFDiv, OpFNeg, OpIToF, OpFToI, OpFExt, OpFDemote, OpBits,
  OpLoad, OpStore, OpBSwap, OpCopy, OpZero,
  OpGep, OpBound,
  OpCall, OpCallInd, OpCallC, OpSyscall,
  OpBlock, OpLoop, OpIf, OpElse, OpUnch, OpEnd, OpBr, OpBrIf, OpSwitch, OpRet, OpTrap, OpTrapIf,
}

## A verifier rule (§5).
pub VRule := enum { V1, V2, V3, V4, V5, V6, V7, V8, V9, V10, VOk }

## ───────────────────────────── kind helpers (one exhaustive `match` each) ─────────────────────────────

## An injective small code per kind, used ONLY to compare two kinds for equality (`kty_code(a) ==
## kty_code(b)`) — never to recover a variant from a number.
kty_code := fn(k : Kty) -> u64 {
  match k { KI8 => { 1 }; KI16 => { 2 }; KI32 => { 3 }; KI64 => { 4 }; KBool => { 5 }; KPtr => { 6 }; KF32 => { 7 }; KF64 => { 8 }; KNone => { 9 } }
}
sgn_code := fn(s : Sgn) -> u64 {
  match s { SgS => { 1 }; SgU => { 2 }; SgNone => { 3 } }
}
pub kty_eq := fn(a : Kty, b : Kty) -> bool { kty_code(a) == kty_code(b) }
pub sgn_eq := fn(a : Sgn, b : Sgn) -> bool { sgn_code(a) == sgn_code(b) }

pub kty_name := fn(k : Kty) -> str {
  match k { KI8 => { "i8" }; KI16 => { "i16" }; KI32 => { "i32" }; KI64 => { "i64" }; KBool => { "bool" }; KPtr => { "ptr" }; KF32 => { "f32" }; KF64 => { "f64" }; KNone => { "void" } }
}
## The byte width a value of the kind occupies in memory (V6: always one of 1, 2, 4, 8). `KNone` has
## none; 0 is its width, and V2/V1 refuse it before a width is ever asked of it.
pub kty_bytes := fn(k : Kty) -> u64 {
  match k { KI8 => { 1 }; KI16 => { 2 }; KI32 => { 4 }; KI64 => { 8 }; KBool => { 1 }; KPtr => { 8 }; KF32 => { 4 }; KF64 => { 8 }; KNone => { 0 } }
}
pub kty_is_int := fn(k : Kty) -> bool {
  match k { KI8 | KI16 | KI32 | KI64 => { true }; KBool | KPtr | KF32 | KF64 | KNone => { false } }
}
## A NARROW integer: canonical form is a sign- or zero-extension from its width (§3.2, V3).
pub kty_is_narrow := fn(k : Kty) -> bool {
  match k { KI8 | KI16 | KI32 => { true }; KI64 | KBool | KPtr | KF32 | KF64 | KNone => { false } }
}
pub kty_is_float := fn(k : Kty) -> bool {
  match k { KF32 | KF64 => { true }; KI8 | KI16 | KI32 | KI64 | KBool | KPtr | KNone => { false } }
}
pub kty_is_none := fn(k : Kty) -> bool {
  match k { KNone => { true }; KI8 | KI16 | KI32 | KI64 | KBool | KPtr | KF32 | KF64 => { false } }
}
pub kty_is_bool := fn(k : Kty) -> bool {
  match k { KBool => { true }; KI8 | KI16 | KI32 | KI64 | KPtr | KF32 | KF64 | KNone => { false } }
}
pub kty_is_ptr := fn(k : Kty) -> bool {
  match k { KPtr => { true }; KI8 | KI16 | KI32 | KI64 | KBool | KF32 | KF64 | KNone => { false } }
}
## Is the kind a sign-carrying integer? Only integers carry `s`/`u`; every other kind carries `SgNone`.
sgn_is_none := fn(s : Sgn) -> bool {
  match s { SgNone => { true }; SgS | SgU => { false } }
}
sgn_name := fn(s : Sgn) -> str {
  match s { SgS => { "s" }; SgU => { "u" }; SgNone => { "" } }
}
mode_name := fn(m : Mode) -> str {
  match m { MdWrap => { "wrap" }; MdChk => { "chk" }; MdHw => { "hw" }; MdNone => { "" } }
}
mode_is_none := fn(m : Mode) -> bool {
  match m { MdNone => { true }; MdWrap | MdChk | MdHw => { false } }
}
pub mode_is_chk := fn(m : Mode) -> bool {
  match m { MdChk => { true }; MdWrap | MdHw | MdNone => { false } }
}
mode_is_hw := fn(m : Mode) -> bool {
  match m { MdHw => { true }; MdWrap | MdChk | MdNone => { false } }
}
mode_is_wrap := fn(m : Mode) -> bool {
  match m { MdWrap => { true }; MdChk | MdHw | MdNone => { false } }
}
## A predicate prints as its operator (`cmp.<.s`), so the IR text reads like the source it came from.
cc_name := fn(c : Cc) -> str {
  match c { CcEq => { "==" }; CcNe => { "!=" }; CcLt => { "<" }; CcLe => { "<=" }; CcGt => { ">" }; CcGe => { ">=" }; CcNone => { "?" } }
}
## An ORDERING predicate depends on signedness; equality does not (§3.4 `cmp … ·s/u`).
cc_is_ordering := fn(c : Cc) -> bool {
  match c { CcLt | CcLe | CcGt | CcGe => { true }; CcEq | CcNe | CcNone => { false } }
}
cc_is_none := fn(c : Cc) -> bool {
  match c { CcNone => { true }; CcEq | CcNe | CcLt | CcLe | CcGt | CcGe => { false } }
}
pub trap_name := fn(t : TrapKind) -> str {
  match t {
    TkOverflow => { "overflow" }; TkDivZero => { "div_zero" }; TkDivOverflow => { "div_overflow" }
    TkShiftRange => { "shift_range" }; TkNarrow => { "narrow" }; TkBounds => { "bounds" }
    TkMatchNoArm => { "match_no_arm" }; TkUnwrap => { "unwrap" }; TkRequire => { "require" }
    TkPanic => { "panic" }; TkNone => { "" }
  }
}
trap_is_none := fn(t : TrapKind) -> bool {
  match t {
    TkNone => { true }
    TkOverflow | TkDivZero | TkDivOverflow | TkShiftRange | TkNarrow | TkBounds | TkMatchNoArm | TkUnwrap | TkRequire | TkPanic => { false }
  }
}
pub vrule_name := fn(r : VRule) -> str {
  match r { V1 => { "V1" }; V2 => { "V2" }; V3 => { "V3" }; V4 => { "V4" }; V5 => { "V5" }; V6 => { "V6" }; V7 => { "V7" }; V8 => { "V8" }; V9 => { "V9" }; V10 => { "V10" }; VOk => { "ok" } }
}
vrule_code := fn(r : VRule) -> u64 {
  match r { V1 => { 1 }; V2 => { 2 }; V3 => { 3 }; V4 => { 4 }; V5 => { 5 }; V6 => { 6 }; V7 => { 7 }; V8 => { 8 }; V9 => { 9 }; V10 => { 10 }; VOk => { 0 } }
}
pub vrule_is_ok := fn(r : VRule) -> bool {
  match r { VOk => { true }; V1 | V2 | V3 | V4 | V5 | V6 | V7 | V8 | V9 | V10 => { false } }
}
opndk_is_vreg := fn(k : OpndK) -> bool {
  match k { OkVReg => { true }; OkNone | OkImm | OkFrame | OkSym | OkFn | OkLabel => { false } }
}
opndk_is_none := fn(k : OpndK) -> bool {
  match k { OkNone => { true }; OkVReg | OkImm | OkFrame | OkSym | OkFn | OkLabel => { false } }
}
opndk_is_frame := fn(k : OpndK) -> bool {
  match k { OkFrame => { true }; OkNone | OkVReg | OkImm | OkSym | OkFn | OkLabel => { false } }
}
opndk_is_fn := fn(k : OpndK) -> bool {
  match k { OkFn => { true }; OkNone | OkVReg | OkImm | OkFrame | OkSym | OkLabel => { false } }
}

## The textual mnemonic of an op.
pub op_name := fn(o : Op) -> str {
  match o {
    OpConst => { "const" }; OpFConst => { "fconst" }; OpAddrSym => { "addr" }; OpAddrFrame => { "addr" }
    OpFnAddr => { "fnaddr" }; OpMov => { "mov" }
    OpAdd => { "add" }; OpSub => { "sub" }; OpMul => { "mul" }; OpDiv => { "div" }; OpRem => { "rem" }
    OpAnd => { "and" }; OpOr => { "or" }; OpXor => { "xor" }; OpNot => { "not" }; OpNeg => { "neg" }
    OpShl => { "shl" }; OpShr => { "shr" }; OpRotl => { "rotl" }; OpRotr => { "rotr" }
    OpExt => { "ext" }; OpFit => { "fit" }; OpTrunc => { "trunc" }
    OpCmp => { "cmp" }; OpFCmp => { "fcmp" }
    OpFAdd => { "fadd" }; OpFSub => { "fsub" }; OpFMul => { "fmul" }; OpFDiv => { "fdiv" }; OpFNeg => { "fneg" }
    OpIToF => { "itof" }; OpFToI => { "ftoi" }; OpFExt => { "fext" }; OpFDemote => { "fdemote" }; OpBits => { "bits" }
    OpLoad => { "load" }; OpStore => { "store" }; OpBSwap => { "bswap" }; OpCopy => { "copy" }; OpZero => { "zero" }
    OpGep => { "gep" }; OpBound => { "bound" }
    OpCall => { "call" }; OpCallInd => { "call_ind" }; OpCallC => { "call_c" }; OpSyscall => { "syscall" }
    OpBlock => { "block" }; OpLoop => { "loop" }; OpIf => { "if" }; OpElse => { "else" }; OpUnch => { "unchecked" }
    OpEnd => { "end" }; OpBr => { "br" }; OpBrIf => { "br_if" }; OpSwitch => { "switch" }; OpRet => { "ret" }
    OpTrap => { "trap" }; OpTrapIf => { "trap_if" }
  }
}

## The CLASS of an op, which is what the verifier and the printer decide on. One exhaustive `match`
## classifies every op once; each rule then matches on the class instead of re-listing forty ops.
pub OpClass := enum {
  ClConst,     ## const, fconst: dst ← immediate
  ClAddr,      ## addr @sym, addr $k, fnaddr: dst ptr
  ClMov,       ## dst ← a, same type
  ClIntBin,    ## add sub mul div rem and or xor shl shr rotl rotr: dst ← a op b, integer
  ClIntUn,     ## not neg: dst ← op a, integer
  ClWidth,     ## ext fit: dst:ty ← a:from, integer
  ClTrunc,     ## trunc: dst bool ← a integer
  ClCmp,       ## cmp: dst bool ← a cc b
  ClFCmp,      ## fcmp: dst bool ← a cc b, float
  ClFBin,      ## fadd fsub fmul fdiv
  ClFUn,       ## fneg
  ClConv,      ## itof ftoi fext fdemote bits: dst:ty ← a:from
  ClLoad,      ## load
  ClStore,     ## store
  ClBSwap,     ## bswap
  ClMem,       ## copy zero
  ClGep,       ## gep
  ClBound,     ## bound (traps)
  ClCall,      ## call call_ind call_c syscall
  ClOpen,      ## block loop if unchecked
  ClElse,      ## else
  ClEnd,       ## end
  ClBr,        ## br br_if
  ClSwitch,    ## switch
  ClRet,       ## ret
  ClTrap,      ## trap trap_if
}
pub op_class := fn(o : Op) -> OpClass {
  match o {
    OpConst | OpFConst => { OpClass.ClConst }
    OpAddrSym | OpAddrFrame | OpFnAddr => { OpClass.ClAddr }
    OpMov => { OpClass.ClMov }
    OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd | OpOr | OpXor | OpShl | OpShr | OpRotl | OpRotr => { OpClass.ClIntBin }
    OpNot | OpNeg => { OpClass.ClIntUn }
    OpExt | OpFit => { OpClass.ClWidth }
    OpTrunc => { OpClass.ClTrunc }
    OpCmp => { OpClass.ClCmp }
    OpFCmp => { OpClass.ClFCmp }
    OpFAdd | OpFSub | OpFMul | OpFDiv => { OpClass.ClFBin }
    OpFNeg => { OpClass.ClFUn }
    OpIToF | OpFToI | OpFExt | OpFDemote | OpBits => { OpClass.ClConv }
    OpLoad => { OpClass.ClLoad }
    OpStore => { OpClass.ClStore }
    OpBSwap => { OpClass.ClBSwap }
    OpCopy | OpZero => { OpClass.ClMem }
    OpGep => { OpClass.ClGep }
    OpBound => { OpClass.ClBound }
    OpCall | OpCallInd | OpCallC | OpSyscall => { OpClass.ClCall }
    OpBlock | OpLoop | OpIf | OpUnch => { OpClass.ClOpen }
    OpElse => { OpClass.ClElse }
    OpEnd => { OpClass.ClEnd }
    OpBr | OpBrIf => { OpClass.ClBr }
    OpSwitch => { OpClass.ClSwitch }
    OpRet => { OpClass.ClRet }
    OpTrap | OpTrapIf => { OpClass.ClTrap }
  }
}

## Does the op's meaning depend on signedness (§3.2: "Division, remainder, right shift, ordering
## compares, overflow checks, extension and int↔float conversion each spell `s` or `u`")? The compare
## and the checked-arithmetic cases also depend on the instruction's predicate/mode and are decided by
## the verifier beside this answer.
op_needs_sign := fn(o : Op) -> bool {
  match o {
    OpDiv | OpRem | OpShr | OpExt | OpFit | OpIToF | OpFToI => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpAnd | OpOr | OpXor
      | OpNot | OpNeg | OpShl | OpRotl | OpRotr | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv
      | OpFNeg | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound
      | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr
      | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## Arithmetic whose OVERFLOW is the op's business: the ops a mode applies to (§3.4).
op_has_mode := fn(o : Op) -> bool {
  match o {
    OpAdd | OpSub | OpMul | OpDiv | OpRem | OpNeg | OpShl | OpShr | OpFToI => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAnd | OpOr | OpXor | OpNot | OpRotl
      | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF
      | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall
      | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr | OpBrIf
      | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## V3 — the ops whose result is canonical for a narrow type by construction: bitwise ops over canonical
## operands, a `load` (its extension comes from the type's sign), an in-range `const`, and the width
## ops themselves. A `call` result is canonical by the convention every selector keeps, and a `mov`
## copies a canonical value. Everything else that produces a narrow type must go through `ext`/`fit`.
op_keeps_canonical := fn(o : Op) -> bool {
  match o {
    OpAnd | OpOr | OpXor | OpLoad | OpConst | OpExt | OpFit | OpMov | OpCall | OpCallInd | OpCallC => { true }
    OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpNot | OpNeg | OpShl
      | OpShr | OpRotl | OpRotr | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF
      | OpFToI | OpFExt | OpFDemote | OpBits | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpSyscall
      | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## A TERMINATOR ends a sequence: nothing may follow it before the region's `else`/`end` (V7). A `switch`
## always transfers control (its `default` is mandatory), so it terminates too.
op_is_terminator := fn(o : Op) -> bool {
  match o {
    OpBr | OpRet | OpTrap | OpSwitch => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem
      | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp
      | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits
      | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall
      | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBrIf | OpTrapIf => { false }
  }
}
## The region an opening op creates.
pub RegionK := enum { RkBlock, RkLoop, RkIf, RkUnch, RkNone }
op_region := fn(o : Op) -> RegionK {
  match o {
    OpBlock => { RegionK.RkBlock }; OpLoop => { RegionK.RkLoop }; OpIf => { RegionK.RkIf }; OpUnch => { RegionK.RkUnch }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem
      | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp
      | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits
      | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall
      | OpElse | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { RegionK.RkNone }
  }
}
region_has_label := fn(r : RegionK) -> bool {
  match r { RkBlock | RkLoop => { true }; RkIf | RkUnch | RkNone => { false } }
}
region_is_if := fn(r : RegionK) -> bool {
  match r { RkIf => { true }; RkBlock | RkLoop | RkUnch | RkNone => { false } }
}
region_is_loop := fn(r : RegionK) -> bool {
  match r { RkLoop => { true }; RkBlock | RkIf | RkUnch | RkNone => { false } }
}
region_is_unch := fn(r : RegionK) -> bool {
  match r { RkUnch => { true }; RkBlock | RkLoop | RkIf | RkNone => { false } }
}
region_code := fn(r : RegionK) -> u64 {
  match r { RkBlock => { 1 }; RkLoop => { 2 }; RkIf => { 3 }; RkUnch => { 4 }; RkNone => { 5 } }
}


## ───────────────────────────── handles ─────────────────────────────

## Every handle the IR hands out is a BRAND of the arena index it is (Types §4.2): a vreg, a label, a
## frame object and a function of the program cannot be passed for one another without a visible
## conversion.
pub VRegId := brand(usize)
pub LabelId := brand(usize)
pub FrameId := brand(usize)
pub FnId := brand(usize)
pub SymId := brand(usize)

## ───────────────────────────── storage: a growing word buffer ─────────────────────────────

## A list of words that GROWS: when full it doubles into a fresh block of the arena it is handed and
## copies itself (the old block is simply abandoned — arenas are reclaimed at process exit). There is
## no capacity a program can exceed short of the arena itself, which panics loudly (`rt::bump`).
pub WBuf := struct { data : ptr(mut u8), len : usize, cap : usize }

## The `usize` <-> pointer crossings of this module live in this band and in the record accessors below.
## unchecked-ok: `rt::bump` returns the fresh block's address as a usize (the arena's handle currency); this is that block.
bump_ptr := fn(in out a : rt::Arena, n : usize) -> ptr(mut u8) { unchecked bitcast(ptr(mut u8), rt::bump(a, n)) }
## The address of word `i` of a block. Pointer arithmetic on a `ptr(mut u8)` is unchecked by type.
word_at := fn(d : ptr(mut u8), i : usize) -> ptr(mut usize) {
  ## unchecked-ok: every WBuf block is 8-byte-aligned arena memory of `cap` words, and every caller passes `i < cap`.
  unchecked bitcast(ptr(mut usize), d + i * 8)
}
## unchecked-ok: a record pointer is stored in a WBuf word; this is the only way in, and each `*_ptr` accessor below the only way out.
ptr_word := fn(p : ptr(mut u8)) -> usize { unchecked bitcast(usize, p) }

pub wb_new := fn(in out a : rt::Arena, cap : usize) -> ptr(mut WBuf) {
  hp := bump_ptr(a, 24)
  ## unchecked-ok: a fresh 24-byte arena block is exactly one `WBuf` record.
  w : ptr(mut WBuf) = unchecked bitcast(ptr(mut WBuf), hp)
  mut c := cap
  if c == 0 { c = 8 }
  d := bump_ptr(a, c * 8)
  nw := WBuf(data = d, len = 0, cap = c)
  deref(w) = nw
  w
}
pub wb_len := fn(w : ptr(mut WBuf)) -> usize { wv : WBuf = deref(w); wv.len }
pub wb_get := fn(w : ptr(mut WBuf), i : usize) -> usize {
  wv : WBuf = deref(w)
  if i >= wv.len { panic("selfhost: ir — WBuf read past its length") }
  deref(word_at(wv.data, i))
}
## Append `x`, doubling the block when it is full. Returns the new element's index.
pub wb_push := fn(w : ptr(mut WBuf), in out a : rt::Arena, x : usize) -> usize {
  wv : WBuf = deref(w)
  n := wv.len
  mut d := wv.data
  if n >= wv.cap {
    nc := wv.cap * 2
    nd := bump_ptr(a, nc * 8)
    mut k : usize = 0
    while k < n {
      deref(word_at(nd, k)) = deref(word_at(d, k))
      k = k + 1
    }
    d = nd
    deref(w).data = nd
    deref(w).cap = nc
  }
  deref(word_at(d, n)) = x
  deref(w).len = n + 1
  n
}

## Drop the last element (a selector's region stack). Answers false on an empty buffer.
pub wb_pop := fn(w : ptr(mut WBuf)) -> bool {
  n := wb_len(w)
  if n == 0 { return false }
  deref(w).len = n - 1
  true
}
## Replace the last element. Answers false on an empty buffer.
pub wb_set_top := fn(w : ptr(mut WBuf), x : usize) -> bool {
  wv : WBuf = deref(w)
  if wv.len == 0 { return false }
  deref(word_at(wv.data, wv.len - 1)) = x
  true
}

## ───────────────────────────── the IR records ─────────────────────────────
##
## Every record is read back by COPYING it into an annotated local first (`it : IrInst = deref(ip)`), and
## every enum field is read from that local by a one-line accessor whose call is then the `match`
## scrutinee. That is not style: reading an enum-typed field straight through a pointer
## (`deref(p).op`) answers the wrong variant or SIGSEGVs on x86_64 today, on `main` and on the frozen
## seed alike (#792). For the same reason no record carries an `Option(u64)` field (measured to read a
## neighbouring word, #792) or a payload-carrying enum field (reads 0, #792): an absent span is
## `has_span = false`, an absent operand is the kind `OkNone`. Convert both when #792 is fixed and the
## seed is promoted.

## One vreg's declared type (V1: "every vreg has one IR type"). Signedness lives on the value (§3.8).
pub VInfo := struct { ty : Kty, sg : Sgn }

## One frame object (§3.3): per-function memory with a size and an alignment.
pub Frame := struct { size : usize, align : usize }

## An operand, as a value handed to the instruction builders: its kind and its payload word.
##
## Throughout this file a call whose result is an enum, an `Option` or a struct is bound to an annotated
## local before it is passed on, and a call never receives two such results as arguments: the x86_64
## lowering reserves too small an aggregate-argument pool for a call with two enum-valued call
## arguments and aborts the build ("aggregate-value call-arg temp pool overflow"; measured on the seed
## with `put_ty(sb, fn_ret_ty(f), fn_ret_sg(f))`, the #772 family).
pub Opnd := struct { k : OpndK, v : i64 }

## One instruction. Operands are (kind, value) pairs; an absent operand is `OkNone`. `ty`/`sg` are the
## type the op works at (the result type, the stored value's type for `store`, the operand type for
## `cmp`); `from`/`fsg` are the source type of a width or conversion op. `pool`/`n` address a run of the
## function's operand pool (call arguments; `switch` key/label pairs). `lbl` is a region's or a
## branch's label; `off` a memory offset or a `gep` stride. `has_span`/`span` locate the construct that
## owns the op (V9). `proven` marks a `wrap` op the builder proved cannot overflow (a range `for` step
## after its bound test, §4) — the one way a `wrap` op may appear outside an `unchecked` region (V10).
pub IrInst := struct {
  op : Op, ty : Kty, sg : Sgn, md : Mode, cc : Cc, tk : TrapKind,
  dk : OpndK, dv : i64,
  ak : OpndK, av : i64,
  bk : OpndK, bv : i64,
  from : Kty, fsg : Sgn,
  off : i64, n : usize, pool : usize, lbl : usize,
  has_span : bool, span : usize, proven : bool,
}

## One function. Parameters are vregs `%0 .. %(nparams-1)`. `name_p`/`name_n` name it; `has_ret` with
## `ret_ty`/`ret_sg` is its result. `vregs`, `frames` and `insts` hold record pointers; `pool` holds
## plain words (vreg ids, switch keys, label ids).
pub IrFn := struct {
  name_p : ptr(u8), name_n : usize,
  nparams : usize, has_ret : bool, ret_ty : Kty, ret_sg : Sgn,
  vregs : ptr(mut WBuf), frames : ptr(mut WBuf), insts : ptr(mut WBuf), pool : ptr(mut WBuf),
  nlabels : usize,
}

## A program: its functions, in order (an `OkFn` operand is an index into `fns`), and the symbols its
## `OkSym` operands name — a function or a global outside the program, identified by its declaration.
## `syms` holds three words per symbol: the declaration's index, its name's address and its length.
pub IrProg := struct { fns : ptr(mut WBuf), syms : ptr(mut WBuf) }

## ── the way back out of a WBuf word: one accessor per record type ──
## unchecked-ok: `fn_ptr` reads back a word `prog_add` pushed from a `ptr(mut IrFn)`.
fn_ptr := fn(w : usize) -> ptr(mut IrFn) { unchecked bitcast(ptr(mut IrFn), w) }
## unchecked-ok: `inst_ptr` reads back a word `emit` pushed from a `ptr(mut IrInst)`.
inst_ptr := fn(w : usize) -> ptr(mut IrInst) { unchecked bitcast(ptr(mut IrInst), w) }
## unchecked-ok: `vinfo_ptr` reads back a word `new_vreg` pushed from a `ptr(mut VInfo)`.
vinfo_ptr := fn(w : usize) -> ptr(mut VInfo) { unchecked bitcast(ptr(mut VInfo), w) }
## unchecked-ok: `frame_ptr` reads back a word `new_frame` pushed from a `ptr(mut Frame)`.
frame_ptr := fn(w : usize) -> ptr(mut Frame) { unchecked bitcast(ptr(mut Frame), w) }

pub prog_new := fn(in out a : rt::Arena) -> IrProg {
  fw := wb_new(a, 8)
  sw := wb_new(a, 24)
  IrProg(fns = fw, syms = sw)
}
## The symbol of declaration `decl` named `[name_p, name_p+name_n)`, added on first use.
pub prog_sym := fn(p : IrProg, in out a : rt::Arena, decl : usize, name_p : ptr(u8), name_n : usize) -> SymId {
  n := wb_len(p.syms) / 3
  mut i : usize = 0
  while i < n {
    if wb_get(p.syms, i * 3) == decl { return SymId(i) }
    i = i + 1
  }
  k1 := wb_push(p.syms, a, decl)
  ## unchecked-ok: a symbol's name address is kept as its WBuf word; `sym_name` is the only way back.
  k2 := wb_push(p.syms, a, unchecked bitcast(usize, name_p))
  k3 := wb_push(p.syms, a, name_n)
  SymId(n)
}
pub prog_nsyms := fn(p : IrProg) -> usize { wb_len(p.syms) / 3 }
## The declaration index a symbol names.
pub sym_decl := fn(p : IrProg, s : SymId) -> usize { wb_get(p.syms, usize(s) * 3) }
sym_name := fn(p : IrProg, s : SymId) -> str {
  ## unchecked-ok: the word `prog_sym` stored from the symbol's name address.
  np : ptr(u8) = unchecked bitcast(ptr(u8), wb_get(p.syms, usize(s) * 3 + 1))
  str_at(np, wb_get(p.syms, usize(s) * 3 + 2))
}
pub prog_len := fn(p : IrProg) -> usize { wb_len(p.fns) }
pub prog_fn := fn(p : IrProg, i : FnId) -> ptr(mut IrFn) { fn_ptr(wb_get(p.fns, usize(i))) }

## A new function; the caller then declares its parameters with `new_param`, in order.
pub fn_new := fn(in out a : rt::Arena, name_p : ptr(u8), name_n : usize, has_ret : bool, ret_ty : Kty, ret_sg : Sgn) -> ptr(mut IrFn) {
  hp := bump_ptr(a, size(IrFn))
  ## unchecked-ok: a fresh arena block of `size(IrFn)` bytes is exactly one `IrFn` record.
  f : ptr(mut IrFn) = unchecked bitcast(ptr(mut IrFn), hp)
  vw := wb_new(a, 16)
  fw := wb_new(a, 4)
  iw := wb_new(a, 32)
  pw := wb_new(a, 8)
  nf := IrFn(name_p = name_p, name_n = name_n, nparams = 0, has_ret = has_ret, ret_ty = ret_ty, ret_sg = ret_sg,
             vregs = vw, frames = fw, insts = iw, pool = pw, nlabels = 0)
  deref(f) = nf
  f
}
pub prog_add := fn(p : IrProg, in out a : rt::Arena, f : ptr(mut IrFn)) -> FnId {
  ## unchecked-ok: the IrFn record pointer is stored as its address word; `fn_ptr` reads it back.
  FnId(wb_push(p.fns, a, ptr_word(unchecked bitcast(ptr(mut u8), f))))
}
## Record reads, one copy-then-read each (#792, see the band comment above).
pub fn_nparams := fn(f : ptr(mut IrFn)) -> usize { fv : IrFn = deref(f); fv.nparams }
pub fn_has_ret := fn(f : ptr(mut IrFn)) -> bool { fv : IrFn = deref(f); fv.has_ret }
pub fn_ret_ty := fn(f : ptr(mut IrFn)) -> Kty { fv : IrFn = deref(f); fv.ret_ty }
pub fn_ret_sg := fn(f : ptr(mut IrFn)) -> Sgn { fv : IrFn = deref(f); fv.ret_sg }
fn_nlabels := fn(f : ptr(mut IrFn)) -> usize { fv : IrFn = deref(f); fv.nlabels }
fn_vregs := fn(f : ptr(mut IrFn)) -> ptr(mut WBuf) { fv : IrFn = deref(f); fv.vregs }
fn_frames := fn(f : ptr(mut IrFn)) -> ptr(mut WBuf) { fv : IrFn = deref(f); fv.frames }
fn_insts := fn(f : ptr(mut IrFn)) -> ptr(mut WBuf) { fv : IrFn = deref(f); fv.insts }
fn_pool := fn(f : ptr(mut IrFn)) -> ptr(mut WBuf) { fv : IrFn = deref(f); fv.pool }
pub irfn_name := fn(f : ptr(mut IrFn)) -> str { fv : IrFn = deref(f); str_at(fv.name_p, fv.name_n) }

## Declare a new vreg of type `ty`/`sg` and return its handle.
pub new_vreg := fn(f : ptr(mut IrFn), in out a : rt::Arena, ty : Kty, sg : Sgn) -> VRegId {
  hp := bump_ptr(a, size(VInfo))
  ## unchecked-ok: a fresh arena block of `size(VInfo)` bytes is exactly one `VInfo` record.
  v : ptr(mut VInfo) = unchecked bitcast(ptr(mut VInfo), hp)
  nv := VInfo(ty = ty, sg = sg)
  deref(v) = nv
  VRegId(wb_push(fn_vregs(f), a, ptr_word(hp)))
}
## Declare the next parameter (a vreg) of type `ty`/`sg`. Parameters come first: vreg `i` is param `i`.
pub new_param := fn(f : ptr(mut IrFn), in out a : rt::Arena, ty : Kty, sg : Sgn) -> VRegId {
  id := new_vreg(f, a, ty, sg)
  deref(f).nparams = fn_nparams(f) + 1
  id
}
pub new_frame := fn(f : ptr(mut IrFn), in out a : rt::Arena, sz : usize, al : usize) -> FrameId {
  hp := bump_ptr(a, size(Frame))
  ## unchecked-ok: a fresh arena block of `size(Frame)` bytes is exactly one `Frame` record.
  fr : ptr(mut Frame) = unchecked bitcast(ptr(mut Frame), hp)
  nfr := Frame(size = sz, align = al)
  deref(fr) = nfr
  FrameId(wb_push(fn_frames(f), a, ptr_word(hp)))
}
pub new_label := fn(f : ptr(mut IrFn)) -> LabelId {
  l := fn_nlabels(f)
  deref(f).nlabels = l + 1
  LabelId(l)
}
pub pool_push := fn(f : ptr(mut IrFn), in out a : rt::Arena, x : usize) -> usize { wb_push(fn_pool(f), a, x) }
pub pool_get := fn(f : ptr(mut IrFn), i : usize) -> usize { wb_get(fn_pool(f), i) }
pool_len := fn(f : ptr(mut IrFn)) -> usize { wb_len(fn_pool(f)) }

pub fn_ninst := fn(f : ptr(mut IrFn)) -> usize { wb_len(fn_insts(f)) }
pub fn_inst := fn(f : ptr(mut IrFn), i : usize) -> ptr(mut IrInst) { inst_ptr(wb_get(fn_insts(f), i)) }
pub fn_nvregs := fn(f : ptr(mut IrFn)) -> usize { wb_len(fn_vregs(f)) }
fn_nframes := fn(f : ptr(mut IrFn)) -> usize { wb_len(fn_frames(f)) }
pub vreg_ty := fn(f : ptr(mut IrFn), v : usize) -> Kty { vi : VInfo = deref(vinfo_ptr(wb_get(fn_vregs(f), v))); vi.ty }
pub vreg_sg := fn(f : ptr(mut IrFn), v : usize) -> Sgn { vi : VInfo = deref(vinfo_ptr(wb_get(fn_vregs(f), v))); vi.sg }
frame_bytes := fn(f : ptr(mut IrFn), k : usize) -> usize { fr : Frame = deref(frame_ptr(wb_get(fn_frames(f), k))); fr.size }
frame_align_of := fn(f : ptr(mut IrFn), k : usize) -> usize { fr : Frame = deref(frame_ptr(wb_get(fn_frames(f), k))); fr.align }

## Instruction field reads (#792: copy first, then read; the call is what a `match` scrutinizes).
pub i_op := fn(ip : ptr(mut IrInst)) -> Op { it : IrInst = deref(ip); it.op }
pub i_ty := fn(ip : ptr(mut IrInst)) -> Kty { it : IrInst = deref(ip); it.ty }
pub i_sg := fn(ip : ptr(mut IrInst)) -> Sgn { it : IrInst = deref(ip); it.sg }
pub i_md := fn(ip : ptr(mut IrInst)) -> Mode { it : IrInst = deref(ip); it.md }
pub i_cc := fn(ip : ptr(mut IrInst)) -> Cc { it : IrInst = deref(ip); it.cc }
pub i_tk := fn(ip : ptr(mut IrInst)) -> TrapKind { it : IrInst = deref(ip); it.tk }
pub i_from := fn(ip : ptr(mut IrInst)) -> Kty { it : IrInst = deref(ip); it.from }
pub i_fsg := fn(ip : ptr(mut IrInst)) -> Sgn { it : IrInst = deref(ip); it.fsg }
pub i_dk := fn(ip : ptr(mut IrInst)) -> OpndK { it : IrInst = deref(ip); it.dk }
pub i_ak := fn(ip : ptr(mut IrInst)) -> OpndK { it : IrInst = deref(ip); it.ak }
pub i_bk := fn(ip : ptr(mut IrInst)) -> OpndK { it : IrInst = deref(ip); it.bk }
pub i_dv := fn(ip : ptr(mut IrInst)) -> i64 { it : IrInst = deref(ip); it.dv }
pub i_av := fn(ip : ptr(mut IrInst)) -> i64 { it : IrInst = deref(ip); it.av }
pub i_bv := fn(ip : ptr(mut IrInst)) -> i64 { it : IrInst = deref(ip); it.bv }
pub i_off := fn(ip : ptr(mut IrInst)) -> i64 { it : IrInst = deref(ip); it.off }
pub i_n := fn(ip : ptr(mut IrInst)) -> usize { it : IrInst = deref(ip); it.n }
pub i_pool := fn(ip : ptr(mut IrInst)) -> usize { it : IrInst = deref(ip); it.pool }
pub i_lbl := fn(ip : ptr(mut IrInst)) -> usize { it : IrInst = deref(ip); it.lbl }
pub i_has_span := fn(ip : ptr(mut IrInst)) -> bool { it : IrInst = deref(ip); it.has_span }
pub i_span := fn(ip : ptr(mut IrInst)) -> usize { it : IrInst = deref(ip); it.span }
i_proven := fn(ip : ptr(mut IrInst)) -> bool { it : IrInst = deref(ip); it.proven }

## ── operands and the instruction builder ──
pub o_none := fn() -> Opnd { Opnd(k = OpndK.OkNone, v = 0) }
pub o_vreg := fn(v : VRegId) -> Opnd { Opnd(k = OpndK.OkVReg, v = i64(usize(v))) }
pub o_imm := fn(x : i64) -> Opnd { Opnd(k = OpndK.OkImm, v = x) }
pub o_frame := fn(k : FrameId) -> Opnd { Opnd(k = OpndK.OkFrame, v = i64(usize(k))) }
pub o_sym := fn(id : SymId) -> Opnd { Opnd(k = OpndK.OkSym, v = i64(usize(id))) }
pub o_fn := fn(i : FnId) -> Opnd { Opnd(k = OpndK.OkFn, v = i64(usize(i))) }

## A blank instruction of op `o`: every operand absent, every attribute `…None`.
pub inst0 := fn(o : Op) -> IrInst {
  IrInst(op = o, ty = Kty.KNone, sg = Sgn.SgNone, md = Mode.MdNone, cc = Cc.CcNone, tk = TrapKind.TkNone,
       dk = OpndK.OkNone, dv = 0, ak = OpndK.OkNone, av = 0, bk = OpndK.OkNone, bv = 0,
       from = Kty.KNone, fsg = Sgn.SgNone, off = 0, n = 0, pool = 0, lbl = 0,
       has_span = false, span = 0, proven = false)
}
pub set_dst := fn(in out it : IrInst, v : VRegId) { it.dk = OpndK.OkVReg; it.dv = i64(usize(v)) }
pub set_a := fn(in out it : IrInst, o : Opnd) { it.ak = o.k; it.av = o.v }
pub set_b := fn(in out it : IrInst, o : Opnd) { it.bk = o.k; it.bv = o.v }
pub set_span := fn(in out it : IrInst, s : usize) { it.has_span = true; it.span = s }
## Append an instruction to `f`; returns its index.
pub emit := fn(f : ptr(mut IrFn), in out a : rt::Arena, it : IrInst) -> usize {
  hp := bump_ptr(a, size(IrInst))
  ## unchecked-ok: a fresh arena block of `size(IrInst)` bytes is exactly one `Inst` record.
  ip : ptr(mut IrInst) = unchecked bitcast(ptr(mut IrInst), hp)
  deref(ip) = it
  wb_push(fn_insts(f), a, ptr_word(hp))
}

## ───────────────────────────── the printer ─────────────────────────────
##
## One line per instruction, indented by region depth. The text is for people and fixtures; nothing
## parses it back. Examples:
##   %2 = add.chk.s i64 %0, %1  @17
##   %5 = ext.s i64 <- i8 %4
##   %6 = cmp.<.u i64 %0, 10
##   store i32 [$0 + 4], %6
##   trap_if %7 div_zero  @40
##   block L0 {  …  }   loop L1 {  …  }   if %3 {  …  } else {  …  }   unchecked {  …  }
push_str := rt::push_str
push_int := rt::push_int

put := fn(in out sb : rt::StrBuf, s : str) { k := push_str(sb, s) }
put_u := fn(in out sb : rt::StrBuf, n : usize) { k := push_int(sb, i64(n)) }
put_i := fn(in out sb : rt::StrBuf, n : i64) { k := push_int(sb, n) }
## Each str-returning call is bound to a local before it is pushed: an inline str-returning call as a
## str argument can lose its length in the lean lower (the note at `cli::run_cli`'s emit modes).
put_kty := fn(in out sb : rt::StrBuf, k : Kty) { s := kty_name(k); put(sb, s) }
put_sgn := fn(in out sb : rt::StrBuf, g : Sgn) { s := sgn_name(g); put(sb, s) }
put_mode := fn(in out sb : rt::StrBuf, m : Mode) { s := mode_name(m); put(sb, s) }
put_cc := fn(in out sb : rt::StrBuf, c : Cc) { s := cc_name(c); put(sb, s) }
put_trap := fn(in out sb : rt::StrBuf, t : TrapKind) { s := trap_name(t); put(sb, s) }
put_op := fn(in out sb : rt::StrBuf, o : Op) { s := op_name(o); put(sb, s) }
put_fn_name := fn(in out sb : rt::StrBuf, f : ptr(mut IrFn)) { s := irfn_name(f); put(sb, s) }
put_rule := fn(in out sb : rt::StrBuf, r : VRule) { s := vrule_name(r); put(sb, s) }
put_construct := fn(in out sb : rt::StrBuf, c : Construct) { s := construct_name(c); put(sb, s) }
put_indent := fn(in out sb : rt::StrBuf, depth : usize) {
  mut d : usize = 0
  while d <= depth { put(sb, "  "); d = d + 1 }
}
## `i64 s`, `i8 u`, `bool`, `ptr` — a type with its signedness when it has one.
put_ty := fn(in out sb : rt::StrBuf, t : Kty, s : Sgn) {
  put_kty(sb, t)
  if not sgn_is_none(s) { put(sb, " "); put_sgn(sb, s) }
}
## A function operand: the callee's name when the program holds it, else its index.
put_fn_opnd := fn(in out sb : rt::StrBuf, p : IrProg, v : i64) {
  held := v >= 0 and usize(v) < prog_len(p)
  if held {
    put(sb, "@")
    put_fn_name(sb, prog_fn(p, FnId(usize(v))))
    return
  }
  put(sb, "@f")
  put_i(sb, v)
}
## A symbol operand: `@<name>` when the program holds it, else its index.
put_sym_opnd := fn(in out sb : rt::StrBuf, p : IrProg, v : i64) {
  if v >= 0 and usize(v) < prog_nsyms(p) {
    nm := sym_name(p, SymId(usize(v)))
    put(sb, "@")
    put(sb, nm)
    return
  }
  put(sb, "@s")
  put_i(sb, v)
}
## An operand.
put_opnd := fn(in out sb : rt::StrBuf, p : IrProg, k : OpndK, v : i64) {
  match k {
    OkNone => { put(sb, "_") }
    OkVReg => { put(sb, "%"); put_i(sb, v) }
    OkImm => { put_i(sb, v) }
    OkFrame => { put(sb, "$"); put_i(sb, v) }
    OkSym => { put_sym_opnd(sb, p, v) }
    OkFn => { put_fn_opnd(sb, p, v) }
    OkLabel => { put(sb, "L"); put_i(sb, v) }
  }
}
put_a := fn(in out sb : rt::StrBuf, p : IrProg, ip : ptr(mut IrInst)) { put_opnd(sb, p, i_ak(ip), i_av(ip)) }
put_b := fn(in out sb : rt::StrBuf, p : IrProg, ip : ptr(mut IrInst)) { put_opnd(sb, p, i_bk(ip), i_bv(ip)) }
## `%d = ` when the instruction defines a vreg.
put_def := fn(in out sb : rt::StrBuf, p : IrProg, ip : ptr(mut IrInst)) {
  if not opndk_is_none(i_dk(ip)) { put_opnd(sb, p, i_dk(ip), i_dv(ip)); put(sb, " = ") }
}
## `.chk`, `.s`, … — the attributes an op spells, in a fixed order: predicate, mode, signedness.
put_attrs := fn(in out sb : rt::StrBuf, ip : ptr(mut IrInst)) {
  if not cc_is_none(i_cc(ip)) { put(sb, "."); put_cc(sb, i_cc(ip)) }
  if not mode_is_none(i_md(ip)) { put(sb, "."); put_mode(sb, i_md(ip)) }
  if not sgn_is_none(i_sg(ip)) { put(sb, "."); put_sgn(sb, i_sg(ip)) }
}
## `[a + off]` — a memory operand.
put_mem := fn(in out sb : rt::StrBuf, p : IrProg, ip : ptr(mut IrInst)) {
  put(sb, "[")
  put_a(sb, p, ip)
  put(sb, " + ")
  put_i(sb, i_off(ip))
  put(sb, "]")
}
## The call argument run `(%x, %y)` from the operand pool.
put_args := fn(in out sb : rt::StrBuf, f : ptr(mut IrFn), ip : ptr(mut IrInst)) {
  put(sb, "(")
  mut j : usize = 0
  n := i_n(ip)
  base := i_pool(ip)
  while j < n {
    if j != 0 { put(sb, ", ") }
    put(sb, "%")
    put_u(sb, pool_get(f, base + j))
    j = j + 1
  }
  put(sb, ")")
}
## The trailing location and trap kind.
put_tail := fn(in out sb : rt::StrBuf, ip : ptr(mut IrInst)) {
  if i_proven(ip) { put(sb, "  !proven") }
  if i_has_span(ip) { put(sb, "  @"); put_u(sb, i_span(ip)) }
  put(sb, "\n")
}

## A region opener. Its own function: a variant `match` nested in another `match`'s arm is a form the
## frozen seed miscompiles (strict_forms.md §8).
put_open := fn(in out sb : rt::StrBuf, p : IrProg, ip : ptr(mut IrInst), r : RegionK) {
  put_op(sb, i_op(ip))
  match r {
    RkBlock | RkLoop => { put(sb, " L"); put_u(sb, i_lbl(ip)) }
    RkIf => { put(sb, " "); put_a(sb, p, ip) }
    RkUnch | RkNone => {}
  }
  put(sb, " {")
}
## Does a line of this class close a region before it prints (`else`, `end`), and open one after it
## prints (`block`, `loop`, `if`, `unchecked`, `else`)?
class_dedents := fn(c : OpClass) -> bool {
  match c {
    ClElse | ClEnd => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}
class_opens := fn(c : OpClass) -> bool {
  match c {
    ClOpen | ClElse => { true }
    ClEnd | ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn
      | ClConv | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}

## The body of one instruction line (after the indent), by class.
put_inst := fn(in out sb : rt::StrBuf, p : IrProg, f : ptr(mut IrFn), ip : ptr(mut IrInst)) {
  o : Op = i_op(ip)
  match op_class(o) {
    ClConst | ClMov | ClIntBin | ClIntUn | ClFBin | ClFUn | ClBSwap | ClCmp | ClFCmp => {
      put_def(sb, p, ip)
      put_op(sb, o)
      put_attrs(sb, ip)
      put(sb, " ")
      put_kty(sb, i_ty(ip))
      put(sb, " ")
      put_a(sb, p, ip)
      if not opndk_is_none(i_bk(ip)) { put(sb, ", "); put_b(sb, p, ip) }
      if not trap_is_none(i_tk(ip)) { put(sb, " "); put_trap(sb, i_tk(ip)) }
    }
    ClAddr => { put_def(sb, p, ip); put_op(sb, o); put(sb, " "); put_a(sb, p, ip) }
    ClWidth | ClTrunc | ClConv => {
      put_def(sb, p, ip)
      put_op(sb, o)
      put_attrs(sb, ip)
      put(sb, " ")
      put_kty(sb, i_ty(ip))
      put(sb, " <- ")
      put_kty(sb, i_from(ip))
      put(sb, " ")
      put_a(sb, p, ip)
      if not trap_is_none(i_tk(ip)) { put(sb, " "); put_trap(sb, i_tk(ip)) }
    }
    ClLoad => { put_def(sb, p, ip); put(sb, "load"); put_attrs(sb, ip); put(sb, " "); put_kty(sb, i_ty(ip)); put(sb, " "); put_mem(sb, p, ip) }
    ClStore => { put(sb, "store "); put_kty(sb, i_ty(ip)); put(sb, " "); put_mem(sb, p, ip); put(sb, ", "); put_b(sb, p, ip) }
    ClMem => {
      put_op(sb, o)
      put(sb, " ")
      put_a(sb, p, ip)
      if not opndk_is_none(i_bk(ip)) { put(sb, ", "); put_b(sb, p, ip) }
      put(sb, ", ")
      put_u(sb, i_n(ip))
    }
    ClGep => { put_def(sb, p, ip); put(sb, "gep "); put_a(sb, p, ip); put(sb, ", "); put_b(sb, p, ip); put(sb, ", "); put_i(sb, i_off(ip)) }
    ClBound => { put(sb, "bound "); put_a(sb, p, ip); put(sb, ", "); put_b(sb, p, ip); put(sb, " "); put_trap(sb, i_tk(ip)) }
    ClCall => { put_def(sb, p, ip); put_op(sb, o); put(sb, " "); put_a(sb, p, ip); put_args(sb, f, ip) }
    ClOpen => { put_open(sb, p, ip, op_region(o)) }
    ClElse => { put(sb, "} else {") }
    ClEnd => { put(sb, "}") }
    ClBr => {
      put_op(sb, o)
      if not opndk_is_none(i_ak(ip)) { put(sb, " "); put_a(sb, p, ip) }
      put(sb, " L")
      put_u(sb, i_lbl(ip))
    }
    ClSwitch => {
      put(sb, "switch ")
      put_a(sb, p, ip)
      put(sb, " [")
      mut j : usize = 0
      while j < i_n(ip) {
        if j != 0 { put(sb, ", ") }
        put_u(sb, pool_get(f, i_pool(ip) + j * 2))
        put(sb, " -> L")
        put_u(sb, pool_get(f, i_pool(ip) + j * 2 + 1))
        j = j + 1
      }
      put(sb, "] default L")
      put_u(sb, i_lbl(ip))
    }
    ClRet => { put(sb, "ret"); if not opndk_is_none(i_ak(ip)) { put(sb, " "); put_a(sb, p, ip) } }
    ClTrap => {
      put_op(sb, o)
      if not opndk_is_none(i_ak(ip)) { put(sb, " "); put_a(sb, p, ip) }
      put(sb, " ")
      put_trap(sb, i_tk(ip))
    }
  }
}

## Print one function: its signature, its frame objects, then its instructions.
pub print_fn := fn(in out sb : rt::StrBuf, p : IrProg, f : ptr(mut IrFn)) {
  put(sb, "fn ")
  put_fn_name(sb, f)
  put(sb, "(")
  mut i : usize = 0
  np := fn_nparams(f)
  while i < np {
    if i != 0 { put(sb, ", ") }
    put(sb, "%")
    put_u(sb, i)
    put(sb, " : ")
    pvt : Kty = vreg_ty(f, i)
    pvs : Sgn = vreg_sg(f, i)
    put_ty(sb, pvt, pvs)
    i = i + 1
  }
  put(sb, ")")
  if fn_has_ret(f) {
    rty : Kty = fn_ret_ty(f)
    rsg : Sgn = fn_ret_sg(f)
    put(sb, " -> ")
    put_ty(sb, rty, rsg)
  }
  put(sb, " {\n")
  mut k : usize = 0
  while k < fn_nframes(f) {
    put(sb, "  $")
    put_u(sb, k)
    put(sb, " : frame ")
    put_u(sb, frame_bytes(f, k))
    put(sb, " align ")
    put_u(sb, frame_align_of(f, k))
    put(sb, "\n")
    k = k + 1
  }
  mut depth : usize = 0
  mut j : usize = 0
  n := fn_ninst(f)
  while j < n {
    ip := fn_inst(f, j)
    if class_dedents(op_class(i_op(ip))) and depth > 0 { depth = depth - 1 }
    put_indent(sb, depth)
    put_inst(sb, p, f, ip)
    put_tail(sb, ip)
    if class_opens(op_class(i_op(ip))) { depth = depth + 1 }
    j = j + 1
  }
  put(sb, "}\n")
}

## ───────────────────────────── the verifier (docs/ir.md §5) ─────────────────────────────
##
## `verify_fn` answers the FIRST rule a function breaks (`VOk` when it breaks none) and leaves the index
## of the offending instruction in `V_AT` (the instruction count for a rule broken at the end of the
## body). A failure is a located internal error, never emitted code: `report_verify` prints
## `alatyr: internal: IR verify <rule> in <function> at inst <n>`.
##
## What each rule checks here:
##   V1 types            every defined vreg has the op's result type; every operand has the type its op
##                        takes; an op that yields no value defines none; a moded op carries a mode.
##   V2 kernel only      every vreg's type is a kernel type (`KNone` is refused), an integer vreg carries
##                        `s`/`u`, and a non-integer vreg carries none.
##   V3 canonical narrow an op producing a narrow integer is one of the canonical-preserving ops, and a
##                        narrow `const` is in range for its width and sign.
##   V4 signedness       a signedness-dependent op spells `s`/`u` and it agrees with its operands; integer
##                        arithmetic never mixes signedness (only `ext`/`fit`/`bits` change it).
##   V5 definite assign  every vreg read is assigned on every path reaching it (structured forward flow).
##   V6 memory           a frame object named by an access exists and the access lies inside it.
##   V7 control          `br` targets an enclosing `block`/`loop`; labels are unique; nothing follows a
##                        terminator; regions nest; a function with a result returns or traps on every path.
##   V8 calls            a call of a function of this program matches its arity, parameter types and result.
##   V9 traps            every `trap`, `trap_if`, `bound`, `fit` and `chk` op names a kind and a span.
##   V10 checked scope   no `chk` op inside `unchecked`; `hw` only inside it; `wrap` only inside it or proven.
mut V_AT : usize = 0

## ── operand checks ──
vreg_in := fn(f : ptr(mut IrFn), v : i64) -> bool { v >= 0 and usize(v) < fn_nvregs(f) }
## A VALUE operand of type `ty`: a vreg of that type, or an immediate of an integer, bool or pointer type.
val_ok := fn(f : ptr(mut IrFn), k : OpndK, v : i64, ty : Kty) -> bool {
  match k {
    OkVReg => { vreg_in(f, v) and kty_eq(vreg_ty(f, usize(v)), ty) }
    OkImm => { kty_is_int(ty) or kty_is_bool(ty) or kty_is_ptr(ty) }
    OkNone | OkFrame | OkSym | OkFn | OkLabel => { false }
  }
}
## An ADDRESS operand: a `ptr` vreg, a frame object, or a symbol.
addr_ok := fn(f : ptr(mut IrFn), k : OpndK, v : i64) -> bool {
  match k {
    OkVReg => { vreg_in(f, v) and kty_is_ptr(vreg_ty(f, usize(v))) }
    OkFrame => { v >= 0 and usize(v) < fn_nframes(f) }
    OkSym => { true }
    OkNone | OkImm | OkFn | OkLabel => { false }
  }
}
## The signedness an operand contributes: a vreg's own; an immediate adopts `dflt` (the op's).
opnd_sg := fn(f : ptr(mut IrFn), k : OpndK, v : i64, dflt : Sgn) -> Sgn {
  if opndk_is_vreg(k) and vreg_in(f, v) { return vreg_sg(f, usize(v)) }
  dflt
}
dst_ok := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), ty : Kty) -> bool {
  opndk_is_vreg(i_dk(ip)) and vreg_in(f, i_dv(ip)) and kty_eq(vreg_ty(f, usize(i_dv(ip))), ty)
}
no_dst := fn(ip : ptr(mut IrInst)) -> bool { opndk_is_none(i_dk(ip)) }
a_val := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), ty : Kty) -> bool { val_ok(f, i_ak(ip), i_av(ip), ty) }
b_val := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), ty : Kty) -> bool { val_ok(f, i_bk(ip), i_bv(ip), ty) }
## The result vreg's signedness.
dst_sg := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> Sgn {
  k : OpndK = i_dk(ip)
  none : Sgn = Sgn.SgNone
  opnd_sg(f, k, i_dv(ip), none)
}
is_shift := fn(o : Op) -> bool {
  match o {
    OpShl | OpShr | OpRotl | OpRotr => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv
      | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep
      | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr
      | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
rule_if := fn(bad : bool, r : VRule) -> VRule {
  if bad { return r }
  VRule.VOk
}

## ── V1: per-class operand and result types ──
## `copy` (two addresses), as against `zero` (one).
op_is_copy := fn(o : Op) -> bool {
  match o {
    OpCopy => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
      | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt
      | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF
      | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpZero | OpGep | OpBound
      | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd
      | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## `br_if` (a condition), as against `br`.
op_is_brif := fn(o : Op) -> bool {
  match o {
    OpBrIf => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
      | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt
      | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF
      | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep
      | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse
      | OpUnch | OpEnd | OpBr | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## `trap_if` (a condition), as against `trap`.
op_is_trapif := fn(o : Op) -> bool {
  match o {
    OpTrapIf => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv
      | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt
      | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF
      | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep
      | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse
      | OpUnch | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap => { false }
  }
}
v1_conv := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  t : Kty = i_ty(ip)
  s : Kty = i_from(ip)
  if not dst_ok(f, ip, t) or not a_val(f, ip, s) { return false }
  match i_op(ip) {
    OpIToF => { kty_is_int(s) and kty_is_float(t) }
    OpFToI => { kty_is_float(s) and kty_is_int(t) }
    OpFExt => { kty_eq(s, Kty.KF32) and kty_eq(t, Kty.KF64) }
    OpFDemote => { kty_eq(s, Kty.KF64) and kty_eq(t, Kty.KF32) }
    OpBits => { kty_bytes(s) == kty_bytes(t) and (kty_is_float(s) != kty_is_float(t)) }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp
      | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound
      | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr | OpBrIf
      | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
v1_addr := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  if not dst_ok(f, ip, Kty.KPtr) { return false }
  match i_op(ip) {
    OpAddrFrame => { opndk_is_frame(i_ak(ip)) and addr_ok(f, i_ak(ip), i_av(ip)) }
    OpAddrSym => { addr_ok(f, i_ak(ip), i_av(ip)) and not opndk_is_vreg(i_ak(ip)) }
    OpFnAddr => { opndk_is_fn(i_ak(ip)) or addr_ok(f, i_ak(ip), i_av(ip)) }
    OpConst | OpFConst | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl
      | OpShr | OpRotl | OpRotr | OpExt | OpFit | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg
      | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap | OpCopy | OpZero | OpGep | OpBound
      | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch | OpEnd | OpBr | OpBrIf
      | OpSwitch | OpRet | OpTrap | OpTrapIf => { false }
  }
}
## A moded op must spell a mode; any other op must not.
v1_mode := fn(ip : ptr(mut IrInst)) -> bool {
  m : Mode = i_md(ip)
  has := mode_is_wrap(m) or mode_is_chk(m) or mode_is_hw(m)
  has == op_has_mode(i_op(ip))
}
v1_class := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), c : OpClass) -> bool {
  t : Kty = i_ty(ip)
  match c {
    ClConst => {
      if kty_is_float(t) { return dst_ok(f, ip, t) and opndk_is_none(i_bk(ip)) }
      dst_ok(f, ip, t) and val_ok(f, i_ak(ip), i_av(ip), t) and not opndk_is_vreg(i_ak(ip))
    }
    ClAddr => { v1_addr(f, ip) }
    ClMov => { dst_ok(f, ip, t) and a_val(f, ip, t) and not kty_is_none(t) }
    ClIntBin => {
      if is_shift(i_op(ip)) { return kty_is_int(t) and dst_ok(f, ip, t) and a_val(f, ip, t) and b_val(f, ip, Kty.KI64) }
      kty_is_int(t) and dst_ok(f, ip, t) and a_val(f, ip, t) and b_val(f, ip, t)
    }
    ClIntUn => { kty_is_int(t) and dst_ok(f, ip, t) and a_val(f, ip, t) }
    ClWidth => { kty_is_int(t) and kty_is_int(i_from(ip)) and dst_ok(f, ip, t) and a_val(f, ip, i_from(ip)) }
    ClTrunc => { kty_is_bool(t) and kty_is_int(i_from(ip)) and dst_ok(f, ip, t) and a_val(f, ip, i_from(ip)) }
    ClCmp => {
      scalar := kty_is_int(t) or kty_is_bool(t) or kty_is_ptr(t)
      scalar and not cc_is_none(i_cc(ip)) and dst_ok(f, ip, Kty.KBool) and a_val(f, ip, t) and b_val(f, ip, t)
    }
    ClFCmp => { kty_is_float(t) and not cc_is_none(i_cc(ip)) and dst_ok(f, ip, Kty.KBool) and a_val(f, ip, t) and b_val(f, ip, t) }
    ClFBin => { kty_is_float(t) and dst_ok(f, ip, t) and a_val(f, ip, t) and b_val(f, ip, t) }
    ClFUn => { kty_is_float(t) and dst_ok(f, ip, t) and a_val(f, ip, t) }
    ClConv => { v1_conv(f, ip) }
    ClLoad => { not kty_is_none(t) and dst_ok(f, ip, t) and addr_ok(f, i_ak(ip), i_av(ip)) }
    ClStore => { not kty_is_none(t) and no_dst(ip) and addr_ok(f, i_ak(ip), i_av(ip)) and b_val(f, ip, t) }
    ClBSwap => { kty_is_int(t) and dst_ok(f, ip, t) and a_val(f, ip, t) }
    ClMem => {
      if not no_dst(ip) or not addr_ok(f, i_ak(ip), i_av(ip)) { return false }
      if op_is_copy(i_op(ip)) { return addr_ok(f, i_bk(ip), i_bv(ip)) }
      opndk_is_none(i_bk(ip))
    }
    ClGep => { dst_ok(f, ip, Kty.KPtr) and a_val(f, ip, Kty.KPtr) and b_val(f, ip, Kty.KI64) }
    ClBound => { no_dst(ip) and a_val(f, ip, Kty.KI64) and b_val(f, ip, Kty.KI64) }
    ClCall => { true }
    ClOpen => {
      if not no_dst(ip) { return false }
      if region_is_if(op_region(i_op(ip))) { return a_val(f, ip, Kty.KBool) }
      opndk_is_none(i_ak(ip))
    }
    ClElse | ClEnd => { no_dst(ip) and opndk_is_none(i_ak(ip)) }
    ClBr => {
      if not no_dst(ip) { return false }
      if op_is_brif(i_op(ip)) { return a_val(f, ip, Kty.KBool) }
      opndk_is_none(i_ak(ip))
    }
    ClSwitch => { no_dst(ip) and opndk_is_vreg(i_ak(ip)) and vreg_in(f, i_av(ip)) and kty_is_int(vreg_ty(f, usize(i_av(ip)))) }
    ClRet => {
      if not no_dst(ip) { return false }
      if fn_has_ret(f) { return a_val(f, ip, fn_ret_ty(f)) }
      opndk_is_none(i_ak(ip))
    }
    ClTrap => {
      if not no_dst(ip) { return false }
      if op_is_trapif(i_op(ip)) { return a_val(f, ip, Kty.KBool) }
      opndk_is_none(i_ak(ip))
    }
  }
}

## ── V3: canonical narrow form ──
## The inclusive range a narrow `const` of `bytes` width and signedness `s` may hold.
const_fits := fn(x : i64, bytes : u64, s : Sgn) -> bool {
  if bytes >= 8 { return true }
  bits : u64 = bytes * 8
  span : i64 = i64(shl(u64(1), bits))
  match s {
    SgS => { half : i64 = span / 2; x >= 0 - half and x < half }
    SgU | SgNone => { x >= 0 and x < span }
  }
}
v3_inst := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  if not opndk_is_vreg(i_dk(ip)) or not vreg_in(f, i_dv(ip)) { return true }
  t : Kty = vreg_ty(f, usize(i_dv(ip)))
  if not kty_is_narrow(t) { return true }
  if not op_keeps_canonical(i_op(ip)) { return false }
  match op_class(i_op(ip)) {
    ClConst => { const_fits(i_av(ip), kty_bytes(t), vreg_sg(f, usize(i_dv(ip)))) }
    ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv | ClLoad
      | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClElse | ClEnd | ClBr | ClSwitch | ClRet
      | ClTrap => { true }
  }
}

## ── V4: signedness ──
sg_known := fn(s : Sgn) -> bool { not sgn_is_none(s) }
## An op that needs a sign spells one, and it is `want`.
sg_spelled := fn(ip : ptr(mut IrInst), want : Sgn) -> bool { sg_known(i_sg(ip)) and sgn_eq(i_sg(ip), want) }
## An immediate operand has no signedness of its own: it takes the one `dflt` names (the result's for
## arithmetic, the other operand's for a compare, the spelled one for a width or conversion op).
a_sgd := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), dflt : Sgn) -> Sgn { k : OpndK = i_ak(ip); opnd_sg(f, k, i_av(ip), dflt) }
b_sgd := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), dflt : Sgn) -> Sgn { k : OpndK = i_bk(ip); opnd_sg(f, k, i_bv(ip), dflt) }
v4_intbin := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  sd : Sgn = dst_sg(f, ip)
  if not sgn_eq(a_sgd(f, ip, sd), sd) { return false }
  if not is_shift(i_op(ip)) and not sgn_eq(b_sgd(f, ip, sd), sd) { return false }
  if op_needs_sign(i_op(ip)) or mode_is_chk(i_md(ip)) { return sg_spelled(ip, sd) }
  true
}
## The signedness a compare works at: its first vreg operand's.
cmp_sg := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> Sgn {
  if opndk_is_vreg(i_ak(ip)) { return a_sgd(f, ip, i_sg(ip)) }
  b_sgd(f, ip, i_sg(ip))
}
v4_class := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), c : OpClass) -> bool {
  match c {
    ClIntBin => { v4_intbin(f, ip) }
    ClIntUn => {
      sd : Sgn = dst_sg(f, ip)
      if not sgn_eq(a_sgd(f, ip, sd), sd) { return false }
      if mode_is_chk(i_md(ip)) { return sg_spelled(ip, sd) }
      true
    }
    ClMov | ClBSwap => { sd2 : Sgn = dst_sg(f, ip); sgn_eq(a_sgd(f, ip, sd2), sd2) }
    ClConst => {
      if kty_is_int(i_ty(ip)) { return sg_spelled(ip, dst_sg(f, ip)) }
      sgn_is_none(i_sg(ip))
    }
    ClLoad => {
      if kty_is_int(i_ty(ip)) { return sg_spelled(ip, dst_sg(f, ip)) }
      sgn_is_none(i_sg(ip))
    }
    ClWidth => { sg_spelled(ip, a_sgd(f, ip, i_sg(ip))) }
    ClCmp => {
      if not kty_is_int(i_ty(ip)) { return sgn_is_none(i_sg(ip)) }
      sc : Sgn = cmp_sg(f, ip)
      if not sgn_eq(a_sgd(f, ip, sc), sc) or not sgn_eq(b_sgd(f, ip, sc), sc) { return false }
      if cc_is_ordering(i_cc(ip)) { return sg_spelled(ip, sc) }
      sgn_is_none(i_sg(ip)) or sgn_eq(i_sg(ip), sc)
    }
    ClConv => { v4_conv(f, ip) }
    ClAddr | ClTrunc | ClFCmp | ClFBin | ClFUn | ClStore | ClMem | ClGep | ClBound | ClCall | ClOpen | ClElse | ClEnd
      | ClBr | ClSwitch | ClRet | ClTrap => { true }
  }
}
v4_conv := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  match i_op(ip) {
    OpIToF => { sg_spelled(ip, a_sgd(f, ip, i_sg(ip))) }
    OpFToI => { sg_spelled(ip, dst_sg(f, ip)) }
    OpFExt | OpFDemote | OpBits | OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub
      | OpMul | OpDiv | OpRem | OpAnd | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpFit
      | OpTrunc | OpCmp | OpFCmp | OpFAdd | OpFSub | OpFMul | OpFDiv | OpFNeg | OpLoad | OpStore | OpBSwap | OpCopy
      | OpZero | OpGep | OpBound | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet | OpTrap | OpTrapIf => { true }
  }
}

## ── V6: memory ──
## A frame-object access `[ $k + off ]` of `width` bytes lies inside object `k`.
frame_access_ok := fn(f : ptr(mut IrFn), k : OpndK, v : i64, off : i64, width : u64) -> bool {
  if not opndk_is_frame(k) { return true }
  if v < 0 or usize(v) >= fn_nframes(f) { return false }
  if off < 0 { return false }
  u64(off) + width <= u64(frame_bytes(f, usize(v)))
}
v6_class := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), c : OpClass) -> bool {
  match c {
    ClLoad | ClStore => {
      w : u64 = kty_bytes(i_ty(ip))
      wok := w == 1 or w == 2 or w == 4 or w == 8
      wok and frame_access_ok(f, i_ak(ip), i_av(ip), i_off(ip), w)
    }
    ClMem => {
      n : u64 = u64(i_n(ip))
      frame_access_ok(f, i_ak(ip), i_av(ip), 0, n) and frame_access_ok(f, i_bk(ip), i_bv(ip), 0, n)
    }
    ClAddr => { frame_access_ok(f, i_ak(ip), i_av(ip), 0, 0) }
    ClConst | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv | ClBSwap
      | ClGep | ClBound | ClCall | ClOpen | ClElse | ClEnd | ClBr | ClSwitch | ClRet | ClTrap => { true }
  }
}

## ── V8: calls ──
## Argument `j`'s vreg of the call `ip` (from the operand pool).
call_arg := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), j : usize) -> usize { pool_get(f, i_pool(ip) + j) }
v8_args_are_vregs := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  if i_pool(ip) + i_n(ip) > pool_len(f) { return false }
  mut j : usize = 0
  while j < i_n(ip) {
    if call_arg(f, ip, j) >= fn_nvregs(f) { return false }
    j = j + 1
  }
  true
}
v8_call := fn(p : IrProg, f : ptr(mut IrFn), ip : ptr(mut IrInst)) -> bool {
  if not v8_args_are_vregs(f, ip) { return false }
  if not opndk_is_fn(i_ak(ip)) { return true }
  ci := i_av(ip)
  if ci < 0 or usize(ci) >= prog_len(p) { return false }
  g := prog_fn(p, FnId(usize(ci)))
  if i_n(ip) != fn_nparams(g) { return false }
  mut j : usize = 0
  while j < i_n(ip) {
    av := call_arg(f, ip, j)
    at : Kty = vreg_ty(f, av)
    pt : Kty = vreg_ty(g, j)
    asg : Sgn = vreg_sg(f, av)
    psg : Sgn = vreg_sg(g, j)
    if not kty_eq(at, pt) or not sgn_eq(asg, psg) { return false }
    j = j + 1
  }
  if fn_has_ret(g) {
    gsg : Sgn = fn_ret_sg(g)
    dsg : Sgn = dst_sg(f, ip)
    return dst_ok(f, ip, fn_ret_ty(g)) and sgn_eq(dsg, gsg)
  }
  no_dst(ip)
}

## ── V9: traps are located ──
v9_needs := fn(ip : ptr(mut IrInst)) -> bool {
  if mode_is_chk(i_md(ip)) { return true }
  match i_op(ip) {
    OpTrap | OpTrapIf | OpBound | OpFit => { true }
    OpConst | OpFConst | OpAddrSym | OpAddrFrame | OpFnAddr | OpMov | OpAdd | OpSub | OpMul | OpDiv | OpRem | OpAnd
      | OpOr | OpXor | OpNot | OpNeg | OpShl | OpShr | OpRotl | OpRotr | OpExt | OpTrunc | OpCmp | OpFCmp | OpFAdd
      | OpFSub | OpFMul | OpFDiv | OpFNeg | OpIToF | OpFToI | OpFExt | OpFDemote | OpBits | OpLoad | OpStore | OpBSwap
      | OpCopy | OpZero | OpGep | OpCall | OpCallInd | OpCallC | OpSyscall | OpBlock | OpLoop | OpIf | OpElse | OpUnch
      | OpEnd | OpBr | OpBrIf | OpSwitch | OpRet => { false }
  }
}
v9_inst := fn(ip : ptr(mut IrInst)) -> bool {
  if not v9_needs(ip) { return true }
  not trap_is_none(i_tk(ip)) and i_has_span(ip)
}

## ── V10: checked scope ──
v10_inst := fn(ip : ptr(mut IrInst), unch : bool) -> bool {
  if not op_has_mode(i_op(ip)) { return true }
  m : Mode = i_md(ip)
  if mode_is_chk(m) { return not unch }
  if mode_is_hw(m) { return unch }
  if mode_is_wrap(m) { return unch or i_proven(ip) }
  true
}

## Every per-instruction rule, in rule order. `unch` is whether the instruction sits in an `unchecked`
## region (V10 needs the structure, which `verify_fn` tracks).
check_inst := fn(p : IrProg, f : ptr(mut IrFn), ip : ptr(mut IrInst), unch : bool) -> VRule {
  c : OpClass = op_class(i_op(ip))
  if not v1_mode(ip) { return VRule.V1 }
  if not v1_class(f, ip, c) { return VRule.V1 }
  if not v3_inst(f, ip) { return VRule.V3 }
  if not v4_class(f, ip, c) { return VRule.V4 }
  if not v6_class(f, ip, c) { return VRule.V6 }
  if class_is_call(c) and not v8_call(p, f, ip) { return VRule.V8 }
  if not v9_inst(ip) { return VRule.V9 }
  if not v10_inst(ip, unch) { return VRule.V10 }
  VRule.VOk
}
class_is_call := fn(c : OpClass) -> bool {
  match c {
    ClCall => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClOpen | ClElse | ClEnd | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}

## ── V2: every vreg's type is a kernel type with the signedness its kind carries ──
v2_fn := fn(f : ptr(mut IrFn)) -> bool {
  mut v : usize = 0
  n := fn_nvregs(f)
  while v < n {
    t : Kty = vreg_ty(f, v)
    if kty_is_none(t) { return false }
    if kty_is_int(t) == sgn_is_none(vreg_sg(f, v)) { return false }
    v = v + 1
  }
  if fn_has_ret(f) {
    rt0 : Kty = fn_ret_ty(f)
    if kty_is_none(rt0) or kty_is_int(rt0) == sgn_is_none(fn_ret_sg(f)) { return false }
  }
  true
}

## ── the structural walk: V5 (definite assignment), V7 (control) and the `unchecked` scope for V10 ──
##
## Definite assignment is a structured forward dataflow over one bit per vreg (a word per vreg, in a
## block of the verifier's arena). `reach` is whether the current point is reachable; at an
## unreachable point nothing is checked (the set there is "everything"). A region records what it
## needs on a stack of `RFrame`s:
##   block  — the meet of the states at every `br` to it (its exits);
##   loop   — nothing: `br` restarts it, and falling off its end continues after it (wasm's rule);
##   if     — the state at its entry (the else-arm starts from it) and, after `else`, the then-arm's end;
##   unchecked — nothing but the scope flag.
## The meet of two states is the intersection of their sets when both are reachable, the reachable
## one's set otherwise.
RFrame := struct {
  rk : RegionK, lbl : usize, unch : bool,
  entry : ptr(mut u8), entry_reach : bool,
  other : ptr(mut u8), other_reach : bool, seen_else : bool,
}
## unchecked-ok: `rframe_ptr` reads back a word `verify_fn` pushed from a `ptr(mut RFrame)`.
rframe_ptr := fn(w : usize) -> ptr(mut RFrame) { unchecked bitcast(ptr(mut RFrame), w) }
rf_rk := fn(fp : ptr(mut RFrame)) -> RegionK { fr : RFrame = deref(fp); fr.rk }
rf_lbl := fn(fp : ptr(mut RFrame)) -> usize { fr : RFrame = deref(fp); fr.lbl }
rf_unch := fn(fp : ptr(mut RFrame)) -> bool { fr : RFrame = deref(fp); fr.unch }
rf_entry := fn(fp : ptr(mut RFrame)) -> ptr(mut u8) { fr : RFrame = deref(fp); fr.entry }
rf_entry_reach := fn(fp : ptr(mut RFrame)) -> bool { fr : RFrame = deref(fp); fr.entry_reach }
rf_other := fn(fp : ptr(mut RFrame)) -> ptr(mut u8) { fr : RFrame = deref(fp); fr.other }
rf_other_reach := fn(fp : ptr(mut RFrame)) -> bool { fr : RFrame = deref(fp); fr.other_reach }
rf_seen_else := fn(fp : ptr(mut RFrame)) -> bool { fr : RFrame = deref(fp); fr.seen_else }

## One definite-assignment set: `n` words, all clear.
vda_new := fn(in out a : rt::Arena, n : usize) -> ptr(mut u8) {
  mut w := n
  if w == 0 { w = 1 }
  d := bump_ptr(a, w * 8)
  mut i : usize = 0
  while i < w { deref(word_at(d, i)) = 0; i = i + 1 }
  d
}
vda_has := fn(d : ptr(mut u8), i : usize) -> bool { deref(word_at(d, i)) != 0 }
vda_set := fn(d : ptr(mut u8), i : usize) { deref(word_at(d, i)) = 1 }
vda_copy := fn(in out a : rt::Arena, s : ptr(mut u8), n : usize) -> ptr(mut u8) {
  d := vda_new(a, n)
  mut i : usize = 0
  while i < n { deref(word_at(d, i)) = deref(word_at(s, i)); i = i + 1 }
  d
}
## `into &= other`, in place.
vda_meet := fn(into : ptr(mut u8), other : ptr(mut u8), n : usize) {
  mut i : usize = 0
  while i < n {
    if deref(word_at(other, i)) == 0 { deref(word_at(into, i)) = 0 }
    i = i + 1
  }
}

## Is operand (k, v) — when it is a vreg — assigned in `cur`?
read_ok := fn(k : OpndK, v : i64, cs : ptr(mut u8)) -> bool {
  if not opndk_is_vreg(k) { return true }
  vda_has(cs, usize(v))
}
## V5 — every vreg the instruction READS is assigned: `a` and `b`, a call's or a switch's pool run.
reads_ok := fn(f : ptr(mut IrFn), ip : ptr(mut IrInst), cs : ptr(mut u8)) -> bool {
  if not read_ok(i_ak(ip), i_av(ip), cs) or not read_ok(i_bk(ip), i_bv(ip), cs) { return false }
  if class_is_call(op_class(i_op(ip))) {
    mut j : usize = 0
    while j < i_n(ip) {
      if not vda_has(cs, call_arg(f, ip, j)) { return false }
      j = j + 1
    }
  }
  true
}

## The innermost open region labelled `l`, searched outward — `br`'s target (V7).
find_label := fn(stack : ptr(mut WBuf), l : usize) -> Option(u64) {
  mut i := wb_len(stack)
  while i > 0 {
    i = i - 1
    fp := rframe_ptr(wb_get(stack, i))
    if region_has_label(rf_rk(fp)) and rf_lbl(fp) == l { return Option(u64).Some(u64(i)) }
  }
  Option(u64).None
}
## A `br` (or a `switch` arm) to label `l` from state (state, reach): a block records the state as one
## of its exits. Answers whether the target is an enclosing labelled region.
branch_to := fn(stack : ptr(mut WBuf), in out a : rt::Arena, l : usize, cs : ptr(mut u8), reach : bool, n : usize) -> bool {
  hit : Option(u64) = find_label(stack, l)
  match hit {
    Some(i) => {
      fp := rframe_ptr(wb_get(stack, usize(i)))
      if reach and not region_is_loop(rf_rk(fp)) {
        if rf_other_reach(fp) { vda_meet(rf_other(fp), cs, n) } else {
          cp := vda_copy(a, cs, n)
          deref(fp).other = cp
          deref(fp).other_reach = true
        }
      }
      true
    }
    None => { false }
  }
}

## The per-function verification. Answers the first broken rule, `VOk` when none is.
pub verify_fn := fn(p : IrProg, f : ptr(mut IrFn), in out a : rt::Arena) -> VRule {
  V_AT = 0
  if not v2_fn(f) { return VRule.V2 }
  nv := fn_nvregs(f)
  ni := fn_ninst(f)
  nl := fn_nlabels(f)
  mut cs := vda_new(a, nv)
  mut pi : usize = 0
  while pi < fn_nparams(f) { vda_set(cs, pi); pi = pi + 1 }
  mut reach := true
  mut after_term := false
  seen := vda_new(a, nl)
  stack := wb_new(a, 8)
  mut i : usize = 0
  while i < ni {
    V_AT = i
    ip := fn_inst(f, i)
    o : Op = i_op(ip)
    c : OpClass = op_class(o)
    mut unch := false
    if wb_len(stack) > 0 { unch = rf_unch(rframe_ptr(wb_get(stack, wb_len(stack) - 1))) }
    ## V7 — nothing follows a terminator in a sequence.
    if after_term and not class_dedents(c) { return VRule.V7 }
    after_term = op_is_terminator(o)
    r := check_inst(p, f, ip, unch)
    if not vrule_is_ok(r) { return r }
    ## V5 — reads before the region/branch bookkeeping (an `if`'s condition is read at its entry).
    if reach and not reads_ok(f, ip, cs) { return VRule.V5 }
    if class_is_open(c) {
      rk : RegionK = op_region(o)
      if region_has_label(rk) {
        l := i_lbl(ip)
        if l >= nl or vda_has(seen, l) { return VRule.V7 }
        vda_set(seen, l)
      }
      ep := vda_copy(a, cs, nv)
      hp := bump_ptr(a, size(RFrame))
      ## unchecked-ok: a fresh arena block of `size(RFrame)` bytes is exactly one `RFrame` record.
      fp : ptr(mut RFrame) = unchecked bitcast(ptr(mut RFrame), hp)
      nf := RFrame(rk = rk, lbl = i_lbl(ip), unch = unch or region_is_unch(rk), entry = ep, entry_reach = reach,
                   other = ep, other_reach = false, seen_else = false)
      deref(fp) = nf
      k := wb_push(stack, a, ptr_word(hp))
    } else if class_is_else(c) {
      if wb_len(stack) == 0 { return VRule.V7 }
      fp := rframe_ptr(wb_get(stack, wb_len(stack) - 1))
      if not region_is_if(rf_rk(fp)) or rf_seen_else(fp) { return VRule.V7 }
      deref(fp).other = cs
      deref(fp).other_reach = reach
      deref(fp).seen_else = true
      cs = vda_copy(a, rf_entry(fp), nv)
      reach = rf_entry_reach(fp)
    } else if class_is_end(c) {
      if wb_len(stack) == 0 { return VRule.V7 }
      fp := rframe_ptr(wb_get(stack, wb_len(stack) - 1))
      deref(stack).len = wb_len(stack) - 1
      rk2 : RegionK = rf_rk(fp)
      ## The state the region's end meets with the fall-through: an `if` without `else` meets its entry,
      ## an `if` with one meets the then-arm's end, a block meets its exits; a loop and `unchecked` none.
      mut mo := rf_other(fp)
      mut mr := rf_other_reach(fp)
      if region_is_if(rk2) and not rf_seen_else(fp) { mo = rf_entry(fp); mr = rf_entry_reach(fp) }
      if region_is_loop(rk2) or region_is_unch(rk2) { mr = false }
      if mr {
        if reach { vda_meet(cs, mo, nv) } else { cs = vda_copy(a, mo, nv); reach = true }
      }
    } else if class_is_br(c) {
      if not branch_to(stack, a, i_lbl(ip), cs, reach, nv) { return VRule.V7 }
      if op_is_terminator(o) { reach = false }
    } else if class_is_switch(c) {
      mut j : usize = 0
      while j < i_n(ip) {
        if not branch_to(stack, a, pool_get(f, i_pool(ip) + j * 2 + 1), cs, reach, nv) { return VRule.V7 }
        j = j + 1
      }
      if not branch_to(stack, a, i_lbl(ip), cs, reach, nv) { return VRule.V7 }
      reach = false
    } else if op_is_terminator(o) {
      reach = false
    } else if opndk_is_vreg(i_dk(ip)) {
      vda_set(cs, usize(i_dv(ip)))
    }
    i = i + 1
  }
  V_AT = ni
  if wb_len(stack) != 0 { return VRule.V7 }
  if fn_has_ret(f) and reach { return VRule.V7 }
  VRule.VOk
}
class_is_open := fn(c : OpClass) -> bool {
  match c {
    ClOpen => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClElse | ClEnd | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}
class_is_else := fn(c : OpClass) -> bool {
  match c {
    ClElse => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClEnd | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}
class_is_end := fn(c : OpClass) -> bool {
  match c {
    ClEnd => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClElse | ClBr | ClSwitch | ClRet | ClTrap => { false }
  }
}
class_is_br := fn(c : OpClass) -> bool {
  match c {
    ClBr => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClElse | ClEnd | ClSwitch | ClRet | ClTrap => { false }
  }
}
class_is_switch := fn(c : OpClass) -> bool {
  match c {
    ClSwitch => { true }
    ClConst | ClAddr | ClMov | ClIntBin | ClIntUn | ClWidth | ClTrunc | ClCmp | ClFCmp | ClFBin | ClFUn | ClConv
      | ClLoad | ClStore | ClBSwap | ClMem | ClGep | ClBound | ClCall | ClOpen | ClElse | ClEnd | ClBr | ClRet | ClTrap => { false }
  }
}

## Verify every function of a program; print a located internal error for the first failure of each.
## Answers the number of functions that failed.
pub verify_prog := fn(p : IrProg, in out a : rt::Arena, in out sb : rt::StrBuf) -> usize {
  mut bad : usize = 0
  mut i : usize = 0
  while i < prog_len(p) {
    f := prog_fn(p, FnId(i))
    r := verify_fn(p, f, a)
    if not vrule_is_ok(r) {
      put(sb, "alatyr: internal: IR verify ")
      put_rule(sb, r)
      put(sb, " in ")
      put_fn_name(sb, f)
      put(sb, " at inst ")
      put_u(sb, V_AT)
      put(sb, "\n")
      bad = bad + 1
    }
    i = i + 1
  }
  bad
}

## ───────────────────────────── the builder's refusals ─────────────────────────────
##
## The builder (`ir::build`, slice 1: `docs/ir-slice-1.md` §2) is the one place a language construct
## becomes IR (§3.1). For a function it cannot build it answers `NotYet(construct, span)` naming the
## first construct outside its subset, and the target keeps its legacy emitter (§7.1 rule 1,
## function-level fallback per D7). The construct names are the AST's own variant names, so a later
## slice claims its reasons exactly (`scripts/ir_census.sh` ranks them).

## The construct a `NotYet` names.
pub Construct := enum {
  CGeneric, CEmpty, CSignature, CBodyless,
  SAssign, SWhile, SFieldAssign, SReturn, SIf, SMatch, SFor, SDerefAssign, SIndexAssign, SIndexFieldAssign,
  SFieldPathAssign, SLoop, SBreak, SContinue, SExprStmt, SCompIf, SCompFor, SCompMatch, SCompForRange,
  SUnchecked, SAllocWith,
  ENum, EBoolLit, EVar, EBin, EIf, EMatch, ECall, EStructLit, EField, EEnumLit, EAddrOf, EDeref, EStrLit,
  EArrayLit, EIndex, ETry, EFloatLit, ESlice, ECompField, EUnchecked, ELambda, EFnRef, EBitcast, ELoop,
}
pub construct_name := fn(c : Construct) -> str {
  match c {
    CGeneric => { "generic function (needs a mono instance)" }; CEmpty => { "empty body" }
    CSignature => { "signature (a parameter or result that is not a kernel scalar)" }
    CBodyless => { "a declaration with no body (`@abi(syscall)`, `@extern`: slice 2)" }
    SAssign => { "stmt Assign" }; SWhile => { "stmt While" }; SFieldAssign => { "stmt FieldAssign" }
    SReturn => { "stmt Return" }; SIf => { "stmt If" }; SMatch => { "stmt Match" }; SFor => { "stmt For" }
    SDerefAssign => { "stmt DerefAssign" }; SIndexAssign => { "stmt IndexAssign" }
    SIndexFieldAssign => { "stmt IndexFieldAssign" }; SFieldPathAssign => { "stmt FieldPathAssign" }
    SLoop => { "stmt Loop" }; SBreak => { "stmt Break" }; SContinue => { "stmt Continue" }
    SExprStmt => { "stmt ExprStmt" }; SCompIf => { "stmt CompIf" }; SCompFor => { "stmt CompFor" }
    SCompMatch => { "stmt CompMatch" }; SCompForRange => { "stmt CompForRange" }
    SUnchecked => { "stmt Unchecked" }; SAllocWith => { "stmt AllocWith" }
    ENum => { "expr Num" }; EBoolLit => { "expr BoolLit" }; EVar => { "expr Var" }; EBin => { "expr Bin" }
    EIf => { "expr If" }; EMatch => { "expr Match" }; ECall => { "expr Call" }; EStructLit => { "expr StructLit" }
    EField => { "expr Field" }; EEnumLit => { "expr EnumLit" }; EAddrOf => { "expr AddrOf" }
    EDeref => { "expr Deref" }; EStrLit => { "expr StrLit" }; EArrayLit => { "expr ArrayLit" }
    EIndex => { "expr Index" }; ETry => { "expr Try" }; EFloatLit => { "expr FloatLit" }; ESlice => { "expr Slice" }
    ECompField => { "expr CompField" }; EUnchecked => { "expr Unchecked" }; ELambda => { "expr Lambda" }
    EFnRef => { "expr FnRef" }; EBitcast => { "expr Bitcast" }; ELoop => { "expr Loop" }
  }
}

## The AST ends every list with a null link and marks an absent optional child with a null pointer.
## These two predicates are the only places this module spells that null. They cannot yet be written
## as a `match` over `Option(ptr(T))`: matching such a parameter or local and dereferencing its payload
## SIGSEGVs on x86_64 today, on `main` and on the frozen seed (#789).
## null-ok: blocked by #789 — Decl.body_stmts / Stmt.next are null-terminated AST links.
stmt_present := fn(p : ptr(mut Stmt)) -> bool { unchecked bitcast(usize, p) != 0 }
## null-ok: blocked by #789 — Decl.value, Stmt::Return's and Stmt::Break's value are null when absent.
expr_present := fn(e : ptr(Expr)) -> bool { unchecked bitcast(usize, e) != 0 }

## A source offset, unless it names no source position (a span a desugar synthesized, #523).
real_span := fn(s : usize) -> Option(u64) {
  if ast::span_is_synthetic(s) { return Option(u64).None }
  Option(u64).Some(u64(s))
}
## The leftmost source offset of an expression, when it has one.
pub expr_span := fn(e : ptr(Expr)) -> Option(u64) {
  match deref(e) {
    Expr::Num(v, s, n) => { if n == 0 { return Option(u64).None }; real_span(s) }
    Expr::BoolLit(v) => { Option(u64).None }
    Expr::Var(s, n) => { real_span(s) }
    Expr::Bin(op, l, r) => { expr_span(l) }
    Expr::If(c, t, x) => { expr_span(c) }
    Expr::Match(sc, ah) => { expr_span(sc) }
    Expr::Call(cs, cl, na, ah) => { real_span(cs) }
    Expr::StructLit(ss, sl, nf, fh) => { real_span(ss) }
    Expr::Field(b, fs, fl) => { expr_span(b) }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { real_span(es) }
    Expr::AddrOf(p) => { expr_span(p) }
    Expr::Deref(p) => { expr_span(p) }
    Expr::StrLit(s, n, lbl, ps, pn) => { real_span(s) }
    Expr::ArrayLit(n, eh) => { Option(u64).None }
    Expr::Index(b, i) => { expr_span(b) }
    Expr::Try(inner) => { expr_span(inner) }
    Expr::FloatLit(s, n) => { real_span(s) }
    Expr::Slice(b, lo, hi) => { expr_span(b) }
    Expr::CompField(b, i) => { expr_span(b) }
    Expr::Unchecked(inner) => { expr_span(inner) }
    Expr::Lambda(fnpos, ph, rts, rtl, bh, value) => { real_span(fnpos) }
    Expr::FnRef(fnpos, fs, fl) => { real_span(fnpos) }
    Expr::Bitcast(inner, ts, tl) => { real_span(ts) }
    Expr::Loop(b) => { Option(u64).None }
  }
}
pub expr_construct := fn(e : ptr(Expr)) -> Construct {
  match deref(e) {
    Expr::Num => { Construct.ENum }; Expr::BoolLit => { Construct.EBoolLit }; Expr::Var => { Construct.EVar }
    Expr::Bin => { Construct.EBin }; Expr::If => { Construct.EIf }; Expr::Match => { Construct.EMatch }
    Expr::Call => { Construct.ECall }; Expr::StructLit => { Construct.EStructLit }; Expr::Field => { Construct.EField }
    Expr::EnumLit => { Construct.EEnumLit }; Expr::AddrOf => { Construct.EAddrOf }; Expr::Deref => { Construct.EDeref }
    Expr::StrLit => { Construct.EStrLit }; Expr::ArrayLit => { Construct.EArrayLit }; Expr::Index => { Construct.EIndex }
    Expr::Try => { Construct.ETry }; Expr::FloatLit => { Construct.EFloatLit }; Expr::Slice => { Construct.ESlice }
    Expr::CompField => { Construct.ECompField }; Expr::Unchecked => { Construct.EUnchecked }
    Expr::Lambda => { Construct.ELambda }; Expr::FnRef => { Construct.EFnRef }; Expr::Bitcast => { Construct.EBitcast }
    Expr::Loop => { Construct.ELoop }
  }
}
## The statement at `h` (a non-null link).
stmt_construct := fn(h : ptr(mut Stmt)) -> Construct {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign => { Construct.SAssign }; Stmt::While => { Construct.SWhile }
    Stmt::FieldAssign => { Construct.SFieldAssign }; Stmt::Return => { Construct.SReturn }
    Stmt::If => { Construct.SIf }; Stmt::Match => { Construct.SMatch }; Stmt::For => { Construct.SFor }
    Stmt::DerefAssign => { Construct.SDerefAssign }; Stmt::IndexAssign => { Construct.SIndexAssign }
    Stmt::IndexFieldAssign => { Construct.SIndexFieldAssign }; Stmt::FieldPathAssign => { Construct.SFieldPathAssign }
    Stmt::Loop => { Construct.SLoop }; Stmt::Break => { Construct.SBreak }; Stmt::Continue => { Construct.SContinue }
    Stmt::ExprStmt => { Construct.SExprStmt }; Stmt::CompIf => { Construct.SCompIf }; Stmt::CompFor => { Construct.SCompFor }
    Stmt::CompMatch => { Construct.SCompMatch }; Stmt::CompForRange => { Construct.SCompForRange }
    Stmt::Unchecked => { Construct.SUnchecked }; Stmt::AllocWith => { Construct.SAllocWith }
  }
}
## The leftmost source offset of the statement at `h`, when it has one.
stmt_span := fn(h : ptr(mut Stmt)) -> Option(u64) {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { real_span(ns) }
    Stmt::While(c, b, nx) => { expr_span(c) }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { real_span(bns) }
    Stmt::Return(rv, nx) => { opt_expr_span(rv) }
    Stmt::If(c, th, el, nx) => { expr_span(c) }
    Stmt::Match(sc, ah, nx) => { expr_span(sc) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { real_span(fns) }
    Stmt::DerefAssign(p, v, nx) => { expr_span(p) }
    Stmt::IndexAssign(b, i, v, nx) => { expr_span(b) }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { expr_span(b) }
    Stmt::FieldPathAssign(pl, pv, nx) => { expr_span(pl) }
    Stmt::Loop(b, nx) => { Option(u64).None }
    Stmt::Break(bv, bd, nx) => { opt_expr_span(bv) }
    Stmt::Continue(cd, nx) => { Option(u64).None }
    Stmt::ExprStmt(e, nx) => { expr_span(e) }
    Stmt::CompIf(c, th, el, nx) => { expr_span(c) }
    Stmt::CompFor(vs, vl, iv, b, nx) => { real_span(vs) }
    Stmt::CompMatch(sc, ah, nx) => { expr_span(sc) }
    Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { real_span(vs) }
    Stmt::Unchecked(b, nx) => { Option(u64).None }
    Stmt::AllocWith(ae, b, nx) => { expr_span(ae) }
  }
}
opt_expr_span := fn(e : ptr(Expr)) -> Option(u64) {
  if expr_present(e) { return expr_span(e) }
  Option(u64).None
}

## ───────────────────────────── the `alatyr ir <file>` report ─────────────────────────────
##
## One line per function that reaches the builder, in declaration order, then a summary:
##   fn <module>::<name> NotYet(<construct>, <file>:<line>:<col>)
##   ir: functions=<n> built=<b> notyet=<n-b>
## `scripts/ir_census.sh` reads exactly these lines. The module tables are the front end's own: the
## newline-split source paths and, per module, its offset and length in the shared source buffer.

## The module whose source holds offset `off`, by index.
module_of := fn(off : usize, offs : ptr(rt::Vec), lens : ptr(rt::Vec)) -> Option(u64) {
  n := rt::vec_len(deref(offs))
  mut k : usize = 0
  while k < n {
    so := rt::vec_get(deref(offs), k)
    if off >= so and off < so + rt::vec_get(deref(lens), k) { return Option(u64).Some(u64(k)) }
    k = k + 1
  }
  Option(u64).None
}
## `<file>:<line>:<col>` of offset `off`, counting from its module's first byte.
put_loc := fn(in out sb : rt::StrBuf, src : ptr(u8), off : usize, paths : ptr(rt::Vec), offs : ptr(rt::Vec), lens : ptr(rt::Vec)) {
  mo : Option(u64) = module_of(off, offs, lens)
  match mo {
    Some(k) => {
      ku := usize(k)
      pth := rt::svec_str_get(deref(paths), ku)
      put(sb, pth)
      so := rt::vec_get(deref(offs), ku)
      mut line : usize = 1
      mut col : usize = 1
      mut q := so
      while q < off {
        if str_at((src + q), 1) == "\n" { line = line + 1; col = 1 } else { col = col + 1 }
        q = q + 1
      }
      put(sb, ":")
      put_u(sb, line)
      put(sb, ":")
      put_u(sb, col)
    }
    None => { put(sb, "<no source>") }
  }
}

## Run the builder over every function declaration of `decls` and print the report: a built function's
## verified IR, else its `NotYet`. The verifier runs on EVERY built function (§5). One it refuses is a
## located internal error, never printed as if it were sound: its report line is `VerifyFailed(<rule> at
## inst <n>)`, `alatyr: internal: IR verify <rule> in <function> at <file>:<line>:<col>` goes to stderr,
## and it is counted in `IR_VERIFY_FAILED`, which makes the `ir` verb exit 70 (an internal error).
## Answers the number of verifier refusals.
pub report_program := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), paths : ptr(rt::Vec), offs : ptr(rt::Vec), lens : ptr(rt::Vec), in out ba : rt::Arena) -> usize {
  p := prog_new(ba)
  mut eb := rt::strbuf(ba, 65536)
  cnt := rt::vec_len(deref(decls))
  mut nfn : usize = 0
  mut nbuilt : usize = 0
  mut ngap : usize = 0
  mut nbad : usize = 0
  mut i : usize = 0
  while i < cnt {
    ## unchecked-ok: `decls` holds Decl record addresses (the parser's `rt::Vec` of handles).
    dp : ptr(Decl) = unchecked bitcast(ptr(Decl), rt::vec_get(deref(decls), i))
    d : Decl = deref(dp)
    if d.is_fn and d.name_len != 0 {
      mut why := BuildWhy(c = Construct.CEmpty, w = NyWhy.NwOutside, span = u64(d.name_start))
      out : BuildOut = build_one(p, decls, src, i, ba, why)
      put(sb, "fn ")
      put_qual_name(sb, src, d)
      match out {
        Built(fid) => {
          f := prog_fn(p, fid)
          r : VRule = verify_fn(p, f, ba)
          if vrule_is_ok(r) {
            put(sb, " Built\n")
            print_fn(sb, p, f)
            nbuilt = nbuilt + 1
          } else {
            put(sb, " VerifyFailed(")
            put_rule(sb, r)
            put(sb, " at inst ")
            put_u(sb, V_AT)
            put(sb, ")\n")
            report_verify_failure(eb, p, f, r, src, d, paths, offs, lens)
            nbad = nbad + 1
          }
        }
        Refused => {
          wc : Construct = why.c
          ww : NyWhy = why.w
          put(sb, " NotYet(")
          if nywhy_is_gap(ww) {
            ngap = ngap + 1
            wn := nywhy_name(ww)
            put(sb, wn)
            put(sb, ": ")
          }
          put_construct(sb, wc)
          put(sb, ", ")
          put_loc(sb, src, usize(why.span), paths, offs, lens)
          put(sb, ")\n")
        }
      }
      nfn = nfn + 1
    }
    i = i + 1
  }
  put(sb, "ir: functions=")
  put_u(sb, nfn)
  put(sb, " built=")
  put_u(sb, nbuilt)
  put(sb, " notyet=")
  put_u(sb, nfn - nbuilt - nbad)
  put(sb, " sema_gaps=")
  put_u(sb, ngap)
  put(sb, " verify_failed=")
  put_u(sb, nbad)
  put(sb, "\n")
  if eb.len != 0 { elen : usize = eb.len; ew := rt::sb_flush(eb, 2) }
  IR_VERIFY_FAILED = IR_VERIFY_FAILED + nbad
  nbad
}
## How many built functions the verifier refused in this process (the `ir` verb exits 70 when any did).
mut IR_VERIFY_FAILED : usize = 0
pub verify_failures := fn() -> usize { IR_VERIFY_FAILED }
## `<module>::<name>` of a declaration, or `<name>` in the default module.
put_qual_name := fn(in out sb : rt::StrBuf, src : ptr(u8), d : Decl) {
  if d.mod_len != 0 { mnm := str_at((src + d.mod_start), d.mod_len); put(sb, mnm); put(sb, "::") }
  fnm := str_at((src + d.name_start), d.name_len)
  put(sb, fnm)
}
## The located internal error for a verifier refusal (§5): the rule, the function, and the source of
## the offending instruction (the function's name when that instruction carries no span).
report_verify_failure := fn(in out eb : rt::StrBuf, p : IrProg, f : ptr(mut IrFn), r : VRule, src : ptr(u8), d : Decl, paths : ptr(rt::Vec), offs : ptr(rt::Vec), lens : ptr(rt::Vec)) {
  mut at : usize = d.name_start
  if V_AT < fn_ninst(f) {
    ip := fn_inst(f, V_AT)
    if i_has_span(ip) { at = i_span(ip) }
  }
  put(eb, "alatyr: internal: IR verify ")
  put_rule(eb, r)
  put(eb, " in ")
  put_qual_name(eb, src, d)
  put(eb, " at ")
  put_loc(eb, src, at, paths, offs, lens)
  put(eb, "\n")
}

## ───────────────────────────── the selectors' hook (`docs/ir-slice-1.md` §4) ─────────────────────────────
##
## The three twins' program loops hand every function declaration to `select_input` before their
## legacy emitter. It answers `SiBuilt(f)` for a function the builder BUILT and the verifier accepted,
## and `SiLegacy` for a builder `NotYet` (the function keeps its legacy emission, owner decision D7).
## A verifier refusal is never a silent fallback (§5): it prints the located internal error, counts it
## in `IR_VERIFY_FAILED` (the twin verb then exits 70 instead of printing what it emitted), and answers
## `SiLegacy` so the emission loop can finish.
pub SelIn := enum { SiBuilt(ptr(mut IrFn)), SiLegacy }
## The predicate of an AST comparison operator byte (`CcNone` for any other byte), for the legacy
## emitters that share a selector's condition table instead of keeping their own.
pub cc_of_ast_op := fn(op : u8) -> Cc { ast_op_cc(op) }

## The front end's module tables, for the `<file>:<line>:<col>` a selector writes beside each trap it
## emits (§3.6) and for the verifier's located error. The twins' driver path sets them before the
## emitters run; a path that never does prints `<no source>`.
mut IR_SM_PATHS : Option(ptr(rt::Vec)) = Option.None
mut IR_SM_OFFS : Option(ptr(rt::Vec)) = Option.None
mut IR_SM_LENS : Option(ptr(rt::Vec)) = Option.None
pub set_source_map := fn(paths : ptr(rt::Vec), offs : ptr(rt::Vec), lens : ptr(rt::Vec)) {
  IR_SM_PATHS = Option(ptr(rt::Vec)).Some(paths)
  IR_SM_OFFS = Option(ptr(rt::Vec)).Some(offs)
  IR_SM_LENS = Option(ptr(rt::Vec)).Some(lens)
}
## `<file>:<line>:<col>` of source offset `off`, through the module tables `set_source_map` recorded.
pub put_src_loc := fn(in out sb : rt::StrBuf, src : ptr(u8), off : usize) {
  pso : Option(ptr(rt::Vec)) = IR_SM_PATHS
  oso : Option(ptr(rt::Vec)) = IR_SM_OFFS
  lso : Option(ptr(rt::Vec)) = IR_SM_LENS
  match pso {
    Some(paths) => {
      match oso {
        Some(offs) => {
          match lso {
            Some(lens) => { put_loc(sb, src, off, paths, offs, lens); return }
            None => {}
          }
        }
        None => {}
      }
    }
    None => {}
  }
  put(sb, "<no source>")
}
## The source location of instruction `ip`: its span when it carries one, else `fallback` (the owning
## function's name).
pub put_inst_loc := fn(in out sb : rt::StrBuf, src : ptr(u8), ip : ptr(mut IrInst), fallback : usize) {
  mut at : usize = fallback
  if i_has_span(ip) { at = i_span(ip) }
  put_src_loc(sb, src, at)
}

## Build declaration `di` of `decls` and verify it, for a selector.
pub select_input := fn(p : IrProg, decls : ptr(rt::Vec), src : ptr(u8), di : usize, in out a : rt::Arena) -> SelIn {
  ## unchecked-ok: `decls` holds Decl record addresses (the parser's `rt::Vec` of handles).
  dp : ptr(Decl) = unchecked bitcast(ptr(Decl), rt::vec_get(deref(decls), di))
  d : Decl = deref(dp)
  if not d.is_fn or d.name_len == 0 { return SelIn.SiLegacy }
  mut why := BuildWhy(c = Construct.CEmpty, w = NyWhy.NwOutside, span = u64(d.name_start))
  out : BuildOut = build_one(p, decls, src, di, a, why)
  match out {
    Built(fid) => {
      f := prog_fn(p, fid)
      r : VRule = verify_fn(p, f, a)
      if vrule_is_ok(r) { return SelIn.SiBuilt(f) }
      mut eb := rt::strbuf(a, 4096)
      put(eb, "alatyr: internal: IR verify ")
      put_rule(eb, r)
      put(eb, " in ")
      put_qual_name(eb, src, d)
      put(eb, " at ")
      mut at : usize = d.name_start
      if V_AT < fn_ninst(f) {
        vip := fn_inst(f, V_AT)
        if i_has_span(vip) { at = i_span(vip) }
      }
      put_src_loc(eb, src, at)
      put(eb, "\n")
      IR_VERIFY_FAILED = IR_VERIFY_FAILED + 1
      ew := rt::sb_flush(eb, 2)
      if ew < 0 { panic("selfhost: ir — the IR verifier's located error could not be written to stderr") }
      SelIn.SiLegacy
    }
    Refused => { SelIn.SiLegacy }
  }
}

## ───────────────────────────── the self-test (`alatyr ir --self-test`) ─────────────────────────────
##
## Builds a small program by hand, verifies it (it must pass), prints it (the text must equal the golden
## copy below), then builds one PLANTED function per verifier rule — each broken in exactly one way —
## and requires the verifier to refuse each with exactly the rule it plants. A verifier nobody has seen
## refuse anything is decoration; this is the proof each rule is live. Exit status = failures.

## An instruction of op `o` at type `ty`/`sg` in mode `md`.
st_mk := fn(o : Op, ty : Kty, sg : Sgn, md : Mode) -> IrInst {
  mut it := inst0(o)
  it.ty = ty
  it.sg = sg
  it.md = md
  it
}
## `%d = <o>.<md>.<sg> ty x, y`, optionally trapping with kind `tk` at `span`.
e_bin := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, md : Mode, sg : Sgn, ty : Kty, d : VRegId, x : Opnd, y : Opnd) -> usize {
  mut it := st_mk(o, ty, sg, md)
  set_dst(it, d)
  set_a(it, x)
  set_b(it, y)
  emit(f, a, it)
}
## …the same with a trap kind and a span (a `chk` op, V9).
e_binc := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, sg : Sgn, ty : Kty, d : VRegId, x : Opnd, y : Opnd, tk : TrapKind, span : usize) -> usize {
  mut it := st_mk(o, ty, sg, Mode.MdChk)
  set_dst(it, d)
  set_a(it, x)
  set_b(it, y)
  it.tk = tk
  set_span(it, span)
  emit(f, a, it)
}
e_const := fn(f : ptr(mut IrFn), in out a : rt::Arena, ty : Kty, sg : Sgn, d : VRegId, x : i64) -> usize {
  mut it := st_mk(Op.OpConst, ty, sg, Mode.MdNone)
  set_dst(it, d)
  ox1 := o_imm(x)
  set_a(it, ox1)
  emit(f, a, it)
}
e_cmp := fn(f : ptr(mut IrFn), in out a : rt::Arena, c : Cc, sg : Sgn, ty : Kty, d : VRegId, x : Opnd, y : Opnd) -> usize {
  mut it := st_mk(Op.OpCmp, ty, sg, Mode.MdNone)
  it.cc = c
  set_dst(it, d)
  set_a(it, x)
  set_b(it, y)
  emit(f, a, it)
}
e_width := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, sg : Sgn, ty : Kty, from : Kty, d : VRegId, x : VRegId) -> usize {
  mut it := st_mk(o, ty, sg, Mode.MdNone)
  it.from = from
  set_dst(it, d)
  ox2 := o_vreg(x)
  set_a(it, ox2)
  emit(f, a, it)
}
## A region opener (`block`/`loop` with label `l`, or `unchecked`).
e_open := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, l : LabelId) -> usize {
  mut it := inst0(o)
  it.lbl = usize(l)
  emit(f, a, it)
}
e_if := fn(f : ptr(mut IrFn), in out a : rt::Arena, c : VRegId) -> usize {
  mut it := inst0(Op.OpIf)
  ox3 := o_vreg(c)
  set_a(it, ox3)
  emit(f, a, it)
}
e_plain := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op) -> usize {
  it := inst0(o)
  emit(f, a, it)
}
e_br := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, c : Opnd, l : LabelId) -> usize {
  mut it := inst0(o)
  set_a(it, c)
  it.lbl = usize(l)
  emit(f, a, it)
}
e_ret := fn(f : ptr(mut IrFn), in out a : rt::Arena, x : Opnd) -> usize {
  mut it := inst0(Op.OpRet)
  set_a(it, x)
  emit(f, a, it)
}
e_trap_if := fn(f : ptr(mut IrFn), in out a : rt::Arena, c : VRegId, tk : TrapKind, span : usize, located : bool) -> usize {
  mut it := inst0(Op.OpTrapIf)
  ox4 := o_vreg(c)
  set_a(it, ox4)
  it.tk = tk
  if located { set_span(it, span) }
  emit(f, a, it)
}
e_mem := fn(f : ptr(mut IrFn), in out a : rt::Arena, o : Op, ty : Kty, sg : Sgn, d : Opnd, adr : Opnd, off : i64, val : Opnd) -> usize {
  mut it := st_mk(o, ty, sg, Mode.MdNone)
  if opndk_is_vreg(d.k) { it.dk = d.k; it.dv = d.v }
  set_a(it, adr)
  set_b(it, val)
  it.off = off
  emit(f, a, it)
}
## `%d = call callee(args…)`, the arguments pushed onto the pool first.
e_call2 := fn(f : ptr(mut IrFn), in out a : rt::Arena, callee : Opnd, d : VRegId, x : VRegId, y : VRegId) -> usize {
  mut it := inst0(Op.OpCall)
  set_dst(it, d)
  set_a(it, callee)
  it.pool = pool_push(f, a, usize(x))
  k := pool_push(f, a, usize(y))
  it.n = 2
  emit(f, a, it)
}
e_call1 := fn(f : ptr(mut IrFn), in out a : rt::Arena, callee : Opnd, d : VRegId, x : VRegId) -> usize {
  mut it := inst0(Op.OpCall)
  set_dst(it, d)
  set_a(it, callee)
  it.pool = pool_push(f, a, usize(x))
  it.n = 1
  emit(f, a, it)
}

## The two well-formed functions every run builds: `add2` and `tour` (which calls `add2`).
st_add2 := fn(p : IrProg, in out a : rt::Arena) -> ptr(mut IrFn) {
  nm := "add2"
  f := fn_new(a, nm.ptr, nm.len, true, Kty.KI64, Sgn.SgS)
  x := new_param(f, a, Kty.KI64, Sgn.SgS)
  y := new_param(f, a, Kty.KI64, Sgn.SgS)
  r := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  ox5 := o_vreg(x)
  ox6 := o_vreg(y)
  k1 := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI64, r, ox5, ox6, TrapKind.TkOverflow, 11)
  ox7 := o_vreg(r)
  k2 := e_ret(f, a, ox7)
  fi := prog_add(p, a, f)
  f
}
st_tour := fn(p : IrProg, in out a : rt::Arena) -> ptr(mut IrFn) {
  nm := "tour"
  f := fn_new(a, nm.ptr, nm.len, true, Kty.KI64, Sgn.SgS)
  x := new_param(f, a, Kty.KI64, Sgn.SgS)
  b := new_param(f, a, Kty.KI8, Sgn.SgU)
  fr := new_frame(f, a, 16, 8)
  seven := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  lt := new_vreg(f, a, Kty.KBool, Sgn.SgNone)
  r := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  z := new_vreg(f, a, Kty.KBool, Sgn.SgNone)
  q := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  ge := new_vreg(f, a, Kty.KBool, Sgn.SgNone)
  wide := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  sum := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  nar := new_vreg(f, a, Kty.KI8, Sgn.SgS)
  back := new_vreg(f, a, Kty.KI8, Sgn.SgS)
  again := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  res := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  l0 := new_label(f)
  l1 := new_label(f)
  l2 := new_label(f)
  l3 := new_label(f)
  k0 := e_const(f, a, Kty.KI64, Sgn.SgS, seven, 7)
  ox8 := o_vreg(x)
  ox9 := o_vreg(seven)
  k1 := e_cmp(f, a, Cc.CcLt, Sgn.SgS, Kty.KI64, lt, ox8, ox9)
  k2 := e_if(f, a, lt)
  ox10 := o_vreg(x)
  ox11 := o_none()
  k3 := e_bin(f, a, Op.OpMov, Mode.MdNone, Sgn.SgNone, Kty.KI64, r, ox10, ox11)
  k4 := e_plain(f, a, Op.OpElse)
  ox12 := o_vreg(x)
  ox13 := o_vreg(seven)
  k5 := e_binc(f, a, Op.OpSub, Sgn.SgS, Kty.KI64, r, ox12, ox13, TrapKind.TkOverflow, 21)
  k6 := e_plain(f, a, Op.OpEnd)
  ox14 := o_vreg(seven)
  ox15 := o_imm(0)
  k7 := e_cmp(f, a, Cc.CcEq, Sgn.SgNone, Kty.KI64, z, ox14, ox15)
  k8 := e_trap_if(f, a, z, TrapKind.TkDivZero, 30, true)
  ox16 := o_vreg(r)
  ox17 := o_vreg(seven)
  k9 := e_binc(f, a, Op.OpDiv, Sgn.SgS, Kty.KI64, q, ox16, ox17, TrapKind.TkDivZero, 30)
  k10 := e_open(f, a, Op.OpBlock, l0)
  k11 := e_open(f, a, Op.OpLoop, l1)
  ox18 := o_vreg(q)
  ox19 := o_imm(100)
  k12 := e_cmp(f, a, Cc.CcGe, Sgn.SgS, Kty.KI64, ge, ox18, ox19)
  ox20 := o_vreg(ge)
  k13 := e_br(f, a, Op.OpBrIf, ox20, l0)
  mut step := st_mk(Op.OpAdd, Kty.KI64, Sgn.SgNone, Mode.MdWrap)
  set_dst(step, q)
  ox21 := o_vreg(q)
  set_a(step, ox21)
  ox22 := o_imm(1)
  set_b(step, ox22)
  step.proven = true
  k14 := emit(f, a, step)
  ox23 := o_none()
  k15 := e_br(f, a, Op.OpBr, ox23, l1)
  k16 := e_plain(f, a, Op.OpEnd)
  k17 := e_plain(f, a, Op.OpEnd)
  k18 := e_open(f, a, Op.OpUnch, LabelId(0))
  k19 := e_width(f, a, Op.OpExt, Sgn.SgU, Kty.KI64, Kty.KI8, wide, b)
  ox24 := o_vreg(wide)
  ox25 := o_vreg(wide)
  k20 := e_bin(f, a, Op.OpAdd, Mode.MdWrap, Sgn.SgNone, Kty.KI64, sum, ox24, ox25)
  k21 := e_width(f, a, Op.OpExt, Sgn.SgS, Kty.KI8, Kty.KI64, nar, sum)
  k22 := e_plain(f, a, Op.OpEnd)
  ox26 := o_none()
  ox27 := o_frame(fr)
  ox28 := o_vreg(nar)
  k23 := e_mem(f, a, Op.OpStore, Kty.KI8, Sgn.SgNone, ox26, ox27, 4, ox28)
  ox29 := o_vreg(back)
  ox30 := o_frame(fr)
  ox31 := o_none()
  k24 := e_mem(f, a, Op.OpLoad, Kty.KI8, Sgn.SgS, ox29, ox30, 4, ox31)
  k25 := e_width(f, a, Op.OpExt, Sgn.SgS, Kty.KI64, Kty.KI8, again, back)
  ox32 := o_fn(FnId(0))
  k26 := e_call2(f, a, ox32, res, q, again)
  k27 := e_open(f, a, Op.OpBlock, l2)
  k28 := e_open(f, a, Op.OpBlock, l3)
  mut sw := inst0(Op.OpSwitch)
  ox33 := o_vreg(res)
  set_a(sw, ox33)
  sw.pool = pool_push(f, a, 0)
  k29 := pool_push(f, a, usize(l3))
  sw.n = 1
  sw.lbl = usize(l2)
  k30 := emit(f, a, sw)
  k31 := e_plain(f, a, Op.OpEnd)
  k32 := e_const(f, a, Kty.KI64, Sgn.SgS, res, 1)
  k33 := e_plain(f, a, Op.OpEnd)
  ox34 := o_vreg(res)
  k34 := e_ret(f, a, ox34)
  fi := prog_add(p, a, f)
  f
}

## The golden text of the two well-formed functions. A change to the printer changes this string in the
## same commit, on purpose.
st_golden := fn() -> str {
  "fn add2(%0 : i64 s, %1 : i64 s) -> i64 s {\n  %2 = add.chk.s i64 %0, %1 overflow  @11\n  ret %2\n}\nfn tour(%0 : i64 s, %1 : i8 u) -> i64 s {\n  $0 : frame 16 align 8\n  %2 = const.s i64 7\n  %3 = cmp.<.s i64 %0, %2\n  if %3 {\n    %4 = mov i64 %0\n  } else {\n    %4 = sub.chk.s i64 %0, %2 overflow  @21\n  }\n  %5 = cmp.== i64 %2, 0\n  trap_if %5 div_zero  @30\n  %6 = div.chk.s i64 %4, %2 div_zero  @30\n  block L0 {\n    loop L1 {\n      %7 = cmp.>=.s i64 %6, 100\n      br_if %7 L0\n      %6 = add.wrap i64 %6, 1  !proven\n      br L1\n    }\n  }\n  unchecked {\n    %8 = ext.u i64 <- i8 %1\n    %9 = add.wrap i64 %8, %8\n    %10 = ext.s i8 <- i64 %9\n  }\n  store i8 [$0 + 4], %10\n  %11 = load.s i8 [$0 + 4]\n  %12 = ext.s i64 <- i8 %11\n  %13 = call @add2(%6, %12)\n  block L2 {\n    block L3 {\n      switch %13 [0 -> L3] default L2\n    }\n    %13 = const.s i64 1\n  }\n  ret %13\n}\n"
}

## One planted function: a single broken instruction in an otherwise well-formed body. `which` selects
## the plant (`st_want` names the rule it breaks); `st_plant` answers what the verifier said.
st_plant := fn(p : IrProg, in out a : rt::Arena, which : usize) -> VRule {
  nm := "planted"
  f := fn_new(a, nm.ptr, nm.len, true, Kty.KI64, Sgn.SgS)
  x := new_param(f, a, Kty.KI64, Sgn.SgS)
  y := new_param(f, a, Kty.KI64, Sgn.SgS)
  r := new_vreg(f, a, Kty.KI64, Sgn.SgS)
  if which == 0 {
    ## V1 — the result vreg is an i32, the op works at i64.
    w32 := new_vreg(f, a, Kty.KI32, Sgn.SgS)
    ox35 := o_vreg(x)
    ox36 := o_vreg(y)
    k := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI64, w32, ox35, ox36, TrapKind.TkOverflow, 5)
  } else if which == 1 {
    ## V2 — a vreg of no kernel type.
    nv := new_vreg(f, a, Kty.KNone, Sgn.SgNone)
  } else if which == 2 {
    ## V3 — wrapping arithmetic producing a narrow type without `ext`/`fit`.
    n1 := new_vreg(f, a, Kty.KI8, Sgn.SgS)
    n2 := new_vreg(f, a, Kty.KI8, Sgn.SgS)
    k1 := e_const(f, a, Kty.KI8, Sgn.SgS, n1, 5)
    ox37 := o_vreg(n1)
    ox38 := o_vreg(n1)
    k2 := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI8, n2, ox37, ox38, TrapKind.TkOverflow, 5)
  } else if which == 3 {
    ## V4 — an UNSIGNED divide over signed operands (#764's shape, spelled).
    ox39 := o_vreg(x)
    ox40 := o_vreg(y)
    k := e_binc(f, a, Op.OpDiv, Sgn.SgU, Kty.KI64, r, ox39, ox40, TrapKind.TkDivZero, 5)
  } else if which == 4 {
    ## V5 — a vreg read before any path assigns it.
    u := new_vreg(f, a, Kty.KI64, Sgn.SgS)
    ox41 := o_vreg(x)
    ox42 := o_vreg(u)
    k := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI64, r, ox41, ox42, TrapKind.TkOverflow, 5)
  } else if which == 5 {
    ## V5 — assigned on the then-arm only of an `if` with no `else`, then read after it.
    c := new_vreg(f, a, Kty.KBool, Sgn.SgNone)
    u := new_vreg(f, a, Kty.KI64, Sgn.SgS)
    ox43 := o_vreg(x)
    ox44 := o_vreg(y)
    k1 := e_cmp(f, a, Cc.CcLt, Sgn.SgS, Kty.KI64, c, ox43, ox44)
    k2 := e_if(f, a, c)
    k3 := e_const(f, a, Kty.KI64, Sgn.SgS, u, 1)
    k4 := e_plain(f, a, Op.OpEnd)
    ox45 := o_vreg(x)
    ox46 := o_vreg(u)
    k5 := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI64, r, ox45, ox46, TrapKind.TkOverflow, 5)
  } else if which == 6 {
    ## V6 — an 8-byte store at offset 12 of a 16-byte frame object.
    fr := new_frame(f, a, 16, 8)
    ox47 := o_none()
    ox48 := o_frame(fr)
    ox49 := o_vreg(x)
    k := e_mem(f, a, Op.OpStore, Kty.KI64, Sgn.SgNone, ox47, ox48, 12, ox49)
  } else if which == 7 {
    ## V7 — a `br` to a label no enclosing region carries.
    l := new_label(f)
    ox50 := o_none()
    k := e_br(f, a, Op.OpBr, ox50, l)
  } else if which == 8 {
    ## V7 — an instruction after a terminator in the same sequence.
    ox51 := o_vreg(x)
    k1 := e_ret(f, a, ox51)
    k2 := e_const(f, a, Kty.KI64, Sgn.SgS, r, 1)
  } else if which == 9 {
    ## V7 — a function with a result that falls off its end.
    k := e_const(f, a, Kty.KI64, Sgn.SgS, r, 1)
  } else if which == 10 {
    ## V8 — `add2` called with one argument.
    ox52 := o_fn(FnId(0))
    k := e_call1(f, a, ox52, r, x)
  } else if which == 11 {
    ## V9 — a `trap_if` with no source span.
    c := new_vreg(f, a, Kty.KBool, Sgn.SgNone)
    ox53 := o_vreg(x)
    ox54 := o_imm(0)
    k1 := e_cmp(f, a, Cc.CcEq, Sgn.SgNone, Kty.KI64, c, ox53, ox54)
    k2 := e_trap_if(f, a, c, TrapKind.TkDivZero, 0, false)
  } else if which == 12 {
    ## V10 — a `chk` op inside an `unchecked` region.
    k1 := e_open(f, a, Op.OpUnch, LabelId(0))
    ox55 := o_vreg(x)
    ox56 := o_vreg(y)
    k2 := e_binc(f, a, Op.OpAdd, Sgn.SgS, Kty.KI64, r, ox55, ox56, TrapKind.TkOverflow, 5)
    k3 := e_plain(f, a, Op.OpEnd)
  } else {
    ## V10 — a `wrap` op outside any `unchecked` region, not proven.
    ox57 := o_vreg(x)
    ox58 := o_vreg(y)
    k := e_bin(f, a, Op.OpAdd, Mode.MdWrap, Sgn.SgNone, Kty.KI64, r, ox57, ox58)
  }
  ox59 := o_vreg(x)
  if which != 9 { kr := e_ret(f, a, ox59) }
  fi := prog_add(p, a, f)
  verify_fn(p, f, a)
}
## The rule plant `which` breaks.
st_want := fn(which : usize) -> VRule {
  if which == 0 { return VRule.V1 }
  if which == 1 { return VRule.V2 }
  if which == 2 { return VRule.V3 }
  if which == 3 { return VRule.V4 }
  if which == 4 or which == 5 { return VRule.V5 }
  if which == 6 { return VRule.V6 }
  if which == 7 or which == 8 or which == 9 { return VRule.V7 }
  if which == 10 { return VRule.V8 }
  if which == 11 { return VRule.V9 }
  VRule.V10
}
st_plants := fn() -> usize { 14 }

st_line := fn(in out sb : rt::StrBuf, ok : bool, what : str) {
  if ok { put(sb, "ok   ") } else { put(sb, "FAIL ") }
  put(sb, what)
  put(sb, "\n")
}

pub self_test := fn(in out ca : rt::Arena) -> usize {
  mut a := rt::Arena(base = ca.base, off = 0, cap = 0)
  rt::arena_init(a, 67108864)
  ## Room for a failing golden's whole report, printed beside its verdict.
  mut sb := rt::strbuf(a, 4194304)
  mut fails : usize = 0
  ## Storage: a WBuf grows past any initial capacity and keeps every word.
  w := wb_new(a, 2)
  mut i : usize = 0
  while i < 5000 { k := wb_push(w, a, i * 3); i = i + 1 }
  mut good := wb_len(w) == 5000
  i = 0
  while i < 5000 and good { if wb_get(w, i) != i * 3 { good = false }; i = i + 1 }
  st_line(sb, good, "storage: a WBuf grown from 2 to 5000 words keeps every word")
  if not good { fails = fails + 1 }
  ## The well-formed program verifies and prints its golden text.
  p := prog_new(a)
  f1 := st_add2(p, a)
  f2 := st_tour(p, a)
  bad := verify_prog(p, a, sb)
  st_line(sb, bad == 0, "verify: the well-formed program (add2, tour) passes every rule")
  if bad != 0 { fails = fails + 1 }
  mut pb := rt::strbuf(a, 16384)
  print_fn(pb, p, f1)
  print_fn(pb, p, f2)
  printed := str_at(pb.data, pb.len)
  golden := st_golden()
  pok := printed == golden
  st_line(sb, pok, "print: the printed program equals the golden text")
  if not pok { fails = fails + 1; put(sb, printed) }
  ## Every rule refuses its plant, with exactly that rule.
  mut w2 : usize = 0
  while w2 < st_plants() {
    got : VRule = st_plant(p, a, w2)
    want : VRule = st_want(w2)
    pgood := vrule_code(got) == vrule_code(want)
    if pgood { put(sb, "ok   planted #") } else { put(sb, "FAIL planted #") }
    put_u(sb, w2)
    put(sb, " (a ")
    put_rule(sb, want)
    put(sb, " violation): the verifier answered ")
    put_rule(sb, got)
    put(sb, "\n")
    if not pgood { fails = fails + 1 }
    w2 = w2 + 1
  }
  ## The golden builds: real programs through the `ir` verb's whole pipeline (`ir::golden`).
  mut ngold : usize = 0
  gfails := golden_run(sb, a, ngold)
  fails = fails + gfails
  put(sb, "ir self-test: ")
  put_u(sb, st_plants() + 3 + ngold - fails)
  put(sb, " passed, ")
  put_u(sb, fails)
  put(sb, " failed\n")
  outlen : usize = sb.len
  wr := rt::sb_flush(sb, 1)
  if wr != isize(outlen) { fails = fails + 1 }
  fails
}

## ───────────────────────────── the sema side table (docs/ir.md §3.8, owner decision D6) ─────────────────────────────
##
## Sema is the single source of types (D6). While it checks a program it records, for every expression
## node it types, the VALUE type the expression has — class, width and signedness — keyed by the node's
## address. The IR builder will copy it onto the IR value (§3.8 step 2) instead of re-deriving it from
## the expression's shape; in slice 0a only the census reads it.
##
## Recording is OFF unless a consumer asks for it (`sty_enable`, or the census channel below being
## open), so an ordinary build maps nothing and runs no extra code past one flag test per expression.
## The table lives in its own anonymous mappings, never in a compile arena, because the compiler's own
## output must not move with an instrument (the #529 bitcast table's rule). It GROWS: the key/value
## arrays rehash into a mapping twice the size at half load, and the records come from chunks that are
## never moved, so a record's address stays valid for the whole run.

## The class of a recorded value type. `VcAbsent` is "sema never typed this node"; `VcUnknown` is
## "sema typed it and could not name a kernel type" — a sema gap to close, never a default (§3.8.4);
## `VcLit` is an integer literal (or a literal-only expression) whose type comes from its context and
## no context has given it one.
pub VCls := enum { VcAbsent, VcUnknown, VcLit, VcInt, VcBool, VcPtr, VcFloat, VcAgg }
pub VTy := struct { cls : VCls, bytes : u64, sg : Sgn }
vcls_code := fn(c : VCls) -> u64 {
  match c { VcAbsent => { 0 }; VcUnknown => { 1 }; VcLit => { 2 }; VcInt => { 3 }; VcBool => { 4 }; VcPtr => { 5 }; VcFloat => { 6 }; VcAgg => { 7 } }
}
pub vcls_is_int := fn(c : VCls) -> bool {
  match c { VcInt => { true }; VcAbsent | VcUnknown | VcLit | VcBool | VcPtr | VcFloat | VcAgg => { false } }
}
pub vcls_is_lit := fn(c : VCls) -> bool {
  match c { VcLit => { true }; VcAbsent | VcUnknown | VcInt | VcBool | VcPtr | VcFloat | VcAgg => { false } }
}
pub vty_unknown := fn() -> VTy { VTy(cls = VCls.VcUnknown, bytes = 0, sg = Sgn.SgNone) }
pub vty_lit := fn() -> VTy { VTy(cls = VCls.VcLit, bytes = 0, sg = Sgn.SgNone) }
pub vty_bool := fn() -> VTy { VTy(cls = VCls.VcBool, bytes = 1, sg = Sgn.SgNone) }
pub vty_int := fn(bytes : u64, sg : Sgn) -> VTy { VTy(cls = VCls.VcInt, bytes = bytes, sg = sg) }
## The recorded type's class, read through a copy (#792).
pub vty_cls := fn(t : VTy) -> VCls { t.cls }

mut STY_ON : bool = false
mut STY_KEYS : usize = 0    ## address of the key array (node addresses)
mut STY_USED : usize = 0    ## address of the occupancy array (1 = the slot holds a key)
mut STY_VALS : usize = 0    ## address of the value array (record addresses)
mut STY_CAP : usize = 0     ## slots, a power of two
mut STY_N : usize = 0       ## occupied slots
mut STY_RB : usize = 0      ## the current record chunk
mut STY_ROFF : usize = 0
mut STY_RCAP : usize = 0

## Turn recording on. Idempotent.
pub sty_enable := fn() { STY_ON = true }
pub sty_on := fn() -> bool { STY_ON or sign_open() }
pub sty_len := fn() -> usize { STY_N }

## A fresh zeroed anonymous mapping of `bytes` bytes (`mmap` answers zero-filled pages).
sty_map := fn(bytes : usize) -> usize {
  fdm1 := 0 - 1
  r := rt::sys_mmap(9, 0, bytes, 3, 34, fdm1, 0)
  if r < 0 { panic("selfhost: ir — sema type table mapping failed (mmap)") }
  ## unchecked-ok: `mmap` answered a non-negative address; it is the mapping's base.
  unchecked bitcast(usize, r)
}
## The address of word `i` of the mapping at `base`.
sty_word := fn(base : usize, i : usize) -> ptr(mut usize) {
  ## unchecked-ok: `base` is an 8-byte-aligned mapping of at least `i + 1` words (every caller bounds `i`).
  unchecked bitcast(ptr(mut usize), base + i * 8)
}
## The slot a key hashes to: multiplicative hashing of the node address (nodes are 8-byte aligned).
sty_home := fn(k : usize, cap : usize) -> usize {
  ## unchecked-ok: a hash is modular by intent; the product's overflow is the mixing, not an error.
  h : usize = unchecked { shr(k, 3) * 2654435761 }
  shr(h, 8) % cap
}
## Is slot `i` of the occupancy array at `used` taken? Occupancy is its own array, so no key value is
## reserved to mean "free".
sty_taken := fn(used : usize, i : usize) -> bool { deref(sty_word(used, i)) == 1 }
## Insert or overwrite `k -> v` in the arrays at (keys, vals, used) of `cap` slots, WITHOUT growing.
## Answers whether a new slot was taken.
sty_place := fn(keys : usize, vals : usize, used : usize, cap : usize, k : usize, v : usize) -> bool {
  mut i := sty_home(k, cap)
  mut probes : usize = 0
  while probes < cap {
    if not sty_taken(used, i) {
      deref(sty_word(keys, i)) = k
      deref(sty_word(vals, i)) = v
      deref(sty_word(used, i)) = 1
      return true
    }
    if deref(sty_word(keys, i)) == k { deref(sty_word(vals, i)) = v; return false }
    i = (i + 1) % cap
    probes = probes + 1
  }
  panic("selfhost: ir — sema type table full (rehash missed)")
  false
}
## Double the table (or create it) and reinsert every entry.
sty_grow := fn() {
  mut nc : usize = STY_CAP * 2
  if nc == 0 { nc = 65536 }
  nk := sty_map(nc * 8)
  nv := sty_map(nc * 8)
  nu := sty_map(nc * 8)
  mut i : usize = 0
  while i < STY_CAP {
    if sty_taken(STY_USED, i) { fresh := sty_place(nk, nv, nu, nc, deref(sty_word(STY_KEYS, i)), deref(sty_word(STY_VALS, i))) }
    i = i + 1
  }
  STY_KEYS = nk
  STY_VALS = nv
  STY_USED = nu
  STY_CAP = nc
}
## A new record slot from the current chunk (a fresh chunk when it is spent), large enough for either
## record kind the table holds: a `VTy` or a `TySpell`.
sty_record := fn() -> usize {
  mut rs : usize = size(VTy)
  sp : usize = size(TySpell)
  if sp > rs { rs = sp }
  if STY_ROFF + rs > STY_RCAP {
    STY_RCAP = 1048576
    STY_RB = sty_map(STY_RCAP)
    STY_ROFF = 0
  }
  p := STY_RB + STY_ROFF
  STY_ROFF = STY_ROFF + rs
  p
}
## Record (or re-record) the value type of the node at `e`.
pub sty_put := fn(e : ptr(Expr), t : VTy) {
  ## unchecked-ok: the node's address is the table key; nothing reads it back as a pointer.
  k := unchecked bitcast(usize, e)
  sty_put_key(k, t)
}
## docs/ir-slice-1.md §2 — the value type of a BINDING, keyed by its declaration's name offset: an
## unannotated local's type is known only where it is declared, and each use of it reads it here. The
## key is the offset with the top bit set, a value no node address (an arena address) takes, so binding
## keys and node keys share the one growing table without meeting.
bind_key := fn(ns : usize) -> usize { ns | shl(usize(1), 63) }
pub sty_bind_put := fn(ns : usize, t : VTy) { sty_put_key(bind_key(ns), t) }
pub sty_bind_get := fn(ns : usize) -> VTy { sty_get_key(bind_key(ns)) }
sty_put_key := fn(k : usize, t : VTy) {
  if STY_N * 2 >= STY_CAP { sty_grow() }
  ## An existing record is overwritten in place, so a context that refines a literal reaches every
  ## reader of the node.
  ex := sty_find(k)
  match ex {
    Some(rw) => {
      ## unchecked-ok: every value word is a record address `sty_record` handed out.
      rp : ptr(mut VTy) = unchecked bitcast(ptr(mut VTy), usize(rw))
      deref(rp) = t
    }
    None => {
      ra := sty_record()
      ## unchecked-ok: `sty_record` answered a fresh slot of a live mapping, at least `size(VTy)` bytes.
      rp2 : ptr(mut VTy) = unchecked bitcast(ptr(mut VTy), ra)
      deref(rp2) = t
      if sty_place(STY_KEYS, STY_VALS, STY_USED, STY_CAP, k, ra) { STY_N = STY_N + 1 }
    }
  }
}
## The record address stored for key `k`, if any.
sty_find := fn(k : usize) -> Option(u64) {
  if STY_CAP == 0 { return Option(u64).None }
  mut i := sty_home(k, STY_CAP)
  mut probes : usize = 0
  while probes < STY_CAP {
    if not sty_taken(STY_USED, i) { return Option(u64).None }
    if deref(sty_word(STY_KEYS, i)) == k { return Option(u64).Some(u64(deref(sty_word(STY_VALS, i)))) }
    i = (i + 1) % STY_CAP
    probes = probes + 1
  }
  Option(u64).None
}
## The value type recorded for the node at `e` (`VcAbsent` when sema never typed it).
pub sty_get := fn(e : ptr(Expr)) -> VTy {
  ## unchecked-ok: the node's address is the table key.
  k := unchecked bitcast(usize, e)
  sty_get_key(k)
}
sty_get_key := fn(k : usize) -> VTy {
  ex := sty_find(k)
  match ex {
    Some(rw) => {
      ## unchecked-ok: every value word is a record address `sty_record` handed out.
      rp : ptr(mut VTy) = unchecked bitcast(ptr(mut VTy), usize(rw))
      t : VTy = deref(rp)
      return t
    }
    None => {}
  }
  VTy(cls = VCls.VcAbsent, bytes = 0, sg = Sgn.SgNone)
}
## docs/ir.md §3.8 item 8 — the SPELLING of the type sema resolved for a node or a binding: the source
## span `[s, s+n)` of the declaration text that names it (a parameter's or a field's annotation, a
## callee's `-> R`, a pointer's pointee inside `ptr(…)`), `n == 0` when sema resolved none. It is the
## recorder's own companion, never read by a builder: a value type (`VTy`) is enough to emit a scalar,
## but reaching the scalar a field, a `deref` or an element holds needs the aggregate or pointer it is
## read from, and only its spelling names that. Same table, own key space (bit 62), so a spelling key
## meets neither a node key (an arena address) nor a binding key (bit 63 alone).
pub TySpell := struct { s : usize, n : usize }
spell_key := fn(k : usize) -> usize { k | shl(usize(1), 62) }
pub sty_spell_put := fn(e : ptr(Expr), t : TySpell) {
  ## unchecked-ok: the node's address is the table key; nothing reads it back as a pointer.
  k := unchecked bitcast(usize, e)
  sty_spell_put_key(spell_key(k), t)
}
pub sty_spell_get := fn(e : ptr(Expr)) -> TySpell {
  ## unchecked-ok: the node's address is the table key.
  k := unchecked bitcast(usize, e)
  sty_spell_get_key(spell_key(k))
}
pub sty_bind_spell_put := fn(ns : usize, t : TySpell) { sty_spell_put_key(spell_key(bind_key(ns)), t) }
pub sty_bind_spell_get := fn(ns : usize) -> TySpell { sty_spell_get_key(spell_key(bind_key(ns))) }
sty_spell_put_key := fn(k : usize, t : TySpell) {
  if STY_N * 2 >= STY_CAP { sty_grow() }
  ex := sty_find(k)
  match ex {
    Some(rw) => {
      ## unchecked-ok: every value word under a spelling key is a record address `sty_record` handed out.
      rp : ptr(mut TySpell) = unchecked bitcast(ptr(mut TySpell), usize(rw))
      deref(rp) = t
    }
    None => {
      ra := sty_record()
      ## unchecked-ok: `sty_record` answered a fresh slot of a live mapping, at least `size(TySpell)` bytes.
      rp2 : ptr(mut TySpell) = unchecked bitcast(ptr(mut TySpell), ra)
      deref(rp2) = t
      if sty_place(STY_KEYS, STY_VALS, STY_USED, STY_CAP, k, ra) { STY_N = STY_N + 1 }
    }
  }
}
sty_spell_get_key := fn(k : usize) -> TySpell {
  ex := sty_find(k)
  match ex {
    Some(rw) => {
      ## unchecked-ok: every value word under a spelling key is a record address `sty_record` handed out.
      rp : ptr(mut TySpell) = unchecked bitcast(ptr(mut TySpell), usize(rw))
      t : TySpell = deref(rp)
      return t
    }
    None => {}
  }
  TySpell(s = 0, n = 0)
}

## ───────────────────────────── the signedness differential census (docs/ir.md §3.8.5) ─────────────────────────────
##
## For every `/`, `%`, ordering compare and `shr` the compiler meets, each LEGACY emitter writes the
## signedness it chose, and sema writes the signedness its recorded operand types imply. A disagreement
## is a #764-class wrong value found mechanically. The channel is file descriptor 97, the convention of
## the #299 (fd 99) and #529 (fd 98) census instruments: it is open only when the harness opens it
## (`alatyr <verb> <file> 97>rows`), an ordinary run writes nothing, and no emitted byte depends on it.
##
## A row is keyed by SOURCE TEXT, not by address, because sema and a twin's emitter run over two
## different parses of the same files:
##   #sign <who> <op-byte> <lcol> <rcol> <answer> |<the source line>
## `who` is `sema`, `x86_64`, `aarch64`, `riscv64` or `wasm`; `lcol`/`rcol` are the 1-based columns of the
## operands' leftmost tokens on that line (`?` when an operand has no source position); `answer` is `s`
## or `u`, and for sema also `lit` (literal-only, no context typed it) or `?` (sema could not type it).
mut SIGN_PROBED : bool = false
mut SIGN_OPEN : bool = false
sign_fd := fn() -> usize { 97 }
pub sign_open := fn() -> bool {
  if not SIGN_PROBED {
    SIGN_PROBED = true
    SIGN_OPEN = rt::sys_write(1, sign_fd(), 0, 0) == 0
  }
  SIGN_OPEN
}
## Is `op` one of the signedness-dependent binary operators the census follows?
pub sign_op_followed := fn(op : u8) -> bool { op == 19 or op == 29 or op == 24 or op == 25 or op == 26 or op == 27 }
## The start of the line holding offset `off`.
line_start := fn(src : ptr(u8), off : usize) -> usize {
  mut p := off
  while p > 0 and str_at((src + p - 1), 1) != "\n" { p = p - 1 }
  p
}
## `<col>` of an expression's leftmost token (1-based, relative to `ls`), or `?`.
put_col := fn(in out sb : rt::StrBuf, e : ptr(Expr), src : ptr(u8)) {
  sp : Option(u64) = expr_span(e)
  match sp {
    Some(s) => {
      su := usize(s)
      put_u(sb, su - line_start(src, su) + 1)
    }
    None => { put(sb, "?") }
  }
}
## The leftmost source offset of the pair: the left operand's, else the right's.
pair_span := fn(l : ptr(Expr), r : ptr(Expr)) -> Option(u64) {
  sl : Option(u64) = expr_span(l)
  match sl { Some(s) => { return Option(u64).Some(s) }; None => {} }
  expr_span(r)
}
## The source line holding the pair (` |`, the line, a newline).
put_line := fn(in out sb : rt::StrBuf, l : ptr(Expr), r : ptr(Expr), src : ptr(u8)) {
  put_line_at(sb, pair_span(l, r), src)
}
## The source line holding offset `sp` (` |`, the line, a newline); just ` |` and the newline without one.
put_line_at := fn(in out sb : rt::StrBuf, sp : Option(u64), src : ptr(u8)) {
  put(sb, " |")
  match sp {
    Some(s) => {
      su := usize(s)
      ls := line_start(src, su)
      mut le := su
      end := ast::src_extent()
      while le < end and str_at((src + le), 1) != "\n" { le = le + 1 }
      ln := str_at((src + ls), le - ls)
      put(sb, ln)
    }
    None => {}
  }
  put(sb, "\n")
}
## The one row buffer: a 64 KiB mapping made on the first row and reused (a row is written whole).
mut SIGN_BUF : usize = 0
mut SIGN_BUF_MAPPED : bool = false
sign_buf := fn() -> rt::StrBuf {
  if not SIGN_BUF_MAPPED { SIGN_BUF = sty_map(65536); SIGN_BUF_MAPPED = true }
  ## unchecked-ok: `SIGN_BUF` is the address of a live 64 KiB mapping made just above.
  d : ptr(mut u8) = unchecked bitcast(ptr(mut u8), SIGN_BUF)
  rt::StrBuf(data = d, len = 0, cap = 65536)
}
## Write one census row to fd 97.
sign_emit := fn(who : str, op : u8, l : ptr(Expr), r : ptr(Expr), src : ptr(u8), answer : str) {
  mut sb := sign_buf()
  put(sb, "#sign ")
  put(sb, who)
  put(sb, " ")
  ## The AST operator byte (`0` for the `shr` builtin): `scripts/sign_census.sh` names it, so this
  ## file keeps no second copy of the operator-spelling table (`lower::op_symbol`).
  put_u(sb, usize(op))
  put(sb, " ")
  put_col(sb, l, src)
  put(sb, " ")
  put_col(sb, r, src)
  put(sb, " ")
  put(sb, answer)
  put_line(sb, l, r, src)
  rowlen : usize = sb.len
  w := rt::sb_flush(sb, sign_fd())
  if w != isize(rowlen) { SIGN_LOST = SIGN_LOST + 1 }
}
## Rows a short or failed write lost (a census whose channel can go quiet must say so).
mut SIGN_LOST : usize = 0
## A legacy emitter's decision: `signed` is what it chose for the operation over (`l`, `r`).
pub sign_row := fn(who : str, op : u8, l : ptr(Expr), r : ptr(Expr), src : ptr(u8), signed : bool) {
  if not sign_open() { return }
  if signed { sign_emit(who, op, l, r, src, "s") } else { sign_emit(who, op, l, r, src, "u") }
}

## docs/ir.md §3.8.6 — what sema's RECORD pass over a library declaration found that a check of the
## same body as user code would refuse. The verdict stays TRUST (a library body never refuses the
## program), so this row is the only place the finding surfaces; it is never dropped.
##   #semalib refused <module>::<decl> |<the declaration's line>   check_decl refused the body
##   #semalib head <module>::<decl> |<the line of the head>        a `::` head in it resolves to nothing (#580)
pub LibFinding := enum { LfRefused, LfHead }
pub sign_lib_row := fn(what : LibFinding, ms : usize, ml : usize, ns : usize, nl : usize, at : usize, src : ptr(u8)) {
  if not sign_open() { return }
  mut sb := sign_buf()
  match what { LfRefused => { put(sb, "#semalib refused ") }; LfHead => { put(sb, "#semalib head ") } }
  put(sb, str_at((src + ms), ml))
  put(sb, "::")
  put(sb, str_at((src + ns), nl))
  put_line_at(sb, Option(u64).Some(u64(at)), src)
  rowlen : usize = sb.len
  w := rt::sb_flush(sb, sign_fd())
  if w != isize(rowlen) { SIGN_LOST = SIGN_LOST + 1 }
}
## docs/ir.md §3.8.7 — code whose records-only walk (`sema::sema_ct_record`: a `comptime if`/`match`/
## `for` condition or body, or a generic call's argument written where an implicit type parameter
## sits) the checker refused. The verdict does not move (the checker does not check that code yet), so
## this row is where the finding surfaces:
##   #semact refused |<the line of the walked condition, loop variable or argument>
pub sign_ct_row := fn(at : Option(u64), src : ptr(u8)) {
  if not sign_open() { return }
  mut sb := sign_buf()
  put(sb, "#semact refused")
  put_line_at(sb, at, src)
  rowlen : usize = sb.len
  w := rt::sb_flush(sb, sign_fd())
  if w != isize(rowlen) { SIGN_LOST = SIGN_LOST + 1 }
}

## Sema's answer for a site: the signedness of the first operand whose recorded type is an integer.
sema_answer := fn(l : ptr(Expr), r : ptr(Expr)) -> str {
  lt : VTy = sty_get(l)
  rt0 : VTy = sty_get(r)
  lc : VCls = vty_cls(lt)
  rc : VCls = vty_cls(rt0)
  ls : Sgn = lt.sg
  rs : Sgn = rt0.sg
  if vcls_is_int(lc) { return sgn_name(ls) }
  if vcls_is_int(rc) { return sgn_name(rs) }
  if vcls_is_lit(lc) and vcls_is_lit(rc) { return "lit" }
  "?"
}
## The followed sites sema met, recorded while it checks so the rows are written only once every
## context has refined its literals (`sign_flush_sema`, on `check_program`'s accepting exit).
mut SITES : usize = 0     ## address of a site-array mapping (node addresses)
mut SITES_N : usize = 0
mut SITES_CAP : usize = 0
pub sign_site := fn(e : ptr(Expr)) {
  if not sign_open() { return }
  if SITES_N >= SITES_CAP {
    mut nc := SITES_CAP * 2
    if nc == 0 { nc = 65536 }
    nb := sty_map(nc * 8)
    mut i : usize = 0
    while i < SITES_N { deref(sty_word(nb, i)) = deref(sty_word(SITES, i)); i = i + 1 }
    SITES = nb
    SITES_CAP = nc
  }
  ## unchecked-ok: the node's address is stored as a word; `site_expr` reads it back.
  deref(sty_word(SITES, SITES_N)) = unchecked bitcast(usize, e)
  SITES_N = SITES_N + 1
}
## unchecked-ok: every site word was stored by `sign_site` from a `ptr(Expr)`.
site_expr := fn(i : usize) -> ptr(Expr) { unchecked bitcast(ptr(Expr), deref(sty_word(SITES, i))) }
## One sema row for the site at `e` (a followed `Bin`, or a `shr(x, n)` call).
sign_sema_row := fn(e : ptr(Expr), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { ans := sema_answer(l, r); sign_emit("sema", op, l, r, src, ans) }
    Expr::Call(cs, cl, na, ah) => {
      if na == 2 {
        a0 := deref(arg_at(ah, "argument list ended early"))
        a1 := deref(arg_at(a0.next, "argument list ended early"))
        ans2 := sema_answer(a0.e, a1.e)
        sign_emit("sema", 0, a0.e, a1.e, src, ans2)
      }
    }
    Expr::Num | Expr::BoolLit | Expr::Var | Expr::If | Expr::Match | Expr::StructLit | Expr::Field | Expr::EnumLit
      | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit
      | Expr::Slice | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => {}
  }
}
## Write every recorded sema site, then forget them (a later check in the same process starts clean).
pub sign_flush_sema := fn(src : ptr(u8)) {
  if not sign_open() { return }
  mut i : usize = 0
  while i < SITES_N { sign_sema_row(site_expr(i), src); i = i + 1 }
  SITES_N = 0
}
pub vty_u := fn(bytes : u64) -> VTy { VTy(cls = VCls.VcInt, bytes = bytes, sg = Sgn.SgU) }
pub vty_s := fn(bytes : u64) -> VTy { VTy(cls = VCls.VcInt, bytes = bytes, sg = Sgn.SgS) }
pub vty_ptr := fn() -> VTy { VTy(cls = VCls.VcPtr, bytes = 8, sg = Sgn.SgNone) }
pub vty_float := fn(bytes : u64) -> VTy { VTy(cls = VCls.VcFloat, bytes = bytes, sg = Sgn.SgNone) }
## An aggregate value (a struct, an enum, an array, a `str`, a tuple): never an IR value (§3.2).
pub vty_agg := fn() -> VTy { VTy(cls = VCls.VcAgg, bytes = 0, sg = Sgn.SgNone) }
## Has sema named a kernel type here (not absent, not unknown, not a literal still awaiting context)?
vcls_known := fn(c : VCls) -> bool {
  match c { VcInt | VcBool | VcPtr | VcFloat | VcAgg => { true }; VcAbsent | VcUnknown | VcLit => { false } }
}
pub vty_known := fn(t : VTy) -> bool { c : VCls = t.cls; vcls_known(c) }
pub vty_is_int := fn(t : VTy) -> bool { c : VCls = t.cls; vcls_is_int(c) }
pub vty_is_lit := fn(t : VTy) -> bool { c : VCls = t.cls; vcls_is_lit(c) }
